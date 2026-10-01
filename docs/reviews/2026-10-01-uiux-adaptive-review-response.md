# UI/UX 适配评审 · 回应

日期：2026-10-01。回应 `2026-10-01-uiux-adaptive-review.md`（基线 `cd79f83`）。实现者：Claude。

评审的核心判断我同意：方向不用再改，注意力从"加功能"转到"不同设备上是否真能看、能操作、能纠错"。24 条里没有我认为不成立的；有两处做法与建议不同，一处范围需要 Lee 决定，写在第 3 节。

按组里"修复轮次要小"的约定分轮做：每轮改完、测完、提交、装机，再做下一轮。状态词沿用四档：源码 / 测试（模拟器）/ 真机 / 现场。

## 1. 第一轮（P1 + 一个真 bug）

| 编号 | 做了什么 | 验证 |
|---|---|---|
| U01 Inspect 大字溢出 | 草稿编辑改为系统底部面板（`DraftEditor`）：任意字号可滚动、键盘避让、iPad 上是居中面板；标签用自动换行的流式布局；Save / Discard 固定在面板底部安全区，放不下时上下排。取景器上的地址与房间在放不下时改为上下排（`ViewThatFits`）。底栏三个动作等宽 | UI 测试 `AdaptiveLayoutUITests.testInspectAndItsEditorAtTheLargestText`：最大辅助字号下地址、房间、快门、Light、Save、Discard、Like / Concern / Ask 全部在窗口宽度内，Save / Discard 可点 |
| U02 Light 大字失效 | 顶栏放不下时问题选择独占一行；进度数字在大字下移到圆环旁；结果改为系统面板（`LightResultSheet`），标签与值放不下时上下排，正文可滚动，Done 固定在底部 | `testLightScanAndItsResultAtTheLargestText`：问题按钮宽 > 200 pt、高 < 220 pt（不再是单字列），结果标题、"Sunlight not calculated yet"、Done 在窗口内且 Done 可点 |
| U04 复看 | 新增 `ObservationDetailView`：照片大图，点开全屏可捏合、平移、双击缩放（`UIScrollView`，1:1 跟手、回弹）；原话完整可编辑，第一次修改时把原文存进 `originalText`，可展开查看、可恢复；标签可改；来源用白话写。记录列表与房产详情里的行都能点进来 | 单元 `testCorrectingATranscriptKeepsTheOriginalOnce`；UI `testCorrectedNoteKeepsItsOriginalAndThePhotoOpensLarge` |
| U05 按住说话的语义 | 控件有名称（Dictate note）、状态值、按钮特征与 `.startsMediaSession`（VoiceOver 不会把自己的朗读录进去）；辅助功能与键盘不能"按住"，改为激活一次开始、再激活一次结束（VoiceOver 双击、⌘D）；"准备中"与"正在录"分开显示，准备阶段明说麦克风还没开 | 源码；VoiceOver / Switch Control 需真机开辅助功能验收 |
| U06 诚实状态 | 达标提示改为 "Sun path covered. Tap Save."；准备阶段有图例（实线 = 镜头看过，虚线 = 还没有，形状与颜色都不同）；结果面板把"Scan saved"与"Sunlight not calculated yet"分成两块，说明当前分不清天空与建筑、没有小时数，并写明"分析就绪后这个点可能需要重扫"，不再承诺以后一定能补算；观察文字改为 "camera covered N% … sunlight not calculated" | 单元 `ScanCoachTests`；UI 断言结果面板同时出现两块 |
| U12 房产详情层级 | 首屏：地图、完整地址、预约时间（没有就写 "No inspection time set"，不再拿今天的日期当显示值）、Inspect now / Scan light 两个主按钮、状态；随后是记录与 Light。地址、pin、预约时间、删除收进 Edit 面板，保存时才生效。去掉了写着 "sun engine" 的占位区 | UI `testEditingAPropertyChangesTheInspectionTimeNotTheAddress`、`testPropertyPageAtTheLargestText` |
| U23 切换问题后的完成态 | 确认是 bug。`reachedTarget` 每次按"当前问题 + 当前覆盖率"重算；切换问题时路径重算期间显示 "Working out the sun path…"，不显示达标 | UI `testSwitchingQuestionTakesCoveredAwayAndGivesItBack`：冬季达标 → 切全年不达标且保存会询问 → 切回冬季恢复达标 |
| U22（部分） | Light 保存失败时保留这次扫描，面板给 "Try saving again"（重存同一次扫描）与 "Close without saving"，不再只有"重扫" | UI `testAFailedSaveIsRetriedWithoutRescanning`（注入首次保存失败） |
| U17 / U18 / U19 / U20（随上面一起改到的部分） | 取景器上的地址放进材质底；标签芯片统一为一种样式、最小高度 44 pt、选中态有实心图标与描边；自绘按钮按下即缩放（0.97，快门 0.94），减弱动态效果时只变暗；快门反馈限在取景器内（短暂变暗），不再全屏闪白；拍照、录音开始 / 结束、保存有触感 | 源码 + 上述 UI 测试走过这些控件 |

