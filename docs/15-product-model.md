# 15 · 产品模型：Property 图与 SceneRecord 的关系

版本 0.1 · 2026-09-30 · 对应 ADR-0012、0013、0015；Swift 包 `PropertyModel`（待建）以此为准

## 1. 图

```
Property
├─ id, address (G-NAF id?), coordinates?, source (user_shared | manual), createdAt
├─ preload: listingText?, listingPhotos[], floorplanImage?, sharedURL?, inspectionTimes[]
├─ Inspection[]
│  ├─ id, startedAt, endedAt, weatherNote?
│  ├─ Room[]            id, label, floorplanPosition? (L0 手工), confirmedBy
│  └─ Observation[]     见第 2 节
├─ Question[]           id, text, whoToAsk (agent | conveyancer | inspector | other), originObservationId?, resolved
├─ Priority[]           personId, dimension, weight
└─ Comparison[]         id, propertyIds[], cells[{dimension, propertyId, value, level, source}]
```

## 1a. 已实现（`ios/Packages/PropertyModel`，SwiftData）

| 模型 | 字段 | 说明 |
|---|---|---|
| `Property` | `uuid`、`address`、`suburb?`、`latitude?`、`longitude?`、`source`（manual / shared / sample）、`status`（toInspect / inspected / shortlisted / dropped）、`createdAt`、`inspectionAt?`、`notes?` | 坐标来自 Apple 地理编码，只用于 pin；`sample` 只在 DEBUG 出现且标注虚构 |
| `UserPreferences` | `displayName`、`priorityRaws[]`（≤ 5）、`targetHeightM`、`hapticsEnabled`、`viewpointToleranceM`、`createdAt` | 单行；`PropertyStore.preferences(in:)` 首次创建 |
| `PropertyStore` | `container(inMemory:)`、`preferences(in:)`、`deleteEverything(in:)` | 删除是物理删除 |

| `Inspection` | `uuid`、`startedAt`、`endedAt?`、`property`、`observations[]`（级联删除） | 一套房同时只有一个未结束的 inspection；`PropertyStore.openInspection(for:in:)` 找或建 |
| `InspectionObservation` | 第 2 节的字段；Swift 类型名避开 `Observation` 模块 | `level` 由 `InspectionObservation.level(for:source:)` 规则赋予；`modelSuggested` 标记模型建议未确认；`mediaPath` 指向 `MediaStore` |
| `MediaStore` | `saveJPEG`、`delete`、`deleteAll` | 沙盒 Documents/observations，相对路径 |

Room 暂以 `roomLabel` 字符串表示（L0）；Question 暂以 `sentiment == .ask` 表示；Comparison 随 Phase 2 加入。`Priority` 暂以 `UserPreferences.priorityRaws` 表示（单人）；多人（couple 模式）时拆成独立模型。

## 2. Observation

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 稳定 ID（App Entity 化预留） |
| `inspectionId`, `roomId?` | | |
| `kind` | enum | `photo` / `voice` / `light` / `tag` |
| `category` | enum | naturalLight / privacy / noise / space / condition / layout / outdoor / other |
| `sentiment` | enum | like / concern / ask / neutral |
| `text` | String? | 语音转写（可编辑）或用户输入 |
| `media[]` | refs | 照片路径；不存音频 |
| `capturedAt`, `headingCandidate?`, `devicePose?`, `locationAccuracy?` | | Capture 的自动元数据 |
| `level` | enum | verified / observedMeasured / observedNoted / strongIndication / indicative / unknown（ADR-0013） |
| `source` | enum | listing / user_photo / user_voice / sensor / open_data / model |
| `followUp` | Bool | 为真则生成 Question |
| `sceneId` | String? | `kind == light` 时指向 SceneRecord 的 `scene_id` |
| `modelExtraction?` | struct | FM 结构化的原始输出与版本，供回归 |

规则：`level` 只由规则赋予（ADR-0013）；`kind == light` 的 `level` 由 SceneRecord 的 `quality` 与时段映射得出，展示层计算，不写回 SceneRecord。

## 3. 与 SceneRecord 的关系

- SceneRecord 保持 JSON 文件（`03-scene-record.md`），可回放、可交叉核对；`scene.json` 与资产在 `<scene_id>/` 目录。
- Property 图只存 `sceneId` 引用；删除 Property 时一并删除其 SceneRecord 目录。
- 一个 TargetPoint 一份 SceneRecord；同一房间多个点是多条 LightObservation。

## 4. 存储

- SwiftData，本地优先；不强制账户。
- 原片、深度、掩膜在应用沙盒；分享导出只含脱敏摘要（`01` §9）。
- 用户删除即物理删除；去标识回归集需单独授权（`11` §3）。

## 5. App Entity 化预留（Phase 4）

Property、Inspection、Room、Observation 各有稳定 ID 与可显示名；Phase 4 接 App Intents（"Add this house"、"What did I dislike about the house on Saturday?"）与 Visual Intelligence。V1 不实现，只保证字段存在。

## 6. 扩展位

`Property.extensions: [String: Codable]` 预留 finance intent（Phase 4，独立 workflow）与跨 App（风水境）授权字段；V1 不写入。

## 7. 迁移

SwiftData 模型版本化；破坏性变更写迁移；SceneRecord 的 `schema_version` 独立演进。
