#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include "engineTurboshaft.h"
#include "functions_TMATS.h"
#include "newtonSolver.h"
#include "constants_TMATS.h"
#include "shtHealthSchedule.h"
#include "shtLowSpeedSolver.h"
#include "shtStartStop.h"

EngineTurboshaft Turboshaft;

/*
 * 起停增强求解仅由专用入口临时打开。三/六部件的普通入口及设计点程序
 * 均保持0，从而不改变已有残差定义和Newton路径。
 */
static int SHT_LowSpeedResidualScalingActive = 0;
static double SHT_LowSpeedFlowReference = 0.05;
static double SHT_LowSpeedZeroHoldRpm = 0.5;
static double SHT_LowSpeedACPathMaximum = 1.5;
static double SHT_LowSpeedCCPathMaximum = 1.5;
static double SHT_LowSpeedNozzleFlowBlendPressureRatio = 0.002;
static double SHT_LowSpeedShutdownAccuracyRequired = 1.0e-4;
static SHTLowSpeedSolverOptions SHT_LowSpeedOptions;
static SHTLowSpeedSolverDiagnostics SHT_LowSpeedDiagnostics;
static int SHT_LowSpeedOptionsInitialized = 0;

/* 只复位求值期临时开关，不改变起停物理配置或调用方积分状态。 */
static void SHT_ResetStartStopEvaluationScope(void)
{
    SHT_LowSpeedResidualScalingActive = 0;
    shtStartStopSetTorqueRegularizationEnabled(0);
    SHT_SetZeroFlowHeatEvaluationEnabled(0);
}

#define SHT_REYNOLDS_CONFIG_VERSION 1
#define SHT_REYNOLDS_COMPONENT_COUNT 6
#define SHT_REYNOLDS_PARAMETER_COUNT 43

enum
{
	SHT_REYNOLDS_AC = 0,
	SHT_REYNOLDS_CC = 1,
	SHT_REYNOLDS_GT1 = 2,
	SHT_REYNOLDS_GT2 = 3,
	SHT_REYNOLDS_PT1 = 4,
	SHT_REYNOLDS_PT2 = 5
};

typedef struct SHTReynoldsComponentConfiguration
{
	int enabled;
	double designTemperature;
	double designPressure;
	double lowIndex;
	double lowEfficiencyFactor;
	double highIndex;
	double highEfficiencyFactor;
} SHTReynoldsComponentConfiguration;

typedef struct SHTReynoldsCorrectionConfiguration
{
	int configured;
	double flowLossFraction;
	SHTReynoldsComponentConfiguration
		component[SHT_REYNOLDS_COMPONENT_COUNT];
} SHTReynoldsCorrectionConfiguration;

/*
 * 排气背压和雷诺数配置均独立于 EngineTurboshaft 公共结构体，避免改变
 * MATLAB loadlibrary 使用的 ABI。每次 DLL 初始化都会恢复为历史关闭态。
 */
static double SHT_NozzleBackPressure = 101325.0;
static int SHT_ExplicitNozzleBackPressure = 0;
static SHTReynoldsCorrectionConfiguration SHT_ReynoldsCorrection;

/* 私有运行状态不改变公共结构体ABI。与现有单发动机DLL实例同寿命。 */
static int SHT_ShaftLoadMode = SHT_SHAFT_LOAD_POWER;
static double SHT_PTLoadTorque = 0.0;
static double SHT_GTLoadTorque = 0.0;

static void SHT_ResetShaftLoad(void)
{
	SHT_ShaftLoadMode = SHT_SHAFT_LOAD_POWER;
	SHT_PTLoadTorque = 0.0;
	SHT_GTLoadTorque = 0.0;
}

static int SHT_ReadShaftLoad(const double *stepIn)
{
	double mode = stepIn[SHT_SHAFT_LOAD_MODE_INDEX];
	SHT_ResetShaftLoad();
	if ((mode != SHT_SHAFT_LOAD_POWER && mode != SHT_SHAFT_LOAD_TORQUE) ||
		!_finite(stepIn[SHT_PT_LOAD_INPUT_INDEX]) ||
		!_finite(stepIn[SHT_GT_LOAD_INPUT_INDEX]))
		return SHT_ERROR_PARAMETER_VALUE;
	SHT_ShaftLoadMode = (int)mode;
	if (SHT_ShaftLoadMode == SHT_SHAFT_LOAD_TORQUE)
	{
		SHT_PTLoadTorque = stepIn[SHT_PT_LOAD_INPUT_INDEX];
		SHT_GTLoadTorque = stepIn[SHT_GT_LOAD_INPUT_INDEX];
	}
	else
	{
		Turboshaft.LPS_Power = stepIn[SHT_PT_LOAD_INPUT_INDEX];
		Turboshaft.HPS_Power = stepIn[SHT_GT_LOAD_INPUT_INDEX];
	}
	return SHT_STATUS_OK;
}

static void SHT_UpdateShaftLoadPower(void)
{
	/* 必须在每次共同工作求值写入候选转速后更新，包括Newton差分。
	 * 保留原shaftRun、机械效率和惯量模型，仅替换外部负载边界。
	 */
	if (SHT_ShaftLoadMode == SHT_SHAFT_LOAD_TORQUE)
	{
		Turboshaft.LPS_Power = SHT_PTLoadTorque * Turboshaft.LPS_Nmech * PI / 30.0;
		Turboshaft.HPS_Power = SHT_GTLoadTorque * Turboshaft.HPS_Nmech * PI / 30.0;
	}
}

static void SHT_ResetReynoldsCorrection(void)
{
	memset(&SHT_ReynoldsCorrection, 0, sizeof(SHT_ReynoldsCorrection));
}

static double SHT_AirDynamicViscosity(double temperature)
{
	/* 与现有干空气物性口径一致的 Sutherland 低阶近似，单位 Pa*s。 */
	return 1.5105e-6 * pow(temperature, 1.5) / (temperature + 120.0);
}

static double SHT_ReynoldsMapFactor(
	double reynoldsIndex,
	const SHTReynoldsComponentConfiguration *configuration)
{
	double interpolationCoordinate;
	if (reynoldsIndex <= configuration->lowIndex)
		return configuration->lowEfficiencyFactor;
	if (reynoldsIndex >= configuration->highIndex)
		return configuration->highEfficiencyFactor;
	interpolationCoordinate = log(reynoldsIndex / configuration->lowIndex) /
		log(configuration->highIndex / configuration->lowIndex);
	return configuration->lowEfficiencyFactor + interpolationCoordinate *
		(configuration->highEfficiencyFactor -
		 configuration->lowEfficiencyFactor);
}

static int SHT_EvaluateReynoldsCorrection(
	int componentIndex,
	double totalTemperature,
	double totalPressure,
	double *flowMultiplier,
	double *efficiencyMultiplier)
{
	const SHTReynoldsComponentConfiguration *configuration;
	double currentViscosity;
	double designViscosity;
	double reynoldsIndex;
	double designIndex;
	double currentEfficiencyFactor;
	double designEfficiencyFactor;
	double currentFlowFactor;
	double designFlowFactor;

	if (flowMultiplier == NULL || efficiencyMultiplier == NULL)
		return SHT_ERROR_NULL_POINTER;
	*flowMultiplier = 1.0;
	*efficiencyMultiplier = 1.0;
	if (!SHT_ReynoldsCorrection.configured ||
		componentIndex < 0 || componentIndex >= SHT_REYNOLDS_COMPONENT_COUNT)
		return SHT_STATUS_OK;
	configuration = &SHT_ReynoldsCorrection.component[componentIndex];
	if (!configuration->enabled)
		return SHT_STATUS_OK;
	if (!_finite(totalTemperature) || totalTemperature <= 0.0 ||
		!_finite(totalPressure) || totalPressure <= 0.0)
		return SHT_ERROR_PARAMETER_VALUE;

	currentViscosity = SHT_AirDynamicViscosity(totalTemperature);
	designViscosity = SHT_AirDynamicViscosity(
		configuration->designTemperature);
	reynoldsIndex = totalPressure / configuration->designPressure *
		sqrt(configuration->designTemperature / totalTemperature) *
		designViscosity / currentViscosity;
	designIndex = 1.0;
	currentEfficiencyFactor = SHT_ReynoldsMapFactor(
		reynoldsIndex, configuration);
	designEfficiencyFactor = SHT_ReynoldsMapFactor(
		designIndex, configuration);
	currentFlowFactor = 1.0 - SHT_ReynoldsCorrection.flowLossFraction *
		(1.0 - currentEfficiencyFactor);
	designFlowFactor = 1.0 - SHT_ReynoldsCorrection.flowLossFraction *
		(1.0 - designEfficiencyFactor);
	if (!_finite(currentEfficiencyFactor) ||
		!_finite(designEfficiencyFactor) || designEfficiencyFactor <= 0.0 ||
		!_finite(currentFlowFactor) || !_finite(designFlowFactor) ||
		designFlowFactor <= 0.0)
		return SHT_ERROR_PARAMETER_VALUE;
	*efficiencyMultiplier = currentEfficiencyFactor /
		designEfficiencyFactor;
	*flowMultiplier = currentFlowFactor / designFlowFactor;
	return SHT_STATUS_OK;
}

#define SHT_HEAT_FEEDBACK_MAX_ITERATIONS 50
#define SHT_HEAT_FEEDBACK_TEMPERATURE_TOL 1.0e-9

#define SHT_MODEL_MODE_ORIGINAL 0
#define SHT_MODEL_MODE_SPLIT 1
#define SHT_SPLIT_VARIABLE_COUNT 9
#define SHT_SPLIT_GAS_VARIABLE_COUNT 7
#define SHT_PHYSICAL_BLEED_COUNT SHT_EXTERNAL_BLEED_COUNT
#define SHT_SPLIT_COMPRESSOR_BLEED_COUNT 5
#define SHT_LEGACY_BLEED_COUNT 14
#define SHT_SPLIT_HEALTH_COMPONENT_COUNT 6
#define SHT_SPLIT_HEALTH_PER_COMPONENT 3
#define SHT_SPLIT_HEALTH_LOCAL_BASE 71
#define SHT_BLEED_PRESSURE_HEALTH_BASE 16
#define SHT_BLEED_FLOW_HEALTH_BASE 30
#define SHT_BLEED_THERMAL_HEALTH_BASE 44
#define SHT_PRESSURE_LOSS_COMPONENT_COUNT 4
#define SHT_PRESSURE_LOSS_GATE_ZERO_RATIO 0.015
#define SHT_PRESSURE_LOSS_GATE_FULL_RATIO 0.04

enum
{
	SHT_PRESSURE_LOSS_INLET = 0,
	SHT_PRESSURE_LOSS_BURNER = 1,
	SHT_PRESSURE_LOSS_DUCT2 = 2,
	SHT_PRESSURE_LOSS_DUCT3 = 3
};

typedef struct SHTPressureLossReference
{
	double massFlow;
	double totalTemperature;
	double totalPressure;
} SHTPressureLossReference;

/*
 * 两套参考量分别来自 V1 三部件和 V2 六部件的独立设计点回放。
 * 它们只用于把局部修正流量参数归一化到设计点，不把两个模型互相
 * 关联。以后若设计点边界或部件缩放系数发生改变，应同步重新冻结
 * 本表，并通过 RunModelSHT_V1_2DP/V2_2DP 的设计点门禁复核。
 * 顺序固定为 Inlet、Burner、Duct2、Duct3 的进口状态 [W,Tt,Pt]。
 */
static const SHTPressureLossReference
SHT_PressureLossReferenceOriginal[SHT_PRESSURE_LOSS_COMPONENT_COUNT] = {
	{ 6.7114014807153133, 288.15, 101325.0 },
	{ 5.5046914944826995, 702.3079869521182, 1572564.0 },
	{ 6.6706983026652109, 1142.9390961112899, 395927.73736700282 },
	{ 6.8331142184985216, 857.21353991631679, 108055.52346425848 }
};

static const SHTPressureLossReference
SHT_PressureLossReferenceSplit[SHT_PRESSURE_LOSS_COMPONENT_COUNT] = {
	{ 6.7114423282275082, 288.15, 101325.0 },
	{ 5.5047249976122021, 702.30798695211797, 1572564.0 },
	{ 6.6707389024422223, 1143.4502168824008, 395927.73735746165 },
	{ 6.8331558067853280, 857.20314825615196, 108055.52351408289 }
};

static int SHT_ConfigurePressureLossModels(EngineTurboshaft *eng)
{
	const SHTPressureLossReference *reference;
	PressureLossModel *model[SHT_PRESSURE_LOSS_COMPONENT_COUNT];
	int i;

	if(eng == NULL)
		return -1;

	reference = eng->modelMode == SHT_MODEL_MODE_SPLIT ?
		SHT_PressureLossReferenceSplit : SHT_PressureLossReferenceOriginal;
	model[SHT_PRESSURE_LOSS_INLET] = &eng->Inlet.pressureLossModel;
	model[SHT_PRESSURE_LOSS_BURNER] = &eng->Burner.pressureLossModel;
	model[SHT_PRESSURE_LOSS_DUCT2] = &eng->Duct2.pressureLossModel;
	model[SHT_PRESSURE_LOSS_DUCT3] = &eng->Duct3.pressureLossModel;

	for(i = 0; i < SHT_PRESSURE_LOSS_COMPONENT_COUNT; ++i)
	{
		if(pressureLossModelConfigure(
			model[i], reference[i].massFlow, reference[i].totalTemperature,
			reference[i].totalPressure, SHT_PRESSURE_LOSS_GATE_ZERO_RATIO,
			SHT_PRESSURE_LOSS_GATE_FULL_RATIO) != 0)
			return -1;
	}

	return 0;
}

enum
{
	SHT_BLEED_CC_GT1_INLET = SHT_EXTERNAL_BLEED_CC_GT1_INLET,
	SHT_BLEED_CC_GT1_EXIT = SHT_EXTERNAL_BLEED_CC_GT1_EXIT,
	SHT_BLEED_CC_GT2_INLET = SHT_EXTERNAL_BLEED_CC_GT2_INLET,
	SHT_BLEED_CC_GT2_EXIT = SHT_EXTERNAL_BLEED_CC_GT2_EXIT,
	SHT_BLEED_AC_PT1_INLET = SHT_EXTERNAL_BLEED_AC_PT1_INLET,
	SHT_BLEED_AC_PT1_EXIT = SHT_EXTERNAL_BLEED_AC_PT1_EXIT,
	SHT_BLEED_AC_PT2_INLET = SHT_EXTERNAL_BLEED_AC_PT2_INLET,
	SHT_BLEED_AC_PT2_EXIT = SHT_EXTERNAL_BLEED_AC_PT2_EXIT,
	SHT_BLEED_CC_PT2_EXIT = SHT_EXTERNAL_BLEED_CC_PT2_EXIT,
	SHT_BLEED_AC_LEAK = SHT_EXTERNAL_BLEED_AC_LEAK
};

/*
 * 外部空气系统与六部件模型统一采用10条真实物理流路。分数引气仍以
 * 整体 HPC 进口流量为基准；两个子压气机在每次 Newton 求值时换算为
 * 各自进口流量基准，保证实际支路流量不因拆分位置改变。
 */
static const double SHT_PhysicalBleedFraction[SHT_PHYSICAL_BLEED_COUNT] = {
	0.081, 0.0306, 0.0247, 0.0148, 0.0057,
	0.0046, 0.0064, 0.0045, 0.003, 0.0045
};
/* AC局部口：PT1进口、PT1出口、PT2进口、PT2出口、泄漏。 */
static const int
SHT_AxialBleedIndex[SHT_SPLIT_COMPRESSOR_BLEED_COUNT] = {
	SHT_BLEED_AC_PT1_INLET, SHT_BLEED_AC_PT1_EXIT,
	SHT_BLEED_AC_PT2_INLET, SHT_BLEED_AC_PT2_EXIT,
	SHT_BLEED_AC_LEAK
};
/* CC局部口：GT1进口、GT1出口、GT2进口、GT2出口、PT2出口。 */
static const int
SHT_CentrifugalBleedIndex[SHT_SPLIT_COMPRESSOR_BLEED_COUNT] = {
	SHT_BLEED_CC_GT1_INLET, SHT_BLEED_CC_GT1_EXIT,
	SHT_BLEED_CC_GT2_INLET, SHT_BLEED_CC_GT2_EXIT,
	SHT_BLEED_CC_PT2_EXIT
};

/*
 * 三部件聚合模型内部仍需要原14个等效输入位置。公共外部接口不再暴露
 * 这套历史编号；仅在模式0内部按下列映射把10条物理流路展开。四对流路
 * 原始比例相同，因此各按50%分配质量流量，热力状态保持不变。
 */
static const int SHT_LegacyBleedPhysicalIndex[SHT_LEGACY_BLEED_COUNT] = {
	0, 1, 2, 1, 2, 3, 4, 5, 6, 5, 6, 7, 8, 9
};
static const double SHT_LegacyBleedFlowShare[SHT_LEGACY_BLEED_COUNT] = {
	1.0, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0,
	0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0
};

/*
 * 三部件模式对外同样只接收10路物理引气修正。下列数组是模式0内部
 * 传给原14路压气机核心的派生量，不属于新的公共参数接口。
 */
static double SHT_OriginalBleedPressureHealth[SHT_LEGACY_BLEED_COUNT];
static double SHT_OriginalBleedFlowHealth[SHT_LEGACY_BLEED_COUNT];
static double SHT_OriginalBleedEnthalpyHealth[SHT_LEGACY_BLEED_COUNT];

static double SHT_SplitGT1Cooling[2 * gasPathWidth];
static double SHT_SplitGT2Cooling[2 * gasPathWidth];
static double SHT_SplitPT1Cooling[2 * gasPathWidth];
static double SHT_SplitPT2Cooling[3 * gasPathWidth];
static double SHT_SplitLeakCooling[gasPathWidth];

typedef struct SHTCoolingSplitRuntime
{
	int initialized;
	int version;
	int parameterCount;
	double ratio[SHT_VISSER_COOLING_BRANCH_COUNT];
} SHTCoolingSplitRuntime;

typedef struct SHTVisserCoolingEvaluation
{
	int valid;
	double metalHeatFlow[SHT_VISSER_METAL_NODE_COUNT];
	double diskHeatFlow[SHT_DISK_NODE_COUNT];
	double branchHeatFlow[SHT_VISSER_COOLING_BRANCH_COUNT];
	double routeInletTemperature[SHT_PHYSICAL_COOLING_ROUTE_COUNT];
	double routeOutletTemperature[SHT_PHYSICAL_COOLING_ROUTE_COUNT];
} SHTVisserCoolingEvaluation;

/* 10条物理流路在19个内部换热支路中的连续分组。 */
static const int SHT_CoolingBranchStart[SHT_PHYSICAL_COOLING_ROUTE_COUNT] = {
	0, 3, 5, 9, 11, 13, 14, 16, 17, 18
};
static const int SHT_CoolingBranchCount[SHT_PHYSICAL_COOLING_ROUTE_COUNT] = {
	3, 2, 4, 2, 2, 1, 2, 1, 1, 1
};
static SHTCoolingSplitRuntime SHT_CoolingSplit;
static SHTVisserCoolingEvaluation SHT_VisserCoolingEvaluation;
static double SHT_SplitZeroHealth[16];
static double SHT_SplitEffectiveHealth[
	SHT_SPLIT_HEALTH_COMPONENT_COUNT * SHT_SPLIT_HEALTH_PER_COMPONENT];
static double SHT_HealthDesignValue[SHT_HEALTH_TOTAL_COUNT];
static SHTHealthScheduleSystem SHT_HealthSchedule;

static void SHT_ResetCoolingSplit(void)
{
	memset(&SHT_CoolingSplit, 0, sizeof(SHT_CoolingSplit));
	memset(&SHT_VisserCoolingEvaluation, 0,
		sizeof(SHT_VisserCoolingEvaluation));
}

static int SHT_InitializeCoolingSplit(
	int version,
	int parameterCount,
	const double *ratio)
{
	SHTCoolingSplitRuntime candidate;
	int routeIndex;
	int branchIndex;
	if (ratio == NULL)
		return SHT_ERROR_NULL_POINTER;
	if (version != SHT_COOLING_SPLIT_VERSION_1)
		return SHT_ERROR_THERMAL_CONFIG_VERSION;
	if (parameterCount != SHT_COOLING_SPLIT_PARAMETER_COUNT)
		return SHT_ERROR_COOLING_SPLIT_SIZE;
	memset(&candidate, 0, sizeof(candidate));
	candidate.version = version;
	candidate.parameterCount = parameterCount;
	for (branchIndex = 0;
		branchIndex < SHT_VISSER_COOLING_BRANCH_COUNT; ++branchIndex)
	{
		if (!_finite(ratio[branchIndex]) || ratio[branchIndex] < 0.0 ||
			ratio[branchIndex] > 1.0)
			return SHT_ERROR_COOLING_SPLIT_VALUE;
		candidate.ratio[branchIndex] = ratio[branchIndex];
	}
	for (routeIndex = 0;
		routeIndex < SHT_PHYSICAL_COOLING_ROUTE_COUNT; ++routeIndex)
	{
		double sum = 0.0;
		int start = SHT_CoolingBranchStart[routeIndex];
		int count = SHT_CoolingBranchCount[routeIndex];
		for (branchIndex = 0; branchIndex < count; ++branchIndex)
			sum += candidate.ratio[start + branchIndex];
		if (fabs(sum - 1.0) > 1.0e-9)
			return SHT_ERROR_COOLING_SPLIT_VALUE;
	}
	candidate.initialized = 1;
	SHT_CoolingSplit = candidate;
	return SHT_STATUS_OK;
}

static int SHT_GetCoolingSplitStatus(void)
{
	return SHT_CoolingSplit.initialized ?
		SHT_STATUS_OK : SHT_ERROR_COOLING_SPLIT_NOT_INITIALIZED;
}

/*
 * 模式0环境边界只在ConditionsInit读取，保持历史锁存语义；模式1至4
 * 在每次运行入口读取。Newton/Jacobian重复回放仅复用已解析的边界状态。
 * 该缓存不进入导出的 EngineTurboshaft 结构体，避免改变既有MATLAB头文件
 * 所依赖的结构体二进制布局。
 */
typedef struct SHTInletBoundaryState
{
	int mode;
	double ambientTemperature;
	double externalPressureRecovery;
	double totalEnthalpy;
	double totalTemperature;
	double totalPressure;
	double staticPressure;
	double staticTemperature;
	double velocity;
	double measuredPt2;
	double inferredPressureLossCorrection;
} SHTInletBoundaryState;

static SHTInletBoundaryState SHT_InletBoundaryState;

/*
 * 六个旋转子部件的总体修正索引。每行依次是
 * [流量K_W，效率K_eta，压比K_PR]，部件顺序为
 * [AC, CC, GT1, GT2, PT1, PT2]。
 */
static const int SHT_SplitGroupHealthIndex[
	SHT_SPLIT_HEALTH_COMPONENT_COUNT][SHT_SPLIT_HEALTH_PER_COMPONENT] = {
	{ 1, 2, 3 }, { 1, 2, 3 },
	{ 7, 8, 9 }, { 7, 8, 9 },
	{ 11, 12, 13 }, { 11, 12, 13 }
};

static double *SHT_HealthAddress(int healthIndex)
{
	if (healthIndex < 0 || healthIndex >= SHT_HEALTH_TOTAL_COUNT)
		return NULL;
	if (healthIndex < SHT_HEALTH_BASE_COUNT)
		return &Turboshaft.hlthparas[healthIndex];
	return &Turboshaft.hlthparasExtended[
		healthIndex - SHT_HEALTH_BASE_COUNT];
}

static double SHT_HealthValue(int healthIndex)
{
	double *value = SHT_HealthAddress(healthIndex);
	return value == NULL ? 0.0 : *value;
}

static int SHT_SetHealthParameterError(int healthIndex, double value);
static int SHT_UpdateSplitEffectiveHealth(void);

/*
 * 四项压损调度的零流量节点不是独立待估参数，而是由当前stepIn设计点值
 * 派生：Delta_0=-k_design。表只需初始化一次；参数辨识改变k_design时，
 * 本约束随每次DLL调用自动更新，不要求MATLAB重复装表。
 */
static int SHT_UpdatePressureScheduleZeroAnchors(void)
{
	static const int pressureHealthIndex[] = { 0, 6, 10, 14 };
	int i;
	if(!SHT_HealthSchedule.enabled)
		return SHT_STATUS_OK;
	for(i = 0; i < (int)(sizeof(pressureHealthIndex) /
		sizeof(pressureHealthIndex[0])); ++i)
	{
		int healthIndex = pressureHealthIndex[i];
		SHTHealthScheduleTable *table =
			&SHT_HealthSchedule.table[healthIndex];
		if(!table->configured || table->nodeCount < 2 ||
			table->nodeCount > SHT_HEALTH_SCHEDULE_MAX_NODES ||
			table->xNode[0] != 0.0)
			return SHT_SetHealthParameterError(
				healthIndex, table->nodeCount);
		table->deltaNode[0] = -SHT_HealthDesignValue[healthIndex];
	}
	return SHT_STATUS_OK;
}

static int SHT_SetEffectiveHealthValue(int healthIndex, double value)
{
	double *destination = SHT_HealthAddress(healthIndex);
	if(destination == NULL || !_finite(value))
		return SHT_SetHealthParameterError(healthIndex, value);
	*destination = value;
	return SHT_STATUS_OK;
}

/*
 * 将公共10路物理引气健康参数展开为三部件压气机核心使用的历史14路。
 * 四对等效支路由同一条物理气流拆成两路：流量加性修正各取一半；
 * 压力恢复和焓提取位置描述的是同一气流状态，原值复制而不分半。
 */
static int SHT_UpdateOriginalBleedEffectiveHealth(void)
{
	int legacyIndex;

	memset(SHT_OriginalBleedPressureHealth, 0,
		sizeof(SHT_OriginalBleedPressureHealth));
	memset(SHT_OriginalBleedFlowHealth, 0,
		sizeof(SHT_OriginalBleedFlowHealth));
	memset(SHT_OriginalBleedEnthalpyHealth, 0,
		sizeof(SHT_OriginalBleedEnthalpyHealth));
	if (Turboshaft.modelMode != SHT_MODEL_MODE_ORIGINAL)
		return SHT_STATUS_OK;
	if ((int)Turboshaft.HPC.compressorStruct.FracBldNm !=
		SHT_LEGACY_BLEED_COUNT ||
		Turboshaft.HPC.fractionalBleedsDemand == NULL ||
		Turboshaft.HPC.compressorStruct.FracBldPRecov == NULL ||
		Turboshaft.HPC.compressorStruct.FracBldht == NULL)
		return SHT_ERROR_PARAMETER_VALUE;

	for (legacyIndex = 0; legacyIndex < SHT_LEGACY_BLEED_COUNT;
		++legacyIndex)
	{
		int physicalIndex =
			SHT_LegacyBleedPhysicalIndex[legacyIndex];
		int pressureIndex =
			SHT_BLEED_PRESSURE_HEALTH_BASE + physicalIndex;
		int flowIndex =
			SHT_BLEED_FLOW_HEALTH_BASE + physicalIndex;
		int enthalpyIndex =
			SHT_BLEED_THERMAL_HEALTH_BASE + physicalIndex;
		double pressureCorrection = SHT_HealthValue(pressureIndex);
		double flowCorrection = SHT_HealthValue(flowIndex) *
			SHT_LegacyBleedFlowShare[legacyIndex];
		double enthalpyCorrection = SHT_HealthValue(enthalpyIndex);
		double effectivePressure =
			Turboshaft.HPC.compressorStruct.FracBldPRecov[legacyIndex] +
			pressureCorrection;
		double effectiveFlow =
			Turboshaft.HPC.fractionalBleedsDemand[legacyIndex] +
			flowCorrection;
		double effectiveEnthalpyPosition =
			Turboshaft.HPC.compressorStruct.FracBldht[legacyIndex] +
			enthalpyCorrection;

		if (!_finite(pressureCorrection) ||
			!_finite(effectivePressure) || effectivePressure <= 0.0)
			return SHT_SetHealthParameterError(
				pressureIndex, pressureCorrection);
		if (!_finite(flowCorrection) ||
			!_finite(effectiveFlow) || effectiveFlow < 0.0)
			return SHT_SetHealthParameterError(flowIndex,
				SHT_HealthValue(flowIndex));
		if (!_finite(enthalpyCorrection) ||
			!_finite(effectiveEnthalpyPosition) ||
			effectiveEnthalpyPosition < 0.0 ||
			effectiveEnthalpyPosition > 1.0)
			return SHT_SetHealthParameterError(
				enthalpyIndex, enthalpyCorrection);

		SHT_OriginalBleedPressureHealth[legacyIndex] =
			pressureCorrection;
		SHT_OriginalBleedFlowHealth[legacyIndex] = flowCorrection;
		SHT_OriginalBleedEnthalpyHealth[legacyIndex] =
			enthalpyCorrection;
	}
	return SHT_STATUS_OK;
}

/*
 * 每次共同工作方程求值都从 stepIn 设计点值重新开始，随后按本次局部状态
 * 覆盖有调度表的参数。这样 Newton、有限差分和连续时间步之间不会把
 * 上一次的 K_eff 当作新的设计点值继续累加。
 */
static int SHT_ResetEffectiveHealthFromDesignValue(void)
{
	int healthIndex;
	int status;
	for(healthIndex = 0;
		healthIndex < SHT_HEALTH_TOTAL_COUNT;
		++healthIndex)
	{
		status = SHT_SetEffectiveHealthValue(
			healthIndex, SHT_HealthDesignValue[healthIndex]);
		if(status != SHT_STATUS_OK)
			return status;
	}
	Turboshaft.Inlet.pressureLossModel.correctionBypassNominalGate = 0;
	Turboshaft.Burner.pressureLossModel.correctionBypassNominalGate = 0;
	Turboshaft.Duct2.pressureLossModel.correctionBypassNominalGate = 0;
	Turboshaft.Duct3.pressureLossModel.correctionBypassNominalGate = 0;
	status = SHT_UpdateOriginalBleedEffectiveHealth();
	if(status != SHT_STATUS_OK)
		return status;
	return SHT_UpdateSplitEffectiveHealth();
}

static int SHT_ApplyScheduledHealth(int healthIndex, double coordinate)
{
	double incrementValue;
	double effectiveValue;
	int status;

	if(!SHT_HealthSchedule.enabled ||
		!shtHealthScheduleIsConfigured(&SHT_HealthSchedule, healthIndex))
		return SHT_STATUS_OK;
	status = shtHealthScheduleEvaluateIncrement(
		&SHT_HealthSchedule, healthIndex, coordinate, &incrementValue);
	if(status != 0)
		return SHT_SetHealthParameterError(healthIndex, coordinate);
	effectiveValue = SHT_HealthDesignValue[healthIndex] + incrementValue;
	return SHT_SetEffectiveHealthValue(healthIndex, effectiveValue);
}

static int SHT_ApplyScheduledHealthList(
	const int *healthIndex,
	int count,
	double coordinate)
{
	int i;
	for(i = 0; i < count; ++i)
	{
		int status = SHT_ApplyScheduledHealth(healthIndex[i], coordinate);
		if(status != SHT_STATUS_OK)
			return status;
	}
	return SHT_STATUS_OK;
}

/*
 * 计算与 Compressor_TMATS_body y[15] 完全一致的未修正图上换算转速。
 * 该量只由当前机械转速、进口总温和配置期转速缩放系数决定，不读取
 * 流量/压比/效率健康修正，因此不会形成“修正系数决定调度坐标”的
 * 代数迭代。
 */
