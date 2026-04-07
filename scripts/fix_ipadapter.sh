#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"

echo "[1/7] 使用 COMFY_DIR=$COMFY_DIR"
if [[ ! -d "$COMFY_DIR" ]]; then
  echo "错误: 找不到 ComfyUI 目录: $COMFY_DIR"
  echo "请用: COMFY_DIR=/你的/ComfyUI路径 bash scripts/fix_ipadapter.sh"
  exit 1
fi

cd "$COMFY_DIR"

echo "[2/7] 安装/更新 ComfyUI_IPAdapter_plus"
mkdir -p custom_nodes
if [[ -d custom_nodes/ComfyUI_IPAdapter_plus/.git ]]; then
  git -C custom_nodes/ComfyUI_IPAdapter_plus pull --ff-only
else
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git custom_nodes/ComfyUI_IPAdapter_plus
fi

echo "[3/7] 选择 Python 解释器"
if [[ -x "$COMFY_DIR/venv/bin/python" ]]; then
  PY="$COMFY_DIR/venv/bin/python"
else
  PY="python3"
fi
echo "Using Python: $PY"

# Some images lack pip in venv
if ! "$PY" -m pip --version >/dev/null 2>&1; then
  "$PY" -m ensurepip --upgrade || true
fi

echo "[4/7] 安装依赖"
"$PY" -m pip install -U -r custom_nodes/ComfyUI_IPAdapter_plus/requirements.txt
"$PY" -m pip install -U insightface onnxruntime-gpu || "$PY" -m pip install -U insightface onnxruntime

echo "[5/7] 检查节点类"
if grep -R "IPAdapterModelLoader\\|IPAdapterFaceID\\|IPAdapterInsightFaceLoader" custom_nodes/ComfyUI_IPAdapter_plus -n | head -n 20; then
  echo "节点类检索通过"
else
  echo "警告: 未检索到目标节点类，请检查插件是否完整"
fi

echo "[6/7] 检查模型文件"
check_file() {
  local f="$1"
  if [[ -s "$f" ]]; then
    ls -lh "$f"
  else
    echo "缺失: $f"
  fi
}
check_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    ls -lh "$d" | head -n 20
  else
    echo "缺失目录: $d"
  fi
}

check_file "$COMFY_DIR/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin"
check_file "$COMFY_DIR/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"
check_dir  "$COMFY_DIR/models/insightface/models/antelopev2"

echo "[7/7] 完成"
echo "请彻底重启 ComfyUI 进程后再导入工作流。"
echo "如仍报错，执行: cd $COMFY_DIR && python3 main.py 2>&1 | tee /tmp/comfy_start.log"
