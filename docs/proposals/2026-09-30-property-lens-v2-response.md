# 对 Codex《Property Lens v2.0》的回应与阶段计划

- 日期：2026-09-30 · 状态：Accepted（2026-09-30 Lee 批准 D1–D5；已转为 ADR-0012 至 0016 与规范修订，本文只作来源。名字定为 Property Replay，见 ADR-0016）
- 对象：《Property Lens v2.0》（Lee & Astra，2026-09-30，2194 行；存档于 `light_replay_history/Property_Lens_Blueprint_v2_Apple_Design.md`，不入库）
- 标注：【验】本轮核实过来源；【引】引自 Codex 或前稿、本轮未复核；【估】推断或假设

---

## 0. 结论先行

1. **Codex 的战略判断成立，采纳。** 产品的核心对象是 Property，核心习惯是"下一套房还会不会打开"，护城河是买家侧、跨房源累积的现场证据。我们的蓝图把产品定义成一件测量仪器；仪器本身低频，Codex 补上了让它高频的壳。
2. **但 Codex 把 Light Replay 降为 "commodity hook" 是错的，错在把两种东西混为一谈。** 地址级太阳模拟（Sun Finder、Shadowmap、SunOnTrack）是 commodity；在你要坐的位置实测遮挡、带来源与精度的点级结果，市面上没有人做。它正是 Codex 自己的 Trust Architecture 里唯一能给出 "Observed（measured）" 等级的证据。没有它，Property memory 只剩 "listing 说法 + 用户感受 + 模型推断"，Listing-to-Inspection Delta 没有硬锚。
3. **合并命题：Property Lens = 买家侧、证据分级、跨房源累积的看房记忆；OneTake 实测是它的英雄采集；Light 是第一个 Lens。** Codex 的 MVP v0 用 "address + heading 的 Light Preview" 替代 OneTake，这一条不采纳。OneTake R1 在非 LiDAR 机型也能跑（ADR-0008），不构成 Codex 担心的设备门槛。
4. **Codex 的 Tier 1 数据入口（Domain API）本轮核实后不成立。** Domain 不公布价格、按合同出 Product Schedule，且 API 条款 7.6(d) 禁止向第三方 "display, disclose or otherwise commercially exploit" API 产品【验】。消费级 App 展示 Domain 数据要单独商务谈判，正是 ADR-0004 所说的时间黑洞。MVP 的入口只能是用户自己分享的内容。
5. **名字有冲突风险。** 澳洲已有 realestatelens.com.au（Promethic Labs，买家侧 AI 合同审阅，pre-launch）【验】；"Property Inspect" 是注册商标【验】。"Property Lens" 在商标检索前不能定，工作名暂留 光境 / Light Replay。
6. **阶段安排改为两条并行线。** 测量链 spike（3 周，不变）与产品壳原型（Codex 的 Prototype A，2 周，10 位真实看房者）同时跑，第 3 周末汇合，之前不写 MVP 代码。两条线互不依赖，分别回答"测得准不准"和"第二套房还开不开"。

---

## 1. 逐条裁决

