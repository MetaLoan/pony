# ComfyUI PuLID SDXL Workflow & RunPod Installer

This repository contains a one-click deployment script and a complete ComfyUI workflow for using PuLID with SDXL, specifically optimized for cloud environments like RunPod.

## What is PuLID?
PuLID (Pure Latent Identity) is an advanced face-consistency and identity injection method for Stable Diffusion XL (and Flux). Unlike traditional post-processing face-swap tools (like ReActor), PuLID embeds the facial features (ID) directly into the diffusion model's attention layers *before* the sampling starts in the latent space. This results in far better preservation of lighting, style, and structure without the "sticker" effect.

## Repository Contents

- `pulid_sdxl_workflow.json` - A highly optimized ComfyUI workflow integrating:
  - PuLID SDXL base injection
  - Depth ControlNet for pose alignment
  - Standardized KSampler setup
- `install_pulid_runpod.sh` - An automated Bash deployment script.

## Quick Start on RunPod

1. Clone or download this repository into your RunPod workspace.
2. Make the script executable and run it:
```bash
chmod +x install_pulid_runpod.sh
./install_pulid_runpod.sh
```

**What the script does automatically:**
- Auto-locates your ComfyUI root directory.
- Clones missing custom nodes (`PuLID_ComfyUI`, `ComfyUI_FaceAnalysis`, `comfyui_controlnet_aux`).
- Installs necessary Python dependencies (`insightface`, `onnxruntime-gpu`).
- Downloads the required model weights via HuggingFace HUB (PuLID safetensors, EVA-CLIP pt, buffalo_l face models).

3. **Restart ComfyUI**.
4. Drag and drop the `pulid_sdxl_workflow.json` into your ComfyUI interface.

## Workflow Parameters (Cheat Sheet)
- **ApplyPulid -> Weight:** 0.85 (Sweet spot for realistic styles)
- **ApplyPulid -> Fidelity:** Recommended for strict facial adherence.
- **ControlNet Depth -> Strength:** 0.6 (Provides structural guidance without overriding the ID).
- **KSampler -> CFG Scale:** 5.0 - 7.0 (Lower CFG avoids over-saturation).
