#!/bin/bash
set -euo pipefail

# ==========================================
# Qwen Image Edit Model Deployment Script
# ComfyUI root = /ComfyUI (OneClick RunPod template)
#
# Two separate Comfy-Org repos:
#   diffusion model -> Comfy-Org/Qwen-Image-Edit_ComfyUI  (with -Edit)
#   text encoder    -> Comfy-Org/Qwen-Image_ComfyUI       (no -Edit)
#   vae             -> Comfy-Org/Qwen-Image_ComfyUI       (no -Edit)
# ==========================================

COMFY_DIR="/ComfyUI"
DIFF_DIR="$COMFY_DIR/models/diffusion_models"
TEXT_DIR="$COMFY_DIR/models/text_encoders"
VAE_DIR="$COMFY_DIR/models/vae"

mkdir -p "$DIFF_DIR" "$TEXT_DIR" "$VAE_DIR"

download() {
    local url="$1"
    local out="$2"
    if [ -s "$out" ]; then
        echo "Already exists, skipping: $(basename "$out")"
        return 0
    fi
    echo "Downloading: $out"
    curl -L -C - "$url" -o "${out}.tmp" && mv "${out}.tmp" "$out"
    echo "Done: $(ls -lh "$out" | awk '{print $5, $9}')"
}

echo ">>> [1/3] Diffusion model (from Comfy-Org/Qwen-Image-Edit_ComfyUI, ~17GB)..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors" \
  "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors"

echo ">>> [2/3] Text encoder (from Comfy-Org/Qwen-Image_ComfyUI, ~8.8GB)..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
  "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors"

echo ">>> [3/3] VAE (from Comfy-Org/Qwen-Image_ComfyUI, ~243MB)..."
download \
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors" \
  "$VAE_DIR/qwen_image_vae.safetensors"

echo ""
echo "=== Final check ==="
ls -lh "$DIFF_DIR/qwen_image_edit_2511_bf16.safetensors"   2>/dev/null || echo "MISSING: diffusion model!"
ls -lh "$TEXT_DIR/qwen_2.5_vl_7b_fp8_scaled.safetensors"   2>/dev/null || echo "MISSING: text encoder!"
ls -lh "$VAE_DIR/qwen_image_vae.safetensors"                2>/dev/null || echo "MISSING: vae!"
echo ""
echo "All done! Please restart ComfyUI."
