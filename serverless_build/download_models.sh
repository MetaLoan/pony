#!/bin/bash
# ==========================================================
# PuLID SDXL 模型一键下载脚本
# 用于 RunPod Network Volume 初始化
# 挂载路径：/workspace/models
# ==========================================================

set -e

CIVITAI_TOKEN="fd0f3beec0b56c19715e0161cca7505c"
BASE="/workspace/models"

echo "🚀 开始下载所有模型到 Network Volume..."

# 创建目录结构
mkdir -p $BASE/checkpoints
mkdir -p $BASE/loras
mkdir -p $BASE/pulid
mkdir -p $BASE/clip_vision
mkdir -p $BASE/insightface/models/antelopev2
mkdir -p $BASE/controlnet
mkdir -p $BASE/upscale_models
mkdir -p $BASE/custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose

pip install -q huggingface_hub

# 1. SDXL Checkpoint (~7GB)
echo "⬇️  [1/7] 下载 SDXL 主模型..."
curl -L "https://civitai.com/api/download/models/544282?token=${CIVITAI_TOKEN}" \
  -o $BASE/checkpoints/SDXL_Photorealistic_Mix_nsfw.safetensors

# 2. PuLID Models (~1GB)
echo "⬇️  [2/7] 下载 PuLID 模型..."
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='huchenlei/ipadapter_pulid', filename='ip-adapter_pulid_sdxl_fp16.safetensors', local_dir='$BASE/pulid')
hf_hub_download(repo_id='QuanSun/EVA-CLIP', filename='EVA02_CLIP_L_336_psz14_s6B.pt', local_dir='$BASE/clip_vision')
print('PuLID OK')
"

# 3. Insightface Antelopev2 (~200MB)
echo "⬇️  [3/7] 下载 InsightFace antelopev2..."
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='DIAMONIK7777/antelopev2', local_dir='$BASE/insightface/models/antelopev2', local_dir_use_symlinks=False)
print('InsightFace OK')
"

# 4. ControlNet Models (~3GB)
echo "⬇️  [4/7] 下载 ControlNet 模型..."
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='diffusers/controlnet-depth-sdxl-1.0', filename='diffusion_pytorch_model.safetensors', local_dir='$BASE/controlnet')
hf_hub_download(repo_id='thibaud/controlnet-openpose-sdxl-1.0', filename='OpenPoseXL2.safetensors', local_dir='$BASE/controlnet')
print('ControlNet OK')
"
mv $BASE/controlnet/diffusion_pytorch_model.safetensors $BASE/controlnet/controlnet-depth-sdxl-1.0.safetensors
mv $BASE/controlnet/OpenPoseXL2.safetensors $BASE/controlnet/controlnet-openpose-sdxl-1.0.safetensors

# 5. DWPose (仅下载使用到的2个文件, ~770MB)
echo "⬇️  [5/7] 下载 DWPose 关键文件..."
python3 -c "
from huggingface_hub import hf_hub_download
import os
target = '$BASE/custom_nodes/comfyui_controlnet_aux/ckpts/yzd-v/DWPose'
os.makedirs(target, exist_ok=True)
hf_hub_download(repo_id='yzd-v/DWPose', filename='yolox_l.onnx', local_dir=target)
hf_hub_download(repo_id='yzd-v/DWPose', filename='dw-ll_ucoco_384.onnx', local_dir=target)
print('DWPose OK')
"

# 6. LoRAs (3个)
echo "⬇️  [6/7] 下载 3 个 LoRA 模型..."
curl -L "https://civitai.com/api/download/models/160240?token=${CIVITAI_TOKEN}" \
  -o $BASE/loras/NSFW_POV_AllInOne.safetensors
curl -L "https://civitai.com/api/download/models/278770?token=${CIVITAI_TOKEN}" \
  -o $BASE/loras/SDXL_Sevenof9_7th_NSFW.safetensors
curl -L "https://civitai.com/api/download/models/518458?token=${CIVITAI_TOKEN}" \
  -o "$BASE/loras/Beautiful_face_alpha1.0.safetensors"

# 7. Upscaler (~67MB)
echo "⬇️  [7/7] 下载 4x-UltraSharp 放大模型..."
python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='lokCX/4x-Ultrasharp', filename='4x-UltraSharp.pth', local_dir='$BASE/upscale_models')
print('Upscaler OK')
"

echo ""
echo "✅ 所有模型下载完成！目录结构："
du -sh $BASE/*
