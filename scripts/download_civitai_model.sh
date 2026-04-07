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
# 若 API 返回异常（空响应/HTML/限流页），自动回退为 modelVersionId.safetensors
META_JSON="/tmp/civitai_model_version_${MODEL_VERSION_ID}.json"
DEFAULT_FILE_NAME="${MODEL_VERSION_ID}.safetensors"
if curl -fsSL -H "Accept: application/json" "$API_URL" -o "$META_JSON"; then
  FILE_NAME="$(python3 - "$META_JSON" "$DEFAULT_FILE_NAME" <<'PY'
import json, sys
p = sys.argv[1]
default = sys.argv[2]
try:
    with open(p, "r", encoding="utf-8") as f:
        obj = json.load(f)
    files = obj.get("files") or []
    if files and isinstance(files[0], dict) and files[0].get("name"):
        print(files[0]["name"])
    else:
        print(default)
except Exception:
    print(default)
PY
)"
else
  FILE_NAME="$DEFAULT_FILE_NAME"
fi

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
