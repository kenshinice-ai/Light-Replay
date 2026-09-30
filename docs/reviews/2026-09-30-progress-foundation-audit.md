# Property Replay · 阶段进展与地基审计

日期：2026-09-30（Australia/Melbourne）
审计人：Codex。范围：当前仓库、工程配置、数据层、采集链、现有测试，以及审计期间出现并提交的 Inspect 工作。业务代码未修改；未提交、推送、部署或执行真机采集。

## 1. 结论

**项目已经从方案进入可构建的原生原型，但尚未证明核心技术可行性。** 五个 tab、房产列表/地图、本地数据模型、偏好与 R0 采集记录器都已存在；SunEngine、NorthResolver、天空可见域、全年时段回放还没有生产实现。

现有测试全部通过，说明数据校验、合成记录与基础模型有了起点；不能据此宣布“20 秒判断全年日照”已经实现。当前记录器强制输出 `R0 + blocked + analysis=[]`，暂时不会产生假日照小时，这是应保留的保护。

优先顺序建议：**记录不丢失 → 锚点/时间/方向对齐 → 质量门槛闭合 → 最小真机采集 → 单点日照验证 → 看房记忆与 AI。** 五个 tab 保留；暂不继续扩张功能面。

## 2. 审计基线与并行工作边界

- 实际目录：`/Users/llmacbookpro/Library/Mobile Documents/com~apple~CloudDocs/PARADISE PRODUCTION/07 TOOLS/light_replay`。
- 起始分支：`docs/blueprint-v1`；起始提交：`55abaf130c57245f1000f27c79dd974d475b1da6`；工作区起初干净。
- 审计期间 PR #1 已合并：merge commit `31b18717bd319c4a89f21859bbee2dc3b51bc6bf`，远端 main 已指向它。合并时间为 Melbourne 2026-09-30 15:25:12。
- 这两个提交的文件树相同（`git diff 55abaf1 31b1871` 为空）；本轮现有测试覆盖的是这一文件树。
- 随后工作区切换到 `feat/inspect-screen`，另一条工作线加入 Inspection/Observation、照片存储、相机、语音和 FM 结构化，并提交 `45bb55f66e566c7ba0d7420d995030b70ff2c819`、打开 PR #2。本报告第 6 节单独评审这批工作，并为它重跑模拟器测试；旧基线成绩不转移。之后 InspectView 仍有并行编辑，本报告不声明所有后续改动都已验收。
- 收尾时 HEAD 为 `b41c2e8`（转写失败提示去重），该显示文案修复由另一条工作线提交；本轮14测试对应此前构建快照，不自动视为这个最后提交的整套验收。
- 源码行号按本轮读取时文件记录；后续修复或并行编辑可能移动行号。正式修复前重新定位符号。

## 3. 实际进展地图

| 能力 | 当前证据 | 状态与验收边界 |
|---|---|---|
| iOS 27 工程 | `ios/project.yml`、生成的 Xcode 工程、Swift 6 配置 | 已实现；本轮 simulator build/test 成功 |
| 五个 tab | RootView：Home / Properties / Inspect / Compare / You | 已实现；本轮没有完成逐屏点击验收 |
| Property、UserPreferences | SwiftData，地址、坐标、状态、优先级等 | 已实现；4 个模型测试通过，但使用内存容器 |
| 手动添加房产 | 地址输入 + Apple 地理编码 | 已实现；地理编码失败/错误候选/磁盘写入异常未验收 |
| Properties List / Map | 分组列表、状态 pin、详情入口、无坐标数量提示 | 已实现；真实地址纠正、定位拒绝、重启后恢复未验收 |
| Compare | 2–3 套选择、读取偏好、显示 Unknown | 部分实现；没有实际日照或观察比较数据 |
| You | 个人名字、优先级、haptics、高度、容差、删除入口 | 部分实现；高度与容差未接入采集器，haptics 没有回放场景 |
| SceneRecord | Swift/Python 校验器、CLI、交叉核对 | 已实现且测试通过；仍有本报告列出的语义门槛缺口 |
| CaptureCore | ARSession、位姿、intrinsics、漂移、heading/location | 部分实现；无图像、深度资产、mask、太阳走廊；只输出 R0 |
| 相机照片、语音、观察摘要 | PR #2（45bb55f），AVFoundation/Speech/FM/Observation | 部分实现；本轮新构建与14测试通过；真机照片/语音/权限/持久化未验收 |
| SunEngine / NorthResolver | `docs/05`、`docs/06`、历史复算脚本 | 计划；历史脚本不是 App 的实现 |
| 天空分割 / 可见域 / Viewpoint 重投影 | 架构与协议 | 计划；没有实际 Vision 管线或可见域模块 |
| Light Replay、热力图、时段滑杆 | 产品规范；详情页提示文字 | 计划；没有可使用的结果页 |
| Share Extension、OCR、URL 解析 | 规范；工程无 extension target | 计划 |
| Foundation Models | 基线无集成；PR #2 NoteStructurer 已 import | 已有端侧文本结构化路径；真机可用性、语言、内容正确性未验证 |
| PCC | ADR/方案，工程无 entitlement 配置 | 接入尚未实现；账号审批状态不能由源码推断 |
| report / Light Passport | report/README 与规范 | 计划 |
| 真值/holdout | field 模板 | 未见已跟踪的现场记录；本轮未证明现场精度 |

