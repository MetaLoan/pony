import runpod
import json
import base64
import urllib.request
import urllib.parse
import urllib.error
import time
import os
import subprocess
import subprocess
import os
import io
import boto3
from botocore.config import Config
from PIL import Image

COMFY_HOST = "127.0.0.1:8188"
JSON_WORKFLOW_FILE = "/sd-2xctrlnet-facefusion-api.json"


# ======= R2 上传配置（从环境变量读取，RunPod 后台配置） =======
R2_ENDPOINT    = os.environ.get("R2_ENDPOINT",    "")
R2_ACCESS_KEY  = os.environ.get("R2_ACCESS_KEY",  "")
R2_SECRET_KEY  = os.environ.get("R2_SECRET_KEY",  "")
R2_BUCKET      = os.environ.get("R2_BUCKET",      "candyhub-s")
R2_PUBLIC_URL  = os.environ.get("R2_PUBLIC_URL",  "https://vcdn.sprize.ai")

def get_r2_client():
    return boto3.client(
        "s3",
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_ACCESS_KEY,
        aws_secret_access_key=R2_SECRET_KEY,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"}   # R2 必须用 path-style，否则 AccessDenied
        ),
        region_name="auto"
    )

def upload_image_to_r2(image_bytes, job_id, index, fmt="jpg"):
    """将图片字节流上传到 R2，返回公共 CDN URL"""
    key = f"r/{job_id}_{index}.{fmt}"
    client = get_r2_client()
    client.put_object(
        Bucket=R2_BUCKET,
        Key=key,
        Body=image_bytes,
        ContentType=f"image/{fmt}"
    )
    url = f"{R2_PUBLIC_URL.rstrip('/')}/{key}"
    print(f"[R2] 上传成功: {url}")
    return url

