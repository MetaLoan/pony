import runpod
import os
import sys
import json
import uuid
import time
import base64
import requests
import subprocess
from io import BytesIO

# Configuration
COMFY_DIR = "/workspace/ComfyUI"
sys.path.append(COMFY_DIR)
PORT = 8188
API_URL = f"http://127.0.0.1:{PORT}"

def start_comfyui():
    """Starts ComfyUI in the background and waits until the API is available."""
    print("Starting ComfyUI server...")
    subprocess.Popen(
        [sys.executable, "main.py", "--port", str(PORT), "--listen", "127.0.0.1"],
        cwd=COMFY_DIR,
        stdout=sys.stdout,
        stderr=sys.stderr
    )

    # Wait for the server to spin up
    for i in range(30):
        try:
            res = requests.get(f"{API_URL}/history")
            if res.status_code == 200:
                print("ComfyUI server is ready.")
                return
        except requests.exceptions.ConnectionError:
            pass
        time.sleep(2)
    raise Exception("Failed to start ComfyUI within the timeout.")

def save_base64_image(b64_str, filename):
    """Decodes a base64 string and saves it to ComfyUI's input directory."""
    try:
        # Strip data:image prefix if present
        if "," in b64_str:
            b64_str = b64_str.split(",")[1]
            
        img_data = base64.b64decode(b64_str)
        filepath = os.path.join(COMFY_DIR, "input", filename)
        with open(filepath, "wb") as f:
            f.write(img_data)
        return filename
    except Exception as e:
        raise ValueError(f"Failed to decode and save base64 image: {str(e)}")

