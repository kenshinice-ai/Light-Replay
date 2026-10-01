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

## 2. 第二轮（iPad 与复看）

| 编号 | 做了什么 | 验证 |
|---|---|---|
| U07 iPad 分栏 | tab 用 `.sidebarAdaptable`（iPhone 仍是底部 tab，iPad 是可切侧栏的 tab）；Properties 改为 `NavigationSplitView`：宽窗口左边列表或地图、右边详情，窄窗口自动折成单列并保留选中；Inspect 一律全屏呈现，不挤在详情栏里 | UI `BrowseAndCompareUITests.testAHomeOpensBesideTheListOnAWideWindow`（iPad 模拟器：列表与详情同时可点，换一套房详情就地切换）；iPhone 同一测试走单列 |
| U09 共用状态 | 搜索（地址 / 区名）、状态筛选、选中的房产、地图镜头都放在 `PropertiesView`，List 与 Map 只是同一批房的两种视图；筛选后显示 "Showing N of M"，地图显示 "N of M homes match" | UI `testSearchNarrowsListAndMapTogether` |
| U10 地图卡片 | 手机上选中 pin 出卡片，整卡可点进详情，另有系统地图导航按钮；卡片与计数放在地图的安全区内，不遮 pin 和地图的法律信息；宽窗口不出卡片，详情栏直接显示；没有 pin 的房产数写明并可一键回列表 | 源码 + 截图 |
| U11 Inspect 选房 | 已授权时进入和回到前台都自动刷新位置、最近的排前面，另有手动刷新；未询问时一个按钮说明用途；被拒绝时说明当前顺序并给"打开设置"；定位精度从 100 m 改为 10 m 级（相邻两套房只差几十米）。距离只排序，不替用户选房 | 源码；定位行为需真机 |
| U14 Compare | 行是关注维度、列是房产，房产名固定在顶部；格子来自买家自己的标签与扫描（`CompareSummary`），四种"没有"分开写：Not recorded / Scanned, sunlight not calculated / Not in the app yet，另有 Measured 留给以后；有记录的格子点进去是原始照片与原话；选满三套时写明上限；没选偏好时直达选择页；大字号或窄屏三列时改为逐套竖排 | 单元 `CompareSummaryTests`；UI `testCompareNamesEveryNothingAndOpensWhatWasRecorded` |
| U08 Home | Next inspection 卡下面直接 "Start inspecting"；Recent 不再重复 Next 那一套，按最近记录排序并显示记录数 | 源码 + 截图 |
| U03 相机旋转 | `AVCaptureDevice.RotationCoordinator`：预览角度跟随屏幕上的预览层，拍照角度跟随重力，各用各的；不再写死 90° | 源码。**模拟器没有相机，方向未验证**：要 Lee 用 iPhone 竖持 / 横持、iPad 四向各拍一张带"上"标记的东西，看预览、缩略图、大图是否一致 |

第二轮里自己发现并修掉的两处：

- 搜索时 iOS 用搜索框替换了导航栏，原先放在导航栏里的 List / Map 切换随之消失，带着搜索词切不到地图。切换控件挪到了内容区顶部。
- 给两个主按钮加"不换行"后，系统 `Label` 把标题收掉了，按钮只剩图标（蓝色那个连图标都看不清）。测试按无障碍标签找按钮所以没拦住，是看截图发现的。改用明确的"图标 + 文字"，并在测试里加了"按钮里真的画了文字、宽度明显大于图标"的断言。

验证：iPhone 模拟器 55 个单元 + 13 个 UI，iPad Pro 13 模拟器 13 个 UI，全部通过；iPad 截图人工看过分栏、比较表、笔记详情、大字号各屏。

## 2b. 第三轮（同步、设置、输入）

