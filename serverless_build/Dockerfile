FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04

# Use bash
SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git wget libgl1 libglib2.0-0 jq \
    && rm -rf /var/lib/apt/lists/*

# Setup workspace
WORKDIR /workspace

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git 
WORKDIR /workspace/ComfyUI

# Install ComfyUI dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Install custom nodes
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone https://github.com/cubiq/PuLID_ComfyUI.git && \
    git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git

# Install python dependencies for nodes
RUN pip install --no-cache-dir insightface huggingface_hub onnxruntime-gpu
RUN pip install --no-cache-dir -r comfyui_controlnet_aux/requirements.txt

# Download Models (Baking into Docker!)
# 1. SDXL Checkpoint
ARG CIVITAI_TOKEN="fd0f3beec0b56c19715e0161cca7505c"

WORKDIR /workspace/ComfyUI/models

# 1. SDXL Checkpoints
RUN curl -L "https://civitai.com/api/download/models/544282?token=${CIVITAI_TOKEN}" -o checkpoints/SDXL_Photorealistic_Mix_nsfw.safetensors

# 2. PuLID Models
RUN python3 -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='huchenlei/ipadapter_pulid', filename='ip-adapter_pulid_sdxl_fp16.safetensors', local_dir='pulid')" && \
    python3 -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='QuanSun/EVA-CLIP', filename='EVA02_CLIP_L_336_psz14_s6B.pt', local_dir='clip_vision')"

# 3. Insightface Antelopev2 Models
RUN python3 -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='DIAMONIK7777/antelopev2', local_dir='insightface/models/antelopev2', local_dir_use_symlinks=False)"

# 4. ControlNet & Annotators
RUN wget -O controlnet/controlnet-depth-sdxl-1.0.safetensors "https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.safetensors"

# 5. LoRA
RUN curl -L "https://civitai.com/api/download/models/160240?token=${CIVITAI_TOKEN}" -o loras/NSFW_POV_AllInOne.safetensors

# 6. Upscaler
RUN mkdir -p upscale_models && wget -O upscale_models/4x-UltraSharp.pth "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth"

# Install Serverless dependencies
WORKDIR /
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy handler and the workflow JSON
COPY handler.py /handler.py
COPY sd-ctrlnet-facefusion-api.json /sd-ctrlnet-facefusion-api.json

# Start the RunPod serverless handler
CMD ["python3", "-u", "/handler.py"]