static int SHT_GetCompressorMapCorrectedSpeed(
	const CompressorBlock *compressor,
	double *correctedSpeed)
{
	double theta;
	double nc;
	double cNc;
	double inletTemperature;
	double mechanicalSpeed;

	if(compressor == NULL || correctedSpeed == NULL ||
		compressor->gasPathIn == NULL || compressor->nMech == NULL)
		return SHT_ERROR_NULL_POINTER;
	inletTemperature = compressor->gasPathIn[2];
	mechanicalSpeed = *compressor->nMech;
	if(!_finite(inletTemperature) || inletTemperature <= 0.0 ||
		!_finite(mechanicalSpeed))
		return SHT_ERROR_PARAMETER_VALUE;
	theta = inletTemperature / C_TSTD;
	nc = mechanicalSpeed / sqrt(theta);
	if(compressor->compressorStruct.IDes < 0.5)
		cNc = nc / compressor->compressorStruct.NcDes;
	else if(compressor->compressorStruct.IDes < 1.5)
		cNc = compressor->s_C_Nc_des;
	else
		cNc = compressor->s_C_Nc_in;
	if(!_finite(cNc) || cNc == 0.0)
		return SHT_ERROR_PARAMETER_VALUE;
	*correctedSpeed = nc / cNc;
	return _finite(*correctedSpeed) ?
		SHT_STATUS_OK : SHT_ERROR_PARAMETER_VALUE;
}

static int SHT_ApplyPressureLossSchedule(
	int healthIndex,
	double massFlow,
	double totalTemperature,
	double totalPressure,
	PressureLossModel *model)
{
	double correctedFlow;
	int status;
	if(model == NULL)
		return SHT_ERROR_NULL_POINTER;
	model->correctionBypassNominalGate = 0;
	if(!SHT_HealthSchedule.enabled ||
		!shtHealthScheduleIsConfigured(&SHT_HealthSchedule, healthIndex))
		return SHT_STATUS_OK;
	if(!_finite(massFlow) || !_finite(totalTemperature) ||
		!_finite(totalPressure) || massFlow < 0.0 ||
		totalTemperature <= 0.0 || totalPressure <= 0.0)
		return SHT_SetHealthParameterError(healthIndex, massFlow);
	correctedFlow = massFlow * sqrt(totalTemperature / C_TSTD) *
		C_PSTD / totalPressure;
	status = SHT_ApplyScheduledHealth(healthIndex, correctedFlow);
	if(status == SHT_STATUS_OK)
		model->correctionBypassNominalGate = 1;
	return status;
}

/*
 * 三部件模式只调度总体HPC、GT和PT修正。HPC使用未施加健康修正的
 * 图上换算转速，GT/PT使用共同工作变量给出的未修正物理压比；因此
 * 调度坐标不会由本次K_eff反向改变，也不会形成代数迭代。
 */