| 编号 | 做了什么 | 验证 |
|---|---|---|
| U16 同步状态 | `SyncMonitor` 监听 SwiftData 底下 CloudKit 镜像的事件（`NSPersistentCloudKitContainer.eventChangedNotification`），`SyncStatus` 只记真正完成的发送 / 接收与失败。You 页一行说现状：仅本机 / 已开但本机未登录 iCloud / 已开但上次失败（写哪一步、几点、原因，并说明记录在本机安全）/ 最近一次发出与收到的时间（并注明"此后记录的可能还在路上"）/ 已开但打开后还没有任何收发。失败按种类（发送 / 接收 / 启动）分开记：接收恢复不会抹掉仍在失败的发送，迟到的旧事件不会把时间往回拨。新设备资料库为空且同步已开时，空态说明"另一台设备上的房产要等 iCloud 跟上，可能几分钟" | 单元 `SyncStatusTests`（5 个）；UI 断言测试库显示 "Kept on this device only"。真实事件要真机，模拟器没有 iCloud 账号 |
| U15 设置分层 | "Advanced (spike)"、Viewpoint tolerance、Capture validator、Device capabilities 收进只在 DEBUG 构建出现的 Developer 区；去掉 "Partner · Sharing arrives in Phase 3"；"Haptics on the timeline" 改为 "Haptics"，Inspect 与 Light 的触感都听它的（每个触感都有可见的对应反馈）；"Measure height" 改为 "Light scan height" 并说明 1.15 m 是坐姿眼高 | UI `testYouSaysWhereTheRecordsAreAndHidesNothingBehindJargon` |
| U21 输入 | 添加房产的面板一打开光标就在地址栏；地址栏下一行说明查找状态（正在找 / 还没匹配，可以照输入保存 / 连不上 Apple Maps，可以照输入保存），空列表不再等于"没有这个地址"；Cancel / Save 支持 Esc 与回车（添加、编辑两个面板）；⌘N 添加房产、⌘D 口述、⌘↩ 拍照 | UI `testAddingAHomeStartsInTheAddressField`（不点输入框直接打字，文字落在地址栏）、`testChoosingASuggestionKeepsItsPin`、`testAnAddressTheMapCannotFindIsSavedAsTypedAfterAsking`。UI 测试里 Apple Maps 由两套虚构的房子顶替（`AddressCompleter.StandIn`，仅 DEBUG 且带 `-uitest`），不联网、不向外发任何地址。真实 Maps 的补全与软键盘遮挡仍需真机 |
| U24（部分） | 消费者界面里不再出现 spike、Phase 3、R0、SceneRecord；这些词只留在 DEBUG 的调试页 | UI 断言 You 页没有 "Phase 3"、"spike" |

第三轮里自己发现并修掉的（评审没有提到；多数是看截图或给新行为补测试时撞出来的）：

