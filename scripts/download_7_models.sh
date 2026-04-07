#!/bin/bash
# ============================================================
# 下载工作流所需模型 (7个目标文件)
# 包含 Qwen-Lightning, Flux文本编码器/VAE, 放大模型和 NSFW LoRAs
# ============================================================

# 目录定义
DIR_CHECKPOINTS="/ComfyUI/models/checkpoints"
DIR_LORAS="/ComfyUI/models/loras"
DIR_UPSCALE="/ComfyUI/models/upscale_models"
DIR_CLIP="/ComfyUI/models/clip"
DIR_VAE="/ComfyUI/models/vae"

# 创建所需的目录
mkdir -p "$DIR_CHECKPOINTS" "$DIR_LORAS" "$DIR_UPSCALE" "$DIR_CLIP" "$DIR_VAE"

echo "=================================================="
echo " 开始批量下载模型..."
echo "=================================================="

# 统一下载函数
download_file() {
    local url="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [ -f "$dest" ]; then
        echo "[跳过] $name 已存在。"
        return 0
    fi

    if [ -z "$url" ]; then
        echo "⚠️ [注意] $name 无法自动下载，请从 Civitai 手动下载并放入 $(dirname "$dest") 目录。"
        return 0
    fi

    echo "[下载中] $name ..."
    curl -L -C - --retry 3 --progress-bar -o "$dest" "$url"
}

# ----------------------------------------------------
# 1. 文本编码器 & VAE (用于 FLUX 结构)
# ----------------------------------------------------
# clip_l.safetensors
download_file "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" "$DIR_CLIP/clip_l.safetensors"

# t5xxl_fp16.safetensors
download_file "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" "$DIR_CLIP/t5xxl_fp16.safetensors"

# ae.safetensors (Flux VAE)
download_file "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" "$DIR_VAE/ae.safetensors"

# ----------------------------------------------------
# 2. Qwen Edit 2511 Lightning LoRA
# ----------------------------------------------------
# Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors
# 官方文件统一放在 loras 文件夹内供加载
mkdir -p "$DIR_LORAS/Qwen Edit 2511"
download_file "https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors?download=true" "$DIR_LORAS/Qwen Edit 2511/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"

# ----------------------------------------------------
# 3. 图像放大模型 Upscaler
# ----------------------------------------------------
# 4xNomos8kDAT.pth
download_file "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4xNomos8kDAT.pth" "$DIR_UPSCALE/4xNomos8kDAT.pth"

# ----------------------------------------------------
# 4. NSFW LoRAs (Civitai 模型)
# ----------------------------------------------------
# 注：Civitai 的 NSFW 模型需要 API 验证，通常无法直接公开链接 curl，需提供真实直链
# fuxCapacityNSFWPornFlux_50.safetensors
download_file "" "$DIR_LORAS/fuxCapacityNSFWPornFlux_50.safetensors"

# SEXGOD_FemaleNudity_QwenEdit_2511_v1.safetensors
mkdir -p "$DIR_LORAS/SexGod"
download_file "" "$DIR_LORAS/SexGod/SEXGOD_FemaleNudity_QwenEdit_2511_v1.safetensors"

echo "=================================================="
echo " 基础模型下载完成！"
echo " 提示：包含 'SexGod' 和 'fuxCapacity' 的 NSFW LoRA 需要你登录 Civitai 账户获取直链手动下载，或通过包含 API_KEY 的格式下载。"
echo "=================================================="
