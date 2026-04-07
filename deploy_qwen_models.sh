#!/bin/bash

# ==========================================
# Qwen Native Face Swap Research Environment setup
# ==========================================

echo "Starting deployment of Qwen Native Face Swap dependencies..."

# Ensure we have comfyui path (defaulting to the RunPod environment used in other scripts)
COMFY_DIR="${COMFY_DIR:-/workspace/runpod-slim/ComfyUI}"

if [ ! -d "$COMFY_DIR/custom_nodes" ]; then
    echo "Warning: $COMFY_DIR/custom_nodes not found. Please pass the correct ComfyUI path as an environment variable."
    echo "Usage: COMFY_DIR=/path/to/ComfyUI ./deploy_qwen_models.sh"
    exit 1
fi

# 1. Install Kijai's ComfyUI-Qwen2-VL Node
echo ">>> Step 1: Installing ComfyUI-Qwen2-VL custom node..."
cd "$COMFY_DIR/custom_nodes" || exit 1
if [ ! -d "ComfyUI-Qwen2-VL" ]; then
    # Use GIT_CONFIG_GLOBAL=/dev/null to avoid local git config (like `insteadOf`) forcing auth on public repos
    GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/kijai/ComfyUI-Qwen2-VL.git
    cd ComfyUI-Qwen2-VL
    pip install -r requirements.txt
    cd ..
else
    echo "ComfyUI-Qwen2-VL already installed, pulling latest..."
    cd ComfyUI-Qwen2-VL && GIT_CONFIG_GLOBAL=/dev/null git pull && cd ..
fi

# 2. Download Qwen2.5-VL-7B-Instruct GGUF models
echo ">>> Step 2: Downloading Qwen2.5-VL-7B-Instruct GGUF models..."
cd "$COMFY_DIR/models" || exit 1

# Create the specific directory if required by the Kijai node
mkdir -p LLM/Qwen2.5-VL
cd LLM/Qwen2.5-VL || exit 1

# Check if huggingface-cli is installed, try using python module directly
if ! python3 -m huggingface_hub.cli env &> /dev/null; then
    echo "huggingface_hub cli not working, installing..."
    pip install -U "huggingface_hub[cli]"
fi

echo "Downloading the Qwen2.5-VL Q4_K_M GGUF (Low VRAM optimized)..."
python3 -m huggingface_hub.cli download Qwen/Qwen2.5-VL-7B-Instruct-GGUF qwen2.5-vl-7b-instruct-q4_k_m.gguf --local-dir .

echo ">>> Deployment completed successfully!"
echo "Please restart ComfyUI. You can now use the Qwen2-VL nodes."
