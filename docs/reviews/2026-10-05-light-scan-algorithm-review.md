# Light Scan 算法修复审计

日期：2026-10-05（Australia/Melbourne）。评审：Codex。状态：**LS01、LS02、LS03 待修；没有修改实现，没有 commit / push。**

状态更新（2026-10-05，Claude）：三条已修，逐条回应与回归见 `2026-10-05-light-scan-algorithm-review-response.md`。本文其余部分是 Codex 的原文。

基线：`1a27949`，分支 `feat/inspect-screen`，审计开始时工作区干净【验】。范围：算法提交 `d103f5a` 与后续说明提交 `1a27949`，连同采集、保存、NorthResolver 与覆盖率调用链。数字的【验】仅指本轮软件运行或本地记录复算；版本、日期、编号和代码字面量用于定位。合成输入没有真实地址或用户数据。

## 判断

修复方向合理：相机抬头时排除不可靠的航向读数；实时覆盖使用规范中的漂移上限；帧卷多留实验所需的输入；弧线名称说明季节。保持 R0、不输出日照小时的边界也仍在。

但“整场中位数与保存候选一致”尚未成立，发现 **2 项算法 P2 问题，另有 1 项相关 UI P2 问题【验】**。先修 LS01，再修 LS02；LS03 随季节标签补齐。没有发现本次修改引入的 P1 数据丢失或日照时长误算；这不代表新版已经通过真机或现场验收。

## LS01 · P2：开扫前的预览读数长期参与实时方向，保存候选没有它们

位置：`ios/PropertyReplay/Light/LightScanModel.swift:188–200、401–404`；`ios/Packages/CaptureCore/Sources/CaptureCore/CaptureRecorder.swift:128–130、385–386`。

`handle()` 在预览阶段就调用 `liveYaw.add()`，不检查是否正在记录。按 Start 时，`CaptureRecorder.start()` 清空 `headings`，但 `LightScanModel.start()` 不重置 `liveYaw`。因此整场中位数的两个“整场”具有不同起点：屏幕包含预览期，保存候选只用正式采集期。

复现：预览先积累 **400 条 Δ=115°**，开扫后增加 **200 条 Δ=100°**，读数有效、相机端平、报告精度相同。当前 Swift `LiveYaw` 得到 **115°**，正式采集读数通过保存路径所用的 `NorthResolver.merge` 得到 **100°【验】**。这是合成状态复现结合调用链审查，不是对 Lee 的扫描断言实际偏了这个角度。

影响：如果在预览里等罗盘或选择问题，初始偏差会持续影响太阳路径、覆盖率与箭头；保存后却得到不同方向。旧窗口也可能短暂包含预览样本，本次改成全历史后，影响会持续到正式扫描里的稳定读数超过预览数量。源码与记录说明中的“同一场采集”不符。

改法：明确正式采集的证据起点。最直接是在 Start 时重置实时累积，并确保不会把 Start 前的 `latestHeading` 再次计入。如果需要保留预览校准，显式保存这批校准证据并让实时与离线使用相同输入；不要靠不可复算的内存历史。

关闭条件：预览带偏差、正式采集稳定、预览较长、开扫后暂时没有新罗盘读数的场景都有回归；实时与保存候选的差异只来自已声明的时间配对容差。模拟器使用 `fixedYaw`，现有 Light UI 测试不能覆盖这个真实罗盘状态问题。

## LS02 · P2：反复抽稀改变历史读数权重，长扫描重新偏向近期航向

位置：`ios/Packages/CaptureCore/Sources/CaptureCore/ScanCoach.swift:134–153`。

超过 `LiveYaw.capacity` 时，已累计数组隔条保留；之后的新读数却每条都加入。第二次抽稀时，最早读数又被减半。合并仍把每条保留样本等权计票，因此这不是原始全历史的中位数：越早的读数被重复降权。保存候选使用完整 `log.headings`，没有这种抽稀。

复现：先加入 **2400 条 Δ=100°**，随后加入 **1201 条 Δ=130°**。全量 **3601 条** 的中位数仍为 **100°**；当前实时实现经过抽稀只保留 **1201 条**，结果为 **130°【验】**。新读数原本占约 **33.4%**，抽稀后却能主导结果【验】。脚本直接编译仓库中的 Swift 定义。

