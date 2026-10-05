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

## 7. 当前状态（2026-10-05）

状态词分四档，不混用：**源码**（代码在仓库里）→ **测试**（模拟器或包测试通过）→ **真机**（Lee 或 Claude 在 iPhone 17 Pro / iOS 27.0.1 上走过）→ **现场**（有 `field/` 记录编号）。没有任何一项到"现场"。

| 能力 | 源码 | 测试 | 真机 | 备注 |
|---|---|---|---|---|
| 文档：蓝图 1.1，ADR-0001–0022 | ✓ | — | — | ADR-0017 iCloud 同步；0018 佐证；0019 可见域存储与时机；0020 姿态频率；0021 方向确认；0022 schema 0.2 与结果契约 |
| SceneRecord 格式与校验（Swift / Python 一致） | ✓ | ✓ | — | `scripts/test.sh` |
| R0 采集验证器（每帧姿态、全部罗盘读数、一次定位） | ✓ | ✓ | ✓ 首跑 167 帧、漂移 0.14 m、罗盘 ±13°、定位 ±8 m | 北向候选依赖"竖持时 CLHeading = 后摄方位"假设，待日晷验证 |
| 五个 tab（iPad 上可切侧栏）、Properties List / Map 共用搜索 / 筛选 / 选中、宽窗口分栏、地址补全 | ✓ | ✓ UI `BrowseAndCompareUITests`（iPhone 与 iPad 模拟器） | ✓ iPhone 旧版；分栏待 Lee 在 iPad 上看 | UI/UX 评审 U07 / U09 / U10 |
| Compare：关注维度 × 房产，格子来自买家自己的标签与扫描，各种"没有"分开写，不打分 | ✓ | ✓ 单元 `CompareSummaryTests` + UI | — | U14；School / Commute / Price comfort 的来源是回家补记的笔记（见下） |
| 相机方向：预览与拍照角度由 RotationCoordinator 分别给出 | ✓ | — | ✓ 10-03 Lee 横持拍的照片存成 2048×1536，像素方向正确；iPad 四向待看 | U03；模拟器无相机 |
| Inspect：拍照、按住说话、Like / Concern / Ask、Light 入口 | ✓ | ✓ 照片路径 | ✓ 拍照、中英文转写 | Measure 在界面上改名 Light（ADR-0015 修订） |
| Light scan：全屏 AR 相机、太阳路径叠加、单行指引、走廊覆盖率、保存到房产（`04` §11） | ✓ | ✓ 单元（`SkyGeometryTests`、`ScanCoachTests`）+ UI（`LightScanUITests`：保存、覆盖不足询问、丢弃、切换问题重算、保存失败重试；模拟器假相机） | ✓ 10-05 Lee 扫 9 段（`PR-20261005-01…09`，All-year）：只有 4 段到 90%，用了 39–87 秒。三个原因与改法在 `spike/2026-10-05-scan-coverage.md`：路径随最近 60 条罗盘读数滑动（改为 Start 之后全部读数的中位数；起点与不抽稀是 Codex 同日评审 LS01 / LS02 后补的，回应在 `reviews/2026-10-05-light-scan-algorithm-review-response.md`）、镜头抬过 40° 后罗盘读数转 180°（俯仰上限 50° → 30°）、实时覆盖按 0.15 m 截断而规范是 0.40 m（已对齐）。**改后的版本待 Lee 再扫**：重放只说明同样的动作怎么计，不说明路径稳定后人会不会扫得更好 | 不出日照小时：没有天空分割，记录仍是 R0，结果面板明说"Sunlight not calculated yet"。All-year 要转 240°、抬到近乎头顶，本身就比 Winter 难（同样 9 段按 Winter 计，8 段里 6 段在 13–28 秒到线）。弧线标签写明是哪一天（10-05：只写 "20 Mar" 被读成今天的日期）|
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
| iPhone 横屏（含拍摄与 Light，Lee 2026-10-03）：方向支持、罗盘参考边随界面方向、每条读数带设备方向；编辑面板横屏时照片在左、标签在右（10-03 Lee 发现竖排要拖才见标签） | ✓ | ✓ UI `testInspectAndLightInLandscape`：横屏下 Inspect 三个动作、编辑面板（Like / Concern / Ask 不滚动就在窗口内）、Light 控件在窗口内且可点 | ✓ 横持拍（照片 2048×1536）；✓ 横持扫 `PR-20261003-04`：182 条样本全标 `landscapeLeft`，方位 303° ± 13°，与同房间竖持的 288° / 298° 一致，没有 90° 跳变 | 相机预览与照片方向靠 `RotationCoordinator`（U03），模拟器看不到；罗盘参考边错 90° 也只有真机能看出 |
| 双语界面（Lee 2026-10-03）：英文 + 简体中文，跟随系统 / 每 App 语言；App 的 String Catalog 由编译器抽取（345 键，314 译，31 项开发者页标为不译），PropertyModel 与 CaptureCore 各一份手写目录 | ✓ | ✓ UI `ChineseInterfaceUITests`：中文启动后五个 tab、列表、房产页、Inspect、Light 指引都是中文 | 待 Lee 看中文措辞（截图见评审回应 §2f） | 存进记录里的生成文本（光线扫描状态行）按保存时的语言写入；`./scripts/strings-sync.sh` 抽取新字符串并列出没有中文的键 |
| 回家补记：房产页与 Compare 空格里 Add a note；School / Commute / Price comfort 三个类别；笔记挂在房产上不算一次看房 | ✓ | ✓ 单元 + 故障注入 + UI `NotesUITests` | — | Compare 九个维度都有来源，"Not in the app yet" 状态删除 |
| 最大辅助字号：Inspect、编辑面板、Light、结果面板、房产页、四个列表屏（Home / Properties / Inspect / Compare）不溢出不截断 | ✓ | ✓ UI `AdaptiveLayoutUITests`（元素必须在窗口宽度内；标题完整；搜索框在）+ 人工看截图（iPhone 默认 / XXXL / AX1 / AX5，iPad AX5） | — | 相机上的悬浮文字在 accessibility2 封顶（否则挡住取景器），底栏三个动作在 xxxLarge 封顶并支持 Large Content Viewer；面板与正文完全跟随 |
| 按住说话的辅助入口：VoiceOver 双击开始 / 结束、⌘D、`.startsMediaSession` | ✓ | — | — | 需真机开 VoiceOver / Switch Control 验收（U05） |
| 改地址使旧 pin 失效、过期结果丢弃 | ✓ | ✓ | — | |
| SunEngine：太阳位置、3×3 日盘判定、全年时段（Δ 不确定度 64 次抽样）、太阳走廊覆盖率 | ✓ | ✓ 13 项合成天空与解析解对照；SPA 算例；独立算法 0.011°；太阳位置 Swift / Python 1e-7°；走廊、时段与随机数流 Swift / Python 逐分钟、逐比特一致（`sun-bands.json`，2026-10-03） | — | `ios/Packages/SunEngine`；全年计算 0.05 秒（Release，Mac） |
| NorthResolver 融合（组内中位数、两两一致性、最大一致组合、佐证、方向灯；ADR-0009、ADR-0018） | ✓ | ✓ 22 个按文档手写的情形 + 200 个随机输入，Swift / Python 1e-9° | — | `ios/Packages/NorthResolver`，`northresolver-0.2`。候选目前只有罗盘一组：一组且 σ > 6° 是阻断，真机 σ 10–20°，所以方向灯是**阻断**、记录停在 R0（10-04 更正：此前写成"最多黄灯"是错的，评审 R04） |
| QualityEvaluator：走廊覆盖、方向、分割三盏灯按证据重算，校验器拒绝写入值与证据不符的记录（复审 R08） | ✓ | ✓ 29 个用例，Swift / Python 同一份；复审的六个探针全部拒绝 | — | 水平与追踪、镜头两盏灯在 schema 0.1.0 里没有可重算的证据，按写入值；"反射未识别"未判。见复审回应的 10-01 补记 |
| 罗盘读数全部保留（`raw.samples`），候选取中位数，σ 含扫动中的分散 | ✓ | ✓ CaptureCore 6 例 | ✓ 10-03 三份记录（`PR-20261003-01…03`，Lee 家客厅）：σ 10° / 17° / 11°，CLHeading 精度 10–22°，三份都过 Python 校验器且重算的灯与写入值一致；方向灯阻断（一组且 σ > 6°），按规则该如此 | 俯仰超过 30° 的读数保留但不参与合并（10-05 起；此前 50°，40–50° 一档有 41% 的读数转了 180°，把候选 σ 撑到 25–53°）。新规则下的 σ 等新版扫出的记录 |
| 照片缩略图存在行上、字节数守卫：列表不再为画缩略图加载照片；外部存储文件丢了（SwiftData 回 38 字节引用而非 nil）详情页写"照片还没到这台设备"而不是坏图；旧行启动时分批补缩略图 | ✓ | ✓ 单元 `ObservationTests` 两例（丢字节识别、谓词只找没缩略图的照片） | 待 Lee 装新版后看旧照片列表 | 组记忆 swiftdata-external-storage-original-bytes |
| ⌘D 口述改为场景命令（iPad 菜单栏可见，不进辅助树）；`-uitestEmpty` 空库启动；UI 测试启动关 UIKit 动画 | ✓ | ✓ UI `testEveryTabAnswersInLandscape`：空库横屏五个 tab 15 s 内应答，地图横屏搜索有结果 | — | 组记忆 swiftui-keyboard-shortcuts-as-commands、swiftui-searchable-empty-state-landscape-freeze |
| 发版脚手架（10-03 接入 pwe-tools 组）：`scripts/preflight.sh`（占位文件、冲突副本、干净工作区；接进 `test.sh`）、`scripts/testflight.sh`、`PrivacyInfo.xcprivacy`、版本 / 构建号来自构建设置、`AGENTS.md` | ✓ | 预检 ✓；`testflight.sh --no-upload` 走到归档一次 | — | 上传要 Lee 对构建号的 go，且 CloudKit production schema 先部署 |
| CloudKit schema：开发环境补全后 10-03 Lee 已部署到 Production（控制台里四个 `CD_` 类型在）；补全器（`PropertyStore.initializeCloudKitSchema`，DEBUG 参数 `-initializeCloudKitSchema`，真机上跑：`xcrun devicectl device process launch --console --terminate-existing --device <id> com.pwegroup.propertyreplay -- -initializeCloudKitSchema`，设备要解锁） | ✓ | — | ✓ 10-03 iPad 上跑过，控制台里四个记录类型的字段齐了 | 控制台里开发环境缺 `CD_originalText`、`CD_property`、`CD_mediaPath`、`CD_notes`：CloudKit 只在字段第一次有值时才建；补全后才能部署 Production |
| 姿态记录 ≤ 10 Hz + 第一帧 / 锚定帧 / 追踪状态变化帧（ADR-0020；10-03 一次 6.5 分钟扫描曾写出 25 MB） | ✓ | ✓ 单元 `PoseLogRateTests` | ✓ 10-03 晚三次扫描 `PR-20261003-05…07`：10.0 Hz，18–38 秒 0.29–0.59 MB，`pose_gap` ≤ 52 ms，三份都过校验器 | 漂移仍逐帧算；`frames_within / beyond` 按保留帧计 |
| SceneRecord 0.2.0 与 quality-0.2（ADR-0022）：内联网格与掩膜带长度和 SHA-256、Hero 变换链、太阳圆面候选的有效性、结果 revision、五盏灯全部按证据重算；0.1.0 照旧 | ✓ 两端校验器 | ✓ `scene-v2-cases.json` 57 例（13 接受 / 44 拒绝），Swift 与 Python 的灯与拒绝位置一致；SceneRecord 36 项、Python 96 项 | — | **只是契约**：App 写出的仍是 0.1.0，没有接任何检测器。阈值全是候选 |
| Light 扫描保留分析所需的输入（阶段 B，`04` §12）：Hero 静帧转正存在行上；帧卷（同帧的图像、姿态、内参、深度）落在 `Application Support/LightSpool/<行 uuid>/`，不同步不备份，14 天；记录写 0.2.0 revision 0；行的身份 = 采集会话 uuid | ✓ | ✓ CaptureCore 31 项（入选规则、写出与读回、四个方向的 Hero 角点、深度往返、清理）；PropertyModel 38 项；UI `LightScanUITests`（保存后行上有缩略图、详情页有 Hero、"N 帧保留 14 天"）；模拟器假相机按已知天空的假世界出帧 | ✓ 10-05 九段：Hero 竖持横持都转正；帧卷文件哈希与清单一致、重算摘要等于记录里的 `capture_digest`；每帧有深度且解得开；1.7–3.3 fps，每段 3–73 MB。发热耗电未量 | 分析任务（阶段 C）还没有，所以帧卷现在只存不算。10-05 起帧卷留到离视点 0.50 m（此前 0.15 m，抬头的帧没留下），每帧带偏移量 |
| Light 行的状态来自摘要列 `lightDigestData`，不再写进买家的 `text`；旧行启动时迁移（只动整句与模板全等且未编辑的） | ✓ | ✓ 单元 `LightDigestTests` 6 例 + UI 中英文 | 待 Lee 看旧扫描行的文字还在 | 新增的 CloudKit 字段 `CD_lightDigestData`：Lee 10-05 说已部署到 Production（我没能进控制台复核，登录过期）。同时修了四句中文的参数顺序（此前显示成"镜头覆盖了94路径的 冬季阳光%"） |
| 分割冒烟工具 `tools/segsmoke`（Mac 命令行，Vision 迭代分割） | ✓ | 自测图 + Codex 按 Lee 授权下载的 9 张真实网络照片【验】（`docs/spike/2026-10-04-segmentation-smoke.md` 同日补记） | — | 输入、来源、逐图日志、掩膜和失败观察在 `field/data/smoke/`；只是普通照片的接口冒烟，不替代 App 帧卷评估。细枝天空只返回局部小块，自动种子与真机性能未测 |
| 天空分割（相机帧 → 可见域网格）、日照结果页与回放 | — | — | — | 第三批剩余；方案在 `proposals/2026-10-03-sky-segmentation-plan.md`，三件事 10-03 已按 ADR-0019 定（累积网格 + 3–5 张关键帧掩膜、Save 之后算、W1 评估集 Lee 自家拍）；VisibilityCore 的累积层不等真机就能做 |

