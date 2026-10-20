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
  double varStartInput[9];   //¸ú»»Î¬¶È
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

int engineMixedFanInitial(EngineMixedFan *eng);
int engineMixedFanSetIdes(EngineMixedFan *eng, double iDes);
int engineMixedFanFree(EngineMixedFan *eng);
int engineMixedFanLink(EngineMixedFan *eng);

//------------------------------------------------------------------------------
#endif  /* ENGINEMIXEDFAN */
