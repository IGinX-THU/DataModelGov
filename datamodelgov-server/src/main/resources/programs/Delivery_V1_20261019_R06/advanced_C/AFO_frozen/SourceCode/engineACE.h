#ifndef ENGINE_ACE_H
#define ENGINE_ACE_H

#include "blockAndFunctions.h"

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
	double varStartInput[11];   //¸ú»»Î¬¶È
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

int engineACEInitial(EngineACE *eng);
int engineACESetIdes(EngineACE *eng, double iDes);
int engineACEFree(EngineACE *eng);
int engineACELink(EngineACE *eng);
int engineACECalculate(EngineACE *eng, int runMode);
int engineACEOutPutHead(EngineACE *eng, FILE *fOut);
int engineACEOutPutResult(EngineACE *eng, FILE *fOut);
int engineACERunSteadyComponents(double *varIn, double *errOut, int dime);
int engineACERunTransientComponents(double *varIn, double *errOut, int dime);

//------------------------------------------------------------------------------
#endif  /* ENGINEMIXEDFAN */
#pragma once
