#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "engineMixedFan.h"
#include "functions_TMATS.h"
#include "newtonSolver.h"
#include "constants_TMATS.h"

EngineMixedFan MixedFan;
//------------------------------------------------------------------------------
int engineMixedFanInitial(EngineMixedFan *eng)
{
  int i = 0;
  FILE * fModel;
  char * filename = "MixedFan-222-GenMap.mdl";		// 20230911+, liukai
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
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[0]);   //迭代变量，不读
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[1]);  //
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[2]);  //
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[3]);  //
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[4]);  //
  fscanf(fModel,"%*[^=]=%lf",&eng->altitude);
  fscanf(fModel,"%*[^=]=%lf",&eng->machNumber);
  fscanf(fModel,"%*[^=]=%lf",&eng->dTemperature);
  fscanf(fModel,"%*[^=]=%lf",&eng->TtBurnerOut);

  //fscanf(fModel,"%*[^=]=%lf",&eng->pAmbInput);  //
  //fscanf(fModel,"%*[^=]=%lf",&eng->farInput);   //
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
  compressorFInitial(&eng->Fan,fModel,name, pathName);
  
  fscanf(fModel,"%*[^=]=%s",name);
  splitterInitial(&eng->Splitter,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct1,fModel,name);

  //fscanf(fModel,"%*[^=]=%s",name);            //
  //compressorInitial(&eng->LPC,fModel,name);   //

  //fscanf(fModel,"%*[^=]=%s",name);            //
  //ductInitial(&eng->Duct2,fModel,name);       //

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
  ductInitial(&eng->Duct4,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  mixerInitial(&eng->Mixer,fModel,name);

  fscanf(fModel, "%*[^=]=%s", name);
  burnInitial(&eng->Afterburner, fModel, name);

  //fscanf(fModel,"%*[^=]=%s",name);             //
  //nozzleInitial(&eng->Noz_core,fModel,name);   //

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct5,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  nozzleInitial(&eng->Nozzle,fModel,name);

  //fscanf(fModel,"%*[^=]=%s",name);             //
  //nozzleInitial(&eng->Noz_byp,fModel,name);    //

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->LPS,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->HPS,fModel,name);
  
  fclose(fModel);
  eng->isInitial = 1;

  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanSetIdes(EngineMixedFan *eng, double iDes)
{
	if (iDes < 3)   //0-设计点；1-所有部件的iDes设为1；2-所有部件的iDes设为2
	{
		eng->Fan.compressorStruct.IDes = iDes;  //需要设置旋转部件、混合室和喷管的IDes
		//eng->LPC.compressorStruct.IDes = iDes;
		eng->HPC.compressorStruct.IDes = iDes;
		eng->HPT.turbineStruct.IDes = iDes;
		eng->LPT.turbineStruct.IDes = iDes;
	//	eng->Mixer.mixerStruct.IDes = iDes;
	//	eng->Nozzle.nozzleStruct.IDes = iDes;
		//eng->Noz_byp.nozzleStruct.IDes = iDes;
	}
	else          //3-按照输入文件中的参数配置各部件的IDes
	{
		eng->Fan.compressorStruct.IDes = eng->Fan.IDesInput;
		//eng->LPC.compressorStruct.IDes = eng->LPC.IDesInput;
		eng->HPC.compressorStruct.IDes = eng->HPC.IDesInput;
		eng->HPT.turbineStruct.IDes = eng->HPT.IDesInput;
		eng->LPT.turbineStruct.IDes = eng->LPT.IDesInput;
		eng->Mixer.mixerStruct.IDes = eng->Mixer.IDesInput;
		eng->Nozzle.nozzleStruct.IDes = eng->Nozzle.IDesInput;
		//eng->Noz_byp.nozzleStruct.IDes = eng->Noz_byp.IDesInput;
	}
	return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanFree(EngineMixedFan *eng)
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
  compressorFree(&eng->Fan);
  splitterFree(&eng->Splitter);
  ductFree(&eng->Duct1);
  //compressorFree(&eng->LPC);   //
  //ductFree(&eng->Duct2);       //
  compressorFree(&eng->HPC);
  burnFree(&eng->Burner);
  turbineFree(&eng->HPT);
  ductFree(&eng->Duct2);
  turbineFree(&eng->LPT);
  ductFree(&eng->Duct3);
  ductFree(&eng->Duct4);
  mixerFree(&eng->Mixer);
  burnFree(&eng->Afterburner);
  //nozzleFree(&eng->Noz_core);  //
  ductFree(&eng->Duct5);
  nozzleFree(&eng->Nozzle);
  //nozzleFree(&eng->Noz_byp);   //
  shaftFree(&eng->LPS);
  shaftFree(&eng->HPS);

  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanLink(EngineMixedFan *eng)
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

  eng->Fan.gasPathIn = eng->Inlet.gasPathOut;
  eng->Fan.rLineIn  = &eng->Fan_Rline;
  eng->Fan.nMech  = eng->LPS.nMech;
  eng->Fan.BypassRatioIn = &eng->SplitterBPR;
  eng->Fan.Amean = 0.3;
  eng->Fan.Cmean = 0.1;
  eng->Fan.Kcla = 1.5;
  eng->Fan.Kwe = 0.5;
  eng->Fan.AFT = 0.102500743508674;// 0.084144417633749; // 0.0954;
  eng->Fan.hpW = &(eng->hlthparas[0]);
  eng->Fan.hpEf = &(eng->hlthparas[1]);
  eng->Fan.hpAFT = &(eng->hlthparas[8]);
  eng->Fan.hpPR_TipRootRatio = &(eng->hlthparas[9]);
  eng->Fan.hpEf_TipRootRatio = &(eng->hlthparas[10]);
  eng->Fan.hpWbld = NULL;
  eng->Fan.hpBldPRec = NULL;
  eng->Fan.hpBldht = (double*)calloc(1, sizeof(double));

  eng->Splitter.gasPathIn = &eng->Fan.y[0];
  eng->Splitter.BypassRatioIn = &eng->SplitterBPR;

  eng->Duct1.gasPathIn = eng->Splitter.gasPathOutMain;
  eng->Duct1.hpdP_Loss = &(eng->hlthparas[11]);


  //eng->LPC.gasPathIn = eng->Duct1.gasPathOut;    //
  //eng->LPC.rLineIn = &eng->LPC_Rline;            //
  //eng->LPC.nMech = eng->LPS.nMech;               //

  //eng->Duct2.gasPathIn = &eng->LPC.y[0];         //

  eng->HPC.gasPathIn = eng->Duct1.gasPathOut;
  eng->HPC.rLineIn = &eng->HPC_Rline;
  eng->HPC.nMech =  eng->HPS.nMech;
  eng->HPC.BypassRatioIn = &eng->SplitterBPR;
  eng->HPC.Amean = 0.12;
  eng->HPC.Cmean = 0.1;
  eng->HPC.Kcla = 1.5;
  eng->HPC.Kwe = 0.5;
  eng->HPC.hpW = &(eng->hlthparas[2]);
  eng->HPC.hpEf = &(eng->hlthparas[3]);
  eng->HPC.hpAFT = (double*)calloc(1, sizeof(double));
  eng->HPC.hpPR_TipRootRatio = (double*)calloc(1, sizeof(double));		
  eng->HPC.hpEf_TipRootRatio = (double*)calloc(1, sizeof(double));		
  eng->HPC.hpWbld = &(eng->hlthparas[20 + (int)(eng->HPC.compressorStruct.FracBldNm)]);
  eng->HPC.hpBldPRec = &(eng->hlthparas[20]);
  eng->HPC.hpBldht = (double*)calloc(1, sizeof(double));
  
  eng->Burner.fuelFlowIn = &eng->fuelFlow;
  eng->Burner.gasPathIn = &eng->HPC.y[0];
  eng->Burner.hpEf = &(eng->hlthparas[12]);
  eng->Burner.hpdP_Loss = &(eng->hlthparas[13]);		

  eng->HPT.coolingFlow = eng->HPC.fractionalBleeds;
  //eng->HPT.coolingFlowWidth = &eng->HPC.fractionalBleeds[2500];
  eng->HPT.gasPathIn = &eng->Burner.y[0];
  eng->HPT.PressureRatioIn = &eng->HPT_PRin;
  eng->HPT.nMech = eng->HPS.nMech;
  eng->HPT.Amean = 0.12;
  eng->HPT.Cmean = 0.1;
  eng->HPT.Kcla = 1.5;
  eng->HPT.Kwe = 0.5;
  eng->HPT.hpW = &(eng->hlthparas[6]);
  eng->HPT.hpEf = &(eng->hlthparas[7]);

  eng->Duct2.gasPathIn = &eng->HPT.y[0];
  eng->Duct2.hpdP_Loss = &(eng->hlthparas[14]);

  //eng->LPT.coolingFlow = eng->noFlow;   //
  //eng->LPT.coolingFlowWidth = &eng->noFlowWidth;
  int N;
  N = eng->HPT.coolingFlowWidth;
  eng->LPT.coolingFlow = &eng->HPC.fractionalBleeds[N];
  eng->LPT.gasPathIn = eng->Duct2.gasPathOut;
  eng->LPT.PressureRatioIn = &eng->LPT_PRin;
  eng->LPT.nMech = eng->LPS.nMech;
  eng->LPT.Amean = 0.12;
  eng->LPT.Cmean = 0.1;
  eng->LPT.Kcla = 1.5;
  eng->LPT.Kwe = 0.5;
  eng->LPT.hpW = &(eng->hlthparas[4]);
  eng->LPT.hpEf = &(eng->hlthparas[5]);

  eng->Duct3.gasPathIn = &eng->LPT.y[0];
  eng->Duct3.hpdP_Loss = &(eng->hlthparas[15]);

  //eng->Noz_core.gasPathIn = eng->Duct4.gasPathOut;   //
  //eng->Noz_core.pAmbIn = &eng->pAmbInput;            //

  eng->Duct4.gasPathIn = eng->Splitter.gasPathOutBypass;
  eng->Duct4.hpdP_Loss = &(eng->hlthparas[16]);

  eng->Mixer.gasPathIn1 = eng->Duct4.gasPathOut;		// 外涵道出口
  eng->Mixer.gasPathIn2 = eng->Duct3.gasPathOut;		// LPT出口
  eng->Mixer.MixerPs = &eng->MixerPs;
  eng->Mixer.isDynamicCalculating = &eng->isDynamicCalculating;
  eng->Mixer.betaRVABI = &eng->betaRVABI;

  eng->Afterburner.fuelFlowIn = &eng->fuelFlowA;
  eng->Afterburner.gasPathIn = &eng->Mixer.y[0];
  eng->Afterburner.hpEf = &(eng->hlthparas[17]);
  eng->Afterburner.hpdP_Loss = (double*)calloc(1, sizeof(double));

  eng->Duct5.gasPathIn = &eng->Afterburner.y[0];
  eng->Duct5.hpdP_Loss = &(eng->hlthparas[18]);

  eng->Nozzle.fDrag = &eng->Ambient.fDrag;
  eng->Nozzle.gasPathIn = eng->Duct5.gasPathOut;
  eng->Nozzle.pAmbIn = &eng->Ambient.y[4];
  eng->Nozzle.afterFVABI = 0.0;
  eng->Nozzle.hpA8 = &(eng->hlthparas[19]);
  eng->Nozzle.hpA9 = (double*)calloc(1, sizeof(double));
  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanOutPutHead(EngineMixedFan *eng,FILE *fOut)
{
//  if(eng->isDynamic == 1)
    fprintf(fOut,"time,");
  fprintf(fOut,"%s_altitude,",eng->engineName);
  fprintf(fOut,"%s_machNumber,",eng->engineName);
  fprintf(fOut,"%s_dTemperature,",eng->engineName);
  fprintf(fOut,"%s_TtBurnerOutInput,",eng->engineName);
  //fprintf(fOut,"%s_FarIn,",eng->engineName);       //
  //fprintf(fOut,"%s_pAmb,",eng->engineName);        //
  //fprintf(fOut,"%s_burnerFar,",eng->engineName);   //

  fprintf(fOut,"%s_varWin,",eng->engineName);
  fprintf(fOut,"%s_varFan_Rline,",eng->engineName);
  fprintf(fOut,"%s_varSplitterBPR,",eng->engineName);
  //fprintf(fOut,"%s_varLPC_Rline,",eng->engineName);
  fprintf(fOut,"%s_varHPC_Rline,",eng->engineName);
  fprintf(fOut,"%s_varBurnerFar,",eng->engineName);
  fprintf(fOut,"%s_varHPT_PRin,",eng->engineName);
  fprintf(fOut,"%s_varLPT_PRin,",eng->engineName);
  fprintf(fOut,"%s_varLPS_Nmech,",eng->engineName);
  fprintf(fOut,"%s_varHPS_Nmech,",eng->engineName);

  ambientOutPutHead(&eng->Ambient,fOut);
  inletOutPutHead(&eng->Inlet,fOut);
  compressorOutPutHead(&eng->Fan,fOut);
  splitterOutPutHead(&eng->Splitter,fOut);
  ductOutPutHead(&eng->Duct1,fOut);
  //compressorOutPutHead(&eng->LPC,fOut);
  //ductOutPutHead(&eng->Duct2,fOut);
  compressorOutPutHead(&eng->HPC,fOut);
  burnOutPutHead(&eng->Burner,fOut);
  turbineOutPutHead(&eng->HPT,fOut);
  ductOutPutHead(&eng->Duct2,fOut);
  turbineOutPutHead(&eng->LPT,fOut);
  ductOutPutHead(&eng->Duct3,fOut);
  ductOutPutHead(&eng->Duct4,fOut);
  mixerOutPutHead(&eng->Mixer,fOut);
  burnOutPutHead(&eng->Afterburner, fOut);
  ductOutPutHead(&eng->Duct5,fOut);
  nozzleOutPutHead(&eng->Nozzle,fOut);
  //ductOutPutHead(&eng->Duct5,fOut);
  //nozzleOutPutHead(&eng->Noz_byp,fOut);
  shaftOutPutHead(&eng->LPS,fOut);
  shaftOutPutHead(&eng->HPS,fOut);

  fprintf(fOut,"\n");
  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanOutPutResult(EngineMixedFan *eng,FILE *fOut)
{
//  if(eng->isDynamic == 1)
    fprintf(fOut,"%lf,",eng->timeNow);
  fprintf(fOut,"%lf,",eng->altitude);
  fprintf(fOut,"%lf,",eng->machNumber);
  fprintf(fOut,"%lf,",eng->dTemperature);
  fprintf(fOut,"%lf,",eng->Burner.y[2]);
  //fprintf(fOut,"%lf,",eng->InletGasPort[4]);  //
  //fprintf(fOut,"%lf,",eng->pAmbInput);        //
  //fprintf(fOut,"%lf,",eng->farUse);           //

  fprintf(fOut,"%lf,",eng->inletMassFlow);
  fprintf(fOut,"%lf,",eng->Fan_Rline);
  fprintf(fOut,"%lf,",eng->SplitterBPR);
  //fprintf(fOut,"%lf,",eng->LPC_Rline);
  fprintf(fOut,"%lf,",eng->HPC_Rline);
  fprintf(fOut,"%lf,",eng->MixerPs);
  fprintf(fOut, "%lf,", eng->Afterburner.y[2]);
  fprintf(fOut,"%lf,",eng->HPT_PRin);
  fprintf(fOut,"%lf,",eng->LPT_PRin);
  fprintf(fOut,"%lf,",eng->LPS_Nmech);
  fprintf(fOut,"%lf,",eng->HPS_Nmech);

  ambientOutPutResult(&eng->Ambient,fOut);
  inletOutPutResult(&eng->Inlet,fOut);
  compressorOutPutResult(&eng->Fan,fOut);
  splitterOutPutResult(&eng->Splitter,fOut);
  ductOutPutResult(&eng->Duct1,fOut);
  //compressorOutPutResult(&eng->LPC,fOut);
  //ductOutPutResult(&eng->Duct2,fOut);
  compressorOutPutResult(&eng->HPC,fOut);
  burnOutPutResult(&eng->Burner,fOut);
  turbineOutPutResult(&eng->HPT,fOut);
  ductOutPutResult(&eng->Duct2,fOut);
  turbineOutPutResult(&eng->LPT,fOut);
  ductOutPutResult(&eng->Duct3,fOut);
  ductOutPutResult(&eng->Duct4,fOut);
  mixerOutPutResult(&eng->Mixer,fOut);
  burnOutPutResult(&eng->Afterburner, fOut);
  ductOutPutResult(&eng->Duct5,fOut);
  nozzleOutPutResult(&eng->Nozzle,fOut);
  //ductOutPutResult(&eng->Duct5,fOut);
  //nozzleOutPutResult(&eng->Noz_byp,fOut);
  shaftOutPutResult(&eng->LPS,fOut);
  shaftOutPutResult(&eng->HPS,fOut);

  fprintf(fOut,"\n");
  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanRunOnce(EngineMixedFan *eng)
{
  ambientRun(&eng->Ambient);
  inletRun(&eng->Inlet);
  compressorFRun(&eng->Fan);
  splitterRun(&eng->Splitter);
  ductRun(&eng->Duct1);
  //compressorRun(&eng->LPC);   //
  //ductRun(&eng->Duct2);       //
  compressorRun(&eng->HPC);
  eng->fuelFlow = eng->fuelFlowInput;
  burnRun(&eng->Burner);

  turbineRun(&eng->HPT);
  ductRun(&eng->Duct2);
  turbineRun(&eng->LPT);
  ductRun(&eng->Duct3);
  ductRun(&eng->Duct4);
  mixerRun(&eng->Mixer);
  ductRun(&eng->Duct5);
  nozzleRun(&eng->Nozzle);
  //ductRun(&eng->Duct5);       //
  //nozzleRun(&eng->Noz_byp);   //
//  eng->LPS_Trq = eng->Fan.y[5] + eng->LPT.y[5];		// liukai -
  eng->LPS_Trq = eng->Fan.y[5] + eng->LPT.y[5]*0.99;			// liukai +
  shaftRun(&eng->LPS);
//  eng->HPS_Trq = eng->HPC.y[5] + eng->HPT.y[5];		// liukai -
  eng->HPS_Trq = eng->HPC.y[5]  + eng->HPT.y[5]*0.99;
  shaftRun(&eng->HPS);
  return 0;
}
//------------------------------------------------------------------------------
int MixedFan_RunOnce(double *varIn,double *errOut,int dime)
{
  int i = 0;
  for(i = 0;i < dime;i++)
  {
    MixedFan.varIte[i] = varIn[i];
    MixedFan.errOut[i] = 1;
  }

  engineMixedFanRunOnce(&MixedFan);

  for(i = 0;i < dime;i++)
  {
    errOut[i] = MixedFan.errOut[i];
  }
  if (dime >= 9)
  {
	  errOut[7] = MixedFan.errOut[7] / 10000.0;
	  errOut[8] = MixedFan.errOut[8] / 10000.0;
  }

  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanOnePoint(EngineMixedFan *eng)   //稳态工作点计算
{
	int i = 0;
	if (eng->convergeTag != 0)  //若之前工作点没有收敛，则使用输入的初值；否则使用上次计算收敛的变量做为初值
	{
		for (i = 0; i < eng->varVecDime; i++)
		{
			eng->varStartStore[i] = eng->varStartInput[i];
		}
	}
	eng->convergeTag = newtonSolver(MixedFan_RunOnce,
		eng->varVecDime,
		eng->varStartStore, eng->varMin, eng->varMax, eng->varDelLim,
		eng->accuracyReq,
		eng->distuFactor,
		eng->maxIterations);

	return 0;
}
//------------------------------------------------------------------------------
int MixedTurbofanRunSteadyComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
	for (i = 0; i < dime; i++)
	{
		MixedFan.varIte[i] = varIn[i];
		MixedFan.errOut[i] = 1;
	}
	MixedFan.inletMassFlow = MixedFan.varIte[0];
	MixedFan.Fan_Rline = MixedFan.varIte[1];
	MixedFan.SplitterBPR = MixedFan.varIte[2];
	MixedFan.HPC_Rline = MixedFan.varIte[3];
	MixedFan.HPT_PRin = MixedFan.varIte[4];
	MixedFan.LPT_PRin = MixedFan.varIte[5];
	MixedFan.MixerPs = MixedFan.varIte[6];
	MixedFan.LPS_Nmech = MixedFan.varIte[7];
	MixedFan.HPS_Nmech = MixedFan.varIte[8];

	ambientRun(&MixedFan.Ambient);
	//jrt,20241105
/*/	MixedFan.Ambient.y[4] = MixedFan.AmbientPs;				// P0/*/	// liukai:- for 222; + for 10
	inletRun(&MixedFan.Inlet);
	//jrt,20241105
/*/	MixedFan.Inlet.gasPathOut[2] = MixedFan.InletOutTt;		// T1
	MixedFan.Inlet.gasPathOut[3] = MixedFan.InletOutPt;		// P1/*/	// liukai:- for 222; + for 10
	/*/
	MixedFan.Fan.hpW = &(MixedFan.hlthparas[0]);
	MixedFan.Fan.hpEf = &(MixedFan.hlthparas[1]);
	MixedFan.Fan.hpAFT = &(MixedFan.hlthparas[11]);
	// jrt, 20241105
	MixedFan.Fan.hpPR_TipRootRatio = &(MixedFan.hlthparas[16]);
	MixedFan.Fan.hpEf_TipRootRatio = &(MixedFan.hlthparas[17]);/*/

	compressorFRun(&MixedFan.Fan);
	splitterRun(&MixedFan.Splitter);
	ductRun(&MixedFan.Duct1);
//	MixedFan.HPC.hpW = &(MixedFan.hlthparas[2]);
//	MixedFan.HPC.hpEf = &(MixedFan.hlthparas[3]);
	compressorRun(&MixedFan.HPC);
	MixedFan.fuelFlow = MixedFan.fuelFlowInput;
//	MixedFan.Burner.hpEf = &(MixedFan.hlthparas[9]);
	burnRun(&MixedFan.Burner);
//	MixedFan.HPT.hpW = &(MixedFan.hlthparas[4]);
//	MixedFan.HPT.hpEf = &(MixedFan.hlthparas[5]);
	turbineRun(&MixedFan.HPT);
	ductRun(&MixedFan.Duct2);
//	MixedFan.Duct2.gasPathOut[3] = *(MixedFan.Duct2.gasPathIn + 3) * (1 - MixedFan.Duct2.dP_Loss - MixedFan.hlthparas[15]);
//	MixedFan.LPT.hpW = &(MixedFan.hlthparas[6]);
//	MixedFan.LPT.hpEf = &(MixedFan.hlthparas[7]);
	turbineRun(&MixedFan.LPT);
	ductRun(&MixedFan.Duct3);
	ductRun(&MixedFan.Duct4);
//	MixedFan.Duct3.gasPathOut[3] = *(MixedFan.Duct3.gasPathIn + 3) * (1 - MixedFan.Duct3.dP_Loss - MixedFan.hlthparas[12]);
//	MixedFan.Duct4.gasPathOut[3] = *(MixedFan.Duct4.gasPathIn + 3) * (1 - MixedFan.Duct4.dP_Loss - MixedFan.hlthparas[13]);
	mixerRun(&MixedFan.Mixer);
	MixedFan.fuelFlowA = MixedFan.fuelFlowAInput;		// 20230913+, liukai
//	MixedFan.Afterburner.hpEf = &(MixedFan.hlthparas[10]);
	burnRun(&MixedFan.Afterburner);
	ductRun(&MixedFan.Duct5);
//	MixedFan.Duct5.gasPathOut[3] = *(MixedFan.Duct5.gasPathIn + 3) * (1 - MixedFan.Duct5.dP_Loss - MixedFan.hlthparas[14]);
//	MixedFan.Nozzle.hpA8 = &(MixedFan.hlthparas[8]);
	//jrt,20241106
//	MixedFan.Nozzle.hpA9 = &(MixedFan.hlthparas[18]);

	nozzleRun(&MixedFan.Nozzle);
	MixedFan.LPS_Trq = MixedFan.Fan.y[5] + MixedFan.LPT.y[5] * MixedFan.LPS.effMech;
	shaftRun(&MixedFan.LPS);
	MixedFan.HPS_Trq = MixedFan.HPC.y[5] + MixedFan.HPT.y[5] * MixedFan.HPS.effMech;
	shaftRun(&MixedFan.HPS);

	MixedFan.errOut[0] = MixedFan.Fan.y[6];      //Fan_NErr
	MixedFan.errOut[1] = MixedFan.HPC.y[6];      //HPC_NErr
	MixedFan.errOut[2] = MixedFan.HPT.y[6];      //HPT_NErr
	MixedFan.errOut[3] = MixedFan.LPT.y[6];      //LPT_NErr
	MixedFan.errOut[4] = MixedFan.Mixer.y[5];    //Mixer_NErr_W1
	MixedFan.errOut[5] = MixedFan.Mixer.y[8];	 //Mixer_NErr_W2
	MixedFan.errOut[6] = MixedFan.Nozzle.y[2];   //Nozzle_Nerr
	MixedFan.errOut[7] = MixedFan.LPS.nDot / 10000.0;      //LPS_Ndot
	MixedFan.errOut[8] = MixedFan.HPS.nDot / 10000.0;      //HPS_Ndot
	for (i = 0; i < dime; i++)
	{
		errOut[i] = MixedFan.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
 int MixedTurbofanRunTransientComponents(double *varIn, double *errOut, int dime)
{
	int i = 0;
	for (i = 0; i < dime; i++)
	{
		MixedFan.varIte[i] = varIn[i];
		MixedFan.errOut[i] = 1;
	}
	MixedFan.inletMassFlow = MixedFan.varIte[0];
	MixedFan.Fan_Rline = MixedFan.varIte[1];
	MixedFan.SplitterBPR = MixedFan.varIte[2];
	MixedFan.HPC_Rline = MixedFan.varIte[3];
	MixedFan.HPT_PRin = MixedFan.varIte[4];
	MixedFan.LPT_PRin = MixedFan.varIte[5];
	MixedFan.MixerPs = MixedFan.varIte[6];

	ambientRun(&MixedFan.Ambient);
	inletRun(&MixedFan.Inlet);
	compressorFRun(&MixedFan.Fan);
	splitterRun(&MixedFan.Splitter);
	ductRun(&MixedFan.Duct1);
	compressorRun(&MixedFan.HPC);
	MixedFan.fuelFlow = MixedFan.fuelFlowInput;
	burnRun(&MixedFan.Burner);
	turbineRun(&MixedFan.HPT);
	ductRun(&MixedFan.Duct2);
	turbineRun(&MixedFan.LPT);
	ductRun(&MixedFan.Duct3);
	ductRun(&MixedFan.Duct4);
	mixerRun(&MixedFan.Mixer);
	MixedFan.fuelFlowA = MixedFan.fuelFlowAInput;		// 20230913+, liukai
	burnRun(&MixedFan.Afterburner);
	ductRun(&MixedFan.Duct5);
	nozzleRun(&MixedFan.Nozzle);
	MixedFan.LPS_Trq = MixedFan.Fan.y[5] + MixedFan.LPT.y[5] * MixedFan.LPS.effMech;
	shaftRun(&MixedFan.LPS);
	MixedFan.HPS_Trq = MixedFan.HPC.y[5] + MixedFan.HPT.y[5] * MixedFan.HPS.effMech;
	shaftRun(&MixedFan.HPS);

	MixedFan.errOut[0] = MixedFan.Fan.y[6];      //Fan_NErr
	MixedFan.errOut[1] = MixedFan.HPC.y[6];      //HPC_NErr
	MixedFan.errOut[2] = MixedFan.HPT.y[6];      //HPT_NErr
	MixedFan.errOut[3] = MixedFan.LPT.y[6];      //LPT_NErr
	MixedFan.errOut[4] = MixedFan.Mixer.y[5];    //Mixer_NErr_W1
	MixedFan.errOut[5] = MixedFan.Mixer.y[8];	 //Mixer_NErr_W2
	MixedFan.errOut[6] = MixedFan.Nozzle.y[2];   //Nozzle_Nerr
	for (i = 0; i < dime; i++)
	{
		errOut[i] = MixedFan.errOut[i];
	}

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLInitial()
{
	int i = 0;
	MixedFan.isInitial = 0;
	MixedFan.isDesOk = 0;
	MixedFan.timeNow = 0;
	MixedFan.convergeTag = 1;
	engineMixedFanLink(&MixedFan);
	engineMixedFanInitial(&MixedFan);
	engineMixedFanLink(&MixedFan);
	engineMixedFanSetIdes(&MixedFan, MixedFan.offDesignMode);

	for (i = 0; i < MixedFan.varVecDime; i++)
	{
		MixedFan.varStartStore[i] = MixedFan.varStartInput[i];
	}
	for (i = 0; i < 40; i++)
	{
		MixedFan.hlthparas[i] = 0;
	}

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLFree()
{
	engineMixedFanFree(&MixedFan);
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLvarIteInit(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	int i = 0;

	for (i = 0; i < MixedFan.varVecDime; i++)
	{
		MixedFan.varStartStore[i] = stepIn[i + 20];
	}

	engptr->eng = &MixedFan;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLConditionsInit(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	MixedFan.altitude = stepIn[10];
	MixedFan.machNumber = stepIn[11];
	MixedFan.dTemperature = stepIn[12];

	ambientRun(&MixedFan.Ambient);

	engptr->eng = &MixedFan;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLRunOnePoint(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	int i = 0;
	int varDime = MixedFan.varVecDime;

	MixedFan.fuelFlowInput = stepIn[2];
	MixedFan.Nozzle.areaThroatIn = stepIn[3];
	MixedFan.isDynamicCalculating = stepIn[4];
	MixedFan.LPS_Power = stepIn[5];
	MixedFan.HPS_Power = stepIn[6];
	MixedFan.Fan.alphaIn = stepIn[7];
	MixedFan.HPC.alphaIn = stepIn[8];
	MixedFan.fuelFlowAInput = stepIn[9];
/*/	MixedFan.Nozzle.areaExitIn = stepIn[10];/*/		// liukai:- for 222; + for 10
	//jrt, 20241105
/*/	MixedFan.InletOutTt = stepIn[13];		//T1
	MixedFan.InletOutPt = stepIn[14];		//P1
	MixedFan.AmbientPs = stepIn[15];		//P0	/*/	// liukai:- for 222; + for 10

	MixedFan.betaRVABI = 1;

	for (i = 0; i < 39; i++)// jrt,20241105
	{
		MixedFan.hlthparas[i] = stepIn[i + 40];
	}

	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunSteadyComponents,
		MixedFan.varVecDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	engptr->eng = &MixedFan;
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLRunOneStep(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	int i = 0;
	int varDime  = MixedFan.varVecDime - 2;
	
	MixedFan.LPS_Nmech = stepIn[0];
	MixedFan.HPS_Nmech = stepIn[1];
	MixedFan.fuelFlowInput = stepIn[2];
	MixedFan.Nozzle.areaThroatIn = stepIn[3];
	MixedFan.isDynamicCalculating = stepIn[4];
	MixedFan.LPS_Power = stepIn[5];
	MixedFan.HPS_Power = stepIn[6];
	MixedFan.Fan.alphaIn = stepIn[7];
	MixedFan.HPC.alphaIn = stepIn[8];
	MixedFan.fuelFlowAInput = stepIn[9];
	MixedFan.Nozzle.areaExitIn = stepIn[10];
	MixedFan.betaRVABI = 1;
	for (i = 0; i < 39; i++)
	{
		MixedFan.hlthparas[i] = stepIn[i + 40];
	}

	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	stepOut[0] = MixedFan.LPS.nDot;
	stepOut[1] = MixedFan.HPS.nDot;
	engptr->eng = &MixedFan;
	
	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLRunTransientComponents(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	int i = 0;
	int varDime = MixedFan.varVecDime - 2;
	MixedFan.LPS_Nmech = stepIn[0];
	MixedFan.HPS_Nmech = stepIn[1];
	MixedFan.fuelFlowInput = stepIn[2];
	MixedFan.Nozzle.areaThroatIn = stepIn[3];
	MixedFan.isDynamicCalculating = stepIn[4];
	MixedFan.LPS_Power = stepIn[5];
	MixedFan.HPS_Power = stepIn[6];
	MixedFan.Fan.alphaIn = stepIn[7];
	MixedFan.HPC.alphaIn = stepIn[8];
	MixedFan.fuelFlowAInput = stepIn[9];
	MixedFan.Nozzle.areaExitIn = stepIn[10];
	MixedFan.betaRVABI = 1;

	for (i = 0; i < varDime; i++)
	{
		MixedFan.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 39; i++)
	{
		MixedFan.hlthparas[i] = stepIn[i + 40];
	}

	MixedFan.inletMassFlow = MixedFan.varIte[0];
	MixedFan.Fan_Rline = MixedFan.varIte[1];
	MixedFan.SplitterBPR = MixedFan.varIte[2];
	MixedFan.HPC_Rline = MixedFan.varIte[3];
	MixedFan.HPT_PRin = MixedFan.varIte[4];
	MixedFan.LPT_PRin = MixedFan.varIte[5];
	MixedFan.MixerPs = MixedFan.varIte[6];

	ambientRun(&MixedFan.Ambient);
	inletRun(&MixedFan.Inlet);
	compressorFRun(&MixedFan.Fan);
	splitterRun(&MixedFan.Splitter);
	ductRun(&MixedFan.Duct1);
	compressorRun(&MixedFan.HPC);
	MixedFan.fuelFlow = MixedFan.fuelFlowInput;
	burnRun(&MixedFan.Burner);
	turbineRun(&MixedFan.HPT);
	ductRun(&MixedFan.Duct2);
	turbineRun(&MixedFan.LPT);
	ductRun(&MixedFan.Duct3);
	ductRun(&MixedFan.Duct4);
	mixerRun(&MixedFan.Mixer);
	MixedFan.fuelFlowA = MixedFan.fuelFlowAInput;		// 20230913+, liukai
	burnRun(&MixedFan.Afterburner);
	ductRun(&MixedFan.Duct5);
	nozzleRun(&MixedFan.Nozzle);
	MixedFan.LPS_Trq = MixedFan.Fan.y[5] + MixedFan.LPT.y[5] * MixedFan.LPS.effMech;
	shaftRun(&MixedFan.LPS);
	MixedFan.HPS_Trq = MixedFan.HPC.y[5] + MixedFan.HPT.y[5] * MixedFan.HPS.effMech;
	shaftRun(&MixedFan.HPS);

	MixedFan.errOut[0] = MixedFan.Fan.y[6];      //Fan_NErr
	MixedFan.errOut[1] = MixedFan.HPC.y[6];      //HPC_NErr
	MixedFan.errOut[2] = MixedFan.HPT.y[6];      //HPT_NErr
	MixedFan.errOut[3] = MixedFan.LPT.y[6];      //LPT_NErr
	MixedFan.errOut[4] = MixedFan.Mixer.y[5];    //Mixer_NErr_W1
	MixedFan.errOut[5] = MixedFan.Mixer.y[8];	 //Mixer_NErr_W2
	MixedFan.errOut[6] = MixedFan.Nozzle.y[2];   //Nozzle_Nerr


	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = MixedFan.errOut[i];
	}
	stepOut[varDime] = MixedFan.LPS.nDot;
	stepOut[varDime+1] = MixedFan.HPS.nDot;
	engptr->eng = &MixedFan;

	return 0;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int DLLRunSteadyComponents(double * stepIn, double * stepOut, EnginePointer *engptr)
{
	int i = 0;
	int varDime = MixedFan.varVecDime;

	MixedFan.fuelFlowInput = stepIn[2];
	MixedFan.Nozzle.areaThroatIn = stepIn[3];
	MixedFan.isDynamicCalculating = stepIn[4];
	MixedFan.LPS_Power = stepIn[5];
	MixedFan.HPS_Power = stepIn[6];
	MixedFan.Fan.alphaIn = stepIn[7];
	MixedFan.HPC.alphaIn = stepIn[8];
	MixedFan.fuelFlowAInput = stepIn[9];
	MixedFan.Nozzle.areaExitIn = stepIn[10];
	MixedFan.betaRVABI = 1;

	for (i = 0; i < varDime; i++)
	{
		MixedFan.varIte[i] = stepIn[i + 20];
	}
	for (i = 0; i < 39; i++)
	{
		MixedFan.hlthparas[i] = stepIn[i + 40];
	}

	MixedFan.inletMassFlow = MixedFan.varIte[0];
	MixedFan.Fan_Rline = MixedFan.varIte[1];
	MixedFan.SplitterBPR = MixedFan.varIte[2];
	MixedFan.HPC_Rline = MixedFan.varIte[3];
	MixedFan.HPT_PRin = MixedFan.varIte[4];
	MixedFan.LPT_PRin = MixedFan.varIte[5];
	MixedFan.MixerPs = MixedFan.varIte[6];
	MixedFan.LPS_Nmech = MixedFan.varIte[7];
	MixedFan.HPS_Nmech = MixedFan.varIte[8];

	ambientRun(&MixedFan.Ambient);
	inletRun(&MixedFan.Inlet);
	compressorFRun(&MixedFan.Fan);
	splitterRun(&MixedFan.Splitter);
	ductRun(&MixedFan.Duct1);
	compressorRun(&MixedFan.HPC);
	MixedFan.fuelFlow = MixedFan.fuelFlowInput;
	burnRun(&MixedFan.Burner);
	turbineRun(&MixedFan.HPT);
	ductRun(&MixedFan.Duct2);
	turbineRun(&MixedFan.LPT);
	ductRun(&MixedFan.Duct3);
	ductRun(&MixedFan.Duct4);
	mixerRun(&MixedFan.Mixer);
	MixedFan.fuelFlowA = MixedFan.fuelFlowAInput;		// 20230913+, liukai
	burnRun(&MixedFan.Afterburner);
	ductRun(&MixedFan.Duct5);
	nozzleRun(&MixedFan.Nozzle);
	MixedFan.LPS_Trq = MixedFan.Fan.y[5] + MixedFan.LPT.y[5] * MixedFan.LPS.effMech;
	shaftRun(&MixedFan.LPS);
	MixedFan.HPS_Trq = MixedFan.HPC.y[5] + MixedFan.HPT.y[5] * MixedFan.HPS.effMech;
	shaftRun(&MixedFan.HPS);

	MixedFan.errOut[0] = MixedFan.Fan.y[6];      //Fan_NErr
	MixedFan.errOut[1] = MixedFan.HPC.y[6];      //HPC_NErr
	MixedFan.errOut[2] = MixedFan.HPT.y[6];      //HPT_NErr
	MixedFan.errOut[3] = MixedFan.LPT.y[6];      //LPT_NErr
	MixedFan.errOut[4] = MixedFan.Mixer.y[5];    //Mixer_NErr_W1
	MixedFan.errOut[5] = MixedFan.Mixer.y[8];	 //Mixer_NErr_W2
	MixedFan.errOut[6] = MixedFan.Nozzle.y[2];   //Nozzle_Nerr
	MixedFan.errOut[7] = MixedFan.LPS.nDot / 10000.0;   //LPS_Nerr
	MixedFan.errOut[8] = MixedFan.HPS.nDot / 10000.0;   //HPS_Nerr


	for (i = 0; i < varDime; i++)
	{
		stepOut[i] = MixedFan.errOut[i];
	}
	engptr->eng = &MixedFan;

	return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanSetOldN(EngineMixedFan *eng)   //存储上一个时刻的转速值
{
  eng->LPS.nMechOld = *eng->LPS.nMech;
  eng->HPS.nMechOld = *eng->HPS.nMech;
  return 0;
}
//------------------------------------------------------------------------------
int engineMixedFanUnSteady(EngineMixedFan *eng)   //动态过程计算
{
  FILE *fOut;
  char *resultNameUnsteady = "MixedFan_unsteady.csv";
  int i = 0;
  int calCount = 0;
  int interpErr = -1;
  double stepIn[10], stepOut[10];
  EnginePointer *engptr = (EnginePointer *)malloc(sizeof(EnginePointer));

  MixedFan.isDynamic = 1;
  MixedFan.isDynamicCalculating = 0;
  MixedFan.timeNow = 0;

  MixedFan.fuelFlowInput = interp1Ac(MixedFan.timeVec,MixedFan.farVec,MixedFan.timeNow,MixedFan.timeVecDim,&interpErr);
  stepIn[0] = MixedFan.varStartInput[7];
  stepIn[1] = MixedFan.varStartInput[8];
  stepIn[2] = MixedFan.fuelFlowInput;
  stepIn[3] = MixedFan.Nozzle.areaThroatIn;
  DLLRunOneStep(stepIn, stepOut, engptr);

  if(MixedFan.convergeTag == 0)
  {
    fOut = fopen(resultNameUnsteady,"w");
    engineMixedFanOutPutHead(&MixedFan,fOut);
    engineMixedFanOutPutResult(&MixedFan,fOut);
    printf("第%lf秒计算完成！\n",MixedFan.timeNow);
  }
  else
  {
    printf("第%lf秒计算出错！\n",MixedFan.timeNow);
    MixedFan.isDynamic = 0;
    MixedFan.isDynamicCalculating = 0;
    MixedFan.timeNow = 0;
    return 0;
  }

  calCount = MixedFan.timeTotal / MixedFan.timeStep + 1.1;
  MixedFan.isDynamicCalculating = 1;
  for(i = 0;i < calCount;i++)
  {
    if(MixedFan.timeNow < MixedFan.timeTotal - MixedFan.accuracyReq)
    {
      MixedFan.timeNow = MixedFan.timeNow + MixedFan.timeStep;
	  MixedFan.LPS_Nmech = MixedFan.LPS_Nmech + stepOut[0] * MixedFan.timeStep;
	  MixedFan.HPS_Nmech = MixedFan.HPS_Nmech + stepOut[1] * MixedFan.timeStep;
      if(MixedFan.timeNow > MixedFan.timeTotal)
      {
        MixedFan.timeNow = MixedFan.timeTotal;
      }
    }
    else
    {
      break;
    }
    MixedFan.fuelFlowInput = interp1Ac(MixedFan.timeVec,MixedFan.farVec,MixedFan.timeNow,MixedFan.timeVecDim,&interpErr);
	stepIn[0] = MixedFan.LPS_Nmech;
	stepIn[1] = MixedFan.HPS_Nmech;
	stepIn[2] = MixedFan.fuelFlowInput;
	stepIn[3] = MixedFan.Nozzle.areaThroatIn;
	DLLRunOneStep(stepIn, stepOut, engptr);

    if(MixedFan.convergeTag == 0 || MixedFan.convergeTag == 1)
    {
      engineMixedFanOutPutResult(&MixedFan,fOut);
      printf("第%lf秒计算完成！\n",MixedFan.timeNow);
    }
    else
    {
		engineMixedFanOutPutResult(&MixedFan, fOut);
		printf("input: ");
		for (int j = 0; j < 7; j++)
		{
			printf("%f ", MixedFan.varStartStore[j]);
		}
		printf("%f %f %f\n", MixedFan.LPS_Nmech, MixedFan.HPS_Nmech, MixedFan.fuelFlowInput);
      printf("第%lf秒计算出错！\n",MixedFan.timeNow);
      MixedFan.isDynamic = 0;
      MixedFan.isDynamicCalculating = 0;
      MixedFan.timeNow = 0;
      fclose(fOut);
      return 0;
    }
  }

  MixedFan.isDynamic = 0;
  MixedFan.isDynamicCalculating = 0;
  MixedFan.timeNow = 0;
  printf("动态过程计算完成！\n",MixedFan.timeNow);
  fclose(fOut);
  return 0;
}

//------------------------------------------------------------------------------
extern _declspec(dllexport) int Init(double * Input, double * Output)
{
	int i = 0;
	double maxerr = 0;
	DLLInitial();

	double stepIn[100];
	double stepOut[20];
	for ( i = 0; i < 100; i++)
		stepIn[i] = 0;

	stepIn[2] = Input[2];
	stepIn[3] = Input[3];
	stepIn[5] = Input[5];
	stepIn[6] = Input[6];
	stepIn[9] = Input[9];
	EnginePointer *engptr = (EnginePointer*)malloc(sizeof(EnginePointer));
	DLLRunOnePoint(stepIn, stepOut, engptr);


	Output[0] = MixedFan.Ambient.gasPathOut[3];	// Pt2
	Output[1] = MixedFan.Ambient.gasPathOut[2];	// Tt2
	Output[2] = MixedFan.Fan.y[3];
	Output[3] = MixedFan.HPC.y[3];
	Output[4] = MixedFan.LPT.y[2];
	Output[5] = MixedFan.LPS_Nmech;
	Output[6] = MixedFan.HPS_Nmech;
	for (i = 0; i < 9; i++)
	{
		if (maxerr < fabs(MixedFan.errOut[i]))
			maxerr = fabs(MixedFan.errOut[i]);
	}
	for (i = 12; i < 16; i++)
	{
		if (maxerr < fabs(MixedFan.Mixer.y[i]))
			maxerr = fabs(MixedFan.Mixer.y[i]);
	}
	if (maxerr < fabs(MixedFan.Nozzle.y[16]))
		maxerr = fabs(MixedFan.Nozzle.y[16]);
	Output[7] = maxerr;
	Output[8] = MixedFan.timeNow;
	Output[9] = *(MixedFan.Fan.rLineIn);
	Output[10] = *(MixedFan.HPC.rLineIn);
	Output[11] = MixedFan.HPT.y[19];
	Output[12] = MixedFan.LPT.y[19];
	Output[13] = MixedFan.Fan.y[7];
	Output[14] = MixedFan.HPC.y[7];
	Output[15] = MixedFan.Nozzle.y[1];
	Output[16] = MixedFan.HPC.y[2];
	Output[17] = MixedFan.Fan.y[0];
	Output[18] = MixedFan.HPC.y[3] / MixedFan.HPC.u[3];

	return 1;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int Terminate()
{
	DLLFree();
	return 1;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int Onestep(double * Input, double * Output, double dt)
{
	int i = 0;
	int varDime = MixedFan.varVecDime - 2;
	double maxerr = 0;
	double NLdot, NHdot, NLz1, NHz1, NLdotz1, NHdotz1;

	MixedFan.fuelFlowInput = Input[2];
	MixedFan.Nozzle.areaThroatIn = Input[3];
	MixedFan.isDynamicCalculating = Input[4];
	MixedFan.LPS_Power = Input[5];
	MixedFan.HPS_Power = Input[6];
	MixedFan.Fan.alphaIn = Input[7];
	MixedFan.HPC.alphaIn = Input[8];
	MixedFan.fuelFlowAInput = Input[9];
	MixedFan.betaRVABI = 1;
	for (i = 0; i < 16; i++)
	{
		MixedFan.hlthparas[i] = 0;
	}
	MixedFan.timeStep = dt;

	NLz1 = MixedFan.LPS_Nmech;
	NHz1 = MixedFan.HPS_Nmech;
	NLdotz1 = MixedFan.LPS.nDot;
	NHdotz1 = MixedFan.HPS.nDot;
	MixedFan.LPS_Nmech = NLz1 + NLdotz1 * MixedFan.timeStep;
	MixedFan.HPS_Nmech = NHz1 + NHdotz1 * MixedFan.timeStep;
	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	MixedFan.LPS_Nmech = NLz1 + 0.5*(NLdotz1 + MixedFan.LPS.nDot) * MixedFan.timeStep;
	MixedFan.HPS_Nmech = NHz1 + 0.5*(NHdotz1 + MixedFan.HPS.nDot) * MixedFan.timeStep;
	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	Output[0] = MixedFan.Ambient.gasPathOut[3];	// Pt2
	Output[1] = MixedFan.Ambient.gasPathOut[2];	// Tt2
	Output[2] = MixedFan.Fan.y[3];
	Output[3] = MixedFan.HPC.y[3];
	Output[4] = MixedFan.LPT.y[2];
	Output[5] = MixedFan.LPS_Nmech;
	Output[6] = MixedFan.HPS_Nmech;
	for (i = 0; i < 9; i++)
	{
		if (maxerr < fabs(MixedFan.errOut[i]))
			maxerr = fabs(MixedFan.errOut[i]);
	}
	for (i = 12; i < 16; i++)
	{
		if (maxerr < fabs(MixedFan.Mixer.y[i]))
			maxerr = fabs(MixedFan.Mixer.y[i]);
	}
	if (maxerr < fabs(MixedFan.Nozzle.y[16]))
		maxerr = fabs(MixedFan.Nozzle.y[16]);
	Output[7] = maxerr;
	Output[8] = MixedFan.timeNow;
	Output[9] = *(MixedFan.Fan.rLineIn);
	Output[10] = *(MixedFan.HPC.rLineIn);
	Output[11] = MixedFan.HPT.y[19];
	Output[12] = MixedFan.LPT.y[19];
	Output[13] = MixedFan.Fan.y[7];
	Output[14] = MixedFan.HPC.y[7];
	Output[15] = MixedFan.Nozzle.y[1];
	Output[16] = MixedFan.HPC.y[2];
	Output[17] = MixedFan.Fan.y[0];
	Output[18] = MixedFan.HPC.y[3] / MixedFan.HPC.u[3];

	MixedFan.timeNow = MixedFan.timeNow + MixedFan.timeStep;
	return MixedFan.convergeTag;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int Zerostep_NLNHin(double * Input, double * Output, double dt)
{
	int i = 0;
	int varDime = MixedFan.varVecDime - 2;
	double maxerr = 0;
	double NLdot, NHdot, NLz1, NHz1, NLdotz1, NHdotz1;

	MixedFan.LPS_Nmech = Input[0];
	MixedFan.HPS_Nmech = Input[1];
	MixedFan.fuelFlowInput = Input[2];
	MixedFan.Nozzle.areaThroatIn = Input[3];
	MixedFan.isDynamicCalculating = Input[4];
	MixedFan.LPS_Power = Input[5];
	MixedFan.HPS_Power = Input[6];
	MixedFan.Fan.alphaIn = Input[7];
	MixedFan.HPC.alphaIn = Input[8];
	MixedFan.fuelFlowAInput = Input[9];
	MixedFan.betaRVABI = 1;
	for (i = 0; i < 16; i++)
	{
		MixedFan.hlthparas[i] = 0;
	}
	MixedFan.timeStep = dt;

	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);


	Output[0] = MixedFan.Ambient.gasPathOut[3];	// Pt2
	Output[1] = MixedFan.Ambient.gasPathOut[2];	// Tt2
	Output[2] = MixedFan.Fan.y[3];
	Output[3] = MixedFan.HPC.y[3];
	Output[4] = MixedFan.LPT.y[2];
	Output[5] = MixedFan.LPS_Nmech;
	Output[6] = MixedFan.HPS_Nmech;
	for (i = 0; i < 9; i++)
	{
		if (maxerr < fabs(MixedFan.errOut[i]))
			maxerr = fabs(MixedFan.errOut[i]);
	}
	for (i = 12; i < 16; i++)
	{
		if (maxerr < fabs(MixedFan.Mixer.y[i]))
			maxerr = fabs(MixedFan.Mixer.y[i]);
	}
	if (maxerr < fabs(MixedFan.Nozzle.y[16]))
		maxerr = fabs(MixedFan.Nozzle.y[16]);
	Output[7] = maxerr;
	Output[8] = MixedFan.timeNow;
	Output[9] = *(MixedFan.Fan.rLineIn);
	Output[10] = *(MixedFan.HPC.rLineIn);
	Output[11] = MixedFan.HPT.y[19];
	Output[12] = MixedFan.LPT.y[19];
	Output[13] = MixedFan.Fan.y[7];
	Output[14] = MixedFan.HPC.y[7];
	Output[15] = MixedFan.Nozzle.y[1];
	Output[16] = MixedFan.HPC.y[2];
	Output[17] = MixedFan.Fan.y[0];
	Output[18] = MixedFan.HPC.y[3] / MixedFan.HPC.u[3];

	return MixedFan.convergeTag;
}

//------------------------------------------------------------------------------
extern _declspec(dllexport) int Onestep1(double * Input, double * Output, EnginePointer *engptr, double dt)
{
	int i = 0;
	int varDime = MixedFan.varVecDime - 2;
	double maxerr = 0;
	double NLdot, NHdot, NLz1, NHz1, NLdotz1, NHdotz1;

	MixedFan.fuelFlowInput = Input[2];
	MixedFan.Nozzle.areaThroatIn = Input[3];
	MixedFan.isDynamicCalculating = Input[4];
	MixedFan.LPS_Power = Input[5];
	MixedFan.HPS_Power = Input[6];
	MixedFan.Fan.alphaIn = Input[7];
	MixedFan.HPC.alphaIn = Input[8];
	MixedFan.fuelFlowAInput = Input[9];
	MixedFan.betaRVABI = 1;
	for (i = 0; i < 16; i++)
	{
		MixedFan.hlthparas[i] = 0;
	}
	MixedFan.timeStep = dt;

	NLz1 = MixedFan.LPS_Nmech;
	NHz1 = MixedFan.HPS_Nmech;
	NLdotz1 = MixedFan.LPS.nDot;
	NHdotz1 = MixedFan.HPS.nDot;
	MixedFan.LPS_Nmech = NLz1 + NLdotz1 * MixedFan.timeStep;
	MixedFan.HPS_Nmech = NHz1 + NHdotz1 * MixedFan.timeStep;
	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	MixedFan.LPS_Nmech = NLz1 + 0.5*(NLdotz1 + MixedFan.LPS.nDot) * MixedFan.timeStep;
	MixedFan.HPS_Nmech = NHz1 + 0.5*(NHdotz1 + MixedFan.HPS.nDot) * MixedFan.timeStep;
	MixedFan.convergeTag = newtonSolver(MixedTurbofanRunTransientComponents,
		varDime,
		MixedFan.varStartStore, MixedFan.varMin, MixedFan.varMax, MixedFan.varDelLim,
		MixedFan.accuracyReq,
		MixedFan.distuFactor,
		MixedFan.maxIterations);

	Output[0] = MixedFan.Ambient.gasPathOut[3];	// Pt2
	Output[1] = MixedFan.Ambient.gasPathOut[2];	// Tt2
	Output[2] = MixedFan.Fan.y[3];
	Output[3] = MixedFan.HPC.y[3];
	Output[4] = MixedFan.LPT.y[2];
	Output[5] = MixedFan.LPS_Nmech;
	Output[6] = MixedFan.HPS_Nmech;
	for (i = 0; i < 9; i++)
	{
		if (maxerr < fabs(MixedFan.errOut[i]))
			maxerr = fabs(MixedFan.errOut[i]);
	}
	for (i = 12; i < 16; i++)
	{
		if (maxerr < fabs(MixedFan.Mixer.y[i]))
			maxerr = fabs(MixedFan.Mixer.y[i]);
	}
	if (maxerr < fabs(MixedFan.Nozzle.y[16]))
		maxerr = fabs(MixedFan.Nozzle.y[16]);
	Output[7] = maxerr;
	Output[8] = MixedFan.timeNow;
	Output[9] = *(MixedFan.Fan.rLineIn);
	Output[10] = *(MixedFan.HPC.rLineIn);
	Output[11] = MixedFan.HPT.y[19];
	Output[12] = MixedFan.LPT.y[19];
	Output[13] = MixedFan.Fan.y[7];
	Output[14] = MixedFan.HPC.y[7];
	Output[15] = MixedFan.Nozzle.y[1];
	Output[16] = MixedFan.HPC.y[2];
	Output[17] = MixedFan.Fan.y[0];
	Output[18] = MixedFan.HPC.y[3]/MixedFan.HPC.u[3];

	MixedFan.timeNow = MixedFan.timeNow + MixedFan.timeStep;
	engptr->eng = &MixedFan;
	return MixedFan.convergeTag;
}
//------------------------------------------------------------------------------
extern _declspec(dllexport) int SetPath(char * pathname)
{
	MixedFan.filePath = NULL;
	int i = strlen(pathname) + 1; 
	MixedFan.filePath = (char*)calloc(i, sizeof(char));
	strcpy(MixedFan.filePath, pathname);

	return 1;
}

//------------------------------------------------------------------------------
int engineMixedFanCalculate(EngineMixedFan *eng,int runMode)
{
  FILE *fOut;
  char *resultNameDes = "MixedFan_design.csv";
  char *resultNameSteady = "MixedFan_steady.csv";
  
//  char * pathname = "C:/工作/数发二期/01-程序/03-公开模型/";
//  SetPath(pathname);

  DLLInitial();
  MixedFan.altitude = 0;
  MixedFan.machNumber = 0;
  MixedFan.dTemperature = 0;

  double stepIn[100];
  double stepOut[20];
  for (int i = 0; i < 100; i++)
	  stepIn[i] = 0;

  double input[10] = { 13200,    18330,    0.485634323802285,       0.269610917923381,     0 , 0 , 0 ,  0 , 0,  1.76043765671702 };
  for (int i = 0; i < 10; i++)
	  stepIn[i] = input[i];
/*  double varIte0[9] = { 120.731,   0.6 , 0.8549 ,  0.5,   3.712,   2.498 ,  196277.26418391,   8880.0,  14619.0 };
  for (int i = 0; i < 9; i++)
	  stepIn[20 + i] = varIte0[i];*/
    
  EnginePointer *engptr = (EnginePointer*)malloc(sizeof(EnginePointer));
  DLLRunOnePoint(stepIn, stepOut, engptr);
  printf("Iterration variables: ");
  for (int i = 0; i <= 8; i++)
  {
	  printf("%f ", MixedFan.varIte[i]);
  }
  printf("\n");
  printf("Errors: ");
  for (int i = 0; i <= 8; i++)
  {
	  printf("%f ", MixedFan.errOut[i]);
  }
  printf("\n");
  printf("T: %f \n", MixedFan.Nozzle.y[1]);
  engineMixedFanFree(&MixedFan);

/*  if(runMode == -2)
  {
    engineMixedFanLink(&MixedFan);
    return 0;
  }

  if(runMode == -1)   //从文件初始化
  {
    if(MixedFan.isInitial == 1)  //若之前从文件初始化过，则释放之前申请的内存
    {
      engineMixedFanFree(&MixedFan);
    }
    engineMixedFanInitial(&MixedFan);
    return 0;
  }

  if(MixedFan.isInitial == 0 && runMode != 3)  //若之前没有从文本初始化，则自动初始化
  {
    engineMixedFanInitial(&MixedFan);
  }

  if(runMode == 0)    //设置设计点的iDes
  {
    engineMixedFanSetIdes(&MixedFan,0);
  }
  else                //设置非设计点的iDes
  {
    if(MixedFan.offDesignMode == 1 && !MixedFan.isDesOk)  //当需要使用设计点计算的参数时，判断是否计算过设计点
    {
      printf("请先计算设计点！\n");
      return 0;
    }
    engineMixedFanSetIdes(&MixedFan,MixedFan.offDesignMode);
  }

  if(runMode == 0)         //设计点计算
  {
    //MixedFan.farUse = MixedFan.farInput;    //
    engineMixedFanOnePoint(&MixedFan);
    if(MixedFan.convergeTag == 0)  //设计点计算收敛
    {
      MixedFan.isDesOk = 1;
      fOut = fopen(resultNameDes,"w");
      engineMixedFanOutPutHead(&MixedFan,fOut);
      engineMixedFanOutPutResult(&MixedFan,fOut);
      fclose(fOut);
      printf("设计点计算完成！\n");
    }
    else
    {
      printf("设计点计算出错！\n");
    }
  }
  else if(runMode == 1)     //稳态计算
  {

	  double stepIn[20];
	  double stepOut[20];
	  for (int i = 0; i < 20; i++)
		  stepIn[i] = 0;
	  stepIn[2] = 0.12865;
	  stepIn[3] = 0.15404;
	  stepIn[4] = 0;
	  EnginePointer *engptr = (EnginePointer*)malloc(sizeof(EnginePointer));
	  DLLInitial();
	  DLLRunOnePoint(stepIn, stepOut, engptr);
  }
  else if(runMode == 2)                     //动态计算
  {
  //  engineMixedFanUnSteady(&MixedFan);    //结果输出在函数内部
	  double stepIn[30];
	  double stepOut[20];
	  for (int i = 0; i < 20; i++)
		  stepIn[i] = 0;
	  stepIn[0] = 11632;
	  stepIn[1] = 16899;
	  stepIn[2] = 0.22354;
	  stepIn[3] = 0.14875;
	  stepIn[4] = 1;
	  EnginePointer *engptr = ( EnginePointer*)malloc(sizeof(EnginePointer));
	  DLLInitial();
	  DLLRunOneStep(stepIn, stepOut, engptr);
  }
  else if(runMode == 3)         //退出程序，释放内存
  {
    if(MixedFan.isInitial == 1)  //若之前从文件初始化过，则释放之前申请的内存
    {
      engineMixedFanFree(&MixedFan);
    }
  }*/
  return 0;
}
//------------------------------------------------------------------------------

