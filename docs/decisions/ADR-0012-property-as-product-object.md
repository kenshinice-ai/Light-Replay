# ADR-0012 · 产品对象是 Property；OneTake 是英雄采集；Light 是第一个 Lens

- 状态：Accepted（2026-09-30，Lee 批准）
- 日期：2026-09-30
- 来源：Codex《Property Lens v2.0》§1、§12、§51、§55（存档于 `light_replay_history/`）；`docs/proposals/2026-09-30-property-lens-v2-response.md` 第 0–2 节

## 背景
蓝图把产品定义为一件点级日照测量仪器。它可信但低频：买房几年一次，看房只有几周，Light Passport 之外没有留存机制。Codex v2 指出可积累的资产是买家侧的看房记忆（照片、语音、标签、比较、分歧），切换成本随看过的房子数增长；同时门户（Domain / REA）与太阳 App 已覆盖 listing 侧与地址级日照。本轮核实：地址级日照是 commodity；点级实测仍无人做，且是五级证据里唯一的 measured 来源。

## 决定
1. 产品对象是 Property；一套房是一个持续生长的记录（Inspection、Room、Observation、Question、Priority、Comparison），模型见 `docs/15-product-model.md`。
2. TargetPoint 仍是物理分析单位（ADR-0001 不变）；SceneRecord 作为 LightObservation 的载荷挂进 Property 图，格式不变。
3. OneTake 是 Inspect 模式里的 Measure 动作，是产品的英雄采集；Light 是第一个 Lens，Space 是第二个；Sound lens 不做（ADR-0015）。
4. 北极星指标是 Repeat Inspection Rate；spike 的 false-valid 一票否决不变。
5. 用户的三个任务是 Before（Prep）、During（Inspect）、After（Your inspection、Replay、Compare、Ask）；任何功能不服务这三段就不进首版。

## 备选
- 保持纯测量工具：可信但低频。
- 采纳 Codex 原案（MVP 用地址级 Light Preview 替代实测）：把唯一的 measured 证据换成 commodity。

## 后果
- 蓝图 §1–3、§5–6；01、12、13 重写；新增 14、15。
- Phase 1 两条并行线（测量 spike、产品壳原型），第 3 周末按汇合门决定（`12-roadmap.md`）。
- 产品名见 ADR-0016。
