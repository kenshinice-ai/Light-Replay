# 光境 · `docs/blueprint-v1` 评审核实与修改清单

- 日期：2026-09-10
- 评审对象：`docs/blueprint-v1` → `main`（commit `2750951`，34 个文件，+1275 / −2）
- 来源：云端 ultrareview 10 条；本地核实补充 2 条（#3、#12）
- 状态：**核实完成。第一、二批改法已于 2026-09-10 落地（见本分支后续提交）；第三批等 ADR-0009 由 Proposed 改为 Accepted 后执行。**
- 方法：逐条对照原文；数值用脚本复算（附录 A）；ARKit / ARCore 约定对照官方文档（附录 B）

---

## 1. 结论

1. 云端 10 条全部属实，没有误报。其中两条的理由需要修正：
   - #9（VPS）：问题存在，但"原生 App 里没有这个符号"不成立。真正的问题是 VPS 供应商没定。
   - #11（漂移列）：CSV 列与 `max_drift_m` 本来就不是同一个量，但命名与单位冲突仍然存在。
2. 另补 2 条：#3（像素到方向的轴约定没写死）、#12（只有一组且 σ > 6° 时方向灯无归属，整理本文时发现）。
3. #5 比先前口头汇报的更严重：05 第 3 节与第 6 节自相矛盾，照第 3 节字面实现存在 false-valid 路径。
4. 最高优先是 #1、#2、#3、#5、#12，它们能让输出"错误却确定"。
   - #1–#3 是规范本身的约定错误。Swift 与 Python 照同一份规范实现，交叉核对全绿也抓不到。
   - 需要有物理意义的约定测试，见 #3 的改法。
5. 没有纯措辞问题，全部是规范内部或规范之间的事实冲突。

## 2. 总览

| # | 问题 | 位置 | 类别 | 核实 | 处理 |
|---|---|---|---|---|---|
| 1 | Δ 的文字定义与公式方向相反 | `05:32`、`03:72`、`13:41`、`02:41` | 会算错 | 属实 | 直接改 |
| 2 | `asin(d_y)` 用在未归一化向量上 | `02:43–45` | 会算错 | 属实，比云端说的更严重 | 直接改 |
| 3 | 像素到方向的轴约定没写死 | `02:43`、`03:72` | 会算错 | 补充 | 直接改 |
| 4 | 冲突判定没用圆周差 | `05:26` | 误报冲突 | 属实 | 直接改 |
| 5 | 冲突时只留最可信组；05 §3 与 §6 矛盾 | `05:27`、`05` §6 | 丢佐证 + false-valid 路径 | 属实，严重度上调 | **D1：ADR-0009** |
| 6 | `coverage_pct` 没有公式 | `03:82`、`04:47` | 一致性，影响预注册 | 属实 | 直接改 |
| 7 | north 示例数字与算法不符 | `03:55–72`、`05:13` | 一致性 | 属实 | D4 后改 |
| 8 | "下午西晒"缺枚举与走廊定义 | `03:49`、`04:19` | 一致性 | 属实 | D2 后改 |
| 9 | VPS 供应商没定 | `05:17`、`03:64`、`13:48`、`11` §5 | 一致性 / 依赖 | 属实，理由修正 | D3 后改 |
| 10 | `SceneRecord.json` 与 `scene.json` | `field/README.md:13` | 一致性 | 属实 | 直接改 |
| 11 | `drift_max_cm` 的单位与命名 | `field/templates/capture-log.csv:1` | 一致性 | 前提有偏，结论成立 | 直接改 |
| 12 | 只有一组且 σ > 6° 时方向灯无归属 | `04:48`、`05:27`、`05` §6 | 可能 false-valid | 补充 | **D1：ADR-0009** |

说明：
- 位置 `05:32` 指 `docs/05-north-resolver.md` 第 32 行，其余同理。行号基于 commit `2750951`。
- 云端原顺序与本文编号的对应：1→#4，2→#1，3→#2，4→#5，5→#7，6→#8，7→#9，8→#10，9→#11，10→#6。

## 3. 需要 Lee 决定的事项

| 编号 | 事项 | 推荐 | 影响 |
|---|---|---|---|
| D1 | 批准 ADR-0009（草案见第 6 节） | 批准 | #5、#12 |
| D2 | "下午西晒"预设的候选定义 | 11 月–次年 3 月、14:00–日落【估】 | #8 |
| D3 | VPS 供应商 | Spike 只用 ARKit 地理追踪；ARCore Geospatial 记为候选，引入前登记 | #9 |
| D4 | 磁罗盘 σ 的取法 | `max(headingAccuracy, 组内分散, 先验)`，`headingAccuracy` 按 1σ 处理（候选，spike 校准） | #7 |

- D2–D4 风险低、容易回退，Lee 回复"按推荐"即可执行。
- D1 会改变 ADR-0007 的后果，需要 Lee 明确批准。
- 不依赖决定的条目（#1、#2、#3、#4、#6、#10、#11）可以先做。

## 4. 执行须知（给执行会话）

- 以仓库 `CLAUDE.md` 为准。改决定的顺序是先 ADR、再蓝图、最后规范；本清单里只有 #5、#12 涉及决定。
- 文档用中文；代码、标识符、文件名用英文；术语以 `docs/13-glossary.md` 为准。
- 数字标注【验】【引】【估】，阈值写"候选"。项目状态是 pre-spike，不写"已实现"或"已验证"。
- 替换文本是建议稿，执行前按行号核对原文。
- 只在 Lee 要求时 commit / push。

---

## 5. 逐条详情与改法

### #1 Δ 的文字定义与公式方向相反

**问题**

- 文字与公式对不上：
  - `05:32`、`03:72` 把 Δ 定义为"AR 参考轴**到**真北的顺时针角"。
  - `02:41`、`05:32`、`06:26` 的公式都是 `az_true = az_ar + Δ`（06 写作 `az_ar = az_true − Δ`）。
  - 按文字定义，公式应为 `az_true = az_ar − Δ`。三处公式彼此一致，错的是文字。
