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

# 1. Install 1038lab's ComfyUI-QwenVL Node
echo ">>> Step 1: Installing ComfyUI-QwenVL custom node..."
cd "$COMFY_DIR/custom_nodes" || exit 1
if [ ! -d "ComfyUI-QwenVL" ]; then
    # Use GIT_CONFIG_GLOBAL=/dev/null to avoid local git config (like `insteadOf`) forcing auth on public repos
    GIT_CONFIG_GLOBAL=/dev/null git clone https://github.com/1038lab/ComfyUI-QwenVL.git
    cd ComfyUI-QwenVL
    pip install -r requirements.txt
    cd ..
else
    echo "ComfyUI-QwenVL already installed, pulling latest..."
    cd ComfyUI-QwenVL && GIT_CONFIG_GLOBAL=/dev/null git pull && cd ..
fi

# 2. Download Qwen2.5-VL-7B-Instruct GGUF models
echo ">>> Step 2: Downloading Qwen2.5-VL-7B-Instruct GGUF models..."
cd "$COMFY_DIR/models" || exit 1

# Create the specific directory if required by the Kijai node
mkdir -p LLM/Qwen2.5-VL
cd LLM/Qwen2.5-VL || exit 1

# Use wget for a bulletproof download that avoids pip matching issues entirely
echo "Downloading Qwen2.5-VL Q4_K_M GGUF (Low VRAM optimized)... this will take a few minutes."
if [ ! -f "qwen2.5-vl-7b-instruct-q4_k_m.gguf" ]; then
    wget -c "https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/qwen2.5-vl-7b-instruct-q4_k_m.gguf?download=true" -O qwen2.5-vl-7b-instruct-q4_k_m.gguf.tmp
    mv qwen2.5-vl-7b-instruct-q4_k_m.gguf.tmp qwen2.5-vl-7b-instruct-q4_k_m.gguf
else
    echo "qwen2.5-vl-7b-instruct-q4_k_m.gguf already exists! Skipping download."
fi

echo ">>> Deployment completed successfully!"
echo "Please restart ComfyUI. You can now use the Qwen2-VL nodes."
