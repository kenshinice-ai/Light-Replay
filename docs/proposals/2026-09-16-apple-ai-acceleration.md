# 方案：Xcode 27 的端侧 AI 与 Private Cloud Compute 能否加速光境

- 日期：2026-09-16 · 状态：Proposed（只出方案，未改代码）
- 依据：本机 Xcode 27.0（27A266a）与 iOS 27.0 SDK 的接口文件【验】；Apple 开发者页面与 WWDC26 场次 237、241、324【验】；其余标【估】。
- 结论先行：**会加速，但只加速"辅助层"，不碰"测量链"。** 最大的一笔是天空分割可能不用自己训模型了；其次是拍摄教练与结果文案几乎白送。PCC 对 spike 没有加速作用，对 V1.5 的报告与隐私叙事有用，但要现在就去申请资格。

## 1. 本机 SDK 里实际有什么

| 能力 | SDK 中的符号 | 与我们相关的事实 |
|---|---|---|
| 端侧语言模型带图像输入 | `FoundationModels.ImageAttachment`（CGImage / CIImage / CVPixelBuffer / URL）；`LanguageModelCapabilities.vision`、`.toolCalling`、`.guidedGeneration`、`.reasoning`；`supportsLocale` | 任意尺寸，越大越慢；端侧上下文 4K token【引 241】；能力要在运行时查 |
| Private Cloud Compute | `PrivateCloudComputeLanguageModel`：`isAvailable`、`quotaUsage`（`belowLimit` / `limitReached`、`resetDate`）、错误 `quotaLimitReached` / `networkFailure` / `serviceUnavailable` | 同一套 session API；32K 上下文【引 241】；有每用户每日额度，iCloud+ 更高【引 241】；是否支持图像输入需运行时查 `capabilities`【估】 |
| 交互式分割 | `Vision.GenerateIterativeSegmentationRequest`：`seedPoint` / `seedBox` / `seedScribbleBuffer`，可加减点迭代，`qualityLevel`；`DownloadableAssetsRequest`（首次需下载模型） | 输出 PixelBuffer 掩膜；面向"物体"训练，天空是"背景"，效果待验 |
| 采集质量 | `Vision.DetectHorizonRequest`、`DetectLensSmudgeRequest`、`CalculateImageAestheticsScoresRequest` | 地平线角度可与重力方向互查；镜头脏污直接影响分割，值得做成第五盏灯 |
| 自定义端侧模型 | `CoreAI.framework`（`.aimodel`、Xcode 预编译、Instruments）【引 324】 | 天空分割若需自训模型，部署链比 Core ML 顺；接口面本轮未细读 |
| ARKit / RoomPlan | 接口文件未见 iOS 27 新增标记 | 采集链按原规范，不变 |

PCC 资格【验，developer.apple.com/private-cloud-compute】：App Store Small Business Program 成员、任一 App 首次下载少于 200 万、账号获得 PCC entitlement；无云端 API 费用；TestFlight 与 ad hoc 安装不计入下载；超限或退出 SBP 后有 6 个月迁移期。页面未写具体额度与语言。

## 2. 逐层判断：哪里加速，哪里不许碰

| 层 | 现规范做法 | Apple 能力 | 加速判断 | 前提与风险 |
|---|---|---|---|---|
| **天空四态分割** | 自选 Core ML 分割模型 + 手工修正 | `GenerateIterativeSegmentationRequest`，用几何种子自动喂：姿态已知，地平线以上、太阳走廊内的像素带作为 seedScribble；返回的连通区域即天空，边界即天际线；用户点一下加减 | **最大可能的省时：约 1 周**【估】。免训练、免转换，修正交互白送 | 模型面向物体，把天空当"物体"分割效果未知；云、玻璃反射、逆光可能失败；需下载模型资源；每帧延迟未知，先按 3–5 fps 抽帧评估 |
| **玻璃不确定与反射** | 手写启发式（镜像、亮度一致性、深度贴玻璃面） | 端侧 FM 图像理解做**帧级**判断："画面里是否有室内物体的反射 / 窗帘是否拉开 / 天空是否过曝" | 中等：启发式的第一版可以先不写 | 只做每次扫描的关键帧，不做逐帧（端侧 1–3 秒一张【估】）；准确率要对人工标注测 |
| **拍摄教练** | 规则生成一句补拍提示 | FM guided generation + tool calling：把覆盖缺口、漂移、灯状态作为工具结果喂给模型，生成中英双语一句话 | 中等：2–3 天做完，W3 直接受益 | 规则先判断"是否具备判断资格"，模型只负责措辞；不可用时回退到模板句 |
| **结果卡与复看建议** | 模板文案 | FM `@Generable` 结构化输出；SunEngine 作为 Tool，数字只能来自工具结果 | 中等：双语文案质量提升，成本低 | 宪法第 1、2 条：数字不许由模型生成；测试要覆盖"模型改写数字"的回归 |
| **Light Passport 报告文本** | 未定 | PCC 32K 上下文写整页叙述，照片不出 Apple 隐私边界 | V1.5 有用，spike 无关 | 额度未知；资格现在申请；要留 provider 抽象以便迁移 |
| **SunEngine / NorthResolver / 可见域累积 / 投影** | 确定性算法 | 无 | **不加速，也不许碰**（宪法第 1 条、ADR-0002） | 任何 LLM 不进这条链 |
| **效果预览（V2）** | 服务端重打光 | PCC 不跑自定义模型；ImagePlayground 不可控 | 不加速 | 维持原计划 |
| **采集质量灯** | 水平、覆盖、方向、分割 | `DetectLensSmudgeRequest` 作第五盏灯；`DetectHorizonRequest` 与重力互查 | 小而实：半天 | 无 |

