#ifndef ENGINE_MIXEDFAN_H
#define ENGINE_MIXEDFAN_H

#include "blockAndFunctions.h"

//------------------------------------------------------------------------------
struct EngineMixedFan {
  char   *engineName;
  int    offDesignMode;
  double altitude;
  double machNumber;
  double dTemperature;
  double TtBurnerOut;
  double timeTotal;
  double timeStep;
  int    timeVecDim;
  double *timeVec;
  double *farVec;

  AmbientBlock    Ambient;
  InletBlock      Inlet;
  CompressorBlock Fan;
  SplitterBlock   Splitter;
  DuctBlock       Duct1;
  CompressorBlock HPC;
  BurnBlock       Burner;
  TurbineBlock    HPT;
  DuctBlock       Duct2;
  TurbineBlock    LPT;
  DuctBlock       Duct3;
  DuctBlock       Duct4;
  MixerBlock      Mixer;
  BurnBlock       Afterburner;		// 20230913+, liukai
  DuctBlock       Duct5;
  NozzleBlock     Nozzle;
  ShaftBlock      LPS;
  ShaftBlock      HPS;

  double fuelFlow;
  double fuelFlowA;		// 20230913+, liukai
  double LPS_Trq;
  double HPS_Trq;
  double LPS_Power;
  double HPS_Power;
  double betaFVABI;
  double betaRVABI;

  int    convergeTag;
  double accuracyReq;
  double distuFactor;
  int    maxIterations;
  int    varVecDime;
  double varStartInput[9];   //璺熸崲缁村害
  double varStartStore[9];
  double varMin[9];
  double varMax[9];
  double varDelLim[9];

  double inletMassFlow;
  double Fan_Rline;
  double SplitterBPR;
  double HPC_Rline;
//  double BurnerFarIter;		// liukai
  double HPT_PRin;
  double LPT_PRin;
  double MixerPs;			// liukai
  double LPS_Nmech;
  double HPS_Nmech;

  double farUse;  //
  double errBurner;
  double fuelFlowInput;
  double fuelFlowAInput;

  int isInitial;
  int isDesOk;
  int isDynamic;
  double isDynamicCalculating;
  double timeNow;

  double hlthparas[50];
  double varIte[9];
  double errOut[9];
	char * filePath;
  double InletOutTt;	//T1
  double InletOutPt;	//P1
  double AmbientPs;		//P0
};
typedef struct EngineMixedFan EngineMixedFan;

struct EnginePointer {
	EngineMixedFan * eng;
};
typedef struct EnginePointer EnginePointer;

//------------------------------------------------------------------------------
struct EngineACE {
	char   *engineName;
	int    offDesignMode;
	double altitude;
	double machNumber;
	double dTemperature;
	double TtBurnerOut;
	double timeTotal;
	double timeStep;
	int    timeVecDim;
	double *timeVec;
	double *farVec;

	AmbientBlock    Ambient;
	InletBlock      Inlet;
	CompressorBlock FFan;
	SplitterBlock   SplitterF;
	FVABIBlock		FVABI;
	DuctBlock       DuctBypass2;
	NozzleBlock     NozzleBypass;
	DuctBlock       Duct22_23;
	CompressorBlock RFan;
	SplitterBlock   SplitterR;
	DuctBlock       Duct24_25;
	CompressorBlock HPC;
	BurnBlock       Burner;
	TurbineBlock    HPT;
	DuctBlock       Duct45;
	TurbineBlock    LPT;
	DuctBlock       Duct49_5;
	DuctBlock       DuctBypass1;
	MixerBlock      Mixer;
	BurnBlock       Afterburner;		// 20230913+, liukai
	DuctBlock       Duct7_8;
	NozzleBlock     Nozzle;
	ShaftBlock      LPS;
	ShaftBlock      HPS;

	double fuelFlow;
	double fuelFlowA;		// 20230913+, liukai
	double LPS_Trq;
	double HPS_Trq;
	double LPS_Power;
	double HPS_Power;
	double betaFVABI;
	double betaRVABI;

