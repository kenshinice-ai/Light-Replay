# 00 · 蓝图：冻结的决定与产品契约

版本 1.1 · 2026-09-30（1.0 于 2026-09-10） · 取代此前全部策略稿（存档在 `light_replay_history/`，被 `.gitignore` 排除，不入库）。本文是唯一事实来源；改动流程见第 8 节。

## 1. 产品契约

产品名 **Property Replay**（ADR-0016）。Tagline：**See beyond the inspection.**

一句话定义：**把 20 分钟看房，变成一份可以回放、比较、验证的房产记忆。** 其中最硬的一块记忆是：拍下你会生活的位置，把它一年的直射阳光带回家。

- **Property 是产品对象。** 一套房是一个持续生长的记录：Prep、Inspection、Room、Observation、Question、Priority、Comparison（ADR-0012、`15-product-model.md`）。
- **TargetPoint 是物理分析单位。** 结果只对应一个点和一个高度；换座位就是另一次采集（ADR-0001）。
- **OneTake 是英雄采集。** 它是 Inspect 模式里的 Light 动作（文档旧称 Measure），不是另一个模式（ADR-0015）。
- **SceneRecord 是证据底座。** 每个测量结果都能回溯到采集会话、姿态、掩膜、方向来源与算法版本；它作为 LightObservation 挂进 Property 图。
- **证据分级对外统一。** Verified / Observed·measured / Observed·noted / Strong indication / Indicative / Unknown，每条带来源标签（ADR-0013）。R0–R3 只在测量链内部。
- **输出按等级解锁。** 更大、更漂亮的结果只在输入等级足够时出现；视觉不能比证据更确定。
- **AI 不占位置。** 它结构化语音、写教练句和文案；数字只来自工具（ADR-0010）。

对内验收：**这次输出针对哪个点、根据哪些证据、还不知道什么？**
北极星：**Repeat Inspection Rate**，用户看完第一套房后，下一套是否还主动打开。

## 2. 冻结的决定

| # | 决定 | 一句话理由 | ADR |
|---|---|---|---|
| 1 | 分析原语是 TargetPoint × 天空可见域 | 庭院座位、阳台、沙发位同一引擎；窗框、墙、檐口都只是这个点看出去的遮挡 | [ADR-0001](decisions/ADR-0001-target-point-primitive.md) |
| 2 | 物理算事实，生成只做呈现 | 数字要能被固定机位延时验证；生成模型会幻觉 | [ADR-0002](decisions/ADR-0002-physics-for-evidence.md) |
| 3 | 原生 iOS 先行；单 App 首发；系列保留 | 姿态、深度、帧同步只有 ARKit 提供；风水境是后续独立产品，不进 V1 工程 | [ADR-0003](decisions/ADR-0003-native-ios-single-app.md) |
| 4 | 首发不依赖商业地图与授权高程数据 | R1 只需要现场采集；单人谈数据许可是时间黑洞 | [ADR-0004](decisions/ADR-0004-no-licensed-data-at-launch.md) |
| 5 | V1 不做法律文件、风水功能、合规评分线、地址级评分、价格 | 法律与误导风险；Sunscore 已把建筑级评分商品化；价格等 spike 后 | [ADR-0005](decisions/ADR-0005-v1-exclusions.md) |
| 6 | 镜头漂移用深度重投影处理，不拒帧 | 真人手持漂移 10–60 cm；近场遮挡有深度可修正，远场与漂移无关 | [ADR-0006](decisions/ADR-0006-viewpoint-drift-handling.md) |
| 7 | 真北是多来源一致性问题；不确定性以时段表达；冲突取最大一致组合 | 没有单一可靠传感器；用户要的是几点到几点，不是正负几度 | [ADR-0007](decisions/ADR-0007-north-resolver.md)、[ADR-0009](decisions/ADR-0009-north-conflict-handling.md) |
| 8 | V1 只交付 R1；R2 光斑标"潜力投影" | R1 已是完整任务；精确 R2 需要外部遮挡距离 | [ADR-0008](decisions/ADR-0008-r1-first.md) |
| 9 | 三周 spike 设 holdout；false-valid 一票否决 | 不能用拟合数据证明自己；错误却确定的输出比没有输出更糟 | [07-spike-plan](07-spike-plan.md) |
| 10 | Apple 端侧 AI 与 PCC 只用于辅助层 | 省掉自训分割与文案代码，但不许碰测量链 | [ADR-0010](decisions/ADR-0010-apple-ai-boundaries.md) |
| 11 | Spike 与 V1 只支持 iOS 27 | 加速来源都是 iOS 27 API；不维护回退路径 | [ADR-0011](decisions/ADR-0011-ios-27-minimum.md) |
| 12 | 产品对象是 Property；OneTake 是英雄采集；Light 是第一个 Lens | 仪器低频，记忆高频；点级实测是唯一的 measured 证据 | [ADR-0012](decisions/ADR-0012-property-as-product-object.md) |
| 13 | 对外证据五级 + 来源标签；R 等级留在内部 | listing 说法与实测不能摆成同一种东西 | [ADR-0013](decisions/ADR-0013-evidence-levels.md) |
| 14 | 数据入口：用户分享优先；Domain API 不进首发 | Domain 条款 7.6(d) 禁止向第三方展示；REA 无开放 API | [ADR-0014](decisions/ADR-0014-data-entry-tiers.md) |
| 15 | Inspect 模式 = Capture / Note / Measure；push-to-talk；不做 Sound lens | 看房只有 20 分钟；连续录音撞监控设备法 | [ADR-0015](decisions/ADR-0015-inspect-mode-contract.md) |
| 16 | 产品名 Property Replay | Property Lens 有四家近似；Property Replay 商标检索 0 条 | [ADR-0016](decisions/ADR-0016-product-name.md) |
| 17 | 资料库同步到用户自己的 iCloud 私有库；照片和记录跟着行走 | 回家在 iPad 上复看；删除与保存变成一个事务 | [ADR-0017](decisions/ADR-0017-icloud-private-sync.md) |
| 18 | 一致不等于佐证 | 两组一致只在 `3·sqrt(σ_i² + σ_j²) ≤ 15°` 时点绿灯，否则按一组处理；罗盘按 8° 先验永远不能佐证 | [ADR-0018](decisions/ADR-0018-corroboration-must-detect-an-hour.md) |

