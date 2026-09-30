# engine/

Python 参考实现与验证脚本。

## 现有

| 路径 | 内容 |
|---|---|
| `lightreplay/scenerecord.py` | SceneRecord 0.1.0 严格校验（重复键、非有限数、时间戳与偏移、IANA 时区、相对路径、R0 / blocked 记录不得含分析、analysis-ready 记录的证据要求）；`loads` / `dumps` / CLI |
| `tests/test_scenerecord.py` | 30 个 unittest：合成 R0 与 R1 记录、对抗性变异、与 Swift CLI 的跨语言一致性 |
| `tests/fixtures/scene-r0.json` | 合成 R0 示例（全部虚构，坐标为任意测试输入） |
| `lightreplay/sun.py` | 太阳位置参考：NOAA（Meeus）算法 + SPA 折射，与 Swift `SunEngine` 逐项一致；另含独立的天文年历算法（Michalsky 1988）只作交叉校验 |
| `scripts/make_sun_fixture.py` → `tests/fixtures/sun-positions.json` | 768 个合成输入点（6 城 × 全年 × 每 3 小时）；Swift 测试读它，容差 1e-7° |
| `tests/test_sun.py` | NREL SPA 公开算例、冬夏至正午高度、独立算法 < 0.05°、fixture 是否最新、折射与方位约定 |

## 跑

```bash
./scripts/test.sh
# 或只跑 Python（需先构建 Swift CLI 到 iCloud 之外）：
cd engine && SCENE_RECORD_CHECK=~/Library/Caches/propertyreplay/SceneRecord-build/debug/scene-record-check python3 -m unittest discover -s tests
```

Python 3.12+，标准库即可。SunEngine 的精度对照不依赖第三方包：NREL SPA 论文算例（绝对值）、独立的天文年历算法（全年南北半球最大差 0.011°）、Python 与 Swift 逐位一致。pvlib 不再是必需项。

## 计划

```
engine/
├── lightreplay/
│   ├── scenerecord.py    已有
│   ├── sun.py            太阳位置（已有）；走廊与时段分级的 Python 对照待补
│   ├── visibility.py     可见域网格、状态合并、深度重投影
│   ├── north.py          方向融合与冲突检测（ADR-0009；docs/reviews 的 verify_review.py 是起点）
│   └── metrics.py        spike 指标（误差分布、false-valid、时长、救场分钟）
└── scripts/
    ├── crosscheck.py     Swift vs Python 同输入对照
    └── timelapse_label.py 延时标注辅助
```
