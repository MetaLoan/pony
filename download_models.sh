#!/bin/bash
set -e

echo "=============================================="
echo "    🚀 PuLID SDXL 一键模型自动寻址下载脚本    "
echo "=============================================="

# ================= 自动寻址探测 =================
TARGET_BASE=""

echo "[雷达] 开始深度扫描宿主机文件树，定位 ComfyUI..."

if [ -d "/runpod-volume/models" ]; then
    TARGET_BASE="/runpod-volume/models"
    echo "[寻址] 检测到挂载的网络硬盘卷: ${TARGET_BASE}"
else
    # 在 /workspace 目录下进行深度寻址找存不存在 models/checkpoints
    # 用 head -n 1 找到第一个看起来像 ComfyUI 根 models 的目录
    if [ -d "/workspace" ]; then
        FOUND_MODELS=$(find /workspace -type d -name "checkpoints" -path "*/models/checkpoints" -not -path "*/.Trash-*" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_MODELS" ]; then
            TARGET_BASE=$(dirname "$FOUND_MODELS")
            echo "[寻址] 深度探测成功！找到目标目录: ${TARGET_BASE}"
        fi
    fi
    
    # 彻底没找到的话：如果位于本地 ./models
    if [ -z "$TARGET_BASE" ]; then
        if [ -d "./models/checkpoints" ]; then
            TARGET_BASE="./models"
            echo "[寻址] 探测为 ComfyUI 根目录启动: ./models"
        elif [ -d "../models/checkpoints" ]; then
            TARGET_BASE="../models"
            echo "[寻址] 探测为 custom_nodes 目录启动: ../models"
        elif [ -d "/workspace" ]; then
            # 如果是白板新机器，连ComfyUI还没装
            TARGET_BASE="/workspace/ComfyUI/models"
            echo "[寻址] 全新 /workspace 白板环境，缺省指向: ${TARGET_BASE}"
            mkdir -p "$TARGET_BASE"
        else
            TARGET_BASE="./ComfyUI_Models"
            echo "[寻址] ⚠️ 完全未知环境，强制生成基准目录: $(pwd)/ComfyUI_Models"
            mkdir -p "$TARGET_BASE"
        fi
    fi
fi

echo "=============================================="
echo "最终存放路径 (Base Path): ${TARGET_BASE}"
echo "=============================================="

# Civitai 访问令牌
CIVITAI_TOKEN="fd0f3beec0b56c19715e0161cca7505c"

download_model() {
    local folder="$1"
    local file="$2"
    local url="$3"
    
    local target_path="${TARGET_BASE}/${folder}/${file}"
    mkdir -p "${TARGET_BASE}/${folder}"
    
    # 检查存不存在，且大于 10MB 才认为有效
    if [ -f "$target_path" ]; then
        local size=$(wc -c < "$target_path" 2>/dev/null || stat -f%z "$target_path" 2>/dev/null)
        if [ "$size" -gt 10485760 ]; then
            echo "✅ 跳过: ${folder}/${file} 已就绪。"
            return
        else
            echo "⚠️ 检测到 ${folder}/${file} 文件体积异常(0KB或破损)，即将重新下载..."
            rm -f "$target_path"
        fi
    fi
    
    echo "⬇️ 正在下载: ${folder}/${file} ..."
    
    # 优先尝试 aria2c，最高 16 线程加速
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -x 16 -s 16 --auto-file-renaming=false "$url" -d "${TARGET_BASE}/${folder}" -o "$file"
    else
        # 降级使用支持全平台重定向的 curl -L
        echo "   [!] 未检测到 aria2c，降级使用内建 curl 下载..."
        curl -L "$url" -o "$target_path"
    fi
}

# ================= 开始下载大模型与全部周边依赖 =================

echo -e "\n[模块 1] 核心基础大模型"
download_model "checkpoints" "RealVisXL_V4.safetensors" "https://huggingface.co/SG161222/RealVisXL_V4.0/resolve/main/RealVisXL_V4.0.safetensors"

echo -e "\n[模块 2] PuLID 面部特征提取"
download_model "pulid" "ip-adapter_pulid_sdxl_fp16.safetensors" "https://huggingface.co/guozinan/PuLID/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors"

echo -e "\n[模块 3] EVA-CLIP Vision 模型 (PuLID必需)"
download_model "clip_vision" "EVA02_CLIP_L_336_psz14_s6B.pt" "https://huggingface.co/QuanSun/EVA-CLIP/resolve/main/EVA02_CLIP_L_336_psz14_s6B.pt"

echo -e "\n[模块 4] Insightface (AntelopeV2, PuLID和FaceID必需)"
download_model "insightface/models/antelopev2" "1k3d68.onnx" "https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/1k3d68.onnx"
download_model "insightface/models/antelopev2" "2d106det.onnx" "https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/2d106det.onnx"
download_model "insightface/models/antelopev2" "genderage.onnx" "https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/genderage.onnx"
download_model "insightface/models/antelopev2" "glintr100.onnx" "https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/glintr100.onnx"
download_model "insightface/models/antelopev2" "scrfd_10g_bnkps.onnx" "https://huggingface.co/DIAMONIK7777/antelopev2/resolve/main/scrfd_10g_bnkps.onnx"

echo -e "\n[模块 5] ControlNet 大模型"
download_model "controlnet" "controlnet-depth-sdxl-1.0.safetensors" "https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.fp16.safetensors"
download_model "controlnet" "controlnet-openpose-sdxl-1.0.safetensors" "https://huggingface.co/thibaud/controlnet-openpose-sdxl-1.0/resolve/main/OpenPoseXL2.safetensors"

echo -e "\n[模块 6] ControlNet-Aux 预处理器底层文件"
# 强制放到上一级的 custom_nodes 里，或者放 models 如果插件做了动态链接
# 但为了兼容性，如果能在 ../custom_nodes/comfyui_controlnet_aux 找到，就放那里
AUX_PATH="../custom_nodes/comfyui_controlnet_aux/ckpts"
if [ ! -d "$AUX_PATH" ]; then
    AUX_PATH="checkpoints/controlnet_aux" # 防呆备胎路径
fi
download_model "${AUX_PATH}/lllyasviel/Annotators" "depth_anything_vitl14.pth" "https://huggingface.co/lllyasviel/Annotators/resolve/main/depth_anything_vitl14.pth"
download_model "${AUX_PATH}/yzd-v/DWPose" "yolox_l.onnx" "https://huggingface.co/yzd-v/DWPose/resolve/main/yolox_l.onnx"
download_model "${AUX_PATH}/yzd-v/DWPose" "dw-ll_ucoco_384.onnx" "https://huggingface.co/yzd-v/DWPose/resolve/main/dw-ll_ucoco_384.onnx"

echo -e "\n[模块 7] ESRGAN 超清算法"
download_model "upscale_models" "4x-UltraSharp.pth" "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth"

echo -e "\n[模块 8] 工作流依赖 LoRA"
download_model "loras" "NSFW_XL.safetensors" "https://civitai.com/api/download/models/160240?token=${CIVITAI_TOKEN}"

echo "=============================================="
echo "🎉 真·工作流全套模型与组件下载完毕！"
echo "=============================================="