- `02:41` 写成 `yaw_true = yaw_ar + Δ`，但名词表 `13:41` 把 yaw 定义为 Δ 本身。方向的方位角应统一叫 `az_*`。
- `03:68` 的字段 `ar_to_true_north_yaw_deg` 名字里写的是反方向，而且与 `resolved.yaw_deg` 重复。

**证据**（附录 A）

- 反例：参考轴朝东（真方位角 90°）时，按文字 Δ = 270°。沿参考轴的射线 `az_ar = 0`，公式算出 270°，真值是 90°。
- 照文字实现时，航向误差等于参考轴真方位角的两倍：会话起始朝南北时约 0°，朝东西时 180°。现场结果会时好时坏，很难定位。

**改法**：公式不动，只改文字；参考轴按 #3 定为 −Z。

`05` §4 第 32 行替换为：

```markdown
- `Δ`：AR 世界 −Z 轴的真方位角（从真北俯视顺时针量到 −Z 轴）。`gravity` 对齐下 −Z 是会话开始时相机朝向的水平投影，所以 Δ 就是开始扫描时相机朝向的真方位角。
- `az_true = (az_ar + Δ) mod 360`；`az_ar` 的定义见 `02-architecture.md` 第 3 节。
- `gravityAndHeading` 对齐下 −Z 即罗盘给出的真北，Δ 应接近 0，差值就是罗盘误差，可作对照。
```

`13` 第 41 行替换为：

```markdown
| **yaw / Δ** | AR 世界 −Z 轴的真方位角（俯视顺时针）；`az_true = az_ar + Δ`。北向修正只改它 |
```

`03` 第 68、72 行随 #7 整段替换。`02` 第 41 行随 #3 整段替换。

### #2 `asin(d_y)` 用在未归一化向量上

**问题**

- `d_cam = K⁻¹[u v 1]ᵀ` 的 z 分量为 1，所以除了主点以外，向量模长都大于 1。旋转不改变模长，而 `asin(d_y)` 只对单位向量成立。
- 第 45 行 `p = c_cam + z·d_world` 却要求这个向量**不**归一化（z 是沿光轴的深度）。
- 同一个符号承担了两种约定，照抄只能对一半。

**证据**（附录 A；取画面上沿的像素，tan 30°）

| 相机仰角 | `asin(d_y)` | 真高度角 |
|---|---|---|
| 0° | 35.3° | 30.0° |
| 30° | 90.0° | 60.0° |
| 60° | NaN | 90.0° |

- 云端只算了水平拍摄时约 5° 的高估，并认为 NaN 只在超广角下出现。实际上普通镜头仰拍 60° 就会出 NaN。
- 墨尔本夏至正午太阳高度 75.6°（`06` §2）。扫太阳走廊本来就要大角度仰拍，正好落在出 NaN 的区间。
- Apple 点云示例的反投影是 `x = (u − cx)·depth/fx`、`y = (v − cy)·depth/fy`、`z = depth`，即 `sceneDepth` 是沿光轴的深度【验，附录 B】，与第 45 行的未归一化用法相符。

**改法**：与 #3 一起，整段替换 `02` §3，见 #3。

### #3 【补充】像素到方向的轴约定没写死

**问题**

1. **相机轴向没翻转。** `K⁻¹[u v 1]ᵀ` 用的是针孔约定（y 向下、z 朝前）。ARKit 相机坐标是 y 向上、z 指向屏幕一侧，即相机看向 −z【验】。
   - 中间要乘 `F = diag(1, −1, −1)`。Apple 点云示例代码里的 `makeRotateToARCameraMatrix` 做的就是这个翻转【验：搜索结果摘要，未打开示例源码】。
   - 漏掉的话，天空会被映射到身后下方。第一次测试就会暴露，代价小。
2. **方位角方向反了。** `atan2(d_x, d_z)` 在 ARKit 的世界坐标系（右手、Y 轴朝上）里是**逆时针**的。
   - 在 `gravityAndHeading` 下复算四个方向：南 = 0、东 = 90、北 = 180（附录 A），与全项目"真北 0°、顺时针"（`13:23`）相反。
   - 原文括号里的"按 ARKit 轴向约定校正"没说怎么校正。照字面实现，方位会被镜像，用同一套约定生成的合成测试查不出来。
3. **参考轴没定死。** `03:72` 写的是"+Z 轴（或约定的参考轴）"。
4. **注意事项。** ARKit 相机坐标按设备横向定义，与设备方向无关【验】。`capturedImage` 与内参对应的是传感器原生的横向图像【估：文档未明说，按常规用法】。如果分割在转成竖屏的图上运行，掩膜坐标要先转回原生方向。

**改法**

`02` §3 第 41–45 行（三段）整体替换为：

