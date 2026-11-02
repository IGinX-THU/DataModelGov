# 三部件发动机 C 程序基线

本目录保留 `m_program_adaptive_V1` 当时使用的三部件发动机 C/DLL 完整基线，仅用于历史复现、回归对比和应急恢复，不作为第二轮六部件开发的源码目录。

- 恢复来源：`Report/05_程序/备份/2.1六部件拆分第二轮开发/baseline_20260816_013729/涡轴发动机总体性能仿真C程序`
- 恢复日期：2026-08-17
- `x64/Release/GTESS.dll` SHA-256：`29A8C435ED37E4C51B5399F1FFEA921C5D8F12EE2D1B28FDDA5E02C8D112DDDD`
- 基线特征：仅包含 HPC、GT、PT 三个总体旋转部件，不包含 `modelMode`、`HPC2`、`HPT2`、`LPT2` 六部件扩展。

使用时应将本目录视为独立工程，不要把其中的头文件或 DLL 与当前 `m_program_adaptive_tune` 混用。
