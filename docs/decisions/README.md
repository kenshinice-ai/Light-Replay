# 架构决策记录（ADR）

每个决定一个文件；状态：Proposed / Accepted / Superseded。改决定先改 ADR，再改蓝图。

| 编号 | 决定 | 状态 |
|---|---|---|
| [ADR-0001](ADR-0001-target-point-primitive.md) | 分析原语是 TargetPoint × 天空可见域 | Accepted |
| [ADR-0002](ADR-0002-physics-for-evidence.md) | 物理算事实，生成只做呈现 | Accepted |
| [ADR-0003](ADR-0003-native-ios-single-app.md) | 原生 iOS 先行；单 App 首发；系列保留 | Accepted |
| [ADR-0004](ADR-0004-no-licensed-data-at-launch.md) | 首发不依赖商业地图与授权高程数据 | Accepted |
| [ADR-0005](ADR-0005-v1-exclusions.md) | V1 排除项：法律文件、风水、合规线、地址级评分、价格 | Accepted |
| [ADR-0006](ADR-0006-viewpoint-drift-handling.md) | 镜头漂移用深度重投影处理，不拒帧 | Accepted |
| [ADR-0007](ADR-0007-north-resolver.md) | 真北是多来源一致性问题；不确定性以时段表达 | Accepted |
| [ADR-0008](ADR-0008-r1-first.md) | V1 只交付 R1；R2 光斑标"潜力投影" | Accepted |
| [ADR-0009](ADR-0009-north-conflict-handling.md) | NorthResolver 冲突取最大一致组合；磁罗盘单独偏离不阻断；solar 残差检查 | Accepted |
| [ADR-0010](ADR-0010-apple-ai-boundaries.md) | Apple 端侧 AI 与 PCC 只用于辅助层；允许 / 禁止 / 降级 / 回归 | Accepted |
| [ADR-0011](ADR-0011-ios-27-minimum.md) | Spike 与 V1 只支持 iOS 27 | Accepted |
| [ADR-0012](ADR-0012-property-as-product-object.md) | 产品对象是 Property；OneTake 是英雄采集；Light 是第一个 Lens | Accepted |
| [ADR-0013](ADR-0013-evidence-levels.md) | 对外证据五级与来源标签；R 等级留在测量链内部 | Accepted |
| [ADR-0014](ADR-0014-data-entry-tiers.md) | 数据入口分层：用户分享优先；Domain API 不进首发 | Accepted |
| [ADR-0015](ADR-0015-inspect-mode-contract.md) | Inspect 模式：Capture / Note / Measure；push-to-talk；不做 Sound lens | Accepted |
| [ADR-0016](ADR-0016-product-name.md) | 产品名 Property Replay；Light Replay 是功能名 | Accepted |
| [ADR-0000](ADR-0000-template.md) | 模板 | — |

待写：天空分割路径的最终选型（W1 评估后）；D_near 与漂移阈值（spike 后）；对外中文名；仓库改名；Finance bridge 的独立 workflow 设计（Phase 4）。