| Codex 章节 | 主张 | 裁决 | 说明与修正 | 落到哪 |
|---|---|---|---|---|
| §0、§62 | Sun replay 不是空白；Domain / REA 的 listing 侧智能已很强 | 采纳事实，修正结论 | 事实我们在 v4、v5 已核（Sun Finder、Sunscore）。commodity 的是地址级；点级实测仍是空白，且是 Codex 五级证据里唯一的 measured 来源 | 蓝图 §1 |
| §1、§55 | 核心对象 = Property；产品中心从 Light Replay 改为 Property Memory | **采纳** | TargetPoint 仍是物理分析单位（ADR-0001 不变），Property 是产品对象 | ADR-0012 |
| §2 | 白地 = Personal + Physical + Temporal + Evidence-aware | 采纳 | 措辞进蓝图 | 蓝图 §1 |
| §4 | Before / During / After 三个真实任务 | 采纳 | 产品规范按这三段重组 | 01 §1–2 |
| §5 | 不做总分、不做 "AI says buy"；Your Priorities | 采纳 | 与 ChatGPT v1 "不设综合分"、我们的宪法一致 | 01、14 |
| §6 | Trust Architecture：Verified / Observed / Strong indication / Indicative / Unknown + 来源标签 | **采纳并合并** | R0–R3 留在 SceneRecord 内部描述输入充分性；五级用于 Observation 对外展示；映射见第 3 节 | ADR-0013 |
| §7 | Familiarity：不发明新操作方式 | 采纳 | | 14 |
| §8 | LiDAR 是 enhancement 不是 entry ticket | 已是现状 | R1 不需 LiDAR，R2 需要（ADR-0008） | 无需改 |
| §9 | Open → Start → Walk + Shoot + Talk → Done | **采纳，且约束 OneTake** | OneTake 必须是 Inspect 模式里的 "Measure" 按钮，不能另开"分析模式" | 01 §2 |
| §10 | 性能就是可信度 | 采纳 | 四盏灯、false-valid、Viewpoint Lock 就是这一条的工程形式 | 07 |
| §12 | Property 对象树（含 Finance Intent） | 采纳，缩减 | Finance Intent 不进 V1 数据模型，只留扩展位 | 15 |
| §13 | Share → Property Lens | 采纳 | Share Extension 读取用户明确分享的 URL / 图片 / PDF；不抓取 | 01、ADR-0014 |
| §14 | Property Preload 四层数据；Tier 1 = Domain API | **修正** | Tier 1 不可行（见第 4 节）；planning / hazard context 后置，且只链接官方来源（ChatGPT v1 §8.3：未知不能画成无风险） | ADR-0014 |
| §15 | REA 无开放 API；Domain 可商务评估 | REA 采纳；Domain 修正 | Domain 是按合同的行业 API，非自助消费级路径【验】 | 10、ADR-0014 |
| §16 | Photo-to-floorplan 是 expected capability 不是 moat | 采纳 | 户型 L0（导入 + 手工房间标签）便宜，可进 MVP v0；L1 配准仍在 Phase 3 | 12 |
| §17 | Inspection Mode 像相机：Capture / Note / Measure | 采纳 | Measure = OneTake 入口 | 01 §2 |
| §18 | AI 不占 Tab | 采纳 | | 14 |
| §19 | Foundation Models 作 Data Structuring Engine，`@Generable` | 采纳 | 在 ADR-0010 边界内：结构化观察可以，数字只来自工具 | ADR-0010 不变 |
| §20 | Property Evidence Graph 是 IP | 采纳数据模型，不采纳 "IP" 说法 | 图本身是数据模型，人人能画；可积累的是实测节点与跨房源历史。SceneRecord 作为 LightObservation 节点挂进图 | 15 |
| §21 | Listing-to-Inspection Delta | 采纳，Phase 3 | Delta 的硬锚是 OneTake 结果与用户现场照片 | 12 |
| §22 | Replay 六个 Lens | Light + Space 采纳；**Sound 不采纳**；其余后置 | 开放看房里录环境声会录到中介与其他买家的对话，Surveillance Devices Act (Vic) 的 private conversation 风险【引 Opus，法条可查】。Privacy / Comfort / Future 放 Phase 4 | 11、12 |
| §23 | Light Replay 2.0：Why / Confidence / Verify | 采纳措辞 | 01 §3 已有归因、来源 σ、复看建议；按 Codex 的三段式呈现 | 01 §3 |
| §25 | Prep：3 things worth noticing | 采纳，收窄 | V1 只能基于用户分享的内容 + 建筑轮廓朝向 + SunEngine，标 Indicative；其中最有价值的一条是"看房时该在哪几个点 OneTake" | 01 |
| §26 | Voice-first；Like / Concern / Ask 三个标签 | 采纳 | push-to-talk，不连续录音；转写在端侧（`SpeechTranscriber`，iOS 27 SDK 存在【验】） | 01、11 |
| §27 | After = Your inspection，不是 report | 采纳 | | 01 |
| §28 | Compare 按用户优先级；点只来自用户评分或可解释指标 | 采纳 | Light 一列的点来自 R1 冬至稳定直射小时，标注来源；未测显示"未采" | 01 |
| §29 | Couple / family 模式 | 采纳，Phase 3 | | 12 |
| §30–31 | 三个 destination；Property 详情是一条滚动层级 | 采纳 | | 14 |
| §32–34 | Glass 只用于控件；品牌来自 Light + Space + Time；日出 / 正午 / 日落 / 进出直射的 haptics | 采纳 | haptic 事件恰好是 SunEngine 的时段边界，零成本 | 14 |
| §35–36 | 权限按需请求；local first | 采纳 | 与 11 一致 | 11、14 |
| §37–38 | Visual Intelligence / App Intents | 数据模型第一天准备（稳定 ID、App Entity 化），实现在 Phase 4 | | 15 |
| §39–41 | 技术栈；AI routing "smallest sufficient model" | 采纳 | 与 ADR-0010、ADR-0011 一致 | 02 |
| §42–45 | MVP v0 / v1 / v2 | 采纳骨架，两处修正 | Light Preview → OneTake R1；Domain API 移出 MVP | 第 5 节 |
| §46–47 | Finance bridge 要晚；显式同意；进入信贷协助即切换正式 broker workflow | 采纳 | 11 §4 措辞改为"V1 不做；长期路径独立、需同意、受 BID 约束"。**需 Lee 决定** | 11 §4、ADR-0005 |
| §48 | Free 3 套 / Buyer Pass 90 天 A$29–49 | 延后 | Lee 已定价格后置；结构记为候选 | — |
| §49–50 | B2B 不早；broker 获客是 outcome 不是 product | 采纳 | Light Passport 从"B2B 收入"改为"分发试点"，判据是买家复扫率 | 09、12 |
| §51 | 四个 moat | 采纳前三，**补第 0 条** | 0 = 实测点级证据；没有它其余三条都可被门户复制 | 蓝图 §1 |
| §52–53 | North star = Repeat Inspection Rate；五个 kill signal | 采纳 | 与 spike 门槛合并，见第 5 节 | 07、12 |
| §54 | 竞争矩阵 | 采纳作参考 | 加一列"现场遮挡实测"，只有我们与太阳能行业工具有 | 10 |
| §56 | 命名 Property Lens | **待查** | 冲突风险见第 0 节第 5 条 | Lee 决定 |
| §60 | Prototype A（5 屏）/ Prototype B（3 件难事） | A 采纳；B 修正 | B-b "floorplan / heading → light estimate" 降为 R0，不花 spike 时间；B-a、B-c 各做 3–5 天小 spike | 第 5 节 Phase 1 |
| §61 | 围绕 domain model 组织代码 | 采纳 | 见第 3 节 | 15 |