def download_models_if_missing():
    """方案B：解除硬盘锁区，开机冷启动自动高速下载模型到容器"""
    print("=" * 60)
    print("[DIAG-DOWNLOAD] 环境初始化：检查并在需要时从公网拉取基础模型...")
    
    # 定义必须的核心模型字典
    TOKEN = "fd0f3beec0b56c19715e0161cca7505c"
    model_urls = {
        "checkpoints/SDXL_Photorealistic_Mix_nsfw.safetensors": f"https://civitai.com/api/download/models/378684?token={TOKEN}",
        "pulid/ip-adapter_pulid_sdxl_fp16.safetensors": "https://huggingface.co/guozinan/PuLID/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors",
        "upscale_models/4x-UltraSharp.pth": "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth",
        "loras/NSFW_POV_AllInOne.safetensors": f"https://civitai.com/api/download/models/609924?token={TOKEN}",
        "controlnet/controlnet-openpose-sdxl-1.0.safetensors": "https://huggingface.co/thibaud/controlnet-openpose-sdxl-1.0/resolve/main/OpenPoseXL2.safetensors",
        "controlnet/controlnet-depth-sdxl-1.0.safetensors": "https://huggingface.co/diffusers/controlnet-depth-sdxl-1.0/resolve/main/diffusion_pytorch_model.fp16.safetensors"
    }
    
    # 强制将模型存放到 /workspace/models，脱离网络硬盘
    base_dir = "/workspace/models"
    os.makedirs(base_dir, exist_ok=True)
    
    for relative_path, url in model_urls.items():
        target_path = os.path.join(base_dir, relative_path)
        if not os.path.exists(target_path):
            os.makedirs(os.path.dirname(target_path), exist_ok=True)
            print(f"[DIAG-DOWNLOAD] 正在拉取缺失的跨洋模型 (10Gbps+ 内网加速中): {relative_path}")
            try:
                # 尝试用 aria2c 多线程下载 (极大加速)
                subprocess.run(
                    ["aria2c", "-x", "8", "-s", "8", url, "-d", os.path.dirname(target_path), "-o", os.path.basename(target_path)],
                    check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
            except Exception:
                # Fallback 用 wget
                try:
                    subprocess.run(["wget", "-q", url, "-O", target_path], check=True)
                except Exception as e:
                    print(f"[DIAG-DOWNLOAD] ❌ 下载失败: {relative_path} ({e})")
            
            if os.path.exists(target_path):
                print(f"[DIAG-DOWNLOAD] ✅ 下载完成: {relative_path}")
        else:
            print(f"[DIAG-DOWNLOAD] ✅ 模型已就绪: {relative_path}")
    print("=" * 60)

def check_r2_connectivity():
    print("=" * 60)
    print(f"[DIAG-R2] 开始验证 R2 读写权限... Bucket: {R2_BUCKET}")
    masked_key = f"{R2_ACCESS_KEY[:5]}...{R2_ACCESS_KEY[-4:]}" if len(R2_ACCESS_KEY) > 10 else "EMPTY / WRONG!"
    print(f"[DIAG-R2] 当前使用的 Access Key: {masked_key}")
    try:
        client = get_r2_client()
        client.put_object(Bucket=R2_BUCKET, Key="r2_diagnostic_ping.txt", Body=b"ping", ContentType="text/plain")
        print("[DIAG-R2] ✅ R2 连通性测试通过！具备写入权限。")
    except Exception as e:
        print("❌" * 30)
        print(f"[致命错误] R2 权限验证失败: {e}")
        print("!!! 请检查 RunPod 环境变量 (R2_ACCESS_KEY / R2_SECRET_KEY) 是否填写有误，或无 Object Write 权限 !!!")
        print("❌" * 30)
    print("=" * 60)

def auto_configure_models():
    """全盘自动寻址模型目录并动态生成 extra_model_paths.yaml"""
    print("[DIAG-MODELS] 开始全盘自动寻址模型目录...")
    
    model_dirs = {
        "checkpoints": ["checkpoints"],
        "loras": ["loras"],
        "controlnet": ["controlnet"],
        "vae": ["vae"],
        "clip_vision": ["clip_vision"],
        "upscale_models": ["upscale_models"]
    }
    
    # 按优先级搜索：优先看我们挂载的 volume，再看 fallback
    search_roots = ["/runpod-volume/models", "/runpod-volume", "/workspace/models", "/workspace/ComfyUI/models"]
    
    found_paths = {}
    for target_key, target_names in model_dirs.items():
        found = False
        for root in search_roots:
            for name in target_names:
                candidate = os.path.join(root, name)
                if os.path.exists(candidate) and os.path.isdir(candidate):
                    found_paths[target_key] = candidate
                    print(f"[DIAG-MODELS] ✅ 找到 {target_key}: {candidate}")
                    found = True
                    break
            if found: break
        if not found:
            print(f"[DIAG-MODELS] ⚠️  未找到 {target_key}，可能有生图失败风险")
            
    # 生成 extra_model_paths.yaml (基于根目录寻址，绕开必须指定固定前缀的问题)
    yaml_content = "runpod_dynamic_mount:\n  base_path: /\n"
    for k, v in found_paths.items():
        yaml_content += f"  {k}: {v.lstrip('/')}\n"
        
    yaml_path = "/workspace/ComfyUI/extra_model_paths.yaml"
    try:
        with open(yaml_path, "w") as f:
            f.write(yaml_content)
        print(f"[DIAG-MODELS] ✅ 已根据实际寻址动态生成 {yaml_path}:\n{yaml_content}")
    except Exception as e:
        print(f"[DIAG-MODELS] ⚠️  生成 yaml 失败: {e}")
    print("=" * 60)

def start_comfyui():
    """点火：在后台启动真正的 ComfyUI 引擎"""
    print("🚀 正在后台启动 ComfyUI 核心进程...")
    
    # 先建立 Network Volume 的 symlinks（pulid/insightface/DWPose）
    if os.path.exists("/workspace/setup_volume_links.sh"):
        print("🔗 建立 Volume symlinks...")
        subprocess.run(["/bin/bash", "/workspace/setup_volume_links.sh"], check=False)
    
    # 将 stdout/stderr 写入文件以便调试
    log_out = open("/workspace/comfy_stdout.log", "w")
    log_err = open("/workspace/comfy_stderr.log", "w")
    
    cmd = [
        "python3", "/workspace/ComfyUI/main.py",
        "--listen", "127.0.0.1",
        "--port", "8188",
        "--disable-auto-launch",
        "--extra-model-paths-config", "/workspace/ComfyUI/extra_model_paths.yaml"
    ]
    subprocess.Popen(cmd, stdout=log_out, stderr=log_err)



def wait_for_comfyui(timeout=180):
    """冷启动保险：在 ComfyUI 服务就绪之前阻塞，最多等 timeout 秒"""
    print("⏳ 等待 ComfyUI 启动就绪...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            req = urllib.request.Request(f"http://{COMFY_HOST}/system_stats")
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    print(f"✅ ComfyUI 已就绪（等待了 {round(time.time()-start, 1)} 秒）")
                    return True
        except Exception:
            pass
        time.sleep(2)
    # 超时：把 ComfyUI 的错误日志打出来方便调试
    try:
        with open("/workspace/comfy_stderr.log", "r") as f:
            print("[ComfyUI STDERR]\n" + f.read()[-3000:])
        with open("/workspace/comfy_stdout.log", "r") as f:
            print("[ComfyUI STDOUT]\n" + f.read()[-2000:])
    except Exception as log_err:
        print(f"[无法读取 ComfyUI 日志: {log_err}]")
    raise RuntimeError("❌ ComfyUI 在超时时间内没有启动！")

def get_base_workflow():
    with open(JSON_WORKFLOW_FILE, "r") as f:
        return json.load(f)

def queue_prompt(prompt):
    p = {"prompt": prompt}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"❌ ComfyUI Rejected Prompt (400): {error_body}")
        raise Exception(f"ComfyUI_Error: {error_body}")

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
    wait_for_comfyui()   # 🔒 冷启动保险，确保 ComfyUI 内核已完全就绪
    job_input = job.get('input', {})
    job_id = job.get('id', 'unknown')   # RunPod 任务 ID，用于 R2 文件命名
    
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
    
    # ======= 参数映射 (带严格类型保护) =======
    # 正负文本 (2, 3)
    if "prompt" in job_input and "2" in prompt: 
        prompt["2"]["inputs"]["text"] = str(job_input["prompt"])
    if "negative_prompt" in job_input and "3" in prompt: 
        prompt["3"]["inputs"]["text"] = str(job_input["negative_prompt"])
    
    # Base 一阶段 (Node 22)
    if "22" in prompt:
        prompt["22"]["inputs"]["steps"] = int(job_input.get("base_steps", 8))
        prompt["22"]["inputs"]["seed"] = int(job_input.get("base_seed", 967549018325766))
        prompt["22"]["inputs"]["sampler_name"] = str(job_input.get("base_sampler_name", "dpmpp_2m_sde"))
        prompt["22"]["inputs"]["scheduler"] = str(job_input.get("base_scheduler", "karras"))
        
    # Main 二阶段 (Node 14)
    if "14" in prompt:
        prompt["14"]["inputs"]["steps"] = int(job_input.get("steps", 50))
        prompt["14"]["inputs"]["cfg"] = float(job_input.get("cfg", 4.0))
        prompt["14"]["inputs"]["seed"] = int(job_input.get("seed", 387730445953839))
        prompt["14"]["inputs"]["sampler_name"] = str(job_input.get("sampler_name", "dpmpp_2m_sde"))
        prompt["14"]["inputs"]["scheduler"] = str(job_input.get("scheduler", "karras"))
    
    # 骨骼网控制强度 (Node 12: Depth, Node 26: OpenPose)
    if "12" in prompt:
        prompt["12"]["inputs"]["strength"] = float(job_input.get("cn_depth_strength", 0.6))
    if "26" in prompt:
        prompt["26"]["inputs"]["strength"] = float(job_input.get("cn_pose_strength", 0.6))
    
    # Empty Latent Image (Node 13) - 分辨率控制
    if "13" in prompt:
        prompt["13"]["inputs"]["width"] = int(job_input.get("width", 832))
        prompt["13"]["inputs"]["height"] = int(job_input.get("height", 1216))
        
    # PuLID (Node 8)
    if "8" in prompt:
        prompt["8"]["inputs"]["weight"] = float(job_input.get("pulid_weight", 0.8))
        prompt["8"]["inputs"]["end_at"] = float(job_input.get("pulid_end_at", 1.0))
        prompt["8"]["inputs"]["method"] = str(job_input.get("pulid_method", "fidelity"))
        
    # 执行
    try:
        ws_res = queue_prompt(prompt)
        prompt_id = ws_res['prompt_id']
        
        while True:
            time.sleep(2)
            history = get_history(prompt_id)
            if prompt_id in history:
                break
                
        # 提图 + 上传 R2
        output_urls = []
        errors = []
        outputs = history[prompt_id]['outputs']
        # job_id 已在 handler 入口获取，此处直接使用
        
        print(f"[DEBUG] 任务完成，outputs 包含节点: {list(outputs.keys())}")
        
        img_index = 0
        for node_id, node_output in outputs.items():
            if 'images' in node_output:
                print(f"[DEBUG] 节点 {node_id} 含有图片，数量: {len(node_output['images'])}")
                for image in node_output['images']:
                    try:
                        image_data = get_image(image['filename'], image['subfolder'], image['type'])
                        # 压缩为 JPEG
                        pil_img = Image.open(io.BytesIO(image_data)).convert("RGB")
                        buf = io.BytesIO()
                        pil_img.save(buf, format="JPEG", quality=85, optimize=True)
                        jpeg_bytes = buf.getvalue()
                        print(f"[DEBUG] 节点 {node_id} 压缩后大小: {len(jpeg_bytes)/1024:.1f} KB")
                        
                        # 上传到 R2
                        url = upload_image_to_r2(jpeg_bytes, job_id, img_index, fmt="jpg")
                        output_urls.append(url)
                        img_index += 1
                    except Exception as img_err:
                        err_msg = f"节点 {node_id} 图片处理失败: {img_err}"
                        print(f"[DEBUG] {err_msg}")
                        errors.append(err_msg)
            else:
                print(f"[DEBUG] 节点 {node_id} 无图片输出")
                
        if not output_urls:
            print("[DEBUG] output_urls 为空！请检查上方节点信息。")
                     
        return {"urls": output_urls, "errors": errors}
        
    except Exception as e:
        return {"error": str(e)}


# ================= 启动点 =================
# 先进行环境自检和模型自动寻址
check_r2_connectivity()
download_models_if_missing()
auto_configure_models()
start_comfyui()

runpod.serverless.start({"handler": handler})
