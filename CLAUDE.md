# CLAUDE.md — Property Replay

项目级事实与约定。跨项目偏好见 `~/.claude/CLAUDE.md`；本组（07 TOOLS）约定见上级 `CLAUDE.md`。接手先读 `docs/HANDOFF.md`。

## 事实来源

- `docs/00-blueprint.md` 是唯一事实来源。要改一个决定，先写或改 `docs/decisions/` 里的 ADR，再改蓝图，最后改受影响的规范。
- 策略稿存档在仓库目录内的 `light_replay_history/`，已被 `.gitignore` 排除（不入库、不公开）。观点已被蓝图吸收或否决，不要再从那里引用"决定"。
- 当前阶段以 `README.md` 的"下一步"与 `docs/12-roadmap.md` 为准。没有代码之前，任何文档不得写"已实现"；spike 期间不得写"已验证"，除非有 `field/` 里的记录编号可查。

## 语言与命名

- 文档中文；代码、注释、commit、标识符、文件名英文。
- 产品名 Property Replay；Light Replay 只指功能。术语统一用 `docs/13-glossary.md`：Property、Inspection、Observation、TargetPoint、OneTake、Viewpoint Lock、NorthResolver、SceneRecord、R0–R3、证据五级、太阳走廊、可见域。不要自造同义词。
- 数字一律标注【验】【引】【估】。spike 通过线是"候选"，事后不放宽；确需修订，写 ADR 记录理由。

## 明确不做

价格、法律文件解读、风水功能、规划合规评分线、地址级评分、任何"生成即证据"、Sound lens、V1 的金融内容。有人要求时先指向 `docs/11-compliance-boundaries.md`，再问 Lee。

## 构建与验证

- `./scripts/test.sh` 跑全部纯算法测试；`./scripts/ios-test.sh [unit|ui]` 在专用模拟器上跑 iOS 单元与 UI 测试（跑完关机）。改界面必须跑 UI 测试并看最大字号截图。构建产物必须在 iCloud 之外（`~/Library/Caches/propertyreplay/`）；手跑 `swift build` / `swift test` 加 `--scratch-path`。原因：codesign 拒绝带 iCloud FinderInfo 的 bundle。
- ARKit、LiDAR、RoomPlan、Foundation Models、Speech 只能在真机上跑；模拟器只能跑纯算法（SunEngine、NorthResolver 融合、可见域累积、SceneRecord 编解码）与界面。
- 纯算法必须有 Swift 单元测试，并与 `engine/` 的 Python 参考实现交叉核对（同一输入，输出差异要有容差说明）。
- 涉及现场的结论，引用 `field/` 中的采集编号与延时记录编号。
- 任何 PR 过 `docs/14-design-principles.md` §8 的六问；涉及数字的改动过 Assist 回归。

## 数据与隐私

- `field/data/` 不入库。含照片、深度、位置的原始数据默认只在采集设备与本机。
- 文档里不放真实地址、门牌、客户姓名、开发者账号邮箱；示例一律虚构并标明。

## Git

- 只在 Lee 要求时 commit / push。commit 信息英文，Conventional Commits 风格（`docs:`、`feat(capture):`、`test(sun):`）。
- 不改写共享历史。远端 `kenshinice-ai/Light-Replay` 是公开仓库。

## 恢复工作

从 `docs/HANDOFF.md` §7 的当前状态和 `README.md` 的"下一步"开始；先看 `field/` 有没有新记录，再看 ADR 是否有新条目。