---

## 2. 合并后的产品命题

**对外一句话**：See beyond the inspection.（中文候选：看见看房时看不见的。）

**对内定义**：Property Lens（工作名待定）= 买家侧、证据分级、跨房源累积的看房记忆。OneTake 是它的英雄采集；Light 是第一个 Lens；Space 是第二个。

**护城河，按抄袭难度排序**

| # | 护城河 | 谁抄不了 | 来源 |
|---|---|---|---|
| 0 | 实测点级证据：站在你会生活的位置，20 秒得到带来源与精度的直射时段 | 门户没有人在现场；太阳 App 没有质量门槛与证据链 | 我们的蓝图 |
| 1 | 跨房源累积的个人看房记忆（照片、语音、标签、比较、分歧） | 切换成本随看过的房子数增长 | Codex §51 |
| 2 | 采集体验：20 秒、四盏灯、教练句、Viewpoint Lock | 工程细节的堆积 | 我们的蓝图 |
| 3 | 分发闭环：PP / 中介的 Light Passport → 买家复扫 → 进入 App | 需要渠道 | 我们的 V1.5 |
| 4 | 买家偏好记忆（透明、可编辑、可删除） | 需要时间 | Codex §51 |

**蓝图要改的地方**（Phase 0 执行）：§1 产品契约加"Property 是产品对象；TargetPoint 仍是物理分析单位"；§2 加 ADR-0012 / 0013 / 0014 / 0015；§3 首发范围按第 5 节 Phase 2 重写；§5 证据等级表加映射列。

---

## 3. 数据模型合并：Property 图 + SceneRecord

```
Property                      id · address · source(user_shared|manual) · preload(listing_text, photos, floorplan_ref)
├─ Inspection                 date · duration · weather_note
│  └─ Room                    label · floorplan_position?(L0 手工)
│     └─ Observation          category · source · evidence_level · text · media[] · tags(like|concern|ask)
│                             · timestamp · heading? · follow_up?
│        └─ LightObservation  → SceneRecord（现有 03 规范原样不动；一个 TargetPoint 一份）
├─ Question                   text · who_to_ask(agent|conveyancer|inspector) · origin(observation_id)
├─ Priority                   person · dimension · weight
└─ Comparison                 property_ids[] · per-dimension values with source labels
```