def file_to_base64(filepath):
    """Reads a file and converts it to a base64 string."""
    with open(filepath, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def handler(job):
    job_input = job.get("input", {})
    
    # 1. Parse Image Base64 payload
    ref_b64 = job_input.get("reference_image")
    pose_b64 = job_input.get("pose_image")
    
    if not ref_b64:
        return {"error": "Missing 'reference_image' in input payload."}

    # 2. Extract Configurable Values
    prompt_text = job_input.get("prompt", "a beautiful young woman, perfect face")
    negative_text = job_input.get("negative_prompt", "ugly, deformed, noisy, blurry")
    seed = job_input.get("seed", int(time.time() * 1000))
    cfg = job_input.get("cfg", 4.0)
    steps = job_input.get("steps", 30)
    width = job_input.get("width", 832)
    height = job_input.get("height", 1216)
    ckpt_name = job_input.get("ckpt_name", "SDXL_NSFW.safetensors")
    lora_name = job_input.get("lora_name", "NSFW_POV_AllInOne.safetensors")
    lora_strength = job_input.get("lora_strength", 0.9)
    pulid_weight = job_input.get("pulid_weight", 0.85)
    pulid_end_at = job_input.get("pulid_end_at", 0.85)
    
    # 3. Extract Feature Toggles
    use_controlnet = job_input.get("use_controlnet", True)
    use_upscale = job_input.get("use_upscale", True)

    ref_filename = f"ref_{uuid.uuid4().hex}.jpg"
    pose_filename = f"pose_{uuid.uuid4().hex}.jpg"

    save_base64_image(ref_b64, ref_filename)
    if pose_b64 and use_controlnet:
        save_base64_image(pose_b64, pose_filename)
        
    with open(os.path.join(os.path.dirname(__file__), "sd-ctrlnet-facefusion-api.json"), "r") as f:
        prompt = json.load(f)

    # 4. Patch Basic Configurations
    if "1" in prompt: prompt["1"]["inputs"]["ckpt_name"] = ckpt_name
    if "2" in prompt: prompt["2"]["inputs"]["text"] = prompt_text
    if "3" in prompt: prompt["3"]["inputs"]["text"] = negative_text
    if "7" in prompt: prompt["7"]["inputs"]["image"] = ref_filename
    if "13" in prompt: 
        prompt["13"]["inputs"]["width"] = width
        prompt["13"]["inputs"]["height"] = height
    if "14" in prompt:
        prompt["14"]["inputs"]["seed"] = seed
        prompt["14"]["inputs"]["steps"] = steps
        prompt["14"]["inputs"]["cfg"] = cfg
    if "17" in prompt:
        prompt["17"]["inputs"]["lora_name"] = lora_name
        prompt["17"]["inputs"]["strength_model"] = lora_strength
        prompt["17"]["inputs"]["strength_clip"] = lora_strength
    if "8" in prompt:
        prompt["8"]["inputs"]["weight"] = float(pulid_weight)
        prompt["8"]["inputs"]["end_at"] = float(pulid_end_at)
        
    # --- GRAPH REWIRING LOGIC --- #
    
    # A. CONTROLNET BYPASS
    if use_controlnet:
        if pose_b64:
            prompt["9"]["inputs"]["image"] = pose_filename
        else:
            # Fallback to reference image if pose toggled but missing
            prompt["9"]["inputs"]["image"] = ref_filename
    else:
        # Bypassing ControlNet: Route KSampler inputs directly from CLIPTextEncode
        if "14" in prompt and "2" in prompt and "3" in prompt:
            prompt["14"]["inputs"]["positive"] = ["2", 0] 
            prompt["14"]["inputs"]["negative"] = ["3", 0] 
        # Purge controlnet nodes
        for node_id in ["9", "10", "11", "12"]:
            if node_id in prompt:
                del prompt[node_id]

    # B. UPSCALE BYPASS
    has_upscale_nodes = "18" in prompt and "19" in prompt
    
    if use_upscale:
        if not has_upscale_nodes:
            # Dynamically reconstruct the missing upscale Nodes in memory
            prompt["18"] = {
                "inputs": {"model_name": "4x-UltraSharp.pth"},
                "class_type": "UpscaleModelLoader"
            }
            prompt["19"] = {
                "inputs": {
                    "upscale_model": ["18", 0],
                    "image": ["15", 0] # Hook to VAEDecode
                },
                "class_type": "ImageUpscaleWithModel"
            }
        # Point SaveImage to the Upscaler Output
        if "16" in prompt:
            prompt["16"]["inputs"]["images"] = ["19", 0]
    else:
        # Point SaveImage straight to VAEDecode Output (No Upscale)
        if "16" in prompt:
            prompt["16"]["inputs"]["images"] = ["15", 0]
        # Purge upscale nodes if they existed
        for node_id in ["18", "19"]:
            if node_id in prompt:
                del prompt[node_id]

    # 4. Queue the runtime prompt
    p = {"prompt": prompt, "client_id": str(uuid.uuid4())}
    try:
        res = requests.post(f"{API_URL}/prompt", json=p).json()
        prompt_id = res.get("prompt_id")
        if not prompt_id:
            return {"error": f"Failed to get prompt_id: {res}"}
    except Exception as e:
        return {"error": f"ComfyUI API Request Failed: {str(e)}"}

    # 5. Poll for completion
    timeout = 180
    start_time = time.time()
    while time.time() - start_time < timeout:
        history_res = requests.get(f"{API_URL}/history/{prompt_id}").json()
        
        if prompt_id in history_res:
            outputs = history_res[prompt_id].get("outputs", {})
            output_images = []
            
            # Find SaveImage node (Node 16)
            for node_id, node_output in outputs.items():
                if "images" in node_output:
                    for img in node_output["images"]:
                        img_filename = img["filename"]
                        img_path = os.path.join(COMFY_DIR, "output", img_filename)
                        if os.path.exists(img_path):
                            output_images.append(file_to_base64(img_path))
            
            return {
                "status": "success",
                "images": output_images,
                "seed": seed
            }
        
        time.sleep(2)

    return {"error": "Timeout waiting for image generation."}

# Start ComfyUI up on boot
start_comfyui()
# Start Serverless logic
runpod.serverless.start({"handler": handler})