- **地址补全退回全球。** 截图里 "12 Exa" 的补全全是日本地址。实验表明 `MKLocalSearchCompleter` 的区域（即使 `regionPriority = .required`）在区域内没有匹配时会退回全球结果。现在三道保护：区域设为全澳洲；建议按文字过滤（要出现 Australia 或州 / 领地缩写，且不是美国 / 加拿大的 WA、SA、NT）；解析出的坐标不在澳洲范围就当作没找到，宁可没有 pin 也不把 pin 放到国外。单元 `AddressScopeTests`。依据：V1 的房产都在澳洲（`01` §1）。
- **选中一条建议后，选择立刻被清掉。** 地址栏上有一个"文字一变就清掉已选结果"的 `onChange`，而选中建议本身就会改写地址栏，于是刚选的结果被自己清掉：建议列表还在、没有"已定位"的确认，保存时再查一次。用真实 Maps 在模拟器上复现后，改为把"Maps 对哪一段文字给了什么答案"存成一个值（`PinAnswer`），是否已选、是否查找失败都从它与当前文字推出来，不再有需要同步的两份状态。选中后地址栏下写 "Pin placed in <区名>"，键盘收起。
- **建议行只有文字能点。** 给上一条写测试时点不动：`.buttonStyle(.plain)` 的行命中区只有文字那么宽，短地址右边大半行点了没反应（长地址碰巧能点，所以之前没发现）。现在整行可点；You › Priorities 的行同样处理（名称与对勾之间的空白原来也点不动）。
- **"地图找不到这个地址"的说明被键盘挡住。** 它原来在表单底部，键盘升起时只看到按钮变成 "Save without pin"，看不到原因。挪到地址栏正下方，措辞与编辑面板统一；测试断言它可点到（在屏幕上），不只是存在。
- **保存的地址就是地址栏里的字。** 没选建议直接保存时，原来会把 Maps 返回的规范地址替换掉用户输入的文字（用户没看过它）。现在与编辑面板一致：地址栏显示什么就存什么，Maps 只提供 pin 和区名。
- **橙色 / 红色小字读不清。** 量了一下：系统标准橙在白底约 2.2:1，标准红约 3.6:1，脚注字号要 4.5:1。提示文字改用系统自己的高对比变体（浅色下橙 197,83,0 = 4.55:1，红 233,21,45 = 4.56:1；深色下用标准色，4.96:1 到 9.41:1），存储故障横幅的底色同理（白字 ≥ 4.5:1）。单元 `TextColorTests` 在浅 / 深两种外观、页面与列表行两种底上各量一遍【验，iOS 27 模拟器】。圆环、圆点、pin 这些图形仍用标准色。相机画面上的材质底不是纯白，那里的对比度仍要真机看。
- **You 页 "The switch takes effect the next time you open the app."** 原来按"开关与当前模式不一致"判断，于是同步启动失败时也会出现，把"没启动成功"说成了"等下次打开"。现在只在本次会话里动过开关时出现；启动失败单独一行，且只在这次启动确实尝试过 iCloud 时出现。
- **存储故障横幅指向 "You › About"**，而说明早已搬到 Privacy & data。已改。
- **确认框锚定与删除确认**（来自同组 PWE Receipts 当天记进共享记忆的教训）：iOS 26 起 `confirmationDialog` 是指向所附视图的气泡，挂在整屏上会指到屏幕中间。四个确认框（删除观察、删除房产、丢弃扫描、删除全部）都改为挂在触发它的按钮上，标题写明对象（"Remove 3/21 Placeholder Road and everything recorded for it?"）。列表左滑删除原来是直接删：删一套房会连带删掉全部照片与记录并传到 iCloud，没有撤销，现在房产行和观察行的左滑 / 长按删除都先问，问题挂在那一行上（`DeleteWithConfirmation`）。UI `testSwipeDeleteAsksAndNamesWhatGoes`、`testRemovingAHomeAsksByName`。

验证：iPhone 模拟器全套（单元 + UI）与 iPad 模拟器 UI 全套通过，数字见提交说明。

## 2c. 第三轮提交之后补的（10-02）

第三轮提交前，我只看了那一轮改到的屏（添加面板、You 页）的截图，没有把四个列表屏在各档字号下过一遍。补看时发现四处，都是 iPhone 上一眼能看到的：

| 现象 | 原因 | 改法 |
|---|---|---|
| Properties 的大标题在**所有字号**下都是一团模糊 | 第二轮把 List / Map 切换挪到内容区顶部（`safeAreaInset`），它的滚动边缘模糊盖在了大标题上。当时只看了搜索态和 iPad 的截图，这两种情况下都没有大标题 | 标题改为 inline（地图视图本来就是） |
| 搜索框在 XXXL 及以上字号是一个没有图标、没有提示词的空胶囊 | 随滚动收起的搜索栏在这些字号下初始停在半收起状态 | 搜索栏始终显示 |
| 列表行在 XXXL 把副标题截成 "Bruns… · Sat, 3…"；iPad 侧栏最大字号下地址被拆成四行、"SAMPLE" 被断成 "SAM-PLE"、状态图标压在地址上 | 行布局只有一种，靠单行截断硬塞；图标列宽写死 24 pt | Home、Properties、Inspect、Compare 共用的这一行改为：放得下就一行；放不下就地址换行、细节一行一条、标记放到文字下面，不截断。标记本身不换行，图标列宽随字号缩放 |
| iPhone 上 Home 的标题在最大字号下被截成 "Property Re…" | 大标题不换行 | 窄窗口在辅助字号下用 inline；iPad 宽度够，保持大标题（顶部是 tab 栏时 inline 标题根本不显示） |

