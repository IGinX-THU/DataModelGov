#ifndef ENGINE_UNMIXEDFAN_H
#define ENGINE_UNMIXEDFAN_H

#include "blockAndFunctions.h"

//------------------------------------------------------------------------------
struct EngineUnmixedFan {
  char   *engineName;
  int    offDesignMode;
  double InletGasPort[5];
  double pAmbInput;
  double farInput;
  double timeTotal;
  double timeStep;
  int    timeVecDim;
  double *timeVec;
  double *farVec;

  InletBlock      Inlet;
  CompressorBlock Fan;
  SplitterBlock   Splitter;
  DuctBlock       Duct1;
  CompressorBlock LPC;
  DuctBlock       Duct2;
  CompressorBlock HPC;
  BurnBlock       Burner;
  TurbineBlock    HPT;
  DuctBlock       Duct3;
  TurbineBlock    LPT;
  DuctBlock       Duct4;
  NozzleBlock     Noz_core;
  DuctBlock       Duct5;
  NozzleBlock     Noz_byp;
  ShaftBlock      LPS;
  ShaftBlock      HPS;

  double fuelFlow;
  double *noFlow;
  double noFlowWidth;
  double LPS_Trq;
  double HPS_Trq;
  double LPS_Power;
  double HPS_Power;

  int    convergeTag;
  double accuracyReq;
  double distuFactor;
  int    maxIterations;
  int    varVecDime;
  double varStartInput[9];
  double varStartStore[9];
  double *varIte[9];
  double varMin[9];
  double varMax[9];
  double varDelLim[9];
  double *errOut[9];

  //double InletMassFlow;  //直接从端口读，InletGasPort[0]
  double Fan_Rline;
  double SplitterBPR;
  double LPC_Rline;
  double HPC_Rline;
  double HPT_PRin;
  double LPT_PRin;
  double LPS_Nmech;
  double HPS_Nmech;

  double farUse;

  int isInitial;
  int isDesOk;
  int isDynamic;
  double isDynamicCalculating;
  double timeNow;
};
typedef struct EngineUnmixedFan EngineUnmixedFan;
//------------------------------------------------------------------------------
int engineUnmixedFanCalculate(EngineUnmixedFan *eng,int runMode);
//------------------------------------------------------------------------------
extern EngineUnmixedFan JT9D;
#endif  /* ENGINEUNMIXEDFAN */
