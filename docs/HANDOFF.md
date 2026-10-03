# HANDOFF · Property Replay

给评审者（Codex）与任何接手会话的人。目标：十分钟内知道项目是什么、真相在哪、怎么跑、这一阶段该审什么、不该碰什么。

## 1. 这是什么

Property Replay：iOS App。把 20 分钟看房变成一份可以回放、比较、验证的房产记忆；其中最硬的一块是 OneTake：站在你会生活的位置扫一次天空，20 秒后得到这个点一年的直射时段，带来源与精度。产品契约见 `docs/00-blueprint.md` §1。

分工（2026-09-30 起）：Claude 做原型、代码与文档；Codex 做阶段性 review；Lee 决定与现场；Paradise Production 采集与渠道。

## 2. 真相在哪

| 问题 | 看哪里 |
|---|---|
| 决定了什么、为什么 | `docs/00-blueprint.md` §2 + `docs/decisions/` |
| 用户流程与页面 | `docs/01-product-spec.md` |
| 数据模型 | `docs/15-product-model.md`（Property 图）、`docs/03-scene-record.md`（测量载荷） |
| 采集与测量 | `docs/04` 采集协议、`05` NorthResolver、`06` SunEngine |
| 现在做到哪、下一步 | `docs/12-roadmap.md`；`README.md` 的"下一步" |
| 验证与通过线 | `docs/07-spike-plan.md`、`docs/08-ground-truth-protocol.md` |
| 边界 | `docs/11-compliance-boundaries.md`；ADR-0005、0010、0015 |
| 名词 | `docs/13-glossary.md` |
| 历史与被否决的方案 | `light_replay_history/`（本机，不入库） |

改决定的顺序：先 ADR，再蓝图，最后规范。通过线是"候选"，事后不放宽；要改，写 ADR。

## 3. 怎么跑

```bash
./scripts/test.sh          # SceneRecord Swift 单元测试 + Python 参考实现 + 跨语言一致性（不含 App）
cd ios && xcodegen generate && xcodebuild test -project PropertyReplay.xcodeproj -scheme PropertyReplay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro (iOS 27)' -derivedDataPath ~/Library/Caches/propertyreplay/DerivedData
                            # App 冒烟 + CaptureCore + PropertyModel（模拟器）
```

- 构建产物必须在 iCloud 之外（`~/Library/Caches/propertyreplay/`）：codesign 拒绝带 iCloud FinderInfo 的 bundle，这是本组所有 app 的通病。脚本已处理；手跑 `swift build` 请加 `--scratch-path`。
- App：`cd ios && xcodegen generate`（改了 `project.yml` 之后），然后
  `xcodebuild test -project PropertyReplay.xcodeproj -scheme PropertyReplay -destination 'platform=iOS Simulator,name=iPhone 17 Pro (iOS 27)' -derivedDataPath ~/Library/Caches/propertyreplay/DerivedData`。
  模拟器必须是 iOS 27 运行时（26.x 装不上）。`PropertyReplay.xcodeproj` 是生成物，不手改。
- ARKit、LiDAR、RoomPlan、Foundation Models 只能真机；模拟器只跑纯算法与界面。
- iOS 27 是最低系统（ADR-0011）。测试机需要 LiDAR 且至少一台支持 Apple Intelligence。

## 4. 这一阶段审什么

**Phase 0（现在）**：文档一致性。术语是否只用 `13`；蓝图 §2 与各 ADR 是否一致；01 的每个输出是否带等级与来源；11 的边界是否被任何规范违反。上一轮 ultrareview 的记录与复算脚本在 `docs/reviews/`，它的方法（逐条对照、数值复算、约定测试）是本项目评审的标准。

**Phase 1（第 1–3 周）**：
- 线 A 代码：坐标约定（`02` §3）是否被物理对照夹具覆盖；NorthResolver 是否照 ADR-0009；false-valid 是否有阻断路径；SceneRecord 写入是否完整。
- 线 B 原型：五屏是否只服务三个任务；有没有任何数字来自模型；证据等级是否可见。
- 线 C：三个小 spike 的通过线是否被诚实统计（分母含失败）。

**Phase 2 起**：每个 PR 过 `docs/14-design-principles.md` §8 的六问；每次涉及数字的改动过 Assist 回归（`02` §6）。

