import runpod
import json
import base64
import urllib.request
import urllib.parse
import time
import os

COMFY_HOST = "127.0.0.1:8188"
JSON_WORKFLOW_FILE = "/sd-2xctrlnet-facefusion-api.json"

def get_base_workflow():
    with open(JSON_WORKFLOW_FILE, "r") as f:
        return json.load(f)

def queue_prompt(prompt):
    p = {"prompt": prompt}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read())

def get_image(filename, subfolder, folder_type):
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    req = urllib.request.Request(f"http://{COMFY_HOST}/view?{url_values}")
    with urllib.request.urlopen(req) as response:
        return response.read()

def get_history(prompt_id):
    req = urllib.request.Request(f"http://{COMFY_HOST}/history/{prompt_id}")
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read())

def save_b64_image(b64_str, temp_filename):
    img_data = base64.b64decode(b64_str)
    filepath = f"/workspace/ComfyUI/input/{temp_filename}"
    with open(filepath, "wb") as f:
        f.write(img_data)
    return temp_filename

def handler(job):
    job_input = job.get('input', {})
    
    # 动态参数映射表
    b64_ref = job_input.get("reference_image")
    b64_pose = job_input.get("pose_image")
    
    use_upscale = job_input.get("use_upscale", False)
    use_lora = job_input.get("use_lora", True)
    
    prompt = get_base_workflow()
    
    # ======= 图片输入 =======
    if b64_ref:
        ref_filename = save_b64_image(b64_ref, "runpod_ref.jpg")
        if "7" in prompt: prompt["7"]["inputs"]["image"] = ref_filename
    
    # ======= 高级控制：pose_image 决定骨架来源 =======
    if b64_pose:
        # 用户亲自传了骨架图：跳过第一轮生图，直接拿骨架！
        pose_filename = save_b64_image(b64_pose, "runpod_pose.jpg")
        # 把 Node 10(Depth) 和 Node 24(DWPose) 的输入统统改成 LoadImage(Node 9)
        if "10" in prompt: prompt["10"]["inputs"]["image"] = ["9", 0]
        if "24" in prompt: prompt["24"]["inputs"]["image"] = ["9", 0]
        if "9" in prompt: prompt["9"]["inputs"]["image"] = pose_filename
        
        # 既然不用一阶段底图了，删除相关冗余节点节约算力
        for drop_uid in ["22", "23", "27"]:
            if drop_uid in prompt: del prompt[drop_uid]
    else:
        # 用户没传骨架图：删除预设的 LoadImage(Node 9)，骨架全部从一阶段(Node 23)提
        if "9" in prompt: del prompt["9"]
        if "10" in prompt: prompt["10"]["inputs"]["image"] = ["23", 0]
        if "24" in prompt: prompt["24"]["inputs"]["image"] = ["23", 0]
        
    # ======= 超清放大模块（手工复原 Node 19） =======
    if use_upscale:
        # 原版 JSON 只有 18(Loader)，15(VAEDecode)，16(SaveImage)。在此强接 19
        prompt["19"] = {
            "inputs": {
                "upscale_model": ["18", 0],
                "image": ["15", 0]
            },
            "class_type": "ImageUpscaleWithModel",
            "_meta": {"title": "使用模型放大图像"}
        }
        # 将 SaveImage 节点重定向到 Node 19 的输出
        if "16" in prompt: prompt["16"]["inputs"]["images"] = ["19", 0]
    else:
        # 如果不开超分，直接删掉 18，SaveImage 原封不动吃 Node 15 的图
        if "18" in prompt: del prompt["18"]
        if "19" in prompt: del prompt["19"]
        if "16" in prompt: prompt["16"]["inputs"]["images"] = ["15", 0]
        
    # ======= 动态多重 LoRA 链 =======
    loras = job_input.get("loras")
    
    # 兼容老版本参数
    if loras is None:
        if use_lora:
            legacy_name = job_input.get("lora_name", "NSFW_POV_AllInOne.safetensors")
            if "20" in prompt and "lora_name" in prompt["20"]["inputs"]:
                legacy_name = job_input.get("lora_name", prompt["20"]["inputs"]["lora_name"])
            loras = [{"name": legacy_name, "strength": job_input.get("lora_strength", 1.0)}]
        else:
            loras = []
            
    # 摧毁预设的单体 Node 20
    if "20" in prompt:
        del prompt["20"]
        
    last_model = ["1", 0]
    last_clip = ["1", 1]
    
    # 动态组装无限长度的 LoRA 节点链
    for idx, lora_info in enumerate(loras):
        node_id = f"20{idx}"
        prompt[node_id] = {
            "inputs": {
                "lora_name": lora_info["name"],
                "strength_model": lora_info.get("strength", 1.0),
                "strength_clip": lora_info.get("strength", 1.0),
                "model": last_model,
                "clip": last_clip
            },
            "class_type": "LoraLoader",
            "_meta": {"title": f"Dynamic_Lora_{idx}"}
        }
        last_model = [node_id, 0]
        last_clip = [node_id, 1]
        
    # 把 LoRA 终点强行塞入到主干网的入口
    if "22" in prompt: prompt["22"]["inputs"]["model"] = last_model
    if "8" in prompt: prompt["8"]["inputs"]["model"] = last_model
    if "2" in prompt: prompt["2"]["inputs"]["clip"] = last_clip
    if "3" in prompt: prompt["3"]["inputs"]["clip"] = last_clip
    
    # ======= 参数映射 =======
    # 正负文本 (2, 3)
    if "prompt" in job_input and "2" in prompt: prompt["2"]["inputs"]["text"] = job_input["prompt"]
    if "negative_prompt" in job_input and "3" in prompt: prompt["3"]["inputs"]["text"] = job_input["negative_prompt"]
    
    # Base 一阶段 (Node 22)
    if "22" in prompt:
        prompt["22"]["inputs"]["steps"] = job_input.get("base_steps", prompt["22"]["inputs"].get("steps", 8))
        prompt["22"]["inputs"]["seed"] = job_input.get("base_seed", prompt["22"]["inputs"].get("seed", 967549018325766))
        
    # Main 二阶段 (Node 14)
    if "14" in prompt:
        prompt["14"]["inputs"]["steps"] = job_input.get("steps", prompt["14"]["inputs"].get("steps", 50))
        prompt["14"]["inputs"]["cfg"] = job_input.get("cfg", prompt["14"]["inputs"].get("cfg", 4))
        prompt["14"]["inputs"]["seed"] = job_input.get("seed", prompt["14"]["inputs"].get("seed", 387730445953839))
    
    # PuLID (Node 8)
    if "8" in prompt:
        prompt["8"]["inputs"]["weight"] = job_input.get("pulid_weight", prompt["8"]["inputs"].get("weight", 0.8))
        prompt["8"]["inputs"]["end_at"] = job_input.get("pulid_end_at", prompt["8"]["inputs"].get("end_at", 1.0))
        
    # 执行
    try:
        ws_res = queue_prompt(prompt)
        prompt_id = ws_res['prompt_id']
        
        while True:
            time.sleep(2)
            history = get_history(prompt_id)
            if prompt_id in history:
                break
                
        # 提图逻辑
        output_images = []
        outputs = history[prompt_id]['outputs']
        
        for node_id, node_output in outputs.items():
            if 'images' in node_output:
                for image in node_output['images']:
                    image_data = get_image(image['filename'], image['subfolder'], image['type'])
                    b64_img = base64.b64encode(image_data).decode('utf-8')
                    # 我们只要最高清的最终成品流（Node 16）或者放大终点返回
                    output_images.append(b64_img)
                    
        return {"images": output_images}
        
    except Exception as e:
        return {"error": str(e)}

runpod.serverless.start({"handler": handler})
