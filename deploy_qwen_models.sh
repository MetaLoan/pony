#!/bin/bash

# ==========================================
# Qwen Native Face Swap Research Environment setup
# ComfyUI root = /ComfyUI (OneClick template on RunPod)
# ==========================================

echo "Starting deployment of Qwen Native Face Swap dependencies..."

COMFY_DIR="/ComfyUI"
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
    wget -L -c "$url" -O "${out}.tmp" && mv "${out}.tmp" "$out"
}

# ---------------------------------------------------------------
# Qwen diffusion model (only missing file - text_encoder & vae
# are already pre-installed by the OneClick template)
# ---------------------------------------------------------------
echo ">>> Downloading Qwen Image Edit diffusion model (~17GB)..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors" \
  "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors"

# ---------------------------------------------------------------
# These two are already on the machine (pre-installed by template)
# but download them if for some reason they're missing
# ---------------------------------------------------------------
echo ">>> Checking text encoder..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
  "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors"

echo ">>> Checking VAE..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
  "$VAE_DIR/qwen_image_vae.safetensors"

echo ""
echo ">>> Final file sizes:"
ls -lh "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors" 2>/dev/null || echo "MISSING: diffusion model!"
ls -lh "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors" 2>/dev/null || echo "MISSING: text encoder!"
ls -lh "$VAE_DIR/qwen_image_vae.safetensors" 2>/dev/null || echo "MISSING: vae!"
echo ""
echo "Please restart ComfyUI to load the new models."
