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

/* 2.5 瞬态效应统一配置结构；字段顺序必须与 C 端完全一致。 */
typedef struct SHTTransientControl {
  int interfaceVersion;
  int thermalModelMode;
  int inertiaEnable;
  int heatStateEnable;
  int heatFeedbackEnable;
  int clearanceEnable;
  int clearanceFeedbackEnable;
  int componentMask;
} SHTTransientControl;

typedef struct SHTTransientState {
  double metalTemperature[10];
  double diskTemperature[3];
} SHTTransientState;

typedef struct SHTTransientParameters {
  double tau0[10];
  double heatCapacity0[10];
  double beta[10];
  double diskTau0[3];
  double referenceFlow[4];
  double referenceGasTemperature[4];
  double clearanceParameter[30];
  double epsilonSS[3];
  double kSMHPC;
  double nominalClearanceExchangeRate[4];
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
  int heatFeedbackApplied[4];
  int heatFeedbackConverged[4];
  int heatFeedbackIterationCount[4];
  double heatFeedbackIterationResidual[4];
  double heatFeedbackEnergyResidual[4];
} SHTTransientDiagnostics;

/* P3：当前调用的热状态纯求值结果。C 端不保存积分历史。 */
typedef struct SHTTransientHeatEvaluation {
  double gasTemperature[10];
  double componentRNIStar[4];
  double timeConstant[10];
  double heatConductance[10];
  double heatFlow[10];
  double componentHeatFlow[4];
  double metalTemperatureDerivative[10];
  double diskTimeConstant[3];
  double diskTemperatureDerivative[3];
} SHTTransientHeatEvaluation;

/* P5：HPC、GT、PT 的归一化间隙及本次局部部件调用倍率。 */
typedef struct SHTTransientClearanceEvaluation {
  double normalizedSpeed[3];
  double actualClearance[3];
  double steadyClearance[3];
  double dynamicClearance[3];
  double flowMultiplier[3];
  double efficiencyMultiplier[3];
  double surgeMarginMultiplier;
  int feedbackApplied[3];
} SHTTransientClearanceEvaluation;

struct EngineTurboshaft {
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
  CompressorBlock HPC;
  BurnBlock       Burner;
  TurbineBlock    HPT;
  DuctBlock       Duct2;
  TurbineBlock    LPT;
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
  double varStartInput[6];   //璺熸崲缁村害
  double varStartStore[6];
  double varMin[6];
  double varMax[6];
  double varDelLim[6];

  double inletMassFlow;
  double HPC_Rline;
  double HPT_PRin;
  double LPT_PRin;
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
  double varIte[6];
  double errOut[6];
  char * filePath;
  double InletOutTt;	//T1
  double InletOutPt;	//P1
  double AmbientPs;		//P0
  double InletInTt;		//Tt1: inlet entrance total temperature
  double InletInPt;		//Pt1: inlet entrance total pressure
  double useInletBoundaryInput;	//0: use ambient model output; 1: use external Pt1/Tt1/Ps
  SHTTransientControl transientControl;
  SHTTransientState transientState;
  SHTTransientParameters transientParameters;
  SHTTransientDiagnostics transientDiagnostics;
  SHTTransientHeatEvaluation transientHeatEvaluation;
  SHTTransientClearanceEvaluation transientClearanceEvaluation;
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
 int DLL_SHT_RunOnePoint(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_RunOneStep(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_Free();
 int DLL_SHT_RunTransientComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_RunSteadyComponents(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_varIteInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
 int DLL_SHT_ConditionsInit(double * stepIn, double * stepOut, EngineSHTPointer *engptr);
//------------------------------------------------------------------------------
#endif  