加了或改了界面文字：`./scripts/strings-sync.sh` 把编译器抽到的键并进 `ios/PropertyReplay/Localizable.xcstrings`，并列出还没有中文的键，然后把中文写进目录（`zh-Hans` → `stringUnit.value`）。包里的字符串（显示名、扫描指引）用 `String(localized:bundle:.module)`，目录手写在包目录下。中文启动看界面：`-AppleLanguages (zh-Hans) -AppleLocale zh_CN`。

跑测试：`./scripts/test.sh`（纯算法，Mac：NorthResolver、SceneRecord 含 QualityEvaluator、SunEngine、Python 参考）；`./scripts/ios-test.sh [unit|ui]`（模拟器；自建专用设备 "Property Replay iPhone"，跑完关机；关掉了 xcodebuild 失败后长达十分钟的诊断收集）。默认的 iPhone 17 / 18 Pro 模拟器会被别的项目会话占用，不要用。

UI 测试用 `-uitest` 启动参数：内存库 + 虚构样例，模拟器上用 DEBUG 的测试照片 / 测试笔记按钮代替相机和麦克风，Light scan 用假相机，地址补全用两套虚构的房子顶替 Apple Maps（不联网，不向外发地址）。可调参数：`-syntheticSweepSpeed <度/秒>`（0 = 不动）、`-syntheticSweepPasses 1`（只扫冬季那一遍）、`-failFirstLightSave`（第一次保存失败）、`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`（最大字号）。全套约 8 分钟，改界面必跑，iPad 另跑一遍：`PR_SIM_NAME="Property Replay iPad" PR_SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB ./scripts/ios-test.sh ui`（两套可以并行，给 iPad 那套单独的 `PROPERTYREPLAY_BUILD_ROOT`，否则抢同一个 DerivedData）。断言只能证明元素在窗口内、按钮里有文字；截断和观感要看截图（`xcresulttool export attachments`）。

