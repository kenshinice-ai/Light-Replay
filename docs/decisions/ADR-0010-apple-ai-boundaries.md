# ADR-0010 · Apple 端侧 AI 与 Private Cloud Compute 只用于辅助层

- 状态：Accepted（2026-09-16，Lee 批准）
- 日期：2026-09-16
- 来源：`docs/proposals/2026-09-16-apple-ai-acceleration.md`

## 背景
Xcode 27.0 / iOS 27.0 SDK 提供：Foundation Models 端侧模型带图像输入与工具调用；`PrivateCloudComputeLanguageModel`（同一 session API，32K 上下文，按用户每日额度）；Vision `GenerateIterativeSegmentationRequest`（点 / 框 / 涂抹种子，可迭代，需下载模型资源）；`DetectLensSmudgeRequest`、`DetectHorizonRequest`；CoreAI 自定义模型框架【验，接口文件】。PCC 资格：Small Business Program、首次下载少于 200 万、entitlement【验】。这些能力能省掉自训分割模型和一批文案与教练代码，但也可能把"看起来确定"的输出混进测量链。

## 决定
Apple AI 只进入辅助层，按下列边界使用：

**允许**
1. 天空分割：以 Vision 交互式分割为首选路径，种子由几何生成（地平线以上、太阳走廊内的像素带），用户可点选修正；W1 评估不达线时改用 CoreAI 自训模型。
2. 帧级质量与反射标记：端侧 FM 图像理解只在关键帧运行，输出作为"玻璃不确定"的辅助信号，不替代像素分割。
3. 拍摄教练：规则先判断是否具备判断资格，FM guided generation 只负责把结构化状态写成一句中英提示。
4. 结果卡、复看建议、Light Passport 文本：FM `@Generable` 结构化输出；SunEngine 与 NorthResolver 作为 Tool，数字只能来自工具结果。PCC 只用于低频的整页文本。
5. 采集质量灯：镜头脏污检测作第五盏灯；地平线检测与重力互查。

**禁止**
- 生成、改写或"修正"任何小时数、方位、角度、覆盖率。
- 参与太阳位置、北向融合、可见域累积、投影的计算（ADR-0002）。
- 把"未知"或"玻璃不确定"说成确定。
- 在逐帧路径上调用 FM 或 PCC。

**降级**
FM 不可用（机型、未开启、资源未下载、语言不支持）→ 模板句与规则；分割资源未下载 → 手工涂抹并标"手工分割"；PCC 不可用或额度用尽 → 端侧或模板。每次降级写入 `quality.flags`。

**回归**
测试集加入"模型试图改写数字"的用例，作为阻断项；分割评估集 20 帧人工标注天际线，候选线 IoU ≥ 0.90 且失败可识别。

## 备选
- 不用 Apple AI，全部自研：多约一周训练与转换，且失去交互修正；放弃。
- 让 FM 参与解释分歧与选择方向来源：违反宪法第 1 条；放弃。

## 后果
- `02-architecture.md` 第 1、6、8 节；`04-capture-protocol.md` 第 5、6 节；`03-scene-record.md` 第 5、8 节；`07-spike-plan.md` 第 2、5 节；`01-product-spec.md` 第 8 节；`11-compliance-boundaries.md` 第 5 节；`13-glossary.md`。
- 需要 provider 抽象（`LLMProvider`），PCC 超限或资格变化时可迁移到自有服务端。
- PCC entitlement 由项目主账号申请，状态待定；spike 不依赖它。