static int SHT_ApplyOriginalRotatingSchedules(void)
{
	static const int hpcHealth[] = { 1, 2, 3 };
	static const int gtHealth[] = { 7, 8, 9 };
	static const int ptHealth[] = { 11, 12, 13 };
	double hpcCorrectedSpeed;
	int status;

	status = SHT_GetCompressorMapCorrectedSpeed(
		&Turboshaft.HPC, &hpcCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	status = SHT_ApplyScheduledHealthList(hpcHealth,
		(int)(sizeof(hpcHealth) / sizeof(hpcHealth[0])),
		hpcCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	status = SHT_ApplyScheduledHealthList(gtHealth,
		(int)(sizeof(gtHealth) / sizeof(gtHealth[0])),
		Turboshaft.HPT_PRin);
	if(status != SHT_STATUS_OK) return status;
	return SHT_ApplyScheduledHealthList(ptHealth,
		(int)(sizeof(ptHealth) / sizeof(ptHealth[0])),
		Turboshaft.LPT_PRin);
}

static int SHT_ApplySplitRotatingSchedules(void)
{
	static const int acHealth[] = { 1, 2, 3, 71, 72, 73 };
	static const int gtHealth[] = { 7, 8, 9, 77, 78, 79, 80, 81, 82 };
	static const int ptHealth[] = { 11, 12, 13, 83, 84, 85, 86, 87, 88 };
	double acCorrectedSpeed;
	double gtPressureRatio;
	double ptPressureRatio;
	int status;

	status = SHT_GetCompressorMapCorrectedSpeed(
		&Turboshaft.HPC, &acCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	gtPressureRatio = Turboshaft.HPT_PRin * Turboshaft.HPT2_PRin;
	ptPressureRatio = Turboshaft.LPT_PRin * Turboshaft.LPT2_PRin;
	status = SHT_ApplyScheduledHealthList(acHealth,
		(int)(sizeof(acHealth) / sizeof(acHealth[0])), acCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	status = SHT_ApplyScheduledHealthList(gtHealth,
		(int)(sizeof(gtHealth) / sizeof(gtHealth[0])), gtPressureRatio);
	if(status != SHT_STATUS_OK) return status;
	status = SHT_ApplyScheduledHealthList(ptHealth,
		(int)(sizeof(ptHealth) / sizeof(ptHealth[0])), ptPressureRatio);
	if(status != SHT_STATUS_OK) return status;
	return SHT_UpdateSplitEffectiveHealth();
}

static int SHT_ApplySplitCCSchedules(void)
{
	static const int ccHealth[] = { 74, 75, 76 };
	double ccCorrectedSpeed;
	int status = SHT_GetCompressorMapCorrectedSpeed(
		&Turboshaft.HPC2, &ccCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	status = SHT_ApplyScheduledHealthList(ccHealth,
		(int)(sizeof(ccHealth) / sizeof(ccHealth[0])), ccCorrectedSpeed);
	if(status != SHT_STATUS_OK) return status;
	return SHT_UpdateSplitEffectiveHealth();
}

static int SHT_ExpectedHealthScheduleTableCount(void)
{
	if(Turboshaft.modelMode == SHT_MODEL_MODE_ORIGINAL)
		return SHT_HEALTH_SCHEDULE_ORIGINAL_TABLES;
	if(Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		return SHT_HEALTH_SCHEDULE_SPLIT_TABLES;
	return 0;
}

static int SHT_SetHealthParameterError(int healthIndex, double value)
{
	Turboshaft.transientDiagnostics.errorCode = SHT_ERROR_PARAMETER_VALUE;
	Turboshaft.transientDiagnostics.offendingStepInIndex =
		SHT_HEALTH_INPUT_OFFSET + healthIndex;
	Turboshaft.transientDiagnostics.offendingValue = value;
	return SHT_ERROR_PARAMETER_VALUE;
}

static int SHT_SetHealthScheduleSwitchError(double value)
{
	Turboshaft.transientDiagnostics.errorCode = SHT_ERROR_PARAMETER_VALUE;
	Turboshaft.transientDiagnostics.offendingStepInIndex =
		SHT_HEALTH_SCHEDULE_ENABLE_INDEX;
	Turboshaft.transientDiagnostics.offendingValue = value;
	return SHT_ERROR_PARAMETER_VALUE;
}

/*
 * 子压气机内部派生量无法对应单一stepIn下标。负诊断码
 * -11xx/-12xx分别表示AC/CC，末两位01/02/03分别表示
 * 进口流量非法、支路流量非法和总引气超过子部件进口。
 */
static int SHT_SetSplitBleedDerivedError(
	const CompressorBlock *compressor,
	int reason,
	double value)
{
	int componentCode = compressor == &Turboshaft.HPC ? 11 : 12;
	Turboshaft.transientDiagnostics.errorCode = SHT_ERROR_PARAMETER_VALUE;
	Turboshaft.transientDiagnostics.offendingStepInIndex =
		-(componentCode * 100 + reason);
	Turboshaft.transientDiagnostics.offendingValue = value;
	return SHT_ERROR_PARAMETER_VALUE;
}

/*
 * 总体部件修正与子部件修正均以(1+K)乘性作用。每次共同工作方程
 * 回放先从stepIn设计点值恢复，再按当前局部状态更新有调度表的参数，
 * 随后在本函数重算组合值；因此不会把上一次K_eff继续累乘。
 */
static int SHT_UpdateSplitEffectiveHealth(void)
{
	int componentIndex;
	int correctionIndex;

	memset(SHT_SplitEffectiveHealth, 0,
		sizeof(SHT_SplitEffectiveHealth));
	if (Turboshaft.modelMode != SHT_MODEL_MODE_SPLIT)
		return SHT_STATUS_OK;

	for (componentIndex = 0;
		componentIndex < SHT_SPLIT_HEALTH_COMPONENT_COUNT;
		++componentIndex)
	{
		for (correctionIndex = 0;
			correctionIndex < SHT_SPLIT_HEALTH_PER_COMPONENT;
			++correctionIndex)
		{
			int groupIndex = SHT_SplitGroupHealthIndex[
				componentIndex][correctionIndex];
			int localIndex = SHT_SPLIT_HEALTH_LOCAL_BASE +
				componentIndex * SHT_SPLIT_HEALTH_PER_COMPONENT +
				correctionIndex;
			double groupValue = SHT_HealthValue(groupIndex);
			double localValue = SHT_HealthValue(localIndex);
			double effectiveValue;

			if (!_finite(groupValue) || 1.0 + groupValue <= 0.0)
				return SHT_SetHealthParameterError(groupIndex, groupValue);
			if (!_finite(localValue) || 1.0 + localValue <= 0.0)
				return SHT_SetHealthParameterError(localIndex, localValue);
			effectiveValue =
				(1.0 + groupValue) * (1.0 + localValue) - 1.0;
			if (!_finite(effectiveValue) || 1.0 + effectiveValue <= 0.0)
				return SHT_SetHealthParameterError(localIndex, effectiveValue);
			SHT_SplitEffectiveHealth[
				componentIndex * SHT_SPLIT_HEALTH_PER_COMPONENT +
				correctionIndex] = effectiveValue;
		}
	}
	return SHT_STATUS_OK;
}

static void SHT_ClearHealthParameters(void)
{
	memset(Turboshaft.hlthparas, 0, sizeof(Turboshaft.hlthparas));
	memset(Turboshaft.hlthparasExtended, 0,
		sizeof(Turboshaft.hlthparasExtended));
	memset(SHT_HealthDesignValue, 0, sizeof(SHT_HealthDesignValue));
	memset(SHT_SplitEffectiveHealth, 0,
		sizeof(SHT_SplitEffectiveHealth));
	memset(SHT_OriginalBleedPressureHealth, 0,
		sizeof(SHT_OriginalBleedPressureHealth));
	memset(SHT_OriginalBleedFlowHealth, 0,
		sizeof(SHT_OriginalBleedFlowHealth));
	memset(SHT_OriginalBleedEnthalpyHealth, 0,
		sizeof(SHT_OriginalBleedEnthalpyHealth));
}

static int SHT_LoadHealthParameters(const double *stepIn)
{
	int healthIndex;
	int scheduleEnabled;
	int status;
	double switchValue;
	if (stepIn == NULL)
		return SHT_ERROR_NULL_POINTER;

	/*
	 * stepIn 开关是每次发动机求值的唯一运行期选择量。DLL 初始化接口只
	 * 负责装载调度表；这里显式覆盖上一次调用的状态，避免常值回放受到
	 * 先前调度调用影响。
	 */
	switchValue = stepIn[SHT_HEALTH_SCHEDULE_ENABLE_INDEX];
	if(!_finite(switchValue) ||
		(switchValue != 0.0 && switchValue != 1.0))
		return SHT_SetHealthScheduleSwitchError(switchValue);
	scheduleEnabled = switchValue > 0.5 ? 1 : 0;
	if(scheduleEnabled &&
		SHT_HealthSchedule.configuredCount !=
			SHT_ExpectedHealthScheduleTableCount())
		return SHT_SetHealthScheduleSwitchError(switchValue);
	status = shtHealthScheduleSetEnabled(
		&SHT_HealthSchedule, scheduleEnabled);
	if(status != 0)
		return SHT_SetHealthScheduleSwitchError(switchValue);

	for (healthIndex = 0;
		healthIndex < SHT_HEALTH_TOTAL_COUNT;
		++healthIndex)
	{
		double value = stepIn[SHT_HEALTH_INPUT_OFFSET + healthIndex];
		double *destination = SHT_HealthAddress(healthIndex);
		if (!_finite(value) || destination == NULL)
			return SHT_SetHealthParameterError(healthIndex, value);
		SHT_HealthDesignValue[healthIndex] = value;
		*destination = value;
	}
	status = SHT_UpdatePressureScheduleZeroAnchors();
	if(status != SHT_STATUS_OK)
		return status;
	status = SHT_UpdateOriginalBleedEffectiveHealth();
	if(status != SHT_STATUS_OK)
		return status;
	return SHT_UpdateSplitEffectiveHealth();
}

static void SHT_ClearStepOut(double *stepOut)
{
	memset(stepOut, 0, SHT_STEP_OUT_LENGTH * sizeof(*stepOut));
}

/* P1.5～P5 统一配置入口；每次 DLL 调用均清除上一次的派生求值结果。 */
static int SHT_PrepareTransientConfiguration(double *stepIn)
{
	int status;
	SHT_ResetHeatEvaluation(&Turboshaft.transientHeatEvaluation);
	SHT_ResetClearanceEvaluation(&Turboshaft.transientClearanceEvaluation);
	status = SHT_ParseTransientInput(
		stepIn,
		Turboshaft.modelMode,
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		&Turboshaft.transientDiagnostics);

	if (status != SHT_STATUS_OK)
		return status;

	return SHT_STATUS_OK;
}

/*
 * P2 唯一轴系包装函数。仅在瞬态入口显式调用；稳态入口继续直接调用
 * shaftRun()，因此惯量修正既不改变稳态平衡，也不缩放稳态残差。
 *
 * 局部浅副本保留原轴系全部输入指针，只替换本次求值使用的有效惯量。
 * shaftRun() 当前只写 nDot，故只回写这一项。原结构体 inertia 始终保持
 * 名义值，Newton、有限差分及连续 DLL 调用均不会产生累乘效应。
 */
static int SHT_RunTransientShaft(ShaftBlock *shaft, double inertiaCorrection)
{
	ShaftBlock shaftWork;
	int status;

	if (!Turboshaft.transientControl.inertiaEnable)
		return shaftRun(shaft);

	shaftWork = *shaft;
	shaftWork.inertia = shaft->inertia * (1.0 + inertiaCorrection);
	status = shaftRun(&shaftWork);
	if (status == 0)
		shaft->nDot = shaftWork.nDot;
	return status;
}

/*
 * 在当前 DLL 求值开始时计算一次间隙及其反馈倍率。该结果随后在 Newton
 * 全部残差/有限差分调用中保持不变，避免把当前积分步的边界调度混入
 * Newton 内层迭代，也避免任何跨调用累积。
 */
static int SHT_EvaluateCurrentClearance(void)
{
	double currentSpeed[SHT_CLEARANCE_COMPONENT_COUNT] = { 0.0 };
	double designSpeed[SHT_CLEARANCE_COMPONENT_COUNT] = { 1.0 };
	int status;

	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
	{
		/*
		 * 间隙模型需要的是各转子的轴系设计转速。CompressorStruct 只保存
		 * NcDes，不单独保存机械 NDes；同轴压气机和涡轮在配置中共用同一
		 * 机械设计转速，因此 AC/CC 取高压轴的 HPT.NDes。该写法不是用
		 * 涡轮特性替代压气机特性，而是从含 NDes 的同轴部件取得轴系基准。
		 */
		currentSpeed[0] = Turboshaft.HPS_Nmech;
		currentSpeed[1] = Turboshaft.HPS_Nmech;
		currentSpeed[2] = Turboshaft.HPS_Nmech;
		currentSpeed[3] = Turboshaft.HPS_Nmech;
		currentSpeed[4] = Turboshaft.LPS_Nmech;
		currentSpeed[5] = Turboshaft.LPS_Nmech;
		designSpeed[0] = Turboshaft.HPT.turbineStruct.NDes;
		designSpeed[1] = Turboshaft.HPT.turbineStruct.NDes;
		designSpeed[2] = Turboshaft.HPT.turbineStruct.NDes;
		designSpeed[3] = Turboshaft.HPT2.turbineStruct.NDes;
		designSpeed[4] = Turboshaft.LPT.turbineStruct.NDes;
		designSpeed[5] = Turboshaft.LPT2.turbineStruct.NDes;
	}
	else
	{
		currentSpeed[0] = Turboshaft.HPS_Nmech;
		currentSpeed[1] = Turboshaft.HPS_Nmech;
		currentSpeed[2] = Turboshaft.LPS_Nmech;
		designSpeed[0] = Turboshaft.HPT.turbineStruct.NDes;
		designSpeed[1] = Turboshaft.HPT.turbineStruct.NDes;
		designSpeed[2] = Turboshaft.LPT.turbineStruct.NDes;
	}

	status = SHT_EvaluateClearanceStates(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		currentSpeed,
		designSpeed,
		&Turboshaft.transientClearanceEvaluation,
		&Turboshaft.transientDiagnostics);
	if (status != SHT_STATUS_OK)
		return status;

	return SHT_EvaluateClearanceFeedback(
		&Turboshaft.transientControl,
		Turboshaft.transientParameters.effectiveClearanceExchangeRate,
		Turboshaft.transientParameters.kSM,
		&Turboshaft.transientClearanceEvaluation,
		&Turboshaft.transientDiagnostics);
}

static int SHT_IsClearanceFeedbackSelected(int clearanceComponentIndex)
{
	return Turboshaft.transientControl.clearanceFeedbackEnable &&
		Turboshaft.transientClearanceEvaluation
			.feedbackApplied[clearanceComponentIndex] != 0;
}

static int SHT_IsHeatFeedbackSelected(int componentBit)
{
	return Turboshaft.transientControl.heatFeedbackEnable &&
		(Turboshaft.transientControl.componentMask & componentBit) != 0;
}

/*
 * 局部热反馈求值共用 P3 纯热流核。localEvaluation 每次从零开始，因而
 * Newton 有限差分和同一时刻的重复调用不会积累任何隐含物理状态。
 */
static int SHT_EvaluateLocalHeatDetailed(
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	double *totalHeatFlow,
	double *frontHeatFlow,
	double *rearHeatFlow)
{
	SHTTransientHeatEvaluation localEvaluation;
	int status;

	SHT_ResetHeatEvaluation(&localEvaluation);
	if (Turboshaft.transientControl.thermalModelMode ==
		SHT_THERMAL_MODEL_VISSER)
		status = SHT_EvaluateVisserMainGasComponent(
			&Turboshaft.transientControl,
			&Turboshaft.transientState,
			&Turboshaft.transientParameters,
			componentIndex, componentFlow, inletTemperature,
			outletTemperature, heatTimeCorrection,
			&localEvaluation, &Turboshaft.transientDiagnostics);
	else
		status = SHT_EvaluateHeatComponent(
			&Turboshaft.transientControl,
			&Turboshaft.transientState,
			&Turboshaft.transientParameters,
			componentIndex, componentFlow, inletTemperature,
			outletTemperature, heatTimeCorrection,
			&localEvaluation, &Turboshaft.transientDiagnostics);
	if (status == SHT_STATUS_OK)
	{
		*totalHeatFlow = localEvaluation.componentHeatFlow[componentIndex];
		if (frontHeatFlow != NULL)
			*frontHeatFlow =
				Turboshaft.transientControl.thermalModelMode ==
				SHT_THERMAL_MODEL_VISSER ?
				localEvaluation.visserMainGasFrontHeatFlow[componentIndex] :
				0.5 * *totalHeatFlow;
		if (rearHeatFlow != NULL)
			*rearHeatFlow =
				Turboshaft.transientControl.thermalModelMode ==
				SHT_THERMAL_MODEL_VISSER ?
				localEvaluation.visserMainGasRearHeatFlow[componentIndex] :
				0.5 * *totalHeatFlow;
	}
	return status;
}

static int SHT_EvaluateLocalHeat(
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	double *totalHeatFlow)
{
	return SHT_EvaluateLocalHeatDetailed(
		componentIndex, componentFlow, inletTemperature, outletTemperature,
		heatTimeCorrection, totalHeatFlow, NULL, NULL);
}

static int SHT_SetHeatFeedbackFailure(
	int componentIndex,
	int iterationCount,
	double iterationResidual,
	int existingStatus)
{
	SHTTransientDiagnostics *diagnostics = &Turboshaft.transientDiagnostics;
	diagnostics->heatFeedbackApplied[componentIndex] = 1;
	diagnostics->heatFeedbackConverged[componentIndex] = 0;
	diagnostics->heatFeedbackIterationCount[componentIndex] = iterationCount;
	diagnostics->heatFeedbackIterationResidual[componentIndex] = iterationResidual;
	diagnostics->evaluationValid = 0;
	if (existingStatus != SHT_STATUS_OK)
	{
		if (diagnostics->errorCode == SHT_STATUS_OK)
		{
			diagnostics->errorCode = existingStatus;
			diagnostics->offendingStepInIndex = -1;
			diagnostics->offendingValue = iterationResidual;
		}
		return existingStatus;
	}
	diagnostics->errorCode = SHT_ERROR_HEAT_FEEDBACK;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = iterationResidual;
	return SHT_ERROR_HEAT_FEEDBACK;
}

static void SHT_RecordHeatFeedbackSuccess(
	int componentIndex,
	int iterationCount,
	double iterationResidual,
	double energyResidual)
{
	SHTTransientDiagnostics *diagnostics = &Turboshaft.transientDiagnostics;
	diagnostics->heatFeedbackApplied[componentIndex] = 1;
	diagnostics->heatFeedbackConverged[componentIndex] = 1;
	diagnostics->heatFeedbackIterationCount[componentIndex] = iterationCount;
	diagnostics->heatFeedbackIterationResidual[componentIndex] = iterationResidual;
	diagnostics->heatFeedbackEnergyResidual[componentIndex] = energyResidual;
}

/*
 * Burner：先调用原绝热燃烧室，再解 h_out=h_ad-Q_B/W_out 的一维耦合。
 * 只修改出口焓和温度；燃油、FAR、压损和流量严格沿用原函数结果。
 */
static int SHT_RunTransientBurner(
	BurnBlock *burner,
	int componentIndex)
{
	int status = burnRun(burner);
	int iteration;
	int converged = 0;
	double inletFlow;
	double outletFlow;
	double inletTemperature;
	double adiabaticEnthalpy;
	double outletFAR;
	double outletTemperature;
	double nextTemperature = 0.0;
	double nextEnthalpy = 0.0;
	double totalHeatFlow = 0.0;
	double residual = 0.0;
	double tolerance;
	double energyResidual;

	if (status != 0 || !SHT_IsHeatFeedbackSelected(SHT_COMPONENT_BURNER))
		return status;

	inletFlow = burner->gasPathIn[0];
	outletFlow = burner->y[0];
	inletTemperature = burner->gasPathIn[2];
	adiabaticEnthalpy = burner->y[1];
	outletFAR = burner->y[4];
	outletTemperature = burner->y[2];
	if (!_finite(inletFlow) || inletFlow <= 0.0 ||
		!_finite(outletFlow) || outletFlow <= 0.0 ||
		!_finite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_SetHeatFeedbackFailure(componentIndex, 0,
			outletTemperature, SHT_STATUS_OK);

	for (iteration = 1; iteration <= SHT_HEAT_FEEDBACK_MAX_ITERATIONS; ++iteration)
	{
		status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
			inletTemperature, outletTemperature,
			Turboshaft.transientParameters
				.heatTimeCorrection[componentIndex],
			&totalHeatFlow);
		if (status != SHT_STATUS_OK)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				residual, status);
		/* 热流严格为零时保持原燃烧室输出逐位不变。 */
		if (totalHeatFlow == 0.0)
		{
			SHT_RecordHeatFeedbackSuccess(componentIndex, iteration, 0.0, 0.0);
			return SHT_STATUS_OK;
		}

		nextEnthalpy = adiabaticEnthalpy - totalHeatFlow / outletFlow;
		nextTemperature = h2tc(nextEnthalpy, outletFAR);
		if (!_finite(nextEnthalpy) || !_finite(nextTemperature) ||
			nextTemperature <= 0.0)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				nextTemperature, SHT_STATUS_OK);

		residual = nextTemperature - outletTemperature;
		outletTemperature = nextTemperature;
		tolerance = SHT_HEAT_FEEDBACK_TEMPERATURE_TOL *
			fmax(1.0, fabs(outletTemperature));
		if (fabs(residual) <= tolerance)
		{
			converged = 1;
			break;
		}
	}
	if (!converged)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration - 1,
			residual, SHT_STATUS_OK);

	/* 以收敛温度再求一次热流，使记录的能量残差对应最终输出。 */
	status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
		inletTemperature, outletTemperature,
		Turboshaft.transientParameters.heatTimeCorrection[componentIndex],
		&totalHeatFlow);
	if (status != SHT_STATUS_OK)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
			residual, status);
	nextEnthalpy = adiabaticEnthalpy - totalHeatFlow / outletFlow;
	nextTemperature = h2tc(nextEnthalpy, outletFAR);
	residual = nextTemperature - outletTemperature;
	burner->y[1] = nextEnthalpy;
	burner->y[2] = nextTemperature;
	energyResidual = outletFlow * (burner->y[1] - adiabaticEnthalpy) +
		totalHeatFlow;
	SHT_RecordHeatFeedbackSuccess(componentIndex, iteration,
		residual, energyResidual);
	return SHT_STATUS_OK;
}

static int SHT_SetExternalBleedInputError(void)
{
	Turboshaft.transientDiagnostics.errorCode =
		SHT_ERROR_PARAMETER_VALUE;
	return SHT_ERROR_PARAMETER_VALUE;
}

/*
 * 外部空气系统输入在进入 Newton 迭代前做一次与求解域无关的校验。
 * 其中总引气流量只与 HPC 进口流量自由变量的上界比较；实际迭代点上
 * 的质量守恒检查仍在压气机调用包装层内完成。
 */
static int SHT_ValidateExternalBleedInput(const CompressorBlock *compressor)
{
	int fractionalBleedCount =
		(int)(compressor->compressorStruct.FracBldNm);
	int requiredWidth = gasPathWidth * fractionalBleedCount;
	int i;
	double totalExternalBleedFlow = 0.0;
	double maximumInletFlow = Turboshaft.varMax[0];

	if (fractionalBleedCount < 0 || fractionalBleedCount > 500 ||
		!_finite(compressor->customerBleeds[2500]) ||
		(int)(compressor->customerBleeds[2500]) < requiredWidth ||
		!_finite(maximumInletFlow) || maximumInletFlow <= 0.0)
		return SHT_SetExternalBleedInputError();

	for (i = 0; i < fractionalBleedCount; i++)
	{
		const double *branch =
			&compressor->customerBleeds[gasPathWidth * i];
		if (!_finite(branch[0]) || branch[0] < 0.0 ||
			!_finite(branch[1]) ||
			!_finite(branch[2]) || branch[2] < 0.0 ||
			!_finite(branch[3]) || branch[3] < 0.0 ||
			!_finite(branch[4]) || branch[4] < 0.0)
			return SHT_SetExternalBleedInputError();
		if (branch[0] > 0.0 &&
			(branch[2] <= 0.0 || branch[3] <= 0.0))
			return SHT_SetExternalBleedInputError();

		totalExternalBleedFlow += branch[0];
	}

	if (!_finite(totalExternalBleedFlow) ||
		totalExternalBleedFlow >= maximumInletFlow)
		return SHT_SetExternalBleedInputError();

	return SHT_STATUS_OK;
}

/* 公共外部空气系统接口固定为10条物理流路，每路状态为[W,h,Tt,Pt,FAR]。 */
static int SHT_ValidatePhysicalExternalBleedInput(
	const double *physicalBleeds)
{
	int i;
	double totalFlow = 0.0;
	double maximumInletFlow = Turboshaft.varMax[0];
	if (physicalBleeds == NULL ||
		!_finite(maximumInletFlow) || maximumInletFlow <= 0.0)
		return SHT_SetExternalBleedInputError();

	for (i = 0; i < SHT_PHYSICAL_BLEED_COUNT; ++i)
	{
		const double *branch = &physicalBleeds[gasPathWidth * i];
		if (!_finite(branch[0]) || branch[0] < 0.0 ||
			!_finite(branch[1]) ||
			!_finite(branch[2]) || branch[2] < 0.0 ||
			!_finite(branch[3]) || branch[3] < 0.0 ||
			!_finite(branch[4]) || branch[4] < 0.0 ||
			(branch[0] > 0.0 && (branch[2] <= 0.0 || branch[3] <= 0.0)))
			return SHT_SetExternalBleedInputError();
		totalFlow += branch[0];
	}
	if (!_finite(totalFlow) || totalFlow >= maximumInletFlow)
		return SHT_SetExternalBleedInputError();
	return SHT_STATUS_OK;
}

/*
 * 读取统一的10路物理接口。六部件模式直接保存这10路；三部件模式只在
 * DLL内部展开为原14个等效位置，以维持聚合涡轮模型的历史计算关系。
 */
static int SHT_LoadExternalBleedInput(const double *stepIn)
{
	const double *physicalBleeds;
	int i;
	int status;

	if (stepIn == NULL)
		return SHT_SetExternalBleedInputError();
	if (!_finite(stepIn[SHT_EXTERNAL_BLEED_COUNT_INDEX]) ||
		stepIn[SHT_EXTERNAL_BLEED_COUNT_INDEX] !=
			(double)SHT_EXTERNAL_BLEED_COUNT)
		return SHT_SetExternalBleedInputError();
	physicalBleeds = &stepIn[SHT_EXTERNAL_BLEED_OFFSET];
	status = SHT_ValidatePhysicalExternalBleedInput(physicalBleeds);
	if (status != SHT_STATUS_OK)
		return status;

	memset(Turboshaft.HPC.customerBleeds, 0,
		2500 * sizeof(Turboshaft.HPC.customerBleeds[0]));
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
	{
		memcpy(Turboshaft.HPC.customerBleeds, physicalBleeds,
			SHT_PHYSICAL_BLEED_COUNT * gasPathWidth * sizeof(double));
		Turboshaft.HPC.customerBleeds[2500] =
			SHT_PHYSICAL_BLEED_COUNT * gasPathWidth;
		return SHT_STATUS_OK;
	}

	for (i = 0; i < SHT_LEGACY_BLEED_COUNT; ++i)
	{
		const double *source = &physicalBleeds[gasPathWidth *
			SHT_LegacyBleedPhysicalIndex[i]];
		double *destination = &Turboshaft.HPC.customerBleeds[
			gasPathWidth * i];
		memcpy(destination, source, gasPathWidth * sizeof(double));
		destination[0] *= SHT_LegacyBleedFlowShare[i];
	}
	Turboshaft.HPC.customerBleeds[2500] =
		SHT_LEGACY_BLEED_COUNT * gasPathWidth;
	return SHT_ValidateExternalBleedInput(&Turboshaft.HPC);
}

/*
 * 运行一个子压气机。physicalBleedIndex给出5个局部取气口在统一10路
 * 物理接口中的编号。实际分数引气需求由物理绝对流量除以当前子压气机
 * 进口流量得到。这样CC进口已扣除AC引气时，各路仍严格保持整体HPC
 * 进口流量基准。
 */
static int SHT_RunCompressorMapWithClearance(
	CompressorBlock *compressor,
	int clearanceComponentIndex);
static int SHT_ApplyTransientCompressorHeat(
	CompressorBlock *compressor,
	int componentIndex,
	int componentBit,
	double heatTimeCorrection);

static int SHT_RunSplitCompressor(
	CompressorBlock *compressor,
	const int *physicalBleedIndex,
	int bleedCount,
	double overallHPCInletFlow,
	int useExternalBleed,
	int clearanceComponentIndex,
	int heatComponentIndex,
	int applyTransientEffects)
{
	double effectiveDemand[SHT_SPLIT_COMPRESSOR_BLEED_COUNT];
	double zeroHealth[SHT_SPLIT_COMPRESSOR_BLEED_COUNT] = { 0.0 };
	double pressureRecoveryHealth[SHT_SPLIT_COMPRESSOR_BLEED_COUNT] = { 0.0 };
	double childInletFlow;
	double totalBleedFlow = 0.0;
	double *originalDemand;
	double *originalHpWbld;
	double *originalHpBldPRec;
	double *originalHpBldht;
	int i;
	int status;

	if (compressor == NULL || physicalBleedIndex == NULL)
		return SHT_ERROR_NULL_POINTER;
	if (bleedCount != SHT_SPLIT_COMPRESSOR_BLEED_COUNT ||
		(int)compressor->compressorStruct.FracBldNm != bleedCount)
		return SHT_ERROR_PARAMETER_VALUE;
	childInletFlow = compressor->gasPathIn[0];
	if (!_finite(childInletFlow) || childInletFlow <= 0.0 ||
		!_finite(overallHPCInletFlow) || overallHPCInletFlow <= 0.0)
		return SHT_SetSplitBleedDerivedError(
			compressor, 1, childInletFlow);

	for (i = 0; i < bleedCount; ++i)
	{
		int physicalIndex = physicalBleedIndex[i];
		double branchFlow;
		double physicalFraction;
		if (physicalIndex < 0 || physicalIndex >= SHT_PHYSICAL_BLEED_COUNT)
			return SHT_ERROR_PARAMETER_VALUE;
		if (useExternalBleed)
		{
			branchFlow = Turboshaft.HPC.customerBleeds[
				gasPathWidth * physicalIndex];
		}
		else
		{
			double flowCorrection = SHT_HealthValue(
				SHT_BLEED_FLOW_HEALTH_BASE + physicalIndex);
			double pressureCorrection = SHT_HealthValue(
				SHT_BLEED_PRESSURE_HEALTH_BASE + physicalIndex);
			double effectivePressureRecovery =
				compressor->compressorStruct.FracBldPRecov[i] +
				pressureCorrection;

			physicalFraction =
				SHT_PhysicalBleedFraction[physicalIndex] + flowCorrection;
			if (!_finite(physicalFraction) || physicalFraction < 0.0)
				return SHT_SetHealthParameterError(
					SHT_BLEED_FLOW_HEALTH_BASE + physicalIndex,
					flowCorrection);
			if (!_finite(effectivePressureRecovery) ||
				effectivePressureRecovery <= 0.0)
				return SHT_SetHealthParameterError(
					SHT_BLEED_PRESSURE_HEALTH_BASE + physicalIndex,
					pressureCorrection);
			pressureRecoveryHealth[i] = pressureCorrection;
			branchFlow = physicalFraction * overallHPCInletFlow;
		}
		if (!_finite(branchFlow) || branchFlow < 0.0)
			return SHT_SetSplitBleedDerivedError(
				compressor, 2, branchFlow);
		totalBleedFlow += branchFlow;
		effectiveDemand[i] = branchFlow / childInletFlow;
	}
	if (!_finite(totalBleedFlow) || totalBleedFlow >= childInletFlow)
		return SHT_SetSplitBleedDerivedError(
			compressor, 3, totalBleedFlow / childInletFlow);

	originalDemand = compressor->fractionalBleedsDemand;
	originalHpWbld = compressor->hpWbld;
	originalHpBldPRec = compressor->hpBldPRec;
	originalHpBldht = compressor->hpBldht;
	compressor->fractionalBleedsDemand = effectiveDemand;
	compressor->hpWbld = zeroHealth;
	compressor->hpBldPRec = useExternalBleed ?
		zeroHealth : pressureRecoveryHealth;
	compressor->hpBldht = zeroHealth;
	status = SHT_RunCompressorMapWithClearance(
		compressor, clearanceComponentIndex);
	if (status == SHT_STATUS_OK && applyTransientEffects)
		status = SHT_ApplyTransientCompressorHeat(compressor,
			heatComponentIndex, SHT_COMPONENT_HPC,
			Turboshaft.transientParameters
				.heatTimeCorrection[heatComponentIndex]);

	/*
	 * 六部件内部引气模式不再使用历史“焓提取位置加性
	 * 修正”，而是直接对每条物理支路总温施加(1+K_T)。修正
	 * 引气焓后，必须同步更新引气功、压气机轴功和转矩，避免
	 * 下游冷却流状态与高压轴能量不守恒。外部空气模式的
	 * [W,h,Tt,Pt,FAR]由外部系统完整给定，因此不再施加内部修正。
	 */
	if (status == SHT_STATUS_OK && !useExternalBleed)
	{
		double bleedPowerCorrection = 0.0;
		for (i = 0; i < bleedCount; ++i)
		{
			int physicalIndex = physicalBleedIndex[i];
			int healthIndex =
				SHT_BLEED_THERMAL_HEALTH_BASE + physicalIndex;
			double temperatureCorrection = SHT_HealthValue(healthIndex);
			double *branch = &compressor->fractionalBleeds[
				gasPathWidth * i];
			double originalEnthalpy = branch[1];
			double correctedTemperature;
			double correctedEnthalpy;

			if (!_finite(temperatureCorrection) ||
				1.0 + temperatureCorrection <= 0.0)
			{
				status = SHT_SetHealthParameterError(
					healthIndex, temperatureCorrection);
				break;
			}
			/* K_T=0 时严格保留压气机核心的原始数值路径。 */
			if (temperatureCorrection == 0.0)
				continue;
			correctedTemperature =
				branch[2] * (1.0 + temperatureCorrection);
			correctedEnthalpy = t2hc(correctedTemperature, branch[4]);
			if (!_finite(correctedTemperature) || correctedTemperature <= 0.0 ||
				!_finite(correctedEnthalpy))
			{
				status = SHT_SetHealthParameterError(
					healthIndex, temperatureCorrection);
				break;
			}

			bleedPowerCorrection +=
				branch[0] * (correctedEnthalpy - originalEnthalpy);
			branch[1] = correctedEnthalpy;
			branch[2] = correctedTemperature;
		}
		if (status == SHT_STATUS_OK)
		{
			double mechanicalSpeed = *compressor->nMech;
			double boundedSpeed = mechanicalSpeed > 10.0 ?
				mechanicalSpeed : 10.0;
			compressor->y[22] += bleedPowerCorrection;
			compressor->y[23] -= bleedPowerCorrection;
			compressor->y[5] = compressor->y[23] /
				(boundedSpeed * PI / 30.0);
		}
	}

	/* 临时数组位于当前栈帧，返回前必须无条件恢复长期持有的指针。 */
	compressor->fractionalBleedsDemand = originalDemand;
	compressor->hpWbld = originalHpWbld;
	compressor->hpBldPRec = originalHpBldPRec;
	compressor->hpBldht = originalHpBldht;
	return status;
}

/*
 * 取得一条物理冷却流。内部模式按AC/CC局部口读取，外部模式按统一
 * 10路物理接口编号读取。两种模式的每条状态均为[W,h,Tt,Pt,FAR]，
 * 不再执行历史等效支路的拆分或合并。
 */
static int SHT_GetPhysicalCoolingStream(
	double *destination,
	const CompressorBlock *compressor,
	int localIndex,
	int physicalIndex,
	int useExternalBleed)
{
	if (destination == NULL || compressor == NULL)
		return SHT_ERROR_PARAMETER_VALUE;
	if (!useExternalBleed)
	{
		if (localIndex < 0 ||
			localIndex >= (int)compressor->compressorStruct.FracBldNm)
			return SHT_ERROR_PARAMETER_VALUE;
		memcpy(destination,
			&compressor->fractionalBleeds[gasPathWidth * localIndex],
			gasPathWidth * sizeof(double));
		return SHT_STATUS_OK;
	}

	if (physicalIndex < 0 || physicalIndex >= SHT_PHYSICAL_BLEED_COUNT)
		return SHT_ERROR_PARAMETER_VALUE;
	memcpy(destination,
		&Turboshaft.HPC.customerBleeds[gasPathWidth * physicalIndex],
		gasPathWidth * sizeof(double));
	return SHT_STATUS_OK;
}

enum
{
	SHT_COOLING_TARGET_NONE = 0,
	SHT_COOLING_TARGET_METAL = 1,
	SHT_COOLING_TARGET_DISK = 2
};

/*
 * 19个内部支路的冷却对象。金属节点19/20分别为GT1/GT2导向器；
 * 盘节点顺序为AC、CC、GT1、GT2、PT1、PT2。第19支路为泄漏流，
 * 不参加首轮热网络换热，但保留在统一分流字典中。
 */
static const int SHT_CoolingTargetType[SHT_VISSER_COOLING_BRANCH_COUNT] = {
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_METAL,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_METAL,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_DISK, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_METAL, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_DISK, SHT_COOLING_TARGET_DISK,
	SHT_COOLING_TARGET_NONE
};

static const int SHT_CoolingTargetIndex[SHT_VISSER_COOLING_BRANCH_COUNT] = {
	19, 2, 8, 9, 7, 12, 20, 3, 11, 3, 3, 4, 15, 4, 18, 5, 5, 3, -1
};

static const int SHT_CoolingBranchComponent[
	SHT_VISSER_COOLING_BRANCH_COUNT] = {
	3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 6, 6, 6, 4, -1
};

/* 三部件合并热节点，但保留19个物理换热支路及其流量分配。 */
static int SHT_CoolingTargetForMode(int branchIndex)
{
	static const int legacyTarget[19] = {
		10, 1, 5, 6, 4, 6, 10, 1, 5, 1, 1, 2, 9, 2, 9, 2, 2, 1, -1
	};
	return Turboshaft.modelMode == 0 ? legacyTarget[branchIndex] :
		SHT_CoolingTargetIndex[branchIndex];
}

static int SHT_IsVisserComponentSelected(int componentIndex)
{
	static const int componentBit[SHT_SPLIT_HEAT_COMPONENT_COUNT] = {
		SHT_COMPONENT_HPC, SHT_COMPONENT_HPC, SHT_COMPONENT_BURNER,
		SHT_COMPONENT_GT, SHT_COMPONENT_GT, SHT_COMPONENT_PT,
		SHT_COMPONENT_PT
	};
	return componentIndex >= 0 &&
		componentIndex < SHT_SPLIT_HEAT_COMPONENT_COUNT &&
		(Turboshaft.transientControl.componentMask &
		 componentBit[componentIndex]) != 0;
}

static double SHT_GetVisserMetalTemperature(int logicalNodeIndex)
{
	int count = Turboshaft.transientControl.metalNodeCount;
	if (logicalNodeIndex < count)
		return Turboshaft.transientState.metalTemperature[logicalNodeIndex];
	return Turboshaft.transientState.guideVaneTemperature[logicalNodeIndex - count];
}

static double *SHT_GetSplitCoolingStream(int routeIndex)
{
	switch (routeIndex)
	{
	case 0: return &SHT_SplitGT1Cooling[0];
	case 1: return &SHT_SplitGT1Cooling[gasPathWidth];
	case 2: return &SHT_SplitGT2Cooling[0];
	case 3: return &SHT_SplitGT2Cooling[gasPathWidth];
	case 4: return &SHT_SplitPT1Cooling[0];
	case 5: return &SHT_SplitPT1Cooling[gasPathWidth];
	case 6: return &SHT_SplitPT2Cooling[0];
	case 7: return &SHT_SplitPT2Cooling[gasPathWidth];
	case 8: return &SHT_SplitPT2Cooling[2 * gasPathWidth];
	case 9: return &SHT_SplitLeakCooling[0];
	default: return NULL;
	}
}

static int SHT_ApplyVisserCoolingBranch(
	int branchIndex,
	int routeIndex,
	double branchFlow,
	double inletEnthalpy,
	double inletTemperature,
	double far,
	double *heatFlow)
{
	int targetType;
	int targetIndex;
	int componentIndex;
	double targetTemperature;
	double correction;
	double referenceBranchFlow;
	double flowRatio;
	double conductance;
	double lowerTemperature;
	double upperTemperature;
	double cp;
	double effectiveness;
	double outletEnthalpy;
	double outletTemperature;

	if (heatFlow == NULL || branchIndex < 0 ||
		branchIndex >= SHT_VISSER_COOLING_BRANCH_COUNT ||
		routeIndex < 0 || routeIndex >= SHT_PHYSICAL_COOLING_ROUTE_COUNT)
		return SHT_ERROR_PARAMETER_VALUE;
	*heatFlow = 0.0;
	targetType = SHT_CoolingTargetType[branchIndex];
	targetIndex = SHT_CoolingTargetForMode(branchIndex);
	componentIndex = SHT_CoolingBranchComponent[branchIndex];
	if (targetType == SHT_COOLING_TARGET_NONE || branchFlow <= DBL_MIN ||
		!SHT_IsVisserComponentSelected(componentIndex))
		return SHT_STATUS_OK;
	if (!_finite(branchFlow) || branchFlow < 0.0 ||
		!_finite(inletEnthalpy) || !_finite(inletTemperature) ||
		inletTemperature <= 1.0 || !_finite(far) || far < 0.0)
		return SHT_ERROR_HEAT_EVALUATION;

	if (targetType == SHT_COOLING_TARGET_METAL)
	{
		targetTemperature = SHT_GetVisserMetalTemperature(targetIndex);
		correction = Turboshaft.transientParameters.heatTimeCorrection[
			Turboshaft.modelMode == 0 ? (componentIndex <= 4 ? 2 : 3) : componentIndex];
	}
	else
	{
		targetTemperature =
			Turboshaft.transientState.diskTemperature[targetIndex];
		correction =
			Turboshaft.transientParameters.diskTimeCorrection[targetIndex];
	}
	/*
	 * 10路名义引气比例统一以整体HPC/AC进口流量为基准，不能再用
	 * 换热对象所属部件的主流量近似。第17支路位于第8、9路合流后，
	 * 其参考流量必须同时包含两路设计流量。
	 */
	if (branchIndex == 16)
		referenceBranchFlow =
			Turboshaft.transientParameters.referenceFlow[0] *
			(SHT_PhysicalBleedFraction[7] *
			 SHT_CoolingSplit.ratio[16] +
			 SHT_PhysicalBleedFraction[8] *
			 SHT_CoolingSplit.ratio[17]);
	else
		referenceBranchFlow =
			Turboshaft.transientParameters.referenceFlow[0] *
			SHT_PhysicalBleedFraction[routeIndex] *
			SHT_CoolingSplit.ratio[branchIndex];
	if (!_finite(targetTemperature) || targetTemperature <= 0.0 ||
		!_finite(referenceBranchFlow) || referenceBranchFlow <= 0.0 ||
		!_finite(correction) || 1.0 + correction <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	flowRatio = branchFlow / referenceBranchFlow;
	conductance =
		Turboshaft.transientParameters.visserCoolingConductance0[branchIndex] *
		pow(flowRatio, 0.8) / (1.0 + correction);
	if (!_finite(conductance) || conductance < 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	if (conductance <= DBL_MIN)
		return SHT_STATUS_OK;

	if (fabs(targetTemperature - inletTemperature) > 1.0e-6)
		cp = (t2hc(targetTemperature, far) - inletEnthalpy) /
			(targetTemperature - inletTemperature);
	else
	{
		lowerTemperature = fmax(1.0, inletTemperature - 0.5);
		upperTemperature = inletTemperature + 0.5;
		cp = (t2hc(upperTemperature, far) -
			t2hc(lowerTemperature, far)) /
			(upperTemperature - lowerTemperature);
	}
	if (!_finite(cp) || cp <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	effectiveness = 1.0 - exp(-conductance / (branchFlow * cp));
	outletTemperature = inletTemperature + effectiveness *
		(targetTemperature - inletTemperature);
	outletEnthalpy = t2hc(outletTemperature, far);
	*heatFlow = branchFlow * (outletEnthalpy - inletEnthalpy);
	if (!_finite(*heatFlow) || !_finite(outletTemperature) ||
		outletTemperature <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	return SHT_STATUS_OK;
}

static int SHT_ApplyVisserParallelRoute(int routeIndex)
{
	double *stream = SHT_GetSplitCoolingStream(routeIndex);
	double totalHeatFlow = 0.0;
	double outletEnthalpy;
	double outletTemperature;
	int start;
	int count;
	int localIndex;
	if (stream == NULL || stream[0] < 0.0 || !_finite(stream[0]))
		return SHT_ERROR_HEAT_EVALUATION;
	SHT_VisserCoolingEvaluation.routeInletTemperature[routeIndex] = stream[2];
	start = SHT_CoolingBranchStart[routeIndex];
	count = SHT_CoolingBranchCount[routeIndex];
	for (localIndex = 0; localIndex < count; ++localIndex)
	{
		int branchIndex = start + localIndex;
		double branchHeatFlow = 0.0;
		int status = SHT_ApplyVisserCoolingBranch(
			branchIndex, routeIndex,
			stream[0] * SHT_CoolingSplit.ratio[branchIndex],
			stream[1], stream[2], stream[4], &branchHeatFlow);
		if (status != SHT_STATUS_OK) return status;
		SHT_VisserCoolingEvaluation.branchHeatFlow[branchIndex] =
			branchHeatFlow;
		totalHeatFlow += branchHeatFlow;
		if (SHT_CoolingTargetType[branchIndex] == SHT_COOLING_TARGET_METAL)
			SHT_VisserCoolingEvaluation.metalHeatFlow[
				SHT_CoolingTargetForMode(branchIndex)] += branchHeatFlow;
		else if (SHT_CoolingTargetType[branchIndex] == SHT_COOLING_TARGET_DISK)
			SHT_VisserCoolingEvaluation.diskHeatFlow[
				SHT_CoolingTargetForMode(branchIndex)] += branchHeatFlow;
	}
	if (stream[0] > DBL_MIN)
	{
		outletEnthalpy = stream[1] + totalHeatFlow / stream[0];
		outletTemperature = h2tc(outletEnthalpy, stream[4]);
	}
	else
	{
		outletEnthalpy = stream[1];
		outletTemperature = stream[2];
	}
	if (!_finite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	SHT_VisserCoolingEvaluation.routeOutletTemperature[routeIndex] =
		outletTemperature;
	if (Turboshaft.transientControl.heatFeedbackEnable)
	{
		stream[1] = outletEnthalpy;
		stream[2] = outletTemperature;
	}
	return SHT_STATUS_OK;
}

static int SHT_ApplyVisserCoolingNetwork(void)
{
	double *route8;
	double *route9;
	double route9Heat = 0.0;
	double route9OutletEnthalpy;
	double route9OutletTemperature;
	double combinedFlow;
	double combinedEnthalpy;
	double combinedFAR;
	double combinedTemperature;
	double combinedHeat = 0.0;
	double finalEnthalpy;
	double finalTemperature;
	int routeIndex;
	int status;

	memset(&SHT_VisserCoolingEvaluation, 0,
		sizeof(SHT_VisserCoolingEvaluation));
	if (SHT_GetCoolingSplitStatus() != SHT_STATUS_OK)
		return SHT_ERROR_COOLING_SPLIT_NOT_INITIALIZED;
	for (routeIndex = 0; routeIndex <= 6; ++routeIndex)
	{
		status = SHT_ApplyVisserParallelRoute(routeIndex);
		if (status != SHT_STATUS_OK) return status;
	}

	/* 第9路先冷却GT2盘，再与第8路混合，合流后共同冷却PT2盘。 */
	route8 = SHT_GetSplitCoolingStream(7);
	route9 = SHT_GetSplitCoolingStream(8);
	if (route8 == NULL || route9 == NULL || route8[0] < 0.0 || route9[0] < 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	SHT_VisserCoolingEvaluation.routeInletTemperature[7] = route8[2];
	SHT_VisserCoolingEvaluation.routeInletTemperature[8] = route9[2];
	status = SHT_ApplyVisserCoolingBranch(17, 8, route9[0],
		route9[1], route9[2], route9[4], &route9Heat);
	if (status != SHT_STATUS_OK) return status;
	SHT_VisserCoolingEvaluation.branchHeatFlow[17] = route9Heat;
	SHT_VisserCoolingEvaluation.diskHeatFlow[Turboshaft.modelMode == 0 ? 1 : 3] += route9Heat;
	route9OutletEnthalpy = route9[0] > DBL_MIN ?
		route9[1] + route9Heat / route9[0] : route9[1];
	route9OutletTemperature = h2tc(route9OutletEnthalpy, route9[4]);
	combinedFlow = route8[0] + route9[0];
	if (combinedFlow <= DBL_MIN)
		return SHT_ERROR_HEAT_EVALUATION;
	combinedEnthalpy = (route8[0] * route8[1] +
		route9[0] * route9OutletEnthalpy) / combinedFlow;
	combinedFAR = (route8[0] * route8[4] + route9[0] * route9[4]) /
		combinedFlow;
	combinedTemperature = h2tc(combinedEnthalpy, combinedFAR);
	status = SHT_ApplyVisserCoolingBranch(16, 7, combinedFlow,
		combinedEnthalpy, combinedTemperature, combinedFAR, &combinedHeat);
	if (status != SHT_STATUS_OK) return status;
	SHT_VisserCoolingEvaluation.branchHeatFlow[16] = combinedHeat;
	SHT_VisserCoolingEvaluation.diskHeatFlow[Turboshaft.modelMode == 0 ? 2 : 5] += combinedHeat;
	finalEnthalpy = combinedEnthalpy + combinedHeat / combinedFlow;
	finalTemperature = h2tc(finalEnthalpy, combinedFAR);
	if (!_finite(route9OutletTemperature) || route9OutletTemperature <= 0.0 ||
		!_finite(finalTemperature) || finalTemperature <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	SHT_VisserCoolingEvaluation.routeOutletTemperature[7] = finalTemperature;
	SHT_VisserCoolingEvaluation.routeOutletTemperature[8] = finalTemperature;
	if (Turboshaft.transientControl.heatFeedbackEnable)
	{
		/* 三部件仅回灌换热焓增量，避免改变原14支路等效掺混定义。 */
		if (Turboshaft.modelMode == 0)
		{
			route8[1] += combinedHeat / combinedFlow;
			route9[1] = route9OutletEnthalpy + combinedHeat / combinedFlow;
			route8[2] = h2tc(route8[1], route8[4]);
			route9[2] = h2tc(route9[1], route9[4]);
		}
		else
		{
		route8[1] = finalEnthalpy;
		route8[2] = finalTemperature;
		route8[4] = combinedFAR;
		route9[1] = finalEnthalpy;
		route9[2] = finalTemperature;
		route9[4] = combinedFAR;
		}
	}
	/* 第10路只泄漏、不冷却金属；仍走并联通用函数形成完整诊断。 */
	status = SHT_ApplyVisserParallelRoute(9);
	if (status != SHT_STATUS_OK) return status;
	SHT_VisserCoolingEvaluation.valid = 1;
	return SHT_STATUS_OK;
}

/*
 * 三部件仍以历史14支路供给总体涡轮。先按物理编号合并计算冷却换热，
 * 再向各等效支路施加相同的比焓增量。质量、压力及原始状态不被改写。
 */
static int SHT_PrepareLegacyCoolingFlows(void)
{
	static double cooling[14 * gasPathWidth];
	double inletEnthalpy[10];
	double *source = Turboshaft.HPT.extSecAirSys > 0.5 ?
		Turboshaft.HPC.customerBleeds : Turboshaft.HPC.fractionalBleeds;
	int route, i, status;
	Turboshaft.HPT.coolingFlow = Turboshaft.HPC.fractionalBleeds;
	Turboshaft.HPT.extCoolingFlow = Turboshaft.HPC.customerBleeds;
	Turboshaft.LPT.coolingFlow = &Turboshaft.HPC.fractionalBleeds[(int)Turboshaft.HPT.coolingFlowWidth];
	Turboshaft.LPT.extCoolingFlow = &Turboshaft.HPC.customerBleeds[(int)Turboshaft.HPT.coolingFlowWidth];
	memset(&SHT_VisserCoolingEvaluation, 0, sizeof(SHT_VisserCoolingEvaluation));
	if (!Turboshaft.transientControl.heatStateEnable ||
		Turboshaft.transientControl.thermalModelMode != SHT_THERMAL_MODEL_VISSER)
		return SHT_STATUS_OK;
	for (route = 0; route < 10; ++route)
	{
		double *p = SHT_GetSplitCoolingStream(route);
		memset(p, 0, gasPathWidth * sizeof(double));
		for (i = 0; i < 14; ++i)
		{
			const double *s = source + i * gasPathWidth;
			if (SHT_LegacyBleedPhysicalIndex[i] != route) continue;
			p[0] += s[0];
			p[1] += s[0] * s[1];
			p[4] += s[0] * s[4];
			p[3] = s[3];
			p[2] = s[2];
		}
		if (p[0] > DBL_MIN)
		{
			p[1] /= p[0]; p[4] /= p[0];
			p[2] = h2tc(p[1], p[4]);
		}
		else p[1] = t2hc(p[2], p[4]);
		inletEnthalpy[route] = p[1];
	}
	status = SHT_ApplyVisserCoolingNetwork();
	if (status != SHT_STATUS_OK) return status;
	memcpy(cooling, source, sizeof(cooling));
	for (i = 0; i < 14; ++i)
	{
		double *s = cooling + i * gasPathWidth;
		route = SHT_LegacyBleedPhysicalIndex[i];
		s[1] += SHT_GetSplitCoolingStream(route)[1] - inletEnthalpy[route];
		s[2] = h2tc(s[1], s[4]);
	}
	Turboshaft.HPT.coolingFlow = cooling;
	Turboshaft.HPT.extCoolingFlow = cooling;
	Turboshaft.LPT.coolingFlow = cooling + (int)Turboshaft.HPT.coolingFlowWidth;
	Turboshaft.LPT.extCoolingFlow = Turboshaft.LPT.coolingFlow;
	return SHT_STATUS_OK;
}

static int SHT_PrepareSplitCoolingFlows(int useExternalBleed)
{
	int status;

	/* GT1：CC物理口1进级前；物理口2（原2+4）在级后掺混。 */
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitGT1Cooling[0], &Turboshaft.HPC2, 0,
		SHT_CentrifugalBleedIndex[0], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitGT1Cooling[gasPathWidth], &Turboshaft.HPC2, 1,
		SHT_CentrifugalBleedIndex[1], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;

	/* GT2：CC物理口3（原3+5）进级前；物理口4在级后掺混。 */
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitGT2Cooling[0], &Turboshaft.HPC2, 2,
		SHT_CentrifugalBleedIndex[2], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitGT2Cooling[gasPathWidth], &Turboshaft.HPC2, 3,
		SHT_CentrifugalBleedIndex[3], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;

	/* PT1：AC物理口1进级前；物理口2（原8+10）在级后掺混。 */
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitPT1Cooling[0], &Turboshaft.HPC, 0,
		SHT_AxialBleedIndex[0], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitPT1Cooling[gasPathWidth], &Turboshaft.HPC, 1,
		SHT_AxialBleedIndex[1], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;

	/* PT2：AC物理口3（原9+11）进级前；AC口4与CC口5在级后。 */
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitPT2Cooling[0], &Turboshaft.HPC, 2,
		SHT_AxialBleedIndex[2], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitPT2Cooling[gasPathWidth], &Turboshaft.HPC, 3,
		SHT_AxialBleedIndex[3], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitPT2Cooling[2 * gasPathWidth], &Turboshaft.HPC2, 4,
		SHT_CentrifugalBleedIndex[4], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_GetPhysicalCoolingStream(
		&SHT_SplitLeakCooling[0], &Turboshaft.HPC, 4,
		SHT_AxialBleedIndex[4], useExternalBleed);
	if (status != SHT_STATUS_OK) return status;
	if (Turboshaft.transientControl.thermalModelMode ==
		SHT_THERMAL_MODEL_VISSER &&
		Turboshaft.transientControl.heatStateEnable)
		return SHT_ApplyVisserCoolingNetwork();
	memset(&SHT_VisserCoolingEvaluation, 0,
		sizeof(SHT_VisserCoolingEvaluation));
	return SHT_STATUS_OK;
}

/*
 * HPC 间隙反馈或外部空气系统启用时建立局部浅副本。
 *
 * 外部空气系统通过 customerBleeds 传入每条支路的
 * [流量、焓、总温、总压、油气比]。HPC 只使用其中的绝对流量：
 * 先除以本次 HPC 进口流量，得到压气机核心所需的临时分数引气比例；
 * 同时把 hpWbld 临时置零，避免在外部绝对流量上再次施加流量修正。
 * customerBleeds 本身不改写，GT/PT 仍可读取外部系统给出的完整状态。
 *
 * 所有临时数组和指针均只在本次调用中有效，调用结束前恢复原指针，
 * 因而不会改变公开结构体布局，也不会在 Newton 重复调用或模式切换时累积。
 */
static int SHT_RunCompressorMapWithClearance(
	CompressorBlock *compressor,
	int clearanceComponentIndex)
{
	double reynoldsFlowMultiplier = 1.0;
	double reynoldsEfficiencyMultiplier = 1.0;
	double clearanceFlowMultiplier = 1.0;
	double clearanceEfficiencyMultiplier = 1.0;
	double effectiveHpW;
	double effectiveHpEf;
	double *originalHpW;
	double *originalHpEf;
	int status;

	status = SHT_EvaluateReynoldsCorrection(
		clearanceComponentIndex,
		compressor->gasPathIn[2],
		compressor->gasPathIn[3],
		&reynoldsFlowMultiplier,
		&reynoldsEfficiencyMultiplier);
	if (status != SHT_STATUS_OK)
		return status;
	if (SHT_IsClearanceFeedbackSelected(clearanceComponentIndex))
	{
		clearanceFlowMultiplier = Turboshaft.transientClearanceEvaluation
			.flowMultiplier[clearanceComponentIndex];
		clearanceEfficiencyMultiplier =
			Turboshaft.transientClearanceEvaluation
				.efficiencyMultiplier[clearanceComponentIndex];
	}
	if (reynoldsFlowMultiplier == 1.0 &&
		reynoldsEfficiencyMultiplier == 1.0 &&
		clearanceFlowMultiplier == 1.0 &&
		clearanceEfficiencyMultiplier == 1.0)
		return compressorRun(compressor);
	effectiveHpW = (1.0 + *compressor->hpW) *
		reynoldsFlowMultiplier * clearanceFlowMultiplier - 1.0;
	effectiveHpEf = (1.0 + *compressor->hpEf) *
		reynoldsEfficiencyMultiplier * clearanceEfficiencyMultiplier - 1.0;
	originalHpW = compressor->hpW;
	originalHpEf = compressor->hpEf;
	compressor->hpW = &effectiveHpW;
	compressor->hpEf = &effectiveHpEf;
	status = compressorRun(compressor);
	compressor->hpW = originalHpW;
	compressor->hpEf = originalHpEf;
	return status;
}

static int SHT_RunClearanceAdjustedCompressorCore(
	CompressorBlock *compressor,
	int clearanceComponentIndex)
{
	double effectiveFractionalBleedsDemand[500];
	double zeroBleedFlowHealth[500];
	double inletFlow;
	double totalExternalBleedFlow = 0.0;
	int fractionalBleedCount;
	int useClearanceFeedback;
	int useExternalBleedFlow;
	int useReynoldsCorrection;
	int i;
	int status;
	double *originalFractionalBleedsDemand;
	double *originalHpWbld;

	useClearanceFeedback =
		SHT_IsClearanceFeedbackSelected(clearanceComponentIndex);
	useExternalBleedFlow = Turboshaft.HPT.extSecAirSys > 0.5;
	/* RNI与间隙/外部引气独立。未配置时保留原来的快速调用路径。 */
	useReynoldsCorrection = SHT_ReynoldsCorrection.configured &&
		clearanceComponentIndex >= 0 &&
		clearanceComponentIndex < SHT_REYNOLDS_COMPONENT_COUNT &&
		SHT_ReynoldsCorrection.component[clearanceComponentIndex].enabled;
	if (!useClearanceFeedback && !useExternalBleedFlow && !useReynoldsCorrection)
		return compressorRun(compressor);

	if (useExternalBleedFlow)
	{
		fractionalBleedCount =
			(int)(compressor->compressorStruct.FracBldNm);
		inletFlow = compressor->gasPathIn[0];
		if (fractionalBleedCount < 0 || fractionalBleedCount > 500 ||
			!_finite(inletFlow) || inletFlow <= 0.0)
			return SHT_SetExternalBleedInputError();

		for (i = 0; i < fractionalBleedCount; i++)
		{
			double externalBleedFlow =
				compressor->customerBleeds[gasPathWidth * i];
			if (!_finite(externalBleedFlow) || externalBleedFlow < 0.0)
				return SHT_SetExternalBleedInputError();

			totalExternalBleedFlow += externalBleedFlow;
			effectiveFractionalBleedsDemand[i] =
				externalBleedFlow / inletFlow;
			zeroBleedFlowHealth[i] = 0.0;
		}

		if (!_finite(totalExternalBleedFlow) ||
			totalExternalBleedFlow >= inletFlow)
			return SHT_SetExternalBleedInputError();

	}

	originalFractionalBleedsDemand = compressor->fractionalBleedsDemand;
	originalHpWbld = compressor->hpWbld;
	if (useExternalBleedFlow)
	{
		compressor->fractionalBleedsDemand = effectiveFractionalBleedsDemand;
		compressor->hpWbld = zeroBleedFlowHealth;
	}

	status = SHT_RunCompressorMapWithClearance(
		compressor, clearanceComponentIndex);

	/* 无论部件计算是否成功，均恢复配置期分配的长期指针。 */
	compressor->fractionalBleedsDemand = originalFractionalBleedsDemand;
	compressor->hpWbld = originalHpWbld;
	return status;
}

typedef struct SHTCompressorHeatRootContext {
	int componentIndex;
	double inletFlow;
	double inletTemperature;
	double pressureRatio;
	double adiabaticExponent;
	double adiabaticSpecificWork;
	double heatTimeCorrection;
} SHTCompressorHeatRootContext;

/*
 * 计算压气机非绝热出口温度方程 F(T)-T。该函数只做纯求值，不改变
 * 部件输出；快速定点迭代失稳时，后备有界求根器复用同一个物理方程。
 */
static int SHT_EvaluateCompressorHeatRootResidual(
	const SHTCompressorHeatRootContext *context,
	double candidateTemperature,
	double *residual)
{
	double totalHeatFlow = 0.0;
	double specificHeatFlow;
	double predictedTemperature;
	int status;

	if (context == NULL || residual == NULL ||
		!_finite(candidateTemperature) || candidateTemperature <= 0.0)
		return SHT_ERROR_HEAT_FEEDBACK;
	status = SHT_EvaluateLocalHeat(context->componentIndex,
		context->inletFlow, context->inletTemperature, candidateTemperature,
		context->heatTimeCorrection, &totalHeatFlow);
	if (status != SHT_STATUS_OK)
		return status;
	specificHeatFlow = totalHeatFlow / context->inletFlow;
	predictedTemperature = context->inletTemperature * pow(
		context->pressureRatio,
		context->adiabaticExponent *
		(1.0 - specificHeatFlow / context->adiabaticSpecificWork));
	if (!_finite(predictedTemperature) || predictedTemperature <= 0.0)
		return SHT_ERROR_HEAT_FEEDBACK;
	*residual = predictedTemperature - candidateTemperature;
	return SHT_STATUS_OK;
}

/*
 * 有界二分只在原定点迭代未收敛时启用。先围绕绝热出口温度逐级扩展
 * 温度区间，再对同一能量平衡残差求根；不引入热流削弱、低流量关断
 * 或特性图重调。50～5000 K 是本模型物性函数的工程有效保护区间。
 */
static int SHT_SolveCompressorHeatRootFallback(
	const SHTCompressorHeatRootContext *context,
	double adiabaticTemperature,
	double *solutionTemperature,
	double *solutionResidual,
	int *iterationCount)
{
	const double minimumTemperature = 50.0;
	const double maximumTemperature = 5000.0;
	double centerTemperature = adiabaticTemperature;
	double centerResidual = 0.0;
	double lowerTemperature = centerTemperature;
	double upperTemperature = centerTemperature;
	double lowerResidual = 0.0;
	double upperResidual = 0.0;
	double trialTemperature;
	double trialResidual;
	double tolerance;
	int expansion;
	int iteration;
	int status;
	int bracketed = 0;

	if (context == NULL || solutionTemperature == NULL ||
		solutionResidual == NULL || iterationCount == NULL ||
		!_finite(adiabaticTemperature) || adiabaticTemperature <= 0.0)
		return SHT_ERROR_HEAT_FEEDBACK;
	centerTemperature = fmin(fmax(centerTemperature,
		minimumTemperature), maximumTemperature);
	status = SHT_EvaluateCompressorHeatRootResidual(
		context, centerTemperature, &centerResidual);
	if (status != SHT_STATUS_OK)
		return status;
	tolerance = SHT_HEAT_FEEDBACK_TEMPERATURE_TOL *
		fmax(1.0, fabs(centerTemperature));
	if (fabs(centerResidual) <= tolerance)
	{
		*solutionTemperature = centerTemperature;
		*solutionResidual = centerResidual;
		*iterationCount = 1;
		return SHT_STATUS_OK;
	}

	for (expansion = 1; expansion <= 18 && !bracketed; ++expansion)
	{
		double scale = pow(1.35, (double)expansion);
		trialTemperature = fmax(minimumTemperature,
			centerTemperature / scale);
		status = SHT_EvaluateCompressorHeatRootResidual(
			context, trialTemperature, &trialResidual);
		if (status == SHT_STATUS_OK)
		{
			lowerTemperature = trialTemperature;
			lowerResidual = trialResidual;
			if (lowerResidual * centerResidual <= 0.0)
			{
				upperTemperature = centerTemperature;
				upperResidual = centerResidual;
				bracketed = 1;
				break;
			}
		}

		trialTemperature = fmin(maximumTemperature,
			centerTemperature * scale);
		status = SHT_EvaluateCompressorHeatRootResidual(
			context, trialTemperature, &trialResidual);
		if (status == SHT_STATUS_OK)
		{
			upperTemperature = trialTemperature;
			upperResidual = trialResidual;
			if (centerResidual * upperResidual <= 0.0)
			{
				lowerTemperature = centerTemperature;
				lowerResidual = centerResidual;
				bracketed = 1;
				break;
			}
			if (lowerTemperature < centerTemperature &&
				lowerResidual * upperResidual <= 0.0)
			{
				bracketed = 1;
				break;
			}
		}
	}
	if (!bracketed)
		return SHT_ERROR_HEAT_FEEDBACK;

	for (iteration = 1; iteration <= 60; ++iteration)
	{
		trialTemperature = 0.5 *
			(lowerTemperature + upperTemperature);
		status = SHT_EvaluateCompressorHeatRootResidual(
			context, trialTemperature, &trialResidual);
		if (status != SHT_STATUS_OK)
			return status;
		tolerance = SHT_HEAT_FEEDBACK_TEMPERATURE_TOL *
			fmax(1.0, fabs(trialTemperature));
		if (fabs(trialResidual) <= tolerance ||
			upperTemperature - lowerTemperature <= tolerance)
		{
			*solutionTemperature = trialTemperature;
			*solutionResidual = trialResidual;
			*iterationCount = expansion + iteration;
			return SHT_STATUS_OK;
		}
		if (lowerResidual * trialResidual <= 0.0)
		{
			upperTemperature = trialTemperature;
			upperResidual = trialResidual;
		}
		else
		{
			lowerTemperature = trialTemperature;
			lowerResidual = trialResidual;
		}
	}
	*solutionTemperature = trialTemperature;
	*solutionResidual = trialResidual;
	*iterationCount = expansion + 60;
	return SHT_ERROR_HEAT_FEEDBACK;
}

/*
 * HPC：先求含间隙倍率的原特性图结果，再按 Kurzke 非绝热压缩关系求
 * 实际出口温度，并同步主流、分数引气焓以及轴功率。
 */
static int SHT_ApplyTransientCompressorHeat(
	CompressorBlock *compressor,
	int componentIndex,
	int componentBit,
	double heatTimeCorrection)
{
	int status = SHT_STATUS_OK;
	int iteration;
	int converged = 0;
	int i;
	double inletFlow;
	double inletTemperature;
	double inletFAR;
	double inletEnthalpy;
	double adiabaticEnthalpy;
	double adiabaticTemperature;
	double adiabaticSpecificWork;
	double pressureRatio;
	double adiabaticExponent;
	double outletTemperature;
	double nextTemperature = 0.0;
	double outletEnthalpy;
	double totalHeatFlow = 0.0;
	double specificHeatFlow;
	double gasSpecificWork;
	double shaftSpecificWork;
	double powerBeforeBleed;
	double bleedPower;
	double shaftPower;
	double omega;
	double residual = 0.0;
	double tolerance;
	double energyResidual;
	SHTCompressorHeatRootContext rootContext;
	int fallbackIterationCount = 0;

	if (!SHT_IsHeatFeedbackSelected(componentBit))
		return status;

	inletFlow = compressor->gasPathIn[0];
	inletTemperature = compressor->gasPathIn[2];
	inletFAR = compressor->gasPathIn[4];
	inletEnthalpy = t2hc(inletTemperature, inletFAR);
	adiabaticEnthalpy = compressor->y[1];
	adiabaticTemperature = compressor->y[2];
	pressureRatio = compressor->y[14];
	adiabaticSpecificWork = adiabaticEnthalpy - inletEnthalpy;
	if (!_finite(inletFlow) || inletFlow <= 0.0 ||
		!_finite(inletTemperature) || inletTemperature <= 0.0 ||
		!_finite(adiabaticTemperature) || adiabaticTemperature <= 0.0 ||
		!_finite(pressureRatio) || !_finite(adiabaticSpecificWork))
		return SHT_SetHeatFeedbackFailure(componentIndex, 0,
			adiabaticSpecificWork, SHT_STATUS_OK);
	/*
	 * 低速Newton的有限差分试探点可能暂时落入PR<=1或负绝热比功区。
	 * 此时“非绝热压缩”关系没有定义，但原部件试探值仍可用于构造气路
	 * Jacobian。迭代次数0明确标识本次旁路；接受解回到正压缩区后自动
	 * 恢复热反馈，避免以一次非物理差分点中断整个连续停车过程。
	 */
	if (pressureRatio <= 1.0 || adiabaticSpecificWork <= 0.0)
	{
		if (!SHT_LowSpeedResidualScalingActive)
			return SHT_SetHeatFeedbackFailure(componentIndex, 0,
				adiabaticSpecificWork, SHT_STATUS_OK);
		SHT_RecordHeatFeedbackSuccess(componentIndex, 0, 0.0, 0.0);
		return status;
	}

	adiabaticExponent = log(adiabaticTemperature / inletTemperature) /
		log(pressureRatio);
	outletTemperature = adiabaticTemperature;
	for (iteration = 1; iteration <= SHT_HEAT_FEEDBACK_MAX_ITERATIONS; ++iteration)
	{
		status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
			inletTemperature, outletTemperature, heatTimeCorrection,
			&totalHeatFlow);
		if (status != SHT_STATUS_OK)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				residual, status);
		/* 热流严格为零时保持原压气机输出和引气数组逐位不变。 */
		if (totalHeatFlow == 0.0)
		{
			SHT_RecordHeatFeedbackSuccess(componentIndex, iteration, 0.0, 0.0);
			return SHT_STATUS_OK;
		}

		specificHeatFlow = totalHeatFlow / inletFlow;
		nextTemperature = inletTemperature * pow(pressureRatio,
			adiabaticExponent *
			(1.0 - specificHeatFlow / adiabaticSpecificWork));
		if (!_finite(nextTemperature) || nextTemperature <= 0.0)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				nextTemperature, SHT_STATUS_OK);

		residual = nextTemperature - outletTemperature;
		outletTemperature = nextTemperature;
		tolerance = SHT_HEAT_FEEDBACK_TEMPERATURE_TOL *
			fmax(1.0, fabs(outletTemperature));
		if (fabs(residual) <= tolerance)
		{
			converged = 1;
			break;
		}
	}
	if (!converged)
	{
		if (!SHT_LowSpeedResidualScalingActive)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration - 1,
				residual, SHT_STATUS_OK);
		rootContext.componentIndex = componentIndex;
		rootContext.inletFlow = inletFlow;
		rootContext.inletTemperature = inletTemperature;
		rootContext.pressureRatio = pressureRatio;
		rootContext.adiabaticExponent = adiabaticExponent;
		rootContext.adiabaticSpecificWork = adiabaticSpecificWork;
		rootContext.heatTimeCorrection = heatTimeCorrection;
		status = SHT_SolveCompressorHeatRootFallback(&rootContext,
			adiabaticTemperature, &outletTemperature, &residual,
			&fallbackIterationCount);
		iteration = SHT_HEAT_FEEDBACK_MAX_ITERATIONS +
			fallbackIterationCount;
		if (status != SHT_STATUS_OK)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				residual, status);
		converged = 1;
	}

	status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
		inletTemperature, outletTemperature, heatTimeCorrection,
		&totalHeatFlow);
	if (status != SHT_STATUS_OK)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
			residual, status);
	specificHeatFlow = totalHeatFlow / inletFlow;
	nextTemperature = inletTemperature * pow(pressureRatio,
		adiabaticExponent *
		(1.0 - specificHeatFlow / adiabaticSpecificWork));
	residual = nextTemperature - outletTemperature;
	outletTemperature = nextTemperature;
	outletEnthalpy = t2hc(outletTemperature, inletFAR);
	gasSpecificWork = outletEnthalpy - inletEnthalpy;
	shaftSpecificWork = gasSpecificWork + specificHeatFlow;
	powerBeforeBleed = -inletFlow * shaftSpecificWork;
	bleedPower = 0.0;

	if (compressor->compressorStruct.CustBldEn > 0.5 &&
		compressor->customerBleedsDemand != 0)
	{
		for (i = 0; i < compressor->compressorStruct.CustBldNm; ++i)
		{
			double customerFlow = compressor->customerBleedsDemand[i];
			if (customerFlow != 0.0)
			{
				double customerEnthalpy = inletEnthalpy +
					compressor->compressorStruct.FracCusBldht[i] *
					(outletEnthalpy - inletEnthalpy);
				bleedPower += customerFlow * (customerEnthalpy - outletEnthalpy);
			}
		}
	}
	if (compressor->compressorStruct.FBldEn > 0.5)
	{
		for (i = 0; i < compressor->compressorStruct.FracBldNm; ++i)
		{
			double bleedFlow = compressor->fractionalBleeds[5 * i];
			if (bleedFlow > 0.0)
			{
				double bleedFraction = compressor->compressorStruct.FracBldht[i] +
					compressor->hpBldht[i];
				double bleedEnthalpy = inletEnthalpy + bleedFraction *
					(outletEnthalpy - inletEnthalpy);
				compressor->fractionalBleeds[5 * i + 1] = bleedEnthalpy;
				compressor->fractionalBleeds[5 * i + 2] = h2tc(bleedEnthalpy, inletFAR);
				bleedPower += bleedFlow * (bleedEnthalpy - outletEnthalpy);
			}
		}
	}

	shaftPower = powerBeforeBleed - bleedPower;
	omega = *compressor->nMech > 10.0 ?
		*compressor->nMech * PI / 30.0 : 10.0 * PI / 30.0;
	compressor->y[1] = outletEnthalpy;
	compressor->y[2] = outletTemperature;
	compressor->y[5] = shaftPower / omega;
	compressor->y[21] = powerBeforeBleed;
	compressor->y[22] = bleedPower;
	compressor->y[23] = shaftPower;
	energyResidual = -shaftPower -
		(inletFlow * gasSpecificWork + bleedPower + totalHeatFlow);
	SHT_RecordHeatFeedbackSuccess(componentIndex, iteration,
		residual, energyResidual);
	return SHT_STATUS_OK;
}

/* 复算涡轮前端/出口冷却流混合量，定义与 Turbine_TMATS_body 完全一致。 */
static int SHT_GetTurbineCoolingTerms(
	TurbineBlock *turbine,
	double *stageOneFlow,
	double *stageOneFAR,
	double *stageOneEnthalpy,
	double *rearCoolingEnthalpyFlow,
	double *outletFlow)
{
	const double *coolingFlow = turbine->extSecAirSys < 0.5 ?
		turbine->coolingFlow : turbine->extCoolingFlow;
	int coolingCount = (int)(turbine->coolingFlowWidth / 5.0);
	int i;
	double inletFlow = turbine->gasPathIn[0];
	double inletTemperature = turbine->gasPathIn[2];
	double inletFAR = turbine->gasPathIn[4];
	double frontFlow = 0.0;
	double totalCoolingFlow = 0.0;
	double frontFuelFlow = 0.0;
	double frontEnthalpyFlow = 0.0;
	double rearEnthalpyFlow = 0.0;

	if (coolingCount < 0 || coolingCount > 100 ||
		5 * coolingCount != (int)turbine->coolingFlowWidth)
		return SHT_ERROR_HEAT_FEEDBACK;
	for (i = 0; i < coolingCount; ++i)
	{
		double position;
		double flow;
		double temperature;
		double far;
		double enthalpy;
		if (turbine->turbineStruct.CoolFlwEn < 0.5)
			continue;
		position = turbine->turbineStruct.T_BldPos[i];
		flow = coolingFlow[5 * i];
		temperature = coolingFlow[5 * i + 2];
		far = coolingFlow[5 * i + 4];
		enthalpy = t2hc(temperature, far);
		frontFlow += flow * (1.0 - position);
		totalCoolingFlow += flow;
		frontFuelFlow += far * flow * (1.0 - position) / (1.0 + far);
		frontEnthalpyFlow += enthalpy * flow * (1.0 - position);
		rearEnthalpyFlow += enthalpy * flow * position;
	}

	*stageOneFlow = inletFlow + frontFlow;
	*outletFlow = inletFlow + totalCoolingFlow;
	if (inletFlow > 0.0)
	{
		*stageOneFAR = (inletFAR * inletFlow / (1.0 + inletFAR) +
			frontFuelFlow) /
			(inletFlow / (1.0 + inletFAR) + frontFlow - frontFuelFlow);
	}
	else
		*stageOneFAR = 0.0;
	if (*stageOneFlow > 0.0)
	{
		*stageOneEnthalpy = (t2hc(inletTemperature, inletFAR) * inletFlow +
			frontEnthalpyFlow) / *stageOneFlow;
	}
	else
		*stageOneEnthalpy = t2hc(inletTemperature, inletFAR);
	*rearCoolingEnthalpyFlow = rearEnthalpyFlow;
	return SHT_STATUS_OK;
}

/*
 * GT/PT 间隙反馈只修正效率，不改变涡轮流量；RNI修正则可同时作用于
 * 流量和效率。三部件模式的间隙索引为GT=1、PT=2，六部件模式的
 * RNI/间隙索引按GT1、GT2、PT1、PT2分别为2、3、4、5。
 */
static int SHT_RunClearanceAdjustedTurbineCore(
	TurbineBlock *turbine,
	int clearanceComponentIndex)
{
	double reynoldsFlowMultiplier = 1.0;
	double reynoldsEfficiencyMultiplier = 1.0;
	double clearanceEfficiencyMultiplier = 1.0;
	double stageOneFlow;
	double stageOneFAR;
	double stageOneEnthalpy;
	double rearCoolingEnthalpyFlow;
	double outletFlow;
	double stageOneTemperature;
	double stageOnePressure;
	double effectiveHpW;
	double effectiveHpEf;
	double *originalHpW;
	double *originalHpEf;
	int status;

	if (SHT_ReynoldsCorrection.configured &&
		clearanceComponentIndex >= 0 &&
		clearanceComponentIndex < SHT_REYNOLDS_COMPONENT_COUNT &&
		SHT_ReynoldsCorrection.component[clearanceComponentIndex].enabled)
	{
		status = SHT_GetTurbineCoolingTerms(turbine,
			&stageOneFlow, &stageOneFAR, &stageOneEnthalpy,
			&rearCoolingEnthalpyFlow, &outletFlow);
		if (status != SHT_STATUS_OK)
			return status;
		stageOneTemperature = h2tc(stageOneEnthalpy, stageOneFAR);
		stageOnePressure = turbine->gasPathIn[3];
		status = SHT_EvaluateReynoldsCorrection(
			clearanceComponentIndex, stageOneTemperature, stageOnePressure,
			&reynoldsFlowMultiplier, &reynoldsEfficiencyMultiplier);
		if (status != SHT_STATUS_OK)
			return status;
	}
	if (SHT_IsClearanceFeedbackSelected(clearanceComponentIndex))
		clearanceEfficiencyMultiplier =
			Turboshaft.transientClearanceEvaluation
				.efficiencyMultiplier[clearanceComponentIndex];
	if (reynoldsFlowMultiplier == 1.0 &&
		reynoldsEfficiencyMultiplier == 1.0 &&
		clearanceEfficiencyMultiplier == 1.0)
		return turbineRun(turbine);

	effectiveHpW = (1.0 + *turbine->hpW) *
		reynoldsFlowMultiplier - 1.0;
	effectiveHpEf = (1.0 + *turbine->hpEf) *
		reynoldsEfficiencyMultiplier * clearanceEfficiencyMultiplier - 1.0;
	originalHpW = turbine->hpW;
	originalHpEf = turbine->hpEf;
	turbine->hpW = &effectiveHpW;
	turbine->hpEf = &effectiveHpEf;
	status = turbineRun(turbine);
	turbine->hpW = originalHpW;
	turbine->hpEf = originalHpEf;
	return status;
}

/*
 * GT/PT：先求含间隙效率倍率的特性图结果，再按 Kurzke 的“膨胀前一半、
 * 膨胀后一半”规则重算焓降和轴功率，最后沿用原冷却流混合。
 */
static int SHT_RunTransientTurbine(
	TurbineBlock *turbine,
	int componentIndex,
	int componentBit,
	int clearanceComponentIndex,
	double heatTimeCorrection)
{
	int status = SHT_RunClearanceAdjustedTurbineCore(
		turbine, clearanceComponentIndex);
	int iteration;
	int converged = 0;
	double inletFlow;
	double inletTemperature;
	double stageOneFlow;
	double stageOneFAR;
	double stageOneEnthalpy;
	double stageOneTemperature;
	double heatBoundaryFlow;
	double heatBoundaryTemperature;
	double rearCoolingEnthalpyFlow;
	double outletFlow;
	double outletFAR;
	double stageOnePressure;
	double outletPressure;
	double efficiency;
	double outletTemperature;
	double nextTemperature = 0.0;
	double totalHeatFlow = 0.0;
	double frontHeatFlow = 0.0;
	double rearHeatFlow = 0.0;
	double stageOneEffectiveEnthalpy = 0.0;
	double stageOneEffectiveTemperature;
	double entropy;
	double idealOutletTemperature;
	double idealOutletEnthalpy;
	double turbineSpecificWork = 0.0;
	double stageTwoEnthalpy = 0.0;
	double outletEnthalpy = 0.0;
	double shaftPower = 0.0;
	double omega;
	double residual = 0.0;
	double tolerance;
	double energyResidual;

	if (status != 0 || !SHT_IsHeatFeedbackSelected(componentBit))
		return status;

	inletFlow = turbine->gasPathIn[0];
	inletTemperature = turbine->gasPathIn[2];
	outletFAR = turbine->y[4];
	stageOnePressure = turbine->y[22];
	outletPressure = turbine->y[3];
	efficiency = turbine->y[19];
	outletTemperature = turbine->y[2];
	status = SHT_GetTurbineCoolingTerms(turbine,
		&stageOneFlow, &stageOneFAR, &stageOneEnthalpy,
		&rearCoolingEnthalpyFlow, &outletFlow);
	stageOneTemperature = h2tc(stageOneEnthalpy, stageOneFAR);
	if (status != SHT_STATUS_OK || !_finite(inletFlow) ||
		!_finite(stageOneFlow) || !_finite(outletFlow) ||
		!_finite(stageOnePressure) || !_finite(outletPressure) ||
		!_finite(efficiency) || !_finite(stageOneTemperature) ||
		!_finite(outletTemperature))
		return SHT_SetHeatFeedbackFailure(componentIndex, 0,
			outletTemperature, status);
	/* 与压气机相同，Newton差分点若暂时不满足涡轮热反馈方程的正流量、
	 * 正压力、正效率和正温度前提，只旁路本次热反馈试探。原涡轮部件
	 * 输出仍参与气路Jacobian，接受解回到物理区后会重新执行完整反馈。 */
	if (inletFlow <= 0.0 || stageOneFlow <= 0.0 || outletFlow <= 0.0 ||
		stageOnePressure <= 0.0 || outletPressure <= 0.0 || efficiency <= 0.0 ||
		stageOneTemperature <= 0.0 || outletTemperature <= 0.0)
	{
		if (!SHT_LowSpeedResidualScalingActive)
			return SHT_SetHeatFeedbackFailure(componentIndex, 0,
				outletTemperature, SHT_STATUS_OK);
		SHT_RecordHeatFeedbackSuccess(componentIndex, 0, 0.0, 0.0);
		return SHT_STATUS_OK;
	}
	heatBoundaryFlow = Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT ?
		stageOneFlow : inletFlow;
	heatBoundaryTemperature = Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT ?
		stageOneTemperature : inletTemperature;

	for (iteration = 1; iteration <= SHT_HEAT_FEEDBACK_MAX_ITERATIONS; ++iteration)
	{
		status = SHT_EvaluateLocalHeatDetailed(componentIndex, heatBoundaryFlow,
			heatBoundaryTemperature, outletTemperature, heatTimeCorrection,
			&totalHeatFlow, &frontHeatFlow, &rearHeatFlow);
		if (status != SHT_STATUS_OK)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				residual, status);
		/* 热流严格为零时保持原涡轮输出及冷却掺混结果逐位不变。 */
		if (frontHeatFlow == 0.0 && rearHeatFlow == 0.0)
		{
			SHT_RecordHeatFeedbackSuccess(componentIndex, iteration, 0.0, 0.0);
			return SHT_STATUS_OK;
		}

		stageOneEffectiveEnthalpy = stageOneEnthalpy -
			frontHeatFlow / stageOneFlow;
		stageOneEffectiveTemperature = h2tc(stageOneEffectiveEnthalpy, stageOneFAR);
		entropy = pt2sc(stageOnePressure, stageOneEffectiveTemperature, stageOneFAR);
		idealOutletTemperature = sp2tc(entropy, outletPressure, stageOneFAR);
		idealOutletEnthalpy = t2hc(idealOutletTemperature, stageOneFAR);
		turbineSpecificWork = efficiency *
			(stageOneEffectiveEnthalpy - idealOutletEnthalpy);
		stageTwoEnthalpy = stageOneEffectiveEnthalpy - turbineSpecificWork -
			rearHeatFlow / stageOneFlow;
		outletEnthalpy = (stageTwoEnthalpy * stageOneFlow +
			rearCoolingEnthalpyFlow) / outletFlow;
		nextTemperature = h2tc(outletEnthalpy, outletFAR);
		if (!_finite(nextTemperature) || nextTemperature <= 0.0 ||
			!_finite(turbineSpecificWork) || turbineSpecificWork <= 0.0)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				nextTemperature, SHT_STATUS_OK);

		residual = nextTemperature - outletTemperature;
		outletTemperature = nextTemperature;
		tolerance = SHT_HEAT_FEEDBACK_TEMPERATURE_TOL *
			fmax(1.0, fabs(outletTemperature));
		if (fabs(residual) <= tolerance)
		{
			converged = 1;
			break;
		}
	}
	if (!converged)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration - 1,
			residual, SHT_STATUS_OK);

	status = SHT_EvaluateLocalHeatDetailed(componentIndex, heatBoundaryFlow,
		heatBoundaryTemperature, outletTemperature, heatTimeCorrection,
		&totalHeatFlow, &frontHeatFlow, &rearHeatFlow);
	if (status != SHT_STATUS_OK)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
			residual, status);
	stageOneEffectiveEnthalpy = stageOneEnthalpy -
		frontHeatFlow / stageOneFlow;
	stageOneEffectiveTemperature = h2tc(stageOneEffectiveEnthalpy, stageOneFAR);
	entropy = pt2sc(stageOnePressure, stageOneEffectiveTemperature, stageOneFAR);
	idealOutletTemperature = sp2tc(entropy, outletPressure, stageOneFAR);
	idealOutletEnthalpy = t2hc(idealOutletTemperature, stageOneFAR);
	turbineSpecificWork = efficiency *
		(stageOneEffectiveEnthalpy - idealOutletEnthalpy);
	stageTwoEnthalpy = stageOneEffectiveEnthalpy - turbineSpecificWork -
		rearHeatFlow / stageOneFlow;
	outletEnthalpy = (stageTwoEnthalpy * stageOneFlow +
		rearCoolingEnthalpyFlow) / outletFlow;
	nextTemperature = h2tc(outletEnthalpy, outletFAR);
	residual = nextTemperature - outletTemperature;
	shaftPower = stageOneFlow * turbineSpecificWork;
	omega = *turbine->nMech > 2.0 ?
		*turbine->nMech * PI / 30.0 : 2.0 * PI / 30.0;
	turbine->y[1] = outletEnthalpy;
	turbine->y[2] = nextTemperature;
	turbine->y[5] = shaftPower / omega;
	turbine->y[18] = shaftPower;
	energyResidual = stageOneFlow *
		(stageOneEnthalpy - stageTwoEnthalpy) - shaftPower - totalHeatFlow;
	SHT_RecordHeatFeedbackSuccess(componentIndex, iteration,
		residual, energyResidual);
	return SHT_STATUS_OK;
}