发版（TestFlight）：`scripts/testflight.sh --no-upload` 走完预检（iCloud 占位文件、冲突副本、干净工作区）、纯算法测试、模拟器单元测试、每个字符串都有中文、归档；去掉 `--no-upload` 才上传并打 `testflight/<版本>-<构建号>` 标签。上传要 Lee 对这个构建号的一句"可以"（组规矩，每个构建都要），且第一次之前要在 CloudKit Console 把 schema 部署到 Production（脚本没看到 `PR_CLOUDKIT_SCHEMA_DEPLOYED=1` 就停）。签名用 Xcode 里登录的 Apple ID 或 ASC API key 三个环境变量（在 Lee 的 `~/.zshrc`，只加载不打印）。构建号是 git 提交数，版本号在 `ios/project.yml` 的 `MARKETING_VERSION`。隐私清单 `ios/PropertyReplay/PrivacyInfo.xcprivacy`（目前只有 UserDefaults CA92.1；加了新 API 要补）。

真机排错：崩溃报告从配对的设备取 `xcrun devicectl device info files --device <id> --domain-type systemCrashLogs` / `device copy from`；App 容器文件 `--domain-type appDataContainer --domain-identifier com.pwegroup.propertyreplay`；看 `os.Logger` 输出用 `device process launch --console --environment-variables '{"OS_ACTIVITY_DT_MODE": "YES"}' … -- -参数`（参数放 `--` 后）。CloudKit 在模拟器上不可用（Lee 的账户开了高级数据保护），同步只能真机验。

