#!/usr/bin/env bash
set -euo pipefail

# Required
: "${CIVITAI_API_KEY:?请先 export CIVITAI_API_KEY=...}" 

# Configurable paths
COMFY_DIR="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"
A1111_CKPT_DIR="${A1111_CKPT_DIR:-/workspace/stable-diffusion-webui/models/Stable-diffusion}"

# Your requested models
BASE_MODEL_VERSION_ID="${BASE_MODEL_VERSION_ID:-2113658}"   # https://civitai.com/models/1864281?modelVersionId=2113658
BFS_LORA_MODEL_ID="${BFS_LORA_MODEL_ID:-2027766}"           # https://civitai.com/models/2027766/bfs-best-face-swap

# Online-found Qwen dependencies (from Comfy-Org official repos)
QWEN_UNET_URL="https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_edit_2511_bf16.safetensors"
QWEN_TEXT_ENCODER_URL="https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
QWEN_VAE_URL="https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"

mkdir -p "$A1111_CKPT_DIR" \
         "$COMFY_DIR/models/checkpoints" \
         "$COMFY_DIR/models/loras" \
         "$COMFY_DIR/models/diffusion_models" \
         "$COMFY_DIR/models/text_encoders" \
         "$COMFY_DIR/models/vae"

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

download_with_resume() {
  local url="$1"
  local out_path="$2"
  local header1="${3:-}"
  local header2="${4:-}"
  local tmp_path="${out_path}.downloading"

  if [[ -s "$out_path" ]]; then
    echo "已存在，跳过: $out_path"
    return 0
  fi

  if [[ -f "$tmp_path" ]]; then
    echo "检测到未完成文件，续传: $tmp_path"
  else
    echo "开始下载: $out_path"
  fi

  if [[ -n "$header1" && -n "$header2" ]]; then
    curl -fL -C - --retry 20 --retry-delay 5 \
      -H "$header1" \
      -H "$header2" \
      "$url" -o "$tmp_path"
  elif [[ -n "$header1" ]]; then
    curl -fL -C - --retry 20 --retry-delay 5 \
      -H "$header1" \
      "$url" -o "$tmp_path"
  else
    curl -fL -C - --retry 20 --retry-delay 5 \
      "$url" -o "$tmp_path"
  fi

  mv "$tmp_path" "$out_path"
}

resolve_latest_version_from_model_id() {
  local model_id="$1"
  local jf="/tmp/civitai_model_${model_id}_${RANDOM}.json"
  curl -fsSL "https://civitai.com/api/v1/models/${model_id}" -o "$jf"
  python3 - "$jf" <<'PY'
import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj=json.load(f)
versions=obj.get('modelVersions') or []
if not versions:
    raise SystemExit('未找到 modelVersions')
print(versions[0]['id'])
PY
}

fetch_filename_by_version() {
  local version_id="$1"
  local jf="/tmp/civitai_version_${version_id}_${RANDOM}.json"
  curl -fsSL -H "Accept: application/json" "https://civitai.com/api/v1/model-versions/${version_id}" -o "$jf"
  python3 - "$jf" <<'PY'
import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj=json.load(f)
files=obj.get('files') or []
if files and files[0].get('name'):
    print(files[0]['name'])
else:
    print(f"{obj.get('id','model')}.safetensors")
PY
}

download_civitai_version() {
  local version_id="$1"
  local out_dir="$2"
  local referer_model_id="$3"

  local file_name
  file_name="$(fetch_filename_by_version "$version_id" || true)"
  if [[ -z "$file_name" ]]; then
    file_name="${version_id}.safetensors"
  fi

  local out_path="$out_dir/$file_name"
  local url="https://civitai.com/api/download/models/${version_id}?token=${CIVITAI_API_KEY}"
  local referer="https://civitai.com/models/${referer_model_id}?modelVersionId=${version_id}"

  echo "下载 Civitai version=$version_id -> $out_path"
  download_with_resume "$url" "$out_path" "User-Agent: ${UA}" "Referer: ${referer}"
}

download_url() {
  local url="$1"
  local out="$2"
  download_with_resume "$url" "$out"
}

echo "[1/5] 下载大模型（Civitai versionId=${BASE_MODEL_VERSION_ID}）"
download_civitai_version "$BASE_MODEL_VERSION_ID" "$A1111_CKPT_DIR" "1864281"

echo "[2/5] 下载 BFS 换脸 LoRA（由 modelId=${BFS_LORA_MODEL_ID} 自动取最新版本）"
BFS_LORA_VERSION_ID="$(resolve_latest_version_from_model_id "$BFS_LORA_MODEL_ID")"
echo "解析到 BFS LoRA versionId=$BFS_LORA_VERSION_ID"
download_civitai_version "$BFS_LORA_VERSION_ID" "$COMFY_DIR/models/loras" "$BFS_LORA_MODEL_ID"

echo "[3/5] 下载 Qwen 必需文件"
download_url "$QWEN_UNET_URL" "$COMFY_DIR/models/diffusion_models/qwen_image_edit_2511_bf16.safetensors"
download_url "$QWEN_TEXT_ENCODER_URL" "$COMFY_DIR/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
download_url "$QWEN_VAE_URL" "$COMFY_DIR/models/vae/qwen_image_vae.safetensors"

echo "[4/5] 链接 checkpoint 到 ComfyUI"
# Link all A1111 checkpoints into ComfyUI for convenience
shopt -s nullglob
for f in "$A1111_CKPT_DIR"/*.safetensors "$A1111_CKPT_DIR"/*.ckpt; do
  ln -sfn "$f" "$COMFY_DIR/models/checkpoints/$(basename "$f")"
done
shopt -u nullglob

echo "[5/5] 完成"
echo "请重启 ComfyUI 进程后再打开工作流。"