- SwiftData 建模；每个实体有稳定 ID 与 `DisplayRepresentation`，为 App Entity 化预留（Phase 4 才接 Siri）。
- SceneRecord 保持 JSON 文件形态（可回放、可交叉核对），Property 图只引用其 `scene_id`。
- Finance 相关字段不进 V1 模型；预留一个 `extensions` 字典位。

**证据等级映射（ADR-0013 草案）**

| 对外等级（Codex） | 含义 | 我们的来源 |
|---|---|---|
| Verified | 用户确认的事实，或带出处的授权数据 | 用户确认北向、用户确认房间；G-NAF 地址 |
| Observed · measured | 现场传感器测得，过质量门槛 | SceneRecord R1 / R2 且 `false_valid_guard = passed` 的"稳定直射"时段 |
| Observed · noted | 现场用户记录 | 照片、语音、标签 |
| Strong indication | 多来源一致 | R1 时段 + 用户观察一致（如"实测 14:10 后遮挡"与"下午觉得暗"） |
| Indicative | 模型推断，待验证 | R0 参考模式；R1 的"方向敏感"时段；Prep 的朝向估计；FM 从 listing 抽取的字段 |
| Unknown | 资料不足 | R1 的"资料不足"时段；未采的房间；未知的树种 |

R 等级仍写在 SceneRecord 与结果卡的证据卡里；用户主界面只见五级与来源标签。

---

## 4. 数据入口分层（修正 Codex §14）

| 层 | 内容 | 状态 | 阶段 |
|---|---|---|---|
| A · 用户分享 | Share Extension 收到的 URL（REA / Domain 的 URL 含地址 slug，可解析）、截图、PDF、listing 文字；Vision `RecognizeDocumentsRequest` 端侧 OCR【验，SDK 存在】+ FM 抽取地址 / 房间 / 尺寸 | 首发核心 | Phase 1 小 spike → Phase 2 |
| B · 开放政府数据 | G-NAF 地址校验；建筑轮廓（Overture / OSM）供墙面对齐 | 许可已登记 | Phase 2 |
| C · 授权数据 | Domain API：按行业与调用量按合同报价，价格不公开；条款 7.6(d) 禁止向第三方展示或分发 API 产品【验】 | 只在有商务谈判时评估 | Phase 4 |
| D · 合作 | REA、PropTrack、CoreLogic 等 | 未开始 | Phase 4+ |
| 不做 | 持续抓取门户 | 永不 | — |

**Prep "3 things" 在 V1 能诚实说什么**：主要窗朝向（轮廓 + 用户分享的户型，Indicative）；你预约的看房时刻太阳在哪、这时客厅会不会有直射（SunEngine，Verified 几何 + Indicative 遮挡）；建议在哪几个点做 OneTake。第三条把 Prep 变成采集计划，是 Codex 没写但最实用的一条。

---

## 5. 阶段计划

### Phase 0 · 决定与对齐（本周，≤ 5 个工作日）

| 事项 | 内容 | 负责 |
|---|---|---|
| 决定 D1–D5 | 见第 7 节 | Lee |
| ADR | 0012 产品对象 = Property；0013 证据等级映射；0014 数据入口分层；0015 Inspect 模式契约（Capture / Note / Measure；push-to-talk；Sound 不做） | Claude 起草，Lee 批 |
| 蓝图与规范 | 蓝图 §1–3、§5；01 §1–3 重写；03 加 Property 引用；10 加 Codex 竞品（SunQuest、SunCast、Domain AI Floorplans、REA ChatGPT app，标【引 Codex 09-30】）；11 §4 与 Sound；13 名词；新建 14-design-principles、15-product-model | Claude |
| 名字 | IP Australia 商标检索 + App Store 检索："Property Lens"、"Light Replay"、"光境" | Lee（或 Claude 先做公开检索） |
| 代码 | 工作区里的 SceneRecord Swift 包与 Python 参考实现：platform 从 iOS 18 改 iOS 27（ADR-0011），跑 `/code-review`，并入 docs/blueprint-v1 或新分支 | Claude |
| 资格 | PCC entitlement 申请状态 | Lee |

