# field/

现场采集与真值记录。**数据本身不入库**（见根目录 `.gitignore`），这里只放模板与索引。

```
field/
├── README.md
├── templates/
│   ├── capture-log.csv        每次 OneTake 一行
│   ├── timelapse-log.csv      每个延时事件一行（阳光进入/离开目标）
│   └── consent-checklist.md   采集授权清单
└── data/                      本机数据（gitignored）
    └── <scene_id>/            scene.json（见 docs/03 第 9 节）、hero.heic、masks/、depth/、visibility/、analysis/、timelapse/
```

规则：

- 场景编号 `LR-YYYYMMDD-NN`，与 SceneRecord 的 `scene_id` 一一对应。
- 每个场景在采集前决定是否属于 **holdout**（`capture-log.csv` 的 `holdout` 列）。holdout 场景的任何数据不得用于调参。
- 延时记录按 `docs/08-ground-truth-protocol.md` 执行；没有白卡的延时不算真值。
- 不记录人、门牌、室内物品；只记录目标点、窗与天空。
