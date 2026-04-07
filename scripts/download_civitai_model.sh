#!/usr/bin/env bash
set -euo pipefail

MODEL_VERSION_ID="${MODEL_VERSION_ID:-}"
OUT_DIR="${OUT_DIR:-/workspace/stable-diffusion-webui/models/Stable-diffusion}"

if [[ -z "$MODEL_VERSION_ID" ]]; then
  echo "用法: MODEL_VERSION_ID=2551619 CIVITAI_API_KEY=xxx bash scripts/download_civitai_model.sh"
  exit 1
fi

if [[ -z "${CIVITAI_API_KEY:-}" ]]; then
  echo "错误: 请先设置 CIVITAI_API_KEY"
  exit 1
fi

mkdir -p "$OUT_DIR"
API_URL="https://civitai.com/api/v1/model-versions/${MODEL_VERSION_ID}"
DOWNLOAD_URL="https://civitai.com/api/download/models/${MODEL_VERSION_ID}?token=${CIVITAI_API_KEY}"

# 通过 API 取推荐文件名（避免下载成错误名）
FILE_NAME="$(curl -fsSL "$API_URL" | python3 - <<'PY'
import json,sys
obj=json.load(sys.stdin)
files=obj.get('files') or []
if files:
    print(files[0].get('name') or f"{obj.get('id','model')}.safetensors")
else:
    print(f"{obj.get('id','model')}.safetensors")
PY
)"

TMP_PATH="$OUT_DIR/${FILE_NAME}.downloading"
FINAL_PATH="$OUT_DIR/$FILE_NAME"

echo "下载版本: $MODEL_VERSION_ID"
echo "目标文件: $FINAL_PATH"

wget -c --content-disposition "$DOWNLOAD_URL" -O "$TMP_PATH"
mv "$TMP_PATH" "$FINAL_PATH"

# 轻量校验 safetensors 头，避免下载到 HTML/报错页
python3 - "$FINAL_PATH" <<'PY'
import json, os, struct, sys
p=sys.argv[1]
size=os.path.getsize(p)
if size < 16:
    raise SystemExit('下载文件过小，疑似失败')
with open(p,'rb') as f:
    h=f.read(8)
    hs=struct.unpack('<Q',h)[0]
    if hs <= 0 or hs > size-8:
        raise SystemExit(f'非法 safetensors 头大小: {hs}')
    raw=f.read(hs)
json.loads(raw.decode('utf-8'))
print('safetensors 头校验通过')
PY

echo "下载完成: $FINAL_PATH"