### Phase 1 · 并行验证（第 1–3 周）

**线 A · 测量 spike**：`07-spike-plan.md` 原样执行（W1 Point Core、W2 Hard Cases、W3 Holdout）。通过线不变。

**线 B · 原型 A（Codex Prototype A）**：SwiftUI 假数据的 5 屏：Add（Share / 手动）→ Prep（3 things）→ Inspect（Capture / Note / Measure，Measure 打开 OneTake 的模拟动画）→ Your inspection → Compare。10 位正在看房的人做任务式测试（PP 与中介渠道招募，不招朋友）。

| 指标 | 候选线 | 对应 Codex kill signal |
|---|---|---|
| Time to First Capture（进入 Inspect 到第一条记录） | 中位数 < 10 s | §52 |
| 每套房额外操作时间 | < 2 min | Signal 3 |
| 证据理解 | ≥ 8/10 能指出"哪条是测的、哪条是 listing 说的、哪条是推断" | Signal 4 |
| 再用意愿 | ≥ 6/10 主动问"下一套能不能用" | Signal 2 的前置 |
| 只要太阳 | 若 ≥ 7/10 只关心 Light、不碰 Note / Compare | Signal 1 触发：收窄为专业日照产品 |

**线 C · 三个小 spike（各 3–5 天，可在线 A 的等待时段做）**

| 小 spike | 做什么 | 通过线 |
|---|---|---|
| C1 URL → Property | 50 条真实 REA / Domain listing URL，只用 URL 本身解析地址 | ≥ 90% 得到可校验地址【估】 |
| C2 截图 / PDF → 地址与房间 | Vision OCR + FM `@Generable` 抽取；20 张 listing 截图 | 地址 ≥ 90%，房间列表 ≥ 80%【估】 |
| C3 语音 → InspectionObservation | `SpeechTranscriber` zh-CN 与 en-AU 各 30 句 → FM 结构化（room / category / sentiment / follow-up）；人工评分 | 类别正确 ≥ 85%，且没有一句被改写出不存在的事实【估】 |

**汇合门（第 3 周末）**

| 线 A 结果 | 线 B 结果 | 决定 |
|---|---|---|
| GO | 通过 | 进 Phase 2，OneTake 为英雄采集 |
| GO | 不通过 | 产品壳重做原型；OneTake 先以专业采集（PP）形式存在 |
| CONDITIONAL | 通过 | 进 Phase 2；OneTake 限定户外 + 晴天室内，其余点用 R0 |
| NARROW | 通过 | 进 Phase 2 但 Light 只做 R0；测量链继续修，作为 Phase 3 升级 |
| NARROW | 不通过 | 停，重新评估 |

### Phase 2 · MVP v0（第 4–9 周，6 周）

**做**

| 模块 | 内容 | 来源 |
|---|---|---|
| Property | 地址、hero 图、来源、用户分享的 listing 内容；本地优先 SwiftData | Codex §12 |
| Add | Share Extension（URL / 截图 / PDF）+ 手动地址；C1 / C2 的解析器 | Codex §13 |
| Prep | 3 things（Indicative）+ 建议 OneTake 的点 | Codex §25，收窄 |
| Inspect | 相机式界面：Capture（照片 + 房间 + 朝向 + 时刻 + 位置）/ Note（push-to-talk → 结构化，可编辑）/ Measure（OneTake R1）；Like / Concern / Ask | Codex §17、§26 + 我们的 04 |
| Your inspection | 按 liked / unsure / ask next / replay 组织 | Codex §27 |
| Replay · Light | R1 结果页（01 §3）+ Why / Confidence / Verify 三段式 + 时段 haptics | 我们的 01 + Codex §23、§34 |
| Compare | 用户五个优先级；两到三套；每格带来源标签，未测显示"未采" | Codex §28 |
| 分享页 | 脱敏；可撤销 | 我们的 01 §6 |
| 户型 L0 | 导入图片 + 手工点"这张照片在客厅"；不识别、不配准 | v3 / v5 |

**不做**：R2 光斑与任何 LiDAR 专属功能；户型自动识别；Domain API；planning / hazard；couple 模式；Delta；finance；定价（TestFlight 免费）；Sound lens；Siri 短语。

