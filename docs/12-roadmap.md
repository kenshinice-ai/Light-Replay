# 12 · 路线图：Phase 0 → 4

版本 0.2 · 2026-09-30（0.1 于 2026-09-10）· 来源：`proposals/2026-09-30-property-lens-v2-response.md` 第 5 节；Lee 2026-09-30 批准

## 总览

| 阶段 | 周 | 目标 | 进入条件 |
|---|---|---|---|
| **Phase 0 · 对齐** | 本周 | 决定、ADR、蓝图与规范、名字、代码并入主线 | 完成 |
| **Phase 1 · 并行验证** | 1–3 | 线 A 测量 spike；线 B 原型 A；线 C 三个小 spike | Phase 0 |
| **Phase 2 · MVP v0** | 4–9 | Property + Inspect + Replay·Light + Compare，TestFlight 20–30 人 | 汇合门 |
| **Phase 3 · MVP v1** | 10–16 | R2、户型 L1、Delta、Ask-next、couple、Light Passport 试点、价格实验 | Repeat rate 达线 |
| **Phase 4 · Intelligence** | 17+ | Domain API（如有谈判）、planning、Privacy lens、WeatherKit、App Intents、finance bridge 设计 | 按信号 |

## Phase 0 · 对齐（2026-09-30 起）

- [x] D1–D5 决定；名字 Property Replay（ADR-0016）
- [x] ADR-0012 至 0016；蓝图 1.1；01、03、10、11、13 修订；14、15、HANDOFF 新建
- [x] SceneRecord Swift 包与 Python 参考实现并入主线（iOS 27；时区别名修正；`scripts/test.sh`）
- [x] Xcode 工程（xcodegen）：App target `PropertyReplay`，bundle `com.pwegroup.propertyreplay`，iOS 27；CaptureCore 包（CaptureLog、SceneRecordBuilder、CaptureRecorder）与 W1 采集验证器界面；模拟器上构建、运行、测试通过（2026-09-30）
- [x] App 壳：五个 tab、PropertyModel（SwiftData）、Properties List / Map、添加房产、Inspect 选房、Compare 骨架、You（2026-09-30）
- [ ] PCC entitlement 申请状态（Lee）
- [ ] 正式商标意见（上架前）

## Phase 1 · 并行验证（第 1–3 周）

**线 A · 测量 spike**：`07-spike-plan.md` 原样（W1 Point Core、W2 Hard Cases、W3 Holdout）；通过线不变。

**线 B · 原型 A**：SwiftUI 假数据的 5 屏：Add → Prep → Inspect（Capture / Note / Measure，Measure 打开 OneTake 的模拟）→ Your inspection → Compare。10 位正在看房的人做任务式测试；PP 与中介渠道招募。

| 指标 | 候选线 |
|---|---|
| Time to First Capture | 中位数 < 10 s |
| 每套房额外操作 | < 2 min（原型；MVP 含 OneTake 放宽到 3 min） |
| 证据理解 | ≥ 8/10 能指出测的 / listing 说的 / 推断的 |
| 再用意愿 | ≥ 6/10 主动问下一套能不能用 |
| 只要太阳 | 若 ≥ 7/10 只关心 Light：收窄为专业日照产品 + Light Passport |

**线 C · 小 spike（各 3–5 天）**

| 小 spike | 做什么 | 候选线 |
|---|---|---|
| C1 URL → Property | 50 条真实 REA / Domain listing URL，只用 URL 解析地址 | ≥ 90% 得到可校验地址【估】 |
| C2 截图 / PDF → 地址与房间 | Vision OCR + FM 抽取；20 张 listing 截图 | 地址 ≥ 90%，房间列表 ≥ 80%【估】 |
| C3 语音 → InspectionObservation | `SpeechTranscriber` zh-CN 与 en-AU 各 30 句 → FM 结构化；人工评分 | 类别正确 ≥ 85%；零条被改写出不存在的事实【估】 |

**汇合门（第 3 周末）**

| 线 A | 线 B | 决定 |
|---|---|---|
| GO | 通过 | 进 Phase 2，OneTake 为英雄采集 |
| GO | 不通过 | 产品壳重做原型；OneTake 先以 PP 专业采集形式存在 |
| CONDITIONAL | 通过 | 进 Phase 2；OneTake 限定户外 + 晴天室内，其余点 R0 |
| NARROW | 通过 | 进 Phase 2 但 Light 只做 R0；测量链继续修，作 Phase 3 升级 |
| NARROW | 不通过 | 停，重新评估 |

## Phase 2 · MVP v0（第 4–9 周）

范围见蓝图 §3。交付 TestFlight 给 20–30 位看房者。北极星 Repeat Inspection Rate；支持指标 TTFC、Inspection Completion、Properties per Buyer、Compare Rate、Replay Usage、OneTake 成功率、false-valid（必须为 0）。Codex Signal 1–4 任一触发即停下修，不加功能。

## Phase 3 · MVP v1（第 10–16 周）

RoomPlan 窗几何 → R2 潜力光斑；户型 L1 锚点配准；照片到房间；Listing-to-Inspection Delta；Ask-next 自动生成；couple / family 模式；Light Passport 分发试点（PP 拍摄产出、买家复扫率为判据）；价格实验（Lee 定结构）。

## Phase 4 · Property Intelligence（第 17 周起）

Domain API（仅当有商务谈判且条款允许）；planning context（只链接官方来源，保留 Unknown）；Privacy lens；WeatherKit 舒适度；App Intents / Visual Intelligence；Finance bridge 的独立 workflow 设计与合规审查（`11` §4）。直到有信号仍不做：Sound lens、地址级评分、黑盒总分。

## Kill criteria（合并）

| 信号 | 阈值 | 动作 |
|---|---|---|
| holdout 出现 false-valid | 1 次 | 停消费者产品，修测量链 |
| 第二套房 reopen 率低 | Phase 2 预注册线未达 | 重做 Inspect 体验或收窄 |
| 用户只用 Light | ≥ 70% 活跃用户只碰 Replay | 收窄为专业日照产品 + Light Passport |
| 每套额外操作 > 3 min | 中位数 | 削功能 |
| 用户不信 AI 观察 | 编辑率 > 50% 或访谈反馈 | 强化来源标签，减少 AI |
| 喜欢但不付费 | Phase 3 价格实验 | 检验分发 / B2B 经济，不加功能 |

## 现在预留，现在不做

预留：稳定 ID、App Entity 化字段、楼层、坐标变换版本、原片与衍生分离、跨 App 授权字段。
不做：全国地址预计算、强制账户、复杂生成天气、规划 / 法律评分、第三个综合 App。

## 下一步

Phase 0 剩余：Xcode 工程。然后 Phase 1 W1：采集验证器（`07-spike-plan.md`）与原型 A 同时开工。