	int    convergeTag;
	double accuracyReq;
	double distuFactor;
	int    maxIterations;
	int    varVecDime;
	double varStartInput[11];   //璺熸崲缁村害
	double varStartStore[11];
	double varMin[11];
	double varMax[11];
	double varDelLim[11];

	double inletMassFlow;
	double FFan_Rline;
	double SplitterBPRF;
	double RFan_Rline;
	double SplitterBPRR;
	double HPC_Rline;
	//  double BurnerFarIter;		// liukai
	double HPT_PRin;
	double LPT_PRin;
	double MixerPs;			// liukai
	double LPS_Nmech;
	double HPS_Nmech;

	double farUse;  //
	double fuelFlowInput;
	double fuelFlowAInput;

	int isInitial;
	int isDesOk;
	int isDynamic;
	double isDynamicCalculating;
	double timeNow;

	double hlthparas[20];
	double varIte[11];
	double errOut[11];
    char * filePath;
};
typedef struct EngineACE EngineACE;

struct EngineACEPointer {
	EngineACE * eng;
};
typedef struct EngineACEPointer EngineACEPointer;
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
#define SHT_STEP_IN_LENGTH 512
#define SHT_STEP_OUT_LENGTH 128
#define SHT_LOW_SPEED_SOLVER_CONFIG_VERSION 26082503
#define SHT_LOW_SPEED_SOLVER_CONFIG_COUNT 13
#define SHT_LOW_SPEED_DIAGNOSTIC_COUNT 97
#define SHT_START_STOP_CONFIG_VERSION 26082401
#define SHT_START_STOP_CONFIG_COUNT 29
#define SHT_START_STOP_PHYSICS_INPUT_COUNT 12
#define SHT_START_STOP_PHYSICS_OUTPUT_COUNT 24

/* MATLAB stepIn(8): 0=PT/GT功率W，1=Mkp/Mkg外部扭矩N*m。
 * 模式1的stepIn(6:7)在DLL内部随当前候选转速换算，不改变结构体ABI。
 */
#define SHT_SHAFT_LOAD_MODE_INDEX 7
#define SHT_PT_LOAD_INPUT_INDEX 5
#define SHT_GT_LOAD_INPUT_INDEX 6
#define SHT_SHAFT_LOAD_POWER 0
#define SHT_SHAFT_LOAD_TORQUE 1

/* stepIn[40:198] <=> h0:h158; keep the legacy 100-value field in place. */
#define SHT_HEALTH_INPUT_OFFSET 40
#define SHT_HEALTH_BASE_COUNT 100
#define SHT_HEALTH_EXTENDED_COUNT 59
#define SHT_HEALTH_TOTAL_COUNT \
  (SHT_HEALTH_BASE_COUNT + SHT_HEALTH_EXTENDED_COUNT)

/* 六部件稳态修正系数调度轴与表类型。 */
#define SHT_HEALTH_AXIS_INLET_CORRECTED_FLOW 1
#define SHT_HEALTH_AXIS_BURNER_CORRECTED_FLOW 2
#define SHT_HEALTH_AXIS_GT_PT_DUCT_CORRECTED_FLOW 3
#define SHT_HEALTH_AXIS_PT_NOZZLE_DUCT_CORRECTED_FLOW 4
#define SHT_HEALTH_AXIS_AC_CORRECTED_SPEED 5
#define SHT_HEALTH_AXIS_CC_CORRECTED_SPEED 6
#define SHT_HEALTH_AXIS_GT_TOTAL_PRESSURE_RATIO 7
#define SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO 8
#define SHT_HEALTH_SCHEDULE_KIND_LINEAR 1
/* 旧ABI兼容定义；当前六部件真值资产不使用低流量门控表。 */
#define SHT_HEALTH_SCHEDULE_KIND_LOSS_WITH_LINEAR_GATE 2

/*
 * RunOnePoint/RunOneStep external-air input: stepIn[199] must be 10; stream
 * data start at stepIn[200]. Each stream is [W,h,Tt,Pt,FAR]. Legacy numbering
 * is not public.
 */
