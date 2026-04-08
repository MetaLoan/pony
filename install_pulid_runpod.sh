#!/bin/bash

echo "=========================================="
echo "    ComfyUI PuLID Environment Auto-Fix    "
echo "=========================================="

# 1. 自动寻找 ComfyUI 根目录
echo "[1/4] 正在寻找 ComfyUI 根目录..."
COMFYUI_PATH=""

# 常见 Runpod 路径优先查找
if [ -d "/workspace/ComfyUI" ]; then
    COMFYUI_PATH="/workspace/ComfyUI"
elif [ -d "/home/root/workspace/ComfyUI" ]; then
    COMFYUI_PATH="/home/root/workspace/ComfyUI"
else
    # 扩大搜索范围
    echo "未在默认路径找到，正在全盘扫描 (可能需要几分钟)..."
    COMFYUI_PATH=$(find / -type d -name "ComfyUI" -print -quit 2>/dev/null)
fi

if [ -z "$COMFYUI_PATH" ]; then
    echo "❌ 错误: 找不到 ComfyUI 目录。请在 ComfyUI 根目录下手动运行此脚本。"
    exit 1
fi

echo "✅ 找到 ComfyUI 根目录: $COMFYUI_PATH"

# 2. 安装自定义节点包
echo "[2/4] 正在克隆缺失的自定义节点包..."
cd "$COMFYUI_PATH/custom_nodes" || exit 1

# 安装 PuLID 主包
if [ ! -d "PuLID_ComfyUI" ]; then
    git clone https://github.com/cubiq/PuLID_ComfyUI.git
else
    echo "PuLID_ComfyUI 已存在，跳过克隆。"
fi

# 安装 人脸分析包
if [ ! -d "ComfyUI_FaceAnalysis" ]; then
    git clone https://github.com/cubiq/ComfyUI_FaceAnalysis.git
else
    echo "ComfyUI_FaceAnalysis 已存在，跳过克隆。"
fi

# 安装 ControlNet 预处理器包
if [ ! -d "comfyui_controlnet_aux" ]; then
    git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git
else
    echo "comfyui_controlnet_aux 已存在，跳过克隆。"
fi

# 3. 安装 Python 依赖 (针对 RunPod Linux GPU 环境)
echo "[3/4] 正在安装 Python 依赖..."
# Runpod 上通常是全局或虚拟环境，直接用 pip
pip install -q insightface onnxruntime-gpu huggingface-hub

# 安装 controlnet_aux 依赖
if [ -f "comfyui_controlnet_aux/requirements.txt" ]; then
    pip install -q -r comfyui_controlnet_aux/requirements.txt
fi

# 4. 下载模型到正确的位置
echo "[4/4] 正在下载必要的模型文件 (如果已存在将跳过)..."

mkdir -p "$COMFYUI_PATH/models/pulid"
mkdir -p "$COMFYUI_PATH/models/clip"

# 下载 PuLID SDXL 原型
PULID_MODEL="$COMFYUI_PATH/models/pulid/ip-adapter_pulid_sdxl_fp16.safetensors"
if [ ! -f "$PULID_MODEL" ]; then
    echo "下载 PuLID 模型..."
    python3 -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='ToTheBeginning/PuLID', filename='ip-adapter_pulid_sdxl_fp16.safetensors', local_dir='${COMFYUI_PATH}/models/pulid')"
fi

# 下载 EVA-CLIP
EVA_CLIP="$COMFYUI_PATH/models/clip/EVA02_CLIP_L_336_psz14_s6B.pt"
if [ ! -f "$EVA_CLIP" ]; then
    echo "下载 EVA-CLIP..."
    python3 -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='ToTheBeginning/PuLID', filename='EVA02_CLIP_L_336_psz14_s6B.pt', local_dir='${COMFYUI_PATH}/models/clip')"
fi

# Insightface 模型准备 - 让系统在第一次运行时自动下载 buffalo_l 到 ~/.insightface
# 但为了保险，预先下载:
INSIGHTFACE_DIR="$HOME/.insightface/models/buffalo_l"
mkdir -p "$HOME/.insightface/models"
if [ ! -d "$INSIGHTFACE_DIR" ]; then
    echo "下载 InsightFace 基础模型 buffalo_l ..."
    # insightface 经常卡下载，通过 HF 镜像或直接 wget 下载.zip 解压
    wget -qO buffalo_l.zip https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip
    python3 -m zipfile -e buffalo_l.zip "$INSIGHTFACE_DIR"
    rm buffalo_l.zip
fi

echo "=========================================="
echo "✅ 所有环境配置完成！"
echo "👉 请重启你的 ComfyUI / RunPod Pod 即可生效！"
echo "=========================================="