将来加 Share Extension（ADR-0014）时：**数据库不进 App Group**（`groupContainer: .none`），扩展只往收件箱写文件——同组 PWE Receipts 的 1.0 因为 CloudKit 镜像在挂起时持有共享容器里的 SQLite 锁被 0xdead10cc 杀掉（组记忆 swiftdata-app-group-store-dead10cc）。

界面评审：`reviews/2026-09-30-apple-design-review.md`（Claude）；`reviews/2026-10-01-uiux-adaptive-review.md`（Codex，24 条）与回应 `…-response.md`：三轮都已做完并各自提交（第一轮 P1 与大字号；第二轮 iPad 分栏、共用状态、Compare、相机旋转；第三轮同步状态、设置分层、输入、删除确认、提示文字对比度）。§2c 是第三轮提交后补看各档字号截图修掉的四处；§2d 是仍然排在后面的，§3 是要 Lee 决定的，§4 是只能在真机验收的。改界面后要看的不只是改到的那一屏：四个列表屏在默认、XXXL、最大辅助字号下各看一眼；暗色也跑一遍（`PR_APPEARANCE=dark ./scripts/ios-test.sh ui -resultBundlePath …`，10-03 全套 24/24，16 屏人工看过没有要改的，列表行的缩略图走的是新存的 `thumbnailData`）。