```markdown
关键约定：**可见域以 AR 世界方位角存储**。`az_ar` 从 AR 世界 −Z 轴起算，俯视顺时针；真北方位角 `az_true = (az_ar + Δ) mod 360`，`Δ` 是 −Z 轴的真方位角，由 NorthResolver 给出并带 σ（定义见 `05-north-resolver.md` 第 4 节）。北向修正只改 `Δ`，不改采集。

像素到方向：

- `r_cam = F · K⁻¹ [u v 1]ᵀ`，`F = diag(1, −1, −1)`：把针孔约定（y 向下、z 朝前）换成 ARKit 相机约定（y 向上、看向 −z）。`(u, v)` 是 `capturedImage` 原生方向的像素坐标；分割若在旋转后的图像上运行，先把掩膜坐标转回。
- `r = R_cam · r_cam`（`R_cam` 为 camera transform 的旋转部分）。`r` 不归一化：它沿光轴的分量为 1，供深度重投影使用。
- `d̂ = r / |r|`；方位角 `az_ar = atan2(d̂_x, −d̂_z)`，高度角 `alt = asin(d̂_y)`。

深度重投影（LiDAR）：`sceneDepth` 的 `z` 是沿光轴的深度。若 `z < D_near`（候选 4 m），遮挡点 `p = c_cam + z · r`，改用 `d' = normalize(p − p_target)` 落网格。远于 `D_near` 或无深度：直接用 `d̂`，并记录漂移 `|c_cam − p_target|`。
```

`02` §6 测试表：在 NorthResolver 行之后加一行。这是纯算法测试，W1 在模拟器上就能跑：

```markdown
| 坐标约定 | 物理对照夹具：按 `gravityAndHeading` 构造的合成场景 Δ = 0；−Z 朝东的合成场景中，朝西的窗得到下午直射；水平相机画面上沿像素的高度角等于半个垂直视场角 | 模拟器 / CI |
```

理由：交叉核对只能证明两份实现彼此一致，证明不了规范是对的。这三条测试的期望值来自物理事实，不来自规范。

### #4 冲突判定没用圆周差

**问题**：`05:24–25` 用的是圆周中位数与加权圆周均值，`05:26` 却是直接相减 `|Δ_i − Δ_j|`。

**证据**：`03` 自己的示例就是反例。solar 359° 对 map 2°，直接相减差 357°，门槛只有 13.4°。按原文应判为冲突、只出 R0，示例却写着 `conflict: false`。

**改法**：`05` §3 第 3 步替换为：

```markdown
3. 一致性：任两组的圆周差 `δ_ij = min(d, 360° − d)`，其中 `d = |Δ_i − Δ_j| mod 360`；`δ_ij > 3·sqrt(σ_i² + σ_j²)` 判为冲突。
```

同时在 `02` §6 NorthResolver 测试行加"跨 0°/360°"一类，见第 7 节清单。

### #5 冲突时只留最可信组；05 第 3 节与第 6 节自相矛盾

**问题**

1. **丢掉一致的佐证。** `05:27` 在任何冲突时只保留最可信的一组，其余全部否决，包括和它一致的组。
2. **规范自相矛盾，存在 false-valid 路径。**
   - 按 `05` 第 3 节实现：冲突按可信顺序"自动解决"，只有"最可信组只有一个来源且 σ > 6°"时才要求确认。
   - 按 `05` §6、`04` §6、ADR-0007 实现：任何冲突都亮红灯，确认前只出 R0。
   - 两种实现都"符合规范"。前者在高可信读数本身出错时会输出 R1，这就是 false-valid 路径。
3. **与 `01:79` 也有冲突。** 那里写的是"冲突**且无法解决**"才只出 R0。

**证据**（附录 A；数值为虚构示例）

| 场景 | 按 05 §3 字面实现 | 按 05 §6、04 §6、ADR-0007 实现 | 建议规则（ADR-0009） |
|---|---|---|---|
| A：solar 1±2、map 3±4、磁罗盘 40±8（只有磁罗盘偏离） | 只留 solar，map 被否决；不需要确认，出 R1 | 红灯，只出 R0 | 融合 solar + map，得 1.4° ± 1.8；磁罗盘被否决；绿灯，出 R1 |
| B：solar 20±2（点错了光斑）、vps 3±3、map 2±4 | 只留 solar 20°；不需要确认，出 R1（偏约 17°） | 红灯，只出 R0 | 融合 vps + map，得 2.6° ± 2.4；solar 被否决；红灯，确认前只出 R0 |

**改法**：写 ADR-0009（第 6 节）。批准后改 `05` §3 第 4–6 步、`05` §6、`04` §6，见第 7 节清单。

`05` §3 第 4–5 步替换为以下内容，原第 5 步顺延为第 6 步：

```markdown
4. 冲突时不平均：在两两一致的组合中取组数最多者融合；组数相同时，比较组合中最可信的组（顺序 `solar > vps > map > magnetic`）。其余组标"被否决"。
   - 被否决的只有 magnetic：不算冲突，冲突详情照记。
   - 否决了 magnetic 以外的组：算冲突，要求一次最小确认（用户指认墙面或地图拖拽），确认前只出 R0。
