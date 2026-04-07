#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/workspace/runpod-slim}"
REPO_DIR="${REPO_DIR:-$ROOT_DIR/pony}"
COMFY_DIR="${COMFY_DIR:-$ROOT_DIR/ComfyUI}"
A1111_CKPT_DIR="${A1111_CKPT_DIR:-/workspace/stable-diffusion-webui/models/Stable-diffusion}"
BASE_MODEL_VERSION_ID="${BASE_MODEL_VERSION_ID:-2113658}"
BFS_LORA_MODEL_ID="${BFS_LORA_MODEL_ID:-2027766}"

: "${CIVITAI_API_KEY:?请先 export CIVITAI_API_KEY=...}"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "错误: 找不到仓库目录: $REPO_DIR"
  echo "请先执行: git clone https://github.com/MetaLoan/pony.git $REPO_DIR"
  exit 1
fi

echo "[1/3] 更新仓库"
git -C "$REPO_DIR" pull --ff-only

echo "[2/3] 执行下载"
cd "$REPO_DIR"
COMFY_DIR="$COMFY_DIR" \
A1111_CKPT_DIR="$A1111_CKPT_DIR" \
BASE_MODEL_VERSION_ID="$BASE_MODEL_VERSION_ID" \
BFS_LORA_MODEL_ID="$BFS_LORA_MODEL_ID" \
CIVITAI_API_KEY="$CIVITAI_API_KEY" \
bash scripts/download_qwen_faceswap_bundle.sh

echo "[3/3] 完成（支持断点续传，失败可直接重跑）"