**交付与度量**：TestFlight 给 20–30 位看房者（PP / 中介渠道）。北极星 Repeat Inspection Rate；支持指标 TTFC、Inspection Completion、Properties per Buyer、Compare Rate、Replay Usage、OneTake 成功率、false-valid（必须为 0）。

**阶段结束判定**：Codex Signal 1–4 任一触发即停下修，不加功能。

### Phase 3 · MVP v1 空间升级（第 10–16 周）

RoomPlan 窗几何 → R2 潜力光斑；户型 L1 锚点配准（v3 五步法）；照片到房间；Listing-to-Inspection Delta；Ask-next 自动生成（FM，来源只能是 observation）；couple / family 模式；Light Passport 分发试点（PP 拍摄产出、买家复扫率为判据）；价格实验（Lee 定结构）。进入条件：Phase 2 的 repeat rate 达到 Lee 预注册的线。

### Phase 4 · Property Intelligence（第 17 周起，按信号）

Domain API（仅当有商务谈判）；planning context（只链接官方来源，保留"未知"态）；Privacy lens；WeatherKit 舒适度；App Intents / Visual Intelligence；Finance bridge 的设计与合规审查（独立 workflow、显式同意、BID）。直到有信号仍不做：Sound lens、地址级评分、任何黑盒总分。

### 合并后的 kill criteria

| 信号 | 阈值 | 动作 |
|---|---|---|
| holdout 出现 false-valid | 1 次 | 停消费者产品，修测量链 |
| 第二套房 reopen 率低 | Phase 2 预注册线未达 | 核心习惯未建立：重做 Inspect 体验或收窄 |
| 用户只用 Light | ≥ 70% 的活跃用户只碰 Replay | 收窄为专业日照产品 + Light Passport |
| 每套额外操作 > 2 min | 中位数 | 削功能，不加功能 |
| 用户不信 AI 观察 | 编辑率 > 50% 或访谈反馈 | 强化来源标签，减少 AI |
| 喜欢但不付费 | Phase 3 价格实验 | 检验分发 / B2B 经济，不加功能 |

---

## 6. Phase 0 要改的文档（清单）

| 文件 | 改动 |
|---|---|
| `docs/decisions/ADR-0012-property-as-product-object.md` | 新建（草案见第 8 节） |
| `docs/decisions/ADR-0013-evidence-levels.md` | 新建（第 3 节映射表） |
| `docs/decisions/ADR-0014-data-entry-tiers.md` | 新建（第 4 节） |
| `docs/decisions/ADR-0015-inspect-mode-contract.md` | 新建（Capture / Note / Measure；push-to-talk；无 Sound lens） |
| `docs/00-blueprint.md` | §1 契约、§2 决定表、§3 首发范围、§5 证据表 |
| `docs/01-product-spec.md` | §1–3 按 Before / During / After 与 Inspect 模式重写；§5 Compare 按优先级；结果页加 Why / Confidence / Verify |
| `docs/03-scene-record.md` | 顶部加"SceneRecord 是 Property 图中 LightObservation 的载荷"一句 |
| `docs/10-competitors.md` | 加 Codex 09-30 的条目（标【引】）与"现场遮挡实测"列 |
| `docs/11-compliance-boundaries.md` | §4 finance 长期路径；§3 加 push-to-talk 与不做 Sound 的理由 |
| `docs/12-roadmap.md` | 按第 5 节重写 |
| `docs/13-glossary.md` | Property、Inspection、Observation、Lens、Prep / Inspect / Replay / Compare / Ask、证据五级 |
| `docs/14-design-principles.md` | 新建：Codex §3–11、§30–35 的原则；对照 `apple-design` 与 `jobs-simple-design` |
| `docs/15-product-model.md` | 新建：第 3 节的数据模型与 App Entity 预留 |
| `README.md` | 一句话与阅读顺序 |

---

## 7. 需要 Lee 决定

| # | 事项 | 推荐 | 影响 |
|---|---|---|---|
| D1 | 采纳"Property 是产品对象，OneTake 是英雄采集"的合并命题（ADR-0012） | 采纳 | 蓝图 §1–3 重写 |
| D2 | 名字 | 商标检索前留 光境 / Light Replay；"Property Lens" 与 Realestate Lens 近似，需检索 | 品牌、仓库名 |
| D3 | Finance 的长期措辞 | 11 §4 改为"V1 不做；长期路径存在，独立 workflow、显式同意、BID 约束、不影响分析" | ADR-0005 范围说明 |
| D4 | 并行线人力 | 线 A、C 由 Claude；线 B 的 5 屏原型 Claude 也可做（SwiftUI + 假数据），招募与访谈由 Lee / PP | 3 周内两条线 |
| D5 | 工作区里的 SceneRecord 代码 | 改 iOS 27、过 code-review、并入主线 | Phase 1 W1 的起点 |