/*
 * 把当前已经求得的部件气路量映射到 P3 纯热状态核。映射与 M 端参数资产
 * 的 Wref/Tgref 定义严格一致：HPC 入口、Burner 入口、GT 入口和 PT 入口
 * 分别提供四个部件流量，温度采用各部件进出口总温。
 */
static int SHT_GetTurbineHeatBoundary(
	TurbineBlock *turbine,
	double *componentFlow,
	double *inletTemperature)
{
	double stageOneFAR;
	double stageOneEnthalpy;
	double rearCoolingEnthalpyFlow;
	double outletFlow;
	int status = SHT_GetTurbineCoolingTerms(turbine,
		componentFlow, &stageOneFAR, &stageOneEnthalpy,
		&rearCoolingEnthalpyFlow, &outletFlow);
	if (status != SHT_STATUS_OK)
		return status;
	*inletTemperature = h2tc(stageOneEnthalpy, stageOneFAR);
	if (!_finite(*componentFlow) || *componentFlow <= 0.0 ||
		!_finite(*inletTemperature) || *inletTemperature <= 0.0)
		return SHT_ERROR_HEAT_EVALUATION;
	return SHT_STATUS_OK;
}

static int SHT_EvaluateCurrentHeatState(void)
{
	double componentFlow[SHT_HEAT_COMPONENT_COUNT] = { 0.0 };
	double inletTemperature[SHT_HEAT_COMPONENT_COUNT] = { 0.0 };
	double outletTemperature[SHT_HEAT_COMPONENT_COUNT] = { 0.0 };
	int status;

	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
	{
		componentFlow[0] = Turboshaft.Inlet.gasPathOut[0];
		componentFlow[1] = Turboshaft.HPC.y[0];
		componentFlow[2] = Turboshaft.HPC2.y[0];
		inletTemperature[0] = Turboshaft.Inlet.gasPathOut[2];
		inletTemperature[1] = Turboshaft.HPC.y[2];
		inletTemperature[2] = Turboshaft.HPC2.y[2];
		outletTemperature[0] = Turboshaft.HPC.y[2];
		outletTemperature[1] = Turboshaft.HPC2.y[2];
		outletTemperature[2] = Turboshaft.Burner.y[2];

		status = SHT_GetTurbineHeatBoundary(&Turboshaft.HPT,
			&componentFlow[3], &inletTemperature[3]);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_GetTurbineHeatBoundary(&Turboshaft.HPT2,
			&componentFlow[4], &inletTemperature[4]);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_GetTurbineHeatBoundary(&Turboshaft.LPT,
			&componentFlow[5], &inletTemperature[5]);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_GetTurbineHeatBoundary(&Turboshaft.LPT2,
			&componentFlow[6], &inletTemperature[6]);
		if (status != SHT_STATUS_OK) return status;
		outletTemperature[3] = Turboshaft.HPT.y[2];
		outletTemperature[4] = Turboshaft.HPT2.y[2];
		outletTemperature[5] = Turboshaft.LPT.y[2];
		outletTemperature[6] = Turboshaft.LPT2.y[2];
	}
	else
	{
		/* 2502 保留原三部件参考边界定义，避免改变历史结果。 */
		componentFlow[0] = Turboshaft.Inlet.gasPathOut[0];
		componentFlow[1] = Turboshaft.HPC.y[0];
		componentFlow[2] = Turboshaft.Burner.y[0];
		componentFlow[3] = Turboshaft.Duct2.gasPathOut[0];
		inletTemperature[0] = Turboshaft.Inlet.gasPathOut[2];
		inletTemperature[1] = Turboshaft.HPC.y[2];
		inletTemperature[2] = Turboshaft.Burner.y[2];
		inletTemperature[3] = Turboshaft.Duct2.gasPathOut[2];
		outletTemperature[0] = Turboshaft.HPC.y[2];
		outletTemperature[1] = Turboshaft.Burner.y[2];
		outletTemperature[2] = Turboshaft.HPT.y[2];
		outletTemperature[3] = Turboshaft.LPT.y[2];
		if (Turboshaft.transientControl.thermalModelMode == SHT_THERMAL_MODEL_VISSER)
		{
			status = SHT_GetTurbineHeatBoundary(&Turboshaft.HPT, &componentFlow[2], &inletTemperature[2]);
			if (status != SHT_STATUS_OK) return status;
			status = SHT_GetTurbineHeatBoundary(&Turboshaft.LPT, &componentFlow[3], &inletTemperature[3]);
			if (status != SHT_STATUS_OK) return status;
		}
	}

	if (Turboshaft.transientControl.thermalModelMode ==
		SHT_THERMAL_MODEL_VISSER)
	{
		if (!SHT_VisserCoolingEvaluation.valid)
			return SHT_ERROR_COOLING_SPLIT_NOT_INITIALIZED;
		status = SHT_EvaluateVisserHeatStates(
			&Turboshaft.transientControl,
			&Turboshaft.transientState,
			&Turboshaft.transientParameters,
			componentFlow, inletTemperature, outletTemperature,
			Turboshaft.transientParameters.heatTimeCorrection,
			Turboshaft.transientParameters.diskTimeCorrection,
			SHT_VisserCoolingEvaluation.metalHeatFlow,
			SHT_VisserCoolingEvaluation.diskHeatFlow,
			&Turboshaft.transientHeatEvaluation,
			&Turboshaft.transientDiagnostics);
		if (status == SHT_STATUS_OK)
		{
			memcpy(Turboshaft.transientHeatEvaluation
				.visserCoolingBranchHeatFlow,
				SHT_VisserCoolingEvaluation.branchHeatFlow,
				sizeof(SHT_VisserCoolingEvaluation.branchHeatFlow));
			memcpy(Turboshaft.transientHeatEvaluation
				.visserCoolingInletTemperature,
				SHT_VisserCoolingEvaluation.routeInletTemperature,
				sizeof(SHT_VisserCoolingEvaluation.routeInletTemperature));
			memcpy(Turboshaft.transientHeatEvaluation
				.visserCoolingOutletTemperature,
				SHT_VisserCoolingEvaluation.routeOutletTemperature,
				sizeof(SHT_VisserCoolingEvaluation.routeOutletTemperature));
		}
		return status;
	}
	return SHT_EvaluateHeatStates(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		componentFlow, inletTemperature, outletTemperature,
		Turboshaft.transientParameters.heatTimeCorrection,
		Turboshaft.transientParameters.diskTimeCorrection,
		&Turboshaft.transientHeatEvaluation,
		&Turboshaft.transientDiagnostics);
}

