# Official YOLOv5 is the consumer interface

> Superseded by [ADR-0006](0006-fine-tune-with-airockchip-yolov5.md): v6.2 rebuilds the model
> from `model.yaml` and silently restores SiLU, so the fine-tuning interface is now aiRockchip
> YOLOv5.

V1 documents official Ultralytics YOLOv5 v6.2 `train.py` as the supported fine-tuning
entry point. MMYOLO produced the source checkpoints and remains available through
training records, but exposing it as a second user workflow would add dependencies and
make the first release less approachable without improving downstream RKNN deployment.
