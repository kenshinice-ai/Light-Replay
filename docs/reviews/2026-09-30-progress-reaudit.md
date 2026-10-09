# Property Replay · 修复后进展复审（第二轮）

日期：2026-09-30，Australia/Melbourne。审计基线：`cea97756a43f720dc84a9ea7f734bcf53423ea95`。
目录：`/Users/llmacbookpro/Library/Mobile Documents/com~apple~CloudDocs/PARADISE PRODUCTION/07 TOOLS/light_replay`。
分支：`feat/inspect-screen`，与 origin 一致；审计开始时工作区干净。PR #2 尚未合并，GitHub 未显示 CI 检查。

本轮只读审计源码、已有签名产物与交接资料，并执行测试/合成探针。没有修改业务代码、安装真机应用、启动真机相机/麦克风、调用云模型、提交或推送。上一轮报告保持原样，本报告替代其“当前状态”判断，不抹去历史问题。

## 1. 结论

**进展真实且明显：项目已从“可打开的界面壳”推进到带持久化模型、拍照/语音路径、绑定房产的 R0 采集和 Apple AI 能力检查的原生原型。** 上轮编号覆盖、锚点混用、负真北、默认 light=measured、照片保存失败丢草稿等已有针对性修复。

但仍不能把它称为“全年日照 App 已跑通”：生产 SunEngine、NorthResolver、QualityEvaluator、天空分割、可见域累积和时间回放都没有实现。当前记录继续保持 R0，不产生直射小时数，这是正确的阶段保护。

下阶段建议：先补资产/数据库一致性与异步草稿问题，然后投入最小可重放的单点测量链。暂不继续加 tab，不为 PCC 而扩张功能。

## 2. 本轮直接验证了什么

| 检查 | 本轮结果 | 不代表什么 |
|---|---|---|
| `scripts/test.sh` | Swift SceneRecord 28 tests + Python 30 tests，全部通过 | 不是 UI、真机或现场日照验收 |
| iOS 27 simulator `xcodebuild test` | App smoke 1 + CaptureCore 9 + PropertyModel/Observation 8，共18 tests，通过 | 不是实际相机/录音/模型输出验证 |
| 上轮6个结构/语义探针 | 缺 lens、frame 时间越界已拒绝；另外4个仍 ACCEPT | QualityEvaluator 还没闭合，不是“false-valid 已消除” |
| 删除错误探针 | 对只读临时目录，throwing remove 正确报错；silent remove 正常返回且文件仍在 | 不代表用户真实照片曾发生遗留；是对现有 helper 的合成复现 |
| PCC 源码配置 | project.yml、entitlements 均有 `com.apple.developer.private-cloud-compute=true` | 不是产品已经在调用 PCC |
| 已有真机签名产物 | DerivedData-device 中 app 的签名 entitlement 与 embedded profile 均有 PCC=true | 是此前构建产物，不是本轮重新签名或云模型请求 |
| Git | HEAD 与 PR #2 head 相符；起始工作区干净 | PR 提交/合并不能替代产品验收 |

测试计数为 **28+30+18=76**，跨语言用例有重叠，不能把76解释成独立现场场景数。

直接运行 Python unittest 时，必须设置 `SCENE_RECORD_CHECK` 指向外部缓存中已构建的 Swift CLI；裸命令会在 parity setUpClass 因默认 `.build` 不存在而报错。本轮按 `scripts/test.sh` 配置后30项通过，属于测试入口环境要求，不算产品回归。

日志：
- `/private/tmp/propertyreplay-reaudit-20260930-xcode.log`
- `/private/tmp/propertyreplay-reaudit-20260930/tests.xcresult`
- `/private/tmp/propertyreplay-reaudit-schema.json`
- `/private/tmp/propertyreplay-reaudit-probes/`（删除权限故障探针）

合成复算脚本：同目录 `2026-09-30-reaudit-probes.py`；删除失败探针为 `2026-09-30-delete-failure-probe.swift`（与当前 MediaStore.swift 编译到临时目录运行）。

现有真机产物目录：`~/Library/Caches/propertyreplay/DerivedData-device/Build/Products/Debug-iphoneos/PropertyReplay.app`，目录时间 2026-09-30 20:24:44。本轮只读了签名能力布尔值，不在报告放账号、描述文件 UUID、设备标识或真实地址。

## 3. 上一轮问题的关闭状态

状态含义：“已修+回归”仅指对应代码机制与合成测试；“部分修复”表示原缺陷有进展但剩余边界未闭合；“待验收”不自动等于有 bug。