#define SHT_EXTERNAL_BLEED_COUNT_INDEX 199
#define SHT_EXTERNAL_BLEED_OFFSET 200
#define SHT_HEALTH_SCHEDULE_ENABLE_INDEX 17
#define SHT_EXTERNAL_BLEED_COUNT 10
#define SHT_EXTERNAL_BLEED_STATE_WIDTH 5
#define SHT_EXTERNAL_BLEED_CC_GT1_INLET 0
#define SHT_EXTERNAL_BLEED_CC_GT1_EXIT 1
#define SHT_EXTERNAL_BLEED_CC_GT2_INLET 2
#define SHT_EXTERNAL_BLEED_CC_GT2_EXIT 3
#define SHT_EXTERNAL_BLEED_AC_PT1_INLET 4
#define SHT_EXTERNAL_BLEED_AC_PT1_EXIT 5
#define SHT_EXTERNAL_BLEED_AC_PT2_INLET 6
#define SHT_EXTERNAL_BLEED_AC_PT2_EXIT 7
#define SHT_EXTERNAL_BLEED_CC_PT2_EXIT 8
#define SHT_EXTERNAL_BLEED_AC_LEAK 9

#define SHT_THERMAL_MODEL_KURZKE 1
#define SHT_THERMAL_MODEL_VISSER 3
#define SHT_THERMAL_CONFIG_VERSION_KURZKE_1 250301
#define SHT_THERMAL_CONFIG_KURZKE_PARAMETER_COUNT 147
#define SHT_THERMAL_CONFIG_VERSION_VISSER_1 250303
#define SHT_THERMAL_CONFIG_VISSER_PARAMETER_COUNT 178
#define SHT_COOLING_SPLIT_VERSION_1 250304
#define SHT_COOLING_SPLIT_PARAMETER_COUNT 19

/* 2.5 瞬态效应统一配置结构；字段顺序必须与 C 端完全一致。 */
typedef struct SHTTransientControl {
  /* 内部参数布局：0=未启用，2502=三部件，2503=六部件；不由stepIn选拓扑。 */
  int interfaceVersion;
  int modelMode;
  int thermalModelMode;
  int inertiaEnable;
  int heatStateEnable;
  int heatFeedbackEnable;
  int clearanceEnable;
  int clearanceFeedbackEnable;
  int componentMask;
  int metalNodeCount;
  int diskNodeCount;
  int guideVaneNodeCount;
  int heatComponentCount;
  int clearanceComponentCount;
} SHTTransientControl;

typedef struct SHTTransientState {
  double metalTemperature[19];
  double diskTemperature[6];
  double guideVaneTemperature[2];
} SHTTransientState;

typedef struct SHTTransientParameters {
  double tau0[19];
  double heatCapacity0[19];
  double beta[19];
  double diskTau0[6];
  double referenceFlow[7];
  double referenceGasTemperature[7];
  double clearanceParameter[60];
  double epsilonSS[6];
  double kSM[2];
  double nominalClearanceExchangeRate[8];
  double inertiaCorrection[2];
  double heatTimeCorrection[7];
  double diskTimeCorrection[6];
  double clearanceRateCorrection[8];
  double effectiveClearanceExchangeRate[8];
  double visserMetalHeatCapacity[21];
  double visserHotGasConductance0[21];
  double visserHotGasBeta[21];
  double visserDiskHeatCapacity[6];
  double visserRootDiskConductance0[6];
  double visserCoolingConductance0[19];
} SHTTransientParameters;

typedef struct SHTTransientDiagnostics {
  int errorCode;
  int configurationValid;
  int evaluationValid;
  int offendingStepInIndex;
  double offendingValue;
  int hpcSelected;
  int burnerSelected;
  int gtSelected;
  int ptSelected;
  int heatFeedbackApplied[7];
  int heatFeedbackConverged[7];
  int heatFeedbackIterationCount[7];
  double heatFeedbackIterationResidual[7];
  double heatFeedbackEnergyResidual[7];
} SHTTransientDiagnostics;

