import base64
import requests
import json
import time
import os

# ================= 配置区 =================
API_KEY = os.environ.get("RUNPOD_API_KEY", "")
ENDPOINT_ID = "etsp0v5are7idp"
URL = f"https://api.runpod.ai/v2/{ENDPOINT_ID}/run"

REFERENCE_IMAGE_PATH = "/Users/leo/Desktop/01442-832x1216_Test_pyro_poly_05_DPM++ 2M SDE Heun Exponential_1139559071.png"

def get_base64(filepath):
    try:
        with open(filepath, "rb") as f:
            return base64.b64encode(f.read()).decode('utf-8')
    except FileNotFoundError:
        print(f"❌ 找不到图片: {filepath}")
        exit()

# 如果环境里安装了某些代理软件导致长连接断开，我们强行关闭局域网代理
os.environ['HTTP_PROXY'] = ''
os.environ['HTTPS_PROXY'] = ''

print("1. 正在把图片转码成 Base64...")
b64_face = get_base64(REFERENCE_IMAGE_PATH)

payload = {
    "input": {
        "reference_image": b64_face,
        "prompt": "masterpiece, best quality, ultra detailed, 8k raw photo, photorealistic, sharp focus, intricate details, realistic skin texture, subsurface scattering, 1girl, beautiful young woman, early 20s, long straight dark brown hair, seductive face, heavy blush, furrowed brows, half-closed eyes, ahegao expression, mouth open, tongue sticking out, nude, large natural breasts, erect nipples, slim waist, wide hips, thick thighs, perfect body, squatting position, legs spread wide, knees bent, feet flat on floor, riding a large black dildo, thick veiny black dildo deep inside vagina, dildo base visible, detailed wet pussy, stretched labia, pussy juice dripping down the dildo, glistening fluids, both hands on her lower belly, fingers lightly pressing abdomen, glossy skin, sweat droplets on breasts and belly, realistic skin pores, indoor bedroom setting, white sofa in background, wooden floor, soft natural lighting, depth of field",
        "negative_prompt": "bad anatomy, poorly drawn hands, deformed hands, mutated hands, extra fingers, fused fingers, bad hands, blurry, low quality, worst quality, text, watermark, censored, deformed, ugly, extra limbs, bad proportions, cartoon, painting, overexposed",
        "base_steps": 50,
        "steps": 50,
        "seed": 889934512,
        "use_upscale": True
    }
}

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

print(f"2. 正在把任务丢进 RunPod 异步队列 ({ENDPOINT_ID}) ...")
resp = requests.post(URL, json=payload, headers=headers)
job_data = resp.json()

if "id" not in job_data:
    print("❌ 提交任务失败:", job_data)
    exit()

job_id = job_data["id"]
status_url = f"https://api.runpod.ai/v2/{ENDPOINT_ID}/status/{job_id}"
print(f"✅ 任务下发成功! 任务ID: {job_id}\n")

print("3. 后台大模型开始运转（正在进行冷启动或队列运算），正在监听状态...")
start_time = time.time()
output_url = f"https://api.runpod.ai/v2/{ENDPOINT_ID}/output/{job_id}"

while True:
    try:
        poll_resp = requests.get(status_url, headers=headers, timeout=30)
        poll_data = poll_resp.json()
        status = poll_data.get("status", "UNKNOWN")
        
        print(f"   [状态获取] 当前任务进度: {status}...")
        
        if status == "COMPLETED":
            # 分开拉取 output（RunPod 对大 payload 推荐用 /output 端点）
            print("   [取图] 正在从 output 端点拉取结果...")
            for attempt in range(10):
                try:
                    out_resp = requests.get(output_url, headers=headers, timeout=180)
                    out_data = out_resp.json()
                    print(f"   [取图] output 响应 keys: {list(out_data.keys()) if isinstance(out_data, dict) else type(out_data)}")
                    
                    # 兼容两种响应格式
                    if isinstance(out_data, dict):
                        img_list = out_data.get("images") or (out_data.get("output") or {}).get("images", [])
                    elif isinstance(out_data, list):
                        img_list = out_data
                    else:
                        img_list = []
                    
                    if img_list:
                        with open("v1_output_result.jpg", "wb") as f:
                            f.write(base64.b64decode(img_list[0]))
                        elapsed = round(time.time() - start_time, 2)
                        print(f"\n🎉 爆炸级成功！耗时: {elapsed} 秒。")
                        print(f"高清大图已经保存为 v1_output_result.jpg！")
                        break
                    else:
                        print(f"   [大图重试 {attempt+1}/10] 图片字段为空，原始响应: {str(out_data)[:300]}")
                        time.sleep(3)
                except Exception as e:
                    print(f"   [大图重试 {attempt+1}/10] 获取失败: {e}")
                    time.sleep(3)
            else:
                print("❌ 大图获取失败，已超过最大重试次数。")
            break
            
        elif status == "FAILED":
            print(f"\n❌ 模型后台运算崩溃:\n{json.dumps(poll_data, indent=2)}")
            break
            
        time.sleep(5)
    except Exception as e:
        print(f"   网络波动，5秒后重试: {e}")
        time.sleep(5)