本轮只读确认：已连接的 iPhone 17 Pro 运行 iOS 27.0.1、Developer Mode enabled。没有安装本 App，也没有启动相机或麦克风；设备就绪不等于测量已验证。

## 4. 本轮验证与可复查证据

### 已完成

1. `./scripts/test.sh`：28 个 SceneRecord XCTest，通过；30 个 Python unittest（含 Swift parity），通过。
2. 在独立 `/private/tmp` DerivedData 下执行当前工程的 iOS 27 simulator `xcodebuild test`：App smoke 1、CaptureCore 5、PropertyModel 4，共 10 个测试，通过。
3. 合成 SceneRecord 对抗性探针：6 种语义无效/不充分记录在 Swift 与 Python 都被接受（第 5 节 F05）。
4. 用当前 CaptureLog/Builder 源码编译临时纯算法探针：复现编号碰撞、锚点矛盾、负真北输入被变成合法候选。
5. PR #2 新工作树另行执行 simulator test：App smoke 1、CaptureCore 5、PropertyModel/Observation 8，共14测试通过；运行时照片/录音/模型行为仍未验证。
6. Git 远端与 PR 状态核对；私有 archive 和 field/data 未被跟踪；Markdown 内部链接检查（旧的简单检查器把历史 review 内代码示例识别为链接，核实后不计作断链）。

### 本轮未完成

- 五 tab 逐屏交互、真实地理编码、磁盘重启恢复、UI 删除与资产清理。
- 真机 ARKit、相机、语音、FM、PCC、天空分割、方向标定及日照精度。
- 新 Inspect 的语音权限、模型下载、真实照片/录音、交互与磁盘恢复验证（新构建和合成测试已完成）。
- TestFlight、App Store、用户访谈、重复使用率。

现有 smoke test 只核 bundle ID，不是用户旅程测试；PropertyModel 测试用 `inMemory:true`，不是持久化恢复测试。截至新 Inspect 测试，本轮套件计数为28（Swift SceneRecord）+30（Python）+14（iOS）=72；旧iOS的10个已包含在新14个内，不重复累加。这不是72个独立产品场景。

### 本机日志

- `/private/tmp/propertyreplay-audit-20260930-xcode.log`
- `/private/tmp/propertyreplay-audit-20260930/tests.xcresult`
- `/private/tmp/propertyreplay-audit-20260930-inspect.log`
- `/private/tmp/propertyreplay-audit-20260930/inspect-tests.xcresult`
- `/private/tmp/propertyreplay-audit-probes.json`
- `/private/tmp/propertyreplay-audit-builder/`：合成 Builder 探针及构建物

临时目录不是长期档案；后续验收应把去标识摘要写入版本化 review。可复算源码附在同目录的 `2026-09-30-schema-probes.py` 与 `2026-09-30-builder-probe.swift`。

## 5. 已提交基线中的问题

P1：继续真实采集或解锁 R1 前应修。P2：内部原型可继续，但面向用户前应修。下述是缺陷或验收缺口，不把计划中的功能缺失都算成 bug。

### F01 · P1 · 同一天再次打开采集界面会覆盖已有记录

