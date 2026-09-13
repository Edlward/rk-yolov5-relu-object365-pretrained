#!/usr/bin/env bash
#
# Compatibility smoke test: proves a Release checkpoint loads in the official v6.2 training
# script and completes an epoch.
#
# This is NOT the supported fine-tuning path. v6.2 rebuilds the model from model.yaml and
# silently restores SiLU, so it must not be used to produce deployable weights. Fine-tune with
# aiRockchip YOLOv5 d25a075 instead (ADR-0006), and re-check the activation count afterwards as
# recorded in docs/VERIFICATION.md.
set -euo pipefail

weights=${1:?usage: smoke_finetune_official.sh /weights/model.pt}
workspace=${WORKSPACE:-/workspace}
subset_dir="$workspace/outputs/coco-smoke"

test -f "$weights"
test -d /data/coco/images/train2017
test -d /data/coco/images/val2017

# The upstream dataset checker downloads this plotting-only font. The smoke test is
# offline and uses --noplots, so a sentinel avoids a needless network dependency.
mkdir -p /root/.config/Ultralytics
: > /root/.config/Ultralytics/Arial.ttf

python "$workspace/scripts/create_coco_smoke_subset.py" \
  --coco /data/coco --output "$subset_dir" --train-count 4 --val-count 2

cd /opt/yolov5
python train.py \
  --weights "$weights" \
  --data "$subset_dir/coco-smoke.yaml" \
  --epochs 1 --batch-size 2 --imgsz 64 --workers 0 --device cpu --noval --noplots \
  --project "$workspace/outputs/official-finetune-smoke" --name "$(basename "${weights%.pt}")" \
  --exist-ok