## 3. 首发范围（V1 = MVP v0，`12-roadmap.md` Phase 2）

**做：**
- 系统：iOS 27 及以上（ADR-0011）。
- Property：地址、hero 图、来源、用户分享的 listing 内容；Share Extension（URL / 截图 / PDF）+ 手动地址（ADR-0014）。
- Prep：3 things worth noticing（Indicative）+ 建议 OneTake 的点。
- Inspect：相机式界面，Capture / Note / Light；Like / Concern / Ask；五盏质量灯（含镜头脏污）（ADR-0015）。
- Your inspection：liked / unsure / ask next / replay。
- Replay · Light：R1 结果页，Why / Confidence / Verify 三段式，时段 haptics；参考模式 R0 只画太阳弧。
- Compare：用户五个优先级，两到三套，每格带等级与来源，未测显示 Unknown。
- 户型 L0：导入图片 + 手工房间标签。
- 分享页：脱敏、可撤销。
- 辅助层：教练句、结构化语音、文案；数字只来自工具（ADR-0010）。

**不做：**
- R2 光斑与任何 LiDAR 专属功能；户型自动识别与配准；Listing-to-Inspection Delta；couple 模式。
- Domain API、planning / hazard、气候概率、天气氛围、写实重打光。
- Sound lens；连续录音；后台定位。
- 任何法规合格线、任何价格、任何贷款或法律内容、任何黑盒总分。

## 4. 架构一页

```
        设备端（离线可用）                                 服务端（V1 只有分享页托管）
┌──────────────────────────────────────────────┐        ┌──────────────────────┐
│ CaptureCore   ARSession · 帧/姿态/深度 · Hero  │        │ report/  分享页       │
│               镜头锚点与漂移 · 质量状态          │        │ （只读渲染 SceneRecord│
│ VisibilityCore 天空分割 · 深度重投影 · 可见域     │ ─────► │   的分析结果与来源）  │
│               走廊覆盖率                        │        └──────────────────────┘
│ NorthResolver  方向候选 · 独立组 · 融合 · σ       │
│ SunEngine      SPA · 时区 · 采样 · 时段分级       │        V1.5 起：地址级粗估、Light Passport
│ SceneRecord    模型 · JSON · 版本 · 来源           │        V2 起：GeometryCore（RoomPlan/R2）、预览
└──────────────────────────────────────────────┘
```

坐标约定：可见域以 **AR 世界坐标的方位角**存储（重力对齐，yaw 任意）；真北只是查询时施加的一个绕重力轴的旋转。这样北向被修正时不需要重新采集。

## 5. 证据等级

| 等级 | 需要 | 输出 | 禁止 | 对外等级（ADR-0013） |
|---|---|---|---|---|
| R0 参考 | 地址、时间；或导入照片 + 手工方向 | 太阳弧、笔记 | 任何小时数 | Indicative |
| R1 点级（V1） | 同视点可见域、方向分布、目标点与高度 | 该点直射时段与未知区间、全年热力图 | 推广到其他座位或整间房 | 稳定直射 → Observed·measured；方向敏感 → Indicative；资料不足 → Unknown |
| R2 接收面（V2） | R1 + 窗几何 + 接收面 + 适用的外部遮挡几何 | 潜力光斑；几何充分时的裁剪与面积 | 冒充照度或热舒适 | 时段同 R1；光斑形状 Indicative |
| R3 空间（V2+） | 多视点、配准、情景 | 多点比较、户型绑定 | 未采空间的确定结论 | 按节点各自定级 |

## 6. 成功标准

- **Spike（3 周）**：`07-spike-plan.md` 的候选通过线；holdout 中 false-valid 为 0。
- **原型 A（并行 2 周）**：10 位真实看房者，TTFC < 10 s，≥ 8 人能分清测的 / listing 说的 / 推断的，≥ 6 人主动问下一套能不能用（`12-roadmap.md` Phase 1）。
- **V1（MVP v0）**：Repeat Inspection Rate 达到预注册线；普通用户在 open home 预算内独立完成，不需要专家救场；false-valid 为 0。
- **V1.5**：PP 的挂牌流程不显著拖慢拍摄；Light Passport 有人打开并复扫。

## 7. 名词

全部见 `13-glossary.md`。文档与代码只用那里的名字。

## 8. 变更流程

1. 提出改动：新建 ADR（复制 `decisions/ADR-0000-template.md`），写清背景、决定、后果。
2. ADR 状态改为 Accepted 后，更新本文第 2 节和受影响的规范。
3. 通过线的修订也走 ADR，写明新证据；不得静默放宽。