第二轮复审的逐条回应：`reviews/2026-09-30-progress-reaudit-response.md`。

仍然开着的：
- Light Replay（回家在照片上拖时间看光）是当前主线：方案 v2（`proposals/2026-10-04-light-replay-plan-v2.md`，Lee 10-04 认可，按 Codex 的 v2 复审修订）。**阶段 A 已退出**（ADR-0021 / 0022、`03` §11、`04` §6 与 §12、`05` §2a、`07` §5 与 §5a、两端校验器与 81 例 fixture、冒烟工具；Codex 的 A01–A04 已修，回应在 `reviews/2026-10-04-stage-a-delivery-review-response.md`；网络照片的接口冒烟由 Codex 按 Lee 授权补齐，读法在 spike 补记）。**阶段 B 已实现**（见状态表两行与 `04` §12 末段）。**现在卡在闸门 1**：Lee 用这一版在自家拍评估片段，我从设备取回帧卷做实验 1（三条分割路径的比较）。不等闸门可以并行做的是阶段 C 的纯算法部分：VisibilityCore（采样、深度重投影、按不同帧计票）与分析任务的骨架，用模拟器假世界的已知天空验。逐条回应在 `reviews/2026-10-04-light-replay-plan-v2-review-response.md`。TestFlight 等回放做好再上（Lee 10-03）；内测 / 外测分步与内部测试者名单到阶段 E 再请 Lee 定。
- Light 扫描（10-05 排错后留下的，详见 `spike/2026-10-05-scan-coverage.md` §4）：0.40 m 漂移上限仍是候选，放不放宽要等阶段 C 量过深度重投影的误差后用 ADR 定；All-year 是否分两遍引导等新版数据；罗盘读数与姿态约 0.17 s 的时间差没有修正。复算脚本 `engine/scripts/scan_postmortem.py <记录.json…>`，取回的设备数据在本机 `~/Library/Application Support/propertyreplay-field/`（不在仓库目录里，仓库在 iCloud）。
- QualityEvaluator 没有重算的两盏灯（水平与追踪、镜头）和"反射未识别"：要先给 schema 加检测器证据字段。
- 佐证门槛 15°（ADR-0018）是候选值，日晷 spike 校准（`07` 第 5 节）。
- 方向候选只有罗盘一组；墙面对齐、窗光斑、太阳圆面、VPS 的采集未做。
- iOS 27 SDK 标记弃用、Release 归档时报出的四处（10-03 `testflight.sh --no-upload`），都不影响现在的行为：`CLLocationManager.headingOrientation`（横屏罗盘参考边靠它）→ `headingBody: CLBodyIdentifiable`，SDK 里只有 `UIView` 采纳——把取景器那个 view（或 `InterfaceOrientationReader` 的 view）交给它，罗盘就按那个 view 在屏幕上的朝向参考，手动的 `UIInterfaceOrientation → CLDeviceOrientation` 映射可以整段删掉，真机验过横屏后再换；`UIWindowScene.interfaceOrientation` → `effectiveGeometry.interfaceOrientation`；`installTap(onBus:bufferSize:format:block:)` → 带 `error:` 的同名方法（会抛）；`String(localized:)` 里插入非本地化的 `reason` 得到的是调试描述。
- `installTap` 在 iOS 27 标为弃用，替代 API 未确认，暂留。
- CloudKit production schema 部署（上架前）；跨设备同日 `scene_id` 冲突（ADR-0017 后果）。
- Room 仍是字符串标签（L0），`Question` 模型未拆出。

