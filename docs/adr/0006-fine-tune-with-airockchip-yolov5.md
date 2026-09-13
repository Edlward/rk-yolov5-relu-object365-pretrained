# Fine-tune with aiRockchip YOLOv5

Supersedes [ADR-0002](0002-official-yolov5-is-the-consumer-interface.md) and the fine-tuning
half of [ADR-0005](0005-pin-the-v1-consumer-toolchain.md).

## Context

V1 originally documented official Ultralytics YOLOv5 v6.2 `train.py` as the fine-tuning entry
point. That path silently discards the ReLU activation this project exists to provide:

- `train.py` rebuilds the network from the checkpoint's `model.yaml` instead of reusing the
  checkpointed module (`model = Model(cfg or ckpt['model'].yaml, ...)`).
- In v6.2 `models/common.py` hard-codes `nn.SiLU()` as the `Conv` activation, and
  `models/yolo.py:parse_model` never reads an `activation` field. The `Conv.default_act` lookup
  only arrived in a later upstream release.
- The Release checkpoints carry `activation: 'ReLU'` at checkpoint top level, but their
  `model.yaml` has no `activation` key, so a rebuild could not restore ReLU even if it were read.

Activation layers hold no parameters, so the state dict still transfers in full and the run
reports success. Measured on the COCO N checkpoint, fine-tuned to a two-class dataset and then
exported with `--rknpu`:

| pipeline | fine-tuned `best.pt` | exported ONNX |
| --- | --- | --- |
| Ultralytics v6.2 | ReLU 0, SiLU 57 | Relu 0, Sigmoid 60, 210 nodes |
| aiRockchip `d25a075` | ReLU 57, SiLU 0 | Relu 57, Sigmoid 3, 153 nodes |
| Release checkpoint, no fine-tuning | ReLU 57 | Relu 57, Sigmoid 3, 153 nodes |

The third row is the required outcome: a fine-tuned model must export the same operator profile
as the Release checkpoint. Only the aiRockchip pipeline satisfies it. SiLU costs roughly 57 extra
graph nodes, which is exactly the NPU-side cost this project sets out to remove.

## Decision

Fine-tuning and RKNN-friendly ONNX export both use aiRockchip YOLOv5 `d25a075`. That fork's
`Conv` already defaults to `nn.ReLU()` and its `parse_model` honours `yaml['activation']`, so
rebuilding the model preserves the activation. It is a required dependency for export anyway, so
this decision removes a toolchain rather than adding one.

## Consequences

- mmdet/MMYOLO stays out of the getting-started path; only the training records reference it.
- `scripts/smoke_finetune_official.sh` is kept as a v6.2 checkpoint-loading compatibility record
  only. It does **not** assert activation preservation, and v6.2 must not be used to produce
  deployable weights.
- Any change of fine-tuning toolchain must re-run the activation check recorded in
  [docs/VERIFICATION.md](../VERIFICATION.md).
