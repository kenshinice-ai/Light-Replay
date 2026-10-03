# 03 · SceneRecord 数据规范

版本 0.1.0 · 2026-09-10 · Swift 包 `ios/Packages/SceneRecord` 与 `engine/lightreplay/scenerecord.py` 以此为准

定位：SceneRecord 是 Property 图中 LightObservation 的载荷（ADR-0012，`15-product-model.md`）。一个 TargetPoint 一份；Property 图只引用 `scene_id`。R 等级与时段四态对外映射为证据五级（ADR-0013），映射只在展示层做，不写回本文件。

## 1. 原则

- 分清 **传感器测得 / 算法估计 / AI 候选 / 用户确认 / 外部数据**，每个字段有 `source`。
- 无法取得的字段记 `null`，不造默认值。
- 原片与衍生结果分离；引用用相对路径。
- 所有时间为 ISO 8601 带偏移；另存 IANA 时区名。
- 用户修正保留版本，触发重算。

## 2. 顶层结构

```json
{
  "schema_version": "0.1.0",
  "scene_id": "LR-20260921-03",
  "created_at": "2026-09-21T10:42:13+10:00",
  "timezone": "Australia/Melbourne",
  "app": { "version": "0.1.0", "build": "12",
           "algorithms": { "sun": "sunengine-0.1", "segmentation": "skyseg-0.1", "north": "northresolver-0.2", "visibility": "viscore-0.1" } },
  "device": { "model": "iPhone16,1", "os": "iOS 18.6", "lidar": true, "scene_depth": true, "geo_tracking": "unavailable" },
  "location": { "lat": -37.8136, "lon": 144.9631, "alt_m": 31.0, "h_acc_m": 8.0, "v_acc_m": 5.0,
                "source": "core_location", "captured_at": "2026-09-21T10:41:58+10:00" },
  "target": { "target_id": "T1", "label": "客厅沙发位", "height_m": 1.15,
              "anchor_world": [0.0, 1.15, 0.0], "confirmed_by": "user", "notes": null },
  "capture_session": { "...": "见第 3 节" },
  "north": { "...": "见第 4 节" },
  "visibility": { "...": "见第 5 节" },
  "geometry": { "...": "见第 6 节，V2" },
  "analysis": [ { "...": "见第 7 节" } ],
  "quality": { "...": "见第 8 节" },
  "sharing": { "include_hero": false, "precise_address": false, "revoked": false, "revoked_at": null },
  "context": { "address_estimate": null }
}
```

## 3. capture_session

| 字段 | 类型 | 说明 |
|---|---|---|
| `session_id` | string | ARSession 会话 |
| `started_at`, `ended_at` | datetime | |
| `world_alignment` | enum | `gravity`（推荐）或 `gravityAndHeading`；后者的 yaw 只是磁来源候选，不作真北 |
| `hero_frame` | object | `frame_id`、`image_ref`、`timestamp`、`intrinsics`、`camera_transform`（16 个数，列主序）、`exposure` |
| `frames[]` | array | 每帧：`frame_id`、`t`（自首帧起的秒数，来自 ARFrame 时间戳，≤ `ended_at − started_at`）、`camera_transform`、`intrinsics`、`tracking_state`（`normal` / `limited:<reason>` / `not_available`）、`lens_offset_m`（与锚点距离；锚点锁定前为 null）、`depth_ref`、`depth_confidence_ref`、`mask_ref`、`exposure_offset`、`used_for_visibility` |
| `viewpoint_lock` | object | `anchor_world`、`tolerance_m`、`max_drift_m`、`frames_within`、`frames_beyond`、`handling`（`depth_recentered` / `tolerated` / `rejected`）|
| `guidance` | object | `question`（`winter_breakfast` / `full_year` / `west_afternoon` / `custom`）、`corridor_ref` |

帧记录频率：姿态每帧；掩膜与深度按分割频率（5–10 fps）；其余帧 `mask_ref: null`。

## 4. north

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

`magnetometer` 候选的 `raw` 另有两项（review R08）：`samples[]` 保留本次采集里每一条能与姿态对上的罗盘读数（`sampled_at`、`true_heading`、`magnetic_heading`、`heading_accuracy`、`device_orientation`（读数参考的设备方向，`headingOrientation`）、对上的 `frame_id`、`camera_az_ar_deg`、`camera_pitch_deg`、`pose_gap_s`、该条读数给出的 `yaw_deg`、是否参与合并 `used`），`merged` 记合并方法与统计（`method`、`readings_seen` 收到的全部读数、`readings_valid` 其中有效的、`samples_total` 能与姿态对上的、`samples_used` 参与合并的、`spread_deg`、`prior_sigma_deg`、`max_pitch_deg`）。候选的 `yaw_deg` 是参与合并读数的圆周中位数，`sigma_deg` 取读数 σ 的中位数与读数分散（RMS）的较大者；`raw` 顶层的四个字段仍是第一条参与合并的读数。

