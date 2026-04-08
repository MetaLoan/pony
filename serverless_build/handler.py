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
    """
    Main job handler.
    Expects job["input"] to contain:
    - reference_image: Base64 string of the face reference
    - pose_image: Base64 string of the pose reference (optional)
    - prompt: string
    """
    job_input = job.get("input", {})
    
    # 1. Parse and save inputs
    ref_b64 = job_input.get("reference_image")
    pose_b64 = job_input.get("pose_image")
    prompt_text = job_input.get("prompt", "a beautiful young woman, perfect face")
    negative_text = job_input.get("negative_prompt", "ugly, deformed, noisy, blurry")
    seed = job_input.get("seed", int(time.time() * 1000))
    
    if not ref_b64:
        return {"error": "Missing 'reference_image' in input payload."}

    ref_filename = f"ref_{uuid.uuid4().hex}.jpg"
    pose_filename = f"pose_{uuid.uuid4().hex}.jpg"

    save_base64_image(ref_b64, ref_filename)
    if pose_b64:
        save_base64_image(pose_b64, pose_filename)
    else:
        # Fallback to reference image as pose if not provided (avoids breaking pipeline)
        pose_filename = ref_filename

    # 2. Load the base API workflow JSON
    workflow_path = os.path.join(os.path.dirname(__file__), "sd-ctrlnet-facefusion-api.json")
    with open(workflow_path, "r") as f:
        prompt = json.load(f)

    # 3. Patch the JSON with incoming values
    # These IDs map to the specific nodes in your exported JSON
    try:
        prompt["2"]["inputs"]["text"] = prompt_text
        prompt["3"]["inputs"]["text"] = negative_text
        prompt["7"]["inputs"]["image"] = ref_filename
        prompt["9"]["inputs"]["image"] = pose_filename
        prompt["14"]["inputs"]["seed"] = seed
    except KeyError as e:
        return {"error": f"Workflow JSON structure mismatch on node {str(e)}."}

    # 4. Queue the prompt
    p = {"prompt": prompt, "client_id": str(uuid.uuid4())}
    try:
        res = requests.post(f"{API_URL}/prompt", json=p).json()
        prompt_id = res.get("prompt_id")
        if not prompt_id:
            return {"error": f"Failed to get prompt_id: {res}"}
    except Exception as e:
        return {"error": f"ComfyUI API Request Failed: {str(e)}"}

    # 5. Poll for completion
    timeout = 180 # 3 minutes max execution time
    start_time = time.time()
    while time.time() - start_time < timeout:
        history_res = requests.get(f"{API_URL}/history/{prompt_id}").json()
        
        if prompt_id in history_res:
            # Generation complete
            outputs = history_res[prompt_id].get("outputs", {})
            output_images = []
            
            # Find the SaveImage node output (Node 16)
            for node_id, node_output in outputs.items():
                if "images" in node_output:
                    for img in node_output["images"]:
                        img_filename = img["filename"]
                        # Read from output dir
                        img_path = os.path.join(COMFY_DIR, "output", img_filename)
                        if os.path.exists(img_path):
                            output_images.append(file_to_base64(img_path))
            
            # Return final result
            return {
                "status": "success",
                "images": output_images,
                "seed": seed
            }
        
        time.sleep(2) # Poll every 2 seconds

    return {"error": "Timeout waiting for image generation."}

# Always start ComfyUI up on boot
start_comfyui()

# Start Serverless
runpod.serverless.start({"handler": handler})
