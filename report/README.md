# report/

分享页与 Light Passport 的网页端。**目前为空**。

- 技术：Next.js（静态导出优先），只读渲染 SceneRecord 的 AnalysisResult 与 provenance；不做采集，不做计算。
- 首版页面：单个目标点的结果页（照片、时段条、全年热力图、证据卡、未知区域）；两点比较页；Light Passport 页（`docs/09-light-passport.md`）。
- 隐私：默认不含原片、精确门牌、EXIF；链接可撤销；更正后旧链接指向更正状态。
- 进入条件：Spike 通过后，与 V1 结果页同步设计。
