#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "engineUnmixedFan.h"
#include "functions_TMATS.h"
#include "newtonSolver.h"

EngineUnmixedFan JT9D;
//------------------------------------------------------------------------------
int engineUnmixedFanInitial(EngineUnmixedFan *eng)
{
  int i = 0;
  FILE *fModel;
  char *modelName = "JT9D.mdl";
  char name[100];
  char pathName[1000];

  eng->engineName = NULL;
  eng->timeVec = NULL;
  eng->farVec = NULL;
  eng->timeVecDim = 0;
  eng->noFlow =NULL;
  eng->noFlowWidth = 0;

  fModel = fopen(modelName,"r");
  fscanf(fModel,"%*[^=]=%s",name);
  i = strlen(name) + 1;  //加1为了存储最后的\0
  eng->engineName = (char*)calloc(i,sizeof(char));
  strcpy(eng->engineName,name);

  fscanf(fModel,"%*[^=]=%d",&eng->offDesignMode);
  //fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[0]);   //迭代变量，不读
  fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[1]);
  fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[2]);
  fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[3]);
  fscanf(fModel,"%*[^=]=%lf",&eng->InletGasPort[4]);

  fscanf(fModel,"%*[^=]=%lf",&eng->pAmbInput);
  fscanf(fModel,"%*[^=]=%lf",&eng->farInput);
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
  inletInitial(&eng->Inlet,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  compressorInitial(&eng->Fan,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  splitterInitial(&eng->Splitter,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct1,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  compressorInitial(&eng->LPC,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct2,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  compressorInitial(&eng->HPC,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  burnInitial(&eng->Burner,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->HPT,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct3,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  turbineInitial(&eng->LPT,fModel,name, pathName);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct4,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  nozzleInitial(&eng->Noz_core,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  ductInitial(&eng->Duct5,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  nozzleInitial(&eng->Noz_byp,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->LPS,fModel,name);

  fscanf(fModel,"%*[^=]=%s",name);
  shaftInitial(&eng->HPS,fModel,name);

  fclose(fModel);
  eng->isInitial = 1;
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanFree(EngineUnmixedFan *eng)
{
  if(eng->engineName != NULL)
    free(eng->engineName);
  if(eng->timeVec != NULL)
    free(eng->timeVec);
  if(eng->farVec != NULL)
    free(eng->farVec);

  inletFree(&eng->Inlet);
  compressorFree(&eng->Fan);
  splitterFree(&eng->Splitter);
  ductFree(&eng->Duct1);
  compressorFree(&eng->LPC);
  ductFree(&eng->Duct2);
  compressorFree(&eng->HPC);
  burnFree(&eng->Burner);
  turbineFree(&eng->HPT);
  ductFree(&eng->Duct3);
  turbineFree(&eng->LPT);
  ductFree(&eng->Duct4);
  nozzleFree(&eng->Noz_core);
  ductFree(&eng->Duct5);
  nozzleFree(&eng->Noz_byp);
  shaftFree(&eng->LPS);
  shaftFree(&eng->HPS);

  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanLink(EngineUnmixedFan *eng)
{
  eng->LPS.torqueIn = &eng->LPS_Trq;
  eng->LPS.powerTakeOff = &eng->LPS_Power;
  eng->LPS.nMech = &eng->LPS_Nmech;
  eng->LPS.timeStep = &eng->timeStep;

  eng->HPS.torqueIn = &eng->HPS_Trq;
  eng->HPS.powerTakeOff = &eng->HPS_Power;
  eng->HPS.nMech = &eng->HPS_Nmech;
  eng->HPS.timeStep = &eng->timeStep;

  eng->Inlet.gasPathIn = eng->InletGasPort;
  eng->Inlet.pAmbIn = &eng->pAmbInput;

  eng->Fan.gasPathIn = eng->Inlet.gasPathOut;
  eng->Fan.rLineIn  = &eng->Fan_Rline;
  eng->Fan.nMech  = eng->LPS.nMech;

  eng->Splitter.gasPathIn = &eng->Fan.y[0];
  eng->Splitter.BypassRatioIn = &eng->SplitterBPR;

  eng->Duct1.gasPathIn = eng->Splitter.gasPathOutMain;

  eng->LPC.gasPathIn = eng->Duct1.gasPathOut;
  eng->LPC.rLineIn = &eng->LPC_Rline;
  eng->LPC.nMech = eng->LPS.nMech;

  eng->Duct2.gasPathIn = &eng->LPC.y[0];

  eng->HPC.gasPathIn = eng->Duct2.gasPathOut;
  eng->HPC.rLineIn = &eng->HPC_Rline;
  eng->HPC.nMech =  eng->HPS.nMech;
  
  eng->Burner.fuelFlowIn = &eng->fuelFlow;
  eng->Burner.gasPathIn = &eng->HPC.y[0];

  eng->HPT.coolingFlow = eng->HPC.fractionalBleeds;
  //eng->HPT.coolingFlowWidth = &eng->HPC.fractionalBleeds[2500];
  eng->HPT.gasPathIn = &eng->Burner.y[0];
  eng->HPT.PressureRatioIn = &eng->HPT_PRin;
  eng->HPT.nMech = eng->HPS.nMech;

  eng->Duct3.gasPathIn = &eng->HPT.y[0];

  eng->LPT.coolingFlow = eng->noFlow;
  //eng->LPT.coolingFlowWidth = &eng->noFlowWidth;
  eng->LPT.gasPathIn = eng->Duct3.gasPathOut;
  eng->LPT.PressureRatioIn = &eng->LPT_PRin;
  eng->LPT.nMech = eng->LPS.nMech;

  eng->Duct4.gasPathIn = &eng->LPT.y[0];

  eng->Noz_core.gasPathIn = eng->Duct4.gasPathOut;
  eng->Noz_core.pAmbIn = &eng->pAmbInput;

  eng->Duct5.gasPathIn = eng->Splitter.gasPathOutBypass;

  eng->Noz_byp.gasPathIn = eng->Duct5.gasPathOut;
  eng->Noz_byp.pAmbIn = &eng->pAmbInput;

  eng->varIte[0] = &eng->InletGasPort[0];
  eng->varIte[1] = &eng->Fan_Rline;
  eng->varIte[2] = &eng->SplitterBPR;
  eng->varIte[3] = &eng->LPC_Rline;
  eng->varIte[4] = &eng->HPC_Rline;
  eng->varIte[5] = &eng->HPT_PRin;
  eng->varIte[6] = &eng->LPT_PRin;
  eng->varIte[7] = &eng->LPS_Nmech;
  eng->varIte[8] = &eng->HPS_Nmech;


  eng->errOut[0] = &eng->LPC.y[6];      //LPC_NErr
  eng->errOut[1] = &eng->Noz_byp.y[2];  //Noz_byp_NErr
  eng->errOut[2] = &eng->Fan.y[6];      //Fan_NErr
  eng->errOut[3] = &eng->HPC.y[6];      //HPC_NErr
  eng->errOut[4] = &eng->HPT.y[6];      //HPT_NErr
  eng->errOut[5] = &eng->LPT.y[6];      //LPT_NErr
  eng->errOut[6] = &eng->Noz_core.y[2]; //Noz_core_Nerr
  eng->errOut[7] = &eng->LPS.nDot;      //LPS_Ndot
  eng->errOut[8] = &eng->HPS.nDot;      //HPS_Ndot

  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanOutPutHead(EngineUnmixedFan *eng,FILE *fOut)
{
  if(eng->isDynamic == 1)
    fprintf(fOut,"time,");
  fprintf(fOut,"%s_WIn,",eng->engineName);
  fprintf(fOut,"%s_HtIn,",eng->engineName);
  fprintf(fOut,"%s_TtIn,",eng->engineName);
  fprintf(fOut,"%s_PtIn,",eng->engineName);
  fprintf(fOut,"%s_FarIn,",eng->engineName);
  fprintf(fOut,"%s_pAmb,",eng->engineName);
  fprintf(fOut,"%s_burnerFar,",eng->engineName);

  fprintf(fOut,"%s_varWin,",eng->engineName);
  fprintf(fOut,"%s_varFan_Rline,",eng->engineName);
  fprintf(fOut,"%s_varSplitterBPR,",eng->engineName);
  fprintf(fOut,"%s_varLPC_Rline,",eng->engineName);
  fprintf(fOut,"%s_varHPC_Rline,",eng->engineName);
  fprintf(fOut,"%s_varHPT_PRin,",eng->engineName);
  fprintf(fOut,"%s_varLPT_PRin,",eng->engineName);
  fprintf(fOut,"%s_varLPS_Nmech,",eng->engineName);
  fprintf(fOut,"%s_varHPS_Nmech,",eng->engineName);

  inletOutPutHead(&eng->Inlet,fOut);
  compressorOutPutHead(&eng->Fan,fOut);
  splitterOutPutHead(&eng->Splitter,fOut);
  ductOutPutHead(&eng->Duct1,fOut);
  compressorOutPutHead(&eng->LPC,fOut);
  ductOutPutHead(&eng->Duct2,fOut);
  compressorOutPutHead(&eng->HPC,fOut);
  burnOutPutHead(&eng->Burner,fOut);
  turbineOutPutHead(&eng->HPT,fOut);
  ductOutPutHead(&eng->Duct3,fOut);
  turbineOutPutHead(&eng->LPT,fOut);
  ductOutPutHead(&eng->Duct4,fOut);
  nozzleOutPutHead(&eng->Noz_core,fOut);
  ductOutPutHead(&eng->Duct5,fOut);
  nozzleOutPutHead(&eng->Noz_byp,fOut);
  shaftOutPutHead(&eng->LPS,fOut);
  shaftOutPutHead(&eng->HPS,fOut);

  fprintf(fOut,"\n");
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanOutPutResult(EngineUnmixedFan *eng,FILE *fOut)
{
  if(eng->isDynamic == 1)
    fprintf(fOut,"%lf,",eng->timeNow);
  fprintf(fOut,"%lf,",eng->InletGasPort[0]);
  fprintf(fOut,"%lf,",eng->InletGasPort[1]);
  fprintf(fOut,"%lf,",eng->InletGasPort[2]);
  fprintf(fOut,"%lf,",eng->InletGasPort[3]);
  fprintf(fOut,"%lf,",eng->InletGasPort[4]);
  fprintf(fOut,"%lf,",eng->pAmbInput);
  fprintf(fOut,"%lf,",eng->farUse);

  fprintf(fOut,"%lf,",eng->InletGasPort[0]);
  fprintf(fOut,"%lf,",eng->Fan_Rline);
  fprintf(fOut,"%lf,",eng->SplitterBPR);
  fprintf(fOut,"%lf,",eng->LPC_Rline);
  fprintf(fOut,"%lf,",eng->HPC_Rline);
  fprintf(fOut,"%lf,",eng->HPT_PRin);
  fprintf(fOut,"%lf,",eng->LPT_PRin);
  fprintf(fOut,"%lf,",eng->LPS_Nmech);
  fprintf(fOut,"%lf,",eng->HPS_Nmech);

  inletOutPutResult(&eng->Inlet,fOut);
  compressorOutPutResult(&eng->Fan,fOut);
  splitterOutPutResult(&eng->Splitter,fOut);
  ductOutPutResult(&eng->Duct1,fOut);
  compressorOutPutResult(&eng->LPC,fOut);
  ductOutPutResult(&eng->Duct2,fOut);
  compressorOutPutResult(&eng->HPC,fOut);
  burnOutPutResult(&eng->Burner,fOut);
  turbineOutPutResult(&eng->HPT,fOut);
  ductOutPutResult(&eng->Duct3,fOut);
  turbineOutPutResult(&eng->LPT,fOut);
  ductOutPutResult(&eng->Duct4,fOut);
  nozzleOutPutResult(&eng->Noz_core,fOut);
  ductOutPutResult(&eng->Duct5,fOut);
  nozzleOutPutResult(&eng->Noz_byp,fOut);
  shaftOutPutResult(&eng->LPS,fOut);
  shaftOutPutResult(&eng->HPS,fOut);

  fprintf(fOut,"\n");
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanRunOnce(EngineUnmixedFan *eng)
{
  inletRun(&eng->Inlet);
  compressorRun(&eng->Fan);
  splitterRun(&eng->Splitter);
  ductRun(&eng->Duct1);
  compressorRun(&eng->LPC);
  ductRun(&eng->Duct2);
  compressorRun(&eng->HPC);
  eng->fuelFlow = eng->HPC.y[0] * eng->farUse;
  burnRun(&eng->Burner);
  turbineRun(&eng->HPT);
  ductRun(&eng->Duct3);
  turbineRun(&eng->LPT);
  ductRun(&eng->Duct4);
  nozzleRun(&eng->Noz_core);
  ductRun(&eng->Duct5);
  nozzleRun(&eng->Noz_byp);
  eng->LPS_Trq = eng->Fan.y[5] + eng->LPC.y[5] + eng->LPT.y[5];
  shaftRun(&eng->LPS);
  eng->HPS_Trq = eng->HPC.y[5] + eng->HPT.y[5];
  shaftRun(&eng->HPS);
  return 0;
}
//------------------------------------------------------------------------------
int JT9D_RunOnce(double *varIn,double *errOut,int dime)
{
  int i = 0;
  for(i = 0;i < dime;i++)
  {
    *JT9D.varIte[i] = varIn[i];
    *JT9D.errOut[i] = 1;
  }

  engineUnmixedFanRunOnce(&JT9D);

  for(i = 0;i < dime;i++)
  {
    errOut[i] = *JT9D.errOut[i];
  }
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanOnePoint(EngineUnmixedFan *eng)   //稳态工作点计算
{
  int i = 0;
  if(eng->convergeTag != 0)  //若之前工作点没有收敛，则使用输入的初值；否则使用上次计算收敛的变量做为初值
  {
    for(i = 0;i < eng->varVecDime;i++)
    {
      eng->varStartStore[i] = eng->varStartInput[i];
    }
  }
  eng->convergeTag = newtonSolver(JT9D_RunOnce,
                     eng->varVecDime,
                     eng->varStartStore,eng->varMin,eng->varMax,eng->varDelLim,
                     eng->accuracyReq,
                     eng->distuFactor,
                     eng->maxIterations);

  if((eng->convergeTag != 0) && (i == 0))  //若该工作点没有收敛，并且第一次迭代没有使用输入的初值，则使用输入的初值再计算一次
  {
    for(i = 0;i < eng->varVecDime;i++)
    {
      eng->varStartStore[i] = eng->varStartInput[i];
    }
    eng->convergeTag = newtonSolver(JT9D_RunOnce,
                       eng->varVecDime,
                       eng->varStartStore,eng->varMin,eng->varMax,eng->varDelLim,
                       eng->accuracyReq,
                       eng->distuFactor,
                       eng->maxIterations);
  }
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanSetOldN(EngineUnmixedFan *eng)   //存储上一个时刻的转速值
{
  eng->LPS.nMechOld = *eng->LPS.nMech;
  eng->HPS.nMechOld = *eng->HPS.nMech;
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanUnSteady(EngineUnmixedFan *eng)   //动态过程计算
{
  FILE *fOut;
  char *resultNameUnsteady = "JT9D_unsteady.csv";
  int i = 0;
  int calCount = 0;
  int interpErr = -1;
  eng->isDynamic = 1;
  eng->isDynamicCalculating = 0;
  eng->timeNow = 0;

  eng->farUse = interp1Ac(eng->timeVec,eng->farVec,eng->timeNow,eng->timeVecDim,&interpErr);
  engineUnmixedFanOnePoint(eng);
  if(eng->convergeTag == 0)
  {
    engineUnmixedFanSetOldN(eng);
    fOut = fopen(resultNameUnsteady,"w");
    engineUnmixedFanOutPutHead(eng,fOut);
    engineUnmixedFanOutPutResult(eng,fOut);
    printf("第%lf秒计算完成！\n",eng->timeNow);
  }
  else
  {
    printf("第%lf秒计算出错！\n",eng->timeNow);
    eng->isDynamic = 0;
    eng->isDynamicCalculating = 0;
    eng->timeNow = 0;
    return 0;
  }

  calCount = eng->timeTotal / eng->timeStep + 1.1;
  eng->isDynamicCalculating = 1;
  for(i = 0;i < calCount;i++)
  {
    if(eng->timeNow < eng->timeTotal - eng->accuracyReq * eng->accuracyReq)
    {
      eng->timeNow = eng->timeNow + eng->timeStep;
      if(eng->timeNow > eng->timeTotal)
      {
        eng->timeNow = eng->timeTotal;
      }
    }
    else
    {
      break;
    }
    eng->farUse = interp1Ac(eng->timeVec,eng->farVec,eng->timeNow,eng->timeVecDim,&interpErr);
    engineUnmixedFanOnePoint(eng);
    if(eng->convergeTag == 0)
    {
      engineUnmixedFanSetOldN(eng);
      engineUnmixedFanOutPutResult(eng,fOut);
      printf("第%lf秒计算完成！\n",eng->timeNow);
    }
    else
    {
      printf("第%lf秒计算出错！\n",eng->timeNow);
      eng->isDynamic = 0;
      eng->isDynamicCalculating = 0;
      eng->timeNow = 0;
      fclose(fOut);
      return 0;
    }
  }

  eng->isDynamic = 0;
  eng->isDynamicCalculating = 0;
  eng->timeNow = 0;
  printf("动态过程计算完成！%f\n",eng->timeNow);
  fclose(fOut);
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanSetIdes(EngineUnmixedFan *eng,double iDes)
{
  if(iDes < 3)   //0-设计点；1-所有部件的iDes设为1；2-所有部件的iDes设为2
  {
    eng->Fan.compressorStruct.IDes = iDes;  //需要设置旋转部件、混合室和喷管的IDes
    eng->LPC.compressorStruct.IDes = iDes;
    eng->HPC.compressorStruct.IDes = iDes;
    eng->HPT.turbineStruct.IDes = iDes;
    eng->LPT.turbineStruct.IDes = iDes;
    eng->Noz_core.nozzleStruct.IDes = iDes;
    eng->Noz_byp.nozzleStruct.IDes = iDes;
  }
  else          //3-按照输入文件中的参数配置各部件的IDes
  {
    eng->Fan.compressorStruct.IDes = eng->Fan.IDesInput;
    eng->LPC.compressorStruct.IDes = eng->LPC.IDesInput;
    eng->HPC.compressorStruct.IDes = eng->HPC.IDesInput;
    eng->HPT.turbineStruct.IDes = eng->HPT.IDesInput;
    eng->LPT.turbineStruct.IDes = eng->LPT.IDesInput;
    eng->Noz_core.nozzleStruct.IDes = eng->Noz_core.IDesInput;
    eng->Noz_byp.nozzleStruct.IDes = eng->Noz_byp.IDesInput;
  }
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanSetInitial(EngineUnmixedFan *eng)
{
  eng->isInitial = 0;
  eng->isDesOk = 0;
  eng->isDynamic = 0;
  eng->isDynamicCalculating = 0;
  eng->timeNow = 0;
  eng->convergeTag = 1;
  return 0;
}
//------------------------------------------------------------------------------
int engineUnmixedFanCalculate(EngineUnmixedFan *eng,int runMode)
{
  FILE *fOut;
  char *resultNameDes = "JT9D_design.csv";
  char *resultNameSteady = "JT9D_steady.csv";
  if(runMode == -2)
  {
    engineUnmixedFanLink(eng);
    engineUnmixedFanSetInitial(eng);
    return 0;
  }
  if(runMode == -1)   //从文件初始化
  {
    if(eng->isInitial == 1)  //若之前从文件初始化过，则释放之前申请的内存
    {
      engineUnmixedFanFree(eng);
    }
    engineUnmixedFanInitial(eng);
    return 0;
  }
  if(eng->isInitial == 0 && runMode != 3)  //若之前没有从文本初始化，则自动初始化
  {
    engineUnmixedFanInitial(eng);
  }

  if(runMode == 0)    //设置设计点的iDes
  {
    engineUnmixedFanSetIdes(eng,0);
  }
  else                //设置非设计点的iDes
  {
    if(eng->offDesignMode == 1 && !eng->isDesOk)  //当需要使用设计点计算的参数时，判断是否计算过设计点
    {
      printf("请先计算设计点！\n");
      return 0;
    }
    engineUnmixedFanSetIdes(eng,eng->offDesignMode);
  }
  if(runMode == 0)         //设计点计算
  {
    eng->farUse = eng->farInput;
    engineUnmixedFanOnePoint(eng);
    if(eng->convergeTag == 0)  //设计点计算收敛
    {
      eng->isDesOk = 1;
      fOut = fopen(resultNameDes,"w");
      engineUnmixedFanOutPutHead(eng,fOut);
      engineUnmixedFanOutPutResult(eng,fOut);
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
    eng->farUse = eng->farInput;
    engineUnmixedFanOnePoint(eng);
    if(eng->convergeTag == 0)  //稳态计算收敛
    {
      fOut = fopen(resultNameSteady,"w");
      engineUnmixedFanOutPutHead(eng,fOut);
      engineUnmixedFanOutPutResult(eng,fOut);
      fclose(fOut);
      printf("稳态点计算完成！\n");
    }
    else
    {
      printf("稳态点计算出错！\n");
    }
  }
  else if(runMode == 2)                     //动态计算
  {
    engineUnmixedFanUnSteady(eng);    //结果输出在函数内部
  }
  else if(runMode == 3)         //退出程序，释放内存
  {
    if(eng->isInitial == 1)  //若之前从文件初始化过，则释放之前申请的内存
    {
      engineUnmixedFanFree(eng);
    }
  }
  return 0;
}
//------------------------------------------------------------------------------

