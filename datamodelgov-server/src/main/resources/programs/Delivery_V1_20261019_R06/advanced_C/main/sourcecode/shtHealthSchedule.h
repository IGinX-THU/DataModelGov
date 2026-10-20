#ifndef SHT_HEALTH_SCHEDULE_H
#define SHT_HEALTH_SCHEDULE_H

/*
 * 三部件/六部件稳态修正系数的一维增量调度表。
 *
 * stepIn 继续传递设计点值 k_des；本模块保存 MATLAB 在初始化阶段
 * 一次写入的 Delta_i 节点。所有参数共用同一套分段线性插值，运行时
 * 由发动机模型计算 K_eff = k_des + Delta(x)。压损的零流量约束也只
 * 通过 Delta_0 = -k_des 表达，不在本模块增加专用门控或插值分支。
 */

#define SHT_HEALTH_SCHEDULE_HEALTH_COUNT 159
#define SHT_HEALTH_SCHEDULE_ORIGINAL_TABLES 13
#define SHT_HEALTH_SCHEDULE_SPLIT_TABLES 31
#define SHT_HEALTH_SCHEDULE_MAX_TABLES SHT_HEALTH_SCHEDULE_SPLIT_TABLES
/*
 * DLL接受估计程序保留下来的有效节点，不再要求固定6/7节点。
 * 32是接口容量上限而不是默认节点数；超过上限必须由上层明确报错，
 * 禁止静默重采样，以免改变已经辨识得到的分段线性曲线。
 */
#define SHT_HEALTH_SCHEDULE_MAX_NODES 32

enum SHTHealthScheduleAxis
{
	SHT_HEALTH_AXIS_NONE = 0,
	SHT_HEALTH_AXIS_INLET_CORRECTED_FLOW = 1,
	SHT_HEALTH_AXIS_BURNER_CORRECTED_FLOW = 2,
	SHT_HEALTH_AXIS_GT_PT_DUCT_CORRECTED_FLOW = 3,
	SHT_HEALTH_AXIS_PT_NOZZLE_DUCT_CORRECTED_FLOW = 4,
	SHT_HEALTH_AXIS_AC_CORRECTED_SPEED = 5,
	SHT_HEALTH_AXIS_CC_CORRECTED_SPEED = 6,
	SHT_HEALTH_AXIS_GT_TOTAL_PRESSURE_RATIO = 7,
	SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO = 8
};

typedef struct SHTHealthScheduleTable
{
	int configured;
	int healthIndex;
	int axisType;
	int nodeCount;
	double xNode[SHT_HEALTH_SCHEDULE_MAX_NODES];
	double deltaNode[SHT_HEALTH_SCHEDULE_MAX_NODES];
} SHTHealthScheduleTable;

typedef struct SHTHealthScheduleSystem
{
	int enabled;
	int configuredCount;
	SHTHealthScheduleTable table[SHT_HEALTH_SCHEDULE_HEALTH_COUNT];
} SHTHealthScheduleSystem;

void shtHealthScheduleReset(SHTHealthScheduleSystem *system);
int shtHealthScheduleSetEnabled(SHTHealthScheduleSystem *system, int enabled);
int shtHealthScheduleConfigureTable(
	SHTHealthScheduleSystem *system,
	int healthIndex,
	int axisType,
	int nodeCount,
	const double *xNode,
	const double *deltaNode);
int shtHealthScheduleIsConfigured(
	const SHTHealthScheduleSystem *system,
	int healthIndex);
int shtHealthScheduleEvaluateIncrement(
	const SHTHealthScheduleSystem *system,
	int healthIndex,
	double coordinate,
	double *incrementValue);

#endif