`resolved` 只在方向灯不是阻断时写入；需要确认的方向（冲突、或只有一组且 σ > 6°）保持 `null`。

`yaw_deg` 即 `Δ`：AR 世界 −Z 轴的真方位角（俯视顺时针），`az_true = (az_ar + Δ) mod 360`，见 `05-north-resolver.md` 第 4 节。示例中 solar 取 359°，刻意跨 0°/360°：实现必须用圆周运算，否则会误判冲突。三组两两一致，全部参与加权圆周均值（磁罗盘 σ 取 `heading_accuracy` 12.0，结果 359.78° / σ 1.77，四舍五入见上）。

## 5. visibility

| 字段 | 说明 |
|---|---|
| `grid` | `az_step_deg: 1`, `alt_step_deg: 1`, `az_frame: "ar_world"`, `alt_range: [-10, 90]` |
| `states_ref` | 二进制或 PNG，360 × 100 个单元，值：0 未知、1 天空、2 遮挡、3 玻璃不确定 |
| `confidence_ref` | 同尺寸，0–255 |
| `votes` | 每态投票数摘要 |
| `coverage` | `corridor_cells`（走廊单元数，走廊定义见 `06-sun-engine.md` 第 5 节）、`unknown_cells`（状态 0）、`glass_cells`（状态 3）、`covered_cells = corridor_cells − unknown_cells`、`coverage_pct = covered_cells / corridor_cells`。玻璃不确定计入覆盖，另由分割灯约束（`04-capture-protocol.md` 第 6 节） |
| `segmentation` | `model`（`vision-iterative` / `coreai-custom` / `manual`）、`assets_state`、`seed_strategy`、`glass_detected`、`reflection_flags[]`（来源 `heuristic` / `fm-keyframe`）、`manual_edits` |
| `near_field` | `d_near_m`、`recentered_cells`、`source: "lidar"` |

## 6. geometry（V2）

`windows[]`（`id`、`corners_world[4]`、`source: roomplan|manual`）、`planes[]`（`id`、`normal`、`point`、`extent`、`source`）、`level: "R1_only" | "R2_available"`。

## 7. analysis[]

| 字段 | 说明 |
|---|---|
| `query` | `date_from`、`date_to`、`time_window`、`scenario`（`current`）|
| `bands` | 按日期：`[ { "date": "2026-06-21", "segments": [ { "from": "10:40", "to": "11:00", "state": "sensitive" }, { "from": "11:00", "to": "14:10", "state": "direct" } ] } ]` |
| `heatmap_ref` | 日 × 小时 四态 |
| `attribution[]` | 遮挡归因：`{ "from": "14:10", "to": "sunset", "cause": "blocked_west", "az_range": [250, 290], "alt_range": [0, 25] }` |
| `uncertainty` | `yaw_sigma_deg`、`samples`、`boundary_jitter_deg` |
| `versions` | 各算法版本；`inputs_hash` |
| `computed_at` | |

## 8. quality

```json
{ "level": "R1", "gates": { "level": "pass", "coverage": "pass", "north": "pass", "segmentation": "warn", "lens": "pass" },
  "flags": ["glass_present", "drift_recentered"], "false_valid_guard": "passed", "blocked_reason": null,
  "assist": { "coach": "fm-ondevice", "copy": "fm-ondevice", "glass_flag": "fm-keyframe", "pcc_used": false, "degraded": [] } }
```

`false_valid_guard` 为 `blocked` 时，`analysis` 不得含小时数。`gates` 含五盏灯：`level`、`coverage`、`north`、`segmentation`、`lens`。其中 `coverage`、`north`、`segmentation` 三盏由校验器按记录里的证据重算（QualityEvaluator，规则见 `04-capture-protocol.md` 第 6 节），写入值必须与重算结果一致，R0 记录也一样；`north.resolved` 若存在，必须是候选融合得到的那个结果（允许一位小数的舍入）。高于 R0 的记录另须物理自洽：目标锚点与视点锁定锚点是同一点，并入可见域的帧追踪正常且在漂移上限内。`assist.degraded` 记录每次降级（如 `fm_unavailable`、`seg_assets_missing`、`pcc_quota`），见 ADR-0010。

## 9. 文件布局

```
<scene_id>/
├── scene.json
├── hero.heic
├── masks/<frame_id>.png
├── depth/<frame_id>.bin  (+ .conf)
├── visibility/states.png, confidence.png
└── analysis/<n>-heatmap.png
```

## 10. 版本迁移

`schema_version` 语义化；破坏性变更写迁移脚本并在 `engine/` 保留旧版校验。