## 5. 评审输出格式

指出文件与行；矛盾优先于风格；每条给改法；数字复算附脚本。与 `docs/reviews/2026-09-10-blueprint-v1-review.md` 同一格式。评审结果放 `docs/reviews/<date>-<scope>-review.md`，改法落地后在同文件顶部记状态。

## 6. 不要碰

- 太阳几何、北向融合、可见域累积、投影：任何 LLM 不进这条链（ADR-0002、0010）。
- 价格、法律文件解读、风水功能、规划合格线、地址级评分、finance 内容（ADR-0005；`11` §4）。
- `light_replay_history/` 与 `field/data/`：不入库。
- 不改写共享历史；只在 Lee 要求时 commit / push。

## 7. 当前状态（2026-10-01）

状态词分四档，不混用：**源码**（代码在仓库里）→ **测试**（模拟器或包测试通过）→ **真机**（Lee 或 Claude 在 iPhone 17 Pro / iOS 27.0.1 上走过）→ **现场**（有 `field/` 记录编号）。没有任何一项到"现场"。

| 能力 | 源码 | 测试 | 真机 | 备注 |
|---|---|---|---|---|
| 文档：蓝图 1.1，ADR-0001–0017 | ✓ | — | — | ADR-0017 为 iCloud 同步 |
| SceneRecord 格式与校验（Swift / Python 一致） | ✓ | ✓ | — | `scripts/test.sh` |
| R0 采集验证器（每帧姿态、全部罗盘读数、一次定位） | ✓ | ✓ | ✓ 首跑 167 帧、漂移 0.14 m、罗盘 ±13°、定位 ±8 m | 北向候选依赖"竖持时 CLHeading = 后摄方位"假设，待日晷验证 |
| 五个 tab（iPad 上可切侧栏）、Properties List / Map 共用搜索 / 筛选 / 选中、宽窗口分栏、地址补全 | ✓ | ✓ UI `BrowseAndCompareUITests`（iPhone 与 iPad 模拟器） | ✓ iPhone 旧版；分栏待 Lee 在 iPad 上看 | UI/UX 评审 U07 / U09 / U10 |
| Compare：关注维度 × 房产，格子来自买家自己的标签与扫描，各种"没有"分开写，不打分 | ✓ | ✓ 单元 `CompareSummaryTests` + UI | — | U14；School / Commute / Price comfort 目前没有记录来源 |
| 相机方向：预览与拍照角度由 RotationCoordinator 分别给出 | ✓ | — | 待 Lee 验证（竖持 / 横持 / iPad 四向） | U03；模拟器无相机 |
| Inspect：拍照、按住说话、Like / Concern / Ask、Light 入口 | ✓ | ✓ 照片路径 | ✓ 拍照、中英文转写 | Measure 在界面上改名 Light（ADR-0015 修订） |
| Light scan：全屏 AR 相机、太阳路径叠加、单行指引、走廊覆盖率、保存到房产（`04` §11） | ✓ | ✓ 单元（`SkyGeometryTests`、`ScanCoachTests`）+ UI（`LightScanUITests`：保存、覆盖不足询问、丢弃、切换问题重算、保存失败重试；模拟器假相机） | 已装 iPhone / iPad，待 Lee 实测 | 不出日照小时：没有天空分割，记录仍是 R0，结果面板明说"Sunlight not calculated yet"。真机上要看：弧线是否落在天空对的位置、罗盘 σ、转一圈后覆盖率能否到 90% |
| 端侧 Foundation Models 结构化笔记 | ✓ | — | ✓ 能力 Available | 准确率、幻觉回归未评估 |
| PCC | entitlement ✓，业务未调用 | — | ✓ 能力 Available | 先做端侧 / 模板闭环，再做合成输入 smoke |
| iCloud 私有库同步（ADR-0017） | ✓ | ✓ 无账号降级 | ✓ iPhone → iPad：两台真机数据库逐表计数一致，照片与测量记录字节已同步 | 离线再上线、删除传播待测 |
| 同步状态只报告真实发生的收发与失败（`SyncMonitor` / `SyncStatus`） | ✓ | ✓ 单元 `SyncStatusTests` | 待 Lee 在 iPhone / iPad 的 You › Privacy & data 看一眼 | UI/UX 评审 U16；登录了不等于同步了 |
| 照片与测量记录存在行上；旧文件启动时迁移 | ✓ | ✓ | 装机即迁移，待 Lee 确认旧照片仍在 | |
| 测量先落待关联文件，存库失败可重试、重启补关联 | ✓ | ✓ 幂等 / 串房 / 孤儿 | — | |
| 保存 / 删除失败：不崩溃、不留半个改动 | ✓ | ✓ 磁盘存储上的 5 个故障注入（`FailureInjectionTests`） | — | 从不调用 `rollback()`（删过带外部存储的行后它会崩，见组记忆）：失败的插入手动撤销并解除关联；失败的删除保持待删，下次保存完成。全部删除逐行删，批量 `delete(model:)` 与待删行叠加会崩 |
| 删除前确认：左滑 / 长按删除、详情页删除、删除房产、删除全部都先问，问题挂在触发它的行或按钮上并写明对象 | ✓ | ✓ UI | — | iOS 26 起确认框是锚定的气泡（组记忆 confirmation-dialog-anchors-to-its-view） |
| 地址补全与解析限制在澳洲：区域 + 文字过滤 + 坐标范围校验 | ✓ | ✓ 单元 `AddressScopeTests` | — | Apple Maps 在区域内无匹配时会退回全球结果 |
| 添加房产：选中建议保留其 pin、整行可点、找不到时在地址栏下说明、存的是地址栏里的字 | ✓ | ✓ UI（Apple Maps 由 `AddressCompleter.StandIn` 的两套虚构房子顶替，不联网） | 待 Lee 用真实地址走一遍 | 10-01 用真实 Maps 复现过"选中后被清掉"；修复后的真实 Maps 路径未在真机复验 |
| 提示文字对比度：橙 / 红小字用系统高对比变体（`TextColors.swift`） | ✓ | ✓ 单元 `TextColorTests`：浅 / 深、页面 / 列表行，全部 ≥ 4.5:1 | — | 相机画面上的材质底未量 |
| 草稿编辑面板（系统 sheet）：单一来源、AI 晚到不覆盖买家修改、只能经 Save / Discard 离开、原话可改且保留原文 | ✓ | ✓ UI `InspectFlowUITests`（拍照 / 笔记 / 保存 / 丢弃 / 纠正原话 / Done） | 待 Lee 复测（9-30 的保存即崩已修并有测试守住） | 面板取代了压在取景器上的卡片（UI/UX 评审 U01 / U20）；因为面板是模态的，"Done 时还有未保存草稿"这条路径不再存在 |
| 录音按代隔离资源、后台停止 | ✓ | — | — | 需要真机手测：快速按-松-再按 |
| 观察详情：照片全屏缩放、原话完整可改（保留原文）、标签可改、来源白话说明 | ✓ | ✓ 单元 + UI | — | UI/UX 评审 U04；iPad 复看的核心 |
| 最大辅助字号：Inspect、编辑面板、Light、结果面板、房产页、四个列表屏（Home / Properties / Inspect / Compare）不溢出不截断 | ✓ | ✓ UI `AdaptiveLayoutUITests`（元素必须在窗口宽度内；标题完整；搜索框在）+ 人工看截图（iPhone 默认 / XXXL / AX1 / AX5，iPad AX5） | — | 相机上的悬浮文字在 accessibility2 封顶（否则挡住取景器），底栏三个动作在 xxxLarge 封顶并支持 Large Content Viewer；面板与正文完全跟随 |
| 按住说话的辅助入口：VoiceOver 双击开始 / 结束、⌘D、`.startsMediaSession` | ✓ | — | — | 需真机开 VoiceOver / Switch Control 验收（U05） |
| 改地址使旧 pin 失效、过期结果丢弃 | ✓ | ✓ | — | |
| SunEngine：太阳位置、3×3 日盘判定、全年时段（Δ 不确定度 64 次抽样）、太阳走廊覆盖率 | ✓ | ✓ 13 项合成天空与解析解对照；SPA 算例；独立算法 0.011°；Swift / Python 1e-7° | — | `ios/Packages/SunEngine`；全年计算 0.05 秒（Release，Mac） |
| NorthResolver 融合（组内中位数、两两一致性、最大一致组合、佐证、方向灯；ADR-0009、ADR-0018） | ✓ | ✓ 22 个按文档手写的情形 + 200 个随机输入，Swift / Python 1e-9° | — | `ios/Packages/NorthResolver`，`northresolver-0.2`。候选目前只有罗盘一组，罗盘按 8° 先验永远不能佐证，所以真机上方向灯最多黄灯，这是对的 |
| QualityEvaluator：走廊覆盖、方向、分割三盏灯按证据重算，校验器拒绝写入值与证据不符的记录（复审 R08） | ✓ | ✓ 29 个用例，Swift / Python 同一份；复审的六个探针全部拒绝 | — | 水平与追踪、镜头两盏灯在 schema 0.1.0 里没有可重算的证据，按写入值；"反射未识别"未判。见复审回应的 10-01 补记 |
| 罗盘读数全部保留（`raw.samples`），候选取中位数，σ 含扫动中的分散 | ✓ | ✓ CaptureCore 6 例 | 待下次真机扫描后看一份记录 | 俯仰超过 50° 的读数保留但不参与合并 |
| 天空分割（相机帧 → 可见域网格）、日照结果页与回放 | — | — | — | 第三批剩余；扫描界面、SunEngine、NorthResolver、QualityEvaluator 已就位，分割接上后结果卡换成时段 |

