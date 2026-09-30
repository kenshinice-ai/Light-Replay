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
./scripts/test.sh          # SceneRecord Swift 单元测试 + Python 参考实现 + 跨语言一致性
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

## 7. 当前状态（2026-09-30）

- 文档：蓝图 1.1；ADR-0001 至 0016 全部 Accepted；01 / 12 / 13 / 14 / 15 已按 Property Replay 命题重写。
- 代码：`ios/Packages/SceneRecord`（Swift，28 测试）与 `engine/lightreplay/scenerecord.py`（30 测试含一致性）全绿。`ios/PropertyReplay.xcodeproj`（xcodegen 生成，`ios/project.yml` 是源）：App 壳（三个 destination）+ `CaptureCore` 包（`CaptureLog`、`SceneRecordBuilder`、`CaptureRecorder`）+ W1 采集验证器界面；iOS 27 模拟器上构建、运行、6 个测试通过。
- 线 A W1 已开工：验证器目前记录姿态、一条罗盘读数、一次定位，导出 R0 SceneRecord；下一步在真机上跑，然后加天空分割掩膜与走廊覆盖率。
- 未开始：线 B 原型 A；线 C 小 spike。
- 待办（Lee）：PCC entitlement；正式商标意见；域名；仓库是否改名。
