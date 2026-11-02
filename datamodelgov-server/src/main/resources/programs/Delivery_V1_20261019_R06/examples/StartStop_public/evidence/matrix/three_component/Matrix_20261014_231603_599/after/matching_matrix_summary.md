# matrix 低速共同工作矩阵摘要

- 生成时间：2026-10-14 23:16:11
- 总体结果：**PASS**
- 适用点/通过点/失败点：9 / 9 / 0
- 不收敛点：0
- 物理无效点：0
- 轻微或明显图外点：0（只作风险记录）
- 瞬态接口诊断错误点：0；错误码：zeros(1,0)
- 最大残差RMSE：9.431145e-08
- 最大尺度化Jacobian条件数：4.057689e+01
- 累计秩亏/边界命中：0 / 0

- AttemptCount为实际候选初猜尝试数，BestSeedIndex为最佳初猜序号；均非内部函数评估次数。
- 底层RMS精度：1.000000e-07；矩阵RMS/最大残差限值：1.000000e-06 / 1.000000e-05。

|工况|Np分支|能量状态|Ng%|Np%|状态|求解器码|模型错误码|RMSE|最大残差|秩|条件数|最小图裕度|尝试数|最佳初猜|未通过原因|
|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
|lagging__no_fuel__Ng065.0|lagging|no_fuel|65.0|39.0|PASS|0|0|5.122e-08|1.024e-07|4|4.058e+01|1.017e-01|1|1||
|lagging__no_fuel__Ng030.0|lagging|no_fuel|30.0|18.0|PASS|0|0|9.431e-08|1.886e-07|4|8.723e+00|7.834e-02|1|1||
|lagging__no_fuel__Ng020.0|lagging|no_fuel|20.0|12.0|PASS|0|0|8.493e-08|1.699e-07|4|3.777e+00|7.421e-02|1|1||
|lagging__pre_ignition__Ng065.0|lagging|pre_ignition|65.0|39.0|PASS|0|0|5.122e-08|1.024e-07|4|4.058e+01|1.017e-01|1|1||
|lagging__pre_ignition__Ng030.0|lagging|pre_ignition|30.0|18.0|PASS|0|0|9.431e-08|1.886e-07|4|8.723e+00|7.834e-02|1|1||
|lagging__pre_ignition__Ng020.0|lagging|pre_ignition|20.0|12.0|PASS|0|0|8.493e-08|1.699e-07|4|3.777e+00|7.421e-02|1|1||
|lagging__fired_low_fuel__Ng065.0|lagging|fired_low_fuel|65.0|39.0|PASS|0|0|2.780e-10|5.444e-10|4|3.606e+00|2.157e-01|1|1||
|lagging__fired_low_fuel__Ng030.0|lagging|fired_low_fuel|30.0|18.0|PASS|0|0|4.947e-09|9.894e-09|4|2.380e+00|1.366e-01|1|1||
|lagging__fired_low_fuel__Ng020.0|lagging|fired_low_fuel|20.0|12.0|PASS|0|0|1.408e-09|2.564e-09|4|1.982e+00|9.328e-02|1|1||