| 上轮编号 | 本轮判断 | 依据/剩余边界 |
|---|---|---|
| F01 编号覆盖 | 已修+回归 | 从磁盘取号、创建专用目录、withoutOverwriting；同编号第二次写入抛错。仍需失败后清理/恢复 |
| F02 删除范围 | 部分修复 | 已统一 SceneStore 与照片删除，但单条 helper 吞异常，文件/数据库事务顺序仍有故障窗口 |
| F03 方向残留/无效真北 | 部分修复 | 每会话清空，记录 heading，负真北 invalid；同步相机方位求 Δ 已加测试；设备顶部→镜头映射还是假设 |
| F04 锚点基准 | 已修+回归 | CaptureLog 显式保存锚点与 frame ID，未锁定 offset=null/rejected |
| F05 质量门槛 | 部分修复 | lens 必填、t 上界已修；单组 σ=12、coverage=1%、glass过多、anchor不一致仍可 ACCEPT |
| F06 退出/中断 | 部分修复 | onDisappear、AR 中断/失败记录已加；没有完整 scenePhase/后台协议 |
| F07 房产/设置关联 | 主要路径已接 | Measure 传 property/room，高度与容差进入日志；落一条 Unknown light observation；数据库失败后的资产关联还需处理 |
| F08 pin失败处理 | 部分修复 | MapKit 补全、保留失败表单、重新放 pin 已有；数据库错误却仍混进 pinFailed，地址/pin身份也可能不同步 |
| F09 静默内存库 | 主要入口已改善 | 可见横幅、Add/Inspect保存禁用；Measure/详情修改等入口还需统一持久化权限 |
| F10 时间/资产 | 时间修复，资产待做 | ARFrame 单调时间、每帧位姿已记录；Hero 图像、depth/confidence/mask仍不保存 |
| F11 证据措辞 | 保留设计分歧 | 团队保留蓝图映射；未来结果仍应显式展示“按当前遮挡条件推算”，不能说未来当天已实测 |
| F12 docs/tests | 部分修复 | 测试入口说明已补；README下一步、PCC待办、Note真机未验证/已验证并存，仍需要整理 |
| D01 录音取消 | 主要竞态已改善，待压力测 | generation 与每个 await 后检查、退出停止已有；旧任务仍可能写新会话 state，缺可控延迟测试 |
| D02 无证据measured | 已修+回归 | `.light` 初始 Unknown；`lightLevel` 按质量字段映射，有测试；解锁 R1 前仍应通过真实 QualityEvaluator |
| D03 保存失败丢草稿 | 已修代码，故障注入待做 | do/catch、rollback、错误提示、保留 draft；“Done/返回时尚未保存的草稿”是另一条未覆盖路径 |

不采用“13条已修完”的单一数字作为验收结论：修复实现、正常路径、故障恢复、真机验证是四个不同状态。

## 4. 真机和 Apple AI 的证据分层

### R0 真机采集

HANDOFF 记录一次 iPhone 17 Pro/iOS27.0.1 首跑：167帧、157 normal、最大漂移0.14m、罗盘±13°、定位±8m，Python 校验通过。这是**项目交接记录**，本轮未读取同一场景原始 scene.json 或重做扫描，也没有现场遮挡/日照真值验证。

可以说：项目已经做过真机 R0 首跑。不能说：已证明室内北向误差、冬至日照小时或全年精度。

### 中文转写

HANDOFF 最新段落记载 Lee 真机中文转写验证；源码确实从设备 supportedLocales 选精确标识。可以把“中文端侧转写跑通”作为团队记录的进展。仍缺 zh/en 对照样本、完整长句、多段转写、快速按下/松手、后台中断、资源未下载的重复验收。

### Foundation Models

已有 `NoteStructurer` 端侧 `@Generable` 路径，保持原文，模型摘要另存；数字过滤只是有限保护。尚无本轮模型准确率、反事实输入或幻觉回归证据。它不是太阳/北向算法，测量链边界仍被保留。

### PCC

分清三个层次：
1. **权限与签名：可确认已配置。** 源码与已有 device signed app/profile 同时有 entitlement。
2. **runtime可用：团队交接记录确认。** CapabilitiesView 的 isAvailable 只表示可用性。
3. **业务调用：尚未实现。** 仓库唯一 PCC 模型实例在 CapabilitiesView；NoteStructurer 实际用 SystemLanguageModel.default，没有 PCC respond、quota、网络失败、模板降级的产品链路。

无需为了“已经开通PCC”现在就用它。先完成端侧/模板的确定性闭环，再用全合成输入做一次明确的 PCC smoke，记录版本、locale、usage与失败降级；真实房产内容云端用途仍按既定授权边界。

## 5. 剩余问题和新发现

