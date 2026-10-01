# Apple 设计评审 · 当前界面状态

日期：2026-09-30 深夜。评审者：Claude，方法：`apple-design`（响应、直接操控、可打断、空间一致、材质、反馈、八原则）。
看过的界面：iPhone 17 Pro 模拟器（iOS 27，`-uitest` 虚构样例）逐屏截图；iPad Pro 13 模拟器首页；真机 iPhone / iPad 的数据库比对。

## 结论

**Lee 找不到扫描界面，是因为它还不存在。** Inspect 屏右下角的 "Measure" 通向 "Capture validator"：一张调试用的统计列表（Tracking、Anchor、Pose samples、Lens drift…）和一个 "Start OneTake" 按钮，没有相机画面、没有太阳路径、没有指引。它是给工程验证用的，不是给买家用的。

其余界面的骨架是对的（五个 tab、按时间线排序、Inspect 三动作、卡片式打标签），问题集中在四处：光线入口太深太弱、开发者文字漏到用户界面、iPad 没有大屏布局、按压与触感反馈缺失。

## 发现（按优先级）

| # | 界面 | 问题 | 原则 | 建议 |
|---|---|---|---|---|
| 1 | Measure → Capture validator | 没有扫描界面：只有统计列表，用户不知道该对着哪里、转多少、何时算完 | Purpose、Wayfinding | 做真正的 Light scan 屏（见下节） |
| 2 | Inspect 底栏 | "Measure" 标签不说测什么；与 "Hold to note" 同权重、同位置层级，但它是产品的英雄动作 | Simplicity（最重要的最显眼）、Direct labels | 改名 "Light"，太阳图标；房产详情页也给一个直接入口 |
| 3 | 光线入口深度 | Inspect tab → 选房产 → Inspect 屏 → Measure，四层；房产详情的 Replay 区只有一句被动文字 "appears after the first Measure" | Wayfinding、Agency | 详情页 Replay 区改成按钮 "Measure light here"，直达扫描 |
| 4 | 开发者文字漏出 | "Arrives with the sun engine"、"capture-only (R0) SceneRecord. No sky, no north, no sun yet"、You 的 "Advanced (spike)"、"Capture validator (unbound, debug)"、"Viewpoint tolerance" | Simplicity、Craft | 调试项只在 DEBUG 构建出现；占位文案改成买家语言，或在功能到来前不显示 |
| 5 | iPad | 所有列表横跨 1000+ pt，右侧空白；没有分栏 | Flexibility | TabView 用 `.sidebarAdaptable`；Properties 用 `NavigationSplitView`（列表 + 详情并排）；正文限制在可读宽度 |
| 6 | Inspect 取景器 | 地址与计数直接压在实时画面上，没有材质底，亮场景会看不清；底栏是不透明的 `.bar` 条 | Materials | 顶部信息放进 `.regularMaterial` 胶囊；底栏用半透明材质，画面延伸到底 |
| 7 | 按压与触感 | 快门、Hold to note、标签按钮都用 `.plain`，按下没有状态变化；拍照、开始 / 结束录音、保存都没有触感 | Response、Multimodal | 按下即缩放 0.94（弹簧 response 0.3、damping 1）；`.sensoryFeedback` 用在拍照（impact）、录音开始 / 结束（start / stop）、保存（success）、失败（error） |
| 8 | 标签卡片 | 标题 "Photo · Living" 与下方 Living 芯片重复；房间 / 类别用着色胶囊，Like / Concern / Ask 用描边药丸，两种视觉语言表达同一类选择 | Consistency、Craft | 标题只写内容（照片无文字时不要标题）；三类选择统一成一种芯片样式，选中态实心 |
| 9 | 动效 | 卡片进场用 `.easeOut(0.2)` 固定时长；闪白 80 ms 覆盖全屏 | Behavior over animation、Reduced motion | 卡片用弹簧（response 0.3、damping 1），同路进出；快门反馈改成取景器短暂变暗，尊重减弱动态效果 |
| 10 | 首页 | "12 Example Street" 同时出现在 Next inspection 与 Recent；每行都有 SAMPLE 徽章（仅样例数据） | Simplicity | Recent 排除已在 Next 里的那套 |
| 11 | Inspect tab | 第一行是大按钮 "Sort by my location"；已授权定位时这一步可以省掉 | Purpose | 有定位权限就自动按距离排序，最近一套放顶部并标 "You're here?" |

## Light scan 屏应该长什么样

一次扫描约 30 秒，全屏相机，只有一个主按钮和一行提示：

1. **站定**：画面中央一个目标圈；提示 "Stand where you'd sit. Hold the phone at eye height." 锁定视点时一次轻触感，圈变实心。
2. **扫天**：把所选季节的**太阳路径画在实时画面里**（冬至、夏至两条弧，当前时刻一个点）。镜头扫过的路径段被点亮，底部环形进度显示走廊覆盖率。每次只出一条提示，优先级：慢一点 → 回到圆圈 → 擦镜头 → 朝缺口转（箭头）→ 看到太阳或光斑点一下。
3. **完成**：覆盖率够了一次成功触感，自动停止；结果卡诚实说明当前只保存了采集，日照时段在天空分析上线后出现。

太阳路径用刚完成的 SunEngine 实时算，方向先用罗盘估计（标 "approximate"），日后由光斑 / 墙面校准收紧。路径叠加本身就是扫描指引，也是这个产品第一眼的价值：买家当场看到"冬天的太阳会从这扇窗的哪里经过"。

## 已验证的

- iCloud 同步：真机 iPhone 与 iPad 的数据库比对一致（房产 1、看房 5、观察 13、偏好 1；照片 4 张与测量记录 4 份的字节均已同步；旧文件路径已全部迁移）。
- Inspect 的保存 / 丢弃 / Done 路径由 UI 测试覆盖。

## 建议顺序

1. Light scan 屏（上节）+ 入口改名与详情页直达（发现 1–3）。
2. 开发者文字收进 DEBUG（发现 4），iPad 分栏（发现 5）。
3. 取景器材质、按压与触感、卡片统一（发现 6–9）。

## 跟进（2026-10-01）

- 发现 1–3 已处理：Light scan 屏（`04` §11），入口改名 Light（ADR-0015 修订），房产详情加 "Scan the light here" 直达。
- 发现 4–11 未动。