5. 只有一组有效且 σ > 6°：要求一次最小确认，确认前只出 R0。
6. 输出 `Δ`、`σ_Δ`、参与组、被否决组、冲突详情。
```

`05` §6 表替换为：

```markdown
| 状态 | 显示 |
|---|---|
| 两组以上一致（含磁罗盘单独偏离被否决） | 绿灯；结果卡写来源与 σ；有被否决的磁读数时注明 |
| 只有一组，σ ≤ 6° | 黄灯；提示可做一次确认 |
| 只有一组，σ > 6° | 红灯；要求一次最小确认；确认前只出 R0 |
| 冲突（否决了磁罗盘以外的组） | 红灯；显示分歧，要求确认；确认前只出 R0 |
| 无有效来源 | 只出 R0 |
```

`04` §6 方向灯一行替换为：

```markdown
| 方向 | 至少两个独立组一致 | 只有一组，σ ≤ 6° | 冲突（否决了磁罗盘以外的组）；只有一组且 σ > 6°；无有效来源 |
```

`01:79` 不必改：在新规则下，"冲突且无法解决"就是"用户未完成确认"，措辞仍然成立。

### #6 `coverage_pct` 没有公式

**问题**

- `03:82` 只列了字段名，没给公式。
- `06:30` 定义覆盖率 = 走廊内非未知单元 / 走廊单元，也就是"玻璃不确定"算作已覆盖。另一种同样合理的实现只把天空和遮挡算作已覆盖。
- 两种实现之差，就是走廊内"玻璃不确定"的比例。分割灯允许这个比例到 10%（通过），甚至 25%（警告）（`04:49`）。

**为什么比看上去重要**

- Spike 的误差只统计通过质量门槛的（accepted）场景（`07:26`），而是否通过由四盏灯决定。
- W1 之前不把公式写死，预注册就等于没写完。事后再选公式，就是变相放宽。

**改法**：采用 `06` 的定义。理由有两点：
- "玻璃不确定"靠多扫解决不了，覆盖环不该催用户补扫。
- 这些单元查询时仍按"资料不足"输出（`06:26`），不会被说成直射。

`03` §5 第 82 行替换为：

```markdown
| `coverage` | `corridor_cells`（走廊单元数，走廊定义见 `06-sun-engine.md` 第 5 节）、`unknown_cells`（状态 0）、`glass_cells`（状态 3）、`covered_cells = corridor_cells − unknown_cells`、`coverage_pct = covered_cells / corridor_cells`。玻璃不确定计入覆盖，另由分割灯约束（`04-capture-protocol.md` 第 6 节） |
```

`04` §6 第 47 行替换为：

```markdown
| 走廊覆盖（`coverage_pct`，定义见 `03-scene-record.md` 第 5 节） | ≥ 90%（候选） | 70–90% | < 70% |
```

### #7 north 示例的数字与算法不符

**问题**

- 三个有效候选两两之间无冲突（按圆周差算）。按 `05` §3 应三组全部融合，示例却写 `groups_used: ["map","solar"]`。没有任何规则允许静默丢掉一个有效的磁罗盘读数。
- `resolved` 写的是 0.6°、σ 2.4，但两种算法都得不出这个数：
  - 三组全部融合：0.0°、σ 1.75。
  - 只用 map + solar：359.6°、σ 1.79。
  - 按方差倒数加权融合，结果的 σ 不可能大于输入里最小的 σ（2.0）。
- 磁罗盘候选的 `sigma_deg: 8.0` 比它自己的 `heading_accuracy: 12.0` 还小，而 `05` 没定义 `headingAccuracy` 怎么换算成 σ。
- 这段 JSON 最可能被直接拿去当 Swift / Python 交叉核对的标准答案，值得现在就修。

**改法**：按 D4 推荐，磁罗盘 σ 取 12.0。复算结果为 359.78° / σ 1.77（附录 A）。

`05` §2 磁罗盘一行替换为：

```markdown
| 磁罗盘（CoreLocation `trueHeading`） | magnetic | 始终 | 5–15°，室内更差 | `headingAccuracy` 负值即无效；σ 取 `max(headingAccuracy, 组内分散, 先验)`，`headingAccuracy` 按 1σ 处理（候选，spike 用日晷真值校准）；`gravityAndHeading` 的 yaw 同源，不另算一份 |
```

`03` §4 第 55–72 行（JSON 块和其后的定义行）替换为：

````markdown
```json
{
  "candidates": [
    { "source": "magnetometer", "group": "magnetic", "yaw_deg": 8.0, "sigma_deg": 12.0, "valid": true,
      "raw": { "true_heading": 8.2, "magnetic_heading": 19.9, "heading_accuracy": 12.0, "sampled_at": "..." } },
    { "source": "wall_footprint", "group": "map", "yaw_deg": 2.0, "sigma_deg": 4.0, "valid": true,
      "plane_anchor_id": "…", "footprint": { "dataset": "overture", "feature_id": "…", "edge_bearing_deg": 12.5, "user_selected_edge": true } },
    { "source": "window_patch", "group": "solar", "yaw_deg": 359.0, "sigma_deg": 2.0, "valid": true, "evidence_frame": "…" },
    { "source": "sun_disk", "group": "solar", "yaw_deg": null, "sigma_deg": null, "valid": false, "reason": "sun not visible" },
    { "source": "geo_tracking", "group": "vps", "yaw_deg": null, "sigma_deg": null, "valid": false, "reason": "unavailable" }
  ],
  "resolved": { "yaw_deg": 359.8, "sigma_deg": 1.8, "method": "robust_circular_v0",
                "groups_used": ["magnetic", "map", "solar"], "groups_rejected": [],
                "conflict": false, "conflict_detail": null, "resolved_at": "…" }
}
```

`yaw_deg` 即 `Δ`：AR 世界 −Z 轴的真方位角（俯视顺时针），`az_true = (az_ar + Δ) mod 360`，见 `05-north-resolver.md` 第 4 节。示例中 solar 取 359°，刻意跨 0°/360°：实现必须用圆周运算，否则会误判冲突。三组两两一致，全部参与加权圆周均值。
````

说明：

- 新增的 `groups_rejected` 对应 `05` 里"其余标'被否决'"的输出，现行规则下同样需要。
- 删掉了 `ar_to_true_north_yaw_deg`，理由见 #1。
- 如果 D4 不采纳（保留磁罗盘 σ 8.0）：把 `heading_accuracy` 改为 8.0，`resolved` 改为 `yaw_deg: 0.0`、`sigma_deg: 1.7`，其余同上。

### #8 "下午西晒"缺枚举与走廊定义

**问题**

- `01:23` 列了四个快捷预设：冬季早餐 / 全年 / 下午西晒 / 自定义。`03:49` 的枚举只有三个值。
- `04:19` 只定义了冬季早餐与全年的日期和时段。
- 缺的不只是一个枚举值：没有日期和时段，就算不出太阳走廊，覆盖率门槛也就无从判断。

**改法**：按 D2 推荐。

`03` 第 49 行替换为：

```markdown
| `guidance` | object | `question`（`winter_breakfast` / `full_year` / `west_afternoon` / `custom`）、`corridor_ref` |
```

`04` 第 19 行替换为：

```markdown
- 由用户的问题决定：冬季早餐 = 6 月 ± 6 周、7:00–10:00；全年 = 全部日期、日出到日落；下午西晒 = 11 月–次年 3 月、14:00–日落（候选【估】）；自定义 = 用户给定的日期范围与时段。
```

### #9 VPS 供应商没定

**问题**

- `05:17` 写的 `CheckVpsAvailability` 是 ARCore 的 API。iOS 上是 `GARSession checkVPSAvailabilityAtCoordinate:completionHandler:`，需要启用 ARCore API【验】。
- 云端说"原生 App 里没有这个符号"不成立：ARCore 有 iOS SDK，名词表 `13:48` 也把 ARCore Geospatial 与 ARKit 地理追踪并列。
- 真正的问题是三处各说各话：
  - `05` 用的是 ARCore 的 API 名。
  - `03:64` 用的是 ARKit 的字段名 `geo_tracking`。
  - `13` 两个都列。
- ARCore 是新的外部服务依赖，按 `11` §5 要先登记许可，但许可表里目前没有这一行。
- Apple 文档只写地理追踪覆盖"澳洲多个大都市区"，没有点名墨尔本【验】，需要逐点查询。

**改法**：按 D3 推荐，spike 只用 ARKit。VPS 只在户外有用，室内主场景不受影响。

`05` 第 17 行替换为：

```markdown
| VPS / 地理追踪 | vps | 户外、有覆盖 | 供应商未公开；spike 实测 | Spike 只用 ARKit 地理追踪，逐点用 `ARGeoTrackingConfiguration.checkAvailability(at:)` 验证覆盖（Apple 只写"澳洲多个大都市区"，未点名墨尔本【验】）；ARCore Geospatial 为候选，引入前按 `11-compliance-boundaries.md` 第 5 节登记 |
```

`13` 第 48 行替换为：

```markdown
| **VPS** | 视觉定位服务，户外有覆盖时给高精度姿态。Spike 用 ARKit 地理追踪；ARCore Geospatial 为候选，引入前登记许可 |
```

`11` §5 许可表：在"Google 3D Tiles"一行之后加：

```markdown
| ARCore Geospatial（Google VPS） | 需启用 Google ARCore API；条款未审 | 候选；不进 spike，引入前登记 |
```

### #10 `SceneRecord.json` 与 `scene.json`

`03` 第 3 行声明自己是 `SceneRecord` 包的准绳，§9 写的文件名是 `scene.json`；`field/README.md:13` 写的却是 `SceneRecord.json`。

`field/README.md` 第 13 行替换为：

```
    └── <scene_id>/            scene.json（见 docs/03 第 9 节）、hero.heic、masks/、depth/、visibility/、analysis/、timelapse/