### R01 · P1 · 删除故障被吞，删除失败仍可能留下幽灵或缺资产记录

位置：`MediaStore.swift:22–39,53–55`；`PropertyStore.swift:26–33,38–53`；`PropertyDetailView.swift:65–68`。

单条删除调用 removeIgnoringMissing，它对“权限不足/IO错误”也 try?；随后继续删除数据库行并保存。详情入口再次 try? 后 dismiss。文件没删却关系没了，无法在正常 UI 找到重试对象。

相反，deleteEverything 先删资产再删除/保存数据库；若第二个目录删除或数据库 save 失败，已删除资产不能 rollback，而数据库行还可能存在。源码注释“files first prevents ghosts”不能成立：先后顺序本身不能提供跨介质事务。

**本轮合成复现**：在权限0555的临时目录创建合成图片；throwing helper 抛错，silent helper正常返回，文件仍在。没有触碰用户真实资料。

改法：单条删除也只忽略明确不存在；错误上传 UI；用隔离/待删目录 + cleanup journal、删除任务或可恢复状态协调模型与文件，不靠互换先后顺序。旧版本 Documents/PR-…如存在也需迁移或显式遗留扫描。
验收：单条/整套/全部删除，注入文件失败与DB失败；只清目标资产、错误可重试、不留下失联真实资料。

### R02 · P2 · 测量文件成功后，数据库关联失败会丢失可恢复流程

位置：`CaptureValidatorView.swift:93–117`；`SceneExporter.swift:20–24`。

stop() 后 CaptureLog 仅是局部变量；先写目录/scene.json，再 remember/save。关联失败只有错误字符串，没有 rollback、待关联索引或重试入口。再次按“Start”是新采集，不是原记录重试。exportURL虽保留可分享，也不代表房产历史里能找回。

SceneExporter 创建目录后编码或写入失败也不清理/标识未完成目录；无完整事务或资产 manifest。

改法：保留 PendingCapture/scene_id；记录 export与association的各自状态；成功/失败有可恢复索引；严格避免覆盖，完成标记与校验；DB失败恢复关联而不是强制重扫。
验收：写文件后DB失败、目录创建后IO失败、App重启，原记录可找回、不串房、不重复落库。

### R03 · P2 · 异步 AI 结果更新到父草稿，却不更新编辑卡片

位置：`ObservationCard.swift:6`；`InspectView.swift:33–37,218–226`。

父 View先把原始转写放入draft，显示卡片；等待模型后修改父draft。卡片自己的 `@State var draft` 只取初始值，同一身份的后续父输入不会自动同步。Save回调传的是卡片本地副本，房间/类别/摘要可能仍是AI返回前的版本。

改法：单一draft真相（Binding或共享可观察模型）；每个草稿有稳定ID；异步结果只合并到匹配ID，并尊重用户已编辑字段。不要简单每次新结果都重建卡片覆盖用户修改。
验收：让AI延迟3秒，期间改房间/类别；返回后建议可见、编辑不丢，Save与所见一致；丢弃/新草稿后旧结果不能串入。
证据级别：静态SwiftUI状态路径，未在本轮操作真机或UI宿主复现。

### R04 · P2 · Done/返回可直接丢弃尚未保存的照片或语音草稿

位置：`InspectView.swift:46–49,261–268`。

finish只保存inspection并dismiss；没有检查draft、正在录音或模型正在生成。Save失败时保留草稿的修复很好，但用户随后点Done仍会丢掉它。

改法：退出前给保存/丢弃/继续三种明确动作；正在录音先停止并保留结果；处理中允许取消且不偷偷保存。
验收：拍照未Save、语音未Save、Save失败、模型处理中各退出一次；用户的选择和最终数据一致。

### R05 · P2 · generation取消还需要会话资源归属，不能让旧任务写新状态

位置：`NoteRecorder.swift:43–76,109–145`。

新generation确实阻止多数取消后启动路径。但旧start在await后发现stillWanted=false，会无条件写state=idle；如果新start已进入preparing，这会覆盖新状态。after-analyzer路径的shutdown引用全局self.engine/analyzer，也没有限定它们属于哪代。

改法：取消时持有并取消task；state变化与资源清理都检查generation；每代拥有自己的资源，销毁旧代不能停新代。再加入scenePhase/应用后台协议；onDisappear不能覆盖所有后台场景。
验收：下载/权限/音频准备各注入延迟，快速按-松-再按，旧任务不能改新状态、不能停新麦克风，不得松手后留下录音。当前正常中文转写记录不能代替这项。

### R06 · P2 · Add的磁盘保存错误仍被当作pin错误，重试可能插入重复房产

