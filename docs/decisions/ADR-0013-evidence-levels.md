# ADR-0013 · 对外证据五级与来源标签；R 等级留在测量链内部

- 状态：Accepted（2026-09-30，Lee 批准）
- 日期：2026-09-30
- 来源：Codex v2 §6；蓝图 §5

## 背景
测量链用 R0–R3 描述输入充分性，用 稳定直射 / 方向敏感 / 遮挡 / 资料不足 描述时段。Property 图里还有照片、语音、listing 说法、模型推断，需要一套用户看得懂、跨来源统一的等级，否则"listing 说北向"和"实测冬至三小时"会被摆成同一种东西。

## 决定
对外只用五级 + 来源标签；R 等级与时段四态写在 SceneRecord 与证据卡里，不出现在主界面。

| 对外等级 | 含义 | 来源 |
|---|---|---|
| Verified | 用户确认的事实，或带出处的授权数据 | 用户确认北向、房间；G-NAF 地址 |
| Observed · measured | 现场传感器测得，过质量门槛 | SceneRecord R1 / R2 且 `false_valid_guard = passed` 的"稳定直射"时段 |
| Observed · noted | 现场用户记录 | 照片、语音转写、Like / Concern / Ask |
| Strong indication | 多来源一致 | R1 时段与用户观察一致 |
| Indicative | 模型推断，待验证 | R0 参考模式；R1 的"方向敏感"时段；Prep 的朝向估计；FM 从 listing 抽取的字段 |
| Unknown | 资料不足 | R1 的"资料不足"时段；未采的房间；未知的树种 |

来源标签：`listing`（用户分享的 listing 内容）、`user_photo`、`user_voice`、`sensor`（SceneRecord）、`open_data`（G-NAF、轮廓）、`model`（FM 推断）。每条 Observation 必带一个等级与一个来源；Compare 的每一格也是。

规则：
- 等级只能由规则赋予，不能由 FM 赋予；FM 抽取的内容一律 Indicative 或 Unknown。
- 等级只降不升，除非有新的更高来源；用户编辑 FM 抽取的内容后仍是 Indicative，除非用户点"确认"变 Verified。
- "未测"永远显示为 Unknown，不显示为空白或中间值。

## 备选
- 只用 R 等级：对非测量来源无意义。
- 用百分比置信度：无法解释，且会被当成精度。

## 后果
- 01 结果页与 Compare 的每格加等级与来源；15 的 Observation 模型带两个字段；03 顶部加映射说明。
