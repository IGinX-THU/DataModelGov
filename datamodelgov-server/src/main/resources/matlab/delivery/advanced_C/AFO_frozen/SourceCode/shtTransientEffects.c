#include <float.h>
#include <math.h>
#include <string.h>
#include "shtTransientEffects.h"

/* 健康参数在 stepIn 中的 C 下标。 */
#define SHT_INPUT_K_JG 98
#define SHT_INPUT_K_JP 99
#define SHT_INPUT_K_TAU_HPC 100
#define SHT_INPUT_K_TAU_BURNER 101
#define SHT_INPUT_K_TAU_GT 102
#define SHT_INPUT_K_TAU_PT 103
#define SHT_INPUT_K_CLEARANCE_W_HPC 104
#define SHT_INPUT_K_CLEARANCE_ETA_HPC 105
#define SHT_INPUT_K_CLEARANCE_ETA_GT 106
#define SHT_INPUT_K_CLEARANCE_ETA_PT 107
#define SHT_INPUT_K_TAU_DISK_HPC 108
#define SHT_INPUT_K_TAU_DISK_GT 109
#define SHT_INPUT_K_TAU_DISK_PT 110

static int SHT_IsFinite(double value)
{
	return _finite(value) != 0;
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

/*
 * 运行时热状态求值错误与接口配置错误分开记录。调用该函数前，stepIn 已经
 * 通过完整配置校验，因此只把本次求值标记为无效，保留 configurationValid=1。
 */
static int SHT_SetEvaluationError(
	SHTTransientDiagnostics *diagnostics,
	int stepInIndex,
	double value)
{
	diagnostics->errorCode = SHT_ERROR_HEAT_EVALUATION;
	diagnostics->evaluationValid = 0;
	diagnostics->offendingStepInIndex = stepInIndex;
	diagnostics->offendingValue = value;
	return SHT_ERROR_HEAT_EVALUATION;
}

/*
 * P5 间隙状态/反馈运行时错误。接口已经通过配置校验，因此错误只使本次
 * 物理求值无效，不回写 configurationValid，便于调用方区分输入配置错误
 * 与当前状态超出模型适用范围。
 */
static int SHT_SetClearanceEvaluationError(
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

/*
 * double 离散控制量采用“最近合法目标 + 绝对容差”解码。这里不使用
 * value == target 或 floor(value) == value，避免把浮点传输细节误当成接口语义。
 */
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
		return SHT_SetError(diagnostics, SHT_ERROR_CONTROL_VALUE, stepInIndex, value);

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
		return SHT_SetError(diagnostics, SHT_ERROR_CONTROL_VALUE, stepInIndex, value);

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
		if (!SHT_IsFinite(stepIn[i]) || fabs(stepIn[i]) > SHT_TRANSIENT_CONTROL_TOL)
			return SHT_SetError(diagnostics, SHT_ERROR_RESERVED_INPUT, i, stepIn[i]);
	}
	return SHT_STATUS_OK;
}

static int SHT_CheckPositive(
	double value,
	int stepInIndex,
	SHTTransientDiagnostics *diagnostics)
{
	if (!SHT_IsFinite(value) || value <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE, stepInIndex, value);
	return SHT_STATUS_OK;
}

static int SHT_CheckCorrectionFactor(
	double correction,
	int stepInIndex,
	SHTTransientDiagnostics *diagnostics)
{
	if (!SHT_IsFinite(correction) || 1.0 + correction <= 0.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE, stepInIndex, correction);
	return SHT_STATUS_OK;
}

