# Docker Hub's PyTorch image mirrored for reliable China-region pulls.
FROM docker.m.daocloud.io/pytorch/pytorch:2.1.2-cuda12.1-cudnn8-runtime

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates libglib2.0-0 libgl1 libsm6 libxext6 libxrender1 libxcb1 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt
COPY docker/requirements-smoke.txt /tmp/requirements-smoke.txt
# Fine-tuning and export both use aiRockchip YOLOv5, pinned to d25a075 (ADR-0005 / ADR-0006).
# The fetch makes the pin robust once upstream moves past that commit; the checkout then fails
# loudly instead of silently building the wrong code.
RUN git clone --depth 1 https://github.com/airockchip/yolov5.git yolov5-airockchip && \
    git -C yolov5-airockchip fetch --depth 1 origin d25a075 && \
    git -C yolov5-airockchip checkout --detach d25a075 && \
    git -C yolov5-airockchip rev-parse HEAD && \
    pip install --no-cache-dir -r yolov5-airockchip/requirements.txt && \
    pip install --no-cache-dir "numpy<2" -r /tmp/requirements-smoke.txt

# Official v6.2 is kept only for the checkpoint-loading compatibility smoke
# (scripts/smoke_finetune_official.sh). Never use it to produce weights: it rebuilds the model
# from model.yaml and silently restores SiLU (ADR-0006).
RUN git clone --depth 1 --branch v6.2 https://github.com/ultralytics/yolov5.git yolov5 && \
    pip install --no-cache-dir -r yolov5/requirements.txt && \
    sed -i 's/np\.int/int/g' yolov5/utils/dataloaders.py

WORKDIR /workspace
COPY docker/requirements-smoke.txt /workspace/docker/requirements-smoke.txt
COPY scripts /workspace/scripts

CMD ["bash"]
