#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include "engineTurboshaft.h"
#include "functions_TMATS.h"
#include "newtonSolver.h"
#include "constants_TMATS.h"

EngineTurboshaft Turboshaft;

#define SHT_HEAT_FEEDBACK_MAX_ITERATIONS 50
#define SHT_HEAT_FEEDBACK_TEMPERATURE_TOL 1.0e-9

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
	double currentSpeed[SHT_CLEARANCE_COMPONENT_COUNT];
	double designSpeed[SHT_CLEARANCE_COMPONENT_COUNT];
	double exchangeRate[4];
	int status;

	currentSpeed[0] = Turboshaft.HPS_Nmech;
	currentSpeed[1] = Turboshaft.HPS_Nmech;
	currentSpeed[2] = Turboshaft.LPS_Nmech;
	designSpeed[0] = Turboshaft.HPT.turbineStruct.NDes;
	designSpeed[1] = Turboshaft.HPT.turbineStruct.NDes;
	designSpeed[2] = Turboshaft.LPT.turbineStruct.NDes;

	/*
	 * 标称间隙-性能灵敏度属于固定模型参数；hlthparas[64:67] 只表示
	 * 围绕标称值的无量纲相对修正。零修正保留标称间隙物理效应。
	 */
	exchangeRate[0] = Turboshaft.transientParameters
		.nominalClearanceExchangeRate[0] * (1.0 + Turboshaft.hlthparas[64]);
	exchangeRate[1] = Turboshaft.transientParameters
		.nominalClearanceExchangeRate[1] * (1.0 + Turboshaft.hlthparas[65]);
	exchangeRate[2] = Turboshaft.transientParameters
		.nominalClearanceExchangeRate[2] * (1.0 + Turboshaft.hlthparas[66]);
	exchangeRate[3] = Turboshaft.transientParameters
		.nominalClearanceExchangeRate[3] * (1.0 + Turboshaft.hlthparas[67]);

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
		exchangeRate,
		Turboshaft.transientParameters.kSMHPC,
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
static int SHT_EvaluateLocalHeat(
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	double *totalHeatFlow)
{
	SHTTransientHeatEvaluation localEvaluation;
	int status;

	SHT_ResetHeatEvaluation(&localEvaluation);
	status = SHT_EvaluateHeatComponent(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		componentIndex,
		componentFlow,
		inletTemperature,
		outletTemperature,
		heatTimeCorrection,
		&localEvaluation,
		&Turboshaft.transientDiagnostics);
	if (status == SHT_STATUS_OK)
		*totalHeatFlow = localEvaluation.componentHeatFlow[componentIndex];
	return status;
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
static int SHT_RunTransientBurner(BurnBlock *burner)
{
	const int componentIndex = 1;
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
			inletTemperature, outletTemperature, Turboshaft.hlthparas[61],
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
		inletTemperature, outletTemperature, Turboshaft.hlthparas[61],
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
static int SHT_RunClearanceAdjustedCompressorCore(CompressorBlock *compressor)
{
	CompressorBlock compressorWork;
	double effectiveFractionalBleedsDemand[500];
	double zeroBleedFlowHealth[500];
	double effectiveHpW;
	double effectiveHpEf;
	double inletFlow;
	double totalExternalBleedFlow = 0.0;
	int fractionalBleedCount;
	int useClearanceFeedback;
	int useExternalBleedFlow;
	int i;
	int status;

	useClearanceFeedback = SHT_IsClearanceFeedbackSelected(0);
	useExternalBleedFlow = Turboshaft.HPT.extSecAirSys > 0.5;
	if (!useClearanceFeedback && !useExternalBleedFlow)
		return compressorRun(compressor);

	compressorWork = *compressor;
	if (useClearanceFeedback)
	{
		effectiveHpW = (1.0 + *compressor->hpW) *
			Turboshaft.transientClearanceEvaluation.flowMultiplier[0] - 1.0;
		effectiveHpEf = (1.0 + *compressor->hpEf) *
			Turboshaft.transientClearanceEvaluation.efficiencyMultiplier[0] - 1.0;
		compressorWork.hpW = &effectiveHpW;
		compressorWork.hpEf = &effectiveHpEf;
	}

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

		compressorWork.fractionalBleedsDemand =
			effectiveFractionalBleedsDemand;
		compressorWork.hpWbld = zeroBleedFlowHealth;
	}

	status = compressorRun(&compressorWork);
	if (status == SHT_STATUS_OK)
	{
		compressorWork.hpW = compressor->hpW;
		compressorWork.hpEf = compressor->hpEf;
		compressorWork.fractionalBleedsDemand =
			compressor->fractionalBleedsDemand;
		compressorWork.hpWbld = compressor->hpWbld;
		*compressor = compressorWork;
	}
	return status;
}

/*
 * HPC：先求含间隙倍率的原特性图结果，再按 Kurzke 非绝热压缩关系求
 * 实际出口温度，并同步主流、分数引气焓以及轴功率。
 */
static int SHT_RunTransientCompressor(CompressorBlock *compressor)
{
	const int componentIndex = 0;
	int status = SHT_RunClearanceAdjustedCompressorCore(compressor);
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

	if (status != 0 || !SHT_IsHeatFeedbackSelected(SHT_COMPONENT_HPC))
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
		!_finite(pressureRatio) || pressureRatio <= 1.0 ||
		!_finite(adiabaticSpecificWork) || adiabaticSpecificWork <= 0.0)
		return SHT_SetHeatFeedbackFailure(componentIndex, 0,
			adiabaticSpecificWork, SHT_STATUS_OK);

	adiabaticExponent = log(adiabaticTemperature / inletTemperature) /
		log(pressureRatio);
	outletTemperature = adiabaticTemperature;
	for (iteration = 1; iteration <= SHT_HEAT_FEEDBACK_MAX_ITERATIONS; ++iteration)
	{
		status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
			inletTemperature, outletTemperature, Turboshaft.hlthparas[60],
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
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration - 1,
			residual, SHT_STATUS_OK);

	status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
		inletTemperature, outletTemperature, Turboshaft.hlthparas[60],
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
 * GT/PT 间隙反馈同样使用局部浅副本；首轮只修正效率，不改涡轮流量。
 * clearanceComponentIndex 顺序固定为 GT=1、PT=2。
 */
static int SHT_RunClearanceAdjustedTurbineCore(
	TurbineBlock *turbine,
	int clearanceComponentIndex)
{
	TurbineBlock turbineWork;
	double effectiveHpEf;
	int status;

	if (!SHT_IsClearanceFeedbackSelected(clearanceComponentIndex))
		return turbineRun(turbine);

	turbineWork = *turbine;
	effectiveHpEf = (1.0 + *turbine->hpEf) *
		Turboshaft.transientClearanceEvaluation
			.efficiencyMultiplier[clearanceComponentIndex] - 1.0;
	turbineWork.hpEf = &effectiveHpEf;
	status = turbineRun(&turbineWork);
	if (status == SHT_STATUS_OK)
	{
		turbineWork.hpEf = turbine->hpEf;
		*turbine = turbineWork;
	}
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
	double heatTimeCorrection)
{
	int clearanceComponentIndex = componentIndex == 2 ? 1 : 2;
	int status = SHT_RunClearanceAdjustedTurbineCore(
		turbine, clearanceComponentIndex);
	int iteration;
	int converged = 0;
	double inletFlow;
	double inletTemperature;
	double stageOneFlow;
	double stageOneFAR;
	double stageOneEnthalpy;
	double rearCoolingEnthalpyFlow;
	double outletFlow;
	double outletFAR;
	double stageOnePressure;
	double outletPressure;
	double efficiency;
	double outletTemperature;
	double nextTemperature = 0.0;
	double totalHeatFlow = 0.0;
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
	if (status != SHT_STATUS_OK || inletFlow <= 0.0 || stageOneFlow <= 0.0 ||
		outletFlow <= 0.0 || stageOnePressure <= 0.0 || outletPressure <= 0.0 ||
		efficiency <= 0.0 || !_finite(outletTemperature) || outletTemperature <= 0.0)
		return SHT_SetHeatFeedbackFailure(componentIndex, 0,
			outletTemperature, status);

	for (iteration = 1; iteration <= SHT_HEAT_FEEDBACK_MAX_ITERATIONS; ++iteration)
	{
		status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
			inletTemperature, outletTemperature, heatTimeCorrection,
			&totalHeatFlow);
		if (status != SHT_STATUS_OK)
			return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
				residual, status);
		/* 热流严格为零时保持原涡轮输出及冷却掺混结果逐位不变。 */
		if (totalHeatFlow == 0.0)
		{
			SHT_RecordHeatFeedbackSuccess(componentIndex, iteration, 0.0, 0.0);
			return SHT_STATUS_OK;
		}

		stageOneEffectiveEnthalpy = stageOneEnthalpy -
			totalHeatFlow / (2.0 * stageOneFlow);
		stageOneEffectiveTemperature = h2tc(stageOneEffectiveEnthalpy, stageOneFAR);
		entropy = pt2sc(stageOnePressure, stageOneEffectiveTemperature, stageOneFAR);
		idealOutletTemperature = sp2tc(entropy, outletPressure, stageOneFAR);
		idealOutletEnthalpy = t2hc(idealOutletTemperature, stageOneFAR);
		turbineSpecificWork = efficiency *
			(stageOneEffectiveEnthalpy - idealOutletEnthalpy);
		stageTwoEnthalpy = stageOneEffectiveEnthalpy - turbineSpecificWork -
			totalHeatFlow / (2.0 * stageOneFlow);
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

	status = SHT_EvaluateLocalHeat(componentIndex, inletFlow,
		inletTemperature, outletTemperature, heatTimeCorrection,
		&totalHeatFlow);
	if (status != SHT_STATUS_OK)
		return SHT_SetHeatFeedbackFailure(componentIndex, iteration,
			residual, status);
	stageOneEffectiveEnthalpy = stageOneEnthalpy -
		totalHeatFlow / (2.0 * stageOneFlow);
	stageOneEffectiveTemperature = h2tc(stageOneEffectiveEnthalpy, stageOneFAR);
	entropy = pt2sc(stageOnePressure, stageOneEffectiveTemperature, stageOneFAR);
	idealOutletTemperature = sp2tc(entropy, outletPressure, stageOneFAR);
	idealOutletEnthalpy = t2hc(idealOutletTemperature, stageOneFAR);
	turbineSpecificWork = efficiency *
		(stageOneEffectiveEnthalpy - idealOutletEnthalpy);
	stageTwoEnthalpy = stageOneEffectiveEnthalpy - turbineSpecificWork -
		totalHeatFlow / (2.0 * stageOneFlow);
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
static int SHT_EvaluateCurrentHeatState(void)
{
	double componentFlow[SHT_HEAT_COMPONENT_COUNT];
	double inletTemperature[SHT_HEAT_COMPONENT_COUNT];
	double outletTemperature[SHT_HEAT_COMPONENT_COUNT];
	double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT];
	double diskTimeCorrection[SHT_DISK_NODE_COUNT];

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

	heatTimeCorrection[0] = Turboshaft.hlthparas[60];
	heatTimeCorrection[1] = Turboshaft.hlthparas[61];
	heatTimeCorrection[2] = Turboshaft.hlthparas[62];
	heatTimeCorrection[3] = Turboshaft.hlthparas[63];
	diskTimeCorrection[0] = Turboshaft.hlthparas[68];
	diskTimeCorrection[1] = Turboshaft.hlthparas[69];
	diskTimeCorrection[2] = Turboshaft.hlthparas[70];

	return SHT_EvaluateHeatStates(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		componentFlow,
		inletTemperature,
		outletTemperature,
		heatTimeCorrection,
		diskTimeCorrection,
		&Turboshaft.transientHeatEvaluation,
		&Turboshaft.transientDiagnostics);
}

