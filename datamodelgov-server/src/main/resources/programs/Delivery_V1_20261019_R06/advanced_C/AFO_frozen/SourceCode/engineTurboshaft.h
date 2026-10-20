#ifndef ENGINE_TURBOSHAFT_H
#define ENGINE_TURBOSHAFT_H

#include "blockAndFunctions.h"
#include "shtTransientEffects.h"

#define SHT_STEP_IN_LENGTH 512
#define SHT_STEP_OUT_LENGTH 128

//------------------------------------------------------------------------------
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
  double varStartInput[6];   //¸ú»»Î¬¶È
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

int engineTurboshaftInitial(EngineTurboshaft *eng);
int engineTurboshaftSetIdes(EngineTurboshaft *eng, double iDes);
int engineTurboshaftFree(EngineTurboshaft *eng);
int engineTurboshaftLink(EngineTurboshaft *eng);

//------------------------------------------------------------------------------
#endif  /* ENGINEMIXEDFAN */