/* P3：当前调用的热状态纯求值结果。C 端不保存积分历史。 */
typedef struct SHTTransientHeatEvaluation {
  double gasTemperature[19];
  double componentRNIStar[7];
  double timeConstant[19];
  double heatConductance[19];
  double heatFlow[19];
  double componentHeatFlow[7];
  double metalTemperatureDerivative[19];
  double diskTimeConstant[6];
  double diskTemperatureDerivative[6];
  double guideVaneTemperatureDerivative[2];
  double visserGuideVaneGasTemperature[2];
  double visserGuideVaneHeatFlow[2];
  double visserMainGasHeatFlow[7];
  double visserMainGasFrontHeatFlow[7];
  double visserMainGasRearHeatFlow[7];
  double visserMetalCoolingHeatFlow[21];
  double visserDiskCoolingHeatFlow[6];
  double visserRootDiskHeatFlow[6];
  double visserCoolingBranchHeatFlow[19];
  double visserCoolingInletTemperature[10];
  double visserCoolingOutletTemperature[10];
  double visserEnergyResidual;
  double visserNormalizedEnergyResidual;
} SHTTransientHeatEvaluation;

/* P5：最大六旋转部件拓扑的归一化间隙及本次局部部件调用倍率。 */
typedef struct SHTTransientClearanceEvaluation {
  double normalizedSpeed[6];
  double actualClearance[6];
  double steadyClearance[6];
  double dynamicClearance[6];
  double flowMultiplier[6];
  double efficiencyMultiplier[6];
  double surgeMarginMultiplier[2];
  int feedbackApplied[6];
} SHTTransientClearanceEvaluation;

struct EngineTurboshaft {
  char   *engineName;
  int    offDesignMode;
  int    modelMode;          /* 0: original model; 1: six-component split model */
  double altitude;
  double machNumber;
  double dTemperature;
  double TtBurnerOut;
  double timeTotal;
  double timeStep;
  int    timeVecDim;
  double *timeVec;
  double *farVec;

  AmbientBlock    Ambient;
  InletBlock      Inlet;
  CompressorBlock HPC;
  CompressorBlock HPC2;
  BurnBlock       Burner;
  TurbineBlock    HPT;
  TurbineBlock    HPT2;
  DuctBlock       Duct2;
  TurbineBlock    LPT;
  TurbineBlock    LPT2;
  DuctBlock       Duct3;
  NozzleBlock     Nozzle;
  ShaftBlock      LPS;
  ShaftBlock      HPS;

  double fuelFlow;
  double LPS_Trq;
  double HPS_Trq;
  double LPS_Power;
  double HPS_Power;

  int    convergeTag;
  double accuracyReq;
  double distuFactor;
  int    maxIterations;
  int    varVecDime;
  double varStartInput[9];   /* mode 0 uses 6 variables; mode 1 uses 9 variables */
  double varStartStore[9];
  double varMin[9];
  double varMax[9];
  double varDelLim[9];

  double inletMassFlow;
  double HPC_Rline;
  double HPC2_Rline;
  double HPT_PRin;
  double HPT2_PRin;
  double LPT_PRin;
  double LPT2_PRin;
  double LPS_Nmech;
  double HPS_Nmech;

  double farUse;  //
  double errBurner;
  double fuelFlowInput;
  double fuelFlowAInput;

  int isInitial;
  int isDesOk;
  int isDynamic;
  double isDynamicCalculating;
  double timeNow;

  double hlthparas[100];
  double varIte[9];
  double errOut[9];
  char * filePath;
  double InletOutTt;	//T1
  double InletOutPt;	//P1
  double AmbientPs;		//P0
  double InletInTt;		//Tt1: inlet entrance total temperature
  double InletInPt;		//Pt1: inlet entrance total pressure
  double useInletBoundaryInput;	//SHTInletBoundaryMode 0..4; kept as double for ABI compatibility
  SHTTransientControl transientControl;
  SHTTransientState transientState;
  SHTTransientParameters transientParameters;
  SHTTransientDiagnostics transientDiagnostics;
  SHTTransientHeatEvaluation transientHeatEvaluation;
  SHTTransientClearanceEvaluation transientClearanceEvaluation;
  double hlthparasExtended[SHT_HEALTH_EXTENDED_COUNT];
};
typedef struct EngineTurboshaft EngineTurboshaft;

