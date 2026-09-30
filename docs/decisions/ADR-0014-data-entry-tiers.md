# ADR-0014 · 数据入口分层：用户分享优先；Domain API 不进首发

- 状态：Accepted（2026-09-30，Lee 批准）
- 日期：2026-09-30
- 来源：Codex v2 §13–15；本轮核实

## 背景
Codex 把 Domain Developer API 列为 Tier 1。核实：Domain 不公布价格，按行业与月调用量按合同出 Product Schedule；API 条款 7.6(d) 禁止向第三方 "display, disclose or otherwise commercially exploit" API 产品【验：domain.com.au/group/api-terms-and-conditions】。REA 没有面向第三方消费级 App 的开放 listing API【引 Codex】。ADR-0004 已决定首发不依赖需要谈判的数据。

## 决定

| 层 | 内容 | 阶段 |
|---|---|---|
| A · 用户分享 | Share Extension 收到的 URL（REA / Domain URL 含地址 slug）、截图、PDF、listing 文字；Vision `RecognizeDocumentsRequest` 端侧 OCR + FM 抽取地址 / 房间 / 尺寸；手动输入 | 首发核心 |
| B · 开放政府数据 | G-NAF 地址校验；建筑轮廓（Overture / OSM）供墙面对齐与朝向估计 | 首发 |
| C · 授权数据 | Domain API 等：只在有商务谈判且条款允许对用户展示时评估 | Phase 4 |
| D · 合作 | REA、PropTrack、CoreLogic 等 | Phase 4+ |
| 不做 | 持续抓取门户；把 listing 页面内容缓存为自有数据 | 永不 |

Prep 在 V1 能说的只有三类：主要窗朝向（轮廓 + 用户分享的户型，Indicative）；用户预约的看房时刻太阳在哪、客厅会不会有直射（SunEngine）；建议在哪几个点 OneTake。

## 备选
- 先谈 Domain：谈判周期不可控，且条款可能根本不允许。
- 抓取：法律与稳定性风险，否决。

## 后果
- Phase 1 小 spike C1（URL → 地址）、C2（截图 / PDF → 地址与房间）设通过线（`12-roadmap.md`）。
- 11 §5 许可表加 Domain API 一行。