D1 是方向性的；D2–D5 按推荐回复"按推荐"即可执行。

---

## 8. ADR-0012 草案

```markdown
# ADR-0012 · 产品对象是 Property；OneTake 是英雄采集；Light 是第一个 Lens

- 状态：Proposed
- 日期：2026-09-30
- 来源：Codex《Property Lens v2.0》§1、§12、§51、§55；本回应第 0–2 节

## 背景
蓝图把产品定义为一件点级日照测量仪器。它可信但低频：买房几年一次，看房只有几周。
Codex v2 指出可积累的资产是买家侧的看房记忆（照片、语音、标签、比较、分歧），
切换成本随看过的房子数增长；同时门户（Domain / REA）与太阳 App 已覆盖 listing 侧
与地址级日照。本轮核实：地址级日照是 commodity；点级实测仍无人做，且是五级证据
里唯一的 measured 来源。

## 决定
1. 产品对象是 Property；一套房是一个持续生长的记录（Inspection、Room、Observation、
   Question、Priority、Comparison）。
2. TargetPoint 仍是物理分析单位（ADR-0001 不变）；SceneRecord 作为 LightObservation
   的载荷挂进 Property 图。
3. OneTake 是 Inspect 模式里的 Measure 动作，是产品的英雄采集；Light 是第一个 Lens，
   Space 是第二个；Sound 不做。
4. 北极星指标是 Repeat Inspection Rate；spike 的 false-valid 一票否决不变。

## 备选
- 保持纯测量工具：可信但低频，且 Light Passport 之外没有留存机制。
- 采纳 Codex 原案（MVP 用地址级 Light Preview）：把唯一的 measured 证据换成 commodity。

## 后果
- 蓝图 §1–3、§5；01、12、13 重写；新增 14、15。
- 三周内两条并行线（测量 spike、产品壳原型），第 3 周末按汇合门决定。
- 工作名待商标检索（D2）。
```

---

## 9. 我可能错在哪

1. **两条并行线对一个人加 PP 的带宽是估计。** 若线 B 拖慢线 A，线 A 优先，线 B 顺延一周。
2. **"Observed · measured" 是否真被买家看重，没测过。** 原型 A 的证据理解指标就是为这个设的；若买家不区分测的和推断的，护城河 0 的商业价值下降，但合规价值仍在。
3. **Realestate Lens 可能从合同审阅扩展到看房记忆。** 它已经在买家侧、已经有品牌。要盯。
4. **Codex 对 Domain AI Floorplans、REA ChatGPT app、SunQuest、SunCast 的描述我未逐条核实**，只核了 Domain API 条款与名字冲突。
5. **Prep 的"3 things"在没有授权数据时可能太薄**，用户第一印象是"它什么都不知道"。对策：Prep 的第三条（在哪几个点 OneTake）必须做得有用。
6. **名字**：若 Lee 决定用 Property Lens，需要律师做商标意见，不是我这轮的公开检索能替代的。

---

## 10. 本轮来源

- Domain API Terms and Conditions，条款 7.6(d)【验】：https://www.domain.com.au/group/api-terms-and-conditions/
- Domain Developer Portal（无公开价格；按行业与调用量分计划）【验】：https://developer.domain.com.au/ 、https://developer.domain.com.au/docs/v2/support/faq/
- Realestate Lens（Promethic Labs，pre-launch）【验】：https://realestatelens.com.au/
- Property Inspect 商标【验】：https://propertyinspect.com/au/features/
- iOS 27.0 SDK：`Speech.SpeechTranscriber` / `SpeechAnalyzer` / `DictationTranscriber`、`Vision.RecognizeDocumentsRequest`、`AppIntents`、`SwiftData`、`WeatherKit` 存在【验，接口文件】
- Codex 引用的 Apple WWDC26 场次、Domain / REA 帮助页、太阳 App 商店页：见其 §65，本轮未复核【引】
