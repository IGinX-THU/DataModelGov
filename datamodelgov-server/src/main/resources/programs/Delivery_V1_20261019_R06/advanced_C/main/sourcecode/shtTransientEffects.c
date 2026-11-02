#include <float.h>
#include <math.h>
#include <string.h>
#include "shtTransientEffects.h"

#define SHT_MODEL_MODE_ORIGINAL_LOCAL 0
#define SHT_MODEL_MODE_SPLIT_LOCAL 1

/* 2502: C stepIn indices for the legacy three-component transient channels. */
#define SHT_2502_K_JG 98
#define SHT_2502_K_JP 99
#define SHT_2502_K_TAU_HPC 100
#define SHT_2502_K_TAU_BURNER 101
#define SHT_2502_K_TAU_GT 102
#define SHT_2502_K_TAU_PT 103
#define SHT_2502_K_CLEARANCE_W_HPC 104
#define SHT_2502_K_CLEARANCE_ETA_HPC 105
#define SHT_2502_K_CLEARANCE_ETA_GT 106
#define SHT_2502_K_CLEARANCE_ETA_PT 107
#define SHT_2502_K_TAU_DISK_HPC 108
#define SHT_2502_K_TAU_DISK_GT 109
#define SHT_2502_K_TAU_DISK_PT 110

/* 2503: h89:h111 occupy C stepIn[129:151]. */
#define SHT_2503_K_JG 129
#define SHT_2503_K_JP 130
#define SHT_2503_K_TAU_START 131
#define SHT_2503_K_TAU_DISK_START 138
#define SHT_2503_K_CLEARANCE_RATE_START 144

/* Kurzke-1 标称参数向量布局，与 MATLAB 组装函数保持唯一对应。 */
#define SHT_KURZKE_CONFIG_TAU_START 0
#define SHT_KURZKE_CONFIG_CAPACITY_START 19
#define SHT_KURZKE_CONFIG_BETA_START 38
#define SHT_KURZKE_CONFIG_DISK_TAU_START 57
#define SHT_KURZKE_CONFIG_REFERENCE_FLOW_START 63
#define SHT_KURZKE_CONFIG_REFERENCE_TEMPERATURE_START 70
#define SHT_KURZKE_CONFIG_CLEARANCE_START 77
#define SHT_KURZKE_CONFIG_KSM_START 137
#define SHT_KURZKE_CONFIG_CLEARANCE_RATE_START 139

/* Visser-1标称参数向量布局。 */
#define SHT_VISSER_CONFIG_CAPACITY_START 0
#define SHT_VISSER_CONFIG_HOT_UA_START 21
#define SHT_VISSER_CONFIG_BETA_START 42
#define SHT_VISSER_CONFIG_DISK_CAPACITY_START 63
#define SHT_VISSER_CONFIG_ROOT_DISK_UA_START 69
#define SHT_VISSER_CONFIG_COOLING_UA_START 75
#define SHT_VISSER_CONFIG_REFERENCE_FLOW_START 94
#define SHT_VISSER_CONFIG_REFERENCE_TEMPERATURE_START 101
#define SHT_VISSER_CONFIG_CLEARANCE_START 108
#define SHT_VISSER_CONFIG_KSM_START 168
#define SHT_VISSER_CONFIG_CLEARANCE_RATE_START 170

typedef struct SHTThermalConfigurationRuntime {
	int initialized;
	int modelMode;
	int thermalModelMode;
	int configVersion;
	int parameterCount;
	SHTTransientParameters nominal;
} SHTThermalConfigurationRuntime;

/* DLL 为单实例运行方式，标称热参数与发动机实例同寿命周期。 */
static SHTThermalConfigurationRuntime SHT_ThermalConfiguration;

typedef struct SHTTransientTopology {
	int metalNodeCount;
	int diskNodeCount;
	int heatComponentCount;
	int clearanceComponentCount;
	int heatNodeStart[SHT_HEAT_COMPONENT_COUNT];
	int heatNodeCount[SHT_HEAT_COMPONENT_COUNT];
	int heatComponentBit[SHT_HEAT_COMPONENT_COUNT];
	int heatUsesAir[SHT_HEAT_COMPONENT_COUNT];
	int diskHeatComponent[SHT_DISK_NODE_COUNT];
	int diskRootNode[SHT_DISK_NODE_COUNT];
	int clearanceMetalStart[SHT_CLEARANCE_COMPONENT_COUNT];
	int clearanceComponentBit[SHT_CLEARANCE_COMPONENT_COUNT];
	int clearanceFlowRateIndex[SHT_CLEARANCE_COMPONENT_COUNT];
	int clearanceEfficiencyRateIndex[SHT_CLEARANCE_COMPONENT_COUNT];
	int clearanceCompressorIndex[SHT_CLEARANCE_COMPONENT_COUNT];
} SHTTransientTopology;

static const SHTTransientTopology SHT_LegacyTopology = {
	SHT_LEGACY_METAL_NODE_COUNT,
	SHT_LEGACY_DISK_NODE_COUNT,
	SHT_LEGACY_HEAT_COMPONENT_COUNT,
	SHT_LEGACY_CLEARANCE_COMPONENT_COUNT,
	{ 0, 3, 4, 7, 0, 0, 0 },
	{ 3, 1, 3, 3, 0, 0, 0 },
	{ SHT_COMPONENT_HPC, SHT_COMPONENT_BURNER, SHT_COMPONENT_GT,
	  SHT_COMPONENT_PT, 0, 0, 0 },
	{ 1, 0, 0, 0, 0, 0, 0 },
	{ 0, 2, 3, 0, 0, 0 },
	{ 1, 5, 8, 0, 0, 0 },
	{ 0, 4, 7, 0, 0, 0 },
	{ SHT_COMPONENT_HPC, SHT_COMPONENT_GT, SHT_COMPONENT_PT, 0, 0, 0 },
	{ 0, -1, -1, -1, -1, -1 },
	{ 1, 2, 3, -1, -1, -1 },
	{ 0, -1, -1, -1, -1, -1 }
};

/*
 * 2503 metal order:
 * AC(0:2), CC(3:5), Burner(6), GT1(7:9), GT2(10:12),
 * PT1(13:15), PT2(16:18).
 */
static const SHTTransientTopology SHT_SplitTopology = {
	SHT_SPLIT_METAL_NODE_COUNT,
	SHT_SPLIT_DISK_NODE_COUNT,
	SHT_SPLIT_HEAT_COMPONENT_COUNT,
	SHT_SPLIT_CLEARANCE_COMPONENT_COUNT,
	{ 0, 3, 6, 7, 10, 13, 16 },
	{ 3, 3, 1, 3, 3, 3, 3 },
	{ SHT_COMPONENT_HPC, SHT_COMPONENT_HPC, SHT_COMPONENT_BURNER,
	  SHT_COMPONENT_GT, SHT_COMPONENT_GT, SHT_COMPONENT_PT,
	  SHT_COMPONENT_PT },
	{ 1, 1, 0, 0, 0, 0, 0 },
	{ 0, 1, 3, 4, 5, 6 },
	{ 1, 4, 8, 11, 14, 17 },
	{ 0, 3, 7, 10, 13, 16 },
	{ SHT_COMPONENT_HPC, SHT_COMPONENT_HPC, SHT_COMPONENT_GT,
	  SHT_COMPONENT_GT, SHT_COMPONENT_PT, SHT_COMPONENT_PT },
	{ 0, 2, -1, -1, -1, -1 },
	{ 1, 3, 4, 5, 6, 7 },
	{ 0, 1, -1, -1, -1, -1 }
};

/*
 * Visser-1在既有19个金属节点之外增加GT1/GT2导向器节点。导向器
 * 使用独立状态数组，但其逻辑节点编号仍连续为19、20，便于标称参数
 * 向量和守恒计算保持单一顺序。
 */
static const int SHT_VisserGuideComponent[2] = { 3, 4 };
static const int SHT_VisserRootNode[SHT_SPLIT_DISK_NODE_COUNT] = {
	1, 4, 8, 11, 14, 17
};

static const SHTTransientTopology *SHT_GetTopology(
	const SHTTransientControl *control)
{
	return control->modelMode == SHT_MODEL_MODE_SPLIT_LOCAL ?
		&SHT_SplitTopology : &SHT_LegacyTopology;
}

static int SHT_IsFinite(double value)
{
	return _finite(value) != 0;
}

static int SHT_ZeroFlowHeatEvaluationEnabled = 0;

void SHT_SetZeroFlowHeatEvaluationEnabled(int enabled)
{
	SHT_ZeroFlowHeatEvaluationEnabled = enabled != 0;
}

void SHT_ResetThermalConfiguration(void)
{
	SHT_ZeroFlowHeatEvaluationEnabled = 0;
	memset(&SHT_ThermalConfiguration, 0,
		sizeof(SHT_ThermalConfiguration));
}

static int SHT_ValidateKurzkeConfiguration(
	const SHTTransientParameters *candidate, int modelMode)
{
	int i;
	if (candidate == 0)
		return SHT_ERROR_NULL_POINTER;

	for (i = 0; i < (modelMode == 0 ? 10 : 19); ++i)
	{
		if (!SHT_IsFinite(candidate->tau0[i]) || candidate->tau0[i] <= 0.0 ||
			!SHT_IsFinite(candidate->heatCapacity0[i]) ||
			candidate->heatCapacity0[i] <= 0.0 ||
			!SHT_IsFinite(candidate->beta[i]) ||
			candidate->beta[i] < 0.0 || candidate->beta[i] > 1.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 3 : 6); ++i)
	{
		if (!SHT_IsFinite(candidate->diskTau0[i]) ||
			candidate->diskTau0[i] <= 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 4 : 7); ++i)
	{
		if (!SHT_IsFinite(candidate->referenceFlow[i]) ||
			candidate->referenceFlow[i] <= 0.0 ||
			!SHT_IsFinite(candidate->referenceGasTemperature[i]) ||
			candidate->referenceGasTemperature[i] <= 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 3 : 6); ++i)
	{
		const double *p = &candidate->clearanceParameter[10 * i];
		int j;
		if (!SHT_IsFinite(p[0]) || p[0] <= 0.0 ||
			!SHT_IsFinite(p[5]) || p[5] < 0.0 || p[5] > 1.0)
			return SHT_ERROR_PARAMETER_VALUE;
		for (j = 1; j <= 4; ++j)
			if (!SHT_IsFinite(p[j]))
				return SHT_ERROR_PARAMETER_VALUE;
		for (j = 6; j <= 9; ++j)
			if (!SHT_IsFinite(p[j]) || p[j] <= 0.0)
				return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 1 : 2); ++i)
		if (!SHT_IsFinite(candidate->kSM[i]))
			return SHT_ERROR_PARAMETER_VALUE;
	for (i = 0; i < (modelMode == 0 ? 4 : 8); ++i)
		if (!SHT_IsFinite(candidate->nominalClearanceExchangeRate[i]) ||
			candidate->nominalClearanceExchangeRate[i] > 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	return SHT_STATUS_OK;
}