```

### #11 `drift_max_cm` 的单位与命名

**问题**

- 这一列记的是**实测**的每场景最大漂移（`07:32`）。`03` 里的 `max_drift_m` 是**阈值**（`04:31`，候选 0.40 m）。两者本来就不是同一个量，所以云端的前提有偏差。
- 但这让问题更糟：名字几乎相同，含义不同，单位差 100 倍。
- 同一个 CSV 里的 `target_height_m` 用米，项目其余长度字段也都用米。

**改法**：`field/templates/capture-log.csv` 第 1 行替换为：

```
scene_id,date,local_time,timezone,site_code,indoor,glass,target_label,target_height_m,device_model,lidar,capture_seconds,abandoned,drift_observed_max_m,corridor_coverage_pct,unknown_pct,north_sources_present,north_resolved_sigma_deg,north_conflict,quality_level,false_valid_guard,holdout,rescue_minutes,operator,notes
```

### #12 【补充】只有一组且 σ > 6° 时方向灯无归属

**问题**

- `04:48` 的方向灯：
  - "警告"要求"单来源，σ ≤ 6°"。
  - "阻断"只列了"冲突或无有效来源"。
  - 只有一组且 σ > 6° 的情况，不属于任何一栏。
- `05` §6 给"单来源"亮黄灯，不看 σ。
- `05:27` 的"σ > 6° 要求确认"只写在冲突分支里。

**为什么要紧**

- 阴天室内又没有轮廓数据时，常见情况就是只剩磁罗盘（典型 σ 5–15°，`05:13`）。
- 按 `05` §6 实现会亮黄灯，并输出 R1 的小时数。
- 室内的磁干扰往往不反映在 `headingAccuracy` 里【估】。σ 偏乐观时，这就是 false-valid。

**改法**

- 并入 ADR-0009（第 6 节，规则第 5 条）。文本见 #5 中的 `05` §3 第 5 步、`05` §6 表和 `04` §6 方向灯。
- 用户做一次地图拖拽后就多出一组，流程可以继续。这与 `05` §7"10 秒内完成地图拖拽"的设计一致。

---

## 6. ADR-0009 草案（待 Lee 批准）

新建文件 `docs/decisions/ADR-0009-north-conflict-handling.md`：

```markdown
# ADR-0009 · NorthResolver 冲突与单组处理：取最大一致组合；磁罗盘单独偏离不阻断

- 状态：Proposed
- 日期：2026-09-10
- 取代 / 被取代：细化 ADR-0007 后果中"冲突时只出 R0"的适用范围

## 背景
`05-north-resolver.md` 第 3 节第 4 步规定：任两组冲突时按 `solar > vps > map > magnetic` 只保留最可信组，其余全部否决；只在最可信组只有一个来源且 σ > 6° 时要求确认。评审发现三个问题（数值为虚构示例【估】）：

1. 与最可信组一致的组也被否决。solar 1±2°、map 3±4°、磁罗盘 40±8° 时，只有磁罗盘偏离，map 也被否决。室内磁罗盘偏离是常态【估】，大量"两组以上一致"的场景会因此降级。
2. 与 05 第 6 节、04 第 6 节、ADR-0007 矛盾：后三者规定任何冲突都红灯、确认前只出 R0。照第 3 节字面实现，一个错误但 σ 小的高可信读数（solar 20±2°，对 vps 3±3°、map 2±4°）会自动胜出并输出 R1，这是 false-valid 路径。
3. 只有一组且 σ > 6° 时，04 第 6 节方向灯没有归属，05 第 6 节却给黄灯。

## 决定
方向融合取两两一致的最大组合；只有磁罗盘被否决时不阻断；否决了其他组、或只剩一组且 σ > 6° 时，红灯并要求一次最小确认，确认前只出 R0。