跑测试：`./scripts/test.sh`（纯算法，Mac：NorthResolver、SceneRecord 含 QualityEvaluator、SunEngine、Python 参考）；`./scripts/ios-test.sh [unit|ui]`（模拟器；自建专用设备 "Property Replay iPhone"，跑完关机；关掉了 xcodebuild 失败后长达十分钟的诊断收集）。默认的 iPhone 17 / 18 Pro 模拟器会被别的项目会话占用，不要用。

UI 测试用 `-uitest` 启动参数：内存库 + 虚构样例，模拟器上用 DEBUG 的测试照片 / 测试笔记按钮代替相机和麦克风，Light scan 用假相机，地址补全用两套虚构的房子顶替 Apple Maps（不联网，不向外发地址）。可调参数：`-syntheticSweepSpeed <度/秒>`（0 = 不动）、`-syntheticSweepPasses 1`（只扫冬季那一遍）、`-failFirstLightSave`（第一次保存失败）、`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`（最大字号）。全套约 8 分钟，改界面必跑，iPad 另跑一遍：`PR_SIM_NAME="Property Replay iPad" PR_SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB ./scripts/ios-test.sh ui`。断言只能证明元素在窗口内、按钮里有文字；截断和观感要看截图（`xcresulttool export attachments`）。

