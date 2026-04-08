# AnyPose API v16 接入指南 (Dual-Pass 引擎)

V16 带来了革命性的两段式出图引擎：它会自动在后台跑第一遍低步数出图用以抓取 3D 骨架，再跑第二遍高精度融合出图。本版新增支持动态跳过、超高清复原以及参数全量接管功能！

## 🎯 Endpoint URL
`POST https://api.runpod.ai/v2/{你的ENDPOINT_ID}/runsync` (生产环境中建议改用后台 `/run` 异步队列轮询)
**Headers**:
- `Content-Type`: `application/json`
- `Authorization`: `Bearer {YOUR_API_KEY}`

## 📦 JSON Payload (全部可选，不填则走 JSON 设定缺省值)

### 方案一：极简无脑调用版（强推前端直接用）
如果你只想换脸，其他都不想管，就发这三个字段，剩下的全是默认的顶级效果！
```json
{
  "input": {
    "reference_image": "base64...",   
    "prompt": "masterpiece, 1girl, smiling...",
    "width": 832,
    "height": 1216
  }
}
```

### 方案二：全掌控进阶版（所有参数均可控）
```json
{
  "input": {
    "reference_image": "base64...",   // [强烈建议传] 换脸源底图 (如果不传，就用默认网图)
    "pose_image": "base64...",        // [可选] 姿态控制图
    
    // 💡 提示词与分辨率引擎
    "prompt": "masterpiece, 1girl...", // [可选] 主提示词 (缺省使用原设的大段 NSFW tag)
    "negative_prompt": "ugly...",      // [可选] 负向提示词
    "width": 832,                      // [可选] 图像生成基础宽度 (默认: 832)
    "height": 1216,                    // [可选] 图像生成基础高度 (默认: 1216)
    
    // 💡 工作流全局阀门
    "use_upscale": true,              // [可选] 是否强行启动 4x-UltraSharp 放大 (缺省: false)
    
    // 💡 动态多层 LoRA 叠加控制 (革命性更新)
    // 你可以传入0个、1个甚至5个LoRA，系统会自动把它们按顺序串联！如果不传则默认走单开 NSFW_POV
    "loras": [
      {
        "name": "NSFW_POV_AllInOne.safetensors",
        "strength": 1.0
      },
      {
        "name": "Beauty_Slider.safetensors",
        "strength": 0.8
      }
    ],
    
    // 💡 核心模型参变： 第一阶段 (打底图阶段)
    "base_steps": 8,                  // [可选] 生成骨架底图所用的步数 (默认: 8)
    "base_seed": 967549018325766,     // [可选] 第一阶段种子 (如果想固定同一个动作，锁定此值)
    "base_sampler_name": "dpmpp_2m_sde", // [可选] 第一阶段采样器 (默认: dpmpp_2m_sde)
    "base_scheduler": "karras",       // [可选] 第一阶段调度器 (默认: karras)
    
    // 💡 核心模型参变： 第二阶段 (精细换脸生成阶段)
    "steps": 50,                      // [可选] 最终成图步数 (默认: 50)
    "cfg": 4,                         // [可选] CFG (默认: 4.0)
    "seed": 387730445953839,          // [可选] 最终成图种子 (决定脸部与光影细节)
    "sampler_name": "dpmpp_2m_sde",   // [可选] 第二阶段采样器 (默认: dpmpp_2m_sde，想皮肤柔和可换 euler_a)
    "scheduler": "karras",            // [可选] 第二阶段调度器 (默认: karras)
    
    // 💡 强制姿态介入强度 (极度重要：当输入 pose_image 时)
    "cn_depth_strength": 0.6,         // [可选] 深度轮廓控制力，如果头转不过来请加到 0.8+ (默认: 0.6)
    "cn_pose_strength": 0.6,          // [可选] 肢体动作控制力，同上 (默认: 0.6)
    
    // 💡 面部锁固控制 (PuLID)
    "pulid_weight": 0.8,              // [可选] 面像融合权重，越高长得越像 (默认: 0.8)
    "pulid_end_at": 1.0,              // [可选] 断联阈值，如果发现做不了大表情，建议降到 0.4 (默认: 1.0)
    "pulid_method": "fidelity"        // [可选] 换脸模式：fidelity为骨相死锁锁死，style为神韵相似做大表情首选 (默认: fidelity)
  }
}
```

## 🧠 黑科技行为剖析：`pose_image` 阀门

这是 V16 版本独有的高级动态接力器。

- **情景 A：当 `pose_image` 留空时（默认行为）**
  服务器会默默跑两次：使用 `base_seed` 和 `base_steps` (8步) 先生出一张粗糙草图，然后抽调出深度结构和人体骨架给 ControlNet，最后才跑出 50 步的女主高清脸。这是**“极度吃动作 Prompt”**的玩法。

- **情景 B：当传入图片 base64 给 `pose_image` 时**
  服务器感应到外来干预，**会立刻砍掉和跳过第一阶段的 8 步虚空造影**（帮你节约算力）！这说明你极其明确想要仿照你在 `pose_image` 里的姿势，服务器会直接提你上传图的骨架并套在女主角身上开始作画。

## ⚠️ 参数截留提醒
你具有这台机器 **100% 的生杀大权**。通过调节 Payload，你能跳过 Lora、能随时开启 4K 放大，你的每一个键值传进去，网关 `handler.py` 都会对默认的 JSON 工作流实现“移花接木”硬覆盖。如果不传，服务器将老老实实按照你给的 JSON V3 原版数据输出。
