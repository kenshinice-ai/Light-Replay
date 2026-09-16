# engine/

Python 参考实现与验证脚本。**目前为空**。用途：

1. **参考实现**：SunEngine（pvlib / astronomy-engine）、可见域累积、NorthResolver 融合的可读版本，作为 Swift 实现的对照。
2. **交叉核对**：同一份 SceneRecord JSON 输入，比较 Swift 与 Python 的时段输出，差异写入容差报告。
3. **真值分析**：读取 `field/` 的延时标注与采集日志，计算 `docs/07-spike-plan.md` 定义的指标（误差分布、false-valid、时长分布）。
4. **地址级粗估（V1.5 起）**：G-NAF + Geoscape / Overture + DEM 的地平线剖面。

## 计划结构

```
engine/
├── pyproject.toml
├── lightreplay/
│   ├── sun.py            太阳位置、走廊、时段分级
│   ├── visibility.py     可见域网格、状态合并、深度重投影
│   ├── north.py          方向融合与冲突检测
│   ├── scenerecord.py    JSON schema 校验（与 docs/03 同步）
│   └── metrics.py        spike 指标
└── scripts/
    ├── crosscheck.py     Swift vs Python
    └── timelapse_label.py 延时标注辅助
```

Python 3.12+。依赖：numpy、pvlib、astronomy-engine（择一为主）、pydantic（schema）。
