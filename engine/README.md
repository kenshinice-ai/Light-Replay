# engine/

Python 参考实现与验证脚本。

## 现有

| 路径 | 内容 |
|---|---|
| `lightreplay/scenerecord.py` | SceneRecord 0.1.0 严格校验（重复键、非有限数、时间戳与偏移、IANA 时区、相对路径、R0 / blocked 记录不得含分析、analysis-ready 记录的证据要求）；`loads` / `dumps` / CLI |
| `tests/test_scenerecord.py` | 30 个 unittest：合成 R0 与 R1 记录、对抗性变异、与 Swift CLI 的跨语言一致性 |
| `tests/fixtures/scene-r0.json` | 合成 R0 示例（全部虚构，坐标为任意测试输入） |

## 跑

```bash
./scripts/test.sh
# 或只跑 Python（需先构建 Swift CLI 到 iCloud 之外）：
cd engine && SCENE_RECORD_CHECK=~/Library/Caches/propertyreplay/SceneRecord-build/debug/scene-record-check python3 -m unittest discover -s tests
```

Python 3.12+，标准库即可；pvlib 0.15.2（BSD-3-Clause，已登记）只在 SunEngine 对照时安装。

## 计划

```
engine/
├── lightreplay/
│   ├── scenerecord.py    已有
│   ├── sun.py            太阳位置、走廊、时段分级（对照 Swift SunEngine）
│   ├── visibility.py     可见域网格、状态合并、深度重投影
│   ├── north.py          方向融合与冲突检测（ADR-0009；docs/reviews 的 verify_review.py 是起点）
│   └── metrics.py        spike 指标（误差分布、false-valid、时长、救场分钟）
└── scripts/
    ├── crosscheck.py     Swift vs Python 同输入对照
    └── timelapse_label.py 延时标注辅助
```