验证：UI `testTabsAtTheLargestText`（Home 标题完整、搜索框存在、Inspect 与 Compare 的文字在窗口内）与 `testPropertyPageAtTheLargestText`（标记是单行）；人工看了 iPhone 在默认 / XXXL / AX1 / AX5 四档和 iPad 最大字号的截图。Compare 选择行在最大字号下会把 "Placeholder"、"Richmond" 用连字符断行，这是系统在一行放不下一个词时的行为，没有截断，保留。

## 2d. 仍然排在后面

| 编号 | 说明 |
|---|---|
| U13 其余 | 记录页按房间 / 日期筛选、Question 独立模型 |
| U24 其余 | String Catalog 与中文界面（要 Lee 先定是否做）；证据等级的消费者措辞（ADR-0013 的六个标签是已接受的决定，要改先改 ADR） |
| U17 / U18 其余 | 真实相机画面下的对比度（白墙、逆光窗）、用 Accessibility Inspector 量真实命中区：要真机 |
| Compare 的三个维度没有资料来源 | School、Commute、Price comfort 目前没有对应的记录类别，格子写 "Not in the app yet"。要不要给它们加记录入口是产品决定 |
| 输入地址后直接保存 | Maps 把这段文字匹配到了哪里，保存前没有给用户看（保存后在行里的区名和详情页的小地图上才看得到）。建议下一轮：查到后先显示匹配到的地址与区名，由用户确认再保存 |

## 3. 与建议不同的地方，和要 Lee 决定的

- **相机上的悬浮文字在 accessibility2 封顶**（U01 / U02）。第一次实现让 Light 的顶栏、图例、指引完全跟随最大字号，结果它们加起来超过屏幕高度，图例被截成 "Camera has lo…"，方向芯片被压住，取景器基本被挡住。压在实时画面上的文字改为在 accessibility2 封顶（系统相机的取景器文字也不随辅助字号放大）；编辑面板、结果面板、详情页、房产页全部完全跟随。人工看过最大字号截图：问题、图例、指引、Start、覆盖率都完整。
- **底栏文字不随最大字号放大**（U01）。Capture / Note / Light 三个动作是工具栏性质，标题在 xxxLarge 封顶，并提供 Large Content Viewer（长按放大显示），与系统 tab bar 一致。正文、编辑面板、结果面板全部随字号放大。"按住说话"自身是按住手势，和长按放大冲突，所以它的状态写在上方会放大的状态气泡里。
- **绿色达标保留**（U06）。圆环达标仍变绿，但配了明确的 "covered" 文案、图例和结果面板里的"日照尚未计算"。如果实测仍被读成"采光好"，再把达标色改成中性色。
- **要 Lee 决定：iPhone 是否开放横屏阅读**（评审 5.3）。现在 iPhone 全程竖屏，iPad 四向。建议 V1 保持：看房是单手竖持，回家复看在 iPad；开放横屏要逐屏控制方向，并重验相机与 AR 叠加。
- **要 Lee 决定：界面是否出中文**（U24）。现在中文只在语音转写。String Catalog 可以接，但要先定是否做中文界面。

## 4. 没有验收的

- 真机：相机四向、AR 轨迹的物理对齐、VoiceOver / Switch Control 完整走一遍、软键盘遮挡、减弱透明度与提高对比度。
- 320 / 375 pt 窄手机与 iPad 分屏宽度。
