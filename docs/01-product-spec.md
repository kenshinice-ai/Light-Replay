# 01 · 产品规范：三个任务、Inspect 模式、结果页

版本 0.2 · 2026-09-30（0.1 于 2026-09-10）· 对应蓝图 §1、§3、§5；ADR-0012 至 0016

## 1. 用户与三个任务

| 阶段 | 用户的问题 | 产品给什么 | 时间预算 |
|---|---|---|---|
| **Before · Prep** | 我要去看这套房，该注意什么？ | 3 things worth noticing；建议 OneTake 的点；看房时刻的太阳位置 | 1 分钟 |
| **During · Inspect** | 我只有 20 分钟，帮我记住真正重要的 | Capture / Note / Measure；Like / Concern / Ask | ≤ 3 分钟额外操作 |
| **After · Replay · Compare · Ask** | 看了 6 套，哪一套更符合我的生活？ | Your inspection；Replay · Light；Compare；Ask next | 回家后 |

首批用户：正在比较住宅、有明确日照或空间问题的自住买家与租客（墨尔本、悉尼）。以任务招募，不以族裔或"喜欢科技"招募。Paradise Production 的采集员是第二类用户（`09-light-passport.md`）。

## 2. Add：把一套房带进来

- **Share Extension**：在 REA、Domain、Safari、Messages 里 Share → Property Replay。只读取用户明确分享的 URL、截图、PDF；URL 解析地址 slug；截图 / PDF 走端侧 OCR + FM 抽取（Indicative），用户确认后建档（ADR-0014）。
- **手动**：输入地址（G-NAF 校验）。
- 建档后 Property 页出现：hero 图（用户分享的或自己拍的）、地址、来源标签、Prep。
- 不做：抓取门户；持续 preload；planning / hazard。

## 3. Prep：3 things worth noticing

只显示三条，每条带等级与"怎么验证"：

1. **主要窗朝向**（Indicative）：来自建筑轮廓 + 用户分享的户型；"客厅窗大约朝西北，冬天下午的直射取决于邻居"。
2. **看房时刻的太阳**（几何 Verified，遮挡 Unknown）："周六 11:20 太阳在东北 45°，客厅窗此时无直射；你看到的会是这间房最暗的样子之一。"
3. **建议测的点**："客厅沙发位、主卧床头、后院座位"，并说明为什么。

按钮：Start inspection。

## 4. Inspect 模式（ADR-0015）

相机式界面，房产名与当前房间在顶部，底部三个动作，没有模式选择：

| 动作 | 用户做什么 | 系统记什么 | 产出 |
|---|---|---|---|
| **Capture** | 拍一张 | 时刻、位置与精度、朝向候选、设备姿态、可选房间标签 | Observation（user_photo，Observed·noted） |
| **Note** | 按住说话 | 端侧转写；FM 结构化为 room / category / sentiment / text / followUp；原文保留可编辑；不存音频 | Observation（user_voice，Observed·noted）；followUp → Question |
| **Measure** | 站到会生活的位置，按 `04-capture-protocol.md` 做 OneTake | SceneRecord | LightObservation（sensor，等级按 R1 结果映射） |

- 三个快速标签：Like / Concern / Ask。Ask 自动生成 Question。
- 五盏质量灯（水平与追踪、走廊覆盖、方向、分割、镜头）只在 Measure 时出现；任一阻断只出 R0，且界面说明原因。
- 房间标签：可选，来自户型 L0 的手工房间列表或 FM 候选（Indicative，用户确认后 Verified）。
- 权限按需：相机在 Start inspection；麦克风在第一次 Note；定位在建档或 Measure；相册在导入。

## 5. Your inspection（After）

离开房子后的首页不是报告，是记忆：

- **You liked**：Like 标签的观察，按房间。
- **You were unsure about**：Concern。
- **Ask next**：Ask 与 followUp 生成的 Question，标注问谁（agent / conveyancer / inspector）。
- **Replay**：Light（有 LightObservation 时）、Space（V2）。
- **Compare**：加入 shortlist。

