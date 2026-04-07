#!/bin/bash
# ============================================================
# 下载工作流所需模型 (7个目标文件)
# 包含 Qwen-Lightning, Flux文本编码器/VAE, 放大模型和 NSFW LoRAs
# ============================================================

# 你的 Civitai API Key
CIVITAI_TOKEN="593985208bda960143c74c0ba2b2b4e5"

# 目录定义
DIR_CHECKPOINTS="/ComfyUI/models/checkpoints"
DIR_LORAS="/ComfyUI/models/loras"
DIR_UPSCALE="/ComfyUI/models/upscale_models"
DIR_CLIP="/ComfyUI/models/clip"
DIR_VAE="/ComfyUI/models/vae"

# 创建所需的目录
mkdir -p "$DIR_CHECKPOINTS" "$DIR_LORAS" "$DIR_UPSCALE" "$DIR_CLIP" "$DIR_VAE"
mkdir -p "$DIR_LORAS/Qwen Edit 2511"
mkdir -p "$DIR_LORAS/SexGod"

echo "=================================================="
echo " 开始批量下载模型..."
echo "=================================================="

# 普通无鉴权下载
download_file() {
    local url="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [ -f "$dest" ]; then
        echo "[跳过] $name 已存在。"
        return 0
    fi

    echo "[下载中] $name ..."
    curl -L -C - --retry 3 --progress-bar -o "$dest" "$url"
}

# 带有 Civitai 鉴权的下载函数
download_civitai() {
    local model_id="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [ -f "$dest" ]; then
        echo "[跳过] Civitai 模型 $name 已存在。"
        return 0
    fi
    
    if [ "$model_id" == "REPLACE_ME" ]; then
        echo "⚠️  [注意] Civitai 模型: $name"
        echo "   -> 由于未获取到确切的 Model ID，无法自动下载该文件。"
        echo "   -> 解决方法：请在脚本中替换 'REPLACE_ME' 为该模型在 Civitai 的 Version ID，或手动下载。 "
        return 0
    fi

    echo "[下载中 / Civitai 鉴权] $name ..."
    curl -L -C - --retry 3 --progress-bar \
         -H "Authorization: Bearer $CIVITAI_TOKEN" \
         -H "Content-Type: application/json" \
         -o "$dest" \
         "https://civitai.com/api/download/models/$model_id?token=$CIVITAI_TOKEN"
}

# ----------------------------------------------------
# 1. 文本编码器 & VAE (用于 FLUX 结构)
# ----------------------------------------------------
download_file "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" "$DIR_CLIP/clip_l.safetensors"
download_file "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" "$DIR_CLIP/t5xxl_fp16.safetensors"
download_file "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" "$DIR_VAE/ae.safetensors"

# ----------------------------------------------------
# 2. Qwen Edit 2511 Lightning LoRA
# ----------------------------------------------------
download_file "https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors?download=true" "$DIR_LORAS/Qwen Edit 2511/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"

# ----------------------------------------------------
# 3. 图像放大模型 Upscaler
# ----------------------------------------------------
download_file "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4xNomos8kDAT.pth" "$DIR_UPSCALE/4xNomos8kDAT.pth"

# ----------------------------------------------------
# 4. NSFW LoRAs (需要 Civitai 模型 版本 ID)
# ----------------------------------------------------
# 例子: 如果 Version ID 是 123456，把 REPLACE_ME 改成 123456
download_civitai "REPLACE_ME" "$DIR_LORAS/fuxCapacityNSFWPornFlux_50.safetensors"

# 如果你使用的是之前提过的 Qwen4Play-2512-v1，你可以把 REPLACE_ME 替换为 2004155（这是那个模型的ID）
# 这里保留你给的 SEXGOD 文件名：
download_civitai "REPLACE_ME" "$DIR_LORAS/SexGod/SEXGOD_FemaleNudity_QwenEdit_2511_v1.safetensors"

echo "=================================================="
echo " 批量下载流程结束！"
echo "=================================================="