规则细节：
1. 一致性用圆周差：`δ_ij = min(d, 360° − d)`，`d = |Δ_i − Δ_j| mod 360`；`δ_ij > 3·sqrt(σ_i² + σ_j²)` 为冲突。
2. 在两两一致的组合中取组数最多者，做加权圆周均值；组数相同时，比较组合中最可信的组。
3. 被否决的只有 magnetic：不算冲突，冲突详情照记。
4. 否决了 magnetic 以外的组：算冲突，要求一次最小确认（指认墙面或地图拖拽），确认前只出 R0。
5. 只有一组有效且 σ > 6°：同第 4 条。

## 备选
- 保留最可信组、否决其余（现状）：丢掉一致的佐证；与 05 第 6 节矛盾。
- 以最可信组为锚，只剔除与锚冲突的组：简单，但锚本身错时会把一致的多数剔掉。
- 冲突时全部加权平均：把错误藏进平均值（ADR-0007 已否决）。

## 后果
- 改 05 第 3 节第 4–6 步与第 6 节（第 3 步的圆周差已按评审 #4 先行更正）；04 第 6 节方向灯对齐；01 第 9 节措辞不变。
- 最多 4 个产品组，枚举 15 个组合，计算成本可忽略。
- 02 第 6 节 NorthResolver 合成测试增加：磁罗盘单独偏离、高可信组单独偏离、只有一组且 σ > 6°。
- 07 第 3 节"方向源分布"把冲突触发率拆成"仅磁罗盘被否决"与"否决了其他组"两类报告；第 5 节通过线不变。
- 在 spike 开始前修订（07 状态：未开始），不属于事后放宽。
```

---

## 7. 执行顺序与逐文件清单

按项目流程，ADR 以 Proposed 状态入库就是"提出改动"；Lee 把它改为 Accepted 之后，才动蓝图与规范。

### 第一批：不需要决定，可以立即做

| 文件 | 改动 | 条目 |
|---|---|---|
| `docs/02-architecture.md` | §3 第 41–45 行整段替换；§6 加"坐标约定"行；NorthResolver 测试行加"跨 0°/360°" | #1 #2 #3 #4 |
| `docs/05-north-resolver.md` | §3 第 3 步；§4 第 32 行 | #4 #1 |
| `docs/03-scene-record.md` | §5 第 82 行 | #6 |
| `docs/04-capture-protocol.md` | §6 第 47 行 | #6 |
| `docs/13-glossary.md` | 第 41 行 | #1 |
| `field/README.md` | 第 13 行 | #10 |
| `field/templates/capture-log.csv` | 第 1 行 | #11 |
| `docs/decisions/ADR-0009-north-conflict-handling.md` | 新建，状态 Proposed（第 6 节） | #5 #12 |
| `docs/decisions/README.md` | 在 ADR-0000 行之前加：`\| [ADR-0009](ADR-0009-north-conflict-handling.md) \| NorthResolver 冲突取最大一致组合；磁罗盘单独偏离不阻断 \| Proposed \|` | #5 |

### 第二批：D2–D4 确认后

| 文件 | 改动 | 条目 |
|---|---|---|
| `docs/05-north-resolver.md` | §2 磁罗盘行、VPS 行 | #7 #9 |
| `docs/03-scene-record.md` | 第 49 行；§4 第 55–72 行整段 | #8 #7 #1 |
| `docs/04-capture-protocol.md` | 第 19 行 | #8 |
| `docs/13-glossary.md` | 第 48 行 | #9 |
| `docs/11-compliance-boundaries.md` | §5 加 ARCore 一行 | #9 |

如果第二批要等，`03` 里属于 #1 的部分可以先单独改：
- 把第 72 行换成 #7 替换块末尾那段定义。
- 删掉第 68 行，并去掉第 67 行末尾的逗号。

### 第三批：Lee 把 ADR-0009 改为 Accepted 之后

| 文件 | 改动 | 条目 |
|---|---|---|
| `docs/decisions/ADR-0009-north-conflict-handling.md` | 状态改为 Accepted | #5 #12 |
| `docs/decisions/README.md` | ADR-0009 行状态改为 Accepted | #5 |
| `docs/decisions/ADR-0007-north-resolver.md` | 在"日期"行后加：`- 取代 / 被取代：后果中"冲突时只出 R0"的适用范围由 ADR-0009 细化` | #5 |
| `docs/00-blueprint.md` | §2 第 7 行的 ADR 列改为：`[ADR-0007](decisions/ADR-0007-north-resolver.md)、[ADR-0009](decisions/ADR-0009-north-conflict-handling.md)` | #5 |
| `docs/05-north-resolver.md` | §3 第 4–6 步；§6 表 | #5 #12 |
| `docs/04-capture-protocol.md` | §6 方向灯一行 | #12 |
| `docs/02-architecture.md` | §6 NorthResolver 测试行补三类：磁罗盘单独偏离、高可信组单独偏离、只有一组且 σ > 6° | #5 #12 |
| `docs/07-spike-plan.md` | §3"方向源分布"拆成两类报告（可选） | #5 |

## 8. 收尾检查

```bash
grep -rnE "ar_to_true_north|yaw_true|yaw_ar|CheckVpsAvailability|SceneRecord\.json|drift_max_cm" docs field
```

第一、二批完成后，预期无输出。

- 重跑附录 A 的脚本，确认 `03` 新示例的数值：看 "#7 docs/03 example, sigma_mag = heading_accuracy 12" 一段，应为 359.78 / 1.77。
- 用 `git diff --stat` 核对改动范围，与第 7 节清单一致。
- commit 只在 Lee 要求时做。建议的提交信息：
  - 第一、二批：`docs: fix north and pixel-direction conventions; align cross-doc definitions`
  - ADR-0009 入库：`docs(adr): propose ADR-0009 north conflict handling`
  - 第三批：`docs: apply ADR-0009 to NorthResolver and capture gates`

---

## 附录 A · 复算脚本与输出

只用标准库，运行方式：`python3 verify_review.py`。说明两点：

- 脚本中的 "current rule" 已经采用 #4 的圆周差。若按原文直接相减，`03` 示例会被判为冲突。
- 场景 B 中，"current rule" 只列出保留与否决了哪些组。是否需要确认，要看按 05 §3 还是 §6 实现，见 #5 的表。

```python
"""Recompute the numeric claims in the docs/blueprint-v1 review (2026-09-10).

Run: python3 verify_review.py   (stdlib only)
"""
import itertools
import math