/* 校验一个热模型部件。各数组下标由冻结的 stepIn 字典显式传入。 */
static int SHT_ValidateHeatComponent(
	const double *stepIn,
	const int *stateIndices,
	int stateCount,
	int tauStart,
	int tauCount,
	int capacityStart,
	int betaStart,
	int referenceFlowIndex,
	int referenceTemperatureIndex,
	int healthTauIndex,
	int diskStateIndex,
	int diskTauIndex,
	int healthDiskTauIndex,
	SHTTransientDiagnostics *diagnostics)
{
	int i;
	int status;

	for (i = 0; i < stateCount; ++i)
	{
		double temperature = stepIn[stateIndices[i]];
		if (!SHT_IsFinite(temperature) || temperature <= 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				stateIndices[i], temperature);
	}

	for (i = 0; i < tauCount; ++i)
	{
		status = SHT_CheckPositive(stepIn[tauStart + i], tauStart + i, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
		status = SHT_CheckPositive(stepIn[capacityStart + i],
			capacityStart + i, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
		if (!SHT_IsFinite(stepIn[betaStart + i]) ||
			stepIn[betaStart + i] < 0.0 || stepIn[betaStart + i] > 1.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				betaStart + i, stepIn[betaStart + i]);
	}

	status = SHT_CheckPositive(stepIn[referenceFlowIndex], referenceFlowIndex, diagnostics);
	if (status != SHT_STATUS_OK)
		return status;
	status = SHT_CheckPositive(stepIn[referenceTemperatureIndex],
		referenceTemperatureIndex, diagnostics);
	if (status != SHT_STATUS_OK)
		return status;
	status = SHT_CheckCorrectionFactor(stepIn[healthTauIndex], healthTauIndex, diagnostics);
	if (status != SHT_STATUS_OK)
		return status;

	if (diskStateIndex >= 0)
	{
		status = SHT_CheckPositive(stepIn[diskStateIndex], diskStateIndex, diagnostics);
		if (status != SHT_STATUS_OK)
			return SHT_SetError(diagnostics, SHT_ERROR_STATE_VALUE,
				diskStateIndex, stepIn[diskStateIndex]);
		status = SHT_CheckPositive(stepIn[diskTauIndex], diskTauIndex, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
		status = SHT_CheckCorrectionFactor(stepIn[healthDiskTauIndex],
			healthDiskTauIndex, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
	}

	return SHT_STATUS_OK;
}

static int SHT_ValidateClearanceComponent(
	const double *stepIn,
	int parameterStart,
	int epsilonSSIndex,
	int firstCorrectionIndex,
	int firstNominalRateIndex,
	int exchangeCount,
	int validateSM,
	SHTTransientDiagnostics *diagnostics)
{
	int i;
	int status;

	status = SHT_CheckPositive(stepIn[parameterStart], parameterStart, diagnostics);
	if (status != SHT_STATUS_OK)
		return status;

	/* a_c/a_b/a_d 和离心系数可以为零，但必须是有限数。 */
	for (i = 1; i <= 4; ++i)
	{
		if (!SHT_IsFinite(stepIn[parameterStart + i]))
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				parameterStart + i, stepIn[parameterStart + i]);
	}
	if (!SHT_IsFinite(stepIn[parameterStart + 5]) ||
		stepIn[parameterStart + 5] < 0.0 || stepIn[parameterStart + 5] > 1.0)
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
			parameterStart + 5, stepIn[parameterStart + 5]);

	for (i = 6; i <= 9; ++i)
	{
		status = SHT_CheckPositive(stepIn[parameterStart + i],
			parameterStart + i, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
	}
	status = SHT_CheckPositive(stepIn[epsilonSSIndex], epsilonSSIndex, diagnostics);
	if (status != SHT_STATUS_OK)
		return status;

	for (i = 0; i < exchangeCount; ++i)
	{
		status = SHT_CheckCorrectionFactor(stepIn[firstCorrectionIndex + i],
			firstCorrectionIndex + i, diagnostics);
		if (status != SHT_STATUS_OK)
			return status;

		/* 正间隙偏差只能维持或降低性能，标称灵敏度不得为正。 */
		if (!SHT_IsFinite(stepIn[firstNominalRateIndex + i]) ||
			stepIn[firstNominalRateIndex + i] > 0.0)
			return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE,
				firstNominalRateIndex + i,
				stepIn[firstNominalRateIndex + i]);
	}
	if (validateSM && !SHT_IsFinite(stepIn[433]))
		return SHT_SetError(diagnostics, SHT_ERROR_PARAMETER_VALUE, 433, stepIn[433]);

	return SHT_STATUS_OK;
}

static int SHT_IsHeatComponentSelected(
	const SHTTransientControl *control,
	int componentIndex)
{
	static const int componentBits[SHT_HEAT_COMPONENT_COUNT] = {
		SHT_COMPONENT_HPC, SHT_COMPONENT_BURNER,
		SHT_COMPONENT_GT, SHT_COMPONENT_PT
	};
	return (control->componentMask & componentBits[componentIndex]) != 0;
}

/* HPC 使用干空气 Sutherland 关系；温度单位 K，返回 Pa*s。 */
static double SHT_AirDynamicViscosity(double temperature)
{
	return 1.46176814e-6 * pow(temperature, 1.5) / (temperature + 110.4);
}

/* Burner、GT、PT 首轮沿用现有程序的高温燃气工程关系。 */
static double SHT_GasDynamicViscosity(double temperature)
{
	return 1.5105e-6 * pow(temperature, 1.5) / (temperature + 120.0);
}

void SHT_ResetHeatEvaluation(SHTTransientHeatEvaluation *evaluation)
{
	if (evaluation != 0)
		memset(evaluation, 0, sizeof(*evaluation));
}

void SHT_ResetClearanceEvaluation(SHTTransientClearanceEvaluation *evaluation)
{
	int componentIndex;

	if (evaluation == 0)
		return;

	memset(evaluation, 0, sizeof(*evaluation));
	for (componentIndex = 0;
		componentIndex < SHT_CLEARANCE_COMPONENT_COUNT;
		++componentIndex)
	{
		evaluation->flowMultiplier[componentIndex] = 1.0;
		evaluation->efficiencyMultiplier[componentIndex] = 1.0;
	}
	evaluation->surgeMarginMultiplier = 1.0;
}

/* 间隙部件顺序固定为 HPC、GT、PT；Burner 不属于叶尖间隙模型。 */
static int SHT_IsClearanceComponentSelected(
	const SHTTransientControl *control,
	int componentIndex)
{
	static const int componentBits[SHT_CLEARANCE_COMPONENT_COUNT] = {
		SHT_COMPONENT_HPC, SHT_COMPONENT_GT, SHT_COMPONENT_PT
	};
	return (control->componentMask & componentBits[componentIndex]) != 0;
}

/*
 * P5 归一化间隙状态核。三个部件的金属节点均按“叶片、叶根、机匣”排列；
 * epsilonSS 是 M 端在当前已接受积分步起点查表并保持的稳态参考间隙。
 */
int SHT_EvaluateClearanceStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double currentSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	const double designSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	static const int metalNodeStart[SHT_CLEARANCE_COMPONENT_COUNT] = { 0, 4, 7 };
	int componentIndex;

	if (control == 0 || state == 0 || parameters == 0 ||
		currentSpeed == 0 || designSpeed == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;

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
		componentIndex < SHT_CLEARANCE_COMPONENT_COUNT;
		++componentIndex)
	{
		const double *p;
		int nodeStart;
		double bladeEffectiveTemperature;
		double normalizedSpeed;
		double actualClearance;

		if (!SHT_IsClearanceComponentSelected(control, componentIndex))
			continue;

		if (!SHT_IsFinite(currentSpeed[componentIndex]) ||
			currentSpeed[componentIndex] < 0.0 ||
			!SHT_IsFinite(designSpeed[componentIndex]) ||
			designSpeed[componentIndex] <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_EVALUATION, -1,
				currentSpeed[componentIndex]);

		p = &parameters->clearanceParameter[10 * componentIndex];
		nodeStart = metalNodeStart[componentIndex];
		bladeEffectiveTemperature = p[5] * state->metalTemperature[nodeStart] +
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
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_EVALUATION,
				400 + 10 * componentIndex, actualClearance);

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

/*
 * 把动态间隙偏差转换为部件特性倍率。倍率不做静默限幅；若交换率使倍率
 * 非有限或非正，立即拒绝该计算点，避免把模型失效伪装成可用结果。
 */
int SHT_EvaluateClearanceFeedback(
	const SHTTransientControl *control,
	const double exchangeRate[4],
	double kSMHPC,
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics)
{
	int componentIndex;

	if (control == 0 || exchangeRate == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;

	for (componentIndex = 0;
		componentIndex < SHT_CLEARANCE_COMPONENT_COUNT;
		++componentIndex)
	{
		evaluation->flowMultiplier[componentIndex] = 1.0;
		evaluation->efficiencyMultiplier[componentIndex] = 1.0;
		evaluation->feedbackApplied[componentIndex] = 0;
	}
	evaluation->surgeMarginMultiplier = 1.0;

	if (!control->clearanceEnable || !control->clearanceFeedbackEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		diagnostics->offendingStepInIndex = -1;
		diagnostics->offendingValue = 0.0;
		return SHT_STATUS_OK;
	}

	if (SHT_IsClearanceComponentSelected(control, 0))
	{
		evaluation->flowMultiplier[0] = 1.0 +
			exchangeRate[0] * evaluation->dynamicClearance[0];
		evaluation->efficiencyMultiplier[0] = 1.0 +
			exchangeRate[1] * evaluation->dynamicClearance[0];
		evaluation->surgeMarginMultiplier = 1.0 +
			kSMHPC * evaluation->dynamicClearance[0];
		evaluation->feedbackApplied[0] = 1;

		if (!SHT_IsFinite(evaluation->flowMultiplier[0]) ||
			evaluation->flowMultiplier[0] <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_FEEDBACK, SHT_INPUT_K_CLEARANCE_W_HPC,
				evaluation->flowMultiplier[0]);
		if (!SHT_IsFinite(evaluation->efficiencyMultiplier[0]) ||
			evaluation->efficiencyMultiplier[0] <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_FEEDBACK, SHT_INPUT_K_CLEARANCE_ETA_HPC,
				evaluation->efficiencyMultiplier[0]);
		if (!SHT_IsFinite(evaluation->surgeMarginMultiplier) ||
			evaluation->surgeMarginMultiplier <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_FEEDBACK, 433,
				evaluation->surgeMarginMultiplier);
	}

	if (SHT_IsClearanceComponentSelected(control, 1))
	{
		evaluation->efficiencyMultiplier[1] = 1.0 +
			exchangeRate[2] * evaluation->dynamicClearance[1];
		evaluation->feedbackApplied[1] = 1;
		if (!SHT_IsFinite(evaluation->efficiencyMultiplier[1]) ||
			evaluation->efficiencyMultiplier[1] <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_FEEDBACK, SHT_INPUT_K_CLEARANCE_ETA_GT,
				evaluation->efficiencyMultiplier[1]);
	}

	if (SHT_IsClearanceComponentSelected(control, 2))
	{
		evaluation->efficiencyMultiplier[2] = 1.0 +
			exchangeRate[3] * evaluation->dynamicClearance[2];
		evaluation->feedbackApplied[2] = 1;
		if (!SHT_IsFinite(evaluation->efficiencyMultiplier[2]) ||
			evaluation->efficiencyMultiplier[2] <= 0.0)
			return SHT_SetClearanceEvaluationError(diagnostics,
				SHT_ERROR_CLEARANCE_FEEDBACK, SHT_INPUT_K_CLEARANCE_ETA_PT,
				evaluation->efficiencyMultiplier[2]);
	}

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->evaluationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

/*
 * P3/P4 共用的单部件热状态核。componentIndex 顺序固定为
 * HPC/Burner/GT/PT；本函数只写该部件对应的节点，不清除其他部件结果。
 */
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
	static const int nodeStart[SHT_HEAT_COMPONENT_COUNT] = { 0, 3, 4, 7 };
	static const int nodeCount[SHT_HEAT_COMPONENT_COUNT] = { 3, 1, 3, 3 };
	int firstNode;
	int localIndex;
	double representativeGasTemperature;
	double viscosityCurrent;
	double viscosityReference;
	double rniStar;

	if (control == 0 || state == 0 || parameters == 0 ||
		evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;
	if (componentIndex < 0 || componentIndex >= SHT_HEAT_COMPONENT_COUNT)
		return SHT_SetEvaluationError(diagnostics, -1, (double)componentIndex);

	evaluation->componentHeatFlow[componentIndex] = 0.0;
	if (!control->heatStateEnable ||
		!SHT_IsHeatComponentSelected(control, componentIndex))
		return SHT_STATUS_OK;

	if (!SHT_IsFinite(componentFlow) || componentFlow <= 0.0 ||
		!SHT_IsFinite(inletTemperature) || inletTemperature <= 0.0 ||
		!SHT_IsFinite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_SetEvaluationError(diagnostics, -1, componentFlow);

	firstNode = nodeStart[componentIndex];
	for (localIndex = 0; localIndex < nodeCount[componentIndex]; ++localIndex)
	{
		int nodeIndex = firstNode + localIndex;
		double beta = parameters->beta[nodeIndex];
		evaluation->gasTemperature[nodeIndex] =
			(1.0 - beta) * inletTemperature + beta * outletTemperature;
		if (!SHT_IsFinite(evaluation->gasTemperature[nodeIndex]) ||
			evaluation->gasTemperature[nodeIndex] <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				370 + nodeIndex, evaluation->gasTemperature[nodeIndex]);
	}

	representativeGasTemperature = evaluation->gasTemperature[firstNode];
	if (componentIndex == 0)
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
	if (!SHT_IsFinite(rniStar) || rniStar <= 0.0)
		return SHT_SetEvaluationError(diagnostics,
			383 + componentIndex, rniStar);
	evaluation->componentRNIStar[componentIndex] = rniStar;

	for (localIndex = 0; localIndex < nodeCount[componentIndex]; ++localIndex)
	{
		int nodeIndex = firstNode + localIndex;
		double timeConstant = parameters->tau0[nodeIndex] *
			(1.0 + heatTimeCorrection) / pow(rniStar, 0.8);
		double heatConductance;
		double temperatureDifference;

		if (!SHT_IsFinite(timeConstant) || timeConstant <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				350 + nodeIndex, timeConstant);
		heatConductance = parameters->heatCapacity0[nodeIndex] / timeConstant;
		temperatureDifference = evaluation->gasTemperature[nodeIndex] -
			state->metalTemperature[nodeIndex];

		evaluation->timeConstant[nodeIndex] = timeConstant;
		evaluation->heatConductance[nodeIndex] = heatConductance;
		evaluation->heatFlow[nodeIndex] = heatConductance * temperatureDifference;
		evaluation->componentHeatFlow[componentIndex] +=
			evaluation->heatFlow[nodeIndex];
		evaluation->metalTemperatureDerivative[nodeIndex] =
			temperatureDifference / timeConstant;

		if (!SHT_IsFinite(evaluation->heatFlow[nodeIndex]) ||
			!SHT_IsFinite(evaluation->metalTemperatureDerivative[nodeIndex]))
			return SHT_SetEvaluationError(diagnostics,
				300 + nodeIndex,
				evaluation->metalTemperatureDerivative[nodeIndex]);
	}

	return SHT_STATUS_OK;
}

/*
 * P3 热状态核：给定当前温度状态和已经求得的气路进出口量，只计算热流与
 * 状态导数。该函数不调用部件模型、不写输入状态，也不推进仿真时间。
 */
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
	static const int diskComponent[SHT_DISK_NODE_COUNT] = { 0, 2, 3 };
	static const int diskRootNode[SHT_DISK_NODE_COUNT] = { 1, 5, 8 };
	int componentIndex;
	int diskIndex;

	if (control == 0 || state == 0 || parameters == 0 ||
		componentFlow == 0 || inletTemperature == 0 ||
		outletTemperature == 0 || heatTimeCorrection == 0 ||
		diskTimeCorrection == 0 || evaluation == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;

	SHT_ResetHeatEvaluation(evaluation);
	if (!control->heatStateEnable)
	{
		diagnostics->errorCode = SHT_STATUS_OK;
		diagnostics->evaluationValid = 1;
		return SHT_STATUS_OK;
	}

	for (componentIndex = 0;
		componentIndex < SHT_HEAT_COMPONENT_COUNT;
		++componentIndex)
	{
		int status = SHT_EvaluateHeatComponent(
			control,
			state,
			parameters,
			componentIndex,
			componentFlow[componentIndex],
			inletTemperature[componentIndex],
			outletTemperature[componentIndex],
			heatTimeCorrection[componentIndex],
			evaluation,
			diagnostics);
		if (status != SHT_STATUS_OK)
			return status;
	}

	for (diskIndex = 0; diskIndex < SHT_DISK_NODE_COUNT; ++diskIndex)
	{
		int componentIndexForDisk = diskComponent[diskIndex];
		double diskTimeConstant;

		if (!SHT_IsHeatComponentSelected(control, componentIndexForDisk))
			continue;

		diskTimeConstant = parameters->diskTau0[diskIndex] *
			(1.0 + diskTimeCorrection[diskIndex]);
		if (!SHT_IsFinite(diskTimeConstant) || diskTimeConstant <= 0.0)
			return SHT_SetEvaluationError(diagnostics,
				380 + diskIndex, diskTimeConstant);

		evaluation->diskTimeConstant[diskIndex] = diskTimeConstant;
		evaluation->diskTemperatureDerivative[diskIndex] =
			(state->metalTemperature[diskRootNode[diskIndex]] -
			 state->diskTemperature[diskIndex]) / diskTimeConstant;
		if (!SHT_IsFinite(evaluation->diskTemperatureDerivative[diskIndex]))
			return SHT_SetEvaluationError(diagnostics,
				310 + diskIndex,
				evaluation->diskTemperatureDerivative[diskIndex]);
	}

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
	if (control != 0)
		memset(control, 0, sizeof(*control));
	if (state != 0)
		memset(state, 0, sizeof(*state));
	if (parameters != 0)
		memset(parameters, 0, sizeof(*parameters));
	if (diagnostics != 0)
	{
		memset(diagnostics, 0, sizeof(*diagnostics));
		diagnostics->offendingStepInIndex = -1;
	}
}

int SHT_ParseTransientInput(
	const double *stepIn,
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics)
{
	static const int interfaceTargets[] = { 0, 2502 };
	static const int modeTargets[] = { 0, 1, 2, 3 };
	static const int binaryTargets[] = { 0, 1 };
	static const int maskTargets[] = {
		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
	};
	static const int hpcStateIndices[] = { 300, 301, 302 };
	static const int burnerStateIndices[] = { 303 };
	static const int gtStateIndices[] = { 304, 305, 306 };
	static const int ptStateIndices[] = { 307, 308, 309 };
	int status;
	int i;

	if (stepIn == 0 || control == 0 || state == 0 ||
		parameters == 0 || diagnostics == 0)
		return SHT_ERROR_NULL_POINTER;

	SHT_ResetTransientData(control, state, parameters, diagnostics);

	status = SHT_DecodeDiscrete(stepIn[SHT_INPUT_INTERFACE_VERSION],
		interfaceTargets, 2, SHT_INPUT_INTERFACE_VERSION,
		&control->interfaceVersion, diagnostics);
	if (status != SHT_STATUS_OK)
		return SHT_SetError(diagnostics, SHT_ERROR_INTERFACE_VERSION,
			SHT_INPUT_INTERFACE_VERSION, stepIn[SHT_INPUT_INTERFACE_VERSION]);

	/*
	 * 基准接口的核心兼容规则：版本 0 只读取 stepIn[340]，不读取也不校验
	 * [300:339]、[341:511]。旧 M/SLX 调用方因此无需知道任何新增字段。
	 */
	if (control->interfaceVersion == SHT_TRANSIENT_INTERFACE_BASELINE)
	{
		diagnostics->configurationValid = 1;
		return SHT_STATUS_OK;
	}

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

	diagnostics->hpcSelected = (control->componentMask & SHT_COMPONENT_HPC) != 0;
	diagnostics->burnerSelected = (control->componentMask & SHT_COMPONENT_BURNER) != 0;
	diagnostics->gtSelected = (control->componentMask & SHT_COMPONENT_GT) != 0;
	diagnostics->ptSelected = (control->componentMask & SHT_COMPONENT_PT) != 0;
	if (control->thermalModelMode == 2 || control->thermalModelMode == 3)
		return SHT_SetError(diagnostics, SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED,
			341, stepIn[341]);

	status = SHT_CheckReservedRange(stepIn, 348, 349, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 391, 399, diagnostics);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_CheckReservedRange(stepIn, 438, 511, diagnostics);
	if (status != SHT_STATUS_OK) return status;

	if (control->heatFeedbackEnable && !control->heatStateEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY, 344, stepIn[344]);
	if (control->clearanceEnable && !control->heatStateEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY, 345, stepIn[345]);
	if (control->clearanceFeedbackEnable && !control->clearanceEnable)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY, 346, stepIn[346]);
	if ((control->heatStateEnable || control->clearanceEnable) &&
		control->thermalModelMode != 1)
		return SHT_SetError(diagnostics, SHT_ERROR_SWITCH_DEPENDENCY, 341, stepIn[341]);

	for (i = 0; i < 10; ++i)
	{
		state->metalTemperature[i] = stepIn[300 + i];
		parameters->tau0[i] = stepIn[350 + i];
		parameters->heatCapacity0[i] = stepIn[360 + i];
		parameters->beta[i] = stepIn[370 + i];
	}
	for (i = 0; i < 3; ++i)
	{
		state->diskTemperature[i] = stepIn[310 + i];
		parameters->diskTau0[i] = stepIn[380 + i];
		parameters->epsilonSS[i] = stepIn[430 + i];
	}
	for (i = 0; i < 4; ++i)
	{
		parameters->referenceFlow[i] = stepIn[383 + i];
		parameters->referenceGasTemperature[i] = stepIn[387 + i];
	}
	for (i = 0; i < 30; ++i)
		parameters->clearanceParameter[i] = stepIn[400 + i];
	parameters->kSMHPC = stepIn[433];
	for (i = 0; i < 4; ++i)
		parameters->nominalClearanceExchangeRate[i] =
			stepIn[SHT_INPUT_NOMINAL_CLEARANCE_RATE_START + i];

	if (control->inertiaEnable)
	{
		status = SHT_CheckCorrectionFactor(stepIn[SHT_INPUT_K_JG],
			SHT_INPUT_K_JG, diagnostics);
		if (status != SHT_STATUS_OK) return status;
		status = SHT_CheckCorrectionFactor(stepIn[SHT_INPUT_K_JP],
			SHT_INPUT_K_JP, diagnostics);
		if (status != SHT_STATUS_OK) return status;
	}

	if (control->heatStateEnable)
	{
		if (diagnostics->hpcSelected)
		{
			status = SHT_ValidateHeatComponent(stepIn, hpcStateIndices, 3,
				350, 3, 360, 370, 383, 387, SHT_INPUT_K_TAU_HPC,
				310, 380, SHT_INPUT_K_TAU_DISK_HPC, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->burnerSelected)
		{
			status = SHT_ValidateHeatComponent(stepIn, burnerStateIndices, 1,
				353, 1, 363, 373, 384, 388, SHT_INPUT_K_TAU_BURNER,
				-1, -1, -1, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->gtSelected)
		{
			status = SHT_ValidateHeatComponent(stepIn, gtStateIndices, 3,
				354, 3, 364, 374, 385, 389, SHT_INPUT_K_TAU_GT,
				311, 381, SHT_INPUT_K_TAU_DISK_GT, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->ptSelected)
		{
			status = SHT_ValidateHeatComponent(stepIn, ptStateIndices, 3,
				357, 3, 367, 377, 386, 390, SHT_INPUT_K_TAU_PT,
				312, 382, SHT_INPUT_K_TAU_DISK_PT, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
	}

	if (control->clearanceEnable)
	{
		if (diagnostics->hpcSelected)
		{
			status = SHT_ValidateClearanceComponent(stepIn, 400, 430,
				SHT_INPUT_K_CLEARANCE_W_HPC,
				SHT_INPUT_NOMINAL_CLEARANCE_RATE_START,
				control->clearanceFeedbackEnable ? 2 : 0,
				control->clearanceFeedbackEnable, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->gtSelected)
		{
			status = SHT_ValidateClearanceComponent(stepIn, 410, 431,
				SHT_INPUT_K_CLEARANCE_ETA_GT,
				SHT_INPUT_NOMINAL_CLEARANCE_RATE_START + 2,
				control->clearanceFeedbackEnable ? 1 : 0,
				0, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
		if (diagnostics->ptSelected)
		{
			status = SHT_ValidateClearanceComponent(stepIn, 420, 432,
				SHT_INPUT_K_CLEARANCE_ETA_PT,
				SHT_INPUT_NOMINAL_CLEARANCE_RATE_START + 3,
				control->clearanceFeedbackEnable ? 1 : 0,
				0, diagnostics);
			if (status != SHT_STATUS_OK) return status;
		}
	}

	diagnostics->errorCode = SHT_STATUS_OK;
	diagnostics->configurationValid = 1;
	diagnostics->offendingStepInIndex = -1;
	diagnostics->offendingValue = 0.0;
	return SHT_STATUS_OK;
}