影响：长扫描或长预览可能重新出现方向移动，且与保存时方向相差 **30°【验，合成反例】**。现有 `testTheWholeSessionOutweighsTheLastFewSeconds` 最后持续加入原方向，因此能通过；它没有覆盖“达到容量后持续偏向另一个方向”的情况。本轮旧记录按新俯仰规则最多有 **1528 条**可用读数，未达到容量【验】；不把该合成边界说成 Lee 已经遇到的问题。

改法：如果数据量允许，保留本场全部可用方向样本；若需要有界累积，使用保留历史统计权重的方案，并在规范中说明近似误差。不可重复削减旧样本、同时让新样本满权。还要保证保存候选遵循相同输入和统计策略。

关闭条件：容量前后、连续多轮压缩、跨北向接缝、方向前后分布不同的输入，与全量参考比较；同时验证方向、σ 和样本数量含义。容差预先声明，不能只测返回原方向时的结果。

## LS03 · P2：加长后的季节标签在最大辅助字号被屏幕裁切

位置：新增文字 `ios/PropertyReplay/Light/LightScanModel.swift:363–365`；绘制 `ios/PropertyReplay/Light/SunPathOverlay.swift:23–25、62–63`。

最大字号的 `AdaptiveLayoutUITests.testLightScanAndItsResultAtTheLargestText` 通过，但人工查看它附带的 `large-light-ready` 截图：`Shortest day · 21 Jun` 左右两侧被裁切，且与时刻文字/图例区域相互遮挡【验】。绘制按文字中心定位；`labelPoint` 只约束中心点距屏幕边缘，不测量文字实际宽高。新增的季节说明比旧日期长，使这条路径更容易溢出。

影响：这次为消除日期误解新增的解释，在辅助字号下不能完整阅读。Canvas 被 `accessibilityHidden(true)` 排除，现有按钮边界断言也不会发现它；UI 通过不等于标签完整。

改法：根据可用区域测量并约束标签，允许换行或给季节说明一个可读的布局位置；避让图例与时间标记。保留辅助字号下完整读取季节含义的路径。

关闭条件：Winter / All-year、中英文、最大辅助字号与横屏截图人工确认季节标签完整；不能只断言按钮可点。截图证据见 [large-light-ready](assets/2026-10-05-light-scan/large-light-ready.png)，内容为模拟器虚构天空。

## 已核验的正确部分

- 抬头过滤：同一 `LiveYaw.maximumPitchDeg` 用于实时估计和 `SceneRecordBuilder` 的可用样本筛选；原始读数仍保留。直接 Swift 探针先加入 **40 条 Δ=100°**，再加入 **100 条俯仰 40°、Δ=280°** 的读数，方向仍为 **100°**，计入数量仍为 **40【验】**。
- 覆盖率：`LightScanModel.step()` 使用 `QualityEvaluator.driftLimitM`，默认 **0.40 m【验，代码门槛】**；提示回到圆圈仍按 `toleranceM`。`SkySweep` 只统计镜头看过的格，没有冒充天空分割或直射时长。该门槛仍是候选，不能把覆盖率提高当作近场重投影已正确。
- 帧卷：`SpoolAdmission.keepRadiusM` 为 **0.50 m【验，代码门槛】**，每帧保留 `lensOffsetM`；保存记录的 `used_for_visibility` 仍为 false，后续分析使用与否尚未实现。
- 季节标签：南北半球的 Shortest / Longest day 对应规则正确，App 单元中的 `SunPathLabelTests` 通过。赤道/高纬与具体年份的真实至日日期精确性不在本次修改验收范围内。

## 旧记录复算

本轮读取本机导出的 `PR-20261005-01…09`，使用 `engine/scripts/scan_postmortem.py` 的新规则复算，结果与 `docs/spike/2026-10-05-scan-coverage.md` 的整数表一致【验】。不把原始记录、坐标、照片或深度复制到仓库。

