# ios/

iOS App 与 Swift 包。部署目标 iOS 27.0（ADR-0011）。

## 现有

| 路径 | 内容 | 状态 |
|---|---|---|
| `Packages/SceneRecord` | 测量载荷（`docs/03`）的无类型 `JSONValue` 文档、严格 JSON 预检（拒绝重复键、深度 > 128）、`SceneValidator`、`scene-record-check` CLI | 28 个 XCTest 全绿；与 `engine/` 的 Python 实现有一致性测试。**定位：规范的裁判（oracle）。** W1 在其上加类型化 Codable 模型供采集模块使用，并以"类型化模型编码出的 JSON 必须过校验器"作为测试 |

## 目标结构

```
ios/
├── project.yml                  xcodegen 定义（待建）
├── PropertyReplay.xcodeproj     生成物，不手改
├── PropertyReplay/              App target（SwiftUI）：Home / Properties / Compare；Property 详情；Inspect 模式；Replay · Light
├── PropertyReplayShare/         Share Extension（Add，ADR-0014）
└── Packages/
    ├── SceneRecord/             已有
    ├── PropertyModel/           Property 图（SwiftData，docs/15）
    ├── CaptureCore/             ARSession 封装、帧与姿态记录、Hero frame、漂移
    ├── VisibilityCore/          天空分割适配（Vision 交互式分割 + 几何种子）、可见域累积、深度重投影、走廊覆盖
    ├── NorthResolver/           方向候选、独立组、鲁棒融合、σ 输出（docs/05，ADR-0009）
    ├── SunEngine/               太阳位置、时区、采样、时段分级（docs/06）
    ├── Guide/                   LLMProvider 抽象（端侧 FM / PCC / 模板）；语音结构化；教练句；文案（ADR-0010）
    └── GeometryCore/            RoomPlan windows、AR 平面、R2 投影（Phase 3）
```

Bundle ID `com.pwegroup.propertyreplay`（ADR-0016）。Share Extension `com.pwegroup.propertyreplay.share`。

## 构建

- 构建产物在 iCloud 之外：`swift test --package-path ios/Packages/SceneRecord --scratch-path ~/Library/Caches/propertyreplay/SceneRecord-build`，或直接 `./scripts/test.sh`。Xcode 工程用默认 DerivedData（在 `~/Library/Developer`，已在 iCloud 之外）。
- 设备：spike 需带 LiDAR、已升级 iOS 27 的 iPhone，至少一台支持 Apple Intelligence。R1 不依赖 LiDAR；R2 依赖。
- ARKit、RoomPlan、Speech、Foundation Models 只能真机；模拟器跑纯算法与界面。

## 依赖策略

- 太阳位置：自写 NOAA / SPA 实现并与 `engine/` 的 pvlib 交叉核对；不引入大依赖。
- 天空分割：首选 Vision `GenerateIterativeSegmentationRequest` + 几何种子（W1 评估）；不达线改 CoreAI 自训模型。
- 语音：`Speech.SpeechTranscriber` 端侧转写；结构化用 Foundation Models `@Generable`，经 `LLMProvider` 抽象，数字只来自 Tool（ADR-0010）。
- 第三方包尽量少；引入前记录许可到 `docs/11-compliance-boundaries.md` §5。

## Week 1 最小目标（线 A）

一个只有一个按钮的采集验证器：开始 OneTake，记录 `docs/03` 定义的 CaptureSession 字段，显示走廊覆盖率与漂移，导出 SceneRecord JSON 与帧掩膜到 Files。没有结果页。与原型 A（线 B，SwiftUI 假数据五屏）在同一工程的不同 target 或同一 App 的 debug 入口。