static int SHT_ValidateCommonClearanceConfiguration(
	const SHTTransientParameters *candidate, int modelMode)
{
	int i;
	if (candidate == 0)
		return SHT_ERROR_NULL_POINTER;
	for (i = 0; i < (modelMode == 0 ? 3 : 6); ++i)
	{
		const double *p = &candidate->clearanceParameter[10 * i];
		int j;
		if (!SHT_IsFinite(p[0]) || p[0] <= 0.0 ||
			!SHT_IsFinite(p[5]) || p[5] < 0.0 || p[5] > 1.0)
			return SHT_ERROR_PARAMETER_VALUE;
		for (j = 1; j <= 4; ++j)
			if (!SHT_IsFinite(p[j]))
				return SHT_ERROR_PARAMETER_VALUE;
		for (j = 6; j <= 9; ++j)
			if (!SHT_IsFinite(p[j]) || p[j] <= 0.0)
				return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 1 : 2); ++i)
		if (!SHT_IsFinite(candidate->kSM[i]))
			return SHT_ERROR_PARAMETER_VALUE;
	for (i = 0; i < (modelMode == 0 ? 4 : 8); ++i)
		if (!SHT_IsFinite(candidate->nominalClearanceExchangeRate[i]) ||
			candidate->nominalClearanceExchangeRate[i] > 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	return SHT_STATUS_OK;
}