| 记录 | 新规则 All-year 最终覆盖 | 首次到线 | 新规则 Winter 最终覆盖 | 首次到线 |
|---|---:|---:|---:|---:|
| -01 | 81.0% | 未到 | 100.0% | 20.9 s |
| -02 | 80.9% | 未到 | 85.5% | 23.0 s |
| -03 | 98.8% | 36.6 s | 100.0% | 14.7 s |
| -04 | 92.8% | 61.1 s | 100.0% | 27.8 s |
| -05 | 97.9% | 32.5 s | 100.0% | 24.7 s |
| -06 | 88.3% | 未到 | 97.7% | 12.7 s |
| -07 | 91.8% | 40.6 s | 100.0% | 22.3 s |
| -08 | 36.3% | 未到 | 15.4% | 未到 |
| -09 | 78.8% | 未到 | 82.2% | 未到 |

表内数字全部【验，旧姿态日志的软件重放】；“到线”按候选覆盖目标计。-02 的 Winter 曾到线但最终回落，整场中位数仍会更新，不能称为严格冻结方向。重放不含预览读数，未实现当前 LiveYaw 的容量抽稀；正式记录的姿态和实时处理频率也不同。因此它能复现文档中的统计，不能证明实时与保存完全一致，更不能证明新版动作更容易完成。

## 验证记录与边界

- `PROPERTYREPLAY_BUILD_ROOT=/private/tmp/propertyreplay-light-audit-20261005 ./scripts/test.sh`：NorthResolver **10 项**、SceneRecord **36 项**、SunEngine **26 项**通过，Python 含跨语言对照通过【验】。
- 同一构建目录运行 `./scripts/ios-test.sh unit`：**103 项通过【验】**，包含 CaptureCore **33 项**、PropertyModel **38 项**、SunEngine **26 项**、App **6 项**。日志：`/private/tmp/propertyreplay-light-ios-unit.log`。
- 审计反例：`python3 docs/reviews/2026-10-05-light-scan-probes.py`。从当前仓库提取 `HeadingSample` / `LiveYaw` 定义，与实际 `NorthResolver.swift` 编译；只构建到临时目录。两个反例的输出已核验【验】。
- Python `engine/lightreplay/north.py` 独立复算同一合成输入：正式采集 **100°**、预览与采集合并 **115°**、长序列全量 **100°**，与 Swift 参考一致【验】。
- 相关 UI：`./scripts/ios-test.sh -only-testing:PropertyReplayUITests/LightScanUITests -only-testing:PropertyReplayUITests/ChineseInterfaceUITests -only-testing:PropertyReplayUITests/AdaptiveLayoutUITests`，**12 项全部通过【验】**；包含保存、重试、切换问题、中文、横屏、最大字号。日志 `/private/tmp/propertyreplay-light-ui.log`；结果包 `/private/tmp/propertyreplay-light-audit-20261005/DerivedData/Logs/Test/Test-PropertyReplay-2026.10.05_11-39-06-+1100.xcresult`。
- 人工检查最大字号的 Light ready / scanning / result **3 张截图【验】**：主要操作和指引可读、结果可滚动；弧线标签裁切见 LS03。完整导出附件在 `/private/tmp/propertyreplay-light-audit-screens/`，将 LS03 对应的虚构画面另存到本评审资产目录；没有复制真实采集图像。
- 所有构建都在 iCloud 之外。第一次运行被沙箱的 Swift 缓存与 CoreSimulator 权限阻止，获工具权限后上述测试通过；不是产品失败。
- 没有安装或操作真机，没有验证新版太阳叠加与真实太阳对齐，没有日晷真值，没有对深度重投影做误差测量；没有声称完成 Assist 的模型输出回归。现有扫描仍是 R0，数值指导没有进入 LLM，AI 回归与阶段 C 实验应继续按原计划验收。

## 后续验收

先关闭 LS01 / LS02，再用新版采集：进入预览等待后开扫、从水平抬到夏季路径、竖横持切换，以及长时间扫描。比较屏幕实时 Δ 与保存候选，记录输入起点、时间配对、路径跳变和覆盖回落；用日晷或第二来源验证真实方向。继续保留候选漂移上限，不为了让 All-year 达标放宽。

按 `docs/14-design-principles.md` §8 六问：本次仍服务 Light 采集任务；未知与 R0 边界保留；新增提示更可执行；没有新增动效或权限；季节文字没有把估计写成认证。最大字号检查见上述 UI 验证记录，真实相机叠加的可读性仍待真机。
