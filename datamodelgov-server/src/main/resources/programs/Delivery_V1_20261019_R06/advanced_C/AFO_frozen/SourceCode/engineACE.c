#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include "engineACE.h"
#include "newtonSolver.h"

EngineACE ACE;
//------------------------------------------------------------------------------
int engineACEInitial(EngineACE *eng)
{
	int i = 0;
	FILE *fModel;
	char *modelName = "MixedFan_ACE-VD.mdl";		// 20230911+, liukai
	char name[100];
	char pathName[1000];

	eng->engineName = NULL;
	eng->timeVec = NULL;
	eng->farVec = NULL;
	eng->timeVecDim = 0;

	fModel = fopen(modelName, "r");
	if (fModel == NULL)
	{
		return 0;
	}
	fscanf(fModel, "%*[^=]=%s", name);
	i = strlen(name) + 1;  //加1为了存储最后的\0
	eng->engineName = (char*)calloc(i, sizeof(char));
	strcpy(eng->engineName, name);

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

	fscanf(fModel, "%*[^=]=%d", &eng->offDesignMode);
	fscanf(fModel, "%*[^=]=%lf", &eng->altitude);
	fscanf(fModel, "%*[^=]=%lf", &eng->machNumber);
	fscanf(fModel, "%*[^=]=%lf", &eng->dTemperature);
	fscanf(fModel, "%*[^=]=%lf", &eng->TtBurnerOut);

	fscanf(fModel, "%*[^=]=%lf", &eng->LPS_Power);
	fscanf(fModel, "%*[^=]=%lf", &eng->HPS_Power);
	fscanf(fModel, "%*[^=]=%lf", &eng->timeTotal);
	fscanf(fModel, "%*[^=]=%lf", &eng->timeStep);
	fscanf(fModel, "%*[^=]=%d", &eng->timeVecDim);

	if (eng->timeVecDim > 0)
	{
		eng->timeVec = (double*)calloc(eng->timeVecDim, sizeof(double));
		fscanf(fModel, "%*[^=]=%lf", &eng->timeVec[0]);
	}
	for (i = 1; i < eng->timeVecDim; i++)
	{
		fscanf(fModel, "%lf", &eng->timeVec[i]);
	}
	if (eng->timeVecDim > 0)
	{
		eng->farVec = (double*)calloc(eng->timeVecDim, sizeof(double));
		fscanf(fModel, "%*[^=]=%lf", &eng->farVec[0]);
	}
	for (i = 1; i < eng->timeVecDim; i++)
	{
		fscanf(fModel, "%lf", &eng->farVec[i]);
	}
	fscanf(fModel, "%*[^=]=%lf", &eng->accuracyReq);
	fscanf(fModel, "%*[^=]=%lf", &eng->distuFactor);
	fscanf(fModel, "%*[^=]=%d", &eng->maxIterations);
	fscanf(fModel, "%*[^=]=%d", &eng->varVecDime);
	if (eng->varVecDime > 0)
	{	//内存定义在结构体内
		fscanf(fModel, "%*[^=]=%lf", &eng->varStartInput[0]);
	}
	for (i = 1; i < eng->varVecDime; i++)
	{
		fscanf(fModel, "%lf", &eng->varStartInput[i]);
	}
	if (eng->varVecDime > 0)
	{	//内存定义在结构体内
		fscanf(fModel, "%*[^=]=%lf", &eng->varMin[0]);
	}
	for (i = 1; i < eng->varVecDime; i++)
	{
		fscanf(fModel, "%lf", &eng->varMin[i]);
	}
	if (eng->varVecDime > 0)
	{	//内存定义在结构体内
		fscanf(fModel, "%*[^=]=%lf", &eng->varMax[0]);
	}
	for (i = 1; i < eng->varVecDime; i++)
	{
		fscanf(fModel, "%lf", &eng->varMax[i]);
	}
	if (eng->varVecDime > 0)
	{	//内存定义在结构体内
		fscanf(fModel, "%*[^=]=%lf", &eng->varDelLim[0]);
	}
	for (i = 1; i < eng->varVecDime; i++)
	{
		fscanf(fModel, "%lf", &eng->varDelLim[i]);
	}

	fscanf(fModel, "%*[^=]=%s", name);
	ambientInitial(&eng->Ambient, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	inletInitial(&eng->Inlet, fModel, name);
	// 前风扇
	fscanf(fModel, "%*[^=]=%s", name);
	compressorFInitial(&eng->FFan, fModel, name, pathName);

	fscanf(fModel, "%*[^=]=%s", name);
	splitterInitial(&eng->SplitterF, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	FVABIInitial(&eng->FVABI, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->DuctBypass2, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	nozzleInitial(&eng->NozzleBypass, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->Duct22_23, fModel, name);
	// 后风扇
	fscanf(fModel, "%*[^=]=%s", name);
	compressorFInitial(&eng->RFan, fModel, name, pathName);

	fscanf(fModel, "%*[^=]=%s", name);
	splitterInitial(&eng->SplitterR, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->Duct24_25, fModel, name);
	// HPC
	fscanf(fModel, "%*[^=]=%s", name);
	compressorInitial(&eng->HPC, fModel, name, pathName);

	fscanf(fModel, "%*[^=]=%s", name);
	burnInitial(&eng->Burner, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	turbineInitial(&eng->HPT, fModel, name, pathName);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->Duct45, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	turbineInitial(&eng->LPT, fModel, name, pathName);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->Duct49_5, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->DuctBypass1, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	mixerInitial(&eng->Mixer, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	burnInitial(&eng->Afterburner, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	ductInitial(&eng->Duct7_8, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	nozzleInitial(&eng->Nozzle, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	shaftInitial(&eng->LPS, fModel, name);

	fscanf(fModel, "%*[^=]=%s", name);
	shaftInitial(&eng->HPS, fModel, name);

	fclose(fModel);
	eng->isInitial = 1;
	return 0;
}
//------------------------------------------------------------------------------
int engineACESetIdes(EngineACE *eng, double iDes)
{
	if (iDes < 3)   //0-设计点；1-所有部件的iDes设为1；2-所有部件的iDes设为2
	{
		eng->FFan.compressorStruct.IDes = iDes;  //需要设置旋转部件、混合室和喷管的IDes
		eng->RFan.compressorStruct.IDes = iDes;
		eng->HPC.compressorStruct.IDes = iDes;
		eng->HPT.turbineStruct.IDes = iDes;
		eng->LPT.turbineStruct.IDes = iDes;
		//	eng->Mixer.mixerStruct.IDes = iDes;
		//	eng->Nozzle.nozzleStruct.IDes = iDes;
		//eng->Noz_byp.nozzleStruct.IDes = iDes;
	}
	else          //3-按照输入文件中的参数配置各部件的IDes
	{
		eng->FFan.compressorStruct.IDes = eng->FFan.IDesInput;
		eng->RFan.compressorStruct.IDes = eng->RFan.IDesInput;
		eng->HPC.compressorStruct.IDes = eng->HPC.IDesInput;
		eng->HPT.turbineStruct.IDes = eng->HPT.IDesInput;
		eng->LPT.turbineStruct.IDes = eng->LPT.IDesInput;
		eng->Mixer.mixerStruct.IDes = eng->Mixer.IDesInput;
		eng->Nozzle.nozzleStruct.IDes = eng->Nozzle.IDesInput;
		eng->NozzleBypass.nozzleStruct.IDes = eng->NozzleBypass.IDesInput;
	}
	return 0;
}
//------------------------------------------------------------------------------
int engineACEFree(EngineACE *eng)
{
	if (eng->engineName != NULL)
		free(eng->engineName);
	if (eng->timeVec != NULL)
		free(eng->timeVec);
	if (eng->farVec != NULL)
		free(eng->farVec);

	ambientFree(&eng->Ambient);
	inletFree(&eng->Inlet);
	compressorFree(&eng->FFan);
	splitterFree(&eng->SplitterF);
	ductFree(&eng->DuctBypass2);
	nozzleFree(&eng->NozzleBypass);
	ductFree(&eng->Duct22_23);
	compressorFree(&eng->RFan);
	splitterFree(&eng->SplitterR);
	ductFree(&eng->Duct24_25);
	compressorFree(&eng->HPC);
	burnFree(&eng->Burner);
	turbineFree(&eng->HPT);
	ductFree(&eng->Duct45);
	turbineFree(&eng->LPT);
	ductFree(&eng->Duct49_5);
	ductFree(&eng->DuctBypass1);
	mixerFree(&eng->Mixer);
	burnFree(&eng->Afterburner);
	ductFree(&eng->Duct7_8);
	nozzleFree(&eng->Nozzle);
	shaftFree(&eng->LPS);
	shaftFree(&eng->HPS);

	return 0;
}
//------------------------------------------------------------------------------
int engineACELink(EngineACE *eng)
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

	eng->FFan.gasPathIn = eng->Inlet.gasPathOut;
	eng->FFan.rLineIn = &eng->FFan_Rline;
	eng->FFan.nMech = eng->LPS.nMech;
	eng->FFan.BypassRatioIn = &eng->SplitterBPRF;
	eng->FFan.AFT = 0.0954;
	eng->FFan.hpAFT = 0;

	eng->SplitterF.gasPathIn = &eng->FFan.y[0];
	eng->SplitterF.BypassRatioIn = &eng->SplitterBPRF;

	eng->FVABI.gasPathIn = eng->SplitterF.gasPathOutBypass;
	eng->FVABI.beta = &(eng->betaFVABI);

	eng->DuctBypass2.gasPathIn = &(eng->FVABI.y[0]);

	eng->NozzleBypass.fDrag = (double*)calloc(1, sizeof(double));
	*eng->NozzleBypass.fDrag = 0;
	eng->NozzleBypass.gasPathIn = eng->DuctBypass2.gasPathOut;
	eng->NozzleBypass.pAmbIn = &eng->Ambient.y[4];
	eng->NozzleBypass.betaFVABI = &eng->betaFVABI;
	eng->NozzleBypass.afterFVABI = 1.0;
	eng->betaFVABI = 1.0;
	
	eng->Duct22_23.gasPathIn = eng->SplitterF.gasPathOutMain;

	eng->RFan.gasPathIn = eng->Duct22_23.gasPathOut;
	eng->RFan.rLineIn = &eng->RFan_Rline;
	eng->RFan.nMech = eng->LPS.nMech;
	eng->RFan.BypassRatioIn = &eng->SplitterBPRR;
	eng->RFan.AFT = 0.0954;
	eng->RFan.hpAFT = 0;

	eng->SplitterR.gasPathIn = &eng->RFan.y[0];
	eng->SplitterR.BypassRatioIn = &eng->SplitterBPRR;

	eng->Duct24_25.gasPathIn = eng->SplitterR.gasPathOutMain;
		
	eng->HPC.gasPathIn = eng->Duct24_25.gasPathOut;
	eng->HPC.rLineIn = &eng->HPC_Rline;
	eng->HPC.nMech = eng->HPS.nMech;
	eng->HPC.BypassRatioIn = &eng->SplitterBPRR;

	eng->Burner.fuelFlowIn = &eng->fuelFlow;
	eng->Burner.gasPathIn = &eng->HPC.y[0];

	eng->HPT.coolingFlow = eng->HPC.fractionalBleeds;
	eng->HPT.gasPathIn = &eng->Burner.y[0];
	eng->HPT.PressureRatioIn = &eng->HPT_PRin;
	eng->HPT.nMech = eng->HPS.nMech;

	eng->Duct45.gasPathIn = &eng->HPT.y[0];

	int N;
	N = eng->HPT.coolingFlowWidth;
	eng->LPT.coolingFlow = &eng->HPC.fractionalBleeds[N];
	eng->LPT.gasPathIn = eng->Duct45.gasPathOut;
	eng->LPT.PressureRatioIn = &eng->LPT_PRin;
	eng->LPT.nMech = eng->LPS.nMech;

	eng->Duct49_5.gasPathIn = &eng->LPT.y[0];

	eng->DuctBypass1.gasPathIn = eng->SplitterR.gasPathOutBypass;

	eng->Mixer.gasPathIn1 = eng->DuctBypass1.gasPathOut;		// 外涵道出口
	eng->Mixer.gasPathIn2 = eng->Duct49_5.gasPathOut;		// LPT出口
	eng->Mixer.MixerPs = &eng->MixerPs;
	eng->Mixer.isDynamicCalculating = &eng->isDynamicCalculating;
	eng->Mixer.betaRVABI = &eng->betaRVABI;

	eng->Afterburner.fuelFlowIn = &eng->fuelFlowA;
	eng->Afterburner.gasPathIn = &eng->Mixer.y[0];

	eng->Duct7_8.gasPathIn = &eng->Afterburner.y[0];

	eng->Nozzle.fDrag = &eng->Ambient.fDrag;
	eng->Nozzle.gasPathIn = eng->Duct7_8.gasPathOut;
	eng->Nozzle.pAmbIn = &eng->Ambient.y[4];
	eng->Nozzle.afterFVABI = 0.0;
	return 0;
}
//------------------------------------------------------------------------------
int engineACEOutPutHead(EngineACE *eng, FILE *fOut)
{
	//  if(eng->isDynamic == 1)
/*	fprintf(fOut, "time,");
	fprintf(fOut, "%s_altitude,", eng->engineName);
	fprintf(fOut, "%s_machNumber,", eng->engineName);
	fprintf(fOut, "%s_dTemperature,", eng->engineName);
	fprintf(fOut, "%s_TtBurnerOutInput,", eng->engineName);
	//fprintf(fOut,"%s_FarIn,",eng->engineName);       //
	//fprintf(fOut,"%s_pAmb,",eng->engineName);        //
	//fprintf(fOut,"%s_burnerFar,",eng->engineName);   //

	fprintf(fOut, "%s_varWin,", eng->engineName);
	fprintf(fOut, "%s_varFan_Rline,", eng->engineName);
	fprintf(fOut, "%s_varSplitterBPR,", eng->engineName);
	//fprintf(fOut,"%s_varLPC_Rline,",eng->engineName);
	fprintf(fOut, "%s_varHPC_Rline,", eng->engineName);
	fprintf(fOut, "%s_varBurnerFar,", eng->engineName);
	fprintf(fOut, "%s_varHPT_PRin,", eng->engineName);
	fprintf(fOut, "%s_varLPT_PRin,", eng->engineName);
	fprintf(fOut, "%s_varLPS_Nmech,", eng->engineName);
	fprintf(fOut, "%s_varHPS_Nmech,", eng->engineName);

	ambientOutPutHead(&eng->Ambient, fOut);
	inletOutPutHead(&eng->Inlet, fOut);
	compressorOutPutHead(&eng->Fan, fOut);
	splitterOutPutHead(&eng->Splitter, fOut);
	ductOutPutHead(&eng->Duct1, fOut);
	//compressorOutPutHead(&eng->LPC,fOut);
	//ductOutPutHead(&eng->Duct2,fOut);
	compressorOutPutHead(&eng->HPC, fOut);
	burnOutPutHead(&eng->Burner, fOut);
	turbineOutPutHead(&eng->HPT, fOut);
	ductOutPutHead(&eng->Duct2, fOut);
	turbineOutPutHead(&eng->LPT, fOut);
	ductOutPutHead(&eng->Duct3, fOut);
	ductOutPutHead(&eng->Duct4, fOut);
	mixerOutPutHead(&eng->Mixer, fOut);
	burnOutPutHead(&eng->Afterburner, fOut);
	ductOutPutHead(&eng->Duct5, fOut);
	nozzleOutPutHead(&eng->Nozzle, fOut);
	//ductOutPutHead(&eng->Duct5,fOut);
	//nozzleOutPutHead(&eng->Noz_byp,fOut);
	shaftOutPutHead(&eng->LPS, fOut);
	shaftOutPutHead(&eng->HPS, fOut);

	fprintf(fOut, "\n");*/
	return 0;
}
//------------------------------------------------------------------------------
int engineACEOutPutResult(EngineACE *eng, FILE *fOut)
{
	//  if(eng->isDynamic == 1)
/*	fprintf(fOut, "%lf,", eng->timeNow);
	fprintf(fOut, "%lf,", eng->altitude);
	fprintf(fOut, "%lf,", eng->machNumber);
	fprintf(fOut, "%lf,", eng->dTemperature);
	fprintf(fOut, "%lf,", eng->Burner.y[2]);
	//fprintf(fOut,"%lf,",eng->InletGasPort[4]);  //
	//fprintf(fOut,"%lf,",eng->pAmbInput);        //
	//fprintf(fOut,"%lf,",eng->farUse);           //

	fprintf(fOut, "%lf,", eng->inletMassFlow);
	fprintf(fOut, "%lf,", eng->Fan_Rline);
	fprintf(fOut, "%lf,", eng->SplitterBPR);
	//fprintf(fOut,"%lf,",eng->LPC_Rline);
	fprintf(fOut, "%lf,", eng->HPC_Rline);
	fprintf(fOut, "%lf,", eng->MixerPs);
	fprintf(fOut, "%lf,", eng->Afterburner.y[2]);
	fprintf(fOut, "%lf,", eng->HPT_PRin);
	fprintf(fOut, "%lf,", eng->LPT_PRin);
	fprintf(fOut, "%lf,", eng->LPS_Nmech);
	fprintf(fOut, "%lf,", eng->HPS_Nmech);

	ambientOutPutResult(&eng->Ambient, fOut);
	inletOutPutResult(&eng->Inlet, fOut);
	compressorOutPutResult(&eng->Fan, fOut);
	splitterOutPutResult(&eng->Splitter, fOut);
	ductOutPutResult(&eng->Duct1, fOut);
	//compressorOutPutResult(&eng->LPC,fOut);
	//ductOutPutResult(&eng->Duct2,fOut);
	compressorOutPutResult(&eng->HPC, fOut);
	burnOutPutResult(&eng->Burner, fOut);
	turbineOutPutResult(&eng->HPT, fOut);
	ductOutPutResult(&eng->Duct2, fOut);
	turbineOutPutResult(&eng->LPT, fOut);
	ductOutPutResult(&eng->Duct3, fOut);
	ductOutPutResult(&eng->Duct4, fOut);
	mixerOutPutResult(&eng->Mixer, fOut);
	burnOutPutResult(&eng->Afterburner, fOut);
	ductOutPutResult(&eng->Duct5, fOut);
	nozzleOutPutResult(&eng->Nozzle, fOut);
	//ductOutPutResult(&eng->Duct5,fOut);
	//nozzleOutPutResult(&eng->Noz_byp,fOut);
	shaftOutPutResult(&eng->LPS, fOut);
	shaftOutPutResult(&eng->HPS, fOut);

	fprintf(fOut, "\n");*/
	return 0;
}

//------------------------------------------------------------------------------
int engineACERunSteadyComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
	for (i = 0; i < dime; i++)
	{
		ACE.varIte[i] = varIn[i];
		ACE.errOut[i] = 1;
	}
	ACE.inletMassFlow = ACE.varIte[0];
	ACE.FFan_Rline = ACE.varIte[1];
	ACE.SplitterBPRF = ACE.varIte[2];
	ACE.RFan_Rline = ACE.varIte[3];
	ACE.SplitterBPRR = ACE.varIte[4];
	ACE.HPC_Rline = ACE.varIte[5];
	ACE.HPT_PRin = ACE.varIte[6];
	ACE.LPT_PRin = ACE.varIte[7];
	ACE.MixerPs = ACE.varIte[8];
	ACE.LPS_Nmech = ACE.varIte[9];
	ACE.HPS_Nmech = ACE.varIte[10];

	ambientRun(&ACE.Ambient);
	inletRun(&ACE.Inlet);
	ACE.FFan.hpW = &(ACE.hlthparas[0]);
	ACE.FFan.hpEf = &(ACE.hlthparas[1]);
	compressorFRun(&ACE.FFan);			// 前风扇
	splitterRun(&ACE.SplitterF);
	FVABIRun(&ACE.FVABI);
	ductRun(&ACE.DuctBypass2);
	ACE.NozzleBypass.hpA8 = &(ACE.hlthparas[13]);
	nozzleRun(&ACE.NozzleBypass);
	ductRun(&ACE.Duct22_23);
	ACE.RFan.hpW = &(ACE.hlthparas[2]);
	ACE.RFan.hpEf = &(ACE.hlthparas[3]);
	compressorFRun(&ACE.RFan);			// 后风扇
	splitterRun(&ACE.SplitterR);
	ductRun(&ACE.Duct24_25);
	ACE.HPC.hpW = &(ACE.hlthparas[4]);
	ACE.HPC.hpEf = &(ACE.hlthparas[5]);
	compressorRun(&ACE.HPC);			// HPC
	ACE.fuelFlow = ACE.fuelFlowInput;
	ACE.Burner.hpEf = &(ACE.hlthparas[10]);
	burnRun(&ACE.Burner);
	ACE.HPT.hpW = &(ACE.hlthparas[6]);
	ACE.HPT.hpEf = &(ACE.hlthparas[7]);
	turbineRun(&ACE.HPT);
	ductRun(&ACE.Duct45);
	ACE.LPT.hpW = &(ACE.hlthparas[8]);
	ACE.LPT.hpEf = &(ACE.hlthparas[9]);
	turbineRun(&ACE.LPT);
	ductRun(&ACE.Duct49_5);
	ductRun(&ACE.DuctBypass1);
	mixerRun(&ACE.Mixer);
	ACE.fuelFlowA = ACE.fuelFlowAInput;		// 20230913+, liukai
	ACE.Afterburner.hpEf = &(ACE.hlthparas[11]);
	burnRun(&ACE.Afterburner);
	ductRun(&ACE.Duct7_8);
	ACE.Nozzle.hpA8 = &(ACE.hlthparas[12]);
	nozzleRun(&ACE.Nozzle);
	ACE.LPS_Trq = ACE.FFan.y[5] + ACE.RFan.y[5] + ACE.LPT.y[5] * ACE.LPS.effMech;
	shaftRun(&ACE.LPS);
	ACE.HPS_Trq = ACE.HPC.y[5] + ACE.HPT.y[5] * ACE.HPS.effMech;
	shaftRun(&ACE.HPS);

	ACE.errOut[0] = ACE.FFan.y[6];      //Foward Fan_NErr
	ACE.errOut[1] = ACE.RFan.y[6];      //Rear Fan_NErr
	ACE.errOut[2] = ACE.HPC.y[6];      //HPC_NErr
	ACE.errOut[3] = ACE.HPT.y[6];      //HPT_NErr
	ACE.errOut[4] = ACE.LPT.y[6];      //LPT_NErr
	ACE.errOut[5] = ACE.Mixer.y[5];    //Mixer_NErr_W1
	ACE.errOut[6] = ACE.Mixer.y[8];	 //Mixer_NErr_W2
	ACE.errOut[7] = ACE.Nozzle.y[2];   //Nozzle_Nerr
	ACE.errOut[8] = ACE.NozzleBypass.y[2];   //Nozzle_Nerr
	ACE.errOut[9] = ACE.LPS.nDot / 10000.0;   //LPS_Nerr
	ACE.errOut[10] = ACE.HPS.nDot / 10000.0;   //HPS_Nerr
	for (i = 0; i < dime; i++)
	{
		errOut[i] = ACE.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
int engineACERunTransientComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
	for (i = 0; i < dime; i++)
	{
		ACE.varIte[i] = varIn[i];
		ACE.errOut[i] = 1;
	}
	ACE.inletMassFlow = ACE.varIte[0];
	ACE.FFan_Rline = ACE.varIte[1];
	ACE.SplitterBPRF = ACE.varIte[2];
	ACE.RFan_Rline = ACE.varIte[3];
	ACE.SplitterBPRR = ACE.varIte[4];
	ACE.HPC_Rline = ACE.varIte[5];
	ACE.HPT_PRin = ACE.varIte[6];
	ACE.LPT_PRin = ACE.varIte[7];
	ACE.MixerPs = ACE.varIte[8];

	ambientRun(&ACE.Ambient);
	inletRun(&ACE.Inlet);
	ACE.FFan.hpW = &(ACE.hlthparas[0]);
	ACE.FFan.hpEf = &(ACE.hlthparas[1]);
	compressorFRun(&ACE.FFan);			// 前风扇
	splitterRun(&ACE.SplitterF);
	FVABIRun(&ACE.FVABI);
	ductRun(&ACE.DuctBypass2);
	ACE.NozzleBypass.hpA8 = &(ACE.hlthparas[13]);
	nozzleRun(&ACE.NozzleBypass);
	ductRun(&ACE.Duct22_23);
	ACE.RFan.hpW = &(ACE.hlthparas[2]);
	ACE.RFan.hpEf = &(ACE.hlthparas[3]);
	compressorFRun(&ACE.RFan);			// 后风扇
	splitterRun(&ACE.SplitterR);
	ductRun(&ACE.Duct24_25);
	ACE.HPC.hpW = &(ACE.hlthparas[4]);
	ACE.HPC.hpEf = &(ACE.hlthparas[5]);
	compressorRun(&ACE.HPC);			// HPC
	ACE.fuelFlow = ACE.fuelFlowInput;
	ACE.Burner.hpEf = &(ACE.hlthparas[10]);
	burnRun(&ACE.Burner);
	ACE.HPT.hpW = &(ACE.hlthparas[6]);
	ACE.HPT.hpEf = &(ACE.hlthparas[7]);
	turbineRun(&ACE.HPT);
	ductRun(&ACE.Duct45);
	ACE.LPT.hpW = &(ACE.hlthparas[8]);
	ACE.LPT.hpEf = &(ACE.hlthparas[9]);
	turbineRun(&ACE.LPT);
	ductRun(&ACE.Duct49_5);
	ductRun(&ACE.DuctBypass1);
	mixerRun(&ACE.Mixer);
	ACE.fuelFlowA = ACE.fuelFlowAInput;		// 20230913+, liukai
	ACE.Afterburner.hpEf = &(ACE.hlthparas[11]);
	burnRun(&ACE.Afterburner);
	ductRun(&ACE.Duct7_8);
	ACE.Nozzle.hpA8 = &(ACE.hlthparas[12]);
	nozzleRun(&ACE.Nozzle);
	ACE.LPS_Trq = ACE.FFan.y[5] + ACE.RFan.y[5] + ACE.LPT.y[5] * ACE.LPS.effMech;
	shaftRun(&ACE.LPS);
	ACE.HPS_Trq = ACE.HPC.y[5] + ACE.HPT.y[5] * ACE.HPS.effMech;
	shaftRun(&ACE.HPS);

	ACE.errOut[0] = ACE.FFan.y[6];      //Foward Fan_NErr
	ACE.errOut[1] = ACE.RFan.y[6];      //Rear Fan_NErr
	ACE.errOut[2] = ACE.HPC.y[6];      //HPC_NErr
	ACE.errOut[3] = ACE.HPT.y[6];      //HPT_NErr
	ACE.errOut[4] = ACE.LPT.y[6];      //LPT_NErr
	ACE.errOut[5] = ACE.Mixer.y[5];    //Mixer_NErr_W1
	ACE.errOut[6] = ACE.Mixer.y[8];	 //Mixer_NErr_W2
	ACE.errOut[7] = ACE.Nozzle.y[2];   //Nozzle_Nerr
	ACE.errOut[8] = ACE.NozzleBypass.y[2];   //Nozzle_Nerr
	for (i = 0; i < dime; i++)
	{
		errOut[i] = ACE.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACEInitial()
{
	int i = 0;
	ACE.isInitial = 0;
	ACE.isDesOk = 0;
	ACE.timeNow = 0;
	ACE.convergeTag = 1;
	engineACELink(&ACE);
	engineACEInitial(&ACE);
	engineACELink(&ACE);
	engineACESetIdes(&ACE, ACE.offDesignMode);

	for (i = 0; i < ACE.varVecDime; i++)
	{
		ACE.varStartStore[i] = ACE.varStartInput[i];
	}
	for (i = 0; i < 20; i++)
	{
		ACE.hlthparas[i] = 0;
	}

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACEFree()
{
	engineACEFree(&ACE);
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACEvarIteInit(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	int i = 0;

	for (i = 0; i < ACE.varVecDime; i++)
	{
		ACE.varStartStore[i] = stepIn[i + 20];
	}

	engptr->eng = &ACE;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACEConditionsInit(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	ACE.altitude = stepIn[10];
	ACE.machNumber = stepIn[11];
	ACE.dTemperature = stepIn[12];

	engptr->eng = &ACE;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACERunOnePoint(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	int i = 0;
	int varDime = ACE.varVecDime;

	ACE.fuelFlowInput = stepIn[2];
	ACE.Nozzle.areaThroatIn = stepIn[3];
	ACE.isDynamicCalculating = stepIn[4];
	ACE.LPS_Power = stepIn[5];
	ACE.HPS_Power = stepIn[6];
	ACE.RFan.alphaIn = stepIn[7];
	ACE.HPC.alphaIn = stepIn[8];
	ACE.fuelFlowAInput = stepIn[9];
//	ACE.betaFVABI = stepIn[13];
	ACE.betaRVABI = stepIn[14];
	ACE.NozzleBypass.areaThroatIn = stepIn[15];

	for (i = 0; i < 13; i++)
	{
		ACE.hlthparas[i] = stepIn[i + 40];
	}

	ACE.convergeTag = newtonSolver(engineACERunSteadyComponents,
		varDime,
		ACE.varStartStore, ACE.varMin, ACE.varMax, ACE.varDelLim,
		ACE.accuracyReq,
		ACE.distuFactor,
		ACE.maxIterations);

	engptr->eng = &ACE;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACERunOneStep(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	int i = 0;
	int varDime = ACE.varVecDime - 2;

	ACE.LPS_Nmech = stepIn[0];
	ACE.HPS_Nmech = stepIn[1];
	ACE.fuelFlowInput = stepIn[2];
	ACE.Nozzle.areaThroatIn = stepIn[3];
	ACE.isDynamicCalculating = stepIn[4];
	ACE.LPS_Power = stepIn[5];
	ACE.HPS_Power = stepIn[6];
	ACE.RFan.alphaIn = stepIn[7];
	ACE.HPC.alphaIn = stepIn[8];
	ACE.fuelFlowAInput = stepIn[9];
//	ACE.betaFVABI = stepIn[13];
	ACE.betaRVABI = stepIn[14];
	ACE.NozzleBypass.areaThroatIn = stepIn[15];
	for (i = 0; i < 11; i++)
	{
		ACE.hlthparas[i] = stepIn[i + 40];
	}

	ACE.convergeTag = newtonSolver(engineACERunTransientComponents,
		varDime,
		ACE.varStartStore, ACE.varMin, ACE.varMax, ACE.varDelLim,
		ACE.accuracyReq,
		ACE.distuFactor,
		ACE.maxIterations);

	stepOut[0] = ACE.LPS.nDot;
	stepOut[1] = ACE.HPS.nDot;
	engptr->eng = &ACE;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACERunTransientComponents(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	int i = 0;
	int varDime = ACE.varVecDime - 2;

	ACE.LPS_Nmech = stepIn[0];
	ACE.HPS_Nmech = stepIn[1];
	ACE.fuelFlowInput = stepIn[2];
	ACE.Nozzle.areaThroatIn = stepIn[3];
	ACE.isDynamicCalculating = stepIn[4];
	ACE.LPS_Power = stepIn[5];
	ACE.HPS_Power = stepIn[6];
	ACE.RFan.alphaIn = stepIn[7];
	ACE.HPC.alphaIn = stepIn[8];
	ACE.fuelFlowAInput = stepIn[9];
//	ACE.betaFVABI = stepIn[13];
	ACE.betaRVABI = stepIn[14];
	ACE.NozzleBypass.areaThroatIn = stepIn[15];

	for (i = 0; i < varDime; i++)
	{
		ACE.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 13; i++)
	{
		ACE.hlthparas[i] = stepIn[i + 40];
	}

	ACE.inletMassFlow = ACE.varIte[0];
	ACE.FFan_Rline = ACE.varIte[1];
	ACE.SplitterBPRF = ACE.varIte[2];
	ACE.RFan_Rline = ACE.varIte[3];
	ACE.SplitterBPRR = ACE.varIte[4];
	ACE.HPC_Rline = ACE.varIte[5];
	ACE.HPT_PRin = ACE.varIte[6];
	ACE.LPT_PRin = ACE.varIte[7];
	ACE.MixerPs = ACE.varIte[8];

	ambientRun(&ACE.Ambient);
	inletRun(&ACE.Inlet);
	ACE.FFan.hpW = &(ACE.hlthparas[0]);
	ACE.FFan.hpEf = &(ACE.hlthparas[1]);
	compressorFRun(&ACE.FFan);			// 前风扇
	splitterRun(&ACE.SplitterF);
	FVABIRun(&ACE.FVABI);
	ductRun(&ACE.DuctBypass2);
	ACE.NozzleBypass.hpA8 = &(ACE.hlthparas[13]);
	nozzleRun(&ACE.NozzleBypass);
	ductRun(&ACE.Duct22_23);
	ACE.RFan.hpW = &(ACE.hlthparas[2]);
	ACE.RFan.hpEf = &(ACE.hlthparas[3]);
	compressorFRun(&ACE.RFan);			// 后风扇
	splitterRun(&ACE.SplitterR);
	ductRun(&ACE.Duct24_25);
	ACE.HPC.hpW = &(ACE.hlthparas[4]);
	ACE.HPC.hpEf = &(ACE.hlthparas[5]);
	compressorRun(&ACE.HPC);			// HPC
	ACE.fuelFlow = ACE.fuelFlowInput;
	ACE.Burner.hpEf = &(ACE.hlthparas[10]);
	burnRun(&ACE.Burner);
	ACE.HPT.hpW = &(ACE.hlthparas[6]);
	ACE.HPT.hpEf = &(ACE.hlthparas[7]);
	turbineRun(&ACE.HPT);
	ductRun(&ACE.Duct45);
	ACE.LPT.hpW = &(ACE.hlthparas[8]);
	ACE.LPT.hpEf = &(ACE.hlthparas[9]);
	turbineRun(&ACE.LPT);
	ductRun(&ACE.Duct49_5);
	ductRun(&ACE.DuctBypass1);
	mixerRun(&ACE.Mixer);
	ACE.fuelFlowA = ACE.fuelFlowAInput;		// 20230913+, liukai
	ACE.Afterburner.hpEf = &(ACE.hlthparas[11]);
	burnRun(&ACE.Afterburner);
	ductRun(&ACE.Duct7_8);
	ACE.Nozzle.hpA8 = &(ACE.hlthparas[12]);
	nozzleRun(&ACE.Nozzle);
	ACE.LPS_Trq = ACE.FFan.y[5] + ACE.RFan.y[5] + ACE.LPT.y[5] * ACE.LPS.effMech;
	shaftRun(&ACE.LPS);
	ACE.HPS_Trq = ACE.HPC.y[5] + ACE.HPT.y[5] * ACE.HPS.effMech;
	shaftRun(&ACE.HPS);

	ACE.errOut[0] = ACE.FFan.y[6];      //Foward Fan_NErr
	ACE.errOut[1] = ACE.RFan.y[6];      //Rear Fan_NErr
	ACE.errOut[2] = ACE.HPC.y[6];      //HPC_NErr
	ACE.errOut[3] = ACE.HPT.y[6];      //HPT_NErr
	ACE.errOut[4] = ACE.LPT.y[6];      //LPT_NErr
	ACE.errOut[5] = ACE.Mixer.y[5];    //Mixer_NErr_W1
	ACE.errOut[6] = ACE.Mixer.y[8];	 //Mixer_NErr_W2
	ACE.errOut[7] = ACE.Nozzle.y[2];   //Nozzle_Nerr
	ACE.errOut[8] = ACE.NozzleBypass.y[2];   //Nozzle_Nerr
	
	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = ACE.errOut[i];
	}
	stepOut[varDime] = ACE.LPS.nDot;
	stepOut[varDime + 1] = ACE.HPS.nDot;
	engptr->eng = &ACE;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLL_ACERunSteadyComponents(double * stepIn, double * stepOut, EngineACEPointer *engptr)
{
	int i = 0;
	int varDime = ACE.varVecDime;

	ACE.fuelFlowInput = stepIn[2];
	ACE.Nozzle.areaThroatIn = stepIn[3];
	ACE.isDynamicCalculating = stepIn[4];
	ACE.LPS_Power = stepIn[5];
	ACE.HPS_Power = stepIn[6];
	ACE.RFan.alphaIn = stepIn[7];
	ACE.HPC.alphaIn = stepIn[8];
	ACE.fuelFlowAInput = stepIn[9];
//	ACE.betaFVABI = stepIn[13];
	ACE.betaRVABI = stepIn[14];
	ACE.NozzleBypass.areaThroatIn = stepIn[15];

	for (i = 0; i < varDime; i++)
	{
		ACE.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 13; i++)
	{
		ACE.hlthparas[i] = stepIn[i + 40];
	}

	ACE.inletMassFlow = ACE.varIte[0];
	ACE.FFan_Rline = ACE.varIte[1];
	ACE.SplitterBPRF = ACE.varIte[2];
	ACE.RFan_Rline = ACE.varIte[3];
	ACE.SplitterBPRR = ACE.varIte[4];
	ACE.HPC_Rline = ACE.varIte[5];
	ACE.HPT_PRin = ACE.varIte[6];
	ACE.LPT_PRin = ACE.varIte[7];
	ACE.MixerPs = ACE.varIte[8];
	ACE.LPS_Nmech = ACE.varIte[9];
	ACE.HPS_Nmech = ACE.varIte[10];

	ambientRun(&ACE.Ambient);
	inletRun(&ACE.Inlet);
	ACE.FFan.hpW = &(ACE.hlthparas[0]);
	ACE.FFan.hpEf = &(ACE.hlthparas[1]);
	compressorFRun(&ACE.FFan);			// 前风扇
	splitterRun(&ACE.SplitterF);
	FVABIRun(&ACE.FVABI);
	ductRun(&ACE.DuctBypass2);
	ACE.NozzleBypass.hpA8 = &(ACE.hlthparas[13]);
	nozzleRun(&ACE.NozzleBypass);
	ductRun(&ACE.Duct22_23);
	ACE.RFan.hpW = &(ACE.hlthparas[2]);
	ACE.RFan.hpEf = &(ACE.hlthparas[3]);
	compressorFRun(&ACE.RFan);			// 后风扇
	splitterRun(&ACE.SplitterR);
	ductRun(&ACE.Duct24_25);
	ACE.HPC.hpW = &(ACE.hlthparas[4]);
	ACE.HPC.hpEf = &(ACE.hlthparas[5]);
	compressorRun(&ACE.HPC);			// HPC
	ACE.fuelFlow = ACE.fuelFlowInput;
	ACE.Burner.hpEf = &(ACE.hlthparas[10]);
	burnRun(&ACE.Burner);
	ACE.HPT.hpW = &(ACE.hlthparas[6]);
	ACE.HPT.hpEf = &(ACE.hlthparas[7]);
	turbineRun(&ACE.HPT);
	ductRun(&ACE.Duct45);
	ACE.LPT.hpW = &(ACE.hlthparas[8]);
	ACE.LPT.hpEf = &(ACE.hlthparas[9]);
	turbineRun(&ACE.LPT);
	ductRun(&ACE.Duct49_5);
	ductRun(&ACE.DuctBypass1);
	mixerRun(&ACE.Mixer);
	ACE.fuelFlowA = ACE.fuelFlowAInput;		// 20230913+, liukai
	ACE.Afterburner.hpEf = &(ACE.hlthparas[11]);
	burnRun(&ACE.Afterburner);
	ductRun(&ACE.Duct7_8);
	ACE.Nozzle.hpA8 = &(ACE.hlthparas[12]);
	nozzleRun(&ACE.Nozzle);
	ACE.LPS_Trq = ACE.FFan.y[5] + ACE.RFan.y[5] + ACE.LPT.y[5] * ACE.LPS.effMech;
	shaftRun(&ACE.LPS);
	ACE.HPS_Trq = ACE.HPC.y[5] + ACE.HPT.y[5] * ACE.HPS.effMech;
	shaftRun(&ACE.HPS);

	ACE.errOut[0] = ACE.FFan.y[6];      //Foward Fan_NErr
	ACE.errOut[1] = ACE.RFan.y[6];      //Rear Fan_NErr
	ACE.errOut[2] = ACE.HPC.y[6];      //HPC_NErr
	ACE.errOut[3] = ACE.HPT.y[6];      //HPT_NErr
	ACE.errOut[4] = ACE.LPT.y[6];      //LPT_NErr
	ACE.errOut[5] = ACE.Mixer.y[5];    //Mixer_NErr_W1
	ACE.errOut[6] = ACE.Mixer.y[8];	 //Mixer_NErr_W2
	ACE.errOut[7] = ACE.Nozzle.y[2];   //Nozzle_Nerr
	ACE.errOut[8] = ACE.NozzleBypass.y[2];   //Nozzle_Nerr
	ACE.errOut[9] = ACE.LPS.nDot / 10000.0;   //LPS_Nerr
	ACE.errOut[10] = ACE.HPS.nDot / 10000.0;   //HPS_Nerr


	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = ACE.errOut[i];
	}
	engptr->eng = &ACE;

	return 0;
}

//------------------------------------------------------------------------------
int engineACECalculate(EngineACE *eng, int runMode)
{
	FILE *fOut;
	char *resultNameDes = "ACE_design.csv";
	char *resultNameSteady = "ACE_steady.csv";

	DLL_ACEInitial();
	ACE.altitude = 0;
	ACE.machNumber = 0;
	ACE.dTemperature = 0;

	double stepIn[100];
	double stepOut[20];
	for (int i = 0; i < 100; i++)
		stepIn[i] = 0;


	double input[16] = { 13200, 18330, 0.528184800366167, 0.204274649656814,  0,  0,  0, 0,  0,  1.38051435260454,  0, 0, 0,  1, 1,  0.0223420729851355 };
	for (int i = 0; i < 16; i++)
		stepIn[i] = input[i];
	double varIte0[11] = { 52.0676713990343, 0.125, 0.199820927476431,  0.25, 0.581303622841033, 0.413111111111111,  3.13771435314928,  2.22861392572084,  215017.239799346, 13200, 18330 };
	for (int i = 0; i < 11; i ++)
		stepIn[20+i] = varIte0[i];
	
	EngineACEPointer *engptr = (EngineACEPointer*)malloc(sizeof(EngineACEPointer));
	DLL_ACERunSteadyComponents(stepIn, stepOut, engptr);
//	DLL_ACEvarIteInit(stepIn, stepOut, engptr);
//	DLL_ACERunOnePoint(stepIn, stepOut, engptr);


	printf("Iterration variables: ");
	for (int i = 0; i <= 10; i++)
	{
		printf("%f ", ACE.varIte[i]);
	}
	printf("\n");
	printf("Errors: ");
	for (int i = 0; i <= 10; i++)
	{
		printf("%f ", ACE.errOut[i]);
	}
	printf("\n");
	engineACEFree(eng);

	return 0;
}
//------------------------------------------------------------------------------