static int SHT_ValidateVisserConfiguration(
	const SHTTransientParameters *candidate, int modelMode)
{
	int i;
	int status;
	if (candidate == 0)
		return SHT_ERROR_NULL_POINTER;
	for (i = 0; i < (modelMode == 0 ? 11 : 21); ++i)
	{
		if (!SHT_IsFinite(candidate->visserMetalHeatCapacity[i]) ||
			candidate->visserMetalHeatCapacity[i] <= 0.0 ||
			!SHT_IsFinite(candidate->visserHotGasConductance0[i]) ||
			candidate->visserHotGasConductance0[i] < 0.0 ||
			!SHT_IsFinite(candidate->visserHotGasBeta[i]) ||
			candidate->visserHotGasBeta[i] < 0.0 ||
			candidate->visserHotGasBeta[i] > 1.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < (modelMode == 0 ? 3 : 6); ++i)
	{
		if (!SHT_IsFinite(candidate->visserDiskHeatCapacity[i]) ||
			candidate->visserDiskHeatCapacity[i] <= 0.0 ||
			!SHT_IsFinite(candidate->visserRootDiskConductance0[i]) ||
			candidate->visserRootDiskConductance0[i] <= 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	for (i = 0; i < SHT_VISSER_COOLING_BRANCH_COUNT; ++i)
		if (!SHT_IsFinite(candidate->visserCoolingConductance0[i]) ||
			candidate->visserCoolingConductance0[i] < 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	for (i = 0; i < (modelMode == 0 ? 4 : 7); ++i)
	{
		if (!SHT_IsFinite(candidate->referenceFlow[i]) ||
			candidate->referenceFlow[i] <= 0.0 ||
			!SHT_IsFinite(candidate->referenceGasTemperature[i]) ||
			candidate->referenceGasTemperature[i] <= 0.0)
			return SHT_ERROR_PARAMETER_VALUE;
	}
	status = SHT_ValidateCommonClearanceConfiguration(candidate, modelMode);
	return status;
}

int SHT_InitializeThermalConfiguration(
	int modelMode,
	int thermalModelMode,
	int configVersion,
	int parameterCount,
	const double *parameterVector)
{
	SHTThermalConfigurationRuntime candidate;
	int i;
	int status;

	if (parameterVector == 0)
		return SHT_ERROR_NULL_POINTER;
	if (modelMode != SHT_MODEL_MODE_SPLIT_LOCAL && modelMode != 0)
		return SHT_ERROR_THERMAL_CONFIG_MODEL_MISMATCH;
	if (thermalModelMode != SHT_THERMAL_MODEL_KURZKE &&
		thermalModelMode != SHT_THERMAL_MODEL_VISSER)
		return SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED;
	if ((thermalModelMode == SHT_THERMAL_MODEL_KURZKE &&
		 configVersion != (modelMode == 0 ? SHT_THERMAL_CONFIG_VERSION_LEGACY_KURZKE_1 : SHT_THERMAL_CONFIG_VERSION_KURZKE_1)) ||
		(thermalModelMode == SHT_THERMAL_MODEL_VISSER &&
		 configVersion != (modelMode == 0 ? SHT_THERMAL_CONFIG_VERSION_LEGACY_VISSER_1 : SHT_THERMAL_CONFIG_VERSION_VISSER_1)))
		return SHT_ERROR_THERMAL_CONFIG_VERSION;
	if ((thermalModelMode == SHT_THERMAL_MODEL_KURZKE &&
		 parameterCount != SHT_THERMAL_CONFIG_KURZKE_PARAMETER_COUNT) ||
		(thermalModelMode == SHT_THERMAL_MODEL_VISSER &&
		 parameterCount != SHT_THERMAL_CONFIG_VISSER_PARAMETER_COUNT))
		return SHT_ERROR_THERMAL_CONFIG_SIZE;

	memset(&candidate, 0, sizeof(candidate));
	candidate.modelMode = modelMode;
	candidate.thermalModelMode = thermalModelMode;
	candidate.configVersion = configVersion;
	candidate.parameterCount = parameterCount;
	if (thermalModelMode == SHT_THERMAL_MODEL_KURZKE)
	{
		for (i = 0; i < SHT_SPLIT_METAL_NODE_COUNT; ++i)
		{
			candidate.nominal.tau0[i] =
				parameterVector[SHT_KURZKE_CONFIG_TAU_START + i];
			candidate.nominal.heatCapacity0[i] =
				parameterVector[SHT_KURZKE_CONFIG_CAPACITY_START + i];
			candidate.nominal.beta[i] =
				parameterVector[SHT_KURZKE_CONFIG_BETA_START + i];
		}
		for (i = 0; i < SHT_SPLIT_DISK_NODE_COUNT; ++i)
			candidate.nominal.diskTau0[i] =
				parameterVector[SHT_KURZKE_CONFIG_DISK_TAU_START + i];
		for (i = 0; i < SHT_SPLIT_HEAT_COMPONENT_COUNT; ++i)
		{
			candidate.nominal.referenceFlow[i] =
				parameterVector[SHT_KURZKE_CONFIG_REFERENCE_FLOW_START + i];
			candidate.nominal.referenceGasTemperature[i] =
				parameterVector[SHT_KURZKE_CONFIG_REFERENCE_TEMPERATURE_START + i];
		}
		for (i = 0; i < 10 * SHT_SPLIT_CLEARANCE_COMPONENT_COUNT; ++i)
			candidate.nominal.clearanceParameter[i] =
				parameterVector[SHT_KURZKE_CONFIG_CLEARANCE_START + i];
		for (i = 0; i < SHT_COMPRESSOR_CLEARANCE_COUNT; ++i)
			candidate.nominal.kSM[i] =
				parameterVector[SHT_KURZKE_CONFIG_KSM_START + i];
		for (i = 0; i < SHT_CLEARANCE_RATE_COUNT; ++i)
			candidate.nominal.nominalClearanceExchangeRate[i] =
				parameterVector[SHT_KURZKE_CONFIG_CLEARANCE_RATE_START + i];
		status = SHT_ValidateKurzkeConfiguration(&candidate.nominal, modelMode);
	}
	else
	{
		for (i = 0; i < SHT_VISSER_METAL_NODE_COUNT; ++i)
		{
			candidate.nominal.visserMetalHeatCapacity[i] =
				parameterVector[SHT_VISSER_CONFIG_CAPACITY_START + i];
			candidate.nominal.visserHotGasConductance0[i] =
				parameterVector[SHT_VISSER_CONFIG_HOT_UA_START + i];
			candidate.nominal.visserHotGasBeta[i] =
				parameterVector[SHT_VISSER_CONFIG_BETA_START + i];
		}
		for (i = 0; i < SHT_SPLIT_DISK_NODE_COUNT; ++i)
		{
			candidate.nominal.visserDiskHeatCapacity[i] =
				parameterVector[SHT_VISSER_CONFIG_DISK_CAPACITY_START + i];
			candidate.nominal.visserRootDiskConductance0[i] =
				parameterVector[SHT_VISSER_CONFIG_ROOT_DISK_UA_START + i];
		}
		for (i = 0; i < SHT_VISSER_COOLING_BRANCH_COUNT; ++i)
			candidate.nominal.visserCoolingConductance0[i] =
				parameterVector[SHT_VISSER_CONFIG_COOLING_UA_START + i];
		for (i = 0; i < SHT_SPLIT_HEAT_COMPONENT_COUNT; ++i)
		{
			candidate.nominal.referenceFlow[i] =
				parameterVector[SHT_VISSER_CONFIG_REFERENCE_FLOW_START + i];
			candidate.nominal.referenceGasTemperature[i] =
				parameterVector[SHT_VISSER_CONFIG_REFERENCE_TEMPERATURE_START + i];
		}
		for (i = 0; i < 10 * SHT_SPLIT_CLEARANCE_COMPONENT_COUNT; ++i)
			candidate.nominal.clearanceParameter[i] =
				parameterVector[SHT_VISSER_CONFIG_CLEARANCE_START + i];
		for (i = 0; i < SHT_COMPRESSOR_CLEARANCE_COUNT; ++i)
			candidate.nominal.kSM[i] =
				parameterVector[SHT_VISSER_CONFIG_KSM_START + i];
		for (i = 0; i < SHT_CLEARANCE_RATE_COUNT; ++i)
			candidate.nominal.nominalClearanceExchangeRate[i] =
				parameterVector[SHT_VISSER_CONFIG_CLEARANCE_RATE_START + i];
		status = SHT_ValidateVisserConfiguration(&candidate.nominal, modelMode);
	}
	if (status != SHT_STATUS_OK)
		return status;
	candidate.initialized = 1;
	SHT_ThermalConfiguration = candidate;
	return SHT_STATUS_OK;
}

int SHT_GetThermalConfigurationStatus(
	int modelMode,
	int thermalModelMode)
{
	if (!SHT_ThermalConfiguration.initialized)
		return SHT_ERROR_THERMAL_CONFIG_NOT_INITIALIZED;
	if (SHT_ThermalConfiguration.modelMode != modelMode ||
		SHT_ThermalConfiguration.thermalModelMode != thermalModelMode)
		return SHT_ERROR_THERMAL_CONFIG_MODEL_MISMATCH;
	return SHT_STATUS_OK;
}

static int SHT_CopyThermalConfiguration(
	int modelMode,
	int thermalModelMode,
	SHTTransientParameters *destination)
{
	int i;
	int status = SHT_GetThermalConfigurationStatus(
		modelMode, thermalModelMode);
	if (status != SHT_STATUS_OK)
		return status;
	if (destination == 0)
		return SHT_ERROR_NULL_POINTER;

	for (i = 0; i < SHT_SPLIT_METAL_NODE_COUNT; ++i)
	{
		destination->tau0[i] =
			SHT_ThermalConfiguration.nominal.tau0[i];
		destination->heatCapacity0[i] =
			SHT_ThermalConfiguration.nominal.heatCapacity0[i];
		destination->beta[i] =
			SHT_ThermalConfiguration.nominal.beta[i];
	}
	for (i = 0; i < SHT_SPLIT_DISK_NODE_COUNT; ++i)
		destination->diskTau0[i] =
			SHT_ThermalConfiguration.nominal.diskTau0[i];
	for (i = 0; i < SHT_SPLIT_HEAT_COMPONENT_COUNT; ++i)
	{
		destination->referenceFlow[i] =
			SHT_ThermalConfiguration.nominal.referenceFlow[i];
		destination->referenceGasTemperature[i] =
			SHT_ThermalConfiguration.nominal.referenceGasTemperature[i];
	}
	for (i = 0; i < 10 * SHT_SPLIT_CLEARANCE_COMPONENT_COUNT; ++i)
		destination->clearanceParameter[i] =
			SHT_ThermalConfiguration.nominal.clearanceParameter[i];
	for (i = 0; i < SHT_COMPRESSOR_CLEARANCE_COUNT; ++i)
		destination->kSM[i] =
			SHT_ThermalConfiguration.nominal.kSM[i];
	for (i = 0; i < SHT_CLEARANCE_RATE_COUNT; ++i)
		destination->nominalClearanceExchangeRate[i] =
			SHT_ThermalConfiguration.nominal
				.nominalClearanceExchangeRate[i];
	for (i = 0; i < SHT_VISSER_METAL_NODE_COUNT; ++i)
	{
		destination->visserMetalHeatCapacity[i] =
			SHT_ThermalConfiguration.nominal.visserMetalHeatCapacity[i];
		destination->visserHotGasConductance0[i] =
			SHT_ThermalConfiguration.nominal.visserHotGasConductance0[i];
		destination->visserHotGasBeta[i] =
			SHT_ThermalConfiguration.nominal.visserHotGasBeta[i];
	}
	for (i = 0; i < SHT_SPLIT_DISK_NODE_COUNT; ++i)
	{
		destination->visserDiskHeatCapacity[i] =
			SHT_ThermalConfiguration.nominal.visserDiskHeatCapacity[i];
		destination->visserRootDiskConductance0[i] =
			SHT_ThermalConfiguration.nominal.visserRootDiskConductance0[i];
	}
	for (i = 0; i < SHT_VISSER_COOLING_BRANCH_COUNT; ++i)
		destination->visserCoolingConductance0[i] =
			SHT_ThermalConfiguration.nominal.visserCoolingConductance0[i];
	return SHT_STATUS_OK;
}

static int SHT_SetError(
	SHTTransientDiagnostics *diagnostics,
	int errorCode,
	int stepInIndex,
	double value)
{
	diagnostics->errorCode = errorCode;
	diagnostics->configurationValid = 0;
	diagnostics->evaluationValid = 0;
	diagnostics->offendingStepInIndex = stepInIndex;
	diagnostics->offendingValue = value;
	return errorCode;
}

static int SHT_SetEvaluationError(
	SHTTransientDiagnostics *diagnostics,
	int errorCode,
	int stepInIndex,
	double value)
{
	diagnostics->errorCode = errorCode;
	diagnostics->evaluationValid = 0;
	diagnostics->offendingStepInIndex = stepInIndex;
	diagnostics->offendingValue = value;
	return errorCode;
}

static int SHT_DecodeDiscrete(
	double value,
	const int *targets,
	int targetCount,
	int stepInIndex,
	int *decoded,
	SHTTransientDiagnostics *diagnostics)
{
	int i;
	int nearest = 0;
	double nearestDistance;

	if (!SHT_IsFinite(value))
		return SHT_SetError(diagnostics, SHT_ERROR_CONTROL_VALUE,
			stepInIndex, value);

	nearestDistance = fabs(value - (double)targets[0]);
	for (i = 1; i < targetCount; ++i)
	{
		double distance = fabs(value - (double)targets[i]);
		if (distance < nearestDistance)
		{
			nearest = i;
			nearestDistance = distance;
		}
	}
	if (nearestDistance > SHT_TRANSIENT_CONTROL_TOL)
		return SHT_SetError(diagnostics, SHT_ERROR_CONTROL_VALUE,
			stepInIndex, value);
	*decoded = targets[nearest];
	return SHT_STATUS_OK;
}

static int SHT_CheckReservedRange(
	const double *stepIn,
	int firstIndex,
	int lastIndex,
	SHTTransientDiagnostics *diagnostics)
{
	int i;
	for (i = firstIndex; i <= lastIndex; ++i)
	{
		if (!SHT_IsFinite(stepIn[i]) ||
			fabs(stepIn[i]) > SHT_TRANSIENT_CONTROL_TOL)
			return SHT_SetError(diagnostics, SHT_ERROR_RESERVED_INPUT,
				i, stepIn[i]);
	}
	return SHT_STATUS_OK;
}

static int SHT_CheckPositive(
	double value,
	int stepInIndex,
	SHTTransientDiagnostics *diagnostics)
{
	if (!SHT_IsFinite(value) || value <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			stepInIndex, value);
	return SHT_STATUS_OK;
}

static int SHT_CheckCorrectionFactor(
	double correction,
	int stepInIndex,
	SHTTransientDiagnostics *diagnostics)
{
	if (!SHT_IsFinite(correction) || 1.0 + correction <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			stepInIndex, correction);
	return SHT_STATUS_OK;
}

static void SHT_ConfigureTopology(
	SHTTransientControl *control,
	int modelMode)
{
	const SHTTransientTopology *topology;
	control->modelMode = modelMode;
	topology = SHT_GetTopology(control);
	control->metalNodeCount = topology->metalNodeCount;
	control->diskNodeCount = topology->diskNodeCount;
	control->guideVaneNodeCount = 0;
	control->heatComponentCount = topology->heatComponentCount;
	control->clearanceComponentCount = topology->clearanceComponentCount;
}

static int SHT_IsHeatComponentSelected(
	const SHTTransientControl *control,
	int componentIndex)
{
	const SHTTransientTopology *topology = SHT_GetTopology(control);
	return componentIndex >= 0 &&
		componentIndex < topology->heatComponentCount &&
		(control->componentMask &
		 topology->heatComponentBit[componentIndex]) != 0;
}

static int SHT_IsClearanceComponentSelected(
	const SHTTransientControl *control,
	int componentIndex)
{
	const SHTTransientTopology *topology = SHT_GetTopology(control);
	return componentIndex >= 0 &&
		componentIndex < topology->clearanceComponentCount &&
		(control->componentMask &
		 topology->clearanceComponentBit[componentIndex]) != 0;
}

static int SHT_BetaInputIndex(
	const SHTTransientControl *control,
	int nodeIndex)
{
	return control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		388 + nodeIndex : 370 + nodeIndex;
}

static int SHT_TauInputIndex(
	const SHTTransientControl *control,
	int nodeIndex)
{
	return 350 + nodeIndex;
}

static int SHT_DiskTauInputIndex(
	const SHTTransientControl *control,
	int diskIndex)
{
	return control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		407 + diskIndex : 380 + diskIndex;
}

static int SHT_ValidateHeatComponent(
	const double *stepIn,
	const SHTTransientControl *control,
	int componentIndex,
	int tauCorrectionIndex,
	int diskIndex,
	int diskCorrectionIndex,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology = SHT_GetTopology(control);
	int stateStart = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		300 : 300;
	int diskStateStart = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		319 : 310;
	int capacityStart = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		369 : 360;
	int betaStart = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		388 : 370;
	int referenceFlowStart = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		413 : 383;
	int referenceTemperatureStart =
		control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ? 420 : 387;
	int firstNode = topology->heatNodeStart[componentIndex];
	int count = topology->heatNodeCount[componentIndex];
	int i;
	int status;

	for (i = 0; i < count; ++i)
	{
		int nodeIndex = firstNode + i;
		double temperature = stepIn[stateStart + nodeIndex];
		if (!SHT_IsFinite(temperature) || temperature <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				stateStart + nodeIndex, temperature);
		status = SHT_CheckPositive(stepIn[350 + nodeIndex],
			350 + nodeIndex, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_CheckPositive(stepIn[capacityStart + nodeIndex],
			capacityStart + nodeIndex, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		if (!SHT_IsFinite(stepIn[betaStart + nodeIndex]) ||
			stepIn[betaStart + nodeIndex] < 0.0 ||
			stepIn[betaStart + nodeIndex] > 1.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				betaStart + nodeIndex, stepIn[betaStart + nodeIndex]);
	}

	status = SHT_CheckPositive(stepIn[referenceFlowStart + componentIndex],
		referenceFlowStart + componentIndex, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckPositive(
		stepIn[referenceTemperatureStart + componentIndex],
		referenceTemperatureStart + componentIndex, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckCorrectionFactor(stepIn[tauCorrectionIndex],
		tauCorrectionIndex, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	if (diskIndex >= 0)
	{
		status = SHT_CheckPositive(stepIn[diskStateStart + diskIndex],
			diskStateStart + diskIndex, diagnostics);
		if (status != SHT_STATUS_OK)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				diskStateStart + diskIndex,
				stepIn[diskStateStart + diskIndex]);
		status = SHT_CheckPositive(
			stepIn[SHT_DiskTauInputIndex(control, diskIndex)],
			SHT_DiskTauInputIndex(control, diskIndex), diagnostics);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_CheckCorrectionFactor(stepIn[diskCorrectionIndex],
			diskCorrectionIndex, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	return SHT_STATUS_OK;
}

static int SHT_ValidateClearanceComponent(
	const double *stepIn,
	int parameterStart,
	int epsilonSSIndex,
	const int *correctionIndices,
	const int *nominalRateIndices,
	int exchangeCount,
	int surgeMarginIndex,
	SHTTransientDiagnostics *diagnostics)
{
	int i;
	int status;

	status = SHT_CheckPositive(stepIn[parameterStart],
		parameterStart, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	for (i = 1; i <= 4; ++i)
	{
		if (!SHT_IsFinite(stepIn[parameterStart + i]))
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				parameterStart + i, stepIn[parameterStart + i]);
	}
	if (!SHT_IsFinite(stepIn[parameterStart + 5]) ||
		stepIn[parameterStart + 5] < 0.0 ||
		stepIn[parameterStart + 5] > 1.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			parameterStart + 5, stepIn[parameterStart + 5]);
	for (i = 6; i <= 9; ++i)
	{
		status = SHT_CheckPositive(stepIn[parameterStart + i],
			parameterStart + i, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	status = SHT_CheckPositive(stepIn[epsilonSSIndex],
		epsilonSSIndex, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	for (i = 0; i < exchangeCount; ++i)
	{
		status = SHT_CheckCorrectionFactor(stepIn[correctionIndices[i]],
			correctionIndices[i], diagnostics);
		if (status != SHT_STATUS_OK) return status;
		if (!SHT_IsFinite(stepIn[nominalRateIndices[i]]) ||
			stepIn[nominalRateIndices[i]] > 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				nominalRateIndices[i], stepIn[nominalRateIndices[i]]);
	}
	if (surgeMarginIndex >= 0 &&
		!SHT_IsFinite(stepIn[surgeMarginIndex]))
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			surgeMarginIndex, stepIn[surgeMarginIndex]);
	return SHT_STATUS_OK;
}

/*
 * 2503 新路径的固定参数来自一次初始化配置，而非 stepIn。
 * 因此状态和个体修正量仍按 stepIn 下标报错，初始化参数若异常则
 * 使用 -1 表示错误不属于本次动态输入。
 */
static int SHT_ValidateHeatComponent2503(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	int componentIndex,
	int tauCorrectionIndex,
	int diskIndex,
	int diskCorrectionIndex,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology = SHT_GetTopology(control);
	int firstNode = topology->heatNodeStart[componentIndex];
	int count = topology->heatNodeCount[componentIndex];
	int i;
	int status;

	for (i = 0; i < count; ++i)
	{
		int nodeIndex = firstNode + i;
		double temperature = state->metalTemperature[nodeIndex];
		if (!SHT_IsFinite(temperature) || temperature <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				300 + nodeIndex, temperature);
		if (!SHT_IsFinite(parameters->tau0[nodeIndex]) ||
			parameters->tau0[nodeIndex] <= 0.0 ||
			!SHT_IsFinite(parameters->heatCapacity0[nodeIndex]) ||
			parameters->heatCapacity0[nodeIndex] <= 0.0 ||
			!SHT_IsFinite(parameters->beta[nodeIndex]) ||
			parameters->beta[nodeIndex] < 0.0 ||
			parameters->beta[nodeIndex] > 1.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				-1, parameters->tau0[nodeIndex]);
	}
	if (!SHT_IsFinite(parameters->referenceFlow[componentIndex]) ||
		parameters->referenceFlow[componentIndex] <= 0.0 ||
		!SHT_IsFinite(parameters->referenceGasTemperature[componentIndex]) ||
		parameters->referenceGasTemperature[componentIndex] <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE, -1,
			parameters->referenceFlow[componentIndex]);
	status = SHT_CheckCorrectionFactor(
		parameters->heatTimeCorrection[componentIndex],
		tauCorrectionIndex, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	if (diskIndex >= 0)
	{
		double diskTemperature = state->diskTemperature[diskIndex];
		if (!SHT_IsFinite(diskTemperature) || diskTemperature <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				319 + diskIndex, diskTemperature);
		if (!SHT_IsFinite(parameters->diskTau0[diskIndex]) ||
			parameters->diskTau0[diskIndex] <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				-1, parameters->diskTau0[diskIndex]);
		status = SHT_CheckCorrectionFactor(
			parameters->diskTimeCorrection[diskIndex],
			diskCorrectionIndex, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	return SHT_STATUS_OK;
}

static int SHT_ValidateVisserRuntime(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology = SHT_GetTopology(control);
	int i;
	int status;
	for (i = 0; i < control->metalNodeCount; ++i)
		if (!SHT_IsFinite(state->metalTemperature[i]) ||
			state->metalTemperature[i] <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				300 + i, state->metalTemperature[i]);
	for (i = 0; i < control->diskNodeCount; ++i)
		if (!SHT_IsFinite(state->diskTemperature[i]) ||
			state->diskTemperature[i] <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				300 + control->metalNodeCount + i, state->diskTemperature[i]);
	for (i = 0; i < control->guideVaneNodeCount; ++i)
		if (!SHT_IsFinite(state->guideVaneTemperature[i]) ||
			state->guideVaneTemperature[i] <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				300 + control->metalNodeCount + control->diskNodeCount + i, state->guideVaneTemperature[i]);

	for (i = 0; i < topology->heatComponentCount; ++i)
	{
		if (!SHT_IsHeatComponentSelected(control, i))
			continue;
		status = SHT_CheckCorrectionFactor(
			parameters->heatTimeCorrection[i],
			(control->modelMode == 0 ? SHT_2502_K_TAU_HPC : SHT_2503_K_TAU_START) + i, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	for (i = 0; i < topology->diskNodeCount; ++i)
	{
		if (!SHT_IsHeatComponentSelected(
			control, topology->diskHeatComponent[i]))
			continue;
		status = SHT_CheckCorrectionFactor(
			parameters->diskTimeCorrection[i],
			(control->modelMode == 0 ? SHT_2502_K_TAU_DISK_HPC : SHT_2503_K_TAU_DISK_START) + i, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	return SHT_STATUS_OK;
}

static int SHT_ValidateClearanceComponent2503(
	const SHTTransientParameters *parameters,
	int componentIndex,
	int correctionStart,
	int exchangeCount,
	int surgeMarginIndex,
	SHTTransientDiagnostics *diagnostics)
{
	const double *p = &parameters->clearanceParameter[10 * componentIndex];
	int rateStart = componentIndex < 2 ?
		2 * componentIndex : componentIndex + 2;
	int i;
	int status;

	if (!SHT_IsFinite(p[0]) || p[0] <= 0.0 ||
		!SHT_IsFinite(p[5]) || p[5] < 0.0 || p[5] > 1.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE, -1, p[0]);
	for (i = 1; i <= 4; ++i)
		if (!SHT_IsFinite(p[i]))
			return SHT_SetError(diagnostics,
				SHT_ERROR_PARAMETER_VALUE, -1, p[i]);
	for (i = 6; i <= 9; ++i)
		if (!SHT_IsFinite(p[i]) || p[i] <= 0.0)
			return SHT_SetError(diagnostics,
				SHT_ERROR_PARAMETER_VALUE, -1, p[i]);
	if (!SHT_IsFinite(parameters->epsilonSS[componentIndex]) ||
		parameters->epsilonSS[componentIndex] <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			487 + componentIndex, parameters->epsilonSS[componentIndex]);

	for (i = 0; i < exchangeCount; ++i)
	{
		status = SHT_CheckCorrectionFactor(
			parameters->clearanceRateCorrection[rateStart + i],
			correctionStart + i, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		if (!SHT_IsFinite(
			parameters->nominalClearanceExchangeRate[rateStart + i]) ||
			parameters->nominalClearanceExchangeRate[rateStart + i] > 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				-1, parameters->nominalClearanceExchangeRate[rateStart + i]);
	}
	if (surgeMarginIndex >= 0)
	{
		int compressorIndex = componentIndex;
		if (compressorIndex >= SHT_COMPRESSOR_CLEARANCE_COUNT ||
			!SHT_IsFinite(parameters->kSM[compressorIndex]))
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				-1, parameters->kSM[compressorIndex]);
	}
	return SHT_STATUS_OK;
}

static double SHT_AirDynamicViscosity(double temperature)
{
	return 1.46176814e-6 * pow(temperature, 1.5) /
		(temperature + 110.4);
}

static double SHT_GasDynamicViscosity(double temperature)
{
	return 1.5105e-6 * pow(temperature, 1.5) /
		(temperature + 120.0);
}

void SHT_ResetHeatEvaluation(SHTTransientHeatEvaluation *evaluation)
{
	if (evaluation != 0)
		memset(evaluation, 0, sizeof(*evaluation));
}

void SHT_ResetClearanceEvaluation(SHTTransientClearanceEvaluation *evaluation)
{
	int i;
	if (evaluation == 0) return;
	memset(evaluation, 0, sizeof(*evaluation));
	for (i = 0; i < SHT_CLEARANCE_COMPONENT_COUNT; ++i)
	{
		evaluation->flowMultiplier[i] = 1.0;
		evaluation->efficiencyMultiplier[i] = 1.0;
	}
	for (i = 0; i < SHT_COMPRESSOR_CLEARANCE_COUNT; ++i)
		evaluation->surgeMarginMultiplier[i] = 1.0;
}

int SHT_EvaluateClearanceStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double currentSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	const double designSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	int componentIndex;

	if (control == 0 || state == 0 || parameters == 0 ||
		currentSpeed == 0 || designSpeed == 0 || evaluation == 0 ||
		diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;

	topology = SHT_GetTopology(control);
	SHT_ResetClearanceEvaluation(evaluation);
	if (!control->clearanceEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		diagnostics->offendingStepInIndex = -1;
		diagnostics->offendingValue = 0.0;
		return SHT_STATUS_OK;
	}

	for (componentIndex = 0;
		componentIndex < topology->clearanceComponentCount;
		++componentIndex)
	{
		const double *p;
		int nodeStart;
		double bladeEffectiveTemperature;
		double normalizedSpeed;
		double actualClearance;
		int parameterInputStart =
			control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
			427 + 10 * componentIndex : 400 + 10 * componentIndex;

		if (!SHT_IsClearanceComponentSelected(control, componentIndex))
			continue;
		if (!SHT_IsFinite(currentSpeed[componentIndex]) ||
			currentSpeed[componentIndex] < 0.0 ||
			!SHT_IsFinite(designSpeed[componentIndex]) ||
			designSpeed[componentIndex] <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_EVALUATION, -1,
				currentSpeed[componentIndex]);

		p = &parameters->clearanceParameter[10 * componentIndex];
		nodeStart = topology->clearanceMetalStart[componentIndex];
		bladeEffectiveTemperature =
			p[5] * state->metalTemperature[nodeStart] +
			(1.0 - p[5]) * state->metalTemperature[nodeStart + 1];
		normalizedSpeed = currentSpeed[componentIndex] /
			designSpeed[componentIndex];
		actualClearance = p[0]
			+ p[1] * (state->metalTemperature[nodeStart + 2] - p[6])
			- p[2] * (bladeEffectiveTemperature - p[7])
			- p[3] * (state->diskTemperature[componentIndex] - p[8])
			- p[4] * (normalizedSpeed * normalizedSpeed - p[9] * p[9]);

		if (!SHT_IsFinite(bladeEffectiveTemperature) ||
			!SHT_IsFinite(normalizedSpeed) ||
			!SHT_IsFinite(actualClearance) || actualClearance <= 0.0 ||
			!SHT_IsFinite(parameters->epsilonSS[componentIndex]) ||
			parameters->epsilonSS[componentIndex] <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_EVALUATION,
				parameterInputStart, actualClearance);

		evaluation->normalizedSpeed[componentIndex] = normalizedSpeed;
		evaluation->actualClearance[componentIndex] = actualClearance;
		evaluation->steadyClearance[componentIndex] =
			parameters->epsilonSS[componentIndex];
		evaluation->dynamicClearance[componentIndex] = actualClearance -
			parameters->epsilonSS[componentIndex];
	}

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

static int SHT_ClearanceCorrectionInputIndex(
	const SHTTransientControl *control,
	int rateIndex)
{
	if (control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503)
		return SHT_2503_K_CLEARANCE_RATE_START + rateIndex;
	return SHT_2502_K_CLEARANCE_W_HPC + rateIndex;
}

int SHT_EvaluateClearanceFeedback(
	const SHTTransientControl *control,
	const double exchangeRate[SHT_CLEARANCE_RATE_COUNT],
	const double kSM[SHT_COMPRESSOR_CLEARANCE_COUNT],
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	int componentIndex;
	int i;

	if (control == 0 || exchangeRate == 0 || kSM == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	topology = SHT_GetTopology(control);
	for (i = 0; i < SHT_CLEARANCE_COMPONENT_COUNT; ++i)
	{
		evaluation->flowMultiplier[i] = 1.0;
		evaluation->efficiencyMultiplier[i] = 1.0;
		evaluation->feedbackApplied[i] = 0;
	}
	for (i = 0; i < SHT_COMPRESSOR_CLEARANCE_COUNT; ++i)
		evaluation->surgeMarginMultiplier[i] = 1.0;

	if (!control->clearanceEnable || !control->clearanceFeedbackEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		diagnostics->offendingStepInIndex = -1;
		diagnostics->offendingValue = 0.0;
		return SHT_STATUS_OK;
	}

	for (componentIndex = 0;
		componentIndex < topology->clearanceComponentCount;
		++componentIndex)
	{
		int flowRateIndex = topology->clearanceFlowRateIndex[componentIndex];
		int efficiencyRateIndex =
			topology->clearanceEfficiencyRateIndex[componentIndex];
		int compressorIndex =
			topology->clearanceCompressorIndex[componentIndex];
		double delta = evaluation->dynamicClearance[componentIndex];

		if (!SHT_IsClearanceComponentSelected(control, componentIndex))
			continue;
		if (flowRateIndex >= 0)
		{
			evaluation->flowMultiplier[componentIndex] =
				1.0 + exchangeRate[flowRateIndex] * delta;
			if (!SHT_IsFinite(evaluation->flowMultiplier[componentIndex]) ||
				evaluation->flowMultiplier[componentIndex] <= 0.0)
				return SHT_SetEvaluationError(diagnostics,
					SHT_ERROR_CLEARANCE_FEEDBACK,
					SHT_ClearanceCorrectionInputIndex(control, flowRateIndex),
					evaluation->flowMultiplier[componentIndex]);
		}
		if (efficiencyRateIndex >= 0)
		{
			evaluation->efficiencyMultiplier[componentIndex] =
				1.0 + exchangeRate[efficiencyRateIndex] * delta;
			if (!SHT_IsFinite(
				evaluation->efficiencyMultiplier[componentIndex]) ||
				evaluation->efficiencyMultiplier[componentIndex] <= 0.0)
				return SHT_SetEvaluationError(diagnostics,
					SHT_ERROR_CLEARANCE_FEEDBACK,
					SHT_ClearanceCorrectionInputIndex(
						control, efficiencyRateIndex),
					evaluation->efficiencyMultiplier[componentIndex]);
		}
		if (compressorIndex >= 0)
		{
			int smInputIndex =
				control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
				493 + compressorIndex : 433;
			evaluation->surgeMarginMultiplier[compressorIndex] =
				1.0 + kSM[compressorIndex] * delta;
			if (!SHT_IsFinite(
				evaluation->surgeMarginMultiplier[compressorIndex]) ||
				evaluation->surgeMarginMultiplier[compressorIndex] <= 0.0)
				return SHT_SetEvaluationError(diagnostics,
					SHT_ERROR_CLEARANCE_FEEDBACK, smInputIndex,
					evaluation->surgeMarginMultiplier[compressorIndex]);
		}
		evaluation->feedbackApplied[componentIndex] = 1;
	}

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

int SHT_EvaluateHeatComponent(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	int firstNode;
	int localIndex;
	double representativeGasTemperature;
	double viscosityCurrent;
	double viscosityReference;
	double rniStar;

	if (control == 0 || state == 0 || parameters == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	topology = SHT_GetTopology(control);
	if (componentIndex < 0 ||
		componentIndex >= topology->heatComponentCount)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, (double)componentIndex);

	evaluation->componentHeatFlow[componentIndex] = 0.0;
	if (!control->heatStateEnable ||
		!SHT_IsHeatComponentSelected(control, componentIndex))
		return SHT_STATUS_OK;
	if (!SHT_IsFinite(componentFlow) || componentFlow <= 0.0 ||
		!SHT_IsFinite(inletTemperature) || inletTemperature <= 0.0 ||
		!SHT_IsFinite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, componentFlow);

	firstNode = topology->heatNodeStart[componentIndex];
	for (localIndex = 0;
		localIndex < topology->heatNodeCount[componentIndex];
		++localIndex)
	{
		int nodeIndex = firstNode + localIndex;
		double beta = parameters->beta[nodeIndex];
		evaluation->gasTemperature[nodeIndex] =
			(1.0 - beta) * inletTemperature + beta * outletTemperature;
		if (!SHT_IsFinite(evaluation->gasTemperature[nodeIndex]) ||
			evaluation->gasTemperature[nodeIndex] <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				SHT_BetaInputIndex(control, nodeIndex),
				evaluation->gasTemperature[nodeIndex]);
	}

	representativeGasTemperature = evaluation->gasTemperature[firstNode];
	if (topology->heatUsesAir[componentIndex])
	{
		viscosityCurrent =
			SHT_AirDynamicViscosity(representativeGasTemperature);
		viscosityReference = SHT_AirDynamicViscosity(
			parameters->referenceGasTemperature[componentIndex]);
	}
	else
	{
		viscosityCurrent =
			SHT_GasDynamicViscosity(representativeGasTemperature);
		viscosityReference = SHT_GasDynamicViscosity(
			parameters->referenceGasTemperature[componentIndex]);
	}
	rniStar = componentFlow / parameters->referenceFlow[componentIndex] *
		viscosityReference / viscosityCurrent;
	if (!SHT_IsFinite(rniStar) || rniStar <= 0.0)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, rniStar);
	evaluation->componentRNIStar[componentIndex] = rniStar;

	for (localIndex = 0;
		localIndex < topology->heatNodeCount[componentIndex];
		++localIndex)
	{
		int nodeIndex = firstNode + localIndex;
		double timeConstant = parameters->tau0[nodeIndex] *
			(1.0 + heatTimeCorrection) / pow(rniStar, 0.8);
		double heatConductance;
		double temperatureDifference;
		if (!SHT_IsFinite(timeConstant) || timeConstant <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				SHT_TauInputIndex(control, nodeIndex), timeConstant);
		heatConductance =
			parameters->heatCapacity0[nodeIndex] / timeConstant;
		temperatureDifference = evaluation->gasTemperature[nodeIndex] -
			state->metalTemperature[nodeIndex];
		evaluation->timeConstant[nodeIndex] = timeConstant;
		evaluation->heatConductance[nodeIndex] = heatConductance;
		evaluation->heatFlow[nodeIndex] =
			heatConductance * temperatureDifference;
		evaluation->componentHeatFlow[componentIndex] +=
			evaluation->heatFlow[nodeIndex];
		evaluation->metalTemperatureDerivative[nodeIndex] =
			temperatureDifference / timeConstant;
		if (!SHT_IsFinite(evaluation->heatFlow[nodeIndex]) ||
			!SHT_IsFinite(
				evaluation->metalTemperatureDerivative[nodeIndex]))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				300 + nodeIndex,
				evaluation->metalTemperatureDerivative[nodeIndex]);
	}
	return SHT_STATUS_OK;
}

int SHT_EvaluateHeatStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double componentFlow[SHT_HEAT_COMPONENT_COUNT],
	const double inletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double outletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT],
	const double diskTimeCorrection[SHT_DISK_NODE_COUNT],
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	int componentIndex;
	int diskIndex;

	if (control == 0 || state == 0 || parameters == 0 ||
		componentFlow == 0 || inletTemperature == 0 ||
		outletTemperature == 0 || heatTimeCorrection == 0 ||
		diskTimeCorrection == 0 || evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	topology = SHT_GetTopology(control);
	SHT_ResetHeatEvaluation(evaluation);
	if (!control->heatStateEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		return SHT_STATUS_OK;
	}

	for (componentIndex = 0;
		componentIndex < topology->heatComponentCount;
		++componentIndex)
	{
		int status = SHT_EvaluateHeatComponent(control, state, parameters,
			componentIndex, componentFlow[componentIndex],
			inletTemperature[componentIndex],
			outletTemperature[componentIndex],
			heatTimeCorrection[componentIndex], evaluation, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}

	for (diskIndex = 0; diskIndex < topology->diskNodeCount; ++diskIndex)
	{
		int heatComponent = topology->diskHeatComponent[diskIndex];
		double diskTimeConstant;
		if (!SHT_IsHeatComponentSelected(control, heatComponent))
			continue;
		diskTimeConstant = parameters->diskTau0[diskIndex] *
			(1.0 + diskTimeCorrection[diskIndex]);
		if (!SHT_IsFinite(diskTimeConstant) || diskTimeConstant <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				SHT_DiskTauInputIndex(control, diskIndex),
				diskTimeConstant);
		evaluation->diskTimeConstant[diskIndex] = diskTimeConstant;
		evaluation->diskTemperatureDerivative[diskIndex] =
			(state->metalTemperature[topology->diskRootNode[diskIndex]] -
			 state->diskTemperature[diskIndex]) / diskTimeConstant;
		if (!SHT_IsFinite(
			evaluation->diskTemperatureDerivative[diskIndex]))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION, -1,
				evaluation->diskTemperatureDerivative[diskIndex]);
	}

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

static double SHT_VisserMetalTemperature(
	const SHTTransientState *state,
	int logicalNodeIndex)
{
	if (logicalNodeIndex < SHT_SPLIT_METAL_NODE_COUNT)
		return state->metalTemperature[logicalNodeIndex];
	return state->guideVaneTemperature[
		logicalNodeIndex - SHT_SPLIT_METAL_NODE_COUNT];
}

static int SHT_VisserGuideIndexForComponent(const SHTTransientControl *control, int componentIndex)
{
	int i;
	if (control->modelMode == 0) return componentIndex == 2 ? 0 : -1;
	for (i = 0; i < SHT_VISSER_GUIDE_VANE_NODE_COUNT; ++i)
		if (SHT_VisserGuideComponent[i] == componentIndex)
			return i;
	return -1;
}

/*
 * Visser主流侧纯求值核。UA按RNI*^0.8调度，K_tau仍作为个体换热
 * 时间尺度修正使用。beta表示节点等效气温在部件进出口温度之间的位置，
 * 同时用于把涡轮热流连续分配到膨胀前后，替代固定50/50拆分。
 */
int SHT_EvaluateVisserMainGasComponent(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	int firstNode;
	int nodeCount;
	int localIndex;
	int guideIndex;
	double representativeGasTemperature;
	double viscosityCurrent;
	double viscosityReference;
	double rniStar;
	double correctionMultiplier;
	double totalHeatFlow = 0.0;
	double frontHeatFlow = 0.0;
	double rearHeatFlow = 0.0;

	if (control == 0 || state == 0 || parameters == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	if (control->thermalModelMode != SHT_THERMAL_MODEL_VISSER)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED, 341,
			(double)control->thermalModelMode);
	topology = SHT_GetTopology(control);
	if (componentIndex < 0 || componentIndex >= topology->heatComponentCount)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, (double)componentIndex);

	evaluation->componentHeatFlow[componentIndex] = 0.0;
	evaluation->visserMainGasHeatFlow[componentIndex] = 0.0;
	evaluation->visserMainGasFrontHeatFlow[componentIndex] = 0.0;
	evaluation->visserMainGasRearHeatFlow[componentIndex] = 0.0;
	if (!control->heatStateEnable ||
		!SHT_IsHeatComponentSelected(control, componentIndex))
		return SHT_STATUS_OK;
	/*
	 * 停机热浸允许主流量严格等于零。此时RNI*=0，UA按RNI*^0.8
	 * 自然退化为零；完整Visser核仍保留根部与转盘之间的内部导热。
	 * 负流量仍不属于本轮地面起停模型的物理范围。
	 */
	if (!SHT_IsFinite(componentFlow) || componentFlow < 0.0 ||
		(componentFlow == 0.0 && !SHT_ZeroFlowHeatEvaluationEnabled) ||
		!SHT_IsFinite(inletTemperature) || inletTemperature <= 0.0 ||
		!SHT_IsFinite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, componentFlow);

	firstNode = topology->heatNodeStart[componentIndex];
	nodeCount = topology->heatNodeCount[componentIndex];
	representativeGasTemperature =
		(1.0 - parameters->visserHotGasBeta[firstNode]) * inletTemperature +
		parameters->visserHotGasBeta[firstNode] * outletTemperature;
	if (topology->heatUsesAir[componentIndex])
	{
		viscosityCurrent = SHT_AirDynamicViscosity(representativeGasTemperature);
		viscosityReference = SHT_AirDynamicViscosity(
			parameters->referenceGasTemperature[componentIndex]);
	}
	else
	{
		viscosityCurrent = SHT_GasDynamicViscosity(representativeGasTemperature);
		viscosityReference = SHT_GasDynamicViscosity(
			parameters->referenceGasTemperature[componentIndex]);
	}
	rniStar = componentFlow / parameters->referenceFlow[componentIndex] *
		viscosityReference / viscosityCurrent;
	correctionMultiplier = 1.0 + heatTimeCorrection;
	if (!SHT_IsFinite(rniStar) || rniStar < 0.0 ||
		(rniStar == 0.0 && !SHT_ZeroFlowHeatEvaluationEnabled) ||
		!SHT_IsFinite(correctionMultiplier) || correctionMultiplier <= 0.0)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_HEAT_EVALUATION, -1, rniStar);
	evaluation->componentRNIStar[componentIndex] = rniStar;

	for (localIndex = 0; localIndex < nodeCount; ++localIndex)
	{
		int nodeIndex = firstNode + localIndex;
		double beta = parameters->visserHotGasBeta[nodeIndex];
		double gasTemperature =
			(1.0 - beta) * inletTemperature + beta * outletTemperature;
		double conductance = parameters->visserHotGasConductance0[nodeIndex] *
			pow(rniStar, 0.8) / correctionMultiplier;
		double heatFlow = conductance *
			(gasTemperature - state->metalTemperature[nodeIndex]);
		if (!SHT_IsFinite(gasTemperature) || gasTemperature <= 0.0 ||
			!SHT_IsFinite(conductance) || conductance < 0.0 ||
			!SHT_IsFinite(heatFlow))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION, 300 + nodeIndex, heatFlow);
		evaluation->gasTemperature[nodeIndex] = gasTemperature;
		evaluation->heatConductance[nodeIndex] = conductance;
		evaluation->timeConstant[nodeIndex] = conductance > DBL_MIN ?
			parameters->visserMetalHeatCapacity[nodeIndex] / conductance : 0.0;
		evaluation->heatFlow[nodeIndex] = heatFlow;
		totalHeatFlow += heatFlow;
		frontHeatFlow += (1.0 - beta) * heatFlow;
		rearHeatFlow += beta * heatFlow;
	}

	guideIndex = SHT_VisserGuideIndexForComponent(control, componentIndex);
	if (guideIndex >= 0)
	{
		int logicalIndex = control->metalNodeCount + guideIndex;
		double beta = parameters->visserHotGasBeta[logicalIndex];
		double gasTemperature =
			(1.0 - beta) * inletTemperature + beta * outletTemperature;
		double conductance = parameters->visserHotGasConductance0[logicalIndex] *
			pow(rniStar, 0.8) / correctionMultiplier;
		double heatFlow = conductance *
			(gasTemperature - state->guideVaneTemperature[guideIndex]);
		if (!SHT_IsFinite(gasTemperature) || gasTemperature <= 0.0 ||
			!SHT_IsFinite(conductance) || conductance < 0.0 ||
			!SHT_IsFinite(heatFlow))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				SHT_INPUT_TEMPERATURE_START + control->metalNodeCount +
				control->diskNodeCount + guideIndex, heatFlow);
		evaluation->visserGuideVaneGasTemperature[guideIndex] = gasTemperature;
		evaluation->visserGuideVaneHeatFlow[guideIndex] = heatFlow;
		totalHeatFlow += heatFlow;
		frontHeatFlow += (1.0 - beta) * heatFlow;
		rearHeatFlow += beta * heatFlow;
	}

	evaluation->componentHeatFlow[componentIndex] = totalHeatFlow;
	evaluation->visserMainGasHeatFlow[componentIndex] = totalHeatFlow;
	evaluation->visserMainGasFrontHeatFlow[componentIndex] = frontHeatFlow;
	evaluation->visserMainGasRearHeatFlow[componentIndex] = rearHeatFlow;
	return SHT_STATUS_OK;
}

int SHT_EvaluateVisserHeatStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double componentFlow[SHT_HEAT_COMPONENT_COUNT],
	const double inletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double outletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT],
	const double diskTimeCorrection[SHT_DISK_NODE_COUNT],
	const double metalCoolingHeatFlow[SHT_VISSER_METAL_NODE_COUNT],
	const double diskCoolingHeatFlow[SHT_DISK_NODE_COUNT],
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	const SHTTransientTopology *topology;
	double rootHeatLoss[SHT_SPLIT_METAL_NODE_COUNT] = { 0.0 };
	double mainGasTotal = 0.0;
	double coolingTotal = 0.0;
	double storedEnergyRate = 0.0;
	double scale;
	int componentIndex;
	int nodeIndex;
	int diskIndex;
	int guideIndex;

	if (control == 0 || state == 0 || parameters == 0 ||
		componentFlow == 0 || inletTemperature == 0 ||
		outletTemperature == 0 || heatTimeCorrection == 0 ||
		diskTimeCorrection == 0 || metalCoolingHeatFlow == 0 ||
		diskCoolingHeatFlow == 0 || evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	if (control->thermalModelMode != SHT_THERMAL_MODEL_VISSER)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED, 341,
			(double)control->thermalModelMode);
	topology = SHT_GetTopology(control);
	SHT_ResetHeatEvaluation(evaluation);
	if (!control->heatStateEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		return SHT_STATUS_OK;
	}

	for (componentIndex = 0;
		componentIndex < topology->heatComponentCount; ++componentIndex)
	{
		int status = SHT_EvaluateVisserMainGasComponent(
			control, state, parameters, componentIndex,
			componentFlow[componentIndex], inletTemperature[componentIndex],
			outletTemperature[componentIndex],
			heatTimeCorrection[componentIndex], evaluation, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		mainGasTotal += evaluation->visserMainGasHeatFlow[componentIndex];
	}

	for (nodeIndex = 0; nodeIndex < control->metalNodeCount + control->guideVaneNodeCount; ++nodeIndex)
	{
		evaluation->visserMetalCoolingHeatFlow[nodeIndex] =
			metalCoolingHeatFlow[nodeIndex];
		coolingTotal += metalCoolingHeatFlow[nodeIndex];
	}
	for (diskIndex = 0; diskIndex < topology->diskNodeCount; ++diskIndex)
	{
		int heatComponent = topology->diskHeatComponent[diskIndex];
		double conductance;
		double rootDiskHeatFlow;
		if (!SHT_IsHeatComponentSelected(control, heatComponent))
			continue;
		conductance = parameters->visserRootDiskConductance0[diskIndex] /
			(1.0 + diskTimeCorrection[diskIndex]);
		rootDiskHeatFlow = conductance *
			(state->metalTemperature[topology->diskRootNode[diskIndex]] -
			 state->diskTemperature[diskIndex]);
		if (!SHT_IsFinite(conductance) || conductance <= 0.0 ||
			!SHT_IsFinite(rootDiskHeatFlow))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION, -1, rootDiskHeatFlow);
		evaluation->visserRootDiskHeatFlow[diskIndex] = rootDiskHeatFlow;
		evaluation->visserDiskCoolingHeatFlow[diskIndex] =
			diskCoolingHeatFlow[diskIndex];
		rootHeatLoss[topology->diskRootNode[diskIndex]] = rootDiskHeatFlow;
		evaluation->diskTemperatureDerivative[diskIndex] =
			(rootDiskHeatFlow - diskCoolingHeatFlow[diskIndex]) /
			parameters->visserDiskHeatCapacity[diskIndex];
		storedEnergyRate += parameters->visserDiskHeatCapacity[diskIndex] *
			evaluation->diskTemperatureDerivative[diskIndex];
		coolingTotal += diskCoolingHeatFlow[diskIndex];
	}

	for (nodeIndex = 0; nodeIndex < control->metalNodeCount; ++nodeIndex)
	{
		double derivative =
			(evaluation->heatFlow[nodeIndex] -
			 metalCoolingHeatFlow[nodeIndex] - rootHeatLoss[nodeIndex]) /
			parameters->visserMetalHeatCapacity[nodeIndex];
		if (!SHT_IsFinite(derivative))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION, 300 + nodeIndex, derivative);
		evaluation->metalTemperatureDerivative[nodeIndex] = derivative;
		storedEnergyRate += parameters->visserMetalHeatCapacity[nodeIndex] *
			derivative;
	}
	for (guideIndex = 0;
		guideIndex < control->guideVaneNodeCount; ++guideIndex)
	{
		int logicalIndex = control->metalNodeCount + guideIndex;
		double derivative =
			(evaluation->visserGuideVaneHeatFlow[guideIndex] -
			 metalCoolingHeatFlow[logicalIndex]) /
			parameters->visserMetalHeatCapacity[logicalIndex];
		if (!SHT_IsFinite(derivative))
			return SHT_SetEvaluationError(diagnostics,
				SHT_ERROR_HEAT_EVALUATION,
				SHT_INPUT_TEMPERATURE_START + control->metalNodeCount +
				control->diskNodeCount + guideIndex, derivative);
		evaluation->guideVaneTemperatureDerivative[guideIndex] = derivative;
		storedEnergyRate += parameters->visserMetalHeatCapacity[logicalIndex] *
			derivative;
	}

	evaluation->visserEnergyResidual =
		mainGasTotal - coolingTotal - storedEnergyRate;
	scale = fabs(mainGasTotal) + fabs(coolingTotal) +
		fabs(storedEnergyRate) + 1.0;
	evaluation->visserNormalizedEnergyResidual =
		fabs(evaluation->visserEnergyResidual) / scale;
	if (!SHT_IsFinite(evaluation->visserNormalizedEnergyResidual) ||
		evaluation->visserNormalizedEnergyResidual > 1.0e-9)
		return SHT_SetEvaluationError(diagnostics,
			SHT_ERROR_VISSER_ENERGY_BALANCE, -1,
			evaluation->visserNormalizedEnergyResidual);

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

void SHT_ResetTransientData(
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	if (control != 0) memset(control, 0, sizeof(*control));
	if (state != 0) memset(state, 0, sizeof(*state));
	if (parameters != 0) memset(parameters, 0, sizeof(*parameters));
	if (diagnostics != 0)
	{
		memset(diagnostics, 0, sizeof(*diagnostics));
		diagnostics->offendingStepInIndex = -1;
	}
}

void SHT_ResetTransientEvaluationDiagnostics(
	SHTTransientDiagnostics *diagnostics)
{
	if (diagnostics == 0)
		return;

	/* configurationValid和四个部件选择标志属于本次DLL调用的配置结果。 */
	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	memset(diagnostics->heatFeedbackApplied, 0,
		sizeof(diagnostics->heatFeedbackApplied));
	memset(diagnostics->heatFeedbackConverged, 0,
		sizeof(diagnostics->heatFeedbackConverged));
	memset(diagnostics->heatFeedbackIterationCount, 0,
		sizeof(diagnostics->heatFeedbackIterationCount));
	memset(diagnostics->heatFeedbackIterationResidual, 0,
		sizeof(diagnostics->heatFeedbackIterationResidual));
	memset(diagnostics->heatFeedbackEnergyResidual, 0,
		sizeof(diagnostics->heatFeedbackEnergyResidual));
}

static int SHT_ParseCommonControls(
	const double *stepIn,
	SHTTransientControl *control,
	SHTTransientDiagnostics *diagnostics)
{
	static const int modeTargets[] = { 0, 1, 2, 3 };
	static const int binaryTargets[] = { 0, 1 };
	static const int maskTargets[] = {
		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
	};
	int status;

	status = SHT_DecodeDiscrete(stepIn[341], modeTargets, 4, 341,
		&control->thermalModelMode, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[342], binaryTargets, 2, 342,
		&control->inertiaEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[343], binaryTargets, 2, 343,
		&control->heatStateEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[344], binaryTargets, 2, 344,
		&control->heatFeedbackEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[345], binaryTargets, 2, 345,
		&control->clearanceEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[346], binaryTargets, 2, 346,
		&control->clearanceFeedbackEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_DecodeDiscrete(stepIn[347], maskTargets, 16, 347,
		&control->componentMask, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	diagnostics->hpcSelected =
		(control->componentMask & SHT_COMPONENT_HPC) != 0;
	diagnostics->burnerSelected =
		(control->componentMask & SHT_COMPONENT_BURNER) != 0;
	diagnostics->gtSelected =
		(control->componentMask & SHT_COMPONENT_GT) != 0;
	diagnostics->ptSelected =
		(control->componentMask & SHT_COMPONENT_PT) != 0;
	if (control->thermalModelMode == 2)
		return SHT_SetError(diagnostics,
			SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED, 341, stepIn[341]);
	if (control->heatFeedbackEnable && !control->heatStateEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY,
			344, stepIn[344]);
	if (control->clearanceEnable && !control->heatStateEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY,
			345, stepIn[345]);
	if (control->clearanceFeedbackEnable && !control->clearanceEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY,
			346, stepIn[346]);
	if ((control->heatStateEnable || control->clearanceEnable) &&
		control->thermalModelMode != SHT_THERMAL_MODEL_KURZKE &&
		control->thermalModelMode != SHT_THERMAL_MODEL_VISSER)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY,
			341, stepIn[341]);
	control->guideVaneNodeCount =
		control->thermalModelMode == SHT_THERMAL_MODEL_VISSER ?
		(control->modelMode == 0 ? 1 : SHT_VISSER_GUIDE_VANE_NODE_COUNT) : 0;
	return SHT_STATUS_OK;
}

static int SHT_ParseLegacy2502(
	const double *stepIn,
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	static const int heatCorrectionInput[4] = {
		SHT_2502_K_TAU_HPC, SHT_2502_K_TAU_BURNER,
		SHT_2502_K_TAU_GT, SHT_2502_K_TAU_PT
	};
	static const int diskCorrectionInput[3] = {
		SHT_2502_K_TAU_DISK_HPC, SHT_2502_K_TAU_DISK_GT,
		SHT_2502_K_TAU_DISK_PT
	};
	static const int componentDiskIndex[4] = { 0, -1, 1, 2 };
	static const int componentDiskCorrectionInput[4] = {
		SHT_2502_K_TAU_DISK_HPC, -1,
		SHT_2502_K_TAU_DISK_GT, SHT_2502_K_TAU_DISK_PT
	};
	int i;
	int status;

	status = SHT_CheckReservedRange(stepIn, 348, 349, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 391, 399, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 438, 511, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	for (i = 0; i < SHT_LEGACY_METAL_NODE_COUNT; ++i)
	{
		state->metalTemperature[i] = stepIn[300 + i];
		parameters->tau0[i] = stepIn[350 + i];
		parameters->heatCapacity0[i] = stepIn[360 + i];
		parameters->beta[i] = stepIn[370 + i];
	}
	for (i = 0; i < SHT_LEGACY_DISK_NODE_COUNT; ++i)
	{
		state->diskTemperature[i] = stepIn[310 + i];
		parameters->diskTau0[i] = stepIn[380 + i];
		parameters->epsilonSS[i] = stepIn[430 + i];
		parameters->diskTimeCorrection[i] =
			stepIn[diskCorrectionInput[i]];
	}
	for (i = 0; i < SHT_LEGACY_HEAT_COMPONENT_COUNT; ++i)
	{
		parameters->referenceFlow[i] = stepIn[383 + i];
		parameters->referenceGasTemperature[i] = stepIn[387 + i];
		parameters->heatTimeCorrection[i] =
			stepIn[heatCorrectionInput[i]];
	}
	for (i = 0; i < 30; ++i)
		parameters->clearanceParameter[i] = stepIn[400 + i];
	parameters->kSM[0] = stepIn[433];
	parameters->inertiaCorrection[0] = stepIn[SHT_2502_K_JG];
	parameters->inertiaCorrection[1] = stepIn[SHT_2502_K_JP];
	for (i = 0; i < 4; ++i)
	{
		parameters->nominalClearanceExchangeRate[i] = stepIn[434 + i];
		parameters->clearanceRateCorrection[i] =
			stepIn[SHT_2502_K_CLEARANCE_W_HPC + i];
		parameters->effectiveClearanceExchangeRate[i] =
			parameters->nominalClearanceExchangeRate[i] *
			(1.0 + parameters->clearanceRateCorrection[i]);
	}

	if (control->inertiaEnable)
	{
		status = SHT_CheckCorrectionFactor(stepIn[SHT_2502_K_JG],
			SHT_2502_K_JG, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_CheckCorrectionFactor(stepIn[SHT_2502_K_JP],
			SHT_2502_K_JP, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	if (control->heatStateEnable)
	{
		for (i = 0; i < SHT_LEGACY_HEAT_COMPONENT_COUNT; ++i)
		{
			if (!SHT_IsHeatComponentSelected(control, i)) continue;
			status = SHT_ValidateHeatComponent(stepIn, control, i,
				heatCorrectionInput[i], componentDiskIndex[i],
				componentDiskCorrectionInput[i], diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
	}
	if (control->clearanceEnable)
	{
		if (diagnostics->hpcSelected)
		{
			const int c[] = { 104, 105 };
			const int n[] = { 434, 435 };
			status = SHT_ValidateClearanceComponent(stepIn, 400, 430,
				c, n, control->clearanceFeedbackEnable ? 2 : 0,
				control->clearanceFeedbackEnable ? 433 : -1,
				diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->gtSelected)
		{
			const int c[] = { 106 };
			const int n[] = { 436 };
			status = SHT_ValidateClearanceComponent(stepIn, 410, 431,
				c, n, control->clearanceFeedbackEnable ? 1 : 0,
				-1, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->ptSelected)
		{
			const int c[] = { 107 };
			const int n[] = { 437 };
			status = SHT_ValidateClearanceComponent(stepIn, 420, 432,
				c, n, control->clearanceFeedbackEnable ? 1 : 0,
				-1, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
	}
	return SHT_STATUS_OK;
}

/* 三部件新入口只通过初始化传标称量；旧 Kurzke stepIn 合同继续兼容。 */
static int SHT_Parse2502(
	const double *stepIn, SHTTransientControl *control,
	SHTTransientState *state, SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	double expanded[512];
	const SHTTransientParameters *p = &SHT_ThermalConfiguration.nominal;
	int i, status;
	if (!SHT_ThermalConfiguration.initialized)
	{
		if (control->thermalModelMode == SHT_THERMAL_MODEL_VISSER)
			return SHT_SetError(diagnostics, SHT_ERROR_THERMAL_CONFIG_NOT_INITIALIZED, 341, stepIn[341]);
		return SHT_ParseLegacy2502(stepIn, control, state, parameters, diagnostics);
	}
	status = SHT_CopyThermalConfiguration(control->modelMode, control->thermalModelMode, parameters);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 350, 429, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 433, 511, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, control->guideVaneNodeCount ? 314 : 313, 339, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	memcpy(expanded, stepIn, sizeof(expanded));
	for (i = 0; i < 10; ++i)
	{
		int visser = control->thermalModelMode == SHT_THERMAL_MODEL_VISSER;
		expanded[350 + i] = visser ? p->visserMetalHeatCapacity[i] /
			fmax(p->visserHotGasConductance0[i], 1.e-12) : p->tau0[i];
		expanded[360 + i] = visser ? p->visserMetalHeatCapacity[i] : p->heatCapacity0[i];
		expanded[370 + i] = visser ? p->visserHotGasBeta[i] : p->beta[i];
	}
	for (i = 0; i < 3; ++i)
		expanded[380 + i] = control->thermalModelMode == SHT_THERMAL_MODEL_VISSER ?
			p->visserDiskHeatCapacity[i] / p->visserRootDiskConductance0[i] : p->diskTau0[i];
	for (i = 0; i < 4; ++i)
	{
		expanded[383 + i] = p->referenceFlow[i];
		expanded[387 + i] = p->referenceGasTemperature[i];
		expanded[434 + i] = p->nominalClearanceExchangeRate[i];
	}
	for (i = 0; i < 30; ++i) expanded[400 + i] = p->clearanceParameter[i];
	expanded[433] = p->kSM[0];
	status = SHT_ParseLegacy2502(expanded, control, state, parameters, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CopyThermalConfiguration(control->modelMode, control->thermalModelMode, parameters);
	if (status != SHT_STATUS_OK) return status;
	if (control->guideVaneNodeCount)
	{
		state->guideVaneTemperature[0] = stepIn[313];
		if (control->heatStateEnable)
			return SHT_ValidateVisserRuntime(control, state, parameters, diagnostics);
	}
	return SHT_STATUS_OK;
}

static int SHT_Parse2503(
	const double *stepIn,
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	static const int componentDiskIndex[7] = { 0, 1, -1, 2, 3, 4, 5 };
	static const int componentDiskCorrectionInput[7] = {
		138, 139, -1, 140, 141, 142, 143
	};
	int i;
	int status;

	status = SHT_CheckReservedRange(stepIn,
		control->thermalModelMode == SHT_THERMAL_MODEL_VISSER ? 327 : 325,
		339, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 348, 349, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	/*
	 * 六部件新路径中，原固定参数区必须严格为零。epsilon_ss
	 * 是当前工况量，仍使用 stepIn[487:492]，故从检查范围中排除。
	 */
	status = SHT_CheckReservedRange(stepIn, 350, 486, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 493, 502, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 503, 511, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	if (control->thermalModelMode == SHT_THERMAL_MODEL_KURZKE ||
		control->thermalModelMode == SHT_THERMAL_MODEL_VISSER)
	{
		status = SHT_CopyThermalConfiguration(
			control->modelMode, control->thermalModelMode, parameters);
		if (status != SHT_STATUS_OK)
			return SHT_SetError(diagnostics, status, -1,
				(double)control->thermalModelMode);
	}

	for (i = 0; i < SHT_SPLIT_METAL_NODE_COUNT; ++i)
		state->metalTemperature[i] = stepIn[300 + i];
	if (control->thermalModelMode == SHT_THERMAL_MODEL_VISSER)
	{
		for (i = 0; i < SHT_VISSER_GUIDE_VANE_NODE_COUNT; ++i)
			state->guideVaneTemperature[i] = stepIn[325 + i];
	}
	for (i = 0; i < SHT_SPLIT_DISK_NODE_COUNT; ++i)
	{
		state->diskTemperature[i] = stepIn[319 + i];
		parameters->epsilonSS[i] = stepIn[487 + i];
		parameters->diskTimeCorrection[i] =
			stepIn[SHT_2503_K_TAU_DISK_START + i];
	}
	for (i = 0; i < SHT_SPLIT_HEAT_COMPONENT_COUNT; ++i)
	{
		parameters->heatTimeCorrection[i] =
			stepIn[SHT_2503_K_TAU_START + i];
	}
	parameters->inertiaCorrection[0] = stepIn[SHT_2503_K_JG];
	parameters->inertiaCorrection[1] = stepIn[SHT_2503_K_JP];
	for (i = 0; i < SHT_CLEARANCE_RATE_COUNT; ++i)
	{
		parameters->clearanceRateCorrection[i] =
			stepIn[SHT_2503_K_CLEARANCE_RATE_START + i];
		parameters->effectiveClearanceExchangeRate[i] =
			parameters->nominalClearanceExchangeRate[i] *
			(1.0 + parameters->clearanceRateCorrection[i]);
	}

	if (control->inertiaEnable)
	{
		status = SHT_CheckCorrectionFactor(stepIn[SHT_2503_K_JG],
			SHT_2503_K_JG, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_CheckCorrectionFactor(stepIn[SHT_2503_K_JP],
			SHT_2503_K_JP, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}
	if (control->heatStateEnable)
	{
		if (control->thermalModelMode == SHT_THERMAL_MODEL_VISSER)
		{
			status = SHT_ValidateVisserRuntime(
				control, state, parameters, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		else
		{
			for (i = 0; i < SHT_SPLIT_HEAT_COMPONENT_COUNT; ++i)
			{
				if (!SHT_IsHeatComponentSelected(control, i)) continue;
				status = SHT_ValidateHeatComponent2503(control, state, parameters, i,
					SHT_2503_K_TAU_START + i,
					componentDiskIndex[i],
					componentDiskCorrectionInput[i], diagnostics);
				if (status != SHT_STATUS_OK) return status;
			}
		}
	}
	if (control->clearanceEnable)
	{
		for (i = 0; i < SHT_SPLIT_CLEARANCE_COMPONENT_COUNT; ++i)
		{
			int exchangeCount = 1;
			int correctionStart;
			int surgeMarginIndex = -1;
			if (!SHT_IsClearanceComponentSelected(control, i)) continue;
			if (i < 2)
			{
				correctionStart = 144 + 2 * i;
				exchangeCount = 2;
				surgeMarginIndex = control->clearanceFeedbackEnable ?
					493 + i : -1;
			}
			else
			{
				correctionStart = 146 + i;
			}
			status = SHT_ValidateClearanceComponent2503(parameters, i,
				correctionStart,
				control->clearanceFeedbackEnable ? exchangeCount : 0,
				surgeMarginIndex, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
	}
	return SHT_STATUS_OK;
}

int SHT_ParseTransientInput(
	const double *stepIn,
	int modelMode,
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	static const int binaryTargets[] = { 0, 1 };
	int transientEffectsEnable;
	int status;

	if (stepIn == 0 || control == 0 || state == 0 ||
		parameters == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	SHT_ResetTransientData(control, state, parameters, diagnostics);
	if (modelMode != SHT_MODEL_MODE_ORIGINAL_LOCAL &&
		modelMode != SHT_MODEL_MODE_SPLIT_LOCAL)
		return SHT_SetError(diagnostics,
			SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED, -1, (double)modelMode);
	SHT_ConfigureTopology(control, modelMode);

	/*
	 * stepIn[340] 只控制是否启用增强瞬态效应。三/六部件拓扑已由
	 * DLL_SHT_InitialMode 固定，此处据此派生参数布局，禁止输入数组
	 * 再提供第二个拓扑选择源。
	 */
	status = SHT_DecodeDiscrete(
		stepIn[SHT_INPUT_TRANSIENT_EFFECTS_ENABLE],
		binaryTargets, 2, SHT_INPUT_TRANSIENT_EFFECTS_ENABLE,
		&transientEffectsEnable, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	if (!transientEffectsEnable)
	{
		control->interfaceVersion = SHT_TRANSIENT_INTERFACE_BASELINE;
		diagnostics->configurationValid = 1;
		return SHT_STATUS_OK;
	}
	control->interfaceVersion = modelMode == SHT_MODEL_MODE_SPLIT_LOCAL ?
		SHT_TRANSIENT_INTERFACE_2503 : SHT_TRANSIENT_INTERFACE_2502;

	status = SHT_ParseCommonControls(stepIn, control, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = control->interfaceVersion == SHT_TRANSIENT_INTERFACE_2503 ?
		SHT_Parse2503(stepIn, control, state, parameters, diagnostics) :
		SHT_Parse2502(stepIn, control, state, parameters, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->configurationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}
