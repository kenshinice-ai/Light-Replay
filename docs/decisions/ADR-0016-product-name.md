# ADR-0016 · 产品名 Property Replay；Light Replay 是功能名

- 状态：Accepted（2026-09-30，Lee 授权 Claude 选定）
- 日期：2026-09-30

## 背景
候选：光镜 / Light Replay / Property Lens / Property Replay。本轮核实（2026-09-30）：

| 候选 | 发现 |
|---|---|
| Property Lens | 美国 PropertyLens（买家报告 + API + LensAI）、澳洲 app.propertylens.au、PropertyLenz（房东巡检 App）、澳洲 Realestate Lens（Promethic Labs，买家侧合同审阅）【验】。出局 |
| Light Replay | IP Australia 0 条【验】；但只描述光，与 ADR-0012 的产品对象不符 |
| Property Replay | IP Australia 商标快速检索 0 条【验】；网络检索无同名产品【验】；propertyreplay.com / .com.au / .au 可注册，.app 已被注册【验 whois】 |
| 光镜 / 光境 | 中文名；"光镜"在光学语境是显微镜简称。不作 App Store 名 |

## 决定
- 产品名 **Property Replay**；tagline "See beyond the inspection."。
- 功能族 **Replay**：Light Replay、Space Replay。
- Bundle ID `com.pwegroup.propertyreplay`（沿用 PWE Receipts 的 `com.pwegroup.*` 约定）。
- 中文内部昵称暂留 光境；对外中文名待定，不在 V1 决定。
- 仓库名保留 `Light-Replay` 直到 Lee 决定改名（GitHub 改名保留跳转）。

## 备选
见表。

## 后果
- README、CLAUDE.md、蓝图、名词表改名；文档里 Light Replay 只指功能。
- 上架前用 IP Australia TM Checker 或律师做正式商标意见；公开检索不是法律意见。
- 域名注册由 Lee 决定。
