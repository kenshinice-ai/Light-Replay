# 阶段 A 交付复审与分割冒烟给料

日期：2026-10-04（Australia/Melbourne）。评审：Codex。状态：**问题待 Claude 修正；本轮只准备样本、运行验证和写评审，没有修改实现。**

基线：`eb271f5`，`feat/inspect-screen`；开始时工作区干净【验】。对象：Claude 的阶段 A 回应、ADR-0022、两端 SceneRecord / QualityEvaluator、`tools/segsmoke`。数字的【验】仅指本轮软件验证或观察；版本、日期、编号和代码字面量用于定位。

## 判断与给料

阶段 A 的契约和兼容测试确实已交付。SceneRecord 的 Swift 测试 **36 项**、Python 含 Swift 对照 **96 项**通过【验】；但下面 **4 个**异常输入仍被两端接受【验】，因此不能把“已有测试全绿”当作契约已完整守住。建议先修 A01、A02，再补 A03、A04；B 的输入保存与恢复可以继续准备，不必重写总体方案。

按 `HANDOFF`“等 Lee”指定的位置，已放入 `field/data/smoke/`：**9 张**真实网络照片【验】，窗外、屋檐、树下各 **3 张**【验】。Lee 本轮明确允许网上下载；它们不是 Lee 的现场采集，也没有 AR 姿态、深度或内参，不能替代实验 1 的 App 帧卷、日晷或 holdout。

- `sources.csv` / `sources.json`：逐张来源、作者、许可链接、下载变换、尺寸、SHA-256；所有文件已解码并核对摘要【验】。
- `contact-sheet.jpg`：人工检查过内容的总览。
- `inputs-960/`：按 EXIF 转正、长边不超过 960 px【验】的派生输入；原下载文件保留。
- `results-ready/`：首轮所有原始日志、逐图命令、掩膜、叠加图；没有删失败样本。
- `results-corrected-seed/`、`corrected-08.csv`、`corrected-09.csv`：调整种子后的两张对照。
- `README.md`、`human-review.csv`、`run_smoke.py`：Claude 可直接接手。

上述样本与结果都被 `field/data/` 忽略规则排除【验】，没有提交或推送。详细冒烟记录见 [spike 补记](../spike/2026-10-04-segmentation-smoke.md)。

## A01 · P1：检测证据没有关联到本次实际采集帧

位置：`engine/lightreplay/scenerecord.py:498–521`；Swift `SceneValidator.swift:518–541`；`docs/04-capture-protocol.md` §6。

把 `horizon.frame_id` 改成不存在的帧，把 `lens.frame_id` 改成另一场扫描的标识，两个校验器仍接受 R1，水平与镜头仍为 `pass`【验】。目前仅验证字符串和数值，未验证检测结果来自本次扫描。`not_found` 还可以没有帧和检测器标识，却给水平灯通过。

影响：错关联或恢复时串入的证据能支持本次质量灯；“五灯按证据重算”只证明数值相符，尚未证明证据属于此记录。

改法：把采集帧与 Hero 身份传入证据校验；运行过的地平线检查必须指向本次有效稳定输入，镜头检查按规范指向本次 Hero；`not_found` 也保留运行来源。稳定性的证明在 B 的输入契约中补齐，不能仅凭检测器字符串默认成立。

关闭条件：不存在、其他扫描、错误 Hero 的引用被拒；合法的本次引用与带来源的 `not_found` 仍接受，两端共享夹具。

## A02 · P1：重叠时段可重复计入直射分钟

位置：`engine/lightreplay/scenerecord.py:432–474`；Swift `SceneValidator.swift:553–586`。

复制 `10:55–13:50` 的直射段，再把 `totals.direct_min` 从 **175** 改成 **350 分钟**，两端都接受【验】。各态总和成为 **755 分钟**，查询窗口实际只有 **580 分钟**【验】。代码只核对每段起止与逐段加和，没有核对不同段互斥、日期属于查询、时段落在窗口内。

影响：新结果契约能接受虚增的直射时长；后续列表、Compare 或回放可能把它当作可信的派生结果。这里是合成校验反例，并非已经观察到 App 输出错误时长。

