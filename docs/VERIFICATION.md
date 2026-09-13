# Verification Record

Date: 2026-08-28

## Official YOLOv5 Fine-tuning

Environment: clean Docker image based on `pytorch/pytorch:2.1.2-cuda12.1-cudnn8-runtime`,
official Ultralytics YOLOv5 v6.2, CPU execution.

Command shape:

```bash
bash scripts/smoke_finetune_official.sh \
  /weights/yolov5n_relu_coco_best_epoch300.pt
```

The test used four COCO train images, two COCO validation images, one epoch, image size
64, batch size 2, and zero data-loader workers. It completed successfully and reported:

```text
Transferred 349/349 items from /weights/yolov5n_relu_coco_best_epoch300.pt
1 epochs completed
```

The run wrote official YOLOv5 `last.pt` and `best.pt`, then performed the normal final
validation pass. This confirms that the release checkpoint loads as a pretrained weight
in the upstream training script.

## Rockchip ONNX Export

Environment: the same image, Rockchip YOLOv5 fork commit `d25a075`.

```bash
bash scripts/export_rknn_onnx.sh \
  /weights/yolov5n_relu_coco_best_epoch300.pt \
  /opt/yolov5-airockchip /workspace/outputs/rknn
```

The command completed successfully and generated:

- `yolov5n_relu_coco_best_epoch300.onnx` (7,501,403 bytes)
- `RK_anchors.txt` (96 bytes)

`onnx.checker.check_model` passed for the exported ONNX graph. This proves compatibility
with the Rockchip-friendly ONNX path. Producing a target `.rknn` still requires the
target-SoC RKNN Toolkit2 environment and, where appropriate, calibration data.

## Activation preservation

Date: 2026-09-13

Fine-tuning must preserve the ReLU activation. `train.py` rebuilds the network from
`ckpt['model'].yaml`, so the toolchain has to honour the `activation` field for the rebuild to
keep ReLU.

Measured on `yolov5n_relu_coco_best_epoch300.pt`, fine-tuned to a two-class dataset
(4 train / 2 val images, 320 px, 1 epoch, CPU) and then exported with `--rknpu --imgsz 640`:

| pipeline | fine-tuned `best.pt` | exported ONNX |
| --- | --- | --- |
| Ultralytics YOLOv5 v6.2 | ReLU 0, SiLU 57 | `Relu` 0, `Sigmoid` 60, 210 nodes |
| aiRockchip YOLOv5 `d25a075` | ReLU 57, SiLU 0 | `Relu` 57, `Sigmoid` 3, 153 nodes |
| Release checkpoint, no fine-tuning | ReLU 57 | `Relu` 57, `Sigmoid` 3, 153 nodes |

The aiRockchip row matches the un-fine-tuned export, which is the required outcome. The v6.2 row
does not: v6.2 `models/common.py` hard-codes `nn.SiLU()`, `models/yolo.py:parse_model` never
reads an `activation` field, and the checkpoint's `model.yaml` has no `activation` key. Activation
layers carry no parameters, so the v6.2 run still transfers the full state dict and completes
without error — the regression is silent. See
[ADR-0006](adr/0006-fine-tune-with-airockchip-yolov5.md).

Re-exporting the Release checkpoint reproduced the asset measured above byte for byte:
7,501,403 bytes, `onnx.checker` passed, outputs `output0` plus two auxiliary tensors.

## Environment notes (Windows, CPU)

- Python 3.8.10, `torch 2.1.2+cpu`, `torchvision 0.16.2+cpu`, `numpy 1.24.4`, `onnx 1.16.1`,
  `onnxsim 0.4.36`.
- `RK_anchors.txt` is written to the current working directory, so the export must be run from the
  output directory, as `scripts/export_rknn_onnx.sh` does.
- A placeholder file at `%APPDATA%\Ultralytics\Arial.ttf` avoids a network fetch when YOLOv5
  prepares its plotting font.