static void SHT_WriteHeatStateDerivatives(
	double *stepOut,
	int metalStartIndex,
	int diskStartIndex,
	int guideStartIndex)
{
	int i;
	for (i = 0; i < Turboshaft.transientControl.metalNodeCount; ++i)
		stepOut[metalStartIndex + i] =
			Turboshaft.transientHeatEvaluation.metalTemperatureDerivative[i];
	for (i = 0; i < Turboshaft.transientControl.diskNodeCount; ++i)
		stepOut[diskStartIndex + i] =
			Turboshaft.transientHeatEvaluation.diskTemperatureDerivative[i];
	for (i = 0; i < Turboshaft.transientControl.guideVaneNodeCount; ++i)
		stepOut[guideStartIndex + i] =
			Turboshaft.transientHeatEvaluation
				.guideVaneTemperatureDerivative[i];
}

/*
 * 停机零流量段的Visser热浸求值。主流与冷却流量均为零，因此不人为
 * 引入尚未标定的环境自然对流；完整热核只保留已有的根部-转盘内部导热。
 * dummyTemperature仅用于满足气体物性函数的有限正温度定义，在UA=0时
 * 不参与实际换热量计算。
 */
static int SHT_EvaluateZeroFlowVisserHeatState(void)
{
	double componentFlow[SHT_HEAT_COMPONENT_COUNT] = { 0.0 };
	double inletTemperature[SHT_HEAT_COMPONENT_COUNT];
	double outletTemperature[SHT_HEAT_COMPONENT_COUNT];
	double metalCoolingHeatFlow[SHT_VISSER_METAL_NODE_COUNT] = { 0.0 };
	double diskCoolingHeatFlow[SHT_DISK_NODE_COUNT] = { 0.0 };
	const double dummyTemperature = 288.15;
	int i;
	int status;

	if (!Turboshaft.transientControl.heatStateEnable)
		return SHT_STATUS_OK;
	if (Turboshaft.transientControl.thermalModelMode !=
		SHT_THERMAL_MODEL_VISSER)
		return SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED;
	for (i = 0; i < SHT_HEAT_COMPONENT_COUNT; ++i)
	{
		inletTemperature[i] = dummyTemperature;
		outletTemperature[i] = dummyTemperature;
	}
	SHT_SetZeroFlowHeatEvaluationEnabled(1);
	status = SHT_EvaluateVisserHeatStates(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		componentFlow, inletTemperature, outletTemperature,
		Turboshaft.transientParameters.heatTimeCorrection,
		Turboshaft.transientParameters.diskTimeCorrection,
		metalCoolingHeatFlow, diskCoolingHeatFlow,
		&Turboshaft.transientHeatEvaluation,
		&Turboshaft.transientDiagnostics);
	SHT_SetZeroFlowHeatEvaluationEnabled(0);
	return status;
}

static int SHT_IsFiniteVector(const double *values, int length)
{
	int i;
	for (i = 0; i < length; ++i)
	{
		if (!_finite(values[i]))
			return 0;
	}
	return 1;
}

static void SHT_SetEvaluationValidity(double *stepOut, int validIndex, int valid)
{
	Turboshaft.transientDiagnostics.evaluationValid = valid;
	if (Turboshaft.transientControl.interfaceVersion !=
		SHT_TRANSIENT_INTERFACE_BASELINE)
		stepOut[validIndex] = valid ? 1.0 : 0.0;
}
//------------------------------------------------------------------------------
int engineTurboshaftInitial(EngineTurboshaft *eng)
{
	return engineTurboshaftInitialMode(eng, SHT_MODEL_MODE_ORIGINAL);
}

int engineTurboshaftInitialMode(EngineTurboshaft *eng, int modelMode)
{
  int i = 0;
  FILE * fModel;
  const char *filename;
  char pathName[1000];
  char name[100];

  if (eng == NULL)
	  return SHT_ERROR_NULL_POINTER;
  if (modelMode != SHT_MODEL_MODE_ORIGINAL &&
	  modelMode != SHT_MODEL_MODE_SPLIT)
	  return SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED;
  filename = modelMode == SHT_MODEL_MODE_SPLIT ?
	  "Turboshaft-TS-Split.mdl" : "Turboshaft-TS.mdl";
  eng->modelMode = modelMode;
 
  eng->engineName = NULL;
  eng->timeVec = NULL;
  eng->farVec = NULL;
  eng->timeVecDim = 0;
  //eng->noFlow =NULL;      //
  //eng->noFlowWidth = 0;   //

  if (eng->filePath != NULL)
  {
	  i = strlen(eng->filePath);
	  if (i > 0)
		  strcpy(pathName, eng->filePath);
	  else
		  strcpy(pathName, "");
  }
  else
  {
	  strcpy(pathName, "");
  }
  strcat(pathName, filename);

  fModel = fopen(pathName,"r");
  if (fModel == NULL)
  {
	  return SHT_ERROR_PARAMETER_VALUE;
  }
  fscanf(fModel,"%*[^=]=%s",name);
  i = strlen(name) + 1;  //加1为了存储最后的\0
  eng->engineName = (char*)calloc(i,sizeof(char));
  strcpy(eng->engineName,name);

  if (eng->filePath != NULL)
  {
	  i = strlen(eng->filePath);
	  if (i > 0)
		  strcpy(pathName, eng->filePath);
	  else
		  strcpy(pathName, "");
  }
  else
  {
	  strcpy(pathName, "");
  }

  fscanf(fModel,"%*[^=]=%d",&eng->offDesignMode);
  fscanf(fModel,"%*[^=]=%lf",&eng->altitude);
  fscanf(fModel,"%*[^=]=%lf",&eng->machNumber);
  fscanf(fModel,"%*[^=]=%lf",&eng->dTemperature);
  fscanf(fModel,"%*[^=]=%lf",&eng->TtBurnerOut);


  fscanf(fModel,"%*[^=]=%lf",&eng->LPS_Power);
  fscanf(fModel,"%*[^=]=%lf",&eng->HPS_Power);
  fscanf(fModel,"%*[^=]=%lf",&eng->timeTotal);
  fscanf(fModel,"%*[^=]=%lf",&eng->timeStep);
  fscanf(fModel,"%*[^=]=%d",&eng->timeVecDim);

  if(eng->timeVecDim > 0)
  {
    eng->timeVec = (double*)calloc(eng->timeVecDim,sizeof(double));
    fscanf(fModel,"%*[^=]=%lf",&eng->timeVec[0]);
  }
  for(i = 1;i < eng->timeVecDim;i++)
  {
    fscanf(fModel,"%lf",&eng->timeVec[i]);
  }
  if(eng->timeVecDim > 0)
  {
    eng->farVec = (double*)calloc(eng->timeVecDim,sizeof(double));
    fscanf(fModel,"%*[^=]=%lf",&eng->farVec[0]);
  }
  for(i = 1;i < eng->timeVecDim;i++)
  {
    fscanf(fModel,"%lf",&eng->farVec[i]);
  }
  fscanf(fModel,"%*[^=]=%lf",&eng->accuracyReq);
  fscanf(fModel,"%*[^=]=%lf",&eng->distuFactor);
  fscanf(fModel,"%*[^=]=%d",&eng->maxIterations);
  fscanf(fModel,"%*[^=]=%d",&eng->varVecDime);
  if(eng->varVecDime > 0)
  {
    //内存定义在结构体内
    fscanf(fModel,"%*[^=]=%lf",&eng->varStartInput[0]);
  }
  for(i = 1;i < eng->varVecDime;i++)
  {
    fscanf(fModel,"%lf",&eng->varStartInput[i]);
  }
  if(eng->varVecDime > 0)
  {
    //内存定义在结构体内
    fscanf(fModel,"%*[^=]=%lf",&eng->varMin[0]);
  }
  for(i = 1;i < eng->varVecDime;i++)
  {
    fscanf(fModel,"%lf",&eng->varMin[i]);
  }
  if(eng->varVecDime > 0)
  {
    //内存定义在结构体内
    fscanf(fModel,"%*[^=]=%lf",&eng->varMax[0]);
  }
  for(i = 1;i < eng->varVecDime;i++)
  {
    fscanf(fModel,"%lf",&eng->varMax[i]);
  }
  if(eng->varVecDime > 0)
  {
    //内存定义在结构体内
    fscanf(fModel,"%*[^=]=%lf",&eng->varDelLim[0]);
  }
  for(i = 1;i < eng->varVecDime;i++)
  {
    fscanf(fModel,"%lf",&eng->varDelLim[i]);
  }
  
  fscanf(fModel,"%*[^=]=%s",name);
  ambientInitial(&eng->Ambient,fModel,name);
  
  fscanf(fModel,"%*[^=]=%s",name);
  inletInitial(&eng->Inlet,fModel,name);
 
  fscanf(fModel,"%*[^=]=%s",name);
  compressorInitial(&eng->HPC,fModel,name, pathName);

  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
  {
	  fscanf(fModel,"%*[^=]=%s",name);
	  compressorInitial(&eng->HPC2,fModel,name, pathName);
  }

  fscanf(fModel,"%*[^=]=%s",name);
  burnInitial(&eng->Burner,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->HPT,fModel,name, pathName);

  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
  {
	  fscanf(fModel,"%*[^=]=%s",name);
	  turbineInitial(&eng->HPT2,fModel,name, pathName);
  }

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct2,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->LPT,fModel,name, pathName);

  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
  {
	  fscanf(fModel,"%*[^=]=%s",name);
	  turbineInitial(&eng->LPT2,fModel,name, pathName);
  }

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct3,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  nozzleInitial(&eng->Nozzle,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->LPS,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->HPS,fModel,name);

  if(SHT_ConfigurePressureLossModels(eng) != 0)
  {
    fclose(fModel);
    return SHT_ERROR_PARAMETER_VALUE;
  }
  
  fclose(fModel);
  eng->isInitial = 1;

  return 0;
}
//------------------------------------------------------------------------------
int engineTurboshaftSetIdes(EngineTurboshaft *eng, double iDes)
{
	if (iDes < 3)   //0-设计点；1-所有部件的iDes设为1；2-所有部件的iDes设为2
	{
		eng->HPC.compressorStruct.IDes = iDes;
		eng->HPT.turbineStruct.IDes = iDes;
		eng->LPT.turbineStruct.IDes = iDes;
		if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
		{
			eng->HPC2.compressorStruct.IDes = iDes;
			eng->HPT2.turbineStruct.IDes = iDes;
			eng->LPT2.turbineStruct.IDes = iDes;
		}
	}
	else          //3-按照输入文件中的参数配置各部件的IDes
	{
		eng->HPC.compressorStruct.IDes = eng->HPC.IDesInput;
		eng->HPT.turbineStruct.IDes = eng->HPT.IDesInput;
		eng->LPT.turbineStruct.IDes = eng->LPT.IDesInput;
		if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
		{
			eng->HPC2.compressorStruct.IDes = eng->HPC2.IDesInput;
			eng->HPT2.turbineStruct.IDes = eng->HPT2.IDesInput;
			eng->LPT2.turbineStruct.IDes = eng->LPT2.IDesInput;
		}
		eng->Nozzle.nozzleStruct.IDes = eng->Nozzle.IDesInput;
	}
	return 0;
}
//------------------------------------------------------------------------------
int engineTurboshaftFree(EngineTurboshaft *eng)
{
  /* 这些指针只在三部件链接阶段动态分配；六部件模式指向静态零量。 */
  if (eng->modelMode == SHT_MODEL_MODE_ORIGINAL)
  {
    if (eng->HPC.BypassRatioIn != NULL) free(eng->HPC.BypassRatioIn);
    if (eng->HPC.hp_alf2W != NULL) free(eng->HPC.hp_alf2W);
    if (eng->HPC.hp_alf2PR != NULL) free(eng->HPC.hp_alf2PR);
    if (eng->HPC.hp_alf2Ef != NULL) free(eng->HPC.hp_alf2Ef);
    if (eng->HPC.hpAFT != NULL) free(eng->HPC.hpAFT);
    if (eng->HPC.hpPR_TipRootRatio != NULL) free(eng->HPC.hpPR_TipRootRatio);
    if (eng->HPC.hpEf_TipRootRatio != NULL) free(eng->HPC.hpEf_TipRootRatio);
    if (eng->Nozzle.hpA9 != NULL) free(eng->Nozzle.hpA9);
    eng->HPC.BypassRatioIn = NULL;
    eng->HPC.hp_alf2W = NULL;
    eng->HPC.hp_alf2PR = NULL;
    eng->HPC.hp_alf2Ef = NULL;
    eng->HPC.hpAFT = NULL;
    eng->HPC.hpPR_TipRootRatio = NULL;
    eng->HPC.hpEf_TipRootRatio = NULL;
    eng->Nozzle.hpA9 = NULL;
  }

  if(eng->engineName != NULL)
    free(eng->engineName);
  if (eng->filePath != NULL)
	  free(eng->filePath);
  if(eng->timeVec != NULL)
    free(eng->timeVec);
  if(eng->farVec != NULL)
    free(eng->farVec);

  ambientFree(&eng->Ambient);
  inletFree(&eng->Inlet);
  compressorFree(&eng->HPC);
  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
	compressorFree(&eng->HPC2);
  burnFree(&eng->Burner);
  turbineFree(&eng->HPT);
  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
	turbineFree(&eng->HPT2);
  ductFree(&eng->Duct2);
  turbineFree(&eng->LPT);
  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
	turbineFree(&eng->LPT2);
  ductFree(&eng->Duct3);
  nozzleFree(&eng->Nozzle);
  shaftFree(&eng->LPS);
  shaftFree(&eng->HPS);

  eng->engineName = NULL;
  eng->timeVec = NULL;
  eng->farVec = NULL;
  eng->filePath = NULL;
  eng->isInitial = 0;

  return 0;
}
//------------------------------------------------------------------------------
int engineTurboshaftLink(EngineTurboshaft *eng)
{
  eng->LPS.torqueIn = &eng->LPS_Trq;
  eng->LPS.powerTakeOff = &eng->LPS_Power;
  eng->LPS.nMech = &eng->LPS_Nmech;
  eng->LPS.timeStep = &eng->timeStep;

  eng->HPS.torqueIn = &eng->HPS_Trq;
  eng->HPS.powerTakeOff = &eng->HPS_Power;
  eng->HPS.nMech = &eng->HPS_Nmech;
  eng->HPS.timeStep = &eng->timeStep;

  eng->Ambient.wIn = &eng->inletMassFlow;
  eng->Ambient.altIn = &eng->altitude;
  eng->Ambient.dTambIn = &eng->dTemperature;
  eng->Ambient.machNumber = &eng->machNumber;

  eng->Inlet.gasPathIn = eng->Ambient.gasPathOut;
  eng->Inlet.pAmbIn = &eng->Ambient.y[4];
  eng->Inlet.hpdP_Loss = &(eng->hlthparas[0]);

  if (eng->modelMode == SHT_MODEL_MODE_SPLIT)
  {
	  memset(SHT_SplitZeroHealth, 0, sizeof(SHT_SplitZeroHealth));

	  /* 轴流压气机 AC：7、8+10、9+11、12、14共5个物理取气口。 */
	  eng->HPC.gasPathIn = eng->Inlet.gasPathOut;
	  eng->HPC.rLineIn = &eng->HPC_Rline;
	  eng->HPC.nMech = eng->HPS.nMech;
	  eng->HPC.BypassRatioIn = &SHT_SplitZeroHealth[0];
	  eng->HPC.Amean = 0.12;
	  eng->HPC.Cmean = 0.1;
	  eng->HPC.Kcla = 1.5;
	  eng->HPC.Kwe = 0.5;
	  eng->HPC.hpW = &SHT_SplitEffectiveHealth[0];
	  eng->HPC.hpEf = &SHT_SplitEffectiveHealth[1];
	  eng->HPC.hpPR = &SHT_SplitEffectiveHealth[2];
	  eng->HPC.hp_alf2W = &SHT_SplitZeroHealth[0];
	  eng->HPC.hp_alf2PR = &SHT_SplitZeroHealth[0];
	  eng->HPC.hp_alf2Ef = &SHT_SplitZeroHealth[0];
	  eng->HPC.hpAFT = &SHT_SplitZeroHealth[0];
	  eng->HPC.hpPR_TipRootRatio = &SHT_SplitZeroHealth[0];
	  eng->HPC.hpEf_TipRootRatio = &SHT_SplitZeroHealth[0];
	  eng->HPC.hpBldPRec = SHT_SplitZeroHealth;
	  eng->HPC.hpWbld = SHT_SplitZeroHealth;
	  eng->HPC.hpBldht = SHT_SplitZeroHealth;

	  /* 离心压气机 CC：1、2+4、3+5、6、13共5个物理取气口。 */
	  eng->HPC2.gasPathIn = &eng->HPC.y[0];
	  eng->HPC2.rLineIn = &eng->HPC2_Rline;
	  eng->HPC2.nMech = eng->HPS.nMech;
	  eng->HPC2.BypassRatioIn = &SHT_SplitZeroHealth[0];
	  eng->HPC2.Amean = 0.12;
	  eng->HPC2.Cmean = 0.1;
	  eng->HPC2.Kcla = 1.5;
	  eng->HPC2.Kwe = 0.5;
	  eng->HPC2.hpW = &SHT_SplitEffectiveHealth[3];
	  eng->HPC2.hpEf = &SHT_SplitEffectiveHealth[4];
	  eng->HPC2.hpPR = &SHT_SplitEffectiveHealth[5];
	  eng->HPC2.hp_alf2W = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hp_alf2PR = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hp_alf2Ef = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hpAFT = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hpPR_TipRootRatio = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hpEf_TipRootRatio = &SHT_SplitZeroHealth[0];
	  eng->HPC2.hpBldPRec = SHT_SplitZeroHealth;
	  eng->HPC2.hpWbld = SHT_SplitZeroHealth;
	  eng->HPC2.hpBldht = SHT_SplitZeroHealth;

	  eng->Burner.fuelFlowIn = &eng->fuelFlow;
	  eng->Burner.gasPathIn = &eng->HPC2.y[0];
	  eng->Burner.hpWf = &(eng->hlthparas[4]);
	  eng->Burner.hpEf = &(eng->hlthparas[5]);
	  eng->Burner.hpdP_Loss = &(eng->hlthparas[6]);

	  eng->HPT.coolingFlow = SHT_SplitGT1Cooling;
	  eng->HPT.extCoolingFlow = SHT_SplitGT1Cooling;
	  eng->HPT.gasPathIn = &eng->Burner.y[0];
	  eng->HPT.PressureRatioIn = &eng->HPT_PRin;
	  eng->HPT.nMech = eng->HPS.nMech;
	  eng->HPT.Amean = 0.12;
	  eng->HPT.Cmean = 0.1;
	  eng->HPT.Kcla = 1.5;
	  eng->HPT.Kwe = 0.5;
	  eng->HPT.hpW = &SHT_SplitEffectiveHealth[6];
	  eng->HPT.hpEf = &SHT_SplitEffectiveHealth[7];
	  eng->HPT.hpPR = &SHT_SplitEffectiveHealth[8];
	  eng->HPT.extSecAirSys = 0;
	  /* M1: GT1/GT2 共用原始 HPT 图形，保留标准 beta-压比关系。 */

	  eng->HPT2.coolingFlow = SHT_SplitGT2Cooling;
	  eng->HPT2.extCoolingFlow = SHT_SplitGT2Cooling;
	  eng->HPT2.gasPathIn = &eng->HPT.y[0];
	  eng->HPT2.PressureRatioIn = &eng->HPT2_PRin;
	  eng->HPT2.nMech = eng->HPS.nMech;
	  eng->HPT2.Amean = 0.12;
	  eng->HPT2.Cmean = 0.1;
	  eng->HPT2.Kcla = 1.5;
	  eng->HPT2.Kwe = 0.5;
	  eng->HPT2.hpW = &SHT_SplitEffectiveHealth[9];
	  eng->HPT2.hpEf = &SHT_SplitEffectiveHealth[10];
	  eng->HPT2.hpPR = &SHT_SplitEffectiveHealth[11];
	  eng->HPT2.extSecAirSys = 0;

	  eng->Duct2.gasPathIn = &eng->HPT2.y[0];
	  eng->Duct2.hpdP_Loss = &(eng->hlthparas[10]);

	  eng->LPT.coolingFlow = SHT_SplitPT1Cooling;
	  eng->LPT.extCoolingFlow = SHT_SplitPT1Cooling;
	  eng->LPT.gasPathIn = eng->Duct2.gasPathOut;
	  eng->LPT.PressureRatioIn = &eng->LPT_PRin;
	  eng->LPT.nMech = eng->LPS.nMech;
	  eng->LPT.Amean = 0.12;
	  eng->LPT.Cmean = 0.1;
	  eng->LPT.Kcla = 1.5;
	  eng->LPT.Kwe = 0.5;
	  eng->LPT.hpW = &SHT_SplitEffectiveHealth[12];
	  eng->LPT.hpEf = &SHT_SplitEffectiveHealth[13];
	  eng->LPT.hpPR = &SHT_SplitEffectiveHealth[14];
	  eng->LPT.extSecAirSys = 0;
	  /* M1: PT1/PT2 共用原始 LPT 图形，保留标准 beta-压比关系。 */

	  eng->LPT2.coolingFlow = SHT_SplitPT2Cooling;
	  eng->LPT2.extCoolingFlow = SHT_SplitPT2Cooling;
	  eng->LPT2.gasPathIn = &eng->LPT.y[0];
	  eng->LPT2.PressureRatioIn = &eng->LPT2_PRin;
	  eng->LPT2.nMech = eng->LPS.nMech;
	  eng->LPT2.Amean = 0.12;
	  eng->LPT2.Cmean = 0.1;
	  eng->LPT2.Kcla = 1.5;
	  eng->LPT2.Kwe = 0.5;
	  eng->LPT2.hpW = &SHT_SplitEffectiveHealth[15];
	  eng->LPT2.hpEf = &SHT_SplitEffectiveHealth[16];
	  eng->LPT2.hpPR = &SHT_SplitEffectiveHealth[17];
	  eng->LPT2.extSecAirSys = 0;

	  eng->Duct3.gasPathIn = &eng->LPT2.y[0];
	  eng->Duct3.hpdP_Loss = &(eng->hlthparas[14]);
	  eng->Nozzle.fDrag = &eng->Ambient.fDrag;
	  eng->Nozzle.gasPathIn = eng->Duct3.gasPathOut;
	  eng->Nozzle.pAmbIn = &SHT_NozzleBackPressure;
	  eng->Nozzle.afterFVABI = 0.0;
	  eng->Nozzle.hpA8 = &(eng->hlthparas[15]);
	  eng->Nozzle.hpA9 = &SHT_SplitZeroHealth[0];
	  return 0;
  }

  eng->HPC.gasPathIn = eng->Inlet.gasPathOut;
  eng->HPC.rLineIn = &eng->HPC_Rline;
  eng->HPC.nMech =  eng->HPS.nMech;
  eng->HPC.BypassRatioIn = (double*)calloc(1, sizeof(double));
  eng->HPC.Amean = 0.12;
  eng->HPC.Cmean = 0.1;
  eng->HPC.Kcla = 1.5;
  eng->HPC.Kwe = 0.5;
  eng->HPC.hpW = &(eng->hlthparas[1]);
  eng->HPC.hpEf = &(eng->hlthparas[2]);
  eng->HPC.hpPR = &(eng->hlthparas[3]);
  eng->HPC.hp_alf2W = (double*)calloc(1, sizeof(double));
  eng->HPC.hp_alf2PR = (double*)calloc(1, sizeof(double));
  eng->HPC.hp_alf2Ef = (double*)calloc(1, sizeof(double));
  eng->HPC.hpAFT = (double*)calloc(1, sizeof(double));
  eng->HPC.hpPR_TipRootRatio = (double*)calloc(1, sizeof(double));		// 20241108+, liukai
  eng->HPC.hpEf_TipRootRatio = (double*)calloc(1, sizeof(double));		// 20241108+, liukai
  eng->HPC.hpBldPRec = SHT_OriginalBleedPressureHealth;
  eng->HPC.hpWbld = SHT_OriginalBleedFlowHealth;
  eng->HPC.hpBldht = SHT_OriginalBleedEnthalpyHealth;

  eng->Burner.fuelFlowIn = &eng->fuelFlow;
  eng->Burner.gasPathIn = &eng->HPC.y[0];
  eng->Burner.hpWf = &(eng->hlthparas[4]);
  eng->Burner.hpEf = &(eng->hlthparas[5]);
  eng->Burner.hpdP_Loss = &(eng->hlthparas[6]);		// 20241108+, liukai

  eng->HPT.coolingFlow = eng->HPC.fractionalBleeds;
  eng->HPT.extCoolingFlow = eng->HPC.customerBleeds;
  eng->HPT.gasPathIn = &eng->Burner.y[0];
  eng->HPT.PressureRatioIn = &eng->HPT_PRin;
  eng->HPT.nMech = eng->HPS.nMech;
  eng->HPT.Amean = 0.12;
  eng->HPT.Cmean = 0.1;
  eng->HPT.Kcla = 1.5;
  eng->HPT.Kwe = 0.5;
  eng->HPT.hpW = &(eng->hlthparas[7]);
  eng->HPT.hpEf = &(eng->hlthparas[8]);
  eng->HPT.hpPR = &(eng->hlthparas[9]);
  eng->HPT.extSecAirSys = 0;

  eng->Duct2.gasPathIn = &eng->HPT.y[0];
  eng->Duct2.hpdP_Loss = &(eng->hlthparas[10]);

  int N;
  N = eng->HPT.coolingFlowWidth;
  eng->LPT.coolingFlow = &eng->HPC.fractionalBleeds[N];
  eng->LPT.extCoolingFlow = &eng->HPC.customerBleeds[N];
  eng->LPT.gasPathIn = eng->Duct2.gasPathOut;
  eng->LPT.PressureRatioIn = &eng->LPT_PRin;
  eng->LPT.nMech = eng->LPS.nMech;
  eng->LPT.Amean = 0.12;
  eng->LPT.Cmean = 0.1;
  eng->LPT.Kcla = 1.5;
  eng->LPT.Kwe = 0.5;
  eng->LPT.hpW = &(eng->hlthparas[11]);
  eng->LPT.hpEf = &(eng->hlthparas[12]);
  eng->LPT.hpPR = &(eng->hlthparas[13]);
  eng->LPT.extSecAirSys = 0;

  eng->Duct3.gasPathIn = &eng->LPT.y[0];
  eng->Duct3.hpdP_Loss = &(eng->hlthparas[14]);

  eng->Nozzle.fDrag = &eng->Ambient.fDrag;
  eng->Nozzle.gasPathIn = eng->Duct3.gasPathOut;
  eng->Nozzle.pAmbIn = &SHT_NozzleBackPressure;
  eng->Nozzle.afterFVABI = 0.0;
  eng->Nozzle.hpA8 = &(eng->hlthparas[15]);
  //jrt,20241106
  eng->Nozzle.hpA9 = (double*)calloc(1, sizeof(double));
  return 0;
}

//------------------------------------------------------------------------------
static int SHT_SetInletBoundaryInputError(int stepInIndex, double value)
{
	Turboshaft.transientDiagnostics.errorCode = SHT_ERROR_PARAMETER_VALUE;
	Turboshaft.transientDiagnostics.offendingStepInIndex = stepInIndex;
	Turboshaft.transientDiagnostics.offendingValue = value;
	return SHT_ERROR_PARAMETER_VALUE;
}

/*
 * stepIn[9] 只承载喷管外界的绝对背压。0 是兼容哨兵值，表示继续跟随
 * 环境静压；有限正值表示显式装机背压。该值不写入 Ambient，因而不会
 * 反向污染进气道冲压恢复、环境测量或飞行高度边界。
 */
