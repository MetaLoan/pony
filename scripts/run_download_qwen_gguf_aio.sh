#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/workspace/runpod-slim}"
REPO_DIR="${REPO_DIR:-$ROOT_DIR/pony}"
COMFY_DIR="${COMFY_DIR:-$ROOT_DIR/ComfyUI}"
MODEL_SUBDIR="${MODEL_SUBDIR:-v53}"
MODEL_QUANT="${MODEL_QUANT:-Q4_K_M}"
TEXT_QUANT="${TEXT_QUANT:-Q4_K_M}"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "错误: 找不到仓库目录: $REPO_DIR"
  echo "请先执行: git clone https://github.com/MetaLoan/pony.git $REPO_DIR"
  exit 1
fi

echo "[1/3] 更新仓库"
git -C "$REPO_DIR" pull --ff-only

echo "[2/3] 执行下载脚本"
cd "$REPO_DIR"
COMFY_DIR="$COMFY_DIR" \
MODEL_SUBDIR="$MODEL_SUBDIR" \
MODEL_QUANT="$MODEL_QUANT" \
TEXT_QUANT="$TEXT_QUANT" \
bash scripts/download_qwen_gguf_aio.sh

echo "[3/3] 完成"
echo "如有中断，直接重跑本脚本即可断点续传。"
