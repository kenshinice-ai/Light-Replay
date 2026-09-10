# 光境 · Light Replay

**拍下你会生活的位置，把它一年的直射阳光带回家。**

状态：**Pre-spike**（2026-09-10）。仓库目前只有蓝图与文档，没有可运行代码。下一步是 [docs/07-spike-plan.md](docs/07-spike-plan.md) 第 1 周的采集验证器。

## 一句话

一款 iOS App。看房现场，站到你会坐的位置，对着窗或天空做一次 OneTake 采集；回家后在自己拍的那张照片上拖动时间与日期，看这个点几点到几点有直射阳光、冬至日有几小时。每个数字带来源、精度、未计入项。

## 三条不变的原则

1. **物理算事实，生成只做呈现。** 直射时段来自太阳几何与现场实测的天空可见域；写实重打光只是带水印的预览，不产生任何数字。
2. **你站在哪里，答案就是哪里。** 分析单位是一个目标点，不是一间房。换一个座位，就是另一次采集。
3. **未知进入计算，不进入脚注。** 没扫到的天空显示为"未知"，结果给区间，不给小数点。

## 怎么读

| 顺序 | 文档 | 回答什么 |
|---|---|---|
| 1 | [docs/00-blueprint.md](docs/00-blueprint.md) | 冻结的决定与产品契约。**唯一事实来源** |
| 2 | [docs/01-product-spec.md](docs/01-product-spec.md) | 用户流程、证据等级 R0–R3、结果卡、分享页 |
| 3 | [docs/02-architecture.md](docs/02-architecture.md) | 模块、数据流、端侧与服务端的分工 |
| 4 | [docs/03-scene-record.md](docs/03-scene-record.md) | SceneRecord 数据规范 |
| 5 | [docs/04-capture-protocol.md](docs/04-capture-protocol.md) | 现场采集协议：OneTake、视点锁定、太阳走廊、玻璃 |
| 6 | [docs/05-north-resolver.md](docs/05-north-resolver.md) | 真北：多来源融合与不确定性传播 |
| 7 | [docs/06-sun-engine.md](docs/06-sun-engine.md) | 太阳几何、采样、时段分级 |
| 8 | [docs/07-spike-plan.md](docs/07-spike-plan.md) | 三周技术 spike：任务、指标、通过线、holdout、否决条件 |
| 9 | [docs/08-ground-truth-protocol.md](docs/08-ground-truth-protocol.md) | Paradise Production 现场真值采集协议 |
| 10 | [docs/09-light-passport.md](docs/09-light-passport.md) | B2B 挂牌报告与来源标签 |
| 11 | [docs/10-competitors.md](docs/10-competitors.md) | 已核实的竞品与观察名单 |
| 12 | [docs/11-compliance-boundaries.md](docs/11-compliance-boundaries.md) | 产品宪法、措辞模板、隐私、数据许可 |
| 13 | [docs/12-roadmap.md](docs/12-roadmap.md) | Spike → V1 → V1.5 → V2 → 系列 |
| 14 | [docs/13-glossary.md](docs/13-glossary.md) | 名词表：把新概念一次说清 |
| — | [docs/decisions/](docs/decisions/README.md) | ADR：每个决定的来龙去脉 |
| — | 策略稿存档 | v3–v6 策略稿与评审稿保存在本机 `../light_replay_history/`，不入库、不公开；观点已被蓝图吸收或否决 |

## 目录

```
light_replay/
├── README.md                 本文件
├── CLAUDE.md                 项目级协作约定
├── docs/                     规范与决策（当前唯一有内容的部分）
│   ├── 00-blueprint.md … 13-glossary.md
│   └── decisions/            ADR
├── ios/                      iOS App 与 Swift 包（待建，见 ios/README.md）
├── engine/                   Python 参考实现与验证脚本（待建）
├── report/                   分享页 / Light Passport 网页（待建）
└── field/                    现场数据模板；数据本身不入库
```

## 团队

- **Lee**：产品、现场采集、渠道。
- **Paradise Production**：现场采集、真值延时、Light Passport 试点。
- **Claude**：工程与文档。

## 标注约定

【验】本轮核实过来源。【引】引自前稿、未复核。【估】推断或假设。
**所有数字在 spike 结束前都是目标，不是承诺。**

## 下一步

Week 1 采集验证器：ARKit 会话记录（帧、姿态、重力、罗盘、深度、分割掩膜）、镜头锚点与漂移记录、太阳走廊覆盖率显示、SceneRecord JSON 导出。详见 [docs/07-spike-plan.md](docs/07-spike-plan.md)。
