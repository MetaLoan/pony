#!/bin/bash
# ============================================================
# 下载 Phr00t/Qwen-Image-Edit-Rapid-AIO v23
# AIO checkpoint: Model + CLIP + VAE 合一
# 放到 checkpoints/ 目录，用 CheckpointLoaderSimple 加载
# ============================================================

DEST_DIR="/ComfyUI/models/checkpoints"
mkdir -p "$DEST_DIR"

BASE_URL="https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23"

# ---- 选择版本 ----
# SFW 版（默认）
FILE_SFW="Qwen-Rapid-AIO-SFW-v23.safetensors"
# NSFW 版（取消注释另一行来下载）
FILE_NSFW="Qwen-Rapid-AIO-NSFW-v23.safetensors"

echo "=================================================="
echo " Qwen-Image-Edit-Rapid-AIO v23 下载脚本"
echo " 目标目录: $DEST_DIR"
echo "=================================================="

download_file() {
    local url="$1"
    local dest="$2"
    local name=$(basename "$dest")

    if [ -f "$dest" ]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        local size_gb=$(echo "scale=1; $size/1073741824" | bc)
        echo "[跳过] $name 已存在 (${size_gb}GB)"
        return 0
    fi

    echo ""
    echo "[开始下载] $name (~28.4 GB，预计 10-30 分钟)"
    echo "  URL: $url"
    echo ""

    # -L 跟随重定向，-C - 断点续传，--retry 3 失败重试
    curl -L -C - \
         --retry 3 \
         --retry-delay 10 \
         --progress-bar \
         -o "$dest" \
         "$url"

    if [ $? -eq 0 ]; then
        local size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
        local size_gb=$(echo "scale=1; $size/1073741824" | bc)
        echo "[完成] $name (${size_gb}GB)"
    else
        echo "[失败] $name 下载失败，请重新运行脚本（-C - 会续传）"
        exit 1
    fi
}

# ---- 下载 SFW 版 ----
download_file "${BASE_URL}/${FILE_SFW}?download=true" "${DEST_DIR}/${FILE_SFW}"

# ---- 如需同时下载 NSFW 版，取消下面的注释 ----
# download_file "${BASE_URL}/${FILE_NSFW}?download=true" "${DEST_DIR}/${FILE_NSFW}"

echo ""
echo "=================================================="
echo " 下载完成！"
echo " 在 ComfyUI 中使用 CheckpointLoaderSimple 节点"
echo " 选择: $FILE_SFW"
echo "=================================================="

# 验证文件大小（≥28GB 才算正常）
for f in "${DEST_DIR}/${FILE_SFW}"; do
    if [ -f "$f" ]; then
        size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
        if [ "$size" -lt 28000000000 ]; then
            echo "[警告] $f 文件大小异常 (${size} bytes)，可能下载不完整"
        else
            echo "[验证通过] $(basename $f)"
        fi
    fi
done
