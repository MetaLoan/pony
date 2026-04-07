#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"
A1111_CKPT_DIR="${A1111_CKPT_DIR:-/workspace/stable-diffusion-webui/models/Stable-diffusion}"
CKPT_NAME="${CKPT_NAME:-PonyRealism_v2.2_VAE.safetensors}"
CIVITAI_MODEL_ID="${CIVITAI_MODEL_ID:-914390}"

CKPT_PATH="$A1111_CKPT_DIR/$CKPT_NAME"
COMFY_CKPT_LINK="$COMFY_DIR/models/checkpoints/$CKPT_NAME"

echo "[1/5] 路径信息"
echo "COMFY_DIR=$COMFY_DIR"
echo "A1111_CKPT_DIR=$A1111_CKPT_DIR"
echo "CKPT_NAME=$CKPT_NAME"

mkdir -p "$A1111_CKPT_DIR" "$COMFY_DIR/models/checkpoints"

validate_safetensors() {
  local file="$1"
  python3 - "$file" <<'PY'
import json, os, struct, sys
p=sys.argv[1]
if not os.path.exists(p):
    print('MISSING')
    raise SystemExit(2)
size=os.path.getsize(p)
print(f'SIZE={size}')
if size < 16:
    print('TOO_SMALL')
    raise SystemExit(3)
with open(p,'rb') as f:
    h=f.read(8)
    if len(h)!=8:
        print('BAD_HEADER_LEN')
        raise SystemExit(4)
    header_size=struct.unpack('<Q',h)[0]
    if header_size <= 0 or header_size > size-8:
        print(f'BAD_HEADER_SIZE={header_size}')
        raise SystemExit(5)
    raw=f.read(header_size)
try:
    obj=json.loads(raw.decode('utf-8'))
except Exception as e:
    print(f'BAD_UTF8_OR_JSON={e}')
    raise SystemExit(6)
if not isinstance(obj,dict):
    print('BAD_JSON_TYPE')
    raise SystemExit(7)
print('VALID_SAFETENSORS')
PY
}

echo "[2/5] 检查现有模型文件"
if validate_safetensors "$CKPT_PATH"; then
  echo "checkpoint 文件有效，无需重下"
else
  echo "checkpoint 文件无效，准备重下"
  rm -f "$CKPT_PATH"
  if [[ -z "${CIVITAI_API_KEY:-}" ]]; then
    echo "错误: 检测到文件损坏，且未设置 CIVITAI_API_KEY，无法自动重下"
    exit 1
  fi

  TMP="${CKPT_PATH}.downloading"
  URL="https://civitai.com/api/download/models/${CIVITAI_MODEL_ID}?token=${CIVITAI_API_KEY}"
  echo "开始下载: $URL"
  wget -c "$URL" -O "$TMP"

  mv "$TMP" "$CKPT_PATH"
  echo "下载完成，复检文件"
  validate_safetensors "$CKPT_PATH"
fi

echo "[3/5] 修复 ComfyUI checkpoint 链接"
ln -sfn "$CKPT_PATH" "$COMFY_CKPT_LINK"
ls -lh "$CKPT_PATH"
ls -lh "$COMFY_CKPT_LINK"


echo "[4/5] 建议重启 ComfyUI"
echo "请重启 ComfyUI 进程，再加载 workflow。"

echo "[5/5] 完成"
