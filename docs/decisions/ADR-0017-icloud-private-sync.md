# ADR-0017 · 资料库同步到用户自己的 iCloud 私有库；数据库是唯一事实来源

- 状态：Accepted（2026-09-30，Lee 决定"一开始就做 iCloud 自动备份，回家在 iPad 上看"）
- 日期：2026-09-30
- 修订：`15-product-model.md` §1a / §3 / §4、`11-compliance-boundaries.md` §3 的"只在设备与本机"

## 背景

1. 看房在手机上，复看在家里：买家回家想在 iPad 上看照片、语音和测量结果，换手机也不能丢。
2. 第二轮复审（`reviews/2026-09-30-progress-reaudit.md`）R01 / R02 指出：照片和 SceneRecord 放在 Documents 文件里、数据库只存路径，删除和保存跨两种介质，任何顺序都会留下"行没了文件还在"或"文件写了行没关联"的窗口。
3. 原则"本地优先、不强制账户"（`15` §4）要保留：不登录也能完整使用，不引入我们自己的服务器。

## 决定

1. **SwiftData + CloudKit 私有库**（容器 `iCloud.com.pwegroup.propertyreplay`）。只用私有库：数据在用户自己的 iCloud 里，开发者不可读；不用公共库、不用共享库（couple 模式到 Phase 3 另议）。
2. **字节跟着行走**：照片（`photoData`）和 SceneRecord JSON（`sceneRecordData`）用 `@Attribute(.externalStorage)` 存在行上，CloudKit 以 asset 同步。保存、删除都是一个数据库事务（`PropertyStore.commit` 失败即回滚）。磁盘上的 `scene.json` 只是分享用的临时副本。
3. **测量先落待关联文件**：`PendingCapture` 先写 Application Support，再存库；存库成功才删文件；启动时自动补关联；`scene_id` 保证不重复。
4. **开关**：You › Privacy & data 的 "iCloud sync"，默认开；容器启动时配置一次，所以切换下次打开生效。iCloud 不可用（未登录、受限）时 SwiftData 照常本地运行，登录后自动补同步。容器创建失败 → 仅本机 → 仍失败才落到内存并显示红色横幅。
5. **删除**："Delete everything" 在同步开启时同时删 iCloud 里的副本，确认框写明。
6. **iPad**：App 改为 universal（`TARGETED_DEVICE_FAMILY 1,2`），iPad 以阅读为主；Inspect / Measure 在 iPad 上可用但不针对它设计。
7. **CloudKit 模型约束**：所有存储字段有默认值，关系全部可选，不用唯一约束。`UserPreferences` 两台设备各建一行时，最早的一行胜出、其余删除。
8. **不同步的东西**：待关联测量文件（同步只发生在它进库之后）、临时分享副本、日志；语音音频从来不存（ADR-0015）。

## 备选

- **只靠设备备份（iCloud Backup）**：零代码，但 iPad 看不到，恢复是整机级别。否决。
- **iCloud Drive 文件夹**：文件与数据库仍是两个介质，R01 / R02 原样存在，还多了冲突副本问题（本组 iCloud 冲突副本的教训）。否决。
- **自建服务器同步**：违背"不引入我们自己的服务器"和隐私承诺，成本高。否决。
- **只同步文字、照片留本机**：iPad 看不到照片，正是这次需求的核心。否决。

## 后果

- 上架前必须在 CloudKit Console 把开发环境的 schema 部署到 production；之后模型只能加字段，不能改名或删字段（CloudKit 限制），破坏性变更要写迁移并新建字段。
- 旧版本在 Documents/observations 与 Documents/scenes 的文件由 `LegacyFiles.migrate` 在启动时搬进数据库，成功存库后才删文件；未绑定房产的调试采集不动。
- 隐私说明、定位权限文案、Add property 与 Properties 空态文案改为"本机和你的私有 iCloud"。
- 跨设备在同一天测量可能分配到同一个 `scene_id`（编号取自已同步的行，同步有延迟）。V1 只在手机测量，风险低；Phase 3 前改为带设备后缀或 UUID。
- 同步本身（两台设备、离线再上线、删除传播）需要真机双设备验收，模拟器只验证了无账号降级。
