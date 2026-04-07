#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
A1111_CKPT_DIR="${A1111_CKPT_DIR:-/workspace/stable-diffusion-webui/models/Stable-diffusion}"

if [[ ! -d "$COMFY_DIR" ]]; then
  echo "找不到 ComfyUI 目录: $COMFY_DIR"
  exit 1
fi

if [[ -x "$COMFY_DIR/venv/bin/python" ]]; then
  PY="$COMFY_DIR/venv/bin/python"
else
  PY="python3"
fi

echo "== 安装/更新 ComfyUI_IPAdapter_plus =="
mkdir -p "$COMFY_DIR/custom_nodes"
if [[ -d "$COMFY_DIR/custom_nodes/ComfyUI_IPAdapter_plus/.git" ]]; then
  git -C "$COMFY_DIR/custom_nodes/ComfyUI_IPAdapter_plus" pull --ff-only
else
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git "$COMFY_DIR/custom_nodes/ComfyUI_IPAdapter_plus"
fi

echo "== 安装依赖 =="
"$PY" -m pip install -U insightface onnxruntime-gpu || "$PY" -m pip install -U insightface onnxruntime

echo "== 创建模型目录 =="
mkdir -p "$COMFY_DIR/models/ipadapter" \
         "$COMFY_DIR/models/clip_vision" \
         "$COMFY_DIR/models/insightface/models" \
         "$COMFY_DIR/models/loras" \
         "$COMFY_DIR/models/checkpoints"

download() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" && -s "$out" ]]; then
    echo "已存在: $out"
  else
    echo "下载: $out"
    wget -c "$url" -O "$out"
  fi
}

echo "== 下载 IP-Adapter FaceID + CLIP Vision + LoRA =="
download "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" \
         "$COMFY_DIR/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin"

download "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" \
         "$COMFY_DIR/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

download "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
         "$COMFY_DIR/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors"

echo "== 下载 InsightFace antelopev2 =="
TMP_ZIP="/tmp/antelopev2.zip"
if [[ ! -f "$TMP_ZIP" || ! -s "$TMP_ZIP" ]]; then
  wget -c "https://github.com/deepinsight/insightface/releases/download/v0.7/antelopev2.zip" -O "$TMP_ZIP" || \
  wget -c "https://sourceforge.net/projects/insightface.mirror/files/v0.7/antelopev2.zip/download" -O "$TMP_ZIP"
fi

rm -rf "$COMFY_DIR/models/insightface/models/antelopev2"
unzip -o "$TMP_ZIP" -d "$COMFY_DIR/models/insightface/models/"
if [[ ! -d "$COMFY_DIR/models/insightface/models/antelopev2" ]]; then
  echo "antelopev2 解压失败，请检查 /tmp/antelopev2.zip"
  exit 1
fi

echo "== 链接 A1111 大模型到 ComfyUI checkpoints =="
if [[ -d "$A1111_CKPT_DIR" ]]; then
  shopt -s nullglob
  for f in "$A1111_CKPT_DIR"/*.safetensors "$A1111_CKPT_DIR"/*.ckpt; do
    ln -sfn "$f" "$COMFY_DIR/models/checkpoints/$(basename "$f")"
  done
  shopt -u nullglob
else
  echo "警告: 未找到 A1111 模型目录 $A1111_CKPT_DIR"
fi

echo
echo "完成。请重启 ComfyUI 后再加载 /Users/leo/Desktop/02169.json"
echo "并把参考脸图放到: $COMFY_DIR/input/face_ref.png"