同时修掉的自己的问题：模拟扫动的启动参数按 `Double` 读取，而命令行传入的是字符串，`-syntheticSweepSpeed 0` 实际没生效（上一轮"覆盖不足"的测试只是点得够快才通过）。已改为 `double(forKey:)`。

## 2. 排在后面

| 编号 | 计划 |
|---|---|
| U03 相机旋转 | 第二轮：`AVCaptureDevice.RotationCoordinator` 分别驱动预览与拍照角度。模拟器没有相机，方向要 Lee 用真机拍"上 / 右"标记验收 |
| U07 iPad 分栏 | 第二轮：tab 用 `.sidebarAdaptable`；Properties 用 `NavigationSplitView` |
| U09 / U10 / U11 | 第二轮：List / Map 共用搜索、筛选与选中；地图卡片整卡可点、带 Inspect 与系统地图导航；Inspect tab 有授权时自动按距离排并可刷新 |
| U14 Compare | 第二轮：行是关注维度、列是房产；格子来自买家自己的标签与扫描，区分"没记录 / 已扫描未计算 / 没有资料来源" |
| U08 Home | 第二轮：Next 卡直接开始看房；Recent 排除 Next |
| U15 / U16 / U21 / U24 | 第三轮：调试项只在 DEBUG；同步状态用 CloudKit 事件的真实结果；地址输入焦点与 iPad 快捷键；消费者界面去掉 R0 / σ 等术语 |
| U13 其余 | 房间 / 日期筛选、Question 独立模型：等 Compare 与详情稳定后再做 |

## 3. 与建议不同的地方，和要 Lee 决定的

- **相机上的悬浮文字在 accessibility2 封顶**（U01 / U02）。第一次实现让 Light 的顶栏、图例、指引完全跟随最大字号，结果它们加起来超过屏幕高度，图例被截成 "Camera has lo…"，方向芯片被压住，取景器基本被挡住。压在实时画面上的文字改为在 accessibility2 封顶（系统相机的取景器文字也不随辅助字号放大）；编辑面板、结果面板、详情页、房产页全部完全跟随。人工看过最大字号截图：问题、图例、指引、Start、覆盖率都完整。
- **底栏文字不随最大字号放大**（U01）。Capture / Note / Light 三个动作是工具栏性质，标题在 xxxLarge 封顶，并提供 Large Content Viewer（长按放大显示），与系统 tab bar 一致。正文、编辑面板、结果面板全部随字号放大。"按住说话"自身是按住手势，和长按放大冲突，所以它的状态写在上方会放大的状态气泡里。
- **绿色达标保留**（U06）。圆环达标仍变绿，但配了明确的 "covered" 文案、图例和结果面板里的"日照尚未计算"。如果实测仍被读成"采光好"，再把达标色改成中性色。
- **要 Lee 决定：iPhone 是否开放横屏阅读**（评审 5.3）。现在 iPhone 全程竖屏，iPad 四向。建议 V1 保持：看房是单手竖持，回家复看在 iPad；开放横屏要逐屏控制方向，并重验相机与 AR 叠加。
- **要 Lee 决定：界面是否出中文**（U24）。现在中文只在语音转写。String Catalog 可以接，但要先定是否做中文界面。

## 4. 没有验收的

- 真机：相机四向、AR 轨迹的物理对齐、VoiceOver / Switch Control 完整走一遍、软键盘遮挡、减弱透明度与提高对比度。
- 320 / 375 pt 窄手机与 iPad 分屏宽度。