位置：`ios/PropertyReplay/Capture/CaptureValidatorView.swift:10,61–72`；`SceneRecordBuilder.swift:143–148`。

`sequence` 只存在于 View 的 State，重新创建 View/重启 App 后回到 1。目录名是 `PR-YYYYMMDD-NN`，写入固定 `scene.json`，`.atomic` 保证原子替换但不阻止覆盖。

**复算**：同一天、两个相隔 120 秒的日志、两个重新开始的 sequence=1，得到完全相同 ID。并非浮点问题或 iCloud 问题，而是命名策略。

改法：真实身份用 UUID/ULID；日期序号只做显示名。存储层拒绝覆盖已存在记录，索引与资产原子提交，失败保留草稿。
验收：同一天两套房、多点、多次返回界面、重启各采一次，记录全部独立、旧文件哈希不变。

### F02 · P1 · “删除全部测量”与实际清理范围不一致

位置：基线 `PropertyStore.swift:23–28`；`YouView.swift:59–60`；`CaptureValidatorView.swift:66–69`。

删除只删除 SwiftData 中 Property/UserPreferences；测量文件另存于 Documents/PR-…，无数据库引用，也没有清理逻辑。单套房删除同样没有测量目录归属可以清理。错误被 `try?` 吞掉，用户无法知道清理是否失败。

PR #2 新工作增加了 Observation 及 `MediaStore.deleteAll()`，开始清理照片，但依然没有覆盖 PR 测量目录；单套房照片清理也需与列表左滑、详情删除统一。

改法：统一 AssetStore 与记录归属索引，删除数据库记录与资产均可核查；错误提示、恢复/重试和孤儿资产扫描。不要靠盲删所有 Documents 文件。
验收：A/B 两套房各有照片与测量；删 A 只删 A；删全部清除所有项目资产；权限/IO 失败时不显示成功。

### F03 · P1 · 方向候选跨会话残留，且未转换到 AR 参考轴

位置：`CaptureRecorder.swift:49–68,179–182`；`SceneRecordBuilder.swift:57–72`。

start() 重置 frames/anchor，却没有清 heading/location；heading 只在 nil 时记录第一条。第二次扫描可能一直使用上一会话的方向与时刻；第一次无效读数也会挡住后续有效读数。

Builder 直接把 trueHeading 写成 Δ。规范中的 Δ 是 AR −Z 轴真方位，CLHeading 默认参考的是设备顶部，后摄光轴与它不是一回事；首次 heading 回调也没有与 AR 起始姿态同步。需要用同一采样时刻的相机 AR 方位消去手机转动，并明确 heading body/姿态轴约定。

**本机 SDK 证据**：`CoreLocation.framework/Headers/CLHeading.h` 描述方向从设备顶部参考；`CLLocationManager.h` 默认 portrait、iOS 27 引入 headingBody。新接口存在不等于已解决坐标对应。
**探针**：trueHeading=-1、headingAccuracy=5 被 Builder 接受并转换为 yaw=359、valid=true；有效性只检查 accuracy。

改法：每个 session 清空来源；仅接纳有效、足够新鲜的读数；保存多个同步样本、明确轴变换、求 Δ 后才进入 NorthResolver。负/不可用真北保持无效，不能取模造合法值。
验收：连续两次扫描转向 90°；先无效后有效；定位拒绝；横竖屏/俯仰变化；所有候选的时间与所属会话可核对。

### F04 · P1 · 记录的锚点和漂移使用不同基准

位置：`CaptureRecorder.swift:154–157`；`CaptureLog.swift:124–127`；`SceneRecordBuilder.swift:17–18,103–118`。

Recorder 在第一帧 tracking normal 时锁 anchor，却会在 initializing 时就记录 frame。Builder 取 frames.first.position 当 target/lock anchor。若初始化时从 x=0 移动到 x=1 后才 normal，Recorder 报告 normal 帧 offset=0，导出锚点却是 x=0。

**合成探针已复现**：第二帧位置 x=1、offset=0；JSON lock anchor x=0。