static void SHT_WriteHeatStateDerivatives(
	double *stepOut,
	int metalStartIndex,
	int diskStartIndex)
{
	int i;
	for (i = 0; i < SHT_METAL_NODE_COUNT; ++i)
		stepOut[metalStartIndex + i] =
			Turboshaft.transientHeatEvaluation.metalTemperatureDerivative[i];
	for (i = 0; i < SHT_DISK_NODE_COUNT; ++i)
		stepOut[diskStartIndex + i] =
			Turboshaft.transientHeatEvaluation.diskTemperatureDerivative[i];
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
	if (Turboshaft.transientControl.interfaceVersion == SHT_TRANSIENT_INTERFACE_2502)
		stepOut[validIndex] = valid ? 1.0 : 0.0;
}
//------------------------------------------------------------------------------
int engineTurboshaftInitial(EngineTurboshaft *eng)
{
  int i = 0;
  FILE * fModel;
  char * filename = "Turboshaft-TS.mdl";		// 20230911+, liukai
  char pathName[1000];
  char name[100];
 
  eng->engineName = NULL;
  eng->timeVec = NULL;
  eng->farVec = NULL;
  eng->timeVecDim = 0;
  //eng->noFlow =NULL;      //
  //eng->noFlowWidth = 0;   //

  if (eng->filePath != NULL)
  {
	  i = strlen(pathName);
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
	  return 0;
  }
  fscanf(fModel,"%*[^=]=%s",name);
  i = strlen(name) + 1;  //加1为了存储最后的\0
  eng->engineName = (char*)calloc(i,sizeof(char));
  strcpy(eng->engineName,name);

  if (eng->filePath != NULL)
  {
	  i = strlen(pathName);
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

  fscanf(fModel,"%*[^=]=%s",name);
  burnInitial(&eng->Burner,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->HPT,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct2,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->LPT,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct3,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  nozzleInitial(&eng->Nozzle,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->LPS,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->HPS,fModel,name);
  
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
	}
	else          //3-按照输入文件中的参数配置各部件的IDes
	{
		eng->HPC.compressorStruct.IDes = eng->HPC.IDesInput;
		eng->HPT.turbineStruct.IDes = eng->HPT.IDesInput;
		eng->LPT.turbineStruct.IDes = eng->LPT.IDesInput;
		eng->Nozzle.nozzleStruct.IDes = eng->Nozzle.IDesInput;
	}
	return 0;
}
//------------------------------------------------------------------------------
int engineTurboshaftFree(EngineTurboshaft *eng)
{
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
  burnFree(&eng->Burner);
  turbineFree(&eng->HPT);
  ductFree(&eng->Duct2);
  turbineFree(&eng->LPT);
  ductFree(&eng->Duct3);
  nozzleFree(&eng->Nozzle);
  shaftFree(&eng->LPS);
  shaftFree(&eng->HPS);

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
  eng->HPC.hpBldPRec = &(eng->hlthparas[16]);
  eng->HPC.hpWbld = &(eng->hlthparas[16+(int)(eng->HPC.compressorStruct.FracBldNm)]);
  eng->HPC.hpBldht = &(eng->hlthparas[16 + (int)(eng->HPC.compressorStruct.FracBldNm * 2)]);

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
  eng->Nozzle.pAmbIn = &eng->Ambient.y[4];
  eng->Nozzle.afterFVABI = 0.0;
  eng->Nozzle.hpA8 = &(eng->hlthparas[15]);
  //jrt,20241106
  eng->Nozzle.hpA9 = (double*)calloc(1, sizeof(double));
  return 0;
}

//------------------------------------------------------------------------------
static void SHT_ReadInletBoundaryInput(double *stepIn)
{
	Turboshaft.InletInPt = stepIn[13];
	Turboshaft.InletInTt = stepIn[14];
	Turboshaft.AmbientPs = stepIn[15];
	Turboshaft.useInletBoundaryInput = stepIn[16];
}

//------------------------------------------------------------------------------
static void SHT_ApplyInletBoundaryInput()
{
	if (Turboshaft.useInletBoundaryInput < 0.5)
		return;

	// Pt1/Tt1 are inlet-entrance total pressure/temperature. They must be
	// applied before inletRun so Inlet.hpdP_Loss remains effective.
	if (Turboshaft.InletInPt > 0.0)
	{
		Turboshaft.Ambient.gasPathOut[3] = Turboshaft.InletInPt;
		Turboshaft.Ambient.y[2] = Turboshaft.InletInPt;
	}
	if (Turboshaft.InletInTt > 0.0)
	{
		Turboshaft.Ambient.gasPathOut[2] = Turboshaft.InletInTt;
		Turboshaft.Ambient.y[1] = Turboshaft.InletInTt;
	}
	if (Turboshaft.AmbientPs > 0.0)
	{
		Turboshaft.Ambient.y[4] = Turboshaft.AmbientPs;
	}
}
//------------------------------------------------------------------------------
int TurboshaftRunSteadyComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
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

	ambientRun(&Turboshaft.Ambient);
	SHT_ApplyInletBoundaryInput();
	inletRun(&Turboshaft.Inlet);

	compressorRun(&Turboshaft.HPC);
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	burnRun(&Turboshaft.Burner);
	turbineRun(&Turboshaft.HPT);
	ductRun(&Turboshaft.Duct2);
	turbineRun(&Turboshaft.LPT);
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
	for (i = 0; i < dime; i++)
	{
		Turboshaft.varIte[i] = varIn[i];
		Turboshaft.errOut[i] = 1;
	}
	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];

	ambientRun(&Turboshaft.Ambient);
	SHT_ApplyInletBoundaryInput();
	inletRun(&Turboshaft.Inlet);
	status = SHT_RunTransientCompressor(&Turboshaft.HPC);
	if (status != SHT_STATUS_OK) return status;
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_RunTransientBurner(&Turboshaft.Burner);
	if (status != SHT_STATUS_OK) return status;
	status = SHT_RunTransientTurbine(&Turboshaft.HPT, 2,
		SHT_COMPONENT_GT, Turboshaft.hlthparas[62]);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunTransientTurbine(&Turboshaft.LPT, 3,
		SHT_COMPONENT_PT, Turboshaft.hlthparas[63]);
	if (status != SHT_STATUS_OK) return status;
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.LPS, Turboshaft.hlthparas[59]);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.HPS, Turboshaft.hlthparas[58]);

	Turboshaft.errOut[0] = Turboshaft.HPC.y[6];      //HPC_NErr
	Turboshaft.errOut[1] = Turboshaft.HPT.y[6];      //HPT_NErr
	Turboshaft.errOut[2] = Turboshaft.LPT.y[6];      //LPT_NErr
	Turboshaft.errOut[3] = Turboshaft.Nozzle.y[2];   //Nozzle_Nerr
	for (i = 0; i < dime; i++)
	{
		errOut[i] = Turboshaft.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_Initial()
{
	int i = 0;
	Turboshaft.isInitial = 0;
	Turboshaft.isDesOk = 0;
	Turboshaft.timeNow = 0;
	Turboshaft.convergeTag = 1;
	Turboshaft.InletInPt = 0;
	Turboshaft.InletInTt = 0;
	Turboshaft.AmbientPs = 0;
	Turboshaft.useInletBoundaryInput = 0;
	SHT_ResetTransientData(
		&Turboshaft.transientControl,
		&Turboshaft.transientState,
		&Turboshaft.transientParameters,
		&Turboshaft.transientDiagnostics);
	SHT_ResetHeatEvaluation(&Turboshaft.transientHeatEvaluation);
	SHT_ResetClearanceEvaluation(&Turboshaft.transientClearanceEvaluation);
//	engineTurboshaftLink(&Turboshaft);
	engineTurboshaftInitial(&Turboshaft);
	engineTurboshaftLink(&Turboshaft);
	engineTurboshaftSetIdes(&Turboshaft, Turboshaft.offDesignMode);

	for (i = 0; i < Turboshaft.varVecDime; i++)
	{
		Turboshaft.varStartStore[i] = Turboshaft.varStartInput[i];
	}
	for (i = 0; i < 100; i++)
	{
		Turboshaft.hlthparas[i] = 0;
	}
	Turboshaft.isDynamicCalculating = 0;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_Free()
{
	engineTurboshaftFree(&Turboshaft);
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
	Turboshaft.altitude = stepIn[10];
	Turboshaft.machNumber = stepIn[11];
	Turboshaft.dTemperature = stepIn[12];

	ambientRun(&Turboshaft.Ambient);

	engptr->eng = &Turboshaft;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunOnePoint(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
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

	SHT_ReadInletBoundaryInput(stepIn);
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	Turboshaft.LPS_Power = stepIn[5];
	Turboshaft.HPS_Power = stepIn[6];
	Turboshaft.HPC.alphaIn = stepIn[8];
	Turboshaft.HPT.extSecAirSys = 0;
	Turboshaft.LPT.extSecAirSys = 0;
	
	for (i = 0; i < 100; i++)// jrt,20241105
	{
		Turboshaft.hlthparas[i] = stepIn[i + 40];
	}

	Turboshaft.convergeTag = newtonSolver(TurboshaftRunSteadyComponents,
		Turboshaft.varVecDime,
		Turboshaft.varStartStore, Turboshaft.varMin, Turboshaft.varMax, Turboshaft.varDelLim,
		Turboshaft.accuracyReq,
		Turboshaft.distuFactor,
		Turboshaft.maxIterations);

	engptr->eng = &Turboshaft;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_SHT_RunOneStep(double * stepIn, double * stepOut, EngineSHTPointer *engptr)
{
	int i = 0;
	int status;
	int finiteLength;
	int varDime  = Turboshaft.varVecDime - 2;
	SHT_ClearStepOut(stepOut);
	status = SHT_PrepareTransientConfiguration(stepIn);
	if (status != SHT_STATUS_OK)
	{
		engptr->eng = &Turboshaft;
		return status;
	}
	
	SHT_ReadInletBoundaryInput(stepIn);
	Turboshaft.LPS_Nmech = stepIn[0];
	Turboshaft.HPS_Nmech = stepIn[1];
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	Turboshaft.LPS_Power = stepIn[5];
	Turboshaft.HPS_Power = stepIn[6];
	Turboshaft.HPC.alphaIn = stepIn[8];
	Turboshaft.HPT.extSecAirSys = stepIn[4];
	Turboshaft.LPT.extSecAirSys = stepIn[4];

	if (stepIn[4] > 0.5)
	{
		Turboshaft.HPC.customerBleeds[2500] = Turboshaft.HPC.fractionalBleeds[2500];
		for(i = 0; i < Turboshaft.HPC.customerBleeds[2500]; i++)
			Turboshaft.HPC.customerBleeds[i] = stepIn[200+i];
		status = SHT_ValidateExternalBleedInput(&Turboshaft.HPC);
		if (status != SHT_STATUS_OK)
		{
			engptr->eng = &Turboshaft;
			return status;
		}
	}

	for (i = 0; i < 100; i++)
	{
		Turboshaft.hlthparas[i] = stepIn[i + 40];
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
		SHT_WriteHeatStateDerivatives(stepOut, 2, 12);
	finiteLength = Turboshaft.transientControl.heatStateEnable ? 15 : 2;
	SHT_SetEvaluationValidity(stepOut, 15,
		Turboshaft.convergeTag == 0 &&
		SHT_IsFiniteVector(stepOut, finiteLength));
	engptr->eng = &Turboshaft;
	
	return 0;
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
	SHT_ReadInletBoundaryInput(stepIn);
	Turboshaft.LPS_Nmech = stepIn[0];
	Turboshaft.HPS_Nmech = stepIn[1];
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	Turboshaft.LPS_Power = stepIn[5];
	Turboshaft.HPS_Power = stepIn[6];
	Turboshaft.HPC.alphaIn = stepIn[8];
	Turboshaft.HPT.extSecAirSys = 0;
	Turboshaft.LPT.extSecAirSys = 0;

	for (i = 0; i < varDime; i++)
	{
		Turboshaft.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 100; i++)
	{
		Turboshaft.hlthparas[i] = stepIn[i + 40];
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
	SHT_ApplyInletBoundaryInput();
	inletRun(&Turboshaft.Inlet);
	status = SHT_RunTransientCompressor(&Turboshaft.HPC);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	status = SHT_RunTransientBurner(&Turboshaft.Burner);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	status = SHT_RunTransientTurbine(&Turboshaft.HPT, 2,
		SHT_COMPONENT_GT, Turboshaft.hlthparas[62]);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct2);
	status = SHT_RunTransientTurbine(&Turboshaft.LPT, 3,
		SHT_COMPONENT_PT, Turboshaft.hlthparas[63]);
	if (status != SHT_STATUS_OK)
	{
		SHT_ClearStepOut(stepOut);
		engptr->eng = &Turboshaft;
		return status;
	}
	ductRun(&Turboshaft.Duct3);
	nozzleRun(&Turboshaft.Nozzle);
	Turboshaft.LPS_Trq = Turboshaft.LPT.y[5] * Turboshaft.LPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.LPS, Turboshaft.hlthparas[59]);
	Turboshaft.HPS_Trq = Turboshaft.HPC.y[5] + Turboshaft.HPT.y[5] * Turboshaft.HPS.effMech;
	SHT_RunTransientShaft(&Turboshaft.HPS, Turboshaft.hlthparas[58]);

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
		SHT_WriteHeatStateDerivatives(stepOut, 16, 26);
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

	SHT_ReadInletBoundaryInput(stepIn);
	Turboshaft.fuelFlowInput = stepIn[2];
	Turboshaft.Nozzle.areaThroatIn = stepIn[3];
	Turboshaft.LPS_Power = stepIn[5];
	Turboshaft.HPS_Power = stepIn[6];
	Turboshaft.HPC.alphaIn = stepIn[8];
	Turboshaft.HPT.extSecAirSys = 0;
	Turboshaft.LPT.extSecAirSys = 0;

	for (i = 0; i < varDime; i++)
	{
		Turboshaft.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 100; i++)
	{
		Turboshaft.hlthparas[i] = stepIn[i + 40];
	}

	Turboshaft.inletMassFlow = Turboshaft.varIte[0];
	Turboshaft.HPC_Rline = Turboshaft.varIte[1];
	Turboshaft.HPT_PRin = Turboshaft.varIte[2];
	Turboshaft.LPT_PRin = Turboshaft.varIte[3];
	Turboshaft.LPS_Nmech = Turboshaft.varIte[4];
	Turboshaft.HPS_Nmech = Turboshaft.varIte[5];

	ambientRun(&Turboshaft.Ambient);
	SHT_ApplyInletBoundaryInput();
	inletRun(&Turboshaft.Inlet);
	compressorRun(&Turboshaft.HPC);
	Turboshaft.fuelFlow = Turboshaft.fuelFlowInput;
	burnRun(&Turboshaft.Burner);
	turbineRun(&Turboshaft.HPT);
	ductRun(&Turboshaft.Duct2);
	turbineRun(&Turboshaft.LPT);
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


