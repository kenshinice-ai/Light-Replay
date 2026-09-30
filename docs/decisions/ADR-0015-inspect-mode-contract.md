# ADR-0015 · Inspect 模式契约：Capture / Note / Measure；push-to-talk；不做 Sound lens

- 状态：Accepted（2026-09-30，Lee 批准）
- 日期：2026-09-30
- 来源：Codex v2 §9、§17、§22、§26；`04-capture-protocol.md`；`11-compliance-boundaries.md`

## 背景
看房只有 15–30 分钟，中介在场。用户进入房子后的理想交互是 Open → Start → Walk + Shoot + Talk → Done。OneTake 若做成单独的"分析模式"，就会被跳过。开放看房里连续录音会录到中介与其他买家的对话，撞 Surveillance Devices Act (Vic) 的 private conversation 条款【引】。

## 决定
1. Inspect 是一个相机式界面，只有三个动作，没有模式选择：
   - **Capture**：一张照片 + 自动元数据（时刻、位置与精度、朝向候选、设备姿态、可选房间标签）→ `Observation(source: user_photo, level: observed_noted)`。
   - **Note**：push-to-talk；端侧 `SpeechTranscriber` 转写；FM `@Generable` 结构化为 `InspectionObservation { room, category, sentiment, text, followUp }`；原始转写保留，用户可编辑；不保存音频；不连续录音。
   - **Measure**：OneTake（`04-capture-protocol.md`）→ SceneRecord → `LightObservation`。
2. 三个快速标签：Like / Concern / Ask；Ask 自动生成一条 Question。任何五级评分 UX 不做。
3. 预算：Time to First Capture < 10 s；每套房额外操作 ≤ 3 min（含 2–3 个 OneTake 点）。
4. 不做：Sound lens；后台持续定位；自动连拍；人脸；文件拍摄。
5. 权限按需请求：相机在 Start Inspection 时；麦克风在第一次 Note 时；定位在建档或 Measure 时；相册在导入时。

## 备选
- 语音连续录制再离线整理：法律风险与信任风险都高。
- 先做完整房间扫描：v5 / v6 已否决（隐私、许可、信息增益低）。

## 后果
- 01 §4 按此重写；15 的 Observation 模型；11 §3 加 push-to-talk 与不保存音频；Phase 1 小 spike C3（语音 → 结构化）设通过线。
