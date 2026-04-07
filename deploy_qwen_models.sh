#!/bin/bash

# ==========================================
# Qwen Native Face Swap Research Environment setup
# ==========================================

echo "Starting deployment of Qwen Native Face Swap dependencies..."

# ComfyUI root — auto-detect between two known locations
if [ -d "/ComfyUI/custom_nodes" ]; then
    COMFY_DIR="/ComfyUI"
elif [ -d "/workspace/runpod-slim/ComfyUI/custom_nodes" ]; then
    COMFY_DIR="/workspace/runpod-slim/ComfyUI"
else
    COMFY_DIR="${COMFY_DIR:-/ComfyUI}"
fi
echo ">>> ComfyUI root detected: $COMFY_DIR"

# ---------------------------------------------------------------
# Step 1: Install / update ComfyUI-QwenVL-Mod (already present on
#         the OneClick template, but keep it fresh)
# ---------------------------------------------------------------
echo ""
echo ">>> Step 1: Checking ComfyUI-QwenVL-Mod custom node..."
QWEN_NODE_DIR="$COMFY_DIR/custom_nodes/ComfyUI-QwenVL-Mod"
if [ -d "$QWEN_NODE_DIR" ]; then
    echo "ComfyUI-QwenVL-Mod already installed, pulling latest..."
    cd "$QWEN_NODE_DIR" && GIT_CONFIG_GLOBAL=/dev/null git pull && cd -
else
    echo "Not found — cloning ComfyUI-QwenVL-Mod..."
    cd "$COMFY_DIR/custom_nodes" || exit 1
    GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/huchukato/ComfyUI-QwenVL-Mod.git
    cd ComfyUI-QwenVL-Mod && pip install -r requirements.txt && cd -
fi

# ---------------------------------------------------------------
# Step 2: Download Qwen2.5-VL-7B model files
# The QwenVL-Mod node expects:
#   diffusion_models  -> qwen_image_edit_2511_bf16.safetensors
#   text_encoders     -> qwen_2.5_vl_7b_fp8_scaled.safetensors
#   vae               -> qwen_image_vae.safetensors
# ---------------------------------------------------------------
echo ""
echo ">>> Step 2: Downloading Qwen model weight files..."

DIFF_DIR="$COMFY_DIR/models/diffusion_models"
TEXT_DIR="$COMFY_DIR/models/text_encoders"
VAE_DIR="$COMFY_DIR/models/vae"

mkdir -p "$DIFF_DIR" "$TEXT_DIR" "$VAE_DIR"

download() {
    local url="$1"
    local out="$2"
    if [ -s "$out" ]; then
        echo "Already exists, skipping: $out"
        return 0
    fi
    echo "Downloading: $out"
    wget -c "$url" -O "${out}.tmp" && mv "${out}.tmp" "$out"
}

# Qwen Image Edit UNet (diffusion model)
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors" \
  "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors"

# Qwen 2.5 VL 7B Text Encoder (fp8)
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
  "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors"

# Qwen Image VAE
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
  "$VAE_DIR/qwen_image_vae.safetensors"

echo ""
echo ">>> Deployment completed! File sizes:"
ls -lh "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors" 2>/dev/null
ls -lh "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors" 2>/dev/null
ls -lh "$VAE_DIR/qwen_image_vae.safetensors" 2>/dev/null
echo ""
echo "Please restart ComfyUI to load the new models."