## 3. 设备与系统覆盖

| 事实 | 影响 |
|---|---|
| Foundation Models 需要 Apple Intelligence 机型（iPhone 15 Pro 及之后）且已开启、模型资源已下载【估】 | iPhone 12–14 Pro 有 LiDAR 但无 FM：R1 的教练与文案必须有模板回退；分割路径若靠 Vision 则不受此限【估，需真机验证】 |
| 交互式分割首次需下载模型资源 | 首次采集前预下载；无网络时用手工涂抹 |
| 中文输出 | 运行时 `supportsLocale(zh-Hans)` 判定【估】；不通过则英文加模板中文 |
| iOS 27.0 刚发布 | 新 API 有首版风险；spike 只用 iOS 27，V1 最低版本在 spike 后定 |

## 4. 修订后的三周 spike（只列变化）

| 周 | 原计划 | 变化 |
|---|---|---|
| W1 | 采集验证器 + SunEngine；自选分割模型 | **分割改为先评估 `GenerateIterativeSegmentationRequest`**：20 帧人工标注天际线，测 IoU 与每帧延迟；加镜头脏污与地平线两项检查。候选通过线：天际线 IoU ≥ 0.90、失败可识别【估】。不达线才走 CoreAI 自训模型 |
| W2 | 室内、玻璃、NorthResolver | 加一项：FM 图像理解的帧级反射判断，对 30 张人工标注帧测准确率与延迟；只作"玻璃不确定"的辅助信号，不替代像素分割 |
| W3 | PP 真值 | 若 W1、W2 有余量：FM 教练句上线，记录"人工救场分钟"是否下降；不影响通过线 |

其余指标、holdout、否决条件不变。预计净节省约 1 周【估】，主要来自不训模型；若分割评估不过，节省归零但不亏时间（评估本身 1–2 天）。

## 5. 使用边界（拟作 ADR-0010）

允许：分割种子与掩膜（用户可修正）、帧级质量与反射标记、拍摄教练措辞、结果与报告文案（数字来自工具）。
禁止：生成或改写任何小时数、方位、角度；参与太阳、北向、可见域、投影计算；把"未知"说成"确定"。
降级：FM 不可用 → 模板句与规则；分割资源未下载 → 手工涂抹；PCC 额度用尽或不可用 → 端侧或模板；每条降级记入 SceneRecord 的 `quality.flags`。
测试：回归集里加"模型试图改数字"的用例，作为阻断项。

## 6. 需要 Lee 决定

1. **系统版本**：spike 与 V1 都只支持 iOS 27（推荐；简单，且新 API 是加速来源），还是 V1 兼容 iOS 26 并维护分割回退路径。
2. **PCC 资格**：现在就用哪个开发者账号申请 entitlement。推荐用最终上架 App 的主体；若主体未定，先用已在 Small Business Program 的账号申请，TestFlight 测试不计下载。申请是别人的时钟，越早越好。
3. **批准 ADR-0010** 的边界（第 5 节），我再写入 `docs/decisions/` 与 `02-architecture.md` 第 8 节。

## 7. 我可能错在哪

- 交互式分割对"天空"的效果是整个加速的前提，未在真机测过；它面向物体而非背景，可能一测就否。
- 端侧 FM 图像理解的延迟与准确率都是估计；若每张超过 3 秒，帧级反射判断只能在扫描结束后做一次。
- PCC 是否接受图像输入，SDK 里能查但未查；额度未知，不能用于任何高频路径。
- iPhone 12–14 Pro 的覆盖判断来自公开机型规则，未逐机验证。