TRUST = ["solar", "vps", "map", "magnetic"]


def cdiff(a, b):
    """Circular difference in degrees, in [0, 180]."""
    d = abs(a - b) % 360
    return min(d, 360 - d)


def fuse(cands):
    """Inverse-variance weighted circular mean. cands: [(yaw_deg, sigma_deg)]."""
    w = [1 / s**2 for _, s in cands]
    x = sum(wi * math.cos(math.radians(y)) for wi, (y, _) in zip(w, cands))
    y = sum(wi * math.sin(math.radians(y)) for wi, (y, _) in zip(w, cands))
    return round(math.degrees(math.atan2(y, x)) % 360, 2), round(1 / math.sqrt(sum(w)), 2)


def conflicting_pairs(groups):
    """Group pairs whose circular difference exceeds 3*sqrt(si^2 + sj^2)."""
    return [
        (gi, gj)
        for (gi, (yi, si)), (gj, (yj, sj)) in itertools.combinations(groups.items(), 2)
        if cdiff(yi, yj) > 3 * math.sqrt(si**2 + sj**2)
    ]


def resolve_current(groups):
    """docs/05 §3 step 4 as written: any conflict keeps only the most trusted group."""
    if not conflicting_pairs(groups):
        return list(groups), [], fuse(list(groups.values()))
    top = min(groups, key=TRUST.index)
    return [top], [g for g in groups if g != top], fuse([groups[top]])


def resolve_proposed(groups):
    """Draft ADR-0009: largest pairwise-consistent subset; ties by trust order.

    Returns kept groups, rejected groups, whether it blocks (a non-magnetic
    group was rejected), and the fused (yaw, sigma).
    """
    names = list(groups)
    for k in range(len(names), 0, -1):
        ok = [s for s in itertools.combinations(names, k)
              if not conflicting_pairs({g: groups[g] for g in s})]
        if ok:
            kept = min(ok, key=lambda s: sorted(TRUST.index(g) for g in s))
            rejected = [g for g in names if g not in kept]
            blocking = any(g != "magnetic" for g in rejected)
            return list(kept), rejected, blocking, fuse([groups[g] for g in kept])


def main():
    print("== #4 circular wrap: docs/03 example, solar 359±2 vs map 2±4")
    thr = 3 * math.sqrt(2**2 + 4**2)
    print(f"  literal |359-2| = {abs(359 - 2)}   circular = {cdiff(359, 2)}   threshold = {thr:.1f}")

    print("== #1 delta sign: AR reference axis points east (true azimuth beta = 90)")
    beta = 90
    delta_by_prose = (0 - beta) % 360  # CW angle FROM reference axis TO north
    print(f"  delta per prose = {delta_by_prose}; ray along reference axis -> "
          f"az_ar + delta = {(0 + delta_by_prose) % 360}, truth = {beta}")
    for b in (0, 10, 45, 90, 180):
        print(f"  session heading beta = {b:>3} -> heading error if prose is followed = {(2 * b) % 360}")

    print("== #2 asin on the unnormalized ray (image top edge, tan 30deg = 0.577)")
    t = math.tan(math.radians(30))
    for pitch in (0, 30, 60):
        p = math.radians(pitch)
        dy = t * math.cos(p) + math.sin(p)  # z = 1 ray rotated up by pitch
        true_alt = math.degrees(math.asin(dy / math.sqrt(t * t + 1)))
        naive = "NaN" if abs(dy) > 1 else f"{math.degrees(math.asin(dy)):.1f}"
        print(f"  pitch = {pitch:>2}: d_y = {dy:.3f}   asin(d_y) = {naive:>5}   true alt = {true_alt:.1f}")

    print("== #3 atan2(d_x, d_z) in ARKit gravityAndHeading (+X east, +Y up, +Z south)")
    for name, d in {"N": (0, 0, -1), "E": (1, 0, 0), "S": (0, 0, 1), "W": (-1, 0, 0)}.items():
        a = math.degrees(math.atan2(d[0], d[2])) % 360
        b = math.degrees(math.atan2(d[0], -d[2])) % 360
        print(f"  {name}: atan2(dx, dz) = {a:5.1f}   atan2(dx, -dz) = {b:5.1f}")

    cases = {
        "#5 magnetic outlier (review example)": {"solar": (1, 2), "map": (3, 4), "magnetic": (40, 8)},
        "#5 wrong solar vs agreeing map+vps (fictional)": {"solar": (20, 2), "vps": (3, 3), "map": (2, 4)},
        "#7 docs/03 example as written (sigma_mag 8)": {"magnetic": (8, 8), "map": (2, 4), "solar": (359, 2)},
        "#7 docs/03 example, sigma_mag = heading_accuracy 12": {"magnetic": (8, 12), "map": (2, 4), "solar": (359, 2)},
    }
    for label, groups in cases.items():
        print(f"== {label}")
        for gi, gj in itertools.combinations(groups, 2):
            (yi, si), (yj, sj) = groups[gi], groups[gj]
            d, th = cdiff(yi, yj), 3 * math.sqrt(si**2 + sj**2)
            print(f"  {gi}-{gj}: diff = {d:g}   threshold = {th:.1f}   conflict = {d > th}")
        kept, rej, fused = resolve_current(groups)
        print(f"  current rule : kept = {kept}  rejected = {rej}  fused = {fused}")
        kept, rej, blocking, fused = resolve_proposed(groups)
        print(f"  proposed rule: kept = {kept}  rejected = {rej}  blocking = {blocking}  fused = {fused}")

    print("== #7 other fusion subsets of the docs/03 example (doc claims yaw 0.6, sigma 2.4)")
    print("  map + solar only :", fuse([(2, 4), (359, 2)]))


