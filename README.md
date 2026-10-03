# Property Replay

**See beyond the inspection.**

把 20 分钟看房，变成一份可以回放、比较、验证的房产记忆。其中最硬的一块：站在你会生活的位置扫一次天空，20 秒后得到这个点一年的直射阳光，每个数字带来源、精度、未计入项。

状态：**Phase 1 · 并行验证**（2026-09-30 起）。文档、数据层、Xcode 工程完成；真机已跑通 R0 采集、Inspect（拍照、中英文语音笔记）、端侧模型与 PCC 能力检查、iCloud 私有库同步。下一步见文末。

## 三条不变的原则

1. **物理算事实，生成只做呈现。** 直射时段来自太阳几何与现场实测的天空可见域；AI 结构化语音、写文案，数字只来自工具。
2. **你站在哪里，答案就是哪里。** 分析单位是一个目标点；换一个座位，就是另一次采集。
3. **证据分级，未知进入计算。** Verified / Observed / Indicative / Unknown 每条都显示；没扫到的天空是"未知"，不是空白。

## 怎么读

| 顺序 | 文档 | 回答什么 |
|---|---|---|
| 0 | [docs/HANDOFF.md](docs/HANDOFF.md) | 十分钟上手：真相在哪、怎么跑、这一阶段审什么 |
| 1 | [docs/00-blueprint.md](docs/00-blueprint.md) | 冻结的决定与产品契约。**唯一事实来源** |
| 2 | [docs/01-product-spec.md](docs/01-product-spec.md) | 三个任务、Add / Prep / Inspect / Your inspection / Replay / Compare |
| 3 | [docs/15-product-model.md](docs/15-product-model.md) | Property 图与 SceneRecord 的关系 |
| 4 | [docs/02-architecture.md](docs/02-architecture.md) | 模块、数据流、坐标约定 |
| 5 | [docs/03-scene-record.md](docs/03-scene-record.md) | SceneRecord 数据规范（测量载荷） |
| 6 | [docs/04-capture-protocol.md](docs/04-capture-protocol.md) | OneTake：视点锁定、太阳走廊、玻璃、五盏灯 |
| 7 | [docs/05-north-resolver.md](docs/05-north-resolver.md) | 真北：多来源融合与不确定性传播 |
| 8 | [docs/06-sun-engine.md](docs/06-sun-engine.md) | 太阳几何、采样、时段分级 |
| 9 | [docs/07-spike-plan.md](docs/07-spike-plan.md) | 三周测量 spike：指标、通过线、holdout、否决条件 |
| 10 | [docs/08-ground-truth-protocol.md](docs/08-ground-truth-protocol.md) | Paradise Production 现场真值协议 |
| 11 | [docs/09-light-passport.md](docs/09-light-passport.md) | 挂牌日照页与来源标签（分发试点） |
| 12 | [docs/10-competitors.md](docs/10-competitors.md) | 已核实的竞品：太阳 App、门户、买家侧工具 |
| 13 | [docs/11-compliance-boundaries.md](docs/11-compliance-boundaries.md) | 产品宪法、措辞、隐私、许可、金融分隔 |
| 14 | [docs/12-roadmap.md](docs/12-roadmap.md) | Phase 0–4、汇合门、kill criteria |
| 15 | [docs/13-glossary.md](docs/13-glossary.md) | 名词表 |
| 16 | [docs/14-design-principles.md](docs/14-design-principles.md) | 设计原则与 PR 评审六问 |
| — | [docs/decisions/](docs/decisions/README.md) | ADR-0001 至 0017 |
| — | [docs/reviews/](docs/reviews/2026-09-10-blueprint-v1-review.md) | 评审记录与复算脚本 |
| — | [docs/proposals/](docs/proposals/2026-09-30-property-lens-v2-response.md) | 已批准的方案及其来源 |
| — | 策略稿存档 | `light_replay_history/`，被 `.gitignore` 排除，不入库、不公开 |

## 目录

```
light_replay/
├── README.md · CLAUDE.md
├── docs/                     规范、ADR、评审、方案（见上表）
├── ios/
│   ├── project.yml · PropertyReplay.xcodeproj（生成物）
│   ├── PropertyReplay/       五个 tab：Home / Properties（List·Map）/ Inspect（相机、Capture / Note / Light）/ Compare / You；W1 采集验证器
│   └── Packages/
│       ├── SceneRecord/      测量载荷的校验器与 CLI（规范的 oracle，Swift，28 测试）
│       ├── CaptureCore/      CaptureLog、SceneRecordBuilder、CaptureRecorder（ARKit，5 测试）
│       └── PropertyModel/    Property、Inspection、InspectionObservation、UserPreferences、MediaStore（SwiftData，8 测试）
├── engine/
│   ├── lightreplay/          Python 参考实现（scenerecord.py）
│   └── tests/                含 Swift 跨语言一致性测试
├── scripts/test.sh           跑全部纯算法测试（构建目录在 iCloud 之外）
├── scripts/ios-test.sh       在专用模拟器上跑 iOS 单元与 UI 测试
├── report/                   分享页（待建）
└── field/                    现场模板；数据不入库
```

## 跑测试

```bash
./scripts/test.sh            # 纯算法：SceneRecord、SunEngine、Python 参考
./scripts/ios-test.sh unit   # iOS 单元测试（专用模拟器）
./scripts/ios-test.sh ui     # UI 测试，约 6 分钟
```

## 团队

Lee：决定、现场、渠道。Paradise Production：采集、真值、Light Passport 试点。Claude：原型、代码、文档。Codex：阶段性评审（`docs/HANDOFF.md` §4）。

## 标注约定

【验】本轮核实过来源。【引】引自前稿、未复核。【估】推断或假设。**所有通过线在验证前都是候选，不是承诺。**

## 下一步

Phase 1 进行中。地基（资料不丢、不串、不假成功，iCloud 同步）、Light 扫描界面、SunEngine 与太阳走廊覆盖率、界面评审的三轮修改（大字号、iPad 分栏、复看、同步状态）已在源码与模拟器测试里；相机方向、AR 轨迹对齐、VoiceOver 仍待真机验收。方向融合（NorthResolver）与质量门槛（QualityEvaluator）也已就位，记录里写的灯必须与证据一致。界面英文 + 简体中文；iPhone 可横屏；Compare 的九个维度都有记录入口。下一步是把日照测量闭环接完：天空分割（相机帧 → 可见域；方案 `docs/proposals/2026-10-03-sky-segmentation-plan.md`，存储与时机按 ADR-0019）、罗盘以外的方向来源、日照结果页，再到庭院单点白卡延时验收（`docs/12-roadmap.md`、`docs/HANDOFF.md` §7）。