位置：`AddPropertyView.swift:100–105`。

context.insert后save失败，只设pinFailed=true，没有rollback或保留同一对象重试，提示变成“Save without pin”。再点Save会创建/insert另一条Property。第一次尚未保存的插入仍可能在之后保存/自动保存时落库。

改法：pinError与storageError分开；DB保存失败保留单个pending对象或撤销本次插入；只有真正写盘成功才dismiss。
验收：第一次DB失败、第二次恢复，最终仅一条房产，地址/坐标完整；用户看到真实失败原因。

### R07 · P2 · 编辑地址不会使旧pin失效，错误地图位置可持续显示

位置：`PropertyDetailView.swift:26,63,73–80`。

修改address只清pinNote，latitude/longitude/suburb仍旧。重新放pin失败也不标记原pin过期。房名变成B地址、地图仍指向A，Inspect距离排序继续用A。

改法：坐标绑定已解析地址与版本；地址改变后显示pin stale/待重定位，不能静默当有效位置；异步结果匹配query版本，旧请求不能覆盖新地址。
验收：A改B、离线重定位、B请求中改C，Map与距离只使用与当前地址匹配的坐标。

### R08 · 解锁R1前阻断项 · QualityEvaluator仍待实现

复算6个探针：

| 用例 | Swift/Python最新结果 | 解释 |
|---|---|---|
| missing lens | REJECT/REJECT | 已修 |
| frame超session时间 | REJECT/REJECT | 已修 |
| 仅单组方向σ=12° | ACCEPT/ACCEPT | ADR-0009需要阻断 |
| coverage=1%，gate=pass | ACCEPT/ACCEPT | 应由质量层阻断 |
| glass占走廊90%，gate=pass | ACCEPT/ACCEPT | 应由质量层阻断 |
| target/lock锚点不同 | ACCEPT/ACCEPT | 物理自洽层需检查 |

接受把shape校验和QualityEvaluator分层；不要求所有门槛硬编码进JSON解析器。但在后者存在并接入前，不能将passed字段本身当“可发布R1”证明。当前Builder仍R0，未证明实际用户端产生过错误直射小时数。

此外，CaptureLog内会保存全部headings，Builder最终只导出firstValidHeading构成的一个candidate；下一阶段需要保留原始样本或统计/筛选证据，否则group spread与标定难以离线复算。

## 6. 不应继续重复的旧结论

- 不能再说编号仍必然覆盖：写一次保护与磁盘取号已有测试。
- 不能再说PCC还没配置：源码、已有签名与profile均有证据。
- 不能再说默认light就被标measured：现在初始Unknown。
- 不能再说所有保存错误都丢草稿：照片/语音的显式Save已修；Measure关联和Done是不同路径。
- 不能把“中文转写跑通”扩展为AI摘要、日照或云模型已验证。

## 7. 下一阶段顺序与验收

### 第一批：资料不丢、不串、不假成功

R01、R02、R04、R06、R07；同一批完成统一保存/删除服务与错误状态，覆盖文件与数据库两层。用合成数据做故障注入，不先依赖用户真实看房资料。

通过条件：两套房各一张照片、一条语音、一份R0；重启能找回，删除只删目标，失败可重试、不会覆盖/重复记录；未保存退出有明确选择。

### 第二批：端侧AI建议能可信编辑

R03、R05；统一draft与会话identity。先测试模型不可用、延迟、旧结果、用户手动纠正，再测中英文准确率。PCC可以暂不参与。

通过条件：所见即所存；旧模型结果/旧录音任务不会污染新记录；用户修改优先；后台/退出停止采集。

### 第三批：最小日照测量闭环

保存必要图像/深度/置信度/姿态/时间；SunEngine + 可见域 + 北向来源 + QualityEvaluator。先独立坐标/太阳单元测试，再庭院单点白卡延时，再室内隔玻璃与方向标定。以现有docs/07预注册门槛验收，保留holdout。

通过条件：R0升级R1有可追溯证据；未知不变直射；任意日期只是“在当前场景条件下推算”；有现场时刻误差统计。

### 文档同步

README仍写下一步真机首跑/线B待开工；路线图和ADR-0010仍写PCC待申请；HANDOFF包含早先Note未验证和后来中文已验证两段。建议压成一个状态表：源码状态、本轮测试、团队真机记录、待验收。更新事实不必新增核心ADR。

## 8. 总体判定

可以继续内部开发和受控真机验证。已有代码修复与PCC签名进展值得确认；目前还不适合作为能给买家确定日照结论的消费者测试版本。下一轮最值得投入的是可靠资料闭环和单点测量，价格、B2B平台、复杂天气/生成效果继续后置。