struct EngineSHTPointer {
	EngineTurboshaft * eng;
};
typedef struct EngineSHTPointer EngineSHTPointer;
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
 int DLLInitial();
 int DLLRunOnePoint(double * stepIn, double * stepOut, EnginePointer *engptr);
 int DLLRunOneStep(double * stepIn, double * stepOut, EnginePointer *engptr);
 int DLLFree();
 int DLLRunTransientComponents(double * stepIn, double * stepOut, EnginePointer *engptr);
 int DLLRunSteadyComponents(double * stepIn, double * stepOut, EnginePointer *engptr);
 int DLLvarIteInit(double * stepIn, double * stepOut, EnginePointer *engptr);
 int DLLConditionsInit(double * stepIn, double * stepOut, EnginePointer *engptr);
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
 int DLL_ACEInitial();
 int DLL_ACERunOnePoint(double * stepIn, double * stepOut, EngineACEPointer *engptr);
 int DLL_ACERunOneStep(double * stepIn, double * stepOut, EngineACEPointer *engptr);
 int DLL_ACEFree();
 int DLL_ACERunTransientComponents(double * stepIn, double * stepOut, EngineACEPointer *engptr);
 int DLL_ACERunSteadyComponents(double * stepIn, double * stepOut, EngineACEPointer *engptr);
 int DLL_ACEvarIteInit(double * stepIn, double * stepOut, EngineACEPointer *engptr);
 int DLL_ACEConditionsInit(double * stepIn, double * stepOut, EngineACEPointer *engptr);
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
 int DLL_SHT_Initial();
 int DLL_SHT_InitialMode(int modelMode);
 int DLL_SHT_InitializeReynoldsCorrection(
   int version, int parameterCount, double *parameterVector);
 int DLL_SHT_ReynoldsCorrectionGetStatus(void);
 int DLL_SHT_InitializeThermalConfig(
   int thermalModelMode, int configVersion, int parameterCount,
   double *parameterVector);
 int DLL_SHT_ThermalConfigGetStatus(int thermalModelMode);
 int DLL_SHT_InitializeCoolingSplit(
   int version, int parameterCount, double *ratio);
 int DLL_SHT_CoolingSplitGetStatus(void);
 int DLL_SHT_RunOnePoint(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_RunOneStep(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_RunStartStopStep(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_LowSpeedSolverConfigure(
   int version, int parameterCount, double *parameterVector);
 int DLL_SHT_LowSpeedSolverGetDiagnostics(double *output, int outputLength);
 int DLL_SHT_StartStopConfigure(
   int version, int parameterCount, double *parameterVector);
 int DLL_SHT_StartStopReset(
   double ngRpm, double npRpm, double rotorEquivalentRpm,
   int freewheelEngaged);
 int DLL_SHT_StartStopPhysicsStep(
   double *inputVector, int inputCount,
   double *outputVector, int outputCount);
 int DLL_SHT_FullModeSetLoad(int version, int count, double *values);
 int DLL_SHT_FullModeExportState(int version, int count, double *values);
 int DLL_SHT_FullModeImportState(int version, int count, double *values);
 int DLL_SHT_Free();
 int DLL_SHT_RunTransientComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_RunSteadyComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_varIteInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_ConditionsInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_HealthScheduleReset();
 int DLL_SHT_HealthScheduleConfigureTable(
   int healthIndex, int axisType, int nodeCount,
   double *xNode, double *deltaNode);
 int DLL_SHT_HealthScheduleSetEnabled(int enabled);
 int DLL_SHT_HealthScheduleGetConfiguredCount();
 int DLL_SHT_HealthScheduleEvaluateIncrement(
   int healthIndex, double coordinate, double *incrementValue);
//------------------------------------------------------------------------------
#endif  