改法：CaptureLog 显式保存锁定 anchor、locked_at/frame_id；预锁定帧单独标记，不用于可见域；Hero 绑定明确拍摄动作，不把“第一个位姿样本”叫主照片。
验收：初始化时移动/重定位后，每个已用帧 offset 与导出 anchor 的距离相符；Hero 的 frame、图像、时间、内参匹配。

### F05 · P1 · 校验器验证字段形状，未封闭质量门槛

位置：`SceneValidator.swift:178–192,372–398`；Python `scenerecord.py` 的 `_evidence` 与 quality 校验。

两份实现对以下 6 个合成 R1 记录均 ACCEPT：

| 探针 | 为什么不能当通过记录 |
|---|---|
| 单 magnetic、resolved σ=12°，north=warn | ADR-0009 要求单组 σ>6° 阻断 |
| 没有 lens gate | 当前协议要求五盏灯 |
| coverage=1%，coverage gate=pass | 与 <70% 阻断相反 |
| 已覆盖单元全为 glass，segmentation=pass | glass/走廊比例超 25% 应阻断 |
| frame.t=99999，但 session 仅约 12 秒 | 时间不属于采集会话 |
| target anchor 与 lock anchor 不同 | 同视点前提不成立 |

这是两种实现共同遵循了弱约束，所以 parity 全绿仍会漏掉。**当前 App 的 Builder 始终 R0，尚未证明实际 App 产出过 false-valid；问题是未来解锁 R1 时的防线缺口。**

改法：单独定义可测试 QualityEvaluator（五灯/门槛版本/方向规则），校验器验证 gate 与证据一致；确认例外有显式记录。shape 校验、物理输入检查、资产存在/哈希检查分层，不把 JSON 字段 `passed` 当作真实验收证明。
验收：上述 6 个探针拒绝；合法边界记录通过；未知保持未知；所有输入不足路径拒绝 R1。现有合成 ready_record 也需补 lens 等契约字段。

### F06 · P2 · 采集生命周期和错误处理尚不完整

位置：`CaptureValidatorView.swift`；`CaptureRecorder.swift`。

没有 onDisappear/scenePhase 的暂停或取消；没有相机拒绝、ARSession failure/interruption、定位失败的完整状态。开始后切 tab、进入后台或按返回，没有显式停止协议。

改法：明确 idle/preparing/recording/stopping/failed；退出与后台统一 stop/cancel；权限拒绝与追踪中断落到可导出的失败原因，不留假 running。
验收：开始后切 tab/后台/返回/拒绝相机/中断，设备采集停止，状态与数据一致。本条是静态风险，真机行为未测。

### F07 · P2 · 房产与设置没有进入 Measure

位置：基线 `InspectView.swift:22`（PR #2 新工作仍直接 `CaptureValidatorView()`）；`YouView.swift:34–42`；`CaptureRecorder.swift:25–26,94–99`。

用户选中的 Property 没传入验证器；标签固定为 Capture validator target，targetHeightM=nil，容差仍默认 0.15。You 的 Measure height 与 tolerance 可编辑，却不改变实际日志。

改法：MeasurementContext 明确 property_id/inspection_id/target_id/确认高度/问题范围/参数快照；Advanced 参数仅内部调试模式，普通消费者不能改已预注册门槛。
验收：A 房/1.2m 与 B 房/0.5m 产生正确关联；参数改变有版本/场景快照；高级入口可明确作为未绑定的独立调试采集，不冒充房产测量。

### F08 · P2 · 地址失败提示被关闭，且不能修正 pin

位置：`AddPropertyView.swift:55–68`；`PropertyDetailView.swift:25–32`。

地理编码失败后设置 geocodeNote，紧接着 dismiss；用户很可能看不到。文案说“以后可编辑”，但详情里没有地址/地图点修正入口。只取首个 geocode 结果，没有候选确认；保存靠 autosave，缺显式失败呈现。

改法：保留“地址记录成功/定位失败”两个独立状态；允许离线保存、重试、候选选择与手工 pin；显式数据库保存失败不关闭表单。地理编码涉及 Apple 服务，不能把所有数据均不离开设备作绝对承诺。
验收：离线、模糊地址、错误地点、取消期间返回结果、磁盘失败都能恢复；用户能纠正 pin，而不用删房重建。

### F09 · P2 · 存储失败会静默切换临时内存

位置：`PropertyReplayApp.swift:9–15`。

