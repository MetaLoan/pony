#!/bin/bash
# ============================================================
# 下载 Qwen-Image-Edit-2511 Lightning LoRA
# 仓库: lightx2v/Qwen-Image-Edit-2511-Lightning
# 放到 loras/ 目录，配合 qwen_image_edit_2511_bf16.safetensors 使用
# KSampler 设置: steps=4, CFG=1.0
# ============================================================

LORA_DIR="/ComfyUI/models/loras"
mkdir -p "$LORA_DIR"

BASE_URL="https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main"

echo "=================================================="
echo " Qwen-Image-Edit-2511 Lightning LoRA 下载脚本"
echo " 目标目录: $LORA_DIR"
echo "=================================================="

download_file() {
    local url="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [ -f "$dest" ]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        local size_mb=$(echo "scale=0; $size/1048576" | bc)
        echo "[跳过] $name 已存在 (${size_mb}MB)"
        return 0
    fi

    echo ""
    echo "[开始下载] $name"
    curl -L -C - \
         --retry 3 \
         --retry-delay 5 \
         --progress-bar \
         -o "$dest" \
         "$url"

    if [ $? -eq 0 ]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        local size_mb=$(echo "scale=0; $size/1048576" | bc)
        echo "[完成] $name (${size_mb}MB)"
    else
        echo "[失败] 下载失败，重新运行可续传"
        exit 1
    fi
}

# ---- 主下载：4步 bf16 版（推荐，850MB）----
download_file \
    "${BASE_URL}/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors?download=true" \
    "${LORA_DIR}/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"

# ---- 可选：8步 bf16 版（质量更高，850MB）----
# download_file \
#     "${BASE_URL}/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors?download=true" \
#     "${LORA_DIR}/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"

echo ""
echo "=================================================="
echo " 下载完成！"
echo ""
echo " 使用方式（在 qwen_image_edit_2511.json 中）:"
echo "   Enable Lightning LoRA = true"
echo "   LoRA 文件: Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"
echo "   KSampler: steps=4, cfg=1.0"
echo "=================================================="
