# 02 · 架构：模块、数据流、坐标系

版本 0.1 · 2026-09-10

## 1. 模块

| 模块 | 首版责任 | 明确不做 | 阶段 |
|---|---|---|---|
| **SceneRecord** | 数据模型、JSON 编解码、版本迁移、来源字段 | 存业务逻辑 | Spike |
| **CaptureCore** | ARSession 封装；Hero frame；逐帧姿态、内参、时间戳；深度与置信度；镜头锚点与漂移；曝光控制；质量状态 | 把不同时间戳的照片、深度、姿态硬拼成一个事实 | Spike |
| **VisibilityCore** | 天空 / 遮挡 / 未知 / 玻璃不确定 四态分割适配（首选 Vision `GenerateIterativeSegmentationRequest` + 几何种子；备选 CoreAI 自训模型）；像素到方向；深度重投影到目标点；可见域网格累积；走廊覆盖率 | 把反射或未扫区域默认为天空 | Spike |
| **NorthResolver** | 方向候选采集；独立组；鲁棒融合；冲突检测；yaw 分布 | 把同一磁传感器的两个读数当独立证据 | Spike |
| **SunEngine** | 太阳位置（SPA）；时区与夏令时；采样；走廊生成；直射状态；时段分级 | 用语言模型算太阳 | Spike |
| **GeometryCore** | RoomPlan windows；AR 平面；R2 投影 | 让 LiDAR 假装看见邻楼 | V2 |
| **Assist** | 关键帧反射与过曝标记（FM 图像理解）；补采提示（guided generation）；结果与报告文案（数字来自 Tool）；`LLMProvider` 抽象（端侧 / PCC / 模板） | 生成或改写任何数字；进入太阳、北向、可见域、投影计算（ADR-0010） | V1 |
| **report/** | 分享页只读渲染 | 计算 | V1 |

## 2. 数据流

```
ARSession ──帧──► CaptureCore ──► SceneRecord.capture_session（帧、姿态、深度引用、漂移）
                       │
                       ├─► VisibilityCore ──► SceneRecord.visibility（AR 方位 × 高度 四态网格）
                       │
                       └─► NorthResolver ──► SceneRecord.north（候选、融合 yaw、σ、冲突）

查询（日期范围、时段、情景） ──► SunEngine
      读 visibility + north.resolved + location + timezone
      ──► AnalysisResult（时段分级、热力图、敏感边界、未知区间、算法版本、输入哈希）
```

## 3. 坐标系

| 坐标系 | 定义 | 用途 |
|---|---|---|
| 图像 | 像素 (u, v)，内参 fx fy cx cy | 分割掩膜 |
| 设备 / 相机 | ARKit camera transform | 像素射线 |
| AR 世界 | 重力对齐，yaw 任意，原点为会话起点 | 可见域存储；目标锚点；平面法线 |
| 真北 ENU | East-North-Up | 太阳向量 |

关键约定：**可见域以 AR 世界方位角存储**。`az_ar` 从 AR 世界 −Z 轴起算，俯视顺时针；真北方位角 `az_true = (az_ar + Δ) mod 360`，`Δ` 是 −Z 轴的真方位角，由 NorthResolver 给出并带 σ（定义见 `05-north-resolver.md` 第 4 节）。北向修正只改 `Δ`，不改采集。

像素到方向：

- `r_cam = F · K⁻¹ [u v 1]ᵀ`，`F = diag(1, −1, −1)`：把针孔约定（y 向下、z 朝前）换成 ARKit 相机约定（y 向上、看向 −z）。`(u, v)` 是 `capturedImage` 原生方向（横向）的像素坐标；分割若在旋转后的图像上运行，先把掩膜坐标转回。
- `r = R_cam · r_cam`（`R_cam` 为 camera transform 的旋转部分）。`r` 不归一化：它沿光轴的分量为 1，供深度重投影使用。
- `d̂ = r / |r|`；方位角 `az_ar = atan2(d̂_x, −d̂_z)`，高度角 `alt = asin(d̂_y)`。

深度重投影（LiDAR）：`sceneDepth` 的 `z` 是沿光轴的深度。若 `z < D_near`（候选 4 m），遮挡点 `p = c_cam + z · r`，改用 `d' = normalize(p − p_target)` 落网格。远于 `D_near` 或无深度：直接用 `d̂`，并记录漂移 `|c_cam − p_target|`。

## 4. 端侧与服务端

- V1 全部计算在设备端；分享页只渲染已算好的 AnalysisResult。
- 云端不保存原片，除非用户主动上传。
- V1.5 的地址级粗估在服务端（`engine/`），结果作为"看房前预估"进入 SceneRecord 的 `context`，与实测并列。

## 5. 版本与可复现

- 每个 AnalysisResult 记录：SunEngine 版本、分割模型版本、NorthResolver 版本、输入哈希。
- 同一 SceneRecord 在不同版本下重算，差异要能解释；把"未知被说成确定"设为回归测试的阻断项。

## 6. 测试策略

| 层 | 方法 | 环境 |
|---|---|---|
| SunEngine | 与 pvlib / NOAA 表对照；时区与夏令时边界；南北半球 | 模拟器 / CI |
| VisibilityCore 累积 | 合成掩膜与已知姿态；深度重投影的几何单元测试 | 模拟器 |
| NorthResolver | 合成候选：一致、轻度分歧、冲突、只有一个来源、跨 0°/360°、磁罗盘单独偏离、高可信组单独偏离、只有一组且 σ > 6°、solar 残差不通过 | 模拟器 |
| 坐标约定 | 物理对照夹具：按 `gravityAndHeading` 构造的合成场景 Δ = 0；−Z 朝东的合成场景中，朝西的窗得到下午直射；水平相机画面上沿像素的高度角等于半个垂直视场角。期望值来自物理事实，不来自规范 | 模拟器 / CI |
| CaptureCore | 真机：帧同步、追踪丢失、漂移记录 | 真机 |
| 分割路径 | 20 帧人工标注天际线：IoU、每帧延迟、失败可识别率（ADR-0010） | 真机 |
| Assist 回归 | 合成工具结果，检查模型输出是否改写数字或把未知说成确定；命中即阻断 | 模拟器 / CI |
| 端到端 | 现场延时对照（`08-ground-truth-protocol.md`） | 现场 |

## 7. 性能预算（估，spike 校准）

- 扫描期间：分割每秒 3–10 帧即可（交互式分割的实际延迟 W1 测），其余帧只记姿态；FM 图像理解只在关键帧运行。
- 全年计算：5 分钟步长 × 365 天 ≈ 10.5 万样本，逐样本查表，目标 < 100 ms。
- 时段分级的 yaw 采样（候选 64 组）：目标 < 1 s。

## 8. 端侧 AI 的位置

当系统知道"某个 14°×8° 的天空区域会决定冬季 9–10 点的答案，但当前被反射污染"，Assist 把它翻译成一句动作："稍微降低曝光，向左补扫这里。" 它让测量更容易完成，不决定太阳在哪。允许、禁止、降级与回归的完整边界见 ADR-0010；系统版本见 ADR-0011。
