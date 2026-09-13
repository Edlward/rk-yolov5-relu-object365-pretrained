# 中文入门指南：从原理到板端部署

面向第一次接触这套权重的开发者。读完本文你应该能回答三个问题：
**它是什么、我该怎么用、怎么把它跑到瑞芯微板子上。**

> 术语约定：第一次出现的名词都会给出通俗解释。命令、文件名、上游项目名保持原样不翻译。

---

## 目录

- [一、原理：它解决什么问题](#一原理它解决什么问题)
- [二、先拿到权重和工具链](#二先拿到权重和工具链)
- [三、全流程总览](#三全流程总览)
- [四、分步详解](#四分步详解)
- [五、怎么挑权重](#五怎么挑权重)
- [六、常见坑](#六常见坑)
- [七、本仓库的边界](#七本仓库的边界)

---

## 一、原理：它解决什么问题

### 1.1 三个角色

| 角色 | 通俗解释 |
| --- | --- |
| **YOLOv5** | 目标检测模型。输入一张图，输出若干框 + 每框的类别，例如"左上有个人""中间有辆车"。 |
| **预训练权重（`.pt`）** | 模型训练完的"大脑"。类比：让一个读过大学的人再学一门专业课很快，从零开始教小学生很慢。 |
| **RKNPU / RKNN** | 瑞芯微芯片（RK3568、RK3588 等）里的 AI 加速器。`.rknn` 是给这个加速器吃的模型格式。 |

主链路：**拿预训练权重 → 用你自己的数据微调 → 转成 `.rknn` → 烧到板子上跑。**

### 1.2 为什么要换成 ReLU

官方 YOLOv5 用的激活函数是 **SiLU**。激活函数决定一个信号要不要往后传。

- **SiLU** = `x * sigmoid(x)`，含指数运算。GPU 上无所谓，但**在国产 NPU 上很贵**：算子可能不被硬件直接支持，或者要拆成多个操作拼出来，推理吞吐明显下降。
- **ReLU** = `max(0, x)`，即"负数变 0，正数不变"。硬件上几乎免费，也容易和相邻层融合成一个算子。

所以想在瑞芯微 NPU 上跑得**快**，就要把 SiLU 换成 ReLU。

### 1.3 换激活函数的代价，以及这个仓库的补法

SiLU 的表达能力比 ReLU 强。直接把官方权重里的 SiLU 换成 ReLU，精度会掉——因为结构变了，大脑没重新学过。

本仓库的做法：用 ReLU 结构，在 **Objects365**（365 类）和 **COCO**（80 类）上**从头重新训练**，把精度补回来，再把这些权重作为你的微调起点。

这也是仓库名的由来：`rk-yolov5-relu-object365-pretrained`。

### 1.4 两条不能碰的红线

1. **Objects365 权重是 365 类检测头，不能当 80 类 COCO checkpoint 用。**
   拿它做自己的任务时，必须用你自己的 `data.yaml` 重新适配检测头（`train.py` 会自动重建）。
2. **ReLU 是模型自身的属性。**不要把本仓库的权重塞进别的 SiLU 模型里期待相同行为。
   用官方 `train.py` 加 `--weights` 直接加载即可，激活函数会被自动带回来，**不需要手动改模型结构**。

---

## 二、先拿到权重和工具链

本仓库的 Git 里**只有代码**（`.gitignore` 明确写了 Release 资产走 GitHub Releases，不进 Git），
权重和两个上游工具链需要单独获取。

### 2.1 权重（6 个 `.pt`）

从 Releases 下载，或用仓库自带的 Windows 脚本（下载 + SHA256 校验一步到位）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1

# 只要某几个规格
powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1 -Pattern "yolov5n_*"

# 只校验本地已有文件
powershell -ExecutionPolicy Bypass -File scripts/download_weights.ps1 -VerifyOnly
```

Linux / macOS 下按 README 的方式：

```bash
sha256sum -c SHA256SUMS
```

下载后的文件建议统一放在仓库根目录的 `weights/` 下。

### 2.2 两个上游工具链（版本必须用这两个）

```bash
mkdir -p external && cd external

# 微调用：官方 Ultralytics YOLOv5 v6.2
git clone --branch v6.2 --depth 1 https://github.com/ultralytics/yolov5.git yolov5-ultralytics-v6.2

# 导出用：aiRockchip YOLOv5，必须是 d25a075 这个 commit
git clone https://github.com/airockchip/yolov5.git yolov5-airockchip
git -C yolov5-airockchip checkout d25a075
```

> 为什么要钉死版本：这个组合已经通过了加载权重、训练、导出的冒烟测试。上游一更新，行为可能悄悄变化。

---

## 三、全流程总览

```
① 环境准备（Linux/Docker，或 Windows + Python 3.8 + torch 2.1.2）
        ↓
② 准备自己的数据（图片 + 标注 → YOLO 格式 + data.yaml）
        ↓
③ 微调：ReLU 预训练权重 + 你的数据  →  你的 best.pt
        ↓
④ 导出：aiRockchip export.py --rknpu  →  best.onnx + RK_anchors.txt
        ↓
⑤ 转换：RKNN-Toolkit2（x86 Ubuntu）  →  best.rknn
        ↓
⑥ 部署：板端 rknpu2 推理 + 后处理画框
        ↓
⑦ 精度验证：PyTorch vs ONNX vs RKNN 逐层对比
```

**第 ⑤ 步和第 ⑥ 步在不同的机器上**，这是最容易懵的地方：

| 步骤 | 在哪台机器 | 为什么 |
| --- | --- | --- |
| ③ 微调、④ 导出 | 你的 PC（Windows 可以） | 需要 PyTorch |
| ⑤ 转 `.rknn` | **x86 Ubuntu** | RKNN-Toolkit2 只能装在这里，Windows 和板子都装不了 |
| ⑥ 跑推理 | 瑞芯微板子 | `.rknn` 是给 NPU 用的 |

---

## 四、分步详解

### 第 ① 步：环境准备

#### 微调 + 导出（PC）

**方式 A：Docker（推荐，最不容易踩坑）**

```bash
cd rk-yolov5-relu-object365-pretrained
docker build -f docker/Dockerfile -t yolov5-relu .
docker run --gpus all -it -v $(pwd):/workspace yolov5-relu
```

Dockerfile 基线是 `pytorch/pytorch:2.1.2-cuda12.1-cudnn8-runtime`。

**方式 B：本地 Python 3.8**

```powershell
py -3.8 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -r external\yolov5-ultralytics-v6.2\requirements.txt
.\.venv\Scripts\python.exe -m pip install -r external\yolov5-airockchip\requirements.txt
.\.venv\Scripts\python.exe -m pip install "numpy<2" onnx==1.16.1 onnxsim==0.4.36
```

两个注意点：

- **`numpy<2` 别省。** YOLOv5 v6.2 里有 `np.int` 老写法，numpy 2.x 直接报错。
- **`np.int` 兼容修复。** 项目 Dockerfile 里有一句 `sed -i 's/np\.int/int/g' yolov5/utils/dataloaders.py`。
  如果你在本地克隆的 `external/yolov5-ultralytics-v6.2` 上跑、且 numpy >= 1.24，需要同样处理：

  ```powershell
  # 把 utils\dataloaders.py 里的 .astype(np.int) 全部替换为 .astype(int)（共 3 处）
  ```

- **不要用 Python 3.13/3.14**，torch 2.1.2 没有对应轮子。

#### 转 `.rknn`（x86 Ubuntu）

去 Rockchip 官方仓库获取 **rknn-toolkit2**，按它自带的 `requirements.txt` 安装
（一般要求 Python 3.8–3.11）。**Toolkit2 版本要和板子上 NPU runtime 版本匹配**，否则会报版本不匹配。

### 第 ② 步：准备数据

YOLO 格式目录：

```
mydata/
  images/
    train/  001.jpg 002.jpg ...
    val/    101.jpg ...
  labels/
    train/  001.txt 002.txt ...     # 与图片同名
    val/    101.txt ...
```

`001.txt` 每行一个目标：`类别序号 中心x 中心y 宽 高`，坐标**归一化到 0~1**。

再写一个数据集描述文件 `mydata.yaml`：

```yaml
path: D:/mydata
train: images/train
val: images/val
nc: 3                                        # 类别数
names: ['defect_a', 'defect_b', 'defect_c']  # 类别名
```

标注工具：X-AnyLabeling、labelImg 等，导出时选 YOLO 格式。

> 只想先跑通链路？不必马上标数据。可以从 COCO 抽几十张图造个迷你数据集，
> 仓库里有现成脚本参考：`scripts/create_coco_smoke_subset.py`。

### 第 ③ 步：微调

```bash
cd external/yolov5-ultralytics-v6.2

python train.py \
  --weights ../../weights/yolov5n_relu_objects365_best_epoch100.pt \
  --data /path/to/mydata.yaml \
  --epochs 100 --img 640 --batch 16 \
  --project ../../outputs --name my_run
```

Windows PowerShell 下换成反引号续行或写一行即可，注意参数里的路径用绝对路径最稳。

| 参数 | 说明 |
| --- | --- |
| `--weights` | 换成你要的 ReLU 权重。新手建议先上 `yolov5n`：小、快、好调 |
| `--data` | 指向你的 `mydata.yaml` |
| `--epochs` | 训练轮数。数据少（几百张）时 50~100 通常够 |
| `--img` | 输入分辨率。**后续导出和部署必须一致**，别随意改 |
| `--batch` | 显存不够就往下调：16 → 8 → 4 |

产物在 `outputs/my_run/weights/`，其中 **`best.pt` 就是你的模型**。

✅ 日志里应出现类似 `Transferred 349/349 items from ...`，说明预训练权重被正确加载。

### 第 ④ 步：导出 RKNN 友好 ONNX

```bash
python external/yolov5-airockchip/export.py \
  --rknpu \
  --weights /abs/path/to/best.pt \
  --include onnx --imgsz 640 --device cpu
```

产出：

- `best.onnx`
- **`RK_anchors.txt`** —— 别丢。瑞芯微版导出改变了框的解码布局，板端后处理需要它才能还原真实坐标。

仓库已封装好这一步并附带 `onnx.checker` 校验：

```bash
bash scripts/export_rknn_onnx.sh /abs/path/to/best.pt /abs/path/to/external/yolov5-airockchip /abs/path/to/outputs/rknn
```

> 参考已验证的产出体量：`yolov5n_relu_coco_best_epoch300.onnx` 为 7,501,403 字节，
> `RK_anchors.txt` 为 96 字节。

### 第 ⑤ 步：ONNX → RKNN

在 x86 Ubuntu 上，用 RKNN-Toolkit2。最省事的做法是拿官方 `rknn-toolkit2` 里
`examples/onnx/yolov5/` 的转换脚本，改成你的路径。核心逻辑：

```python
from rknn.api import RKNN

rknn = RKNN(verbose=True)
rknn.config(
    mean_values=[[0, 0, 0]],
    std_values=[[255, 255, 255]],     # 归一化要跟训练/导出一致
    target_platform='rk3588'          # 改成你的芯片型号
)
rknn.load_onnx(model='best.onnx')
rknn.build(do_quantization=True, dataset='calib.txt')   # INT8 量化
rknn.export_rknn('best.rknn')
```

`calib.txt` 是**量化校准集**，每行一张图片路径：

```
/path/to/mydata/images/val/101.jpg
/path/to/mydata/images/val/102.jpg
```

⚠️ **必须用真实场景图片，200~500 张。** 拿无关图凑数会让量化后精度掉得很惨——
这是端侧部署第一大坑。

### 第 ⑥ 步：板端部署

把 `best.rknn` 拷到板子上，用 Rockchip 的 **rknpu2** 运行时推理。

**不要从零自己写后处理。**直接使用官方 **`rknn_model_zoo`** 里的 YOLOv5 示例（有 C++ 与 Python 两版），
把三样东西对应好：

- `best.rknn` 模型路径
- `RK_anchors.txt`
- 类别名文件（`nc` 与 `names` 要和训练时一致）

### 第 ⑦ 步：精度验证

同一张图，三个模型逐层对比：

| 对比 | 期望 | 不一致说明什么 |
| --- | --- | --- |
| PyTorch `.pt` vs ONNX | 几乎完全一致 | 导出环节有问题 |
| ONNX vs `.rknn`（FP16/FP32） | 很接近 | 浮点精度差异 |
| `.rknn` FP32 vs INT8 | **差多少才是你真正关心的** | 量化损失，直接反映到 mAP |

INT8 掉点严重时的处理方向：换更有代表性的校准图；或对敏感层使用混合量化（保持 FP16）。

---

## 五、怎么挑权重

**档位（越大越准也越慢）**

| 档位 | 适合场景 |
| --- | --- |
| N (Nano) | 板子算力弱、要求实时。新手首选 |
| S (Small) | 速度与精度平衡 |
| M (Medium) | 精度优先 |
| L (Large) | 精度优先，但端侧可能跑不动 |

**数据集（决定起跑线）**

| 权重 | 检测头 | 说明 |
| --- | --- | --- |
| COCO | 80 类 | 日常物品（人、车、杯、狗…），通用起点与兼容性参考 |
| Objects365 | 365 类 | 类别更多、"见多识广"，通常**作为微调起点更好** |

完整的可用性矩阵与精度指标见 [README 的权重表](../README.md)。

---

## 六、常见坑

1. **拿错权重**：`*_coco_*` 是 80 类，`*_objects365_*` 是 365 类，别混。
2. **把 SiLU 的官方权重用于这个 ReLU 流程**——两者不通用。
3. **不微调直接转 `.rknn` 上板**——除非你确实就做 80 类通用检测，否则效果会很差。
4. **Python 版本过高**：3.13/3.14 装不了 torch 2.1.2，也装不了 RKNN-Toolkit2。
5. **numpy 2.x**：`np.int` 报错（见第 ① 步的兼容处理）。
6. **在 Windows 上装 RKNN-Toolkit2**：装不上，必须 x86 Ubuntu。
7. **输入尺寸 / 归一化前后不一致**：训练 640、导出 640、转换时的 `mean/std` 与训练一致，任何一环改了都会精度异常。
8. **丢掉 `RK_anchors.txt`**：板端解不出正确坐标。
9. **校准集不具代表性**：INT8 量化掉点的主因。
10. **Toolkit2 与板端 NPU 版本不匹配**：转出来的 `.rknn` 加载失败。

---

## 七、本仓库的边界

这一点请务必了解，它能解释"为什么仓库里没有 `.rknn` 文件"：

- **V1 只保证：**官方格式的 ReLU checkpoint + **已通过验证的 RKNN-friendly ONNX 导出路径**。
- **V1 不保证：**目标 SoC 的 `.rknn` 二进制、NPU 延迟、INT8 精度、板端性能。

原因：`.rknn` 的生成强依赖 **目标芯片型号、RKNN-Toolkit2 版本、量化方式、校准数据** 四件事，
不同人手里这四项都不同，提供一个"通用 `.rknn`"是误导。因此**最终的 `.rknn` 转换与板端验证是使用方自己的职责**。

相关设计记录：

- [docs/adr/0001-rknn-delivery-boundary.md](adr/0001-rknn-delivery-boundary.md)
- [docs/adr/0005-pin-the-v1-consumer-toolchain.md](adr/0005-pin-the-v1-consumer-toolchain.md)
- [docs/VERIFICATION.md](VERIFICATION.md)、[MODEL_CARD.md](../MODEL_CARD.md)

---

## 附：相关文件位置

| 路径 | 作用 |
| --- | --- |
| `weights/` | 下载后的预训练权重（本地目录，不进 Git） |
| `external/yolov5-ultralytics-v6.2/` | 官方 v6.2，用于微调 |
| `external/yolov5-airockchip/` | `d25a075`，用于 `--rknpu` 导出 ONNX |
| `scripts/download_weights.ps1` | Windows 权重下载 + SHA256 校验 |
| `scripts/export_rknn_onnx.sh` | ONNX 导出 + onnx checker 校验 |
| `scripts/smoke_finetune_official.sh` | 官方微调冒烟测试 |
| `scripts/create_coco_smoke_subset.py` | 从 COCO 造迷你数据集 |
| `tools/convert_mmyolo_yolov5_to_ultralytics.py` | 本 Release 使用的严格转换器（溯源用） |
| `release/SHA256SUMS`、`release/models.json` | 下载校验与机器可读元数据 |