磁盘 ModelContainer 初始化失败，App 照常打开内存库，只在 You/About 放诊断字符串。继续添加的数据下次启动消失；用户可能把空列表当作真实数据丢失。

改法：可见的恢复/只读状态；明确说明持久化不可用；未恢复前不让正常 Save 冒充成功；保留原库，不自动覆盖或重建。
验收：损坏/不兼容 store、空间不足、恢复重试；数据原文件保存；不会静默丢记录。

### F10 · P2 · 记录缺少可回放的实际资产和统一时间基准

位置：`CaptureRecorder.swift:137–173`；`SceneRecordBuilder.swift:30–34,38–45`。

仅记录 hasDepth 标志，不保存 depth/confidence/image/mask；所谓 hero_frame 没有 image_ref。t 取回调时 Date，与 ARFrame.timestamp 没建立保存映射。10Hz 位姿采样也与 docs/03“姿态每帧”不同；maxDrift 是已保存样本的 max，可能漏掉未保存峰值。

这是部分实现，不要求本轮马上具备所有功能；但这些数据**不能在以后补回**，不能用当前日志证明照片与测量同步。

改法：统一 monotonic frame 时间 + wall-clock 映射，保存必要图像/深度/内参与像素方向；快照版本、丢帧和峰值漂移摘要；完整资产 manifest。
验收：离线回放能重建同一结果；不同回调延迟不改变采样时间；源资产存在、尺寸/裁切与内参一致。

### F11 · P2 · 证据措辞把推算日期的日照当“观察”

位置：`ADR-0013-evidence-levels.md:15–26`；`docs/01-product-spec.md:47–48`。

现场测量的是当前可见域；未来冬至直射时段是基于该可见域及太阳算法的推算。稳定直射不自动等于未来日期实测；点击“确认”也不应把用户认定变为外部验证事实。Prep 示例在遮挡 Unknown 时直接断言客厅无直射/最暗，超出了输入。

改法：展示原始 observation、computed result、user confirmed 三个来源层；冬至结果写“按当前遮挡条件推算”；季节树冠/未来建筑/云保持情景；将契约变化写 ADR 后同步规范。
验收：未确认窗向/遮挡时不输出室内日照事实；未来日期结果有假设与来源；用户确认不会抹掉测量/推断差异。

### F12 · P2 · 文档与测试覆盖落后于产品范围

- scripts/test.sh 只跑 SceneRecord + Python，不含 CaptureCore/PropertyModel/App 的 xcodebuild tests；“全部测试”需要明确两条命令或一个汇总入口。
- smoke 只验证 bundle ID；没有地图 pin、退出采集、文件不覆盖、文件清理、重启恢复、权限与录音中断的回归。
- docs/HANDOFF §7 同时保留三个 destination/6 tests 与五 tab/10 tests；docs/04 标题仍写“四灯”；docs/03 示例少 lens；历史 review 中的三个“断链”是内联代码示例，不能算真实断链；链接检查应先过滤代码。
- README/HANDOFF 用“20秒后全年直射时段”的陈述未标“产品目标”；核心模块尚未存在。
- D_near/max_drift_m 既作阈值又作观测值，应该拆 `drift_limit_m` 与 `drift_observed_max_m` 等明确名字。
- 无 CI status checks；PR 合并是 Git 状态，不是现场产品验收。

改法：建立模块完成/验证矩阵；改措辞与测试入口；对已发现的真实失败写回归，而非继续堆镜像实现测试。

## 6. PR #2 Inspect 新工作：合并前应核对的风险

这批工作已提交45bb55f并打开 PR #2；另有并行编辑。以下对读取快照负责：编译/合成测试通过，但没有真机录音与用户操作证据，不能判为已发布或已验收。

### D01 · P1 · preparing 状态松手不能阻止稍后开始录音

位置：新 `NoteRecorder.swift:30–65,78–115`；`InspectView.swift` 的 noteButton / onDisappear。

45bb55f 增加了 pressActive：松手后最终 stop。这比最初草稿好，但检查位于 engine.start()/analyzer.start()之后，仍没有取消正在权限、下载与格式准备期间 await 的 start task。松手后可能先打开麦克风再停止；onDisappear 仅停 camera/sensors，没停 recorder。没有 session token/取消传播，尚不能称为严格 push-to-talk。

