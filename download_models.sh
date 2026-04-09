#!/bin/bash
set -e

echo "=============================================="
echo "    🚀 PuLID SDXL 一键模型自动寻址下载脚本    "
echo "=============================================="

# ================= 自动寻址探测 =================
TARGET_BASE=""
if [ -d "/runpod-volume/models" ]; then
    TARGET_BASE="/runpod-volume/models"
    echo "[寻址] 检测到 RunPod Network Volume 环境，将装载到硬盘卷"
elif [ -d "/workspace/ComfyUI/models" ]; then
    TARGET_BASE="/workspace/ComfyUI/models"
    echo "[寻址] 检测到 RunPod 本地容器环境"
elif [ -d "./models/checkpoints" ]; then
    TARGET_BASE="./models"
    echo "[寻址] 检测到本地 ComfyUI 根目录，将安装到 ./models"
elif [ -d "../models/checkpoints" ]; then
    TARGET_BASE="../models"
    echo "[寻址] 检测到脚本正位于 custom_nodes 目录"
else
    # 彻底找不到，就直接在脚本当前目录下新建一个独立文件夹
    TARGET_BASE="./ComfyUI_Models"
    echo "[寻址] ⚠️ 未检测到 ComfyUI 目录结构，将在当前位置创建一个独立库!"
    echo "[寻址] 路径: $(pwd)/ComfyUI_Models"
    mkdir -p "${TARGET_BASE}"
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

# ================= 开始下载核心七大模块 =================

echo -e "\n[模块 1/7] SDXL 基础写实大模型"
download_model "checkpoints" "SDXL_Photorealistic_Mix_nsfw.safetensors" "https://civitai.com/api/download/models/378684?token=${CIVITAI_TOKEN}"

echo -e "\n[模块 2/7] PuLID 面部一致性核心模型"
download_model "pulid" "ip-adapter_pulid_sdxl_fp16.safetensors" "https://huggingface.co/guozinan/PuLID/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors"

echo -e "\n[模块 3/7] ESRGAN 4x 超清放大算法"
download_model "upscale_models" "4x-UltraSharp.pth" "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth"

echo -e "\n[模块 4/7] NSFW 第一人称视角 LoRA"
download_model "loras" "NSFW_POV_AllInOne.safetensors" "https://civitai.com/api/download/models/609924?token=${CIVITAI_TOKEN}"

echo -e "\n[模块 5/7] 绝美面部优化 LoRA"
download_model "loras" "Beautiful_face_alpha1.0.safetensors" "https://civitai.com/api/download/models/518458?token=${CIVITAI_TOKEN}"

echo -e "\n[模块 6/7] ControlNet - 深度图控制 (Depth)"
download_model "controlnet" "controlnet-depth-sdxl-1.0.safetensors" "https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.fp16.safetensors"

echo -e "\n[模块 7/7] ControlNet - 骨骼控制 (OpenPose)"
download_model "controlnet" "controlnet-openpose-sdxl-1.0.safetensors" "https://huggingface.co/thibaud/controlnet-openpose-sdxl-1.0/resolve/main/OpenPoseXL2.safetensors"

echo "=============================================="
echo "🎉 自动寻址与核心模型部署闭环达成！"
echo "=============================================="
