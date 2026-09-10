# ios/

iOS App 与 Swift 包。**目前为空**；本文件描述计划中的结构，供 Week 1 建工程时照做。

## 目标结构

```
ios/
├── LightReplay.xcworkspace
├── LightReplay/                 App target（SwiftUI）
│   ├── App/
│   ├── Capture/                 OneTake 界面、覆盖率环、漂移提示
│   ├── Result/                  照片 + 时间滑杆 + 时段条
│   └── Share/
└── Packages/
    ├── SceneRecord/             数据模型与 JSON 编解码（docs/03）
    ├── CaptureCore/             ARSession 封装、帧与姿态记录、Hero frame、漂移
    ├── VisibilityCore/          天空分割适配、可见域累积、深度重投影、走廊覆盖
    ├── NorthResolver/           方向候选、独立组、鲁棒融合、σ 输出（docs/05）
    ├── SunEngine/               太阳位置、时区、采样、时段分级（docs/06）
    └── GeometryCore/            RoomPlan windows、AR 平面、R2 投影（V2 起）
```

## 设备与系统

- 开发与 spike 设备：带 LiDAR 的 iPhone（12 Pro 及之后）。R1 不依赖 LiDAR；R2 依赖。
- 部署目标：待定（ADR 待写）。倾向 iOS 18+ 以覆盖测试机；iOS 26 的交互式分割等能力按运行时可用性检测，不作硬依赖。
- ARKit 只能真机运行。模拟器用于 SceneRecord、SunEngine、NorthResolver 的单元测试。

## Week 1 最小目标

一个只有一个按钮的 App：开始 OneTake，记录 `docs/03-scene-record.md` 定义的 CaptureSession 字段，显示走廊覆盖率与漂移，导出 SceneRecord JSON 与帧掩膜到 Files。**没有结果页。**

## 依赖策略

- 太阳位置：自写 NOAA/SPA 实现（约 200 行）并与 `engine/` 的 pvlib 交叉核对；不引入大依赖。
- 天空分割：先用 Core ML 通用分割模型（候选：DeepLab/SegFormer 的 sky 类）；WWDC26 交互式分割作为可选修正路径，运行时检测。
- 第三方包尽量少；引入前记录许可到 `docs/11-compliance-boundaries.md` 的许可表。