if __name__ == "__main__":
    main()
```

输出（2026-09-10 本机运行）：

```
== #4 circular wrap: docs/03 example, solar 359±2 vs map 2±4
  literal |359-2| = 357   circular = 3   threshold = 13.4
== #1 delta sign: AR reference axis points east (true azimuth beta = 90)
  delta per prose = 270; ray along reference axis -> az_ar + delta = 270, truth = 90
  session heading beta =   0 -> heading error if prose is followed = 0
  session heading beta =  10 -> heading error if prose is followed = 20
  session heading beta =  45 -> heading error if prose is followed = 90
  session heading beta =  90 -> heading error if prose is followed = 180
  session heading beta = 180 -> heading error if prose is followed = 0
== #2 asin on the unnormalized ray (image top edge, tan 30deg = 0.577)
  pitch =  0: d_y = 0.577   asin(d_y) =  35.3   true alt = 30.0
  pitch = 30: d_y = 1.000   asin(d_y) =  90.0   true alt = 60.0
  pitch = 60: d_y = 1.155   asin(d_y) =   NaN   true alt = 90.0
== #3 atan2(d_x, d_z) in ARKit gravityAndHeading (+X east, +Y up, +Z south)
  N: atan2(dx, dz) = 180.0   atan2(dx, -dz) =   0.0
  E: atan2(dx, dz) =  90.0   atan2(dx, -dz) =  90.0
  S: atan2(dx, dz) =   0.0   atan2(dx, -dz) = 180.0
  W: atan2(dx, dz) = 270.0   atan2(dx, -dz) = 270.0
== #5 magnetic outlier (review example)
  solar-map: diff = 2   threshold = 13.4   conflict = False
  solar-magnetic: diff = 39   threshold = 24.7   conflict = True
  map-magnetic: diff = 37   threshold = 26.8   conflict = True
  current rule : kept = ['solar']  rejected = ['map', 'magnetic']  fused = (1.0, 2.0)
  proposed rule: kept = ['solar', 'map']  rejected = ['magnetic']  blocking = False  fused = (1.4, 1.79)
== #5 wrong solar vs agreeing map+vps (fictional)
  solar-vps: diff = 17   threshold = 10.8   conflict = True
  solar-map: diff = 18   threshold = 13.4   conflict = True
  vps-map: diff = 1   threshold = 15.0   conflict = False
  current rule : kept = ['solar']  rejected = ['vps', 'map']  fused = (20.0, 2.0)
  proposed rule: kept = ['vps', 'map']  rejected = ['solar']  blocking = True  fused = (2.64, 2.4)
== #7 docs/03 example as written (sigma_mag 8)
  magnetic-map: diff = 6   threshold = 26.8   conflict = False
  magnetic-solar: diff = 9   threshold = 24.7   conflict = False
  map-solar: diff = 3   threshold = 13.4   conflict = False
  current rule : kept = ['magnetic', 'map', 'solar']  rejected = []  fused = (360.0, 1.75)
  proposed rule: kept = ['magnetic', 'map', 'solar']  rejected = []  blocking = False  fused = (360.0, 1.75)
== #7 docs/03 example, sigma_mag = heading_accuracy 12
  magnetic-map: diff = 6   threshold = 37.9   conflict = False
  magnetic-solar: diff = 9   threshold = 36.5   conflict = False
  map-solar: diff = 3   threshold = 13.4   conflict = False
  current rule : kept = ['magnetic', 'map', 'solar']  rejected = []  fused = (359.78, 1.77)
  proposed rule: kept = ['magnetic', 'map', 'solar']  rejected = []  blocking = False  fused = (359.78, 1.77)
== #7 other fusion subsets of the docs/03 example (doc claims yaw 0.6, sigma 2.4)
  map + solar only : (359.6, 1.79)
```

## 附录 B · 外部来源（2026-09-10 查阅）

| 来源 | 用于 | 核实内容 |
|---|---|---|
| [ARKit · gravityAndHeading](https://developer.apple.com/documentation/arkit/arconfiguration/worldalignment-swift.enum/gravityandheading) | #3 | +x 东、+y 上、+z 南；(0,0,−1) 指向真北 |
| [ARKit · gravity](https://developer.apple.com/documentation/arkit/arconfiguration/worldalignment-swift.enum/gravity) | #1 #3 | (0,0,−1) 为会话开始时相机朝向（垂直于重力）；x 按右手定则 |
| [ARCamera.transform](https://developer.apple.com/documentation/arkit/arcamera/transform) | #3 | 相机系与设备方向无关；x 沿设备长轴；y 向上；z 指向屏幕一侧 |
| [ARCamera.intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics) | #3 | fx、fy、ox、oy 以图像左上角为原点，单位像素；未写明图像方向 |
| [Displaying a point cloud using scene depth](https://developer.apple.com/documentation/ARKit/displaying-a-point-cloud-using-scene-depth) | #2 #3 | 反投影为 `(u−cx)·depth/fx, (v−cy)·depth/fy, depth`；flipYZ 出自示例代码（经搜索结果摘要确认） |
| [ARGeoTrackingConfiguration](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration) | #9 | 覆盖"澳洲多个大都市区"，未点名城市，需运行时查询 |
| [ARGeoTrackingConfiguration.checkAvailability](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration/checkavailability(completionhandler:)) | #9 | 签名；有 `checkAvailability(at:)` 按坐标查询 |
| [ARCore iOS · Check VPS availability](https://developers.google.com/ar/develop/ios/geospatial/check-vps-availability) | #9 | `GARSession checkVPSAvailabilityAtCoordinate:completionHandler:`；需启用 ARCore API |
