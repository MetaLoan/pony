#!/usr/bin/env bash
set -euo pipefail

# Repo / variant selection
HF_REPO="${HF_REPO:-Phil2Sat/Qwen-Image-Edit-Rapid-AIO-GGUF}"
MODEL_SUBDIR="${MODEL_SUBDIR:-v53}"                    # e.g. v50 / v52 / v53 / v71 / v90
MODEL_QUANT="${MODEL_QUANT:-Q4_K_M}"                  # e.g. Q2_K / Q4_K_M / Q5_K_M / Q8_0 / F16
TEXT_REPO_SUBDIR="${TEXT_REPO_SUBDIR:-Qwen2.5-VL-7B-Instruct-abliterated}"
TEXT_QUANT="${TEXT_QUANT:-Q4_K_M}"

# Paths
COMFY_DIR="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"
DIFF_DIR="${DIFF_DIR:-$COMFY_DIR/models/diffusion_models}"
TEXT_DIR="${TEXT_DIR:-$COMFY_DIR/models/text_encoders}"
VAE_DIR="${VAE_DIR:-$COMFY_DIR/models/vae}"

# Optional HF token for gated/limited downloads
HF_TOKEN="${HF_TOKEN:-}"

mkdir -p "$DIFF_DIR" "$TEXT_DIR" "$VAE_DIR"

api_url="https://huggingface.co/api/models/${HF_REPO}"

# Pull file list from HF API
siblings_json="$(curl -fsSL "$api_url")"

pick_file() {
  local prefix="$1"
  local contains="$2"
  python3 - "$prefix" "$contains" <<'PY'
import json, sys
prefix=sys.argv[1]
contains=sys.argv[2]
obj=json.loads(sys.stdin.read())
files=[x.get('rfilename','') for x in obj.get('siblings',[]) if isinstance(x,dict)]
# Prefer exact quant matches and non-mmproj main gguf first
cand=[f for f in files if f.startswith(prefix+'/') and f.endswith('.gguf') and contains in f and 'mmproj' not in f.lower()]
# shortest filename first to avoid accidental extras
cand=sorted(cand, key=len)
print(cand[0] if cand else '')
PY
}

pick_mmproj() {
  local prefix="$1"
  python3 - "$prefix" <<'PY'
import json, sys
prefix=sys.argv[1]
obj=json.loads(sys.stdin.read())
files=[x.get('rfilename','') for x in obj.get('siblings',[]) if isinstance(x,dict)]
cand=[f for f in files if f.startswith(prefix+'/') and f.endswith('.gguf') and 'mmproj' in f.lower()]
print(sorted(cand, key=len)[0] if cand else '')
PY
}

MODEL_FILE="$(printf '%s' "$siblings_json" | pick_file "$MODEL_SUBDIR" "$MODEL_QUANT")"
TEXT_FILE="$(printf '%s' "$siblings_json" | pick_file "$TEXT_REPO_SUBDIR" "$TEXT_QUANT")"
MMPROJ_FILE="$(printf '%s' "$siblings_json" | pick_mmproj "$TEXT_REPO_SUBDIR")"

if [[ -z "$MODEL_FILE" ]]; then
  echo "错误: 未找到主模型文件。检查 MODEL_SUBDIR=$MODEL_SUBDIR MODEL_QUANT=$MODEL_QUANT"
  exit 1
fi
if [[ -z "$TEXT_FILE" ]]; then
  echo "错误: 未找到文本编码器GGUF。检查 TEXT_REPO_SUBDIR=$TEXT_REPO_SUBDIR TEXT_QUANT=$TEXT_QUANT"
  exit 1
fi
if [[ -z "$MMPROJ_FILE" ]]; then
  echo "错误: 未找到 mmproj 文件（该模型通常需要）"
  exit 1
fi

model_url="https://huggingface.co/${HF_REPO}/resolve/main/${MODEL_FILE}"
text_url="https://huggingface.co/${HF_REPO}/resolve/main/${TEXT_FILE}"
mmproj_url="https://huggingface.co/${HF_REPO}/resolve/main/${MMPROJ_FILE}"
vae_url="https://huggingface.co/calcuis/pig-vae/resolve/main/pig_qwen_image_vae_fp32-f16.gguf"

model_out="$DIFF_DIR/$(basename "$MODEL_FILE")"
text_out="$TEXT_DIR/$(basename "$TEXT_FILE")"
mmproj_out="$TEXT_DIR/$(basename "$MMPROJ_FILE")"
vae_out="$VAE_DIR/pig_qwen_image_vae_fp32-f16.gguf"

download() {
  local url="$1"
  local out="$2"
  if [[ -s "$out" ]]; then
    echo "已存在，跳过: $out"
    return 0
  fi
  echo "下载: $out"
  if [[ -n "$HF_TOKEN" ]]; then
    wget -c --header="Authorization: Bearer ${HF_TOKEN}" "$url" -O "$out"
  else
    wget -c "$url" -O "$out"
  fi
}

echo "[1/4] 下载主模型 GGUF: $MODEL_FILE"
download "$model_url" "$model_out"

echo "[2/4] 下载文本编码器 GGUF + mmproj"
download "$text_url" "$text_out"
download "$mmproj_url" "$mmproj_out"

echo "[3/4] 下载 Qwen VAE GGUF"
download "$vae_url" "$vae_out"

echo "[4/4] 完成"
echo "主模型: $model_out"
echo "文本编码器: $text_out"
echo "mmproj: $mmproj_out"
echo "VAE: $vae_out"
echo "提示: mmproj 已放在 text_encoders 目录，与文本编码器 gguf 同目录。"
