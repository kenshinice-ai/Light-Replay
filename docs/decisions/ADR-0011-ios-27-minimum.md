# ADR-0011 · Spike 与 V1 只支持 iOS 27

- 状态：Accepted（2026-09-16，Lee 批准）
- 日期：2026-09-16

## 背景
本方案的加速来源（Vision 交互式分割、Foundation Models 图像输入、PCC、镜头脏污检测）都是 iOS 27 的 API。维持 iOS 26 兼容意味着为分割与教练各维护一条回退路径，而 spike 与试点设备都能升级到 iOS 27。

## 决定
Spike 与 V1 的最低系统版本为 iOS 27.0。iOS 27 之内仍按运行时可用性检测 Apple Intelligence 相关能力（机型、开启状态、资源、语言），不可用时走 ADR-0010 的降级。

## 备选
- iOS 26 + 回退路径：多两条代码路径与测试矩阵；收益是覆盖少量未升级设备；放弃。

## 后果
- `ios/README.md` 部署目标改为 iOS 27；`01-product-spec.md` 第 8 节加系统要求。
- 现场设备清单只列能运行 iOS 27 的 iPhone；LiDAR 与 Apple Intelligence 是两条独立的能力检测。
- V1 之后是否放宽，等 spike 与试点的设备数据。