static int SHT_ReadExhaustBackPressureInput(const double *stepIn)
{
	double pressure;
	if (stepIn == NULL)
		return SHT_ERROR_NULL_POINTER;
	pressure = stepIn[SHT_EXHAUST_BACK_PRESSURE_INPUT_INDEX];
	if (!_finite(pressure) || pressure < 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_EXHAUST_BACK_PRESSURE_INPUT_INDEX, pressure);
	SHT_ExplicitNozzleBackPressure = pressure > 0.0 ? 1 : 0;
	if (SHT_ExplicitNozzleBackPressure)
		SHT_NozzleBackPressure = pressure;
	return SHT_STATUS_OK;
}

static int SHT_UpdateExhaustBackPressure(void)
{
	if (!SHT_ExplicitNozzleBackPressure)
		SHT_NozzleBackPressure = Turboshaft.Ambient.y[4];
	if (!_finite(SHT_NozzleBackPressure) || SHT_NozzleBackPressure <= 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_EXHAUST_BACK_PRESSURE_INPUT_INDEX,
			SHT_NozzleBackPressure);
	return SHT_STATUS_OK;
}

/*
 * 由静压、静温和马赫数重构1截面总状态。这里使用与 Ambient_TMATS_body
 * 相同的可变比热焓、熵和声速模型：先由 V=M*sqrt(gamma*R*T) 得到动能，
 * 再由等熵条件确定总压。这样无需另建标准大气或常比热近似模型。
 */
static int SHT_ReconstructInletTotalState(
	double ambientPressure,
	double ambientTemperature,
	double machNumber,
	double far,
	SHTInletBoundaryState *state)
{
	double gasConstant;
	double gamma;
	double staticEnthalpy;
	double staticEntropy;
	double totalEntropyAtAmbientPressure;
	double pressureExponent;
	double speedOfSound;
	double targetTotalEnthalpy;
	double totalEnthalpyResidual;
	double temperatureStep;
	double specificHeat;
	double temperatureCorrection;
	int iteration;

	if (state == NULL)
		return SHT_ERROR_NULL_POINTER;
	if (!_finite(ambientPressure) || ambientPressure <= 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_AMBIENT_PRESSURE_INPUT_INDEX, ambientPressure);
	if (!_finite(ambientTemperature) || ambientTemperature <= 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);
	if (!_finite(machNumber) || machNumber < 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_MACH_INPUT_INDEX, machNumber);

	gasConstant = Rcalc(far);
	gamma = t2gc(ambientTemperature, far);
	staticEnthalpy = t2hc(ambientTemperature, far);
	if (!_finite(gasConstant) || gasConstant <= 0.0 ||
		!_finite(gamma) || gamma <= 1.0 ||
		!_finite(staticEnthalpy))
		return SHT_SetInletBoundaryInputError(
			SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);

	speedOfSound = sqrt(gamma * gasConstant * ambientTemperature);
	state->velocity = machNumber * speedOfSound;
	targetTotalEnthalpy = staticEnthalpy +
		0.5 * state->velocity * state->velocity;
	state->totalTemperature = machNumber == 0.0 ? ambientTemperature :
		h2tc(targetTotalEnthalpy, far);

	/*
	 * h2tc在低温表段与t2hc并非机器精度互逆。以它作为初值，随后
	 * 对正向焓表做Newton校正，保证总焓严格满足静焓加单位质量动能。
	 */
	for (iteration = 0; iteration < 12; ++iteration)
	{
		state->totalEnthalpy = t2hc(state->totalTemperature, far);
		totalEnthalpyResidual =
			state->totalEnthalpy - targetTotalEnthalpy;
		if (fabs(totalEnthalpyResidual) <=
			1.0e-11 * fmax(1.0, fabs(targetTotalEnthalpy)))
			break;
		temperatureStep = fmax(1.0e-3,
			1.0e-6 * state->totalTemperature);
		specificHeat = (
			t2hc(state->totalTemperature + temperatureStep, far) -
			t2hc(state->totalTemperature - temperatureStep, far)) /
			(2.0 * temperatureStep);
		if (!_finite(specificHeat) || specificHeat <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);
		temperatureCorrection = totalEnthalpyResidual / specificHeat;
		if (!_finite(temperatureCorrection) ||
			fabs(temperatureCorrection) > 100.0)
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);
		state->totalTemperature -= temperatureCorrection;
		if (!_finite(state->totalTemperature) ||
			state->totalTemperature <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);
	}
	state->totalEnthalpy = t2hc(state->totalTemperature, far);
	if (iteration == 12 || fabs(state->totalEnthalpy - targetTotalEnthalpy) >
		1.0e-9 * fmax(1.0, fabs(targetTotalEnthalpy)))
		return SHT_SetInletBoundaryInputError(
			SHT_AMBIENT_TEMPERATURE_INPUT_INDEX, ambientTemperature);

	staticEntropy = pt2sc(ambientPressure, ambientTemperature, far);
	totalEntropyAtAmbientPressure = pt2sc(
		ambientPressure, state->totalTemperature, far);
	pressureExponent =
		(totalEntropyAtAmbientPressure - staticEntropy) / gasConstant;
	state->totalPressure = ambientPressure * exp(pressureExponent);
	state->staticPressure = ambientPressure;
	state->staticTemperature = ambientTemperature;

	if (!_finite(state->velocity) || state->velocity < 0.0 ||
		!_finite(state->totalEnthalpy) ||
		!_finite(state->totalTemperature) || state->totalTemperature <= 0.0 ||
		!_finite(state->totalPressure) || state->totalPressure <= 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_BOUNDARY_MODE_INDEX, (double)state->mode);
	return SHT_STATUS_OK;
}

static int SHT_RunTransientCompressor(CompressorBlock *compressor)
{
	int status = SHT_RunClearanceAdjustedCompressorCore(compressor, 0);
	if (status != SHT_STATUS_OK)
		return status;
	return SHT_ApplyTransientCompressorHeat(compressor, 0,
		SHT_COMPONENT_HPC,
		Turboshaft.transientParameters.heatTimeCorrection[0]);
}

//------------------------------------------------------------------------------
static int SHT_ReadInletBoundaryInput(double *stepIn)
{
	double modeValue;
	double roundedMode;
	double externalPressureRecoveryInput;
	double standardStaticTemperature;
	double far;
	int mode;
	int status;

	if (stepIn == NULL)
		return SHT_ERROR_NULL_POINTER;
	status = SHT_ReadExhaustBackPressureInput(stepIn);
	if (status != SHT_STATUS_OK)
		return status;

	modeValue = stepIn[SHT_INLET_BOUNDARY_MODE_INDEX];
	if (!_finite(modeValue))
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_BOUNDARY_MODE_INDEX, modeValue);
	roundedMode = floor(modeValue + 0.5);
	if (modeValue < 0.0 || modeValue > 5.0 ||
		fabs(modeValue - roundedMode) > 1.0e-12)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_BOUNDARY_MODE_INDEX, modeValue);
	mode = (int)roundedMode;

	if (!_finite(stepIn[SHT_ALTITUDE_INPUT_INDEX]))
		return SHT_SetInletBoundaryInputError(
			SHT_ALTITUDE_INPUT_INDEX,
			stepIn[SHT_ALTITUDE_INPUT_INDEX]);
	if (!_finite(stepIn[SHT_MACH_INPUT_INDEX]) ||
		stepIn[SHT_MACH_INPUT_INDEX] < 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_MACH_INPUT_INDEX, stepIn[SHT_MACH_INPUT_INDEX]);
	if (!_finite(stepIn[SHT_DELTA_TEMPERATURE_INPUT_INDEX]))
		return SHT_SetInletBoundaryInputError(
			SHT_DELTA_TEMPERATURE_INPUT_INDEX,
			stepIn[SHT_DELTA_TEMPERATURE_INPUT_INDEX]);
	externalPressureRecoveryInput =
		stepIn[SHT_INLET_EXTERNAL_RECOVERY_INPUT_INDEX];
	if (!_finite(externalPressureRecoveryInput) ||
		externalPressureRecoveryInput < 0.0 ||
		externalPressureRecoveryInput > 1.0)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_EXTERNAL_RECOVERY_INPUT_INDEX,
			externalPressureRecoveryInput);
	if (mode != SHT_INLET_BOUNDARY_STATIC_RECONSTRUCTION &&
		mode != SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY &&
		externalPressureRecoveryInput != 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_EXTERNAL_RECOVERY_INPUT_INDEX,
			externalPressureRecoveryInput);

	Turboshaft.altitude = stepIn[SHT_ALTITUDE_INPUT_INDEX];
	Turboshaft.machNumber = stepIn[SHT_MACH_INPUT_INDEX];
	Turboshaft.dTemperature =
		stepIn[SHT_DELTA_TEMPERATURE_INPUT_INDEX];
	Turboshaft.InletInPt =
		stepIn[SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX];
	Turboshaft.InletInTt =
		stepIn[SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX];
	Turboshaft.AmbientPs = stepIn[SHT_AMBIENT_PRESSURE_INPUT_INDEX];
	Turboshaft.useInletBoundaryInput = modeValue;

	memset(&SHT_InletBoundaryState, 0, sizeof(SHT_InletBoundaryState));
	SHT_InletBoundaryState.mode = mode;
	SHT_InletBoundaryState.externalPressureRecovery = 1.0;
	SHT_InletBoundaryState.ambientTemperature =
		stepIn[SHT_AMBIENT_TEMPERATURE_INPUT_INDEX];
	far = Turboshaft.Ambient.ambientStruct.AFARc;

	if (mode == SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE)
		return SHT_STATUS_OK;

	if (mode == SHT_INLET_BOUNDARY_DIRECT_TOTAL)
	{
		if (!_finite(Turboshaft.InletInPt) || Turboshaft.InletInPt <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
				Turboshaft.InletInPt);
		if (!_finite(Turboshaft.InletInTt) || Turboshaft.InletInTt <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX,
				Turboshaft.InletInTt);
		if (!_finite(Turboshaft.AmbientPs) || Turboshaft.AmbientPs <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_PRESSURE_INPUT_INDEX, Turboshaft.AmbientPs);
		SHT_InletBoundaryState.totalPressure = Turboshaft.InletInPt;
		SHT_InletBoundaryState.totalTemperature = Turboshaft.InletInTt;
		SHT_InletBoundaryState.totalEnthalpy = t2hc(
			Turboshaft.InletInTt, far);
		SHT_InletBoundaryState.staticPressure = Turboshaft.AmbientPs;
		if (!_finite(SHT_InletBoundaryState.totalEnthalpy))
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX,
				Turboshaft.InletInTt);
		return SHT_STATUS_OK;
	}
	if (mode == SHT_INLET_BOUNDARY_ALTITUDE_STATIC_TEMPERATURE)
	{
		/*
		 * 先令温差为0并调用既有标准大气模块，取得当前高度的标准静温
		 * 和静压；再由给定静温反算温差。后续部件求值仍由同一个
		 * Ambient模块计算Pt1/Tt1，避免在接口层复制第二套大气模型。
		 */
		if (!_finite(SHT_InletBoundaryState.ambientTemperature) ||
			SHT_InletBoundaryState.ambientTemperature <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_TEMPERATURE_INPUT_INDEX,
				SHT_InletBoundaryState.ambientTemperature);
		Turboshaft.dTemperature = 0.0;
		ambientRun(&Turboshaft.Ambient);
		standardStaticTemperature = Turboshaft.Ambient.y[5];
		if (!_finite(standardStaticTemperature) ||
			standardStaticTemperature <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_ALTITUDE_INPUT_INDEX, Turboshaft.altitude);
		Turboshaft.dTemperature =
			SHT_InletBoundaryState.ambientTemperature -
			standardStaticTemperature;
		if (!_finite(Turboshaft.dTemperature))
			return SHT_SetInletBoundaryInputError(
				SHT_AMBIENT_TEMPERATURE_INPUT_INDEX,
				SHT_InletBoundaryState.ambientTemperature);
		Turboshaft.AmbientPs = Turboshaft.Ambient.y[4];
		return SHT_STATUS_OK;
	}
	if (mode == SHT_INLET_BOUNDARY_MEASURED_TT_PT2_REPLAY)
	{
		SHT_InletBoundaryState.measuredPt2 =
			stepIn[SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX];
		if (!_finite(SHT_InletBoundaryState.measuredPt2) ||
			SHT_InletBoundaryState.measuredPt2 <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
				SHT_InletBoundaryState.measuredPt2);
	}

	status = SHT_ReconstructInletTotalState(
		Turboshaft.AmbientPs,
		SHT_InletBoundaryState.ambientTemperature,
		Turboshaft.machNumber,
		far,
		&SHT_InletBoundaryState);
	if (status != SHT_STATUS_OK)
		return status;
	if (mode == SHT_INLET_BOUNDARY_STATIC_RECONSTRUCTION ||
		mode == SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY)
	{
		/*
		 * 模式2/5先从静压、静温和Mach重构无损来流总态，再施加飞机
		 * 进气道、滤网和低阶等效畸变的总压恢复。该量只影响
		 * Ambient->Inlet输入的Pt1，后续Inlet部件仍独立计算Pt1->Pt2压损。
		 * 模式5的静压来自可测Ps0；历史调用者在stepIn[19]保持0时
		 * 继续按恢复系数1执行。
		 */
		if (externalPressureRecoveryInput > 0.0)
			SHT_InletBoundaryState.externalPressureRecovery =
				externalPressureRecoveryInput;
		SHT_InletBoundaryState.totalPressure *=
			SHT_InletBoundaryState.externalPressureRecovery;
		if (!_finite(SHT_InletBoundaryState.totalPressure) ||
			SHT_InletBoundaryState.totalPressure <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_EXTERNAL_RECOVERY_INPUT_INDEX,
				externalPressureRecoveryInput);
	}
	Turboshaft.InletInPt = SHT_InletBoundaryState.totalPressure;

	if (mode == SHT_INLET_BOUNDARY_MEASURED_TT_PT2_REPLAY ||
		mode == SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY)
	{
		if (!_finite(Turboshaft.InletInTt) || Turboshaft.InletInTt <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX,
				Turboshaft.InletInTt);
		SHT_InletBoundaryState.totalTemperature = Turboshaft.InletInTt;
		SHT_InletBoundaryState.totalEnthalpy = t2hc(
			Turboshaft.InletInTt, far);
		if (!_finite(SHT_InletBoundaryState.totalEnthalpy))
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX,
				Turboshaft.InletInTt);
	}
	else
	{
		Turboshaft.InletInTt = SHT_InletBoundaryState.totalTemperature;
	}
	return SHT_STATUS_OK;
}

//------------------------------------------------------------------------------
static int SHT_ReadRuntimeInletBoundaryInput(double *stepIn)
{
	int status;
	if (stepIn == NULL)
		return SHT_ERROR_NULL_POINTER;
	status = SHT_ReadExhaustBackPressureInput(stepIn);
	if (status != SHT_STATUS_OK)
		return status;

	/*
	 * 模式0沿用初始化时锁存的高度、马赫数和温差。旧版MATLAB与
	 * Simulink程序在运行入口会把stepIn[10:12]保持为0，因此这里
	 * 不得用这些占位零值覆盖ConditionsInit已经保存的环境边界。
	 */
	if (stepIn[SHT_INLET_BOUNDARY_MODE_INDEX] ==
		(double)SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE)
	{
		Turboshaft.useInletBoundaryInput =
			(double)SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE;
		memset(&SHT_InletBoundaryState, 0,
			sizeof(SHT_InletBoundaryState));
		SHT_InletBoundaryState.mode =
			SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE;
		return SHT_STATUS_OK;
	}
	return SHT_ReadInletBoundaryInput(stepIn);
}

//------------------------------------------------------------------------------
static int SHT_ApplyInletBoundaryInput(void)
{
	int mode = SHT_InletBoundaryState.mode;
	if (mode == SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE ||
		mode == SHT_INLET_BOUNDARY_ALTITUDE_STATIC_TEMPERATURE)
		return SHT_UpdateExhaustBackPressure();
	if (mode < SHT_INLET_BOUNDARY_DIRECT_TOTAL ||
		mode > SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_BOUNDARY_MODE_INDEX, (double)mode);

	/*
	 * Pt1/Tt1必须在 inletRun 前写入，才能让进口部件的名义压损和健康
	 * 修正继续作用于 Pt1->Pt2。总温改变时同步更新总焓，避免旧实现中
	 * h 与 T 不一致。
	 */
	Turboshaft.Ambient.gasPathOut[1] =
		SHT_InletBoundaryState.totalEnthalpy;
	Turboshaft.Ambient.gasPathOut[2] =
		SHT_InletBoundaryState.totalTemperature;
	Turboshaft.Ambient.gasPathOut[3] =
		SHT_InletBoundaryState.totalPressure;
	Turboshaft.Ambient.y[0] = SHT_InletBoundaryState.totalEnthalpy;
	Turboshaft.Ambient.y[1] = SHT_InletBoundaryState.totalTemperature;
	Turboshaft.Ambient.y[2] = SHT_InletBoundaryState.totalPressure;
	Turboshaft.Ambient.y[4] = SHT_InletBoundaryState.staticPressure;

	if (mode == SHT_INLET_BOUNDARY_STATIC_RECONSTRUCTION ||
		mode == SHT_INLET_BOUNDARY_MEASURED_TT_PT2_REPLAY ||
		mode == SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY)
	{
		Turboshaft.Ambient.y[5] = SHT_InletBoundaryState.staticTemperature;
		Turboshaft.Ambient.y[6] = SHT_InletBoundaryState.velocity;
	}
	Turboshaft.Ambient.fDrag = Turboshaft.inletMassFlow *
		Turboshaft.Ambient.y[6];
	return SHT_UpdateExhaustBackPressure();
}

/*
 * 模式4先按当前名义压损模型运行进口部件，用未替换的
 * 输出反推冲压恢复因子，再根据测量Pt2反算附加压损修正。
 * 这使直接计算与C程序的名义压损、低流量门控和冲压模型严格一致。
 * 反算值写入lastCorrectionLoss供MATLAB读取，不改写h0。
 */
static int SHT_RunInletWithBoundary(void)
{
	PressureLossModel *lossModel = &Turboshaft.Inlet.pressureLossModel;
	double pt1;
	double pt2BeforeOverride;
	double pressureRecoveryWithoutLoss;
	double requiredTotalLoss;
	double inferredCorrection;
	double recoveryDenominator;
	int status = inletRun(&Turboshaft.Inlet);
	if (status != SHT_STATUS_OK)
		return status;
	if (SHT_InletBoundaryState.mode !=
		SHT_INLET_BOUNDARY_MEASURED_TT_PT2_REPLAY)
		return SHT_STATUS_OK;

	pt1 = Turboshaft.Inlet.gasPathIn[3];
	pt2BeforeOverride = Turboshaft.Inlet.gasPathOut[3];
	if (!_finite(pt1) || pt1 <= 0.0 ||
		!_finite(pt2BeforeOverride) || pt2BeforeOverride <= 0.0)
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
			SHT_InletBoundaryState.measuredPt2);

	if (lossModel->enabled != 0)
	{
		recoveryDenominator = pt1 * (1.0 - lossModel->lastTotalLoss);
		if (!_finite(recoveryDenominator) || recoveryDenominator <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
				SHT_InletBoundaryState.measuredPt2);
		pressureRecoveryWithoutLoss =
			pt2BeforeOverride / recoveryDenominator;
		requiredTotalLoss = 1.0 -
			SHT_InletBoundaryState.measuredPt2 /
			(pt1 * pressureRecoveryWithoutLoss);
		inferredCorrection = requiredTotalLoss -
			lossModel->lastNominalLoss;
	}
	else
	{
		recoveryDenominator = pt1 *
			(Turboshaft.Inlet.eRamBase - Turboshaft.hlthparas[0]);
		if (!_finite(recoveryDenominator) || recoveryDenominator <= 0.0)
			return SHT_SetInletBoundaryInputError(
				SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
				SHT_InletBoundaryState.measuredPt2);
		pressureRecoveryWithoutLoss =
			pt2BeforeOverride / recoveryDenominator;
		requiredTotalLoss = 1.0 -
			SHT_InletBoundaryState.measuredPt2 /
			(pt1 * pressureRecoveryWithoutLoss);
		lossModel->lastNominalLoss = 1.0 - Turboshaft.Inlet.eRamBase;
		inferredCorrection = requiredTotalLoss -
			lossModel->lastNominalLoss;
	}

	if (!_finite(pressureRecoveryWithoutLoss) ||
		pressureRecoveryWithoutLoss <= 0.0 ||
		!_finite(inferredCorrection))
		return SHT_SetInletBoundaryInputError(
			SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX,
			SHT_InletBoundaryState.measuredPt2);

	SHT_InletBoundaryState.inferredPressureLossCorrection =
		inferredCorrection;
	lossModel->lastCorrectionLoss = inferredCorrection;
	lossModel->lastTotalLoss = lossModel->lastNominalLoss +
		inferredCorrection;
	Turboshaft.Inlet.gasPathOut[3] =
		SHT_InletBoundaryState.measuredPt2;
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
static double SHT_LowSpeedRescaleFlowResidual(
	double legacyResidual,
	double correctedFlow)
{
	/*
	 * 旧部件函数在|Wc|<=1时以1 kg/s归一化。先恢复流量差分子，
	 * 再用连续复合尺度归一化，避免Wc趋零时残差尺度突变或消失。
	 */
	double legacyScale = correctedFlow > 1.0 ? correctedFlow : 1.0;
	double numerator = legacyResidual * legacyScale;
	double denominator = sqrt(correctedFlow * correctedFlow +
		SHT_LowSpeedFlowReference * SHT_LowSpeedFlowReference);
	return numerator / denominator;
}

static double SHT_LowSpeedNozzleResidual(void)
{
	/*
	 * 在零流量极限附近，通用喷管的正向流量方程会退化，甚至在入口
	 * 总压略低于环境压时给出反向计算流量。起停专用入口因此采用平滑
	 * 互补边界：压差尚未建立时约束Pt5=Pamb；形成足够正压差后恢复
	 * 原喷管流量残差。普通稳态/瞬态入口不进入本函数。
	 */
	double ambientPressure;
	double totalPressure;
	double pressureResidual;
	double blend;
	double legacyResidual = Turboshaft.Nozzle.y[2];
	if (Turboshaft.Nozzle.gasPathIn == NULL ||
		Turboshaft.Nozzle.pAmbIn == NULL)
		return legacyResidual;
	totalPressure = Turboshaft.Nozzle.gasPathIn[3];
	ambientPressure = *Turboshaft.Nozzle.pAmbIn;
	if (!_finite(totalPressure) || !_finite(ambientPressure) ||
		ambientPressure <= 0.0)
		return legacyResidual;
	pressureResidual = (totalPressure - ambientPressure) / ambientPressure;
	if (pressureResidual <= 0.0)
		return pressureResidual;
	blend = pressureResidual / SHT_LowSpeedNozzleFlowBlendPressureRatio;
	if (blend >= 1.0)
		return legacyResidual;
	blend = blend * blend * (3.0 - 2.0 * blend);
	return (1.0 - blend) * pressureResidual + blend * legacyResidual;
}

static void SHT_ApplyLowSpeedResidualScaling(void)
{
	if (!SHT_LowSpeedResidualScalingActive)
		return;
	if (Turboshaft.modelMode != SHT_MODEL_MODE_SPLIT)
	{
		Turboshaft.errOut[0] = SHT_LowSpeedRescaleFlowResidual(
			Turboshaft.HPC.y[6], Turboshaft.HPC.y[12]);
		Turboshaft.errOut[1] = SHT_LowSpeedRescaleFlowResidual(
			Turboshaft.HPT.y[6], Turboshaft.HPT.y[12]);
		Turboshaft.errOut[2] = SHT_LowSpeedRescaleFlowResidual(
			Turboshaft.LPT.y[6], Turboshaft.LPT.y[12]);
		Turboshaft.errOut[3] = SHT_LowSpeedNozzleResidual();
		return;
	}
	Turboshaft.errOut[0] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.HPC.y[6], Turboshaft.HPC.y[12]);
	Turboshaft.errOut[1] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.HPC2.y[6], Turboshaft.HPC2.y[12]);
	Turboshaft.errOut[2] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.HPT.y[6], Turboshaft.HPT.y[12]);
	Turboshaft.errOut[3] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.HPT2.y[6], Turboshaft.HPT2.y[12]);
	Turboshaft.errOut[4] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.LPT.y[6], Turboshaft.LPT.y[12]);
	Turboshaft.errOut[5] = SHT_LowSpeedRescaleFlowResidual(
		Turboshaft.LPT2.y[6], Turboshaft.LPT2.y[12]);
	Turboshaft.errOut[6] = SHT_LowSpeedNozzleResidual();
}