改法：逐日验证有序、无重叠、无重复日期、查询范围与时间窗口；按已定契约决定是否要求完整覆盖，缺口显式为未知。先拒绝冲突，不能静默合并含不同状态的重叠段。

关闭条件：重复直射、直射与未知重叠、越界时段及查询外日期都被拒；正常四态分段和总数保持兼容。

## A03 · P2：掩膜只验证文件头，图像解码上限没有守住

位置：`engine/lightreplay/scenerecord.py:151–172,227–229`；Swift `SceneValidator.swift:325–330`；ADR-0022 第 2 条及 `docs/03` §11。

构造只有 **24 字节**、没有完整 IHDR / IDAT / IEND 的伪 PNG，声明尺寸为 **100000 × 100000**，长度和 SHA-256 按这些字节正确填写，两端仍接受 R1【验】。这只是 **100 亿像素**的文件头声明【验】，本轮没有解码或分配对应内存。

影响：关键帧掩膜可能不能打开；编码文件小于载荷上限，也不代表解码后的像素和内存有界。回应里“解码上限与完整性检查已补齐”的表述目前超出实际检查。规范自身也只写签名和 IHDR，需连同实现补齐。

改法：明确最大宽高、像素数、像素格式和解码字节上限，并在解码前检查；验证 PNG 结构和可解码性，在有界条件下读出真实尺寸。完整性摘要与图像格式有效性是两项不同检查。

关闭条件：截断 PNG、缺少必需块、超限尺寸在两端拒绝；正常掩膜仍通过。不要通过实际解码巨图来写测试。

## A04 · P2：零帧支持仍可声明已知天空网格

位置：`engine/lightreplay/scenerecord.py:387–400`；Swift `SceneValidator.swift:462–474`；`docs/04` §12。

仅把 `visibility.votes.frames_used` 改为 `0`，保留已有天空网格与 `min_distinct_frames=3`，两端仍接受 R1【验】。目前只校验非负和网格直方图，没有校验支持帧数量与被计入的帧之间的关系。

影响：累积摘要与原始采集证据矛盾，记录仍能进入结果链。整体帧数也不能证明每个格子有足够的不同帧支持。

改法：至少拒绝零帧却有已知格、帧数低于门槛以及超出实际有效帧数的声明；明确 `frames_used` 的计数口径。C 的 VisibilityCore 应在累积时执行时间 / 姿态去重，并保存足以解释逐格支持的证据；不要把一份直方图称为逐格投票证明。

关闭条件：上述矛盾被拒，两端一致；去重与逐格支持另用物理合成夹具验收。

## 复现与验证边界

复现脚本：[2026-10-04-stage-a-probes.py](2026-10-04-stage-a-probes.py)。仅构造虚构记录，不改实现或既有 fixture；每项输出两端接受 / 拒绝及质量灯，不输出大载荷。

```sh
swift test --disable-sandbox --package-path ios/Packages/SceneRecord --scratch-path /tmp/propertyreplay-codex-review/SceneRecord-build
python3 docs/reviews/2026-10-04-stage-a-probes.py --swift-check /tmp/propertyreplay-codex-review/SceneRecord-build/debug/scene-record-check
(cd engine && SCENE_RECORD_CHECK=/tmp/propertyreplay-codex-review/SceneRecord-build/debug/scene-record-check python3 -m unittest discover -s tests)
```

本轮 `scripts/test.sh` 在嵌套 SwiftPM 沙箱处失败；定位为 `sandbox-exec: sandbox_apply: Operation not permitted`。关闭 SwiftPM 自身沙箱、仍使用 iCloud 外 scratch 后，上述改动相关测试通过【验】。未重新验证未改动的 NorthResolver / SunEngine 全套、iOS UI、iPhone 性能、跨设备恢复或现场测量。`CLAUDE.md` 与 `AGENTS.md` 一致【验】。

设计六问：本轮服务于 Light 输入与结果可信度；明确网络 / 合成 / 现场边界；所有数字来自日志与复算；没有改界面、动效、产品文案或权限。App 仍写 schema 0.1.0【引：Claude 交接，本轮未装机】，所以这些新契约反例不能直接描述为线上用户已遇到的故障。
