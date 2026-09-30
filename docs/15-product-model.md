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
| `Property` | `uuid`、`address`、`suburb?`、`latitude?`、`longitude?`、`pinAddress?`、`source`（manual / shared / sample）、`status`（toInspect / inspected / shortlisted / dropped）、`createdAt`、`inspectionAt?`、`notes?` | 坐标来自 Apple 地理编码，只用于 pin；`pinAddress` 不等于当前地址时 pin 过期、不显示也不参与距离；`sample` 只在 DEBUG 出现且标注虚构 |
| `UserPreferences` | `displayName`、`priorityRaws[]`（≤ 5）、`targetHeightM`、`hapticsEnabled`、`viewpointToleranceM`、`noteLanguage?`、`createdAt` | 每个 iCloud 账户一行；`PropertyStore.preferences(in:)` 首次创建，多行时最早的胜出 |
| `PropertyStore` | `container(inMemory:iCloudSync:)`、`commit`、`record`、`preferences(in:)`、`delete`、`deleteEverything(in:)` | 每次写入要么完整保存，要么回滚并抛错；删除是物理删除 |

| `Inspection` | `uuid`、`startedAt`、`endedAt?`、`property`、`observations[]`（级联删除） | 一套房同时只有一个未结束的 inspection；`PropertyStore.openInspection(for:in:)` 找或建 |
| `InspectionObservation` | 第 2 节的字段；`photoData`、`sceneRecordData`（外部存储）；Swift 类型名避开 `Observation` 模块 | `level` 由规则赋予；`modelSuggested` 标记仍有模型建议的标签未被买家确认；`mediaPath` 只剩旧版迁移用 |
| `PendingCaptures` | `write`、`commit`、`recover`、`takenSceneIDs` | 测量先落 Application Support 再存库；按 `scene_id` 幂等（ADR-0017） |
| `LegacyFiles` | `migrate`、`sweep`、`removeAll` | 把 ADR-0017 之前的 Documents 文件搬进行；只忽略"不存在"，其他错误上抛 |

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

- SceneRecord 格式仍是 JSON（`03-scene-record.md`），可回放、可交叉核对；JSON 存在 light observation 的 `sceneRecordData` 上，分享时写临时 `<scene_id>.json`（ADR-0017）。
- 删除 Property 级联删除其 observation，记录随行消失；没有要单独清理的目录。
- 后续的图像、深度、掩膜资产同样作为外部存储字段挂在行上，不再引入独立目录。
- 一个 TargetPoint 一份 SceneRecord；同一房间多个点是多条 LightObservation。

## 4. 存储

- SwiftData，本地优先；不强制账户。开启 iCloud sync 时镜像到用户自己的 CloudKit 私有库，供同一 Apple ID 的 iPad 复看（ADR-0017）。
- 原片、深度、掩膜作为外部存储字段挂在行上，只在设备和用户私有 iCloud；分享导出只含脱敏摘要（`01` §9）。
- 用户删除即物理删除；去标识回归集需单独授权（`11` §3）。

## 5. App Entity 化预留（Phase 4）

Property、Inspection、Room、Observation 各有稳定 ID 与可显示名；Phase 4 接 App Intents（"Add this house"、"What did I dislike about the house on Saturday?"）与 Visual Intelligence。V1 不实现，只保证字段存在。

## 6. 扩展位

`Property.extensions: [String: Codable]` 预留 finance intent（Phase 4，独立 workflow）与跨 App（风水境）授权字段；V1 不写入。

## 7. 迁移

SwiftData 模型版本化；破坏性变更写迁移；SceneRecord 的 `schema_version` 独立演进。CloudKit production schema 部署后只加字段，不改名、不删字段（ADR-0017）。
