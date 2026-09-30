# 对 Codex《阶段进展与地基审计》的核实与处理

- 日期：2026-09-30 · 对象：`2026-09-30-progress-foundation-audit.md`（Codex）及其探针 `2026-09-30-schema-probes.py`、`2026-09-30-builder-probe.swift`
- 核实：Claude 的子代理逐条对照源码，重跑探针（6/6 语义探针在 Swift 与 Python 都被接受，确认缺口；builder 探针复现编号碰撞、锚点矛盾、负真北变合法）
- 状态：第一批修复已落地（分支 `feat/inspect-screen`，PR #2）；未修项列在末尾

## 结论

15 条中 13 条属实；F11（重标证据等级）是设计判断，按蓝图 §5 冻结不改，但 01 §3 的例句越界确认；F05 方向对，修法按 docs/02 §1 分层（校验器只加自洽规则，阈值判定放到 QualityEvaluator）。评审没有错报。

## 分诊与处理

| # | 结论 | 处理 |
|---|---|---|
| F01 场景编号碰撞、覆盖 | 属实 | `SceneRecordBuilder.nextSceneID(in:)` 从磁盘取号；目录 `withIntermediateDirectories: false` + `.withoutOverwriting`；场景统一放 `Documents/scenes` |
| F02 删除范围 | 属实 | `MediaStore.deleteAll()` 抛错（忽略"不存在"）；新增 `SceneStore`；`PropertyStore.delete(property/observation)` 连文件；`deleteEverything` 先文件后行；You 的删除出错弹 alert |
| F03 方向残留 / 负真北 / 轴 | 属实 | 每会话清空；记录全部读数；`HeadingSample.isValid` 含 `trueHeading ≥ 0`；`yaw_deg` = 罗盘读数 − 同步帧的相机 AR 方位角（`FrameSample.cameraAzimuthAR`），raw 记 `frame_id`、`camera_az_ar_deg`、`pose_gap_s` 与假设；无 1 s 内同步帧则 invalid。**轴映射待日晷验证** |
| F04 锚点基准 | 属实 | 锚点 = 首个 normal 帧；锁定前 `lens_offset_m` 为 null；`viewpoint_lock.anchor_world` 用真实锚点；从未锁定 → `handling: rejected` + flag `anchor_never_locked` + level 灯 blocked；hero 帧 = 锚点帧 |
| F05 门槛未封闭 | 属实（分层） | 第一层已做：`gates` 必含 `lens`，`frames[].t ≤ ended − started`（Swift + Python + fixture + 一致性用例）。第二层 `QualityEvaluator` 待做 |
| F06 生命周期 | 属实 | 验证器 `onDisappear` 停止并提示"未导出"；`ARSessionObserver` 的失败 / 中断写入 `failureReason` → flags 与 `blocked_reason` |
| F07 房产未进 Measure | 属实 | `CaptureValidatorView(property:roomLabel:)`；容差与高度来自偏好；导出后落一条 `InspectionObservation(kind: .light)`，等级 Unknown；You › Advanced 入口标 unbound |
| F08 地理编码提示被关闭 | 属实 | 改用 MapKit 补全 + `MKLocalSearch`（去掉弃用的 `CLGeocoder`）；失败时表单不关闭，按钮变 "Save without pin"；详情页可改地址、"Place pin again" |
| F09 静默内存库 | 属实 | `StoreHealth.isPersistent`；RootView 红色横幅；Add / Inspect 保存禁用 |
| F10 资产 / 时间基准 | 属实 | `t` 来自 ARFrame 时间戳（单调）；每帧记录，不再 10 Hz 抽样；`firstFrameAt` 提供映射 |
| F11 证据措辞 | 不同意重标等级 | 01 §3 例句待改为条件句（文档，下一批） |
| F12 文档 / 测试 | 属实 | 04 "五盏灯"；03 补 `lens` 与 `t` 上界；04 §4 阈值改名 `drift_limit_m`；HANDOFF §3 补 App 测试命令、§7 不再手抄计数 |
| D01 push-to-talk 取消 | 属实 | generation 计数：每个 await 后检查是否仍被需要；准备中松手 → 自行清理；`onDisappear` 停止 |
| D02 light+sensor=measured | 属实 | `level(for:.light,_)` 恒为 Unknown；新增 `lightLevel(qualityLevel:falseValidGuard:bandState:)` 规则 + 测试 |
| D03 失败仍清草稿 | 属实 | 保存用 do / catch：失败删已写文件、`rollback`、草稿保留并提示；`finish()` 同样 |
| 补：真机闪退 ×2 | 本轮真机发现 | `ARGeoTrackingConfiguration.checkAvailability` 回调与 `installTap` 闭包补 `@Sendable`（主线程隔离断言在后台队列触发） |
| 补：ADR-0010 回归 | 子代理补 | `NoteStructurer.summaryWithoutNewNumbers`：摘要里出现转写没有的数字即作废摘要 |

## 未修（记入 HANDOFF）

`installTap` 弃用警告；`QualityEvaluator`（F05 第二层，含 ADR-0009 规则 5）；01 §3 例句；Room 仍是字符串标签；`Question` 未拆模型。