## 等 Lee

- **[给料] 用 10-05 午后的版本（`acb48cf`）再扫评估片段** — 已收到 9 段（`PR-20261005-01…09`，已取回本机）。还差约 10 段：隔玻璃有反光或镜面的 1–2 段、树冠下 3–4 段、檐下 2–3 段、开敞庭院 2–3 段。问题选 Winter 或 All-year 都行，不必扫到 90%；每段点 Start 之后先把手机端平停一秒（找北）。其中四段各带一种拍法（Codex 10-05 评审要的）：打开后等十秒再点 Start；从端平慢慢抬到头顶；中途竖横换一次；一段扫满两分钟。扫完告诉我，我从手机取回 · 不给：闸门 1 过不了，分割路径定不下来；10-05 改的指引有没有用也无从知道 · 自 2026-10-04
- **[动手] 真机验收清单（10-01 起）** — You › 隐私与数据的同步行、用真实地址选一条建议、Light 里晴天把手机端平对着太阳看 "Now" 圆点压不压在太阳上、VoiceOver 口述一条笔记 · 不做：HANDOFF 状态表这几行停在"待真机" · 自 2026-10-01
- **[给料] 日晷真值** — 推荐：spike W2 按 `08` 协议采几组 solar + map 同在的场景 · 不给：ADR-0018 的 15° 佐证门槛只能停在候选 · 自 2026-10-03
- **[决定] 正式商标意见、域名、仓库是否改名** — 上架前 · 自 2026-09-30
