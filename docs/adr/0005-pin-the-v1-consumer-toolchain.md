# Pin the V1 consumer toolchain

> Partially superseded by [ADR-0006](0006-fine-tune-with-airockchip-yolov5.md): fine-tuning and
> export both use aiRockchip YOLOv5 `d25a075`. Pinning the commit remains in force.

V1 supports official YOLOv5 v6.2 for fine-tuning and aiRockchip YOLOv5 `d25a075` for
RKNN-friendly ONNX export. This exact pair has passed checkpoint loading, training, and
export smoke tests; pinning it prevents silent behavior changes from upstream releases.