语言是个人的："你标记了卧室 2 为 concern"，不是"卧室 2 评分 3/5"。

## 6. Replay · Light（R1 结果页）

- **照片区**：OneTake 的 Hero frame；Target Pin；当前时刻的太阳方向指示（画方向，不画假光斑）。
- **时间滑杆**：当天 24 小时；太阳方向随动；时段条游标同步；日出、正午、日落、进出直射处有 haptic。
- **日期**：冬至、夏至、春秋分快捷；任意日期。
- **时段条**：四色。稳定直射 / 方向敏感 / 遮挡 / 资料不足。
- **全年热力图**：日 × 小时，四态。
- **三段式结论**（Codex §23 的措辞）：
  - **What**："6 月 21 日约 10:40–14:10 直射（10:40–11:00 对方向敏感）" · Observed·measured
  - **Why**："西北窗；14:10 后西侧建筑遮挡（实测）；7 月太阳高度 28°"
  - **Verify**："若想确认 11:00 前的边界，晴天 10:30–11:15 回到同一点看一眼；或向中介要冬季照片"
- **证据卡**（每个数字可展开）：来源、算法版本、覆盖率、未知比例、五灯状态、北向来源与 σ、采集日期、未计入项（窗帘、玻璃透光率、活动遮阳、云）。

措辞：给区间，不给小数点；标注采集日期；不写"以实测为准"，写"实测通过质量检查"；分歧写"待复核"。

## 7. R2 潜力光斑（V2，LiDAR 机型）

在 R1 之上，用 RoomPlan 的窗四角与地面平面沿太阳向量投影窗多边形；虚线半透明，标签"潜力投影：未计窗外遮挡的视差"（Indicative）。时段仍来自 R1。

## 8. Compare

- 用户设五个优先级（Natural light、Privacy、Quiet、Space、Backyard、School、Commute、Renovation potential、Price comfort 中选）。
- 两到三套并排；每格是用户评分或可解释指标，带等级与来源：Light 一格来自 R1 冬至稳定直射小时（Observed·measured），未测显示 Unknown。
- 不做总分、不做排序、不做"AI 推荐"。

## 9. 分享页

默认包含：时段条、热力图、三段式结论、证据卡摘要、采集日期、目标点标签。默认不含：原片、精确门牌、EXIF。链接可撤销；更正后旧链接显示更正状态。

## 10. 参考模式（R0）

导入照片或只输入地址：画太阳弧与方向；允许手工设北向；**不输出小时数**。用于"先看看"，也是无权限时的兜底。

## 11. 降级矩阵

| 条件 | 行为 |
|---|---|
| 系统低于 iOS 27 | 不支持（ADR-0011） |
| 无 LiDAR | R1 可用；漂移按阈值处理并标注；R2 不可用 |
| 非 Apple Intelligence 机型，或未开启、资源未下载、语言不支持 | 教练句与文案用模板；语音只转写不结构化（用户手工选 room / category）；结果不变 |
| 分割模型资源未下载 | 手工涂抹天空区域；标注"手工分割" |
| 无精确定位 | 用户在地图点位置；位置来源标"手工" |
| 方向来源全部无效或冲突未确认 | 只出 R0 |
| 追踪丢失、运动模糊 | 该段帧不并入；覆盖率相应下降 |
| PCC 不可用或额度用尽 | 报告文本改端侧或模板 |

## 12. 不出结果的情况

以下任一出现时，只显示 R0 与原因，不显示小时数：走廊覆盖率低于门槛；方向来源冲突且未确认；玻璃反射污染且未识别为未知；漂移超出可修正范围；镜头明显脏污。**错误却确定的输出是阻断性缺陷。**

## 13. V1 不做

R2 光斑；户型自动识别与配准；Listing-to-Inspection Delta；couple 模式；Domain API；planning / hazard；气候概率；天气氛围；写实重打光；Sound lens；连续录音；价格；贷款或法律内容；黑盒总分。
