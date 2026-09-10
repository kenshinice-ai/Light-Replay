# 03 · SceneRecord 数据规范

版本 0.1.0 · 2026-09-10 · Swift 包 `SceneRecord` 与 `engine/lightreplay/scenerecord.py` 以此为准

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
           "algorithms": { "sun": "sunengine-0.1", "segmentation": "skyseg-0.1", "north": "northresolver-0.1", "visibility": "viscore-0.1" } },
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
| `frames[]` | array | 每帧：`frame_id`、`t`、`camera_transform`、`intrinsics`、`tracking_state`（`normal` / `limited:<reason>` / `not_available`）、`lens_offset_m`（与锚点距离）、`depth_ref`、`depth_confidence_ref`、`mask_ref`、`exposure_offset`、`used_for_visibility` |
| `viewpoint_lock` | object | `anchor_world`、`tolerance_m`、`max_drift_m`、`frames_within`、`frames_beyond`、`handling`（`depth_recentered` / `tolerated` / `rejected`）|
| `guidance` | object | `question`（`winter_breakfast` / `full_year` / `custom`）、`corridor_ref` |

帧记录频率：姿态每帧；掩膜与深度按分割频率（5–10 fps）；其余帧 `mask_ref: null`。

## 4. north

```json
{
  "candidates": [
    { "source": "magnetometer", "group": "magnetic", "yaw_deg": 8.0, "sigma_deg": 8.0, "valid": true,
      "raw": { "true_heading": 8.2, "magnetic_heading": 19.9, "heading_accuracy": 12.0, "sampled_at": "..." } },
    { "source": "wall_footprint", "group": "map", "yaw_deg": 2.0, "sigma_deg": 4.0, "valid": true,
      "plane_anchor_id": "…", "footprint": { "dataset": "overture", "feature_id": "…", "edge_bearing_deg": 12.5, "user_selected_edge": true } },
    { "source": "window_patch", "group": "solar", "yaw_deg": 359.0, "sigma_deg": 2.0, "valid": true, "evidence_frame": "…" },
    { "source": "sun_disk", "group": "solar", "yaw_deg": null, "sigma_deg": null, "valid": false, "reason": "sun not visible" },
    { "source": "geo_tracking", "group": "vps", "yaw_deg": null, "sigma_deg": null, "valid": false, "reason": "unavailable" }
  ],
  "resolved": { "yaw_deg": 0.6, "sigma_deg": 2.4, "method": "robust_circular_v0", "groups_used": ["map","solar"],
                "conflict": false, "conflict_detail": null, "resolved_at": "…" },
  "ar_to_true_north_yaw_deg": 0.6
}
```

`yaw_deg` 定义：AR 世界 +Z 轴（或约定的参考轴）到真北的顺时针角，见 `05-north-resolver.md`。

## 5. visibility

| 字段 | 说明 |
|---|---|
| `grid` | `az_step_deg: 1`, `alt_step_deg: 1`, `az_frame: "ar_world"`, `alt_range: [-10, 90]` |
| `states_ref` | 二进制或 PNG，360 × 100 个单元，值：0 未知、1 天空、2 遮挡、3 玻璃不确定 |
| `confidence_ref` | 同尺寸，0–255 |
| `votes` | 每态投票数摘要 |
| `coverage` | `corridor_cells`、`covered_cells`、`unknown_cells`、`glass_cells`、`coverage_pct` |
| `segmentation` | `model`、`glass_detected`、`reflection_flags[]`、`manual_edits` |
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
{ "level": "R1", "gates": { "level": "pass", "coverage": "pass", "north": "pass", "segmentation": "warn" },
  "flags": ["glass_present", "drift_recentered"], "false_valid_guard": "passed", "blocked_reason": null }
```

`false_valid_guard` 为 `blocked` 时，`analysis` 不得含小时数。

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