static int SHT_RunSplitComponents(
	double *varIn,
	double *errOut,
	int dime,
	int solveShaftSpeed)
{
	int i;
	int status;
	int useExternalBleed = Turboshaft.HPT.extSecAirSys > 0.5;
	if (varIn == NULL || errOut == NULL)
		return SHT_ERROR_NULL_POINTER;
	if ((solveShaftSpeed && dime != SHT_SPLIT_VARIABLE_COUNT) ||
		(!solveShaftSpeed && dime != SHT_SPLIT_GAS_VARIABLE_COUNT))
		return SHT_ERROR_PARAMETER_VALUE;

	for (i = 0; i < dime; ++i)
	{
		Turboshaft.varIte[i] = varIn[i];
		Turboshaft.errOut[i] = 1.0;
	}
	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPC2_Rline = Turboshaft.varIte[2];
	Turboshaft.HPT_PRin = Turboshaft.varIte[3];
	Turboshaft.HPT2_PRin = Turboshaft.varIte[4];
	Turboshaft.LPT_PRin = Turboshaft.varIte[5];
	Turboshaft.LPT2_PRin = Turboshaft.varIte[6];
	if (solveShaftSpeed)
	{
		Turboshaft.LPS_Nmech = Turboshaft.varIte[7];
		Turboshaft.HPS_Nmech = Turboshaft.varIte[8];
	}

	SHT_UpdateShaftLoadPower();
	status = SHT_ResetEffectiveHealthFromDesignValue();
	if (status != SHT_STATUS_OK) return status;
	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(0,
		Turboshaft.inletMassFlow,
		Turboshaft.Inlet.gasPathIn[2],
		Turboshaft.Inlet.gasPathIn[3],
		&Turboshaft.Inlet.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunInletWithBoundary();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplySplitRotatingSchedules();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunSplitCompressor(&Turboshaft.HPC,
		SHT_AxialBleedIndex, SHT_SPLIT_COMPRESSOR_BLEED_COUNT,
		Turboshaft.inletMassFlow,
		useExternalBleed, 0, 0, !solveShaftSpeed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplySplitCCSchedules();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunSplitCompressor(&Turboshaft.HPC2,
		SHT_CentrifugalBleedIndex, SHT_SPLIT_COMPRESSOR_BLEED_COUNT,
		Turboshaft.inletMassFlow,
		useExternalBleed, 1, 1, !solveShaftSpeed);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(6,
		Turboshaft.Burner.gasPathIn[0],
		Turboshaft.Burner.gasPathIn[2],
		Turboshaft.Burner.gasPathIn[3],
		&Turboshaft.Burner.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_PrepareSplitCoolingFlows(useExternalBleed);
	if (status != SHT_STATUS_OK) return status;

	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	if (solveShaftSpeed)
		burnRun(&Turboshaft.Burner);
	else
	{
		status = SHT_RunTransientBurner(&Turboshaft.Burner, 2);
		if (status != SHT_STATUS_OK) return status;
	}
	if (solveShaftSpeed)
	{
		status = SHT_RunClearanceAdjustedTurbineCore(
			&Turboshaft.HPT, SHT_REYNOLDS_GT1);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_RunClearanceAdjustedTurbineCore(
			&Turboshaft.HPT2, SHT_REYNOLDS_GT2);
		if (status != SHT_STATUS_OK) return status;
	}
	else
	{
		status = SHT_RunTransientTurbine(&Turboshaft.HPT, 3,
			SHT_COMPONENT_GT, 2,
			Turboshaft.transientParameters.heatTimeCorrection[3]);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_RunTransientTurbine(&Turboshaft.HPT2, 4,
			SHT_COMPONENT_GT, 3,
			Turboshaft.transientParameters.heatTimeCorrection[4]);
		if (status != SHT_STATUS_OK) return status;
	}
	status = SHT_ApplyPressureLossSchedule(10,
		Turboshaft.Duct2.gasPathIn[0],
		Turboshaft.Duct2.gasPathIn[2],
		Turboshaft.Duct2.gasPathIn[3],
		&Turboshaft.Duct2.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct2);
	if (solveShaftSpeed)
	{
		status = SHT_RunClearanceAdjustedTurbineCore(
			&Turboshaft.LPT, SHT_REYNOLDS_PT1);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_RunClearanceAdjustedTurbineCore(
			&Turboshaft.LPT2, SHT_REYNOLDS_PT2);
		if (status != SHT_STATUS_OK) return status;
	}
	else
	{
		status = SHT_RunTransientTurbine(&Turboshaft.LPT, 5,
			SHT_COMPONENT_PT, 4,
			Turboshaft.transientParameters.heatTimeCorrection[5]);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_RunTransientTurbine(&Turboshaft.LPT2, 6,
			SHT_COMPONENT_PT, 5,
			Turboshaft.transientParameters.heatTimeCorrection[6]);
		if (status != SHT_STATUS_OK) return status;
	}
	status = SHT_ApplyPressureLossSchedule(14,
		Turboshaft.Duct3.gasPathIn[0],
		Turboshaft.Duct3.gasPathIn[2],
		Turboshaft.Duct3.gasPathIn[3],
		&Turboshaft.Duct3.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);

	Turboshaft.LPS_Trq =
		(Turboshaft.LPT.y[5] + Turboshaft.LPT2.y[5]) *
		Turboshaft.LPS.effMech;
	if (solveShaftSpeed)
		shaftRun(&Turboshaft.LPS);
	else
		SHT_RunTransientShaft(&Turboshaft.LPS,
			Turboshaft.transientParameters.inertiaCorrection[1]);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPC2.y[5] +
		(Turboshaft.HPT.y[5] + Turboshaft.HPT2.y[5]) *
		Turboshaft.HPS.effMech;
	if (solveShaftSpeed)
		shaftRun(&Turboshaft.HPS);
	else
		SHT_RunTransientShaft(&Turboshaft.HPS,
			Turboshaft.transientParameters.inertiaCorrection[0]);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];
	Turboshaft.errOut[1] = Turboshaft.HPC2.y[6];
	Turboshaft.errOut[2] = Turboshaft.HPT.y[6];
	Turboshaft.errOut[3] = Turboshaft.HPT2.y[6];
	Turboshaft.errOut[4] = Turboshaft.LPT.y[6];
	Turboshaft.errOut[5] = Turboshaft.LPT2.y[6];
	Turboshaft.errOut[6] = Turboshaft.Nozzle.y[2];
	SHT_ApplyLowSpeedResidualScaling();
	if (solveShaftSpeed)
	{
		Turboshaft.errOut[7] = Turboshaft.LPS.nDot / 10000.0;
		Turboshaft.errOut[8] = Turboshaft.HPS.nDot / 10000.0;
	}
	for (i = 0; i < dime; ++i)
		errOut[i] = Turboshaft.errOut[i];
	return SHT_STATUS_OK;
}

//------------------------------------------------------------------------------
int TurboshaftRunSteadyComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
	int status;
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		return SHT_RunSplitComponents(varIn, errOut, dime, 1);
	for (i = 0; i < dime; i++)
	{
		Turboshaft.varIte[i] = varIn[i];
		Turboshaft.errOut[i] = 1;
	}
	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];
	Turboshaft.LPS_Nmech = Turboshaft.varIte[4];
	Turboshaft.HPS_Nmech = Turboshaft.varIte[5];

	SHT_UpdateShaftLoadPower();
	status = SHT_ResetEffectiveHealthFromDesignValue();
	if (status != SHT_STATUS_OK)
		return status;
	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK)
		return status;
	status = SHT_ApplyPressureLossSchedule(0,
		Turboshaft.inletMassFlow,
		Turboshaft.Inlet.gasPathIn[2],
		Turboshaft.Inlet.gasPathIn[3],
		&Turboshaft.Inlet.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunInletWithBoundary();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyOriginalRotatingSchedules();
	if (status != SHT_STATUS_OK) return status;

	status = SHT_RunClearanceAdjustedCompressorCore(&Turboshaft.HPC, 0);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_PrepareLegacyCoolingFlows();
	if (status != SHT_STATUS_OK) return status;
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_ApplyPressureLossSchedule(6,
		Turboshaft.Burner.gasPathIn[0],
		Turboshaft.Burner.gasPathIn[2],
		Turboshaft.Burner.gasPathIn[3],
		&Turboshaft.Burner.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	burnRun(&Turboshaft.Burner);
	status = SHT_RunClearanceAdjustedTurbineCore(&Turboshaft.HPT, 1);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(10,
		Turboshaft.Duct2.gasPathIn[0],
		Turboshaft.Duct2.gasPathIn[2],
		Turboshaft.Duct2.gasPathIn[3],
		&Turboshaft.Duct2.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunClearanceAdjustedTurbineCore(&Turboshaft.LPT, 2);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(14,
		Turboshaft.Duct3.gasPathIn[0],
		Turboshaft.Duct3.gasPathIn[2],
		Turboshaft.Duct3.gasPathIn[3],
		&Turboshaft.Duct3.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	shaftRun(&Turboshaft.LPS);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	shaftRun(&Turboshaft.HPS);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];      //HPC_NErr
	Turboshaft.errOut[1] = Turboshaft.HPT.y[6];      //HPT_NErr
	Turboshaft.errOut[2] = Turboshaft.LPT.y[6];      //LPT_NErr
	Turboshaft.errOut[3] = Turboshaft.Nozzle.y[2];   //Nozzle_Nerr
	Turboshaft.errOut[4] = Turboshaft.LPS.nDot / 10000.0;      //LPS_Ndot
	Turboshaft.errOut[5] = Turboshaft.HPS.nDot / 10000.0;      //HPS_Ndot
	for (i = 0; i < dime; i++)
	{
		errOut[i] = Turboshaft.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
 int TurboshaftRunTransientComponents(double *varIn, double *errOut, int dime)
 {
	int i = 0;
	int status;
	/*
     * 起停求解器可拒绝失败试探点并重试，故只在其作用域清理试探诊断。
     * 普通Newton入口保持合入前的错误传播，不清除已有失败原因。
	 */
    if (SHT_LowSpeedResidualScalingActive)
        SHT_ResetTransientEvaluationDiagnostics(
            &Turboshaft.transientDiagnostics);
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		return SHT_RunSplitComponents(varIn, errOut, dime, 0);
	for (i = 0; i < dime; i++)
	{
		Turboshaft.varIte[i] = varIn[i];
		Turboshaft.errOut[i] = 1;
	}
	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];

	SHT_UpdateShaftLoadPower();
	status = SHT_ResetEffectiveHealthFromDesignValue();
	if (status != SHT_STATUS_OK)
		return status;
	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK)
		return status;
	status = SHT_ApplyPressureLossSchedule(0,
		Turboshaft.inletMassFlow,
		Turboshaft.Inlet.gasPathIn[2],
		Turboshaft.Inlet.gasPathIn[3],
		&Turboshaft.Inlet.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunInletWithBoundary();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyOriginalRotatingSchedules();
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunTransientCompressor(&Turboshaft.HPC);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_PrepareLegacyCoolingFlows();
	if (status != SHT_STATUS_OK) return status;
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_ApplyPressureLossSchedule(6,
		Turboshaft.Burner.gasPathIn[0],
		Turboshaft.Burner.gasPathIn[2],
		Turboshaft.Burner.gasPathIn[3],
		&Turboshaft.Burner.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunTransientBurner(&Turboshaft.Burner, 1);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunTransientTurbine(&Turboshaft.HPT, 2,
		SHT_COMPONENT_GT, 1,
		Turboshaft.transientParameters.heatTimeCorrection[2]);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(10,
		Turboshaft.Duct2.gasPathIn[0],
		Turboshaft.Duct2.gasPathIn[2],
		Turboshaft.Duct2.gasPathIn[3],
		&Turboshaft.Duct2.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunTransientTurbine(&Turboshaft.LPT, 3,
		SHT_COMPONENT_PT, 2,
		Turboshaft.transientParameters.heatTimeCorrection[3]);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_ApplyPressureLossSchedule(14,
		Turboshaft.Duct3.gasPathIn[0],
		Turboshaft.Duct3.gasPathIn[2],
		Turboshaft.Duct3.gasPathIn[3],
		&Turboshaft.Duct3.pressureLossModel);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.LPS,
		Turboshaft.transientParameters.inertiaCorrection[1]);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.HPS,
		Turboshaft.transientParameters.inertiaCorrection[0]);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];      //HPC_NErr
	Turboshaft.errOut[1] = Turboshaft.HPT.y[6];      //HPT_NErr
	Turboshaft.errOut[2] = Turboshaft.LPT.y[6];      //LPT_NErr
	Turboshaft.errOut[3] = Turboshaft.Nozzle.y[2];   //Nozzle_Nerr
	SHT_ApplyLowSpeedResidualScaling();
	for (i = 0; i < dime; i++)
	{
		errOut[i] = Turboshaft.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
static int SHT_InitializeDLL(int modelMode)
{
	int i = 0;
	int status;
    if (Turboshaft.isInitial)
        return SHT_ERROR_PARAMETER_VALUE;
    SHT_ResetStartStopEvaluationScope();
    shtHealthScheduleReset(&SHT_HealthSchedule);
	SHT_ResetThermalConfiguration();
	SHT_ResetCoolingSplit();
	SHT_ResetReynoldsCorrection();
	SHT_ResetShaftLoad();
	SHT_NozzleBackPressure = 101325.0;
	SHT_ExplicitNozzleBackPressure = 0;
	Turboshaft.isInitial = 0;
	Turboshaft.isDesOk = 0;
	Turboshaft.timeNow = 0;
	Turboshaft.convergeTag = 1;
	Turboshaft.InletInPt = 0;
	Turboshaft.InletInTt = 0;
	Turboshaft.AmbientPs = 0;
	Turboshaft.useInletBoundaryInput = 0;
	memset(&SHT_InletBoundaryState, 0, sizeof(SHT_InletBoundaryState));
	SHT_ResetTransientData(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		&Turboshaft.transientDiagnostics);
	SHT_ResetHeatEvaluation(&Turboshaft.transientHeatEvaluation);
	SHT_ResetClearanceEvaluation(&Turboshaft.transientClearanceEvaluation);
	status = engineTurboshaftInitialMode(&Turboshaft, modelMode);
	if (status != SHT_STATUS_OK)
		return status;
	status = engineTurboshaftLink(&Turboshaft);
	if (status != SHT_STATUS_OK)
	{
		engineTurboshaftFree(&Turboshaft);
		return status;
	}
	engineTurboshaftSetIdes(&Turboshaft, Turboshaft.offDesignMode);

	for (i = 0; i < Turboshaft.varVecDime; i++)
	{
		Turboshaft.varStartStore[i] = Turboshaft.varStartInput[i];
	}
	SHT_ClearHealthParameters();
	Turboshaft.isDynamicCalculating = 0;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_Initial()
{
	shtFullModeDisable();
	return SHT_InitializeDLL(SHT_MODEL_MODE_ORIGINAL);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_InitialMode(int modelMode)
{
	shtFullModeDisable();
	return SHT_InitializeDLL(modelMode);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_LowSpeedSolverConfigure(
	int version, int parameterCount, double *parameterVector)
{
	if (version != SHT_LOW_SPEED_SOLVER_CONFIG_VERSION ||
		parameterCount != SHT_LOW_SPEED_SOLVER_CONFIG_COUNT ||
		parameterVector == NULL)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	if (parameterVector[0] < 1.0 || parameterVector[1] < 0.0 ||
		parameterVector[2] <= 0.0 || parameterVector[3] <= 0.0 ||
		parameterVector[4] <= 0.0 || parameterVector[4] > 1.0 ||
		parameterVector[5] <= 0.0 || parameterVector[6] <= 0.0 ||
		parameterVector[7] <= 0.0 || parameterVector[8] < 0.0 ||
		parameterVector[9] < 1.0 || parameterVector[9] > 5.0 ||
		parameterVector[10] < 1.0 || parameterVector[10] > 5.0 ||
		parameterVector[11] <= 0.0 || parameterVector[11] > 0.1 ||
		parameterVector[12] <= 0.0 || parameterVector[12] > 0.01)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	SHT_LowSpeedOptions.maxIterations = (int)parameterVector[0];
	SHT_LowSpeedOptions.maxBacktracks = (int)parameterVector[1];
	SHT_LowSpeedOptions.accuracyRequired = parameterVector[2];
	SHT_LowSpeedOptions.disturbanceFactor = parameterVector[3];
	SHT_LowSpeedOptions.minimumStepScale = parameterVector[4];
	SHT_LowSpeedOptions.pivotRelativeTolerance = parameterVector[5];
	SHT_LowSpeedOptions.rankRelativeTolerance = parameterVector[6];
	SHT_LowSpeedFlowReference = parameterVector[7];
	SHT_LowSpeedZeroHoldRpm = parameterVector[8];
	SHT_LowSpeedACPathMaximum = parameterVector[9];
	SHT_LowSpeedCCPathMaximum = parameterVector[10];
	SHT_LowSpeedNozzleFlowBlendPressureRatio = parameterVector[11];
	SHT_LowSpeedShutdownAccuracyRequired = parameterVector[12];
	SHT_LowSpeedOptionsInitialized = 1;
	shtLowSpeedSolverResetDiagnostics(&SHT_LowSpeedDiagnostics);
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
static int SHT_WriteLowSpeedDiagnostics(double *output, int outputLength)
{
	int i;
	if (output == NULL || outputLength < SHT_LOW_SPEED_DIAGNOSTIC_COUNT)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	for (i = 0; i < outputLength; ++i)
		output[i] = 0.0;
	output[0] = (double)SHT_LowSpeedDiagnostics.status;
	output[1] = (double)SHT_LowSpeedDiagnostics.converged;
	output[2] = (double)SHT_LowSpeedDiagnostics.dimension;
	output[3] = (double)SHT_LowSpeedDiagnostics.iterationCount;
	output[4] = (double)SHT_LowSpeedDiagnostics.functionEvaluationCount;
	output[5] = (double)SHT_LowSpeedDiagnostics.jacobianEvaluationCount;
	output[6] = (double)SHT_LowSpeedDiagnostics.acceptedStepCount;
	output[7] = (double)SHT_LowSpeedDiagnostics.rejectedStepCount;
	output[8] = (double)SHT_LowSpeedDiagnostics.effectiveRank;
	output[9] = (double)SHT_LowSpeedDiagnostics.weakestVariableIndex;
	output[10] = (double)SHT_LowSpeedDiagnostics.boundaryHitCount;
	output[11] = SHT_LowSpeedDiagnostics.initialRms;
	output[12] = SHT_LowSpeedDiagnostics.finalRms;
	output[13] = SHT_LowSpeedDiagnostics.finalMaximumAbsoluteResidual;
	output[14] = SHT_LowSpeedDiagnostics.bestRms;
	output[15] = SHT_LowSpeedDiagnostics.lastAcceptedStepScale;
	output[16] = SHT_LowSpeedDiagnostics.scaledJacobianCondition;
	for (i = 0; i < SHT_LOW_SPEED_SOLVER_MAX_DIMENSION; ++i)
	{
		output[17 + i] = SHT_LowSpeedDiagnostics.variable[i];
		output[33 + i] = SHT_LowSpeedDiagnostics.residual[i];
		output[49 + i] = SHT_LowSpeedDiagnostics.jacobianColumnNorm[i];
		output[65 + i] = SHT_LowSpeedDiagnostics.weakestDirection[i];
		output[81 + i] = (double)SHT_LowSpeedDiagnostics.boundaryHit[i];
	}
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_LowSpeedSolverGetDiagnostics(
	double *output, int outputLength)
{
	return SHT_WriteLowSpeedDiagnostics(output, outputLength);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_StartStopConfigure(
	int version, int parameterCount, double *parameterVector)
{
	SHTStartStopConfig config;
	int i;
	int legacy = version == SHT_START_STOP_CONFIG_LEGACY_VERSION &&
		parameterCount == SHT_START_STOP_CONFIG_LEGACY_COUNT;
	int current = version == SHT_START_STOP_CONFIG_VERSION &&
		parameterCount == SHT_START_STOP_CONFIG_COUNT;
	if ((!legacy && !current) || parameterVector == NULL)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	for (i = 0; i < parameterCount; ++i)
		if (!_finite(parameterVector[i]))
			return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	shtStartStopDefaultConfig(&config);
	config.designNpRpm = parameterVector[0];
	config.designNgRpm = parameterVector[1];
	config.idleNgRatio = parameterVector[2];
	config.lightOffNgRatio = parameterVector[3];
	config.selfSustainNgRatio = parameterVector[4];
	config.starterCutoutNgRatio = parameterVector[5];
	config.ignitionDelayS = parameterVector[6];
	config.flameBuildS = parameterVector[7];
	config.starterStallTorqueNm = parameterVector[8];
	config.starterZeroTorqueSpeedRatio = parameterVector[9];
	config.lightOffFuelKgPerS = parameterVector[10];
	config.idleFuelKgPerS = parameterVector[11];
	config.hpsInertiaKgM2 = parameterVector[12];
	config.ptEngineInertiaKgM2 = parameterVector[13];
	config.rotorReflectedInertiaKgM2 = parameterVector[14];
	config.hpsCoulombLossNm = parameterVector[15];
	config.hpsViscousLossNmPerKrpm = parameterVector[16];
	config.hpsWindageLossNmPerKrpm2 = parameterVector[17];
	config.ptCoulombLossNm = parameterVector[18];
	config.ptViscousLossNmPerKrpm = parameterVector[19];
	config.ptWindageLossNmPerKrpm2 = parameterVector[20];
	config.gtAccessoryPowerW = parameterVector[21];
	config.designRotorPowerW = parameterVector[22];
	config.thetaZeroDeg = parameterVector[23];
	config.thetaDesignDeg = parameterVector[24];
	config.profileTorqueFraction = parameterVector[25];
	config.rotorCoulombLossNm = parameterVector[26];
	config.rotorViscousLossNmPerKrpm = parameterVector[27];
	config.freewheelSpeedToleranceRpm = parameterVector[28];
	if (current) config.maximumGasTemperatureK = parameterVector[29];
	return shtStartStopConfigure(&config);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_StartStopReset(
	double ngRpm, double npRpm, double rotorEquivalentRpm,
	int freewheelEngaged)
{
	if (shtStartStopGetState()->configured == 0)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	shtStartStopReset(ngRpm, npRpm, rotorEquivalentRpm, freewheelEngaged);
	return SHT_STATUS_OK;
}
// 会话状态和负载使用独立版本与显式长度，不改变任何旧输入索引。
extern _declspec(dllexport) int DLL_SHT_FullModeSetLoad(int version, int count, double *values)
{
	return shtFullModeSetLoad(version, count, values);
}
extern _declspec(dllexport) int DLL_SHT_FullModeExportState(int version, int count, double *values)
{
	return shtFullModeExportState(version, count, values);
}
extern _declspec(dllexport) int DLL_SHT_FullModeImportState(int version, int count, double *values)
{
	return shtFullModeImportState(version, count, values);
}
//------------------------------------------------------------------------------
static void SHT_WriteStartStopPhysicsOutput(
	const SHTStartStopOutput *source, double *target)
{
	target[0] = source->ngDotRpmPerS;
	target[1] = source->npDotRpmPerS;
	target[2] = source->rotorEquivalentDotRpmPerS;
	target[3] = (double)source->phase;
	target[4] = source->starterTorqueNm;
	target[5] = source->effectiveFuelKgPerS;
	target[6] = source->flameFraction;
	target[7] = source->hpsLossTorqueNm;
	target[8] = source->ptLossTorqueNm;
	target[9] = source->rotorLoadTorqueNm;
	target[10] = source->freewheelTorqueNm;
	target[11] = (double)source->freewheelEngaged;
	target[12] = (double)source->eventCode;
	target[13] = (double)source->hotStartFlag;
	target[14] = (double)source->hungStartFlag;
	target[15] = (double)source->flameoutFlag;
	target[16] = source->requiredFreewheelTorqueNm;
	target[17] = source->hpsNetTorqueNm;
	target[18] = source->ptNetTorqueNm;
	target[19] = source->rotorNetTorqueNm;
	target[20] = source->phaseTimeS;
	target[21] = source->totalTimeS;
	target[22] = source->combustionEfficiency;
	target[23] = (double)source->valid;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_StartStopPhysicsStep(
	double *inputVector, int inputCount,
	double *outputVector, int outputCount)
{
	SHTStartStopInput input;
	SHTStartStopOutput output;
	double effectiveFuel;
	int phase;
	int status;
	if (inputVector == NULL || outputVector == NULL ||
		inputCount != SHT_START_STOP_PHYSICS_INPUT_COUNT ||
		outputCount < SHT_START_STOP_PHYSICS_OUTPUT_COUNT)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	memset(outputVector, 0, (size_t)outputCount * sizeof(double));
	input.timeStepS = inputVector[0];
	input.command = (int)inputVector[1];
	input.ngRpm = inputVector[2];
	input.npRpm = inputVector[3];
	input.rotorEquivalentRpm = inputVector[4];
	input.hpsGasNetTorqueNm = inputVector[5];
	input.ptGasTorqueNm = inputVector[6];
	input.commandedFuelKgPerS = inputVector[7];
	input.collectivePitchDeg = inputVector[8];
	input.ignitionEnabled = (int)inputVector[9];
	input.measuredGasTemperatureK = inputVector[10];
	input.hpsAccessoryPowerW = inputVector[11];
	status = shtStartStopPrepare(&input, &effectiveFuel, &phase);
	if (status != 0) return status;
	status = shtStartStopAdvance(&input, &output);
	if (status != 0) return status;
	SHT_WriteStartStopPhysicsOutput(&output, outputVector);
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_InitializeReynoldsCorrection(
	int version,
	int parameterCount,
	double *parameterVector)
{
	SHTReynoldsCorrectionConfiguration candidate;
	int i;
	if (!Turboshaft.isInitial ||
		(Turboshaft.modelMode != SHT_MODEL_MODE_ORIGINAL &&
		 Turboshaft.modelMode != SHT_MODEL_MODE_SPLIT))
		return SHT_ERROR_PARAMETER_VALUE;
	if (version != SHT_REYNOLDS_CONFIG_VERSION ||
		parameterCount != SHT_REYNOLDS_PARAMETER_COUNT ||
		parameterVector == NULL)
		return SHT_ERROR_PARAMETER_VALUE;
	memset(&candidate, 0, sizeof(candidate));
	candidate.flowLossFraction = parameterVector[0];
	if (!_finite(candidate.flowLossFraction) ||
		candidate.flowLossFraction < 0.0 ||
		candidate.flowLossFraction > 1.0)
		return SHT_ERROR_PARAMETER_VALUE;
	for (i = 0; i < SHT_REYNOLDS_COMPONENT_COUNT; ++i)
	{
		int offset = 1 + 7 * i;
		double enabledValue = parameterVector[offset];
		SHTReynoldsComponentConfiguration *component =
			&candidate.component[i];
		if (!_finite(enabledValue) ||
			(enabledValue != 0.0 && enabledValue != 1.0))
			return SHT_ERROR_PARAMETER_VALUE;
		component->enabled = enabledValue > 0.5 ? 1 : 0;
		/* ABI仍为6槽。三部件按实际调用索引使用HPC/GT/PT，尾3槽禁用。
		 * 六部件仍按AC/CC/GT1/GT2/PT1/PT2解释，不截取其设计数值。 */
		if (Turboshaft.modelMode == SHT_MODEL_MODE_ORIGINAL &&
			i >= 3 && component->enabled)
			return SHT_ERROR_PARAMETER_VALUE;
		component->designTemperature = parameterVector[offset + 1];
		component->designPressure = parameterVector[offset + 2];
		component->lowIndex = parameterVector[offset + 3];
		component->lowEfficiencyFactor = parameterVector[offset + 4];
		component->highIndex = parameterVector[offset + 5];
		component->highEfficiencyFactor = parameterVector[offset + 6];
		if (!_finite(component->designTemperature) ||
			component->designTemperature <= 0.0 ||
			!_finite(component->designPressure) ||
			component->designPressure <= 0.0 ||
			!_finite(component->lowIndex) ||
			component->lowIndex <= 0.0 ||
			!_finite(component->highIndex) ||
			component->highIndex <= component->lowIndex ||
			!_finite(component->lowEfficiencyFactor) ||
			component->lowEfficiencyFactor <= 0.0 ||
			!_finite(component->highEfficiencyFactor) ||
			component->highEfficiencyFactor <= 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	candidate.configured = 1;
	SHT_ReynoldsCorrection = candidate;
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_ReynoldsCorrectionGetStatus(void)
{
	int i;
	int enabledCount = 0;
	if (!Turboshaft.isInitial ||
		(Turboshaft.modelMode != SHT_MODEL_MODE_ORIGINAL &&
		 Turboshaft.modelMode != SHT_MODEL_MODE_SPLIT))
		return SHT_ERROR_PARAMETER_VALUE;
	if (!SHT_ReynoldsCorrection.configured)
		return 0;
	for (i = 0; i < SHT_REYNOLDS_COMPONENT_COUNT; ++i)
		enabledCount += SHT_ReynoldsCorrection.component[i].enabled ? 1 : 0;
	return enabledCount;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_InitializeThermalConfig(
	int thermalModelMode,
	int configVersion,
	int parameterCount,
	double *parameterVector)
{
	if (!Turboshaft.isInitial)
		return SHT_ERROR_THERMAL_CONFIG_NOT_INITIALIZED;
	return SHT_InitializeThermalConfiguration(
		Turboshaft.modelMode,
		thermalModelMode,
		configVersion,
		parameterCount,
		parameterVector);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_ThermalConfigGetStatus(
	int thermalModelMode)
{
	if (!Turboshaft.isInitial)
		return SHT_ERROR_THERMAL_CONFIG_NOT_INITIALIZED;
	return SHT_GetThermalConfigurationStatus(
		Turboshaft.modelMode, thermalModelMode);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_InitializeCoolingSplit(
	int version,
	int parameterCount,
	double *ratio)
{
	if (!Turboshaft.isInitial)
		return SHT_ERROR_THERMAL_CONFIG_MODEL_MISMATCH;
	return SHT_InitializeCoolingSplit(version, parameterCount, ratio);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_CoolingSplitGetStatus(void)
{
	if (!Turboshaft.isInitial)
		return SHT_ERROR_THERMAL_CONFIG_MODEL_MISMATCH;
	return SHT_GetCoolingSplitStatus();
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_HealthScheduleReset(void)
{
	shtHealthScheduleReset(&SHT_HealthSchedule);
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
static int SHT_ExpectedHealthScheduleAxis(int modelMode, int healthIndex)
{
	if(healthIndex == 0) return SHT_HEALTH_AXIS_INLET_CORRECTED_FLOW;
	if(healthIndex == 6) return SHT_HEALTH_AXIS_BURNER_CORRECTED_FLOW;
	if(healthIndex == 10) return SHT_HEALTH_AXIS_GT_PT_DUCT_CORRECTED_FLOW;
	if(healthIndex == 14)
		return SHT_HEALTH_AXIS_PT_NOZZLE_DUCT_CORRECTED_FLOW;
	if(healthIndex >= 1 && healthIndex <= 3)
		return SHT_HEALTH_AXIS_AC_CORRECTED_SPEED;
	if(healthIndex >= 7 && healthIndex <= 9)
		return SHT_HEALTH_AXIS_GT_TOTAL_PRESSURE_RATIO;
	if(healthIndex >= 11 && healthIndex <= 13)
		return SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO;
	if(modelMode != SHT_MODEL_MODE_SPLIT)
		return SHT_HEALTH_AXIS_NONE;
	if(healthIndex >= 71 && healthIndex <= 73)
		return SHT_HEALTH_AXIS_AC_CORRECTED_SPEED;
	if(healthIndex >= 74 && healthIndex <= 76)
		return SHT_HEALTH_AXIS_CC_CORRECTED_SPEED;
	if(healthIndex >= 77 && healthIndex <= 82)
		return SHT_HEALTH_AXIS_GT_TOTAL_PRESSURE_RATIO;
	if(healthIndex >= 83 && healthIndex <= 88)
		return SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO;
	return SHT_HEALTH_AXIS_NONE;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_HealthScheduleConfigureTable(
	int healthIndex,
	int axisType,
	int nodeCount,
	double *xNode,
	double *deltaNode)
{
	int expectedAxis = SHT_ExpectedHealthScheduleAxis(
		Turboshaft.modelMode, healthIndex);
	if(!Turboshaft.isInitial)
		return SHT_ERROR_PARAMETER_VALUE;
	if(expectedAxis == SHT_HEALTH_AXIS_NONE || axisType != expectedAxis)
		return SHT_ERROR_PARAMETER_VALUE;
	if((axisType >= SHT_HEALTH_AXIS_INLET_CORRECTED_FLOW &&
		axisType <= SHT_HEALTH_AXIS_PT_NOZZLE_DUCT_CORRECTED_FLOW &&
		(nodeCount < 2 || nodeCount > SHT_HEALTH_SCHEDULE_MAX_NODES ||
		 xNode == NULL || xNode[0] != 0.0)) ||
	   (axisType >= SHT_HEALTH_AXIS_AC_CORRECTED_SPEED &&
		axisType <= SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO &&
		(nodeCount < 1 || nodeCount > SHT_HEALTH_SCHEDULE_MAX_NODES)))
		return SHT_ERROR_PARAMETER_VALUE;
	return shtHealthScheduleConfigureTable(
		&SHT_HealthSchedule, healthIndex, axisType,
		nodeCount, xNode, deltaNode);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_HealthScheduleSetEnabled(int enabled)
{
	if(!Turboshaft.isInitial)
		return SHT_ERROR_PARAMETER_VALUE;
	if(enabled != 0 &&
		SHT_HealthSchedule.configuredCount !=
			SHT_ExpectedHealthScheduleTableCount())
		return SHT_ERROR_PARAMETER_VALUE;
	return shtHealthScheduleSetEnabled(&SHT_HealthSchedule, enabled);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_HealthScheduleGetConfiguredCount(void)
{
	return SHT_HealthSchedule.configuredCount;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_HealthScheduleEvaluateIncrement(
	int healthIndex,
	double coordinate,
	double *incrementValue)
{
	return shtHealthScheduleEvaluateIncrement(
		&SHT_HealthSchedule, healthIndex, coordinate, incrementValue);
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_Free()
{
    SHT_ResetStartStopEvaluationScope();
	if (!Turboshaft.isInitial)
	{
		shtHealthScheduleReset(&SHT_HealthSchedule);
		SHT_ResetThermalConfiguration();
		SHT_ResetCoolingSplit();
		SHT_ResetReynoldsCorrection();
		SHT_ResetShaftLoad();
		SHT_NozzleBackPressure = 101325.0;
		SHT_ExplicitNozzleBackPressure = 0;
		return 0;
	}
	engineTurboshaftFree(&Turboshaft);
	shtHealthScheduleReset(&SHT_HealthSchedule);
	SHT_ResetThermalConfiguration();
	SHT_ResetCoolingSplit();
	SHT_ResetReynoldsCorrection();
	SHT_ResetShaftLoad();
	SHT_NozzleBackPressure = 101325.0;
	SHT_ExplicitNozzleBackPressure = 0;
	memset(SHT_HealthDesignValue, 0, sizeof(SHT_HealthDesignValue));
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_varIteInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int i = 0;

	for (i = 0; i < Turboshaft.varVecDime; i++)
	{
		Turboshaft.varStartStore[i] = stepIn[i + 20];
	}

	engptr->eng = &Turboshaft;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_ConditionsInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int status = SHT_ReadInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}

	engptr->eng = &Turboshaft;
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunOnePoint(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int status;
	double externalAirEnabled;
	int varDime = Turboshaft.varVecDime;
	SHT_ClearStepOut(stepOut);
	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}

	status = SHT_ReadRuntimeInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	status = SHT_ReadShaftLoad(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.HPC.alphaIn = stepIn[8];
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		Turboshaft.HPC2.alphaIn = 0.0;
	if (!_finite(stepIn[4]) || stepIn[4] < 0.0 || stepIn[4] > 1.0)
	{
		engptr->eng = &Turboshaft;
		return SHT_SetExternalBleedInputError();
	}
	externalAirEnabled = stepIn[4] > 0.5 ? 1.0 : 0.0;
	Turboshaft.HPT.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT.extSecAirSys = externalAirEnabled;
	Turboshaft.HPT2.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT2.extSecAirSys = externalAirEnabled;
	if (externalAirEnabled > 0.5)
	{
		status = SHT_LoadExternalBleedInput(stepIn);
		if (status != SHT_STATUS_OK)
		{
			engptr->eng = &Turboshaft;
			return status;
		}
	}
	status = SHT_LoadHealthParameters(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}

	Turboshaft.convergeTag = newtonSolver(TurboshaftRunSteadyComponents,
		Turboshaft.varVecDime,
		Turboshaft.varStartStore, Turboshaft.varMin, Turboshaft.varMax, Turboshaft.varDelLim,
		Turboshaft.accuracyReq,
		Turboshaft.distuFactor,
		Turboshaft.maxIterations);
	if (Turboshaft.transientDiagnostics.errorCode != SHT_STATUS_OK)
	{
		status = Turboshaft.transientDiagnostics.errorCode;
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}

	engptr->eng = &Turboshaft;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunOneStep(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int status;
	int finiteLength;
	int validIndex;
	double externalAirEnabled;
	int varDime  = Turboshaft.varVecDime - 2;
	SHT_ClearStepOut(stepOut);
	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	
	status = SHT_ReadRuntimeInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.LPS_Nmech = stepIn[0];
	Turboshaft.HPS_Nmech = stepIn[1];
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	status = SHT_ReadShaftLoad(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.HPC.alphaIn = stepIn[8];
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		Turboshaft.HPC2.alphaIn = 0.0;
	if (!_finite(stepIn[4]) || stepIn[4] < 0.0 || stepIn[4] > 1.0)
	{
		engptr->eng = &Turboshaft;
		return SHT_SetExternalBleedInputError();
	}
	externalAirEnabled = stepIn[4] > 0.5 ? 1.0 : 0.0;
	Turboshaft.HPT.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT.extSecAirSys = externalAirEnabled;
	Turboshaft.HPT2.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT2.extSecAirSys = externalAirEnabled;

	if (externalAirEnabled > 0.5)
	{
		status = SHT_LoadExternalBleedInput(stepIn);
		if (status != SHT_STATUS_OK)
		{
			engptr->eng = &Turboshaft;
			return status;
		}
	}

	status = SHT_LoadHealthParameters(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_EvaluateCurrentClearance();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}

	Turboshaft.convergeTag = newtonSolver(TurboshaftRunTransientComponents,
		varDime,
		Turboshaft.varStartStore, Turboshaft.varMin, Turboshaft.varMax, Turboshaft.varDelLim,
		Turboshaft.accuracyReq,
		Turboshaft.distuFactor,
		Turboshaft.maxIterations);
	if (Turboshaft.transientDiagnostics.errorCode != SHT_STATUS_OK)
	{
		status = Turboshaft.transientDiagnostics.errorCode;
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	if (Turboshaft.convergeTag == 0 &&
		Turboshaft.transientControl.heatStateEnable)
	{
		status = SHT_EvaluateCurrentHeatState();
		if (status != SHT_STATUS_OK)
		{
			SHT_ClearStepOut(stepOut);
			engptr->eng = &Turboshaft;
			return status;
		}
	}

	stepOut[0] = Turboshaft.LPS.nDot;
	stepOut[1] = Turboshaft.HPS.nDot;
	if (Turboshaft.transientControl.heatStateEnable)
		SHT_WriteHeatStateDerivatives(stepOut, 2,
			2 + Turboshaft.transientControl.metalNodeCount,
			2 + Turboshaft.transientControl.metalNodeCount +
				Turboshaft.transientControl.diskNodeCount);
	finiteLength = Turboshaft.transientControl.heatStateEnable ?
		2 + Turboshaft.transientControl.metalNodeCount +
			Turboshaft.transientControl.diskNodeCount +
			Turboshaft.transientControl.guideVaneNodeCount : 2;
	/* 输出布局跟随初始化时已经固定的发动机拓扑，不由 stepIn 选择。 */
	validIndex = Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT ?
		(Turboshaft.transientControl.thermalModelMode ==
		 SHT_THERMAL_MODEL_VISSER ? 29 : 27) :
		(Turboshaft.transientControl.thermalModelMode == SHT_THERMAL_MODEL_VISSER ? 16 : 15);
	SHT_SetEvaluationValidity(stepOut, validIndex,
		Turboshaft.convergeTag == 0 &&
		SHT_IsFiniteVector(stepOut, finiteLength));
	engptr->eng = &Turboshaft;
	
	return 0;
}
//------------------------------------------------------------------------------
static void SHT_WriteStartStopStepOutput(
	const SHTStartStopOutput *physics,
	double *stepOut,
	int gasPathValid)
{
	/* 0/1延续原RunOneStep的NpDot/NgDot顺序，2新增旋翼等效转速导数。 */
	stepOut[0] = physics->npDotRpmPerS;
	stepOut[1] = physics->ngDotRpmPerS;
	stepOut[2] = physics->rotorEquivalentDotRpmPerS;
	stepOut[3] = (double)physics->phase;
	stepOut[4] = physics->starterTorqueNm;
	stepOut[5] = physics->effectiveFuelKgPerS;
	stepOut[6] = physics->flameFraction;
	stepOut[7] = physics->hpsLossTorqueNm;
	stepOut[8] = physics->ptLossTorqueNm;
	stepOut[9] = physics->rotorLoadTorqueNm;
	stepOut[10] = physics->freewheelTorqueNm;
	stepOut[11] = (double)physics->freewheelEngaged;
	stepOut[12] = (double)physics->eventCode;
	stepOut[13] = physics->requiredFreewheelTorqueNm;
	stepOut[14] = physics->hpsNetTorqueNm;
	stepOut[15] = physics->ptNetTorqueNm;
	stepOut[16] = physics->rotorNetTorqueNm;
	stepOut[17] = physics->phaseTimeS;
	stepOut[18] = physics->totalTimeS;
	stepOut[19] = physics->combustionEfficiency;
	stepOut[20] = (double)physics->hotStartFlag;
	stepOut[21] = (double)physics->hungStartFlag;
	stepOut[22] = (double)physics->flameoutFlag;
	stepOut[23] = (double)(physics->valid && gasPathValid);
	/* 高频读取只放核心求解诊断；完整97项由GetDiagnostics单独读取。 */
	stepOut[64] = (double)SHT_LowSpeedDiagnostics.status;
	stepOut[65] = (double)SHT_LowSpeedDiagnostics.converged;
	stepOut[66] = (double)SHT_LowSpeedDiagnostics.iterationCount;
	stepOut[67] = (double)SHT_LowSpeedDiagnostics.functionEvaluationCount;
	stepOut[68] = SHT_LowSpeedDiagnostics.initialRms;
	stepOut[69] = SHT_LowSpeedDiagnostics.finalRms;
	stepOut[70] = SHT_LowSpeedDiagnostics.finalMaximumAbsoluteResidual;
	stepOut[71] = SHT_LowSpeedDiagnostics.scaledJacobianCondition;
	stepOut[72] = (double)SHT_LowSpeedDiagnostics.effectiveRank;
	stepOut[73] = (double)SHT_LowSpeedDiagnostics.weakestVariableIndex;
	stepOut[74] = (double)SHT_LowSpeedDiagnostics.boundaryHitCount;
	stepOut[75] = Turboshaft.HPS_Trq;
	stepOut[76] = Turboshaft.LPS_Trq;
	stepOut[77] = (double)Turboshaft.convergeTag;
}

static void SHT_LoadStartStopGasVariableBounds(
	double *minimum, double *maximum, double *maximumIncrement,
	int useExpandedCompressorPath)
{
	int i;
	for (i = 0; i < Turboshaft.varVecDime - 2; ++i)
	{
		minimum[i] = Turboshaft.varMin[i];
		maximum[i] = Turboshaft.varMax[i];
		maximumIncrement[i] = Turboshaft.varDelLim[i];
	}
	/*
	 * AC/CC高Rline尾部只属于起停专用特性图及专用求解入口。普通入口
	 * 继续使用MDL中的原边界，避免低速数学扩展改变正常区Newton路径。
	 */
	if (useExpandedCompressorPath)
	{
		maximum[1] = SHT_LowSpeedACPathMaximum;
		if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
			maximum[2] = SHT_LowSpeedCCPathMaximum;
	}
}

static int SHT_LoadStartStopSeed(const double *stepIn,
	const double *minimum, const double *maximum)
{
	int i;
	if (stepIn[SHT_START_STOP_SEED_ENABLE_INDEX] <= 0.5)
		return SHT_STATUS_OK;
	for (i = 0; i < Turboshaft.varVecDime - 2; ++i)
	{
		double value = stepIn[20 + i];
		if (!_finite(value) || value < minimum[i] || value > maximum[i])
			return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
		Turboshaft.varStartStore[i] = value;
	}
	return SHT_STATUS_OK;
}

/*
 * 三/六部件起停专用联合入口。模型拓扑只由初始化接口决定。
 * 它不替换RunOneStep：只有本入口才会启用
 * 低流量残差、增强Newton和近零转矩正则化。阶段五以后可继续在该
 * 接口上校准低速图，而常规飞行/试车模型保持原路径。
 */
static int SHT_RunStartStopStep(
	double *stepIn, double *stepOut, EngineSHTPointer *engptr)
{
	SHTStartStopState stateBefore;
	SHTStartStopInput physicsInput;
	SHTStartStopOutput physicsOutput;
	SHTLowSpeedSolverOptions stepSolverOptions;
	double effectiveFuel = 0.0;
	double previousEffectiveFuel = 0.0;
	double solverFuel = 0.0;
	double externalAirEnabled;
	double gasVariableMinimum[SHT_SPLIT_GAS_VARIABLE_COUNT];
	double gasVariableMaximum[SHT_SPLIT_GAS_VARIABLE_COUNT];
	double gasVariableMaximumIncrement[SHT_SPLIT_GAS_VARIABLE_COUNT];
	int phase = SHT_START_STOP_PHASE_STOPPED;
	int status;
	int solverStatus;
	int solverPass;
	int solverPassCount;
	int zeroHold;
	int gasPathValid = 0;
	if (stepIn == NULL || stepOut == NULL || engptr == NULL ||
		!Turboshaft.isInitial ||
		shtStartStopGetState()->configured == 0)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	SHT_ClearStepOut(stepOut);
	/* 起停轴负载由独立轴系模型拥有，stepIn[6]仍为附件功率W。
	 * 禁止将常规入口遗留的扭矩模式或功率重复施加到气路。 */
	if (stepIn[SHT_SHAFT_LOAD_MODE_INDEX] != 0.0)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	SHT_ResetShaftLoad();
	if (!SHT_LowSpeedOptionsInitialized)
	{
		shtLowSpeedSolverDefaultOptions(&SHT_LowSpeedOptions);
		SHT_LowSpeedOptions.accuracyRequired = Turboshaft.accuracyReq;
		SHT_LowSpeedOptionsInitialized = 1;
	}

	/*
	 * 单步求解采用事务语义：Newton失败时不能消耗点火延迟、改变火焰
	 * 比例或提前进入停车阶段。MATLAB多初值重试因此始终对应同一物理
	 * 时刻，而不是把一次数值重试误算成一次状态推进。
	 */
	stateBefore = *shtStartStopGetState();
	previousEffectiveFuel = stateBefore.effectiveFuelKgPerS;
	memset(&physicsInput, 0, sizeof(physicsInput));
	physicsInput.timeStepS = stepIn[SHT_START_STOP_TIME_STEP_INDEX];
	physicsInput.command = (int)stepIn[SHT_START_STOP_COMMAND_INDEX];
	physicsInput.npRpm = stepIn[0];
	physicsInput.ngRpm = stepIn[1];
	physicsInput.rotorEquivalentRpm =
		stepIn[SHT_START_STOP_ROTOR_EQUIVALENT_SPEED_INDEX];
	physicsInput.commandedFuelKgPerS = stepIn[2];
	physicsInput.collectivePitchDeg =
		stepIn[SHT_START_STOP_COLLECTIVE_PITCH_INDEX];
	physicsInput.ignitionEnabled =
		(int)stepIn[SHT_START_STOP_IGNITION_ENABLE_INDEX];
	physicsInput.measuredGasTemperatureK =
		stepIn[SHT_START_STOP_GAS_TEMPERATURE_INDEX];
	physicsInput.hpsAccessoryPowerW = stepIn[6];
	status = shtStartStopPrepare(&physicsInput, &effectiveFuel, &phase);
	if (status != SHT_STATUS_OK)
	{
		shtStartStopRestoreState(&stateBefore);
		return status;
	}

	/*
	 * 无燃油且燃气发生器低于气路激活门限时，主流质量流量与两轴燃气
	 * 力矩按零能量渐近处理。自由涡轮和旋翼仍可在较高转速下惯性滑转，
	 * 其减速继续由后续轴系、负载和自由轮模型计算，不能错误地要求Np也
	 * 低于按Ng设计转速定义的同一门限。
	 */
	zeroHold = fabs(physicsInput.ngRpm) <= SHT_LowSpeedZeroHoldRpm &&
		effectiveFuel <= 0.0;
	if (zeroHold)
	{
		/* 阶段六关闭增强瞬态效应时完全沿用原零速路径。 */
		status = SHT_PrepareTransientConfiguration(stepIn);
		if (status != SHT_STATUS_OK)
		{
			shtStartStopRestoreState(&stateBefore);
			return status;
		}
		if (stepIn[SHT_INPUT_TRANSIENT_EFFECTS_ENABLE] > 0.5)
		{
			status = SHT_LoadHealthParameters(stepIn);
			if (status != SHT_STATUS_OK)
			{
				shtStartStopRestoreState(&stateBefore);
				return status;
			}
			Turboshaft.LPS_Nmech = physicsInput.npRpm;
			Turboshaft.HPS_Nmech = physicsInput.ngRpm;
			status = SHT_EvaluateCurrentClearance();
			if (status == SHT_STATUS_OK)
				status = SHT_EvaluateZeroFlowVisserHeatState();
			if (status != SHT_STATUS_OK)
			{
				shtStartStopRestoreState(&stateBefore);
				return status;
			}
		}
		shtLowSpeedSolverResetDiagnostics(&SHT_LowSpeedDiagnostics);
		SHT_LowSpeedDiagnostics.status = SHT_LOW_SPEED_SOLVER_ZERO_HOLD;
		SHT_LowSpeedDiagnostics.converged = 1;
		physicsInput.hpsGasNetTorqueNm = 0.0;
		physicsInput.ptGasTorqueNm = 0.0;
		status = shtStartStopAdvance(&physicsInput, &physicsOutput);
		if (status != SHT_STATUS_OK)
		{
			shtStartStopRestoreState(&stateBefore);
			return status;
		}
		Turboshaft.HPS_Trq = 0.0;
		Turboshaft.LPS_Trq = 0.0;
		Turboshaft.convergeTag = SHT_LOW_SPEED_SOLVER_ZERO_HOLD;
		SHT_WriteStartStopStepOutput(&physicsOutput, stepOut, 1);
		if (Turboshaft.transientControl.heatStateEnable)
			SHT_WriteHeatStateDerivatives(stepOut,
				SHT_START_STOP_METAL_DERIVATIVE_START_INDEX,
				SHT_START_STOP_DISK_DERIVATIVE_START_INDEX,
				SHT_START_STOP_GUIDE_DERIVATIVE_START_INDEX);
		engptr->eng = &Turboshaft;
		return SHT_STATUS_OK;
	}

	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		shtStartStopRestoreState(&stateBefore);
		return status;
	}
	status = SHT_ReadRuntimeInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		shtStartStopRestoreState(&stateBefore);
		return status;
	}
	Turboshaft.LPS_Nmech = physicsInput.npRpm;
	Turboshaft.HPS_Nmech = physicsInput.ngRpm;
	Turboshaft.fuelFlowInput = effectiveFuel;
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	/* 轴负载由起停物理内核统一计算，气路求解中不再重复扣除。 */
	Turboshaft.LPS_Power = 0.0;
	Turboshaft.HPS_Power = 0.0;
	Turboshaft.HPC.alphaIn = stepIn[8];
	Turboshaft.HPC2.alphaIn = 0.0;
	if (!_finite(stepIn[4]) || stepIn[4] < 0.0 || stepIn[4] > 1.0)
	{
		shtStartStopRestoreState(&stateBefore);
		return SHT_SetExternalBleedInputError();
	}
	externalAirEnabled = stepIn[4] > 0.5 ? 1.0 : 0.0;
	Turboshaft.HPT.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT.extSecAirSys = externalAirEnabled;
	Turboshaft.HPT2.extSecAirSys = externalAirEnabled;
	Turboshaft.LPT2.extSecAirSys = externalAirEnabled;
	if (externalAirEnabled > 0.5)
	{
		status = SHT_LoadExternalBleedInput(stepIn);
		if (status != SHT_STATUS_OK)
		{
			shtStartStopRestoreState(&stateBefore);
			return status;
		}
	}
	status = SHT_LoadHealthParameters(stepIn);
	if (status != SHT_STATUS_OK)
	{
		shtStartStopRestoreState(&stateBefore);
		return status;
	}
	status = SHT_EvaluateCurrentClearance();
	if (status != SHT_STATUS_OK)
	{
		shtStartStopRestoreState(&stateBefore);
		return status;
	}

	SHT_LowSpeedResidualScalingActive = 1;
	shtStartStopSetTorqueRegularizationEnabled(1);
	/*
	 * 首次切油会使有火与无火共同工作根发生有限跳变。这里在固定轴速、
	 * 不推进物理时间的条件下，用8个燃油同伦点连续送到零燃油根。
	 * 其余时间步仍只执行一次Newton，不增加正常任务计算量。
	 */
	solverPassCount =
		stateBefore.phase != SHT_START_STOP_PHASE_SHUTDOWN &&
		phase == SHT_START_STOP_PHASE_SHUTDOWN &&
		previousEffectiveFuel > 0.0 ? 8 : 1;
	solverStatus = SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	stepSolverOptions = SHT_LowSpeedOptions;
	if (phase == SHT_START_STOP_PHASE_SHUTDOWN &&
		effectiveFuel <= 0.0 &&
		stepSolverOptions.accuracyRequired <
		SHT_LowSpeedShutdownAccuracyRequired)
		stepSolverOptions.accuracyRequired =
			SHT_LowSpeedShutdownAccuracyRequired;
	for (solverPass = 1; solverPass <= solverPassCount; ++solverPass)
	{
		solverFuel = solverPassCount > 1 ?
			previousEffectiveFuel *
			(double)(solverPassCount - solverPass) /
			(double)solverPassCount : effectiveFuel;
		Turboshaft.fuelFlowInput = solverFuel;
		SHT_LoadStartStopGasVariableBounds(gasVariableMinimum,
			gasVariableMaximum, gasVariableMaximumIncrement,
			solverFuel > 0.0);
		if (solverPass == 1)
		{
			status = SHT_LoadStartStopSeed(stepIn, gasVariableMinimum,
				gasVariableMaximum);
			if (status != SHT_STATUS_OK)
			{
				solverStatus = status;
				break;
			}
		}
		solverStatus = shtLowSpeedNewtonSolver(
			TurboshaftRunTransientComponents, Turboshaft.varVecDime - 2,
			Turboshaft.varStartStore, gasVariableMinimum, gasVariableMaximum,
			gasVariableMaximumIncrement, &stepSolverOptions,
			&SHT_LowSpeedDiagnostics);
		if (solverStatus != SHT_LOW_SPEED_SOLVER_CONVERGED)
			break;
	}
	Turboshaft.fuelFlowInput = effectiveFuel;
	shtStartStopSetTorqueRegularizationEnabled(0);
	SHT_LowSpeedResidualScalingActive = 0;
	Turboshaft.convergeTag = solverStatus;
	gasPathValid = solverStatus == SHT_LOW_SPEED_SOLVER_CONVERGED &&
		Turboshaft.transientDiagnostics.errorCode == SHT_STATUS_OK;
	if (gasPathValid)
	{
		if (Turboshaft.transientControl.heatStateEnable)
		{
			status = SHT_EvaluateCurrentHeatState();
			if (status != SHT_STATUS_OK)
			{
				shtStartStopRestoreState(&stateBefore);
				SHT_ClearStepOut(stepOut);
				engptr->eng = &Turboshaft;
				return status;
			}
		}
		physicsInput.hpsGasNetTorqueNm = Turboshaft.HPS_Trq;
		physicsInput.ptGasTorqueNm = Turboshaft.LPS_Trq;
		status = shtStartStopAdvance(&physicsInput, &physicsOutput);
		if (status != SHT_STATUS_OK)
		{
			shtStartStopRestoreState(&stateBefore);
			return status;
		}
		SHT_WriteStartStopStepOutput(&physicsOutput, stepOut, 1);
		if (Turboshaft.transientControl.heatStateEnable)
			SHT_WriteHeatStateDerivatives(stepOut,
				SHT_START_STOP_METAL_DERIVATIVE_START_INDEX,
				SHT_START_STOP_DISK_DERIVATIVE_START_INDEX,
				SHT_START_STOP_GUIDE_DERIVATIVE_START_INDEX);
	}
	else
	{
		shtStartStopRestoreState(&stateBefore);
		memset(&physicsOutput, 0, sizeof(physicsOutput));
		physicsOutput.phase = phase;
		physicsOutput.effectiveFuelKgPerS = effectiveFuel;
		physicsOutput.freewheelEngaged =
			shtStartStopGetState()->freewheelEngaged;
		SHT_WriteStartStopStepOutput(&physicsOutput, stepOut, 0);
	}
	engptr->eng = &Turboshaft;
	return SHT_STATUS_OK;
}
//------------------------------------------------------------------------------
/* 正步长保持原有事务推进；零步长用于Heun预测/校正端点的瞬时评估。
 * 端点评估仍计算当前气路、热导数和自由轮力矩，但无论成功或失败，均
 * 恢复起停状态机（阶段、计时、火焰、自由轮及待发事件）。Engine结构
 * 保留此次代数评估输出供调用方读取，不承载外部积分的转速/温度状态。
 * 不改变公开函数签名、结构体或stepIn布局，历史正步长行为不变。 */
extern _declspec(dllexport) int DLL_SHT_RunStartStopStep(
	double *stepIn, double *stepOut, EngineSHTPointer *engptr)
{
    SHTStartStopState savedState;
    int status;
    int endpoint = stepIn != NULL &&
        stepIn[SHT_START_STOP_TIME_STEP_INDEX] == 0.0;
    if (endpoint)
        savedState = *shtStartStopGetState();
    status = SHT_RunStartStopStep(stepIn, stepOut, engptr);
    if (endpoint)
        shtStartStopRestoreState(&savedState);
    /* 所有正常/失败返回统一清场，包括参数检查的提前退出。 */
    SHT_ResetStartStopEvaluationScope();
    return status;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunTransientComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int i = 0;
	int status;
	int varDime = Turboshaft.varVecDime - 2;
	SHT_ClearStepOut(stepOut);
	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ReadRuntimeInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.LPS_Nmech = stepIn[0];
	Turboshaft.HPS_Nmech = stepIn[1];
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	status = SHT_ReadShaftLoad(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.HPC.alphaIn = stepIn[8];
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		Turboshaft.HPC2.alphaIn = 0.0;
	Turboshaft.HPT.extSecAirSys = 0;
	Turboshaft.LPT.extSecAirSys = 0;
	Turboshaft.HPT2.extSecAirSys = 0;
	Turboshaft.LPT2.extSecAirSys = 0;

	for (i = 0; i < varDime; i++)
	{
		Turboshaft.varIte[i] = stepIn[i + 20];
	}
	status = SHT_LoadHealthParameters(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
	{
		status = SHT_EvaluateCurrentClearance();
		if (status != SHT_STATUS_OK)
		{
			SHT_ClearStepOut(stepOut);
			engptr->eng = &Turboshaft;
			return status;
		}
		status = SHT_RunSplitComponents(
			Turboshaft.varIte, Turboshaft.errOut, varDime, 0);
		if (status != SHT_STATUS_OK)
		{
			SHT_ClearStepOut(stepOut);
			engptr->eng = &Turboshaft;
			return status;
		}
		for (i = 0; i < varDime; ++i)
			stepOut[i] = Turboshaft.errOut[i];
		stepOut[varDime] = Turboshaft.LPS.nDot;
		stepOut[varDime + 1] = Turboshaft.HPS.nDot;
		if (Turboshaft.transientControl.heatStateEnable)
		{
			status = SHT_EvaluateCurrentHeatState();
			if (status != SHT_STATUS_OK)
			{
				SHT_ClearStepOut(stepOut);
				engptr->eng = &Turboshaft;
				return status;
			}
			/* 0:8 are residuals/nDot; 9:15 remain reserved for ABI stability. */
			SHT_WriteHeatStateDerivatives(stepOut, 16, 35, 41);
		}
		{
			int validIndex = 41 +
				Turboshaft.transientControl.guideVaneNodeCount;
			SHT_SetEvaluationValidity(stepOut, validIndex,
			SHT_IsFiniteVector(stepOut,
				Turboshaft.transientControl.heatStateEnable ?
				validIndex : varDime + 2));
		}
		engptr->eng = &Turboshaft;
		return SHT_STATUS_OK;
	}
	SHT_UpdateShaftLoadPower();
	status = SHT_ResetEffectiveHealthFromDesignValue();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_EvaluateCurrentClearance();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}

	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];

	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(0,
		Turboshaft.inletMassFlow,
		Turboshaft.Inlet.gasPathIn[2],
		Turboshaft.Inlet.gasPathIn[3],
		&Turboshaft.Inlet.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunInletWithBoundary();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyOriginalRotatingSchedules();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunTransientCompressor(&Turboshaft.HPC);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_ApplyPressureLossSchedule(6,
		Turboshaft.Burner.gasPathIn[0],
		Turboshaft.Burner.gasPathIn[2],
		Turboshaft.Burner.gasPathIn[3],
		&Turboshaft.Burner.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunTransientBurner(&Turboshaft.Burner, 1);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunTransientTurbine(&Turboshaft.HPT, 2,
		SHT_COMPONENT_GT, 1,
		Turboshaft.transientParameters.heatTimeCorrection[2]);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(10,
		Turboshaft.Duct2.gasPathIn[0],
		Turboshaft.Duct2.gasPathIn[2],
		Turboshaft.Duct2.gasPathIn[3],
		&Turboshaft.Duct2.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunTransientTurbine(&Turboshaft.LPT, 3,
		SHT_COMPONENT_PT, 2,
		Turboshaft.transientParameters.heatTimeCorrection[3]);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(14,
		Turboshaft.Duct3.gasPathIn[0],
		Turboshaft.Duct3.gasPathIn[2],
		Turboshaft.Duct3.gasPathIn[3],
		&Turboshaft.Duct3.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.LPS,
		Turboshaft.transientParameters.inertiaCorrection[1]);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.HPS,
		Turboshaft.transientParameters.inertiaCorrection[0]);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];      //HPC_NErr
	Turboshaft.errOut[1] = Turboshaft.HPT.y[6];      //HPT_NErr
	Turboshaft.errOut[2] = Turboshaft.LPT.y[6];      //LPT_NErr
	Turboshaft.errOut[3] = Turboshaft.Nozzle.y[2];   //Nozzle_Nerr


	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = Turboshaft.errOut[i];
	}
	stepOut[varDime] = Turboshaft.LPS.nDot;
	stepOut[varDime+1] = Turboshaft.HPS.nDot;
	if (Turboshaft.transientControl.heatStateEnable)
	{
		status = SHT_EvaluateCurrentHeatState();
		if (status != SHT_STATUS_OK)
		{
			SHT_ClearStepOut(stepOut);
			engptr->eng = &Turboshaft;
			return status;
		}
		SHT_WriteHeatStateDerivatives(stepOut, 16, 26, 29);
	}
	SHT_SetEvaluationValidity(stepOut, 29,
		SHT_IsFiniteVector(stepOut,
			Turboshaft.transientControl.heatStateEnable ? 30 : varDime + 2));
	engptr->eng = &Turboshaft;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunSteadyComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int i = 0;
	int status;
	int varDime = Turboshaft.varVecDime;
	SHT_ClearStepOut(stepOut);
	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}

	status = SHT_ReadRuntimeInletBoundaryInput(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	status = SHT_ReadShaftLoad(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.HPC.alphaIn = stepIn[8];
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
		Turboshaft.HPC2.alphaIn = 0.0;
	Turboshaft.HPT.extSecAirSys = 0;
	Turboshaft.LPT.extSecAirSys = 0;
	Turboshaft.HPT2.extSecAirSys = 0;
	Turboshaft.LPT2.extSecAirSys = 0;

	for (i = 0; i < varDime; i++)
	{
		Turboshaft.varIte[i] = stepIn[i + 20];
	}
	status = SHT_LoadHealthParameters(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	if (Turboshaft.modelMode == SHT_MODEL_MODE_SPLIT)
	{
		status = SHT_RunSplitComponents(
			Turboshaft.varIte, Turboshaft.errOut, varDime, 1);
		if (status != SHT_STATUS_OK)
		{
			SHT_ClearStepOut(stepOut);
			engptr->eng = &Turboshaft;
			return status;
		}
		for (i = 0; i < varDime; ++i)
			stepOut[i] = Turboshaft.errOut[i];
		engptr->eng = &Turboshaft;
		return SHT_STATUS_OK;
	}

	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];
	Turboshaft.LPS_Nmech = Turboshaft.varIte[4];
	Turboshaft.HPS_Nmech = Turboshaft.varIte[5];

	SHT_UpdateShaftLoadPower();
	status = SHT_ResetEffectiveHealthFromDesignValue();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ambientRun(&Turboshaft.Ambient);
	status = SHT_ApplyInletBoundaryInput();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(0,
		Turboshaft.inletMassFlow,
		Turboshaft.Inlet.gasPathIn[2],
		Turboshaft.Inlet.gasPathIn[3],
		&Turboshaft.Inlet.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunInletWithBoundary();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyOriginalRotatingSchedules();
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunCompressorMapWithClearance(&Turboshaft.HPC, 0);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_ApplyPressureLossSchedule(6,
		Turboshaft.Burner.gasPathIn[0],
		Turboshaft.Burner.gasPathIn[2],
		Turboshaft.Burner.gasPathIn[3],
		&Turboshaft.Burner.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	burnRun(&Turboshaft.Burner);
	status = SHT_RunClearanceAdjustedTurbineCore(&Turboshaft.HPT, 1);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(10,
		Turboshaft.Duct2.gasPathIn[0],
		Turboshaft.Duct2.gasPathIn[2],
		Turboshaft.Duct2.gasPathIn[3],
		&Turboshaft.Duct2.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunClearanceAdjustedTurbineCore(&Turboshaft.LPT, 2);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_ApplyPressureLossSchedule(14,
		Turboshaft.Duct3.gasPathIn[0],
		Turboshaft.Duct3.gasPathIn[2],
		Turboshaft.Duct3.gasPathIn[3],
		&Turboshaft.Duct3.pressureLossModel);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	shaftRun(&Turboshaft.LPS);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	shaftRun(&Turboshaft.HPS);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];      //HPC_NErr
	Turboshaft.errOut[1] = Turboshaft.HPT.y[6];      //HPT_NErr
	Turboshaft.errOut[2] = Turboshaft.LPT.y[6];      //LPT_NErr
	Turboshaft.errOut[3] = Turboshaft.Nozzle.y[2];   //Nozzle_Nerr
	Turboshaft.errOut[4] = Turboshaft.LPS.nDot / 10000.0;   //LPS_Nerr
	Turboshaft.errOut[5] = Turboshaft.HPS.nDot / 10000.0;   //HPS_Nerr


	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = Turboshaft.errOut[i];
	}
	engptr->eng = &Turboshaft;

	return 0;
}

//------------------------------------------------------------------------------
int engineTurboshaftCalculate(EngineTurboshaft *eng,int runMode)
{

  DLL_SHT_Initial();
  Turboshaft.altitude = 0;
  Turboshaft.machNumber = 0;
  Turboshaft.dTemperature = 0;

  double stepIn[SHT_STEP_IN_LENGTH];
  double stepOut[SHT_STEP_OUT_LENGTH];
  for (int i = 0; i < SHT_STEP_IN_LENGTH; i++)
	  stepIn[i] = 0;
  for (int i = 0; i < SHT_STEP_OUT_LENGTH; i++)
	  stepOut[i] = 0;

  /*
  double varIte0[6] = { 3.465,   0.5,     3.79854596341185,   3.0487722428283,    20000.0,  38000.0 };
  for (int i = 0; i < 6; i++)
	  stepIn[20 + i] = varIte0[i];*/
 // stepIn[40 + 19] = 0.05;

  double input[10] = { 20800,    38000 ,   0.15171  , 0.10573 ,    0 , 2176600 , 0 ,  0 , 0 , 0 };
  double var[6] = { 6.693,   0.6,   3.820 ,  3.568,   20800 ,  38000 };
  for (int i = 0; i < 10; i++)
	  stepIn[i] = input[i];
  for (int i = 0; i < 6; i++)
	  stepIn[20+i] = var[i];

  EngineSHTPointer *engptr = (EngineSHTPointer*)malloc(sizeof(EngineSHTPointer));
  DLL_SHT_RunOnePoint(stepIn, stepOut, engptr);
//  DLL_SHT_RunSteadyComponents(stepIn, stepOut, engptr);

  printf("Iterration variables: ");
  for (int i = 0; i <= 5; i++)
  {
	  printf("%f ", engptr->eng->varIte[i]);
  }
  printf("\n");
  printf("Errors: ");
  for (int i = 0; i <= 5; i++)
  {
	  printf("%f ", engptr->eng->errOut[i]);
  }
  printf("\n");
  printf("Nozzle in Pt7: %f\n", engptr->eng->Nozzle.u[3]);



  /*
  EngineSHTPointer *engptr = (EngineSHTPointer*)malloc(sizeof(EngineSHTPointer));
  //DLL_SHT_RunSteadyComponents(stepIn, stepOut, engptr);
  Init(stepIn, stepOut, 0.01);
  Onestep(stepIn, stepOut, 0.01);
  printf("Iterration variables: ");
  for (int i = 0; i < 6; i++)
  {
	  printf("%f ", Turboshaft.varIte[i]);
  }
  printf("\n");
  printf("Errors: ");
  for (int i = 0; i < 6; i++)
  {
	  printf("%f ", Turboshaft.errOut[i]);
  }
  printf("\n");

  DLL_SHT_Free();
  */

  return 0;
}
//------------------------------------------------------------------------------