要求：持有 start/record task；松手、返回、切 tab、后台立即取消；每个 await 后检查 session token；资源预下载与实时录音分离；true push-to-talk 的实际麦克风生命周期验收。

### D02 · P1 · 仅 kind=light/source=sensor 就自动标 measured

位置：新 `InspectionObservation.swift` 的 `level(for:source:)`；新 `ObservationTests.swift` 把 `.light + .sensor => .observedMeasured` 当正确期望。

没有 scene_id/quality/passed 校验就赋 measured，违背 ADR-0013。当前没有真正保存 light Observation 的入口，所以是模型层的潜在错误，不是已证明的用户输出。

要求：未关联 SceneRecord 默认 Unknown；校验通过后展示 computed/measured 对应来源；不要让测试固定一个尚无证据的升级规则。

### D03 · P1 · 保存失败后仍清掉照片/语音草稿

位置：新 `InspectView.swift:223–242`（save）。

JPEG 保存与数据库 save 都用 try?；随后无条件清 draft，并可能把 property 标 inspected。用户可能看到“完成”，但照片文件或记录没有保存。

要求：保存资产和模型成功后才清草稿；失败提示与重试；避免数据库成功、资产缺失或资产成功、数据库失败成为静默孤儿。级联删模型也不等于删实际 JPEG 文件。

### 新工作状态判断

方向有价值：开始将现场记录挂到 Property/Inspection；保留原话、单独存模型摘要；不开云端、不落盘音频的意图明确。独立 build/tests 本轮已经通过，但仍需磁盘恢复、真机照片与语音权限、AI 内容回归，尤其先过 D01–D03。只有合成规则通过，不能把真实相机/语音/模型行为标成“已验证”。

## 7. 推荐执行顺序与验收关卡

### Gate A · 记录基础完整（下一批）

- F01、F02、F04、F07、F09 与新工作 D03。
- 建统一 MeasurementContext/AssetStore，记录身份与来源稳定；保留所有未知；参数快照明确。
- 验收：两套房 × 两个点 × 重开 App，无覆盖、无串房；删除只删对应资产；失败不丢草稿；磁盘重新打开能恢复。

### Gate B · 采集可信且可终止

- F03、F06、F10、D01；真实保存一份可重放的 R0 采集。
- 真机测：权限拒绝、返回、后台、中断、重定位；照片/姿态/内参/深度时间一致。
- 验收：不录错会话、不留后台采集；每帧的 anchor、t、来源可追溯；失败仍 R0。

### Gate C · 质量门槛与核心单点算法

- 先修 F05，再接 SunEngine、NorthResolver、VisibilityCore；独立算法测试与物理夹具。
- 几何单元：N/E/S/W、画面上沿、0/360°、AR轴/真北转换；随机性用可复现采样。
- 再用固定点白卡/延时验证进出阴影时刻；按 docs/07 预注册门槛统计，保留 holdout。
- 验收：拒绝 6 个坏记录；合法记录通过；只有真实完整输入才解锁 R1；未知不被解释成遮挡/直射。

### Gate D · 看房记忆与 AI

- 五个 tab 保留；闭合 Add → Inspect → Save → Restart → Your inspection → Compare。
- D02、F08、F11；用户语音原文、模型建议与计算结果分开；UI 错误状态可恢复。
- 正式观察用户重复使用之前，先证明他们的资料能保存、找回、纠正和删除。

### PCC 的位置

PCC 可以晚接。当前没有资格/entitlement证据不能算启用；本地模板应可完成全链路。先把确定性记录和端侧能力降级做好，PCC 不应成为下一轮阻塞点。

## 8. 给 Lee 的具体判断

- 五个 tab 的需求没有问题，Map 放 Properties 内也合理，保留。
- 当前最大风险是基础记录与验收边界，不是再选一个 AI 模型。
- “地基已全部做好”应修正为：“工程、规范和基础原型已建立；数据完整性与采集一致性待修；核心日照能力尚未验证”。
- 下一轮以 Gate A/B 为先，核心算法作为单独可测试模块推进；不要直接上消费者 TestFlight 当实测工具。
- 本轮为审计与修复建议，未执行修复，未改变任何核心产品决定。
