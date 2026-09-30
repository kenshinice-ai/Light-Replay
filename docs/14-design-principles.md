# 14 · 设计原则：克制、精确、用手艺建立信任

版本 0.1 · 2026-09-30 · 来源：Codex v2 §3–11、§30–35；Lee 的 `apple-design`（工艺）与 `jobs-simple-design`（方法）；WWDC26 设计原则【引 Codex】

## 1. 方法：先减法，再层级，再视觉

- 每个屏幕先回答：用户在这一刻的任务是什么（Before / During / After）。不服务任务的元素不出现。
- 每一个功能都值得用户付出它所需要的时间、注意力和信任；否则删。
- 五个 destination，按买家的时间线排（Lee 2026-09-30 定）：**Home**（Before：下一次 inspection、最近的房、添加）、**Properties**（shortlist 与历史；同一批房的 List / Map 两种视图）、**Inspect**（During：居中，选你在哪套房、开始；北极星就是这一下）、**Compare**（After：按 You 里设的优先级）、**You**（优先级、个人信息、偏好、隐私与数据、高级设置、关于）。不做 AI Tab、Sun Tab、Scan Tab、Finance Tab。
- 地图只放用户自己加的房产（按状态着色的 pin）与当前位置；不放 listing、不放门户数据、不放任何评分。
- Property 详情是一条滚动层级：Prep → Your inspection → Replay → Questions。不做五个 tab。

## 2. Apple 八条原则在本产品的落点

| 原则 | 我们的做法 |
|---|---|
| Purpose | 三个任务之外的功能不进首版 |
| Agency | 不做总分、不做"AI says buy"；Compare 只比用户设的优先级 |
| Responsibility | 每个结论带等级与来源；"Why am I seeing this?" 一点即见（ADR-0013） |
| Familiarity | SwiftUI 标准导航、Share Sheet、Photos 式画廊、系统 sheet、SF Symbols、Dynamic Type、系统 haptics；品牌在内容层，不在 chrome |
| Flexibility | LiDAR 是增强不是门槛；Apple Intelligence 不可用时按 ADR-0010 降级 |
| Simplicity | Inspect 只有三个动作；复杂度放后台 |
| Craft | 性能就是可信度：罗盘漂移、太阳线跳动、相机卡顿都会让用户怀疑整个结果 |
| Delight | 要的情绪是 Confidence，不是 excitement："对，就是这个，我没有忘记" |

## 3. 视觉语言

- 品牌来自 Light + Space + Time：大面积真实房屋照片、白 / graphite / 暖中性色、时间轴、细的空间网格、房间轮廓、柔和的阴影移动、SF 字体。
- Liquid Glass 只用于控件：浮动时间轴、工具栏、底部控制簇、播放控制、筛选。内容层安静；不在照片上铺透明面板；不为"Apple 感"牺牲可读性。
- 唯一的标志性动作：拖动时间轴，光线慢慢移动。calm, physical, believable。

## 4. 动效与触感

- 默认答案是"不需要动"。动的只有：时间轴拖动时的太阳方向与时段游标（1:1 跟手，可中断，从当前值继续，无过冲）；sheet 的系统转场。
- Haptics 只在物理事件上：日出、正午、日落、目标点进入 / 离开直射。用户不看数字也能感到变化。
- 尊重 reduced motion：时间轴仍可拖，光线变化改为即时。
- 数值取自 `apple-design` 的表格，不凭感觉。

## 5. 文字

- 个人化语言："你标记了卧室 2 为 concern"，不是"卧室 2：3/5"。
- 给区间与整分钟；标注日期；不用"精确"、"认证"、"合格"。
- 中英双语同一事实、同一数字。

## 6. 权限与隐私（HIG）

- 权限在用户理解价值的时刻请求：相机在 Start inspection；麦克风在第一次 Note；定位在建档或 Measure；相册在导入。首屏绝不一次索取四个权限。
- 本地优先；需要云端时明确告诉用户什么离开设备、为什么、产生什么价值。

## 7. 首屏与 demo

- Onboarding 只有一句："See beyond the inspection. Remember what mattered. Replay what you couldn't see." 一个按钮：Add a property；第二入口：Share from Domain or realestate.com.au。
- 最值得展示的 8 秒：Share → Property → 到现场拍客厅 → 拖 winter → afternoon → 光线变化 → "Bedroom 2 — you marked this as a concern." → Compare 两套。

## 8. 评审清单（每个 PR）

1. 这个屏幕服务哪个任务？多出来的元素是什么？
2. 每个结论有没有等级与来源？Unknown 有没有显示？
3. 有没有任何数字来自模型而不是工具？
4. 动效是否可中断、是否有过冲、reduced motion 下是否仍可用？
5. 文案是否个人化、是否给区间、是否避免"精确 / 认证"？
6. 权限是否按需？