界面评审：`reviews/2026-09-30-apple-design-review.md`（Claude）；`reviews/2026-10-01-uiux-adaptive-review.md`（Codex，24 条）与回应 `…-response.md`：三轮都已做完并各自提交（第一轮 P1 与大字号；第二轮 iPad 分栏、共用状态、Compare、相机旋转；第三轮同步状态、设置分层、输入、删除确认、提示文字对比度）。§2c 是第三轮提交后补看各档字号截图修掉的四处；§2d 是仍然排在后面的，§3 是要 Lee 决定的，§4 是只能在真机验收的。改界面后要看的不只是改到的那一屏：四个列表屏在默认、XXXL、最大辅助字号下各看一眼。

第二轮复审的逐条回应：`reviews/2026-09-30-progress-reaudit-response.md`。

仍然开着的：
- QualityEvaluator 没有重算的两盏灯（水平与追踪、镜头）和"反射未识别"：要先给 schema 加检测器证据字段。
- 佐证门槛 15°（ADR-0018）是候选值，日晷 spike 校准（`07` 第 5 节）。
- 方向候选只有罗盘一组；墙面对齐、窗光斑、太阳圆面、VPS 的采集未做。
- SunEngine 的走廊与时段分级还没有 Python 对照实现（太阳位置已有）。
- `installTap` 在 iOS 27 标为弃用，替代 API 未确认，暂留。
- CloudKit production schema 部署（上架前）；跨设备同日 `scene_id` 冲突（ADR-0017 后果）。
- Room 仍是字符串标签（L0），`Question` 模型未拆出。
- 待办（Lee）：正式商标意见；域名；仓库是否改名。
