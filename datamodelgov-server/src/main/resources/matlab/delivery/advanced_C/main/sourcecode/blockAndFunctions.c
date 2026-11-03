 /*
 * =============================================================
 * 各部件的运行函数
 * =============================================================
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "blockAndFunctions.h"
#include "functions_TMATS.h"
#include "componentBody.h"
#include "constants_TMATS.h"

/*
 * 五次 smootherstep。与原来的分段线性低流量处理相比，该函数在两个
 * 端点的一、二阶导数均为零，可避免起动/停车求解中的残差和 Jacobian
 * 突变。
 */
static double pressureLossSmoothGate(double value)
{
  if(value <= 0.0)
    return 0.0;
  if(value >= 1.0)
    return 1.0;

  return value * value * value *
    (10.0 + value * (-15.0 + 6.0 * value));
}

//------------------------------------------------------------------------------
void pressureLossModelReset(PressureLossModel *model)
{
  if(model == NULL)
    return;

  memset(model, 0, sizeof(PressureLossModel));
}

//------------------------------------------------------------------------------
int pressureLossModelConfigure(
  PressureLossModel *model,
  double massFlowDes,
  double totalTemperatureDes,
  double totalPressureDes,
  double gateZeroFlowRatio,
  double gateFullFlowRatio)
{
  if(model == NULL || massFlowDes <= 0.0 || totalTemperatureDes <= 0.0 ||
    totalPressureDes <= 0.0 || gateZeroFlowRatio < 0.0 ||
    gateFullFlowRatio <= gateZeroFlowRatio)
    return -1;

  pressureLossModelReset(model);
  model->enabled = 1;
  model->massFlowDes = massFlowDes;
  model->totalTemperatureDes = totalTemperatureDes;
  model->totalPressureDes = totalPressureDes;
  model->gateZeroFlowRatio = gateZeroFlowRatio;
  model->gateFullFlowRatio = gateFullFlowRatio;
  return 0;
}

//------------------------------------------------------------------------------
double pressureLossModelEvaluate(
  PressureLossModel *model,
  double massFlow,
  double totalTemperature,
  double totalPressure,
  double nominalLossDes,
  double correctionLoss)
{
  double massFlowRatio;
  double correctedFlowRatio;
  double normalizedGateCoordinate;
  double gate;

  if(model == NULL || model->enabled == 0)
    return nominalLossDes + correctionLoss;

  /* 非正流量或非法热力状态按零流量处理，避免低流量端除零。 */
  if(massFlow <= 0.0 || totalTemperature <= 0.0 || totalPressure <= 0.0)
  {
    massFlowRatio = 0.0;
    correctedFlowRatio = 0.0;
  }
  else
  {
    massFlowRatio = massFlow / model->massFlowDes;
    correctedFlowRatio = massFlowRatio *
      sqrt(totalTemperature / model->totalTemperatureDes) *
      model->totalPressureDes / totalPressure;
  }

  normalizedGateCoordinate =
    (massFlowRatio - model->gateZeroFlowRatio) /
    (model->gateFullFlowRatio - model->gateZeroFlowRatio);
  gate = pressureLossSmoothGate(normalizedGateCoordinate);

  model->lastMassFlowRatio = massFlowRatio;
  model->lastCorrectedFlowRatio = correctedFlowRatio;
  model->lastGate = gate;
  model->lastNominalLoss = gate * nominalLossDes *
    correctedFlowRatio * correctedFlowRatio;
  /*
   * 名义压损始终使用平滑门控。旧常值健康修正沿用同一门控，从而
   * 保持调度关闭时的逐值回归。调度开启时，低流量衰减已经包含在
   * Delta(0)=-k_design 的增量节点及统一线性插值中，因此不得在这里
   * 再乘一次名义压损门，否则会造成重复衰减。
   */
  model->lastCorrectionLoss = model->correctionBypassNominalGate ?
    correctionLoss : gate * correctionLoss;
  model->lastTotalLoss = model->lastNominalLoss +
    model->lastCorrectionLoss;

  return model->lastTotalLoss;
}

/*
 * 在特性图中按完整节标题定位下一组数值。
 *
 * 旧实现使用形如 "%*[^MassFlow]Mass Flow%lf" 的字符排除式扫描。
 * 该写法并不是“查找字符串”，遇到 Gasturb 原始图中的说明行（例如
 * Standard/Booster）便会提前停止，随后把尺寸和数据数组读坏。逐行
 * 查找完整标题既兼容原有 MAP，也允许保留原始文件中的说明文字。
 */
static int compressorMapReadSectionValue(
  FILE *fMap,
  const char *sectionName,
  double *value)
{
  char line[512];
  char *sectionPosition;

  if (fMap == NULL || sectionName == NULL || value == NULL)
    return -1;

  while (fgets(line, sizeof(line), fMap) != NULL)
  {
    sectionPosition = strstr(line, sectionName);
    if (sectionPosition == NULL)
      continue;

    sectionPosition += strlen(sectionName);
    if (sscanf(sectionPosition, "%lf", value) == 1)
      return 0;

    return fscanf(fMap, "%lf", value) == 1 ? 0 : -1;
  }

  return -1;
}

//------------------------------------------------------------------------------
int turbineInitial(TurbineBlock *turbine,FILE *fIn,char *name, char *path)  //从文件初始化涡轮部件
{
  int i = 0,j = 0;
  double temp = 0;
  FILE *fMap;
  char mapName[100];
  char optionalSection[64];
  if (path != NULL)
  {
	  i = strlen(path);
	  if (i > 0)
		  strcpy(turbine->mapPath, path);
	  else
		  strcpy(turbine->mapPath, "");
  }
  else
  {
	  strcpy(turbine->mapPath, "");
  }

  turbine->turbineStruct.Y_T_NcVec = NULL;
  //turbine->turbineStruct.X_T_PRVec = NULL;
  turbine->turbineStruct.X_T_betaVec = NULL;
  turbine->turbineStruct.T_T_minPRVec = NULL;
  turbine->turbineStruct.T_T_maxPRVec = NULL;
  turbine->turbineStruct.T_T_Map_WcArray = NULL;
  turbine->turbineStruct.T_T_Map_EffArray = NULL;
  turbine->turbineStruct.T_T_Map_PRArray = NULL;
  turbine->turbineStruct.T_BldPos = NULL;
  turbine->turbineStruct.BlkNm = NULL;
  turbine->turbineStruct.IWork = NULL;

  turbine->turbineStruct.A = 0;
  turbine->turbineStruct.B = 0;
  turbine->turbineStruct.WcMapCol = 0;
  turbine->turbineStruct.EffMapCol = 0;
  turbine->turbineStruct.WcMapRw = 0;
  turbine->turbineStruct.EffMapRw = 0;
  turbine->turbineStruct.PRMapCol = 0;
  turbine->turbineStruct.PRMapRw = 0;
  /* Legacy maps use a linear beta-to-pressure-ratio relation. */
  turbine->turbineStruct.pressureBetaExponent = 1.0;

  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.NcDes);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.betaDes);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.EffDes);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.NDes);
  fscanf(fIn,"%*[^=]=%lf",&turbine->IDesInput);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.s_T_Nc);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.s_T_Wc);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.s_T_PR);
  fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.s_T_Eff);
  fscanf(fIn,"%*[^=]=%d",&turbine->turbineStruct.CoolFlwEn);
  fscanf(fIn,"%*[^=]=%d",&turbine->turbineStruct.BldPosLeng);
  turbine->coolingFlowWidth = turbine->turbineStruct.BldPosLeng * gasPathWidth;
  if(turbine->turbineStruct.BldPosLeng > 0)
  {
    turbine->turbineStruct.T_BldPos = (double*)calloc(turbine->turbineStruct.BldPosLeng,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&turbine->turbineStruct.T_BldPos[0]);
  }
  for(i = 1;i < turbine->turbineStruct.BldPosLeng;i++)
  {
    fscanf(fIn,"%lf",&turbine->turbineStruct.T_BldPos[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&turbine->turbineStruct.ConfigTurbine);

  i = strlen(name) + 1;  //加1为了存储最后的\0
  turbine->turbineStruct.BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(turbine->turbineStruct.BlkNm,name);
  turbine->turbineStruct.IWork = (int*)calloc(Er5 + 1,sizeof(int));

//  turbine->s_T_Nc_des = turbine->turbineStruct.s_T_Nc;
//  turbine->s_T_Wc_des = turbine->turbineStruct.s_T_Wc;
//  turbine->s_T_PR_des = turbine->turbineStruct.s_T_PR;
//  turbine->s_T_Eff_des = turbine->turbineStruct.s_T_Eff;

  fscanf(fIn,"%*[^=]=%s", mapName);   //读取特性图路径
  strcat(turbine->mapPath, mapName);
  fMap = fopen(turbine->mapPath,"r");         //开始读特性数据到相应的变量
  for(i = 0;i < 4;i++)  //读取雷诺数修正系数，本程序暂不支持该功能，先不存储
  {
    fscanf(fMap,"%*[^=]=%lf",&temp);
  }
  if (turbine->turbineStruct.ConfigTurbine < 0.5)		// 20230911+, liukai
	fscanf(fMap,"%*[^MinPressureRatio]Min Pressure Ratio%lf",&temp); //读取关键字
  else
	fscanf(fMap,"%*[^MinEnthalpyDrop]Min Enthalpy Drop%lf", &temp); //读取关键字
  i = temp;                  //提取关键字整数的部分
  i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示等转速线的条数
  turbine->turbineStruct.A = i;
  turbine->turbineStruct.Y_T_NcVec = (double*)calloc(turbine->turbineStruct.A,sizeof(double));
  for(i = 0;i < turbine->turbineStruct.A;i++)
  {
    fscanf(fMap,"%lf",&turbine->turbineStruct.Y_T_NcVec[i]);
  }
  fscanf(fMap,"%lf",&temp); //跳过最小压比数组之前的无意义数据，该数据的存在仅为了文本看起来整齐
  turbine->turbineStruct.T_T_minPRVec = (double*)calloc(turbine->turbineStruct.A,sizeof(double));
  for(i = 0;i < turbine->turbineStruct.A;i++)
  {
    fscanf(fMap,"%lf",&turbine->turbineStruct.T_T_minPRVec[i]);
  }
  if (turbine->turbineStruct.ConfigTurbine < 0.5)		// 20230911+, liukai
	fscanf(fMap,"%*[^MaxPressureRatio]Max Pressure Ratio%lf",&temp); //读取关键字，实际此时关键字和上一个关键字完全相同
  else
	fscanf(fMap,"%*[^MaxEnthalpyDrop]Max Enthalpy Drop%lf", &temp); //读取关键字
  for(i = 0;i < turbine->turbineStruct.A;i++)    //跳过该部分重复的转速数据
  {
    fscanf(fMap,"%lf",&temp);
  }
  fscanf(fMap,"%lf",&temp); //跳过最大压比数组之前的无意义数据，该数据的存在仅为了文本看起来整齐
  turbine->turbineStruct.T_T_maxPRVec = (double*)calloc(turbine->turbineStruct.A,sizeof(double));
  for(i = 0;i < turbine->turbineStruct.A;i++)
  {
    fscanf(fMap,"%lf",&turbine->turbineStruct.T_T_maxPRVec[i]);
  }
  fscanf(fMap,"%*[^MassFlow]Mass Flow%lf",&temp); //读取流量数组的关键字，关键字的整数==等转速线的数量+1
  i = temp;                  //提取关键字整数的部分
  i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示beta的个数
  turbine->turbineStruct.WcMapRw = turbine->turbineStruct.A;
  turbine->turbineStruct.WcMapCol = i;
  turbine->turbineStruct.B = i;
  turbine->turbineStruct.X_T_betaVec = (double*)calloc(turbine->turbineStruct.B,sizeof(double));
  turbine->turbineStruct.T_T_Map_WcArray = (double*)calloc(turbine->turbineStruct.WcMapRw * turbine->turbineStruct.WcMapCol,sizeof(double));
  for(i = 0;i < turbine->turbineStruct.B;i++)
  {
    fscanf(fMap,"%lf",&turbine->turbineStruct.X_T_betaVec[i]);
  }
  for(i = 0;i < turbine->turbineStruct.WcMapRw;i++)
  {
    fscanf(fMap,"%lf",&temp); //跳过每一组数据之前的转速值
    for(j = 0;j < turbine->turbineStruct.WcMapCol;j++)
    {
      fscanf(fMap,"%lf",&turbine->turbineStruct.T_T_Map_WcArray[i * turbine->turbineStruct.WcMapCol + j]);
    }
  }
  fscanf(fMap,"%*[^Efficiency]Efficiency%lf",&temp); //读取效率数组的关键字，关键字的整数==等转速线的数量+1
  turbine->turbineStruct.EffMapRw = turbine->turbineStruct.WcMapRw;
  turbine->turbineStruct.EffMapCol = turbine->turbineStruct.WcMapCol;
  turbine->turbineStruct.T_T_Map_EffArray = (double*)calloc(turbine->turbineStruct.EffMapRw * turbine->turbineStruct.EffMapCol,sizeof(double));
  for(i = 0;i < turbine->turbineStruct.B;i++)
  {
    fscanf(fMap,"%lf",&temp); //跳过效率矩阵的beta值，与流量矩阵的beta值相同
  }
  for(i = 0;i < turbine->turbineStruct.EffMapRw;i++)
  {
    fscanf(fMap,"%lf",&temp); //跳过每一组数据之前的转速值
    for(j = 0;j < turbine->turbineStruct.EffMapCol;j++)
    {
      fscanf(fMap,"%lf",&turbine->turbineStruct.T_T_Map_EffArray[i * turbine->turbineStruct.EffMapCol + j]);
    }
  }
  /*
   * Split-turbine maps may append a full pressure-ratio surface. Legacy maps
   * end after the efficiency table and therefore keep the endpoint mapping.
   */
  if (fscanf(fMap, "%63s", optionalSection) == 1 &&
      strcmp(optionalSection, "PressureRatioSurface") == 0)
  {
    fscanf(fMap, "%lf", &temp);
    i = temp;
    i = (int)((temp - i) * 1000 - 0.5);
    turbine->turbineStruct.PRMapRw = turbine->turbineStruct.A;
    turbine->turbineStruct.PRMapCol = i;
    if (turbine->turbineStruct.PRMapCol == turbine->turbineStruct.B)
    {
      turbine->turbineStruct.T_T_Map_PRArray = (double*)calloc(
        turbine->turbineStruct.PRMapRw * turbine->turbineStruct.PRMapCol,
        sizeof(double));
      for (i = 0; i < turbine->turbineStruct.PRMapCol; ++i)
        fscanf(fMap, "%lf", &temp);
      for (i = 0; i < turbine->turbineStruct.PRMapRw; ++i)
      {
        fscanf(fMap, "%lf", &temp);
        for (j = 0; j < turbine->turbineStruct.PRMapCol; ++j)
          fscanf(fMap, "%lf", &turbine->turbineStruct.T_T_Map_PRArray[
            i * turbine->turbineStruct.PRMapCol + j]);
      }
    }
  }
  fclose(fMap);
  return 0;
}
//------------------------------------------------------------------------------
int turbineRun(TurbineBlock *turbine)  //涡轮部件运行函数
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)               //读气流参数
  {
    turbine->u[i] = *(turbine->gasPathIn + i);
  }
  turbine->u[gasPathWidth + 0] = *(turbine->nMech);      //读机械转速
  turbine->u[gasPathWidth + 1] = *(turbine->PressureRatioIn);     //读beta值
  
  if(turbine->turbineStruct.IDes < 0.5) //实际设计点是计算以下缩放因子，以下操作仅为了初始化
  {
    turbine->u[gasPathWidth + 2] = turbine->s_T_Nc_des;
    turbine->u[gasPathWidth + 3] = turbine->s_T_Wc_des;
    turbine->u[gasPathWidth + 4] = turbine->s_T_PR_des;
    turbine->u[gasPathWidth + 5] = turbine->s_T_Eff_des;
  }
  else if((turbine->turbineStruct.IDes > 0.5) && (turbine->turbineStruct.IDes < 1.5))  //当iDes==1时，使用设计点计算的缩放因子
  {
    turbine->u[gasPathWidth + 2] = turbine->s_T_Nc_des;
    turbine->u[gasPathWidth + 3] = turbine->s_T_Wc_des;
    turbine->u[gasPathWidth + 4] = turbine->s_T_PR_des;
    turbine->u[gasPathWidth + 5] = turbine->s_T_Eff_des;
  }
  else  //当iDes==2时，使用输入的缩放因子
  {
    turbine->u[gasPathWidth + 2] = turbine->turbineStruct.s_T_Nc;
    turbine->u[gasPathWidth + 3] = turbine->turbineStruct.s_T_Wc;
    turbine->u[gasPathWidth + 4] = turbine->turbineStruct.s_T_PR;
    turbine->u[gasPathWidth + 5] = turbine->turbineStruct.s_T_Eff;
  }
  turbine->u[gasPathWidth + 6] = turbine->coolingFlowWidth;  //读引气数据维度
  turbine->u[gasPathWidth + 7] = *(turbine->hpW);
  turbine->u[gasPathWidth + 8] = *(turbine->hpEf);
  turbine->u[gasPathWidth + 9] = *(turbine->hpPR);
  turbine->u[gasPathWidth + 10] = turbine->Amean;
  turbine->u[gasPathWidth + 11] = turbine->Cmean;
  turbine->u[gasPathWidth + 12] = turbine->Kcla;
  turbine->u[gasPathWidth + 13] = turbine->Kwe;

  if (turbine->extSecAirSys < 0.5)
	  Turbine_TMATS_body(turbine->y,turbine->u,turbine->coolingFlow,&(turbine->turbineStruct));
  else
	  Turbine_TMATS_body(turbine->y, turbine->u, turbine->extCoolingFlow, &(turbine->turbineStruct));

  if(turbine->turbineStruct.IDes < 0.5) //保存设计点计算的缩放因子
  {
    turbine->s_T_Nc_des = turbine->y[7];
    turbine->s_T_Wc_des = turbine->y[8];
    turbine->s_T_PR_des = turbine->y[9];
    turbine->s_T_Eff_des = turbine->y[10];
  }
  return 0;
}
//------------------------------------------------------------------------------
int turbineFree(TurbineBlock *turbine)  //涡轮部件释放内存
{
  if(turbine->turbineStruct.Y_T_NcVec != NULL)
    free(turbine->turbineStruct.Y_T_NcVec);
  if(turbine->turbineStruct.X_T_betaVec != NULL)
    free(turbine->turbineStruct.X_T_betaVec);
  if(turbine->turbineStruct.T_T_minPRVec != NULL)
    free(turbine->turbineStruct.T_T_minPRVec);
  if(turbine->turbineStruct.T_T_maxPRVec != NULL)
    free(turbine->turbineStruct.T_T_maxPRVec);
  if(turbine->turbineStruct.T_T_Map_WcArray != NULL)
    free(turbine->turbineStruct.T_T_Map_WcArray);
  if(turbine->turbineStruct.T_T_Map_EffArray != NULL)
    free(turbine->turbineStruct.T_T_Map_EffArray);
  if(turbine->turbineStruct.T_T_Map_PRArray != NULL)
    free(turbine->turbineStruct.T_T_Map_PRArray);
  if(turbine->turbineStruct.T_BldPos != NULL)
    free(turbine->turbineStruct.T_BldPos);
  if(turbine->turbineStruct.BlkNm != NULL)
    free(turbine->turbineStruct.BlkNm);
  if(turbine->turbineStruct.IWork != NULL)
    free(turbine->turbineStruct.IWork);

  turbine->turbineStruct.Y_T_NcVec = NULL;
  turbine->turbineStruct.X_T_betaVec = NULL;
  turbine->turbineStruct.T_T_minPRVec = NULL;
  turbine->turbineStruct.T_T_maxPRVec = NULL;
  turbine->turbineStruct.T_T_Map_WcArray = NULL;
  turbine->turbineStruct.T_T_Map_EffArray = NULL;
  turbine->turbineStruct.T_T_Map_PRArray = NULL;
  turbine->turbineStruct.T_BldPos = NULL;
  turbine->turbineStruct.BlkNm = NULL;
  turbine->turbineStruct.IWork = NULL;
  return 0;
}
//------------------------------------------------------------------------------
int turbineOutPutHead(TurbineBlock *turbine,FILE *fOut)  //涡轮部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_HtOut,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_TtOut,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_PtOut,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_FarOut,",turbine->turbineStruct.BlkNm);

  fprintf(fOut,"%s_s_T_Nc,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_s_T_Wc,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_s_T_PR,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_s_T_Eff,",turbine->turbineStruct.BlkNm);

  fprintf(fOut,"%s_NcMap,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_WcMap,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_PrMap,",turbine->turbineStruct.BlkNm);
  fprintf(fOut,"%s_EffMap,",turbine->turbineStruct.BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int turbineOutPutResult(TurbineBlock *turbine,FILE *fOut)//涡轮部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",turbine->y[i]);
  }

  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 2]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 3]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 4]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 5]);

  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 9]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 10]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 11]);
  fprintf(fOut,"%lf,",turbine->y[gasPathWidth + 12]);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int burnInitial(BurnBlock *burn,FILE *fIn,char *name)  //从文件初始化燃烧室部件
{
  int i = 0;
  burn->BlkNm = NULL;
  pressureLossModelReset(&burn->pressureLossModel);
//  burn->burnStruct.IWork = NULL;

  fscanf(fIn,"%*[^=]=%lf",&burn->burnStruct.LHVEn);
  fscanf(fIn,"%*[^=]=%lf",&burn->burnStruct.LHV);
  fscanf(fIn,"%*[^=]=%lf",&burn->burnStruct.hFuel);
  fscanf(fIn,"%*[^=]=%lf",&burn->burnStruct.Eff);
  fscanf(fIn,"%*[^=]=%lf",&burn->burnStruct.dPnormBurnerH);	// 20230913+, liukai
  fscanf(fIn, "%*[^=]=%lf", &burn->burnStruct.dPnormBurnerC);	// 20230913+, liukai

  i = strlen(name) + 1;  //加1为了存储最后的\0
  burn->BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(burn->BlkNm,name);
//  burn->burnStruct.IWork = (int*)calloc(Er1 + 1,sizeof(int)); //燃烧室没有报错需求，不需要申请内存
  return 0;
}
//------------------------------------------------------------------------------
int burnRun(BurnBlock *burn)  //燃烧室部件运行函数
{
  int i = 0;
  double effectiveFuelFlow;
  double effectiveLoss;
  BurnStruct effectiveBurnStruct;
  const BurnStruct *burnStructToUse = &(burn->burnStruct);

  burn->u[0] = *(burn->fuelFlowIn);
  for(i = 1;i < (gasPathWidth + 1);i++)               //读气流参数
  {
    burn->u[i] = *(burn->gasPathIn + i - 1);
  }
  burn->u[gasPathWidth + 1] = *(burn->hpWf);
  burn->u[gasPathWidth + 2] = *(burn->hpEf);
  burn->u[gasPathWidth + 3] = *(burn->hpdP_Loss);

  if(burn->pressureLossModel.enabled != 0)
  {
    effectiveBurnStruct = burn->burnStruct;
    effectiveFuelFlow = burn->u[0] * (1.0 + burn->u[gasPathWidth + 1]);
    if(effectiveFuelFlow < 1.0e-5)
    {
      effectiveLoss = pressureLossModelEvaluate(
        &burn->pressureLossModel,
        burn->u[1], burn->u[3], burn->u[4],
        burn->burnStruct.dPnormBurnerC,
        burn->u[gasPathWidth + 3]);
      effectiveBurnStruct.dPnormBurnerC = effectiveLoss;
    }
    else
    {
      effectiveLoss = pressureLossModelEvaluate(
        &burn->pressureLossModel,
        burn->u[1], burn->u[3], burn->u[4],
        burn->burnStruct.dPnormBurnerH,
        burn->u[gasPathWidth + 3]);
      effectiveBurnStruct.dPnormBurnerH = effectiveLoss;
    }

    /* 有效损失已并入临时参数，避免 Burner 内部再次叠加健康修正。 */
    burn->u[gasPathWidth + 3] = 0.0;
    burnStructToUse = &effectiveBurnStruct;
  }

  Burner_TMATS_body(burn->y,burn->u,burnStructToUse);

  return 0;
}
//------------------------------------------------------------------------------
int burnFree(BurnBlock *burn)  //燃烧室部件释放内存
{
  if(burn->BlkNm != NULL)
    free(burn->BlkNm);
//  if(burn->burnStruct.IWork != NULL)
//    free(burn->burnStruct.IWork);
  return 0;
}
//------------------------------------------------------------------------------
int burnOutPutHead(BurnBlock *burn,FILE *fOut)  //燃烧室部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",burn->BlkNm);
  fprintf(fOut,"%s_HtOut,",burn->BlkNm);
  fprintf(fOut,"%s_TtOut,",burn->BlkNm);
  fprintf(fOut,"%s_PtOut,",burn->BlkNm);
  fprintf(fOut,"%s_FarOut,",burn->BlkNm);

  fprintf(fOut,"%s_fuelFlowIn,",burn->BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int burnOutPutResult(BurnBlock *burn,FILE *fOut)//燃烧室部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",burn->y[i]);
  }

  fprintf(fOut,"%lf,",*burn->fuelFlowIn);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int nozzleInitial(NozzleBlock *nozzle,FILE *fIn,char *name)  //从文件初始化喷管部件
{
  int i = 0;
  nozzle->nozzleStruct.Y_N_FARVec = NULL;
  nozzle->nozzleStruct.T_N_RtArray = NULL;
  nozzle->nozzleStruct.X_N_TtVec = NULL;
  nozzle->nozzleStruct.T_N_MAP_gammaArray = NULL;
  nozzle->nozzleStruct.X_N_PEQPaVec = NULL;
  nozzle->nozzleStruct.T_N_CdThArray = NULL;
  nozzle->nozzleStruct.T_N_CvArray = NULL;
  nozzle->nozzleStruct.T_N_CfgArray = NULL;
  nozzle->nozzleStruct.T_N_TGArray = NULL;
  nozzle->nozzleStruct.X_N_TtVecTG = NULL;
  nozzle->nozzleStruct.BlkNm = NULL;
  nozzle->nozzleStruct.IWork = NULL;

  nozzle->nozzleStruct.A = 0;
  nozzle->nozzleStruct.B = 0;
  nozzle->nozzleStruct.B1 = 0;
  nozzle->nozzleStruct.C = 0;

  fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.SwitchType);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->areaThroatIn);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->areaExitIn);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.flowLoss);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.IDes);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.WDes);
  fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.CfgEn);
  fscanf(fIn,"%*[^=]=%d",&nozzle->nozzleStruct.C);
  if(nozzle->nozzleStruct.C > 0)
  {
    nozzle->nozzleStruct.X_N_TtVecTG = (double*)calloc(nozzle->nozzleStruct.C,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.X_N_TtVecTG[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.C;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.X_N_TtVecTG[i]);
  }
  if(nozzle->nozzleStruct.C > 0)
  {
    nozzle->nozzleStruct.T_N_TGArray = (double*)calloc(nozzle->nozzleStruct.C,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_TGArray[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.C;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_TGArray[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&nozzle->nozzleStruct.B1);
  if(nozzle->nozzleStruct.B1 > 0)
  {
    nozzle->nozzleStruct.X_N_PEQPaVec = (double*)calloc(nozzle->nozzleStruct.B1,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.X_N_PEQPaVec[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.B1;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.X_N_PEQPaVec[i]);
  }
  if(nozzle->nozzleStruct.B1 > 0)
  {
    nozzle->nozzleStruct.T_N_CdThArray = (double*)calloc(nozzle->nozzleStruct.B1,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_CdThArray[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.B1;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_CdThArray[i]);
  }
  if(nozzle->nozzleStruct.B1 > 0)
  {
    nozzle->nozzleStruct.T_N_CvArray = (double*)calloc(nozzle->nozzleStruct.B1,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_CvArray[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.B1;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_CvArray[i]);
  }
  if(nozzle->nozzleStruct.B1 > 0)
  {
    nozzle->nozzleStruct.T_N_CfgArray = (double*)calloc(nozzle->nozzleStruct.B1,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_CfgArray[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.B1;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_CfgArray[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&nozzle->nozzleStruct.A);
  if(nozzle->nozzleStruct.A > 0)
  {
    nozzle->nozzleStruct.Y_N_FARVec = (double*)calloc(nozzle->nozzleStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.Y_N_FARVec[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.A;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.Y_N_FARVec[i]);
  }
  if(nozzle->nozzleStruct.A > 0)
  {
    nozzle->nozzleStruct.T_N_RtArray = (double*)calloc(nozzle->nozzleStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_RtArray[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.A;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_RtArray[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&nozzle->nozzleStruct.B);
  if(nozzle->nozzleStruct.B > 0)
  {
    nozzle->nozzleStruct.X_N_TtVec = (double*)calloc(nozzle->nozzleStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.X_N_TtVec[0]);
  }
  for(i = 1;i < nozzle->nozzleStruct.B;i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.X_N_TtVec[i]);
  }
  if((nozzle->nozzleStruct.A > 0) && (nozzle->nozzleStruct.B > 0))
  {
    nozzle->nozzleStruct.T_N_MAP_gammaArray = (double*)calloc(nozzle->nozzleStruct.A * nozzle->nozzleStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&nozzle->nozzleStruct.T_N_MAP_gammaArray[0]);
  }
  for(i = 1;i < (nozzle->nozzleStruct.A * nozzle->nozzleStruct.B);i++)
  {
    fscanf(fIn,"%lf",&nozzle->nozzleStruct.T_N_MAP_gammaArray[i]);
  }

  i = strlen(name) + 1;  //加1为了存储最后的\0
  nozzle->nozzleStruct.BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(nozzle->nozzleStruct.BlkNm,name);
  nozzle->nozzleStruct.IWork = (int*)calloc(Er16 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int nozzleRun(NozzleBlock *nozzle)  //喷管部件运行函数
{
  int i = 0;

  for(i = 0;i < gasPathWidth;i++)               //读气流参数
  {
    nozzle->u[i] = *(nozzle->gasPathIn + i);
  }
  nozzle->u[gasPathWidth + 0] = *(nozzle->pAmbIn);
  if(nozzle->nozzleStruct.IDes < 0.5)
  {
    nozzle->u[gasPathWidth + 1] = nozzle->areaThroatIn;
    nozzle->u[gasPathWidth + 2] = nozzle->areaExitIn;
  }
  else if((nozzle->nozzleStruct.IDes > 0.5) && (nozzle->nozzleStruct.IDes < 1.5))
  {
    nozzle->u[gasPathWidth + 1] = nozzle->areaThroatDes;
    nozzle->u[gasPathWidth + 2] = nozzle->areaExitDes;
  }
  else
  {
    nozzle->u[gasPathWidth + 1] = nozzle->areaThroatIn;
    nozzle->u[gasPathWidth + 2] = nozzle->areaExitIn;
  }
  nozzle->u[gasPathWidth + 3] = *(nozzle->hpA8);
  //jrt,20241106
  nozzle->u[gasPathWidth + 7] = *(nozzle->hpA9);

  nozzle->u[gasPathWidth + 4] = *(nozzle->fDrag);
  nozzle->u[gasPathWidth + 5] = nozzle->afterFVABI;
  if (nozzle->afterFVABI > 0.5)
	  nozzle->u[gasPathWidth + 6] = *(nozzle->betaFVABI);
  else
	  nozzle->u[gasPathWidth + 6] = 1;

  Nozzle_TMATS_body(nozzle->y,nozzle->u,&(nozzle->nozzleStruct));

  if(nozzle->nozzleStruct.IDes < 0.5)
  {
    nozzle->areaThroatDes = nozzle->y[3];
    nozzle->areaExitDes = nozzle->y[4];
  }
  return 0;
}
//------------------------------------------------------------------------------
int nozzleFree(NozzleBlock *nozzle)  //喷管部件释放内存
{
  if(nozzle->nozzleStruct.Y_N_FARVec != NULL)
    free(nozzle->nozzleStruct.Y_N_FARVec);
  if(nozzle->nozzleStruct.T_N_RtArray != NULL)
    free(nozzle->nozzleStruct.T_N_RtArray);
  if(nozzle->nozzleStruct.X_N_TtVec != NULL)
    free(nozzle->nozzleStruct.X_N_TtVec);
  if(nozzle->nozzleStruct.T_N_MAP_gammaArray != NULL)
    free(nozzle->nozzleStruct.T_N_MAP_gammaArray);
  if(nozzle->nozzleStruct.X_N_PEQPaVec != NULL)
    free(nozzle->nozzleStruct.X_N_PEQPaVec);
  if(nozzle->nozzleStruct.T_N_CdThArray != NULL)
    free(nozzle->nozzleStruct.T_N_CdThArray);
  if(nozzle->nozzleStruct.T_N_CvArray != NULL)
    free(nozzle->nozzleStruct.T_N_CvArray);
  if(nozzle->nozzleStruct.T_N_CfgArray != NULL)
    free(nozzle->nozzleStruct.T_N_CfgArray);
  if(nozzle->nozzleStruct.T_N_TGArray != NULL)
    free(nozzle->nozzleStruct.T_N_TGArray);
  if(nozzle->nozzleStruct.X_N_TtVecTG != NULL)
    free(nozzle->nozzleStruct.X_N_TtVecTG);
  if(nozzle->nozzleStruct.BlkNm != NULL)
    free(nozzle->nozzleStruct.BlkNm);
  if(nozzle->nozzleStruct.IWork != NULL)
    free(nozzle->nozzleStruct.IWork);
  return 0;
}
//------------------------------------------------------------------------------
int nozzleOutPutHead(NozzleBlock *nozzle,FILE *fOut)  //喷管部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",nozzle->nozzleStruct.BlkNm);
  fprintf(fOut,"%s_Fg,",nozzle->nozzleStruct.BlkNm);
  fprintf(fOut,"%s_Ath,",nozzle->nozzleStruct.BlkNm);
  fprintf(fOut,"%s_Aexit,",nozzle->nozzleStruct.BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int nozzleOutPutResult(NozzleBlock *nozzle,FILE *fOut)//喷管部件输出参数值至文件
{
  fprintf(fOut,"%lf,",nozzle->y[0]);
  fprintf(fOut,"%lf,",nozzle->y[1]);
  fprintf(fOut,"%lf,",nozzle->y[3]);
  fprintf(fOut,"%lf,",nozzle->y[4]);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int compressorInitial(CompressorBlock *compressor,FILE *fIn,char *name, char *path)  //从文件初始化压气机部件
{
  int i = 0,j = 0,k = 0;
  double temp = 0;
  FILE *fMap;
  char mapName[100];
  if (path != NULL)
  {
	  i = strlen(path);
	  if (i > 0)
		  strcpy(compressor->mapPath, path);
	  else
		  strcpy(compressor->mapPath, "");
  }
  else
  {
	  strcpy(compressor->mapPath, "");
  }

  compressor->compressorStruct.Y_C_Map_NcVec = NULL;
  compressor->compressorStruct.X_C_RlineVec = NULL;
  compressor->compressorStruct.Z_C_AlphaVec = NULL;
  compressor->compressorStruct.T_C_Map_WcArray = NULL;
  compressor->compressorStruct.T_C_Map_PRArray = NULL;
  compressor->compressorStruct.T_C_Map_EffArray = NULL;
  compressor->compressorStruct.FracCusBldht = NULL;
  compressor->compressorStruct.FracCusBldPt = NULL;
  compressor->compressorStruct.FracBldht = NULL;
  compressor->compressorStruct.FracBldPt = NULL;
  compressor->compressorStruct.FracBldPRecov = NULL;
  compressor->compressorStruct.X_C_Map_WcSurgeVec = NULL;
  compressor->compressorStruct.T_C_Map_PRSurgeVec = NULL;
  compressor->compressorStruct.BlkNm = NULL;
  compressor->compressorStruct.IWork = NULL;
  compressor->customerBleedsDemand = NULL;
  compressor->fractionalBleedsDemand = NULL;

  compressor->compressorStruct.A = 0;
  compressor->compressorStruct.B = 0;
  compressor->compressorStruct.C = 0;
  compressor->compressorStruct.D = 0;
  compressor->compressorStruct.WcMapCol = 0;
  compressor->compressorStruct.PRMapCol = 0;
  compressor->compressorStruct.EffMapCol = 0;
  compressor->compressorStruct.WcMapRw = 0;
  compressor->compressorStruct.PRMapRw = 0;
  compressor->compressorStruct.EffMapRw = 0;
  compressor->compressorStruct.WcMapLay = 0;
  compressor->compressorStruct.PRMapLay = 0;
  compressor->compressorStruct.EffMapLay = 0;

  // liukai + 加入空文件判断
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.NcDes);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.RlineDes);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.PRDes);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.EffDes);
  fscanf(fIn,"%*[^=]=%lf",&compressor->IDesInput);
  fscanf(fIn,"%*[^=]=%lf",&compressor->s_C_Nc_in);
  fscanf(fIn,"%*[^=]=%lf",&compressor->s_C_Wc_in);
  fscanf(fIn,"%*[^=]=%lf",&compressor->s_C_PR_in);
  fscanf(fIn,"%*[^=]=%lf",&compressor->s_C_Eff_in);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.CustBldEn);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.CustBldNm);
  compressor->customerBleeds[2500] = gasPathWidth * compressor->compressorStruct.CustBldNm;
  if(compressor->compressorStruct.CustBldNm > 0)
  {
    compressor->customerBleedsDemand = (double*)calloc(compressor->compressorStruct.CustBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->customerBleedsDemand[0]);
  }
  for(i = 1;i < compressor->compressorStruct.CustBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->customerBleedsDemand[i]);
  }
  if(compressor->compressorStruct.CustBldNm > 0)
  {
    compressor->compressorStruct.FracCusBldht = (double*)calloc(compressor->compressorStruct.CustBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FracCusBldht[0]);
  }
  for(i = 1;i < compressor->compressorStruct.CustBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->compressorStruct.FracCusBldht[i]);
  }
  if(compressor->compressorStruct.CustBldNm > 0)
  {
    compressor->compressorStruct.FracCusBldPt = (double*)calloc(compressor->compressorStruct.CustBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FracCusBldPt[0]);
  }
  for(i = 1;i < compressor->compressorStruct.CustBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->compressorStruct.FracCusBldPt[i]);
  }
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FBldEn);
  fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FracBldNm);
  compressor->fractionalBleeds[2500] = gasPathWidth * compressor->compressorStruct.FracBldNm;
  if(compressor->compressorStruct.FracBldNm > 0)
  {
    compressor->fractionalBleedsDemand = (double*)calloc(compressor->compressorStruct.FracBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->fractionalBleedsDemand[0]);
  }
  for(i = 1;i < compressor->compressorStruct.FracBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->fractionalBleedsDemand[i]);
  }
  if(compressor->compressorStruct.FracBldNm > 0)
  {
    compressor->compressorStruct.FracBldht = (double*)calloc(compressor->compressorStruct.FracBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FracBldht[0]);
  }
  for(i = 1;i < compressor->compressorStruct.FracBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->compressorStruct.FracBldht[i]);
  }
  if(compressor->compressorStruct.FracBldNm > 0)
  {
    compressor->compressorStruct.FracBldPt = (double*)calloc(compressor->compressorStruct.FracBldNm,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&compressor->compressorStruct.FracBldPt[0]);
  }
  for(i = 1;i < compressor->compressorStruct.FracBldNm;i++)
  {
    fscanf(fIn,"%lf",&compressor->compressorStruct.FracBldPt[i]);
  }
  if (compressor->compressorStruct.FracBldNm > 0)
  {
	  compressor->compressorStruct.FracBldPRecov = (double*)calloc(compressor->compressorStruct.FracBldNm, sizeof(double));
	  fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracBldPRecov[0]);
  }
  for (i = 1; i < compressor->compressorStruct.FracBldNm; i++)
  {
	  fscanf(fIn, "%lf", &compressor->compressorStruct.FracBldPRecov[i]);
  }

  i = strlen(name) + 1;  //加1为了存储最后的\0
  compressor->compressorStruct.BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(compressor->compressorStruct.BlkNm,name);
  compressor->compressorStruct.IWork = (int*)calloc(Er5 + 1,sizeof(int));

//  compressor->compressorStruct.s_C_Nc_des = compressor->compressorStruct.s_C_Nc_in;
//  compressor->compressorStruct.s_C_Wc_des = compressor->compressorStruct.s_C_Wc_in;
//  compressor->compressorStruct.s_C_PR_des = compressor->compressorStruct.s_C_PR_in;
//  compressor->compressorStruct.s_C_Eff_des = compressor->compressorStruct.s_C_Eff_in;

  fscanf(fIn,"%*[^=]=%d",&compressor->is3dMap);
  fscanf(fIn,"%*[^=]=%lf",&compressor->alphaIn);
  fscanf(fIn,"%*[^=]=%s", mapName);   //读取特性图路径
  strcat(compressor->mapPath, mapName);
  fMap = fopen(compressor->mapPath,"r");         //开始读特性数据到相应的变量
  for(i = 0;i < 4;i++)  //读取雷诺数修正系数，本程序暂不支持该功能，先不存储
  {
    fscanf(fMap,"%*[^=]=%lf",&temp);
  }
  if(compressor->is3dMap == 0)
  {
    if (compressorMapReadSectionValue(fMap, "Mass Flow", &temp) != 0)
      return -1;
    i = temp - 1;              //提取关键字整数的部分，此时i表示等转速线的条数
    compressor->compressorStruct.A = i;
    compressor->compressorStruct.WcMapRw = i;
    compressor->compressorStruct.PRMapRw = i;
    compressor->compressorStruct.EffMapRw = i;
    i++;
    i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示等beta线的条数
    compressor->compressorStruct.B = i;
    compressor->compressorStruct.WcMapCol = i;
    compressor->compressorStruct.PRMapCol = i;
    compressor->compressorStruct.EffMapCol = i;

    compressor->compressorStruct.X_C_RlineVec = (double*)calloc(compressor->compressorStruct.B,sizeof(double));
    for(i = 0;i < compressor->compressorStruct.B;i++)
    {
      fscanf(fMap,"%lf",&compressor->compressorStruct.X_C_RlineVec[i]);
    }
    compressor->compressorStruct.Y_C_Map_NcVec = (double*)calloc(compressor->compressorStruct.A,sizeof(double));
    compressor->compressorStruct.T_C_Map_WcArray = (double*)calloc(compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol,sizeof(double));
    for(i = 0;i < compressor->compressorStruct.WcMapRw;i++)
    {
      fscanf(fMap,"%lf",&compressor->compressorStruct.Y_C_Map_NcVec[i]);
      for(j = 0;j < compressor->compressorStruct.WcMapCol;j++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_WcArray[i * compressor->compressorStruct.WcMapCol + j]);
      }
    }

    if (compressorMapReadSectionValue(fMap, "Efficiency", &temp) != 0)
      return -1;
    for(i = 0;i < compressor->compressorStruct.B;i++)
    {
      fscanf(fMap,"%lf",&temp);
    }
    compressor->compressorStruct.T_C_Map_EffArray = (double*)calloc(compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol,sizeof(double));
    for(i = 0;i < compressor->compressorStruct.EffMapRw;i++)
    {
      fscanf(fMap,"%lf",&temp);
      for(j = 0;j < compressor->compressorStruct.EffMapCol;j++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_EffArray[i * compressor->compressorStruct.EffMapCol + j]);
      }
    }

    if (compressorMapReadSectionValue(fMap, "Pressure Ratio", &temp) != 0)
      return -1;
    for(i = 0;i < compressor->compressorStruct.B;i++)
    {
      fscanf(fMap,"%lf",&temp);
    }
    compressor->compressorStruct.T_C_Map_PRArray = (double*)calloc(compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol,sizeof(double));
    for(i = 0;i < compressor->compressorStruct.PRMapRw;i++)
    {
      fscanf(fMap,"%lf",&temp);
      for(j = 0;j < compressor->compressorStruct.PRMapCol;j++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_PRArray[i * compressor->compressorStruct.WcMapCol + j]);
      }
    }

    if (compressorMapReadSectionValue(fMap, "Surge Line", &temp) != 0)
      return -1;
    i = temp;                  //提取关键字整数的部分
    i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示喘振点的条数
    compressor->compressorStruct.D = i;
    compressor->compressorStruct.X_C_Map_WcSurgeVec = (double*)calloc(compressor->compressorStruct.D,sizeof(double));
    compressor->compressorStruct.T_C_Map_PRSurgeVec = (double*)calloc(compressor->compressorStruct.D,sizeof(double));
    for(i = 0;i < compressor->compressorStruct.D;i++)
    {
      fscanf(fMap,"%lf",&compressor->compressorStruct.X_C_Map_WcSurgeVec[i]);
    }
    fscanf(fMap,"%lf",&temp);
    for(i = 0;i < compressor->compressorStruct.D;i++)
    {
      fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_PRSurgeVec[i]);
    }
  }
  else
  {
    fscanf(fMap,"%*[^=]=%d",&compressor->compressorStruct.C); //读取角度数量
    compressor->compressorStruct.WcMapLay = compressor->compressorStruct.C;
    compressor->compressorStruct.PRMapLay = compressor->compressorStruct.C;
    compressor->compressorStruct.EffMapLay = compressor->compressorStruct.C;
    compressor->compressorStruct.Z_C_AlphaVec = (double*)calloc(compressor->compressorStruct.C,sizeof(double));
    for(k = 0;k < compressor->compressorStruct.C;k++)
    {
      fscanf(fMap,"%*[^=]=%lf",&compressor->compressorStruct.Z_C_AlphaVec[k]); //读取角度值
      fscanf(fMap,"%*[^MassFlow]Mass Flow%lf",&temp); //读取关键字
      if(k == 0)
      {
        i = temp - 1;              //提取关键字整数的部分，此时i表示等转速线的条数
        compressor->compressorStruct.A = i;
        compressor->compressorStruct.WcMapRw = i;
        compressor->compressorStruct.PRMapRw = i;
        compressor->compressorStruct.EffMapRw = i;
        i++;
        i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示等beta线的条数
        compressor->compressorStruct.B = i;
        compressor->compressorStruct.WcMapCol = i;
        compressor->compressorStruct.PRMapCol = i;
        compressor->compressorStruct.EffMapCol = i;

        compressor->compressorStruct.X_C_RlineVec = (double*)calloc(compressor->compressorStruct.B,sizeof(double));
        compressor->compressorStruct.Y_C_Map_NcVec = (double*)calloc(compressor->compressorStruct.A,sizeof(double));
        compressor->compressorStruct.T_C_Map_WcArray = (double*)calloc(compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol * compressor->compressorStruct.WcMapLay,sizeof(double));
        compressor->compressorStruct.T_C_Map_EffArray = (double*)calloc(compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol * compressor->compressorStruct.EffMapLay,sizeof(double));
        compressor->compressorStruct.T_C_Map_PRArray = (double*)calloc(compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol * compressor->compressorStruct.PRMapLay,sizeof(double));
      }
      for(i = 0;i < compressor->compressorStruct.B;i++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.X_C_RlineVec[i]);
      }
      for(i = 0;i < compressor->compressorStruct.WcMapRw;i++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.Y_C_Map_NcVec[i]);
        for(j = 0;j < compressor->compressorStruct.WcMapCol;j++)
        {
          fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_WcArray[i * compressor->compressorStruct.WcMapCol + j + k * (compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol)]);
        }
      }

      fscanf(fMap,"%*[^Efficiency]Efficiency%lf",&temp); //读取关键字
      for(i = 0;i < compressor->compressorStruct.B;i++)
      {
        fscanf(fMap,"%lf",&temp);
      }
      for(i = 0;i < compressor->compressorStruct.EffMapRw;i++)
      {
        fscanf(fMap,"%lf",&temp);
        for(j = 0;j < compressor->compressorStruct.EffMapCol;j++)
        {
          fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_EffArray[i * compressor->compressorStruct.EffMapCol + j + k * (compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol)]);
        }
      }

      fscanf(fMap,"%*[^PressureRatio]Pressure Ratio%lf",&temp); //读取关键字
      for(i = 0;i < compressor->compressorStruct.B;i++)
      {
        fscanf(fMap,"%lf",&temp);
      }
      for(i = 0;i < compressor->compressorStruct.PRMapRw;i++)
      {
        fscanf(fMap,"%lf",&temp);
        for(j = 0;j < compressor->compressorStruct.PRMapCol;j++)
        {
          fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_PRArray[i * compressor->compressorStruct.PRMapCol + j + k * (compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol)]);
        }
      }

      fscanf(fMap,"%*[^SurgeLine]Surge Line%lf",&temp); //读取关键字
      if(k == 0)
      {
        i = temp;                  //提取关键字整数的部分
        i = (temp - i)*1000 - 0.5; //提取关键字小数的部分，此时i表示喘振点的条数
        compressor->compressorStruct.D = i;
        compressor->compressorStruct.X_C_Map_WcSurgeVec = (double*)calloc(compressor->compressorStruct.D * compressor->compressorStruct.C,sizeof(double));
        compressor->compressorStruct.T_C_Map_PRSurgeVec = (double*)calloc(compressor->compressorStruct.D * compressor->compressorStruct.C,sizeof(double));
      }

      for(i = 0;i < compressor->compressorStruct.D;i++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.X_C_Map_WcSurgeVec[i * compressor->compressorStruct.C + k]);
      }
      fscanf(fMap,"%lf",&temp);
      for(i = 0;i < compressor->compressorStruct.D;i++)
      {
        fscanf(fMap,"%lf",&compressor->compressorStruct.T_C_Map_PRSurgeVec[i * compressor->compressorStruct.C + k ]);
      }
    }
  }
  fclose(fMap);
  return 0;
}
//------------------------------------------------------------------------------
int compressorFInitial(CompressorBlock *compressor, FILE *fIn, char *name, char *path)  //从文件初始化风扇部件
{
	int i = 0, j = 0, k = 0;
	double temp = 0;
	FILE *fMap;
	char mapName[100];
	if (path != NULL)
	{
		i = strlen(path);
		if (i > 0)
			strcpy(compressor->mapPath, path);
		else
			strcpy(compressor->mapPath, "");
	}
	else
	{
		strcpy(compressor->mapPath, "");
	}

	compressor->compressorStruct.Y_C_Map_NcVec = NULL;
	compressor->compressorStruct.X_C_RlineVec = NULL;
	compressor->compressorStruct.Z_C_AlphaVec = NULL;
	compressor->compressorStruct.T_C_Map_WcArray = NULL;
	compressor->compressorStruct.T_C_Map_PRArray = NULL;
	compressor->compressorStruct.T_C_Map_EffArray = NULL;
	compressor->compressorStruct.FracCusBldht = NULL;
	compressor->compressorStruct.FracCusBldPt = NULL;
	compressor->compressorStruct.FracBldht = NULL;
	compressor->compressorStruct.FracBldPt = NULL;
	compressor->compressorStruct.FracBldPRecov = NULL;
	compressor->compressorStruct.X_C_Map_WcSurgeVec = NULL;
	compressor->compressorStruct.T_C_Map_PRSurgeVec = NULL;
	compressor->compressorStruct.BlkNm = NULL;
	compressor->compressorStruct.IWork = NULL;
	compressor->customerBleedsDemand = NULL;
	compressor->fractionalBleedsDemand = NULL;

	compressor->compressorStruct.A = 0;
	compressor->compressorStruct.B = 0;
	compressor->compressorStruct.C = 0;
	compressor->compressorStruct.D = 0;
	compressor->compressorStruct.WcMapCol = 0;
	compressor->compressorStruct.PRMapCol = 0;
	compressor->compressorStruct.EffMapCol = 0;
	compressor->compressorStruct.WcMapRw = 0;
	compressor->compressorStruct.PRMapRw = 0;
	compressor->compressorStruct.EffMapRw = 0;
	compressor->compressorStruct.WcMapLay = 0;
	compressor->compressorStruct.PRMapLay = 0;
	compressor->compressorStruct.EffMapLay = 0;

	// liukai + 加入空文件判断
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.NcDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.RlineDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.PRDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.PRTipDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.EffDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.EffTipDes);
	fscanf(fIn, "%*[^=]=%lf", &compressor->IDesInput);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_Nc_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_Wc_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_PR_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_PRTip_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_Eff_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->s_C_EffTip_in);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.CustBldEn);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.CustBldNm);
	compressor->customerBleeds[2500] = gasPathWidth * compressor->compressorStruct.CustBldNm;
	if (compressor->compressorStruct.CustBldNm > 0)
	{
		compressor->customerBleedsDemand = (double*)calloc(compressor->compressorStruct.CustBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->customerBleedsDemand[0]);
	}
	for (i = 1; i < compressor->compressorStruct.CustBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->customerBleedsDemand[i]);
	}
	if (compressor->compressorStruct.CustBldNm > 0)
	{
		compressor->compressorStruct.FracCusBldht = (double*)calloc(compressor->compressorStruct.CustBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracCusBldht[0]);
	}
	for (i = 1; i < compressor->compressorStruct.CustBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->compressorStruct.FracCusBldht[i]);
	}
	if (compressor->compressorStruct.CustBldNm > 0)
	{
		compressor->compressorStruct.FracCusBldPt = (double*)calloc(compressor->compressorStruct.CustBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracCusBldPt[0]);
	}
	for (i = 1; i < compressor->compressorStruct.CustBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->compressorStruct.FracCusBldPt[i]);
	}
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FBldEn);
	fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracBldNm);
	compressor->fractionalBleeds[2500] = gasPathWidth * compressor->compressorStruct.FracBldNm;
	if (compressor->compressorStruct.FracBldNm > 0)
	{
		compressor->fractionalBleedsDemand = (double*)calloc(compressor->compressorStruct.FracBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->fractionalBleedsDemand[0]);
	}
	for (i = 1; i < compressor->compressorStruct.FracBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->fractionalBleedsDemand[i]);
	}
	if (compressor->compressorStruct.FracBldNm > 0)
	{
		compressor->compressorStruct.FracBldht = (double*)calloc(compressor->compressorStruct.FracBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracBldht[0]);
	}
	for (i = 1; i < compressor->compressorStruct.FracBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->compressorStruct.FracBldht[i]);
	}
	if (compressor->compressorStruct.FracBldNm > 0)
	{
		compressor->compressorStruct.FracBldPt = (double*)calloc(compressor->compressorStruct.FracBldNm, sizeof(double));
		fscanf(fIn, "%*[^=]=%lf", &compressor->compressorStruct.FracBldPt[0]);
	}
	for (i = 1; i < compressor->compressorStruct.FracBldNm; i++)
	{
		fscanf(fIn, "%lf", &compressor->compressorStruct.FracBldPt[i]);
	}

	i = strlen(name) + 1;  //加1为了存储最后的\0
	compressor->compressorStruct.BlkNm = (char*)calloc(i, sizeof(char));
	strcpy(compressor->compressorStruct.BlkNm, name);
	compressor->compressorStruct.IWork = (int*)calloc(Er5 + 1, sizeof(int));

	//  compressor->compressorStruct.s_C_Nc_des = compressor->compressorStruct.s_C_Nc_in;
	//  compressor->compressorStruct.s_C_Wc_des = compressor->compressorStruct.s_C_Wc_in;
	//  compressor->compressorStruct.s_C_PR_des = compressor->compressorStruct.s_C_PR_in;
	//  compressor->compressorStruct.s_C_Eff_des = compressor->compressorStruct.s_C_Eff_in;

	fscanf(fIn, "%*[^=]=%d", &compressor->is3dMap);
	fscanf(fIn, "%*[^=]=%lf", &compressor->alphaIn);
	fscanf(fIn, "%*[^=]=%s", mapName);   //读取特性图路径
	strcat(compressor->mapPath, mapName);
	fMap = fopen(compressor->mapPath, "r");         //开始读特性数据到相应的变量
	for (i = 0; i < 4; i++)  //读取雷诺数修正系数，本程序暂不支持该功能，先不存储
	{
		fscanf(fMap, "%*[^=]=%lf", &temp);
	}
	if (compressor->is3dMap == 0)
	{
		if (compressorMapReadSectionValue(fMap, "Mass Flow", &temp) != 0)
			return -1;
		i = temp - 1;              //提取关键字整数的部分，此时i表示等转速线的条数
		compressor->compressorStruct.A = i;
		compressor->compressorStruct.WcMapRw = i;
		compressor->compressorStruct.PRMapRw = i;
		compressor->compressorStruct.EffMapRw = i;
		i++;
		i = (temp - i) * 1000 - 0.5; //提取关键字小数的部分，此时i表示等beta线的条数
		compressor->compressorStruct.B = i;
		compressor->compressorStruct.WcMapCol = i;
		compressor->compressorStruct.PRMapCol = i;
		compressor->compressorStruct.EffMapCol = i;

		compressor->compressorStruct.X_C_RlineVec = (double*)calloc(compressor->compressorStruct.B, sizeof(double));
		for (i = 0; i < compressor->compressorStruct.B; i++)
		{
			fscanf(fMap, "%lf", &compressor->compressorStruct.X_C_RlineVec[i]);
		}
		compressor->compressorStruct.Y_C_Map_NcVec = (double*)calloc(compressor->compressorStruct.A, sizeof(double));
		compressor->compressorStruct.T_C_Map_WcArray = (double*)calloc(compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol, sizeof(double));
		for (i = 0; i < compressor->compressorStruct.WcMapRw; i++)
		{
			fscanf(fMap, "%lf", &compressor->compressorStruct.Y_C_Map_NcVec[i]);
			for (j = 0; j < compressor->compressorStruct.WcMapCol; j++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_WcArray[i * compressor->compressorStruct.WcMapCol + j]);
			}
		}

		if (compressorMapReadSectionValue(fMap, "Efficiency", &temp) != 0)
			return -1;
		for (i = 0; i < compressor->compressorStruct.B; i++)
		{
			fscanf(fMap, "%lf", &temp);
		}
		compressor->compressorStruct.T_C_Map_EffArray = (double*)calloc(compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol, sizeof(double));
		for (i = 0; i < compressor->compressorStruct.EffMapRw; i++)
		{
			fscanf(fMap, "%lf", &temp);
			for (j = 0; j < compressor->compressorStruct.EffMapCol; j++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_EffArray[i * compressor->compressorStruct.EffMapCol + j]);
			}
		}

		if (compressorMapReadSectionValue(fMap, "Pressure Ratio", &temp) != 0)
			return -1;
		for (i = 0; i < compressor->compressorStruct.B; i++)
		{
			fscanf(fMap, "%lf", &temp);
		}
		compressor->compressorStruct.T_C_Map_PRArray = (double*)calloc(compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol, sizeof(double));
		for (i = 0; i < compressor->compressorStruct.PRMapRw; i++)
		{
			fscanf(fMap, "%lf", &temp);
			for (j = 0; j < compressor->compressorStruct.PRMapCol; j++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_PRArray[i * compressor->compressorStruct.WcMapCol + j]);
			}
		}

		if (compressorMapReadSectionValue(fMap, "Surge Line", &temp) != 0)
			return -1;
		i = temp;                  //提取关键字整数的部分
		i = (temp - i) * 1000 - 0.5; //提取关键字小数的部分，此时i表示喘振点的条数
		compressor->compressorStruct.D = i;
		compressor->compressorStruct.X_C_Map_WcSurgeVec = (double*)calloc(compressor->compressorStruct.D, sizeof(double));
		compressor->compressorStruct.T_C_Map_PRSurgeVec = (double*)calloc(compressor->compressorStruct.D, sizeof(double));
		for (i = 0; i < compressor->compressorStruct.D; i++)
		{
			fscanf(fMap, "%lf", &compressor->compressorStruct.X_C_Map_WcSurgeVec[i]);
		}
		fscanf(fMap, "%lf", &temp);
		for (i = 0; i < compressor->compressorStruct.D; i++)
		{
			fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_PRSurgeVec[i]);
		}
	}
	else
	{
		fscanf(fMap, "%*[^=]=%d", &compressor->compressorStruct.C); //读取角度数量
		compressor->compressorStruct.WcMapLay = compressor->compressorStruct.C;
		compressor->compressorStruct.PRMapLay = compressor->compressorStruct.C;
		compressor->compressorStruct.EffMapLay = compressor->compressorStruct.C;
		compressor->compressorStruct.Z_C_AlphaVec = (double*)calloc(compressor->compressorStruct.C, sizeof(double));
		for (k = 0; k < compressor->compressorStruct.C; k++)
		{
			fscanf(fMap, "%*[^=]=%lf", &compressor->compressorStruct.Z_C_AlphaVec[k]); //读取角度值
			fscanf(fMap, "%*[^MassFlow]Mass Flow%lf", &temp); //读取关键字
			if (k == 0)
			{
				i = temp - 1;              //提取关键字整数的部分，此时i表示等转速线的条数
				compressor->compressorStruct.A = i;
				compressor->compressorStruct.WcMapRw = i;
				compressor->compressorStruct.PRMapRw = i;
				compressor->compressorStruct.EffMapRw = i;
				i++;
				i = (temp - i) * 1000 - 0.5; //提取关键字小数的部分，此时i表示等beta线的条数
				compressor->compressorStruct.B = i;
				compressor->compressorStruct.WcMapCol = i;
				compressor->compressorStruct.PRMapCol = i;
				compressor->compressorStruct.EffMapCol = i;

				compressor->compressorStruct.X_C_RlineVec = (double*)calloc(compressor->compressorStruct.B, sizeof(double));
				compressor->compressorStruct.Y_C_Map_NcVec = (double*)calloc(compressor->compressorStruct.A, sizeof(double));
				compressor->compressorStruct.T_C_Map_WcArray = (double*)calloc(compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol * compressor->compressorStruct.WcMapLay, sizeof(double));
				compressor->compressorStruct.T_C_Map_EffArray = (double*)calloc(compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol * compressor->compressorStruct.EffMapLay, sizeof(double));
				compressor->compressorStruct.T_C_Map_PRArray = (double*)calloc(compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol * compressor->compressorStruct.PRMapLay, sizeof(double));
			}
			for (i = 0; i < compressor->compressorStruct.B; i++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.X_C_RlineVec[i]);
			}
			for (i = 0; i < compressor->compressorStruct.WcMapRw; i++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.Y_C_Map_NcVec[i]);
				for (j = 0; j < compressor->compressorStruct.WcMapCol; j++)
				{
					fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_WcArray[i * compressor->compressorStruct.WcMapCol + j + k * (compressor->compressorStruct.WcMapRw * compressor->compressorStruct.WcMapCol)]);
				}
			}

			fscanf(fMap, "%*[^Efficiency]Efficiency%lf", &temp); //读取关键字
			for (i = 0; i < compressor->compressorStruct.B; i++)
			{
				fscanf(fMap, "%lf", &temp);
			}
			for (i = 0; i < compressor->compressorStruct.EffMapRw; i++)
			{
				fscanf(fMap, "%lf", &temp);
				for (j = 0; j < compressor->compressorStruct.EffMapCol; j++)
				{
					fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_EffArray[i * compressor->compressorStruct.EffMapCol + j + k * (compressor->compressorStruct.EffMapRw * compressor->compressorStruct.EffMapCol)]);
				}
			}

			fscanf(fMap, "%*[^PressureRatio]Pressure Ratio%lf", &temp); //读取关键字
			for (i = 0; i < compressor->compressorStruct.B; i++)
			{
				fscanf(fMap, "%lf", &temp);
			}
			for (i = 0; i < compressor->compressorStruct.PRMapRw; i++)
			{
				fscanf(fMap, "%lf", &temp);
				for (j = 0; j < compressor->compressorStruct.PRMapCol; j++)
				{
					fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_PRArray[i * compressor->compressorStruct.PRMapCol + j + k * (compressor->compressorStruct.PRMapRw * compressor->compressorStruct.PRMapCol)]);
				}
			}

			fscanf(fMap, "%*[^SurgeLine]Surge Line%lf", &temp); //读取关键字
			if (k == 0)
			{
				i = temp;                  //提取关键字整数的部分
				i = (temp - i) * 1000 - 0.5; //提取关键字小数的部分，此时i表示喘振点的条数
				compressor->compressorStruct.D = i;
				compressor->compressorStruct.X_C_Map_WcSurgeVec = (double*)calloc(compressor->compressorStruct.D * compressor->compressorStruct.C, sizeof(double));
				compressor->compressorStruct.T_C_Map_PRSurgeVec = (double*)calloc(compressor->compressorStruct.D * compressor->compressorStruct.C, sizeof(double));
			}

			for (i = 0; i < compressor->compressorStruct.D; i++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.X_C_Map_WcSurgeVec[i * compressor->compressorStruct.C + k]);
			}
			fscanf(fMap, "%lf", &temp);
			for (i = 0; i < compressor->compressorStruct.D; i++)
			{
				fscanf(fMap, "%lf", &compressor->compressorStruct.T_C_Map_PRSurgeVec[i * compressor->compressorStruct.C + k]);
			}
		}
	}
	fclose(fMap);
	return 0;
}
//------------------------------------------------------------------------------
int compressorRun(CompressorBlock *compressor)  //压气机部件运行函数
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    compressor->u[i] = *(compressor->gasPathIn + i);
  }
  compressor->u[gasPathWidth + 0] = *(compressor->nMech);      //读机械转速
  compressor->u[gasPathWidth + 1] = *(compressor->rLineIn);    //读beta值
  compressor->u[gasPathWidth + 2] = compressor->alphaIn;

  if(compressor->compressorStruct.IDes < 0.5)
  {
    compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_des;
    compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_des;
    compressor->u[gasPathWidth + 5] = compressor->s_C_PR_des;
    compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_des;
  }
  else if((compressor->compressorStruct.IDes > 0.5) && (compressor->compressorStruct.IDes < 1.5))
  {
    compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_des;
    compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_des;
    compressor->u[gasPathWidth + 5] = compressor->s_C_PR_des;
    compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_des;
  }
  else
  {
    compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_in;
    compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_in;
    compressor->u[gasPathWidth + 5] = compressor->s_C_PR_in;
    compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_in;
  }
  compressor->u[gasPathWidth + 7] = *(compressor->BypassRatioIn);
  compressor->u[gasPathWidth + 8] = *(compressor->hpW);
  compressor->u[gasPathWidth + 9] = *(compressor->hpEf);
  compressor->u[gasPathWidth + 12] = compressor->Amean;
  compressor->u[gasPathWidth + 13] = compressor->Cmean;
  compressor->u[gasPathWidth + 14] = compressor->Kcla;
  compressor->u[gasPathWidth + 15] = compressor->Kwe;
  compressor->u[gasPathWidth + 16] = *(compressor->hp_alf2W);
  compressor->u[gasPathWidth + 17] = *(compressor->hp_alf2PR);
  compressor->u[gasPathWidth + 18] = *(compressor->hp_alf2Ef);
  compressor->u[gasPathWidth + 19] = *(compressor->hpPR);

  // 20241108+, liukai
  for (i = 0; i < compressor->compressorStruct.FracBldNm; i++)
  {
	  compressor->u[gasPathWidth + 20 + i] = compressor->hpBldPRec[i];
	  compressor->u[gasPathWidth + 20 + (int)(compressor->compressorStruct.FracBldNm) + i] = compressor->hpWbld[i];
	  compressor->u[gasPathWidth + 20 + (int)(compressor->compressorStruct.FracBldNm)*2 + i] = compressor->hpBldht[i];
  }

  Compressor_TMATS_body(compressor->y,compressor->customerBleeds,compressor->fractionalBleeds,compressor->u,compressor->customerBleedsDemand,compressor->fractionalBleedsDemand,&(compressor->compressorStruct));

  if(compressor->compressorStruct.IDes < 0.5)
  {
    compressor->s_C_Nc_des = compressor->y[8];
    compressor->s_C_Wc_des = compressor->y[9];
    compressor->s_C_PR_des = compressor->y[10];
    compressor->s_C_Eff_des = compressor->y[11];
  }

  return 0;
}
//------------------------------------------------------------------------------
int compressorFRun(CompressorBlock *compressor)  //压气机部件运行函数
{
	int i = 0;
	for (i = 0; i < gasPathWidth; i++)
	{
		compressor->u[i] = *(compressor->gasPathIn + i);
	}
	compressor->u[gasPathWidth + 0] = *(compressor->nMech);      //读机械转速
	compressor->u[gasPathWidth + 1] = *(compressor->rLineIn);    //读beta值
	compressor->u[gasPathWidth + 2] = compressor->alphaIn;

	if (compressor->compressorStruct.IDes < 0.5)
	{
		compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_des;
		compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_des;
		compressor->u[gasPathWidth + 5] = compressor->s_C_PR_des;
		compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_des;
		compressor->u[gasPathWidth + 7] = compressor->s_C_PRTip_des;		// 20230914+, liukai
		compressor->u[gasPathWidth + 8] = compressor->s_C_EffTip_des;
	}
	else if ((compressor->compressorStruct.IDes > 0.5) && (compressor->compressorStruct.IDes < 1.5))
	{
		compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_des;
		compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_des;
		compressor->u[gasPathWidth + 5] = compressor->s_C_PR_des;
		compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_des;
		compressor->u[gasPathWidth + 7] = compressor->s_C_PRTip_des;		// 20230914+, liukai
		compressor->u[gasPathWidth + 8] = compressor->s_C_EffTip_des;
	}
	else
	{
		compressor->u[gasPathWidth + 3] = compressor->s_C_Nc_in;
		compressor->u[gasPathWidth + 4] = compressor->s_C_Wc_in;
		compressor->u[gasPathWidth + 5] = compressor->s_C_PR_in;
		compressor->u[gasPathWidth + 6] = compressor->s_C_Eff_in;
		compressor->u[gasPathWidth + 7] = compressor->s_C_PRTip_in;		// 20230914+, liukai
		compressor->u[gasPathWidth + 8] = compressor->s_C_EffTip_in;
	}
	compressor->u[gasPathWidth + 9] = *(compressor->BypassRatioIn);
	compressor->u[gasPathWidth + 10] = *(compressor->hpW);
	compressor->u[gasPathWidth + 11] = *(compressor->hpEf);
	compressor->u[gasPathWidth + 12] = compressor->Amean;
	compressor->u[gasPathWidth + 13] = compressor->Cmean;
	compressor->u[gasPathWidth + 14] = compressor->Kcla;
	compressor->u[gasPathWidth + 15] = compressor->Kwe;
	compressor->u[gasPathWidth + 16] = compressor->AFT*(1+*(compressor->hpAFT));
	// jrt,20241105
	compressor->u[gasPathWidth + 17] = *(compressor->hpPR_TipRootRatio);
	compressor->u[gasPathWidth + 18] = *(compressor->hpEf_TipRootRatio);

	compressor->u[gasPathWidth + 19] = *(compressor->hp_alf2W);
	compressor->u[gasPathWidth + 20] = *(compressor->hp_alf2PR);
	compressor->u[gasPathWidth + 21] = *(compressor->hp_alf2Ef);
	compressor->u[gasPathWidth + 22] = *(compressor->hpPR);

	CompressorF_TMATS_body(compressor->y, compressor->customerBleeds, compressor->fractionalBleeds, compressor->u, compressor->customerBleedsDemand, compressor->fractionalBleedsDemand, &(compressor->compressorStruct));

	if (compressor->compressorStruct.IDes < 0.5)
	{
		compressor->s_C_Nc_des = compressor->y[8];
		compressor->s_C_Wc_des = compressor->y[9];
		compressor->s_C_PR_des = compressor->y[10];
		compressor->s_C_Eff_des = compressor->y[11];
		compressor->s_C_PRTip_des = compressor->y[24];
		compressor->s_C_EffTip_des = compressor->y[25];
	}

	return 0;
}
//------------------------------------------------------------------------------
int compressorFree(CompressorBlock *compressor)  //压气机部件释放内存
{
  if(compressor->customerBleedsDemand != NULL)
    free(compressor->customerBleedsDemand);
  if(compressor->fractionalBleedsDemand != NULL)
    free(compressor->fractionalBleedsDemand);
  if(compressor->compressorStruct.Y_C_Map_NcVec !=NULL)
    free(compressor->compressorStruct.Y_C_Map_NcVec);
  if(compressor->compressorStruct.X_C_RlineVec !=NULL)
    free(compressor->compressorStruct.X_C_RlineVec);
  if(compressor->compressorStruct.Z_C_AlphaVec !=NULL)
    free(compressor->compressorStruct.Z_C_AlphaVec);
  if(compressor->compressorStruct.T_C_Map_WcArray !=NULL)
    free(compressor->compressorStruct.T_C_Map_WcArray);
  if(compressor->compressorStruct.T_C_Map_PRArray !=NULL)
    free(compressor->compressorStruct.T_C_Map_PRArray);
  if(compressor->compressorStruct.T_C_Map_EffArray !=NULL)
    free(compressor->compressorStruct.T_C_Map_EffArray);
  if(compressor->compressorStruct.FracCusBldht !=NULL)
    free(compressor->compressorStruct.FracCusBldht);
  if(compressor->compressorStruct.FracCusBldPt !=NULL)
    free(compressor->compressorStruct.FracCusBldPt);
  if(compressor->compressorStruct.FracBldht !=NULL)
    free(compressor->compressorStruct.FracBldht);
  if(compressor->compressorStruct.FracBldPt !=NULL)
    free(compressor->compressorStruct.FracBldPt);
  if (compressor->compressorStruct.FracBldPRecov != NULL)
	  free(compressor->compressorStruct.FracBldPRecov);
  if(compressor->compressorStruct.X_C_Map_WcSurgeVec !=NULL)
    free(compressor->compressorStruct.X_C_Map_WcSurgeVec);
  if(compressor->compressorStruct.T_C_Map_PRSurgeVec !=NULL)
    free(compressor->compressorStruct.T_C_Map_PRSurgeVec);
  if(compressor->compressorStruct.BlkNm !=NULL)
    free(compressor->compressorStruct.BlkNm);
  if(compressor->compressorStruct.IWork !=NULL)
    free(compressor->compressorStruct.IWork);

  compressor->customerBleedsDemand = NULL;
  compressor->fractionalBleedsDemand = NULL;
  compressor->compressorStruct.Y_C_Map_NcVec = NULL;
  compressor->compressorStruct.X_C_RlineVec = NULL;
  compressor->compressorStruct.Z_C_AlphaVec = NULL;
  compressor->compressorStruct.T_C_Map_WcArray = NULL;
  compressor->compressorStruct.T_C_Map_PRArray = NULL;
  compressor->compressorStruct.T_C_Map_EffArray = NULL;
  compressor->compressorStruct.FracCusBldht = NULL;
  compressor->compressorStruct.FracCusBldPt = NULL;
  compressor->compressorStruct.FracBldht = NULL;
  compressor->compressorStruct.FracBldPt = NULL;
  compressor->compressorStruct.FracBldPRecov = NULL;
  compressor->compressorStruct.X_C_Map_WcSurgeVec = NULL;
  compressor->compressorStruct.T_C_Map_PRSurgeVec = NULL;
  compressor->compressorStruct.BlkNm = NULL;
  compressor->compressorStruct.IWork = NULL;
  return 0;
}
//------------------------------------------------------------------------------
int compressorOutPutHead(CompressorBlock *compressor,FILE *fOut)  //压气机部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_HtOut,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_TtOut,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_PtOut,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_FarOut,",compressor->compressorStruct.BlkNm);

  fprintf(fOut,"%s_s_C_Nc,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_s_C_Wc,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_s_C_PR,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_s_C_Eff,",compressor->compressorStruct.BlkNm);

  fprintf(fOut,"%s_NcMap,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_WcMap,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_PrMap,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_EffMap,",compressor->compressorStruct.BlkNm);
  fprintf(fOut,"%s_SMavail,",compressor->compressorStruct.BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int compressorOutPutResult(CompressorBlock *compressor,FILE *fOut)//压气机部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",compressor->y[i]);
  }

  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 3]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 4]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 5]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 6]);

  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 10]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 11]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 12]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 13]);
  fprintf(fOut,"%lf,",compressor->y[gasPathWidth + 2]);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int mixerInitial(MixerBlock *mixer,FILE *fIn,char *name)  //从文件初始化混合室部件
{
  int i = 0;
  mixer->mixerStruct.Y_M_FARVec = NULL;
  mixer->mixerStruct.X_M_TVec = NULL;
  mixer->mixerStruct.T_M_RtArray = NULL;
  mixer->mixerStruct.T_M_gammaArray = NULL;
  mixer->mixerStruct.BlkNm = NULL;
  mixer->mixerStruct.IWork = NULL;

  mixer->mixerStruct.A = 0;
  mixer->mixerStruct.B = 0;

  fscanf(fIn,"%*[^=]=%lf",&mixer->Aphy1In);
  fscanf(fIn,"%*[^=]=%lf",&mixer->Aphy2In);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.s_M_Imp1);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.s_M_Imp2);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.s_M_V1);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.s_M_V2);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.BPRdes);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.IDes);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.SWPS);
  fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.MNp);

  fscanf(fIn,"%*[^=]=%d",&mixer->mixerStruct.A);
  if(mixer->mixerStruct.A > 0)
  {
    mixer->mixerStruct.Y_M_FARVec = (double*)calloc(mixer->mixerStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.Y_M_FARVec[0]);
  }
  for(i = 1;i < mixer->mixerStruct.A;i++)
  {
    fscanf(fIn,"%lf",&mixer->mixerStruct.Y_M_FARVec[i]);
  }
  if(mixer->mixerStruct.A > 0)
  {
    mixer->mixerStruct.T_M_RtArray = (double*)calloc(mixer->mixerStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.T_M_RtArray[0]);
  }
  for(i = 1;i < mixer->mixerStruct.A;i++)
  {
    fscanf(fIn,"%lf",&mixer->mixerStruct.T_M_RtArray[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&mixer->mixerStruct.B);
  if(mixer->mixerStruct.B > 0)
  {
    mixer->mixerStruct.X_M_TVec = (double*)calloc(mixer->mixerStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.X_M_TVec[0]);
  }
  for(i = 1;i < mixer->mixerStruct.B;i++)
  {
    fscanf(fIn,"%lf",&mixer->mixerStruct.X_M_TVec[i]);
  }
  if(mixer->mixerStruct.A * mixer->mixerStruct.B > 0)
  {
    mixer->mixerStruct.T_M_gammaArray = (double*)calloc(mixer->mixerStruct.A * mixer->mixerStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&mixer->mixerStruct.T_M_gammaArray[0]);
  }
  for(i = 1;i < mixer->mixerStruct.A * mixer->mixerStruct.B;i++)
  {
    fscanf(fIn,"%lf",&mixer->mixerStruct.T_M_gammaArray[i]);
  }

  i = strlen(name) + 1;  //加1为了存储最后的\0
  mixer->mixerStruct.BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(mixer->mixerStruct.BlkNm,name);
  mixer->mixerStruct.IWork = (int*)calloc(Er17 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int mixerRun(MixerBlock *mixer)  //混合室部件运行函数
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)      //读气流1参数
  {
    mixer->u[i] = *(mixer->gasPathIn1 + i);
  }
  for(i = 0;i < gasPathWidth;i++)      //读气流2参数
  {
    mixer->u[gasPathWidth + i] = *(mixer->gasPathIn2 + i);
  }

  if(mixer->mixerStruct.IDes < 0.5)
  {
    mixer->mixerStruct.Aphy1In = mixer->Aphy1Des;
    mixer->mixerStruct.Aphy2In = mixer->Aphy2Des;
  }
  else if((mixer->mixerStruct.IDes > 0.5) && (mixer->mixerStruct.IDes < 1.5))
  {
    mixer->mixerStruct.Aphy1In = mixer->Aphy1Des;
    mixer->mixerStruct.Aphy2In = mixer->Aphy2Des;
  }
  else
  {
    mixer->mixerStruct.Aphy1In = mixer->Aphy1In;
    mixer->mixerStruct.Aphy2In = mixer->Aphy2In;
  }
  mixer->u[gasPathWidth+gasPathWidth] = *(mixer->MixerPs);
  mixer->u[gasPathWidth + gasPathWidth + 1] = (*mixer->isDynamicCalculating);
  mixer->u[gasPathWidth + gasPathWidth + 2] = (*mixer->betaRVABI);
  mixer->u[gasPathWidth + gasPathWidth + 3] = (*mixer->hpMixerPs);
  mixer->u[gasPathWidth + gasPathWidth + 4] = (*mixer->hpA1);
  mixer->u[gasPathWidth + gasPathWidth + 5] = (*mixer->hpA2);

  Mixer_TMATS_body(mixer->y,mixer->u,&(mixer->mixerStruct));

  if(mixer->mixerStruct.IDes < 0.5)
  {
    mixer->Aphy1Des = mixer->y[6];
    mixer->Aphy2Des = mixer->y[7];
  }

  return 0;
}
//------------------------------------------------------------------------------
int mixerFree(MixerBlock *mixer)  //混合室部件释放内存
{
  if(mixer->mixerStruct.Y_M_FARVec != NULL)
    free(mixer->mixerStruct.Y_M_FARVec);
  if(mixer->mixerStruct.X_M_TVec != NULL)
    free(mixer->mixerStruct.X_M_TVec);
  if(mixer->mixerStruct.T_M_RtArray != NULL)
    free(mixer->mixerStruct.T_M_RtArray);
  if(mixer->mixerStruct.T_M_gammaArray != NULL)
    free(mixer->mixerStruct.T_M_gammaArray);
  if(mixer->mixerStruct.BlkNm != NULL)
    free(mixer->mixerStruct.BlkNm);
  if(mixer->mixerStruct.IWork != NULL)
    free(mixer->mixerStruct.IWork);
  return 0;
}
//------------------------------------------------------------------------------
int mixerOutPutHead(MixerBlock *mixer,FILE *fOut)  //混合室部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",mixer->mixerStruct.BlkNm);
  fprintf(fOut,"%s_HtOut,",mixer->mixerStruct.BlkNm);
  fprintf(fOut,"%s_TtOut,",mixer->mixerStruct.BlkNm);
  fprintf(fOut,"%s_PtOut,",mixer->mixerStruct.BlkNm);
  fprintf(fOut,"%s_FarOut,",mixer->mixerStruct.BlkNm);

  fprintf(fOut,"%s_A1,",mixer->mixerStruct.BlkNm);
  fprintf(fOut,"%s_A2,",mixer->mixerStruct.BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int mixerOutPutResult(MixerBlock *mixer,FILE *fOut)//混合室部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",mixer->y[i]);
  }

  fprintf(fOut,"%lf,",mixer->y[gasPathWidth + 1]);
  fprintf(fOut,"%lf,",mixer->y[gasPathWidth + 2]);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int ambientInitial(AmbientBlock *ambient,FILE *fIn,char *name)  //从文件初始化环境部件
{
  int i = 0;
  ambient->ambientStruct.X_A_AltVec = NULL;
  ambient->ambientStruct.T_A_TsVec = NULL;
  ambient->ambientStruct.T_A_PsVec = NULL;
  ambient->ambientStruct.X_A_FARVec = NULL;
  ambient->ambientStruct.T_A_RtArray = NULL;
  ambient->ambientStruct.Y_A_TVec = NULL;
  ambient->ambientStruct.T_A_gammaArray = NULL;
  ambient->ambientStruct.BlkNm = NULL;
  ambient->ambientStruct.IWork = NULL;

  ambient->ambientStruct.A = 0;
  ambient->ambientStruct.B = 0;
  ambient->ambientStruct.C = 0;

  fscanf(fIn,"%*[^=]=%d",&ambient->ambientStruct.A);
  if(ambient->ambientStruct.A > 0)
  {
    ambient->ambientStruct.X_A_AltVec = (double*)calloc(ambient->ambientStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.X_A_AltVec[0]);
  }
  for(i = 1;i < ambient->ambientStruct.A;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.X_A_AltVec[i]);
  }
  if(ambient->ambientStruct.A > 0)
  {
    ambient->ambientStruct.T_A_TsVec = (double*)calloc(ambient->ambientStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.T_A_TsVec[0]);
  }
  for(i = 1;i < ambient->ambientStruct.A;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.T_A_TsVec[i]);
  }
  if(ambient->ambientStruct.A > 0)
  {
    ambient->ambientStruct.T_A_PsVec = (double*)calloc(ambient->ambientStruct.A,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.T_A_PsVec[0]);
  }
  for(i = 1;i < ambient->ambientStruct.A;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.T_A_PsVec[i]);
  }
  fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.AFARc);
  fscanf(fIn,"%*[^=]=%d",&ambient->ambientStruct.B);
  if(ambient->ambientStruct.B > 0)
  {
    ambient->ambientStruct.X_A_FARVec = (double*)calloc(ambient->ambientStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.X_A_FARVec[0]);
  }
  for(i = 1;i < ambient->ambientStruct.B;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.X_A_FARVec[i]);
  }
  if(ambient->ambientStruct.B > 0)
  {
    ambient->ambientStruct.T_A_RtArray = (double*)calloc(ambient->ambientStruct.B,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.T_A_RtArray[0]);
  }
  for(i = 1;i < ambient->ambientStruct.B;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.T_A_RtArray[i]);
  }
  fscanf(fIn,"%*[^=]=%d",&ambient->ambientStruct.C);
  if(ambient->ambientStruct.C > 0)
  {
    ambient->ambientStruct.Y_A_TVec = (double*)calloc(ambient->ambientStruct.C,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.Y_A_TVec[0]);
  }
  for(i = 1;i < ambient->ambientStruct.C;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.Y_A_TVec[i]);
  }
  if(ambient->ambientStruct.B * ambient->ambientStruct.C > 0)
  {
    ambient->ambientStruct.T_A_gammaArray = (double*)calloc(ambient->ambientStruct.B * ambient->ambientStruct.C,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&ambient->ambientStruct.T_A_gammaArray[0]);
  }
  for(i = 1;i < ambient->ambientStruct.B * ambient->ambientStruct.C;i++)
  {
    fscanf(fIn,"%lf",&ambient->ambientStruct.T_A_gammaArray[i]);
  }

  i = strlen(name) + 1;  //加1为了存储最后的\0
  ambient->ambientStruct.BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(ambient->ambientStruct.BlkNm,name);
  ambient->ambientStruct.IWork = (int*)calloc(Er5 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int ambientRun(AmbientBlock *ambient)  //环境部件运行函数
{
  int i = 0;
  ambient->u[0] = *(ambient->altIn);
  ambient->u[1] = *(ambient->dTambIn);
  ambient->u[2] = *(ambient->machNumber);

  Ambient_TMATS_body(ambient->y,ambient->u,&(ambient->ambientStruct));

  ambient->gasPathOut[0] = *(ambient->wIn);
  for(i = 1;i < gasPathWidth;i++)
  {
    ambient->gasPathOut[i] = ambient->y[i - 1];
  }
  //ambient->fDrag = (*(ambient->wIn)) * ambient->y[6] / 32.1740;  //20221209- lbf
  ambient->fDrag = (*(ambient->wIn)) * ambient->y[6];  //20221209+ N

  return 0;
}
//------------------------------------------------------------------------------
int ambientFree(AmbientBlock *ambient)  //环境部件释放内存
{
  if(ambient->ambientStruct.X_A_AltVec != NULL)
    free(ambient->ambientStruct.X_A_AltVec);
  if(ambient->ambientStruct.T_A_TsVec != NULL)
    free(ambient->ambientStruct.T_A_TsVec);
  if(ambient->ambientStruct.T_A_PsVec != NULL)
    free(ambient->ambientStruct.T_A_PsVec);
  if(ambient->ambientStruct.X_A_FARVec != NULL)
    free(ambient->ambientStruct.X_A_FARVec);
  if(ambient->ambientStruct.T_A_RtArray != NULL)
    free(ambient->ambientStruct.T_A_RtArray);
  if(ambient->ambientStruct.Y_A_TVec != NULL)
    free(ambient->ambientStruct.Y_A_TVec);
  if(ambient->ambientStruct.T_A_gammaArray != NULL)
    free(ambient->ambientStruct.T_A_gammaArray);
  if(ambient->ambientStruct.BlkNm != NULL)
    free(ambient->ambientStruct.BlkNm);
  if(ambient->ambientStruct.IWork != NULL)
    free(ambient->ambientStruct.IWork);
  return 0;
}
//------------------------------------------------------------------------------
int ambientOutPutHead(AmbientBlock *ambient,FILE *fOut)  //环境部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",ambient->ambientStruct.BlkNm);
  fprintf(fOut,"%s_HtOut,",ambient->ambientStruct.BlkNm);
  fprintf(fOut,"%s_TtOut,",ambient->ambientStruct.BlkNm);
  fprintf(fOut,"%s_PtOut,",ambient->ambientStruct.BlkNm);
  fprintf(fOut,"%s_FarOut,",ambient->ambientStruct.BlkNm);

  fprintf(fOut,"%s_Fdrag,",ambient->ambientStruct.BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int ambientOutPutResult(AmbientBlock *ambient,FILE *fOut)//环境部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",ambient->gasPathOut[i]);
  }

  fprintf(fOut,"%lf,",ambient->fDrag);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int inletInitial(InletBlock *inlet,FILE *fIn,char *name)  //从文件初始化进气道部件
{
  int i = 0;
  inlet->BlkNm = NULL;
  inlet->X_eRamVec = NULL;
  inlet->T_eRamTbl = NULL;
  inlet->X_eRamVecDime = 0;
  pressureLossModelReset(&inlet->pressureLossModel);
  
  fscanf(fIn,"%*[^=]=%lf",&inlet->eRamBase);
  fscanf(fIn,"%*[^=]=%d",&inlet->X_eRamVecDime);
  if(inlet->X_eRamVecDime > 0)
  {
    inlet->X_eRamVec = (double*)calloc(inlet->X_eRamVecDime,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&inlet->X_eRamVec[0]);
  }
  for(i = 1;i < inlet->X_eRamVecDime;i++)
  {
    fscanf(fIn,"%lf",&inlet->X_eRamVec[i]);
  }
  if(inlet->X_eRamVecDime > 0)
  {
    inlet->T_eRamTbl = (double*)calloc(inlet->X_eRamVecDime,sizeof(double));
    fscanf(fIn,"%*[^=]=%lf",&inlet->T_eRamTbl[0]);
  }
  for(i = 1;i < inlet->X_eRamVecDime;i++)
  {
    fscanf(fIn,"%lf",&inlet->T_eRamTbl[i]);
  }

  i = strlen(name) + 1;  //加1为了存储最后的\0
  inlet->BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(inlet->BlkNm,name);
  //inlet->IWork = (int*)calloc(Er1 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int inletRun(InletBlock *inlet)  //进气道部件运行函数
{
  int i = 0;
  double etaPt = 1;
  double hpdP_Loss = *(inlet->hpdP_Loss);
  double totalInternalLoss;
  int interpErr = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    inlet->gasPathOut[i] = *(inlet->gasPathIn + i);
  }

  etaPt = interp1Ac(inlet->X_eRamVec,inlet->T_eRamTbl,(*(inlet->gasPathIn + 3)) / (*(inlet->pAmbIn)),inlet->X_eRamVecDime,&interpErr);
  if(inlet->pressureLossModel.enabled != 0)
  {
    totalInternalLoss = pressureLossModelEvaluate(
      &inlet->pressureLossModel,
      *(inlet->gasPathIn), *(inlet->gasPathIn + 2),
      *(inlet->gasPathIn + 3), 1.0 - inlet->eRamBase, hpdP_Loss);
    inlet->gasPathOut[3] = *(inlet->gasPathIn + 3) *
      (1.0 - totalInternalLoss) * etaPt;
  }
  else
  {
    inlet->gasPathOut[3] = *(inlet->gasPathIn + 3) *
      (inlet->eRamBase - hpdP_Loss) * etaPt;
  }

  return 0;
}
//------------------------------------------------------------------------------
int inletFree(InletBlock *inlet)  //进气道部件释放内存
{
  if(inlet->BlkNm != NULL)
    free(inlet->BlkNm);
  if(inlet->X_eRamVec != NULL)
    free(inlet->X_eRamVec);
  if(inlet->T_eRamTbl != NULL)
    free(inlet->T_eRamTbl);
  return 0;
}
//------------------------------------------------------------------------------
int inletOutPutHead(InletBlock *inlet,FILE *fOut)  //进气道部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",inlet->BlkNm);
  fprintf(fOut,"%s_HtOut,",inlet->BlkNm);
  fprintf(fOut,"%s_TtOut,",inlet->BlkNm);
  fprintf(fOut,"%s_PtOut,",inlet->BlkNm);
  fprintf(fOut,"%s_FarOut,",inlet->BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int inletOutPutResult(InletBlock *inlet,FILE *fOut)//进气道部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",inlet->gasPathOut[i]);
  }

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int splitterInitial(SplitterBlock *splitter,FILE *fIn,char *name)  //从文件初始化分流器部件
{
  int i = 0;
  splitter->BlkNm = NULL;
  
  fscanf(fIn,"%*[^=]=%lf",&splitter->BypassRatioDes);   

  i = strlen(name) + 1;  //加1为了存储最后的\0
  splitter->BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(splitter->BlkNm,name);
  //splitter->IWork = (int*)calloc(Er1 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int splitterRun(SplitterBlock *splitter)  //分流器部件运行函数
{
  int i = 0;

  for(i = 0;i < gasPathWidth;i++)
  {
    splitter->gasPathOutMain[i] = *(splitter->gasPathIn + i);
    splitter->gasPathOutBypass[i] = *(splitter->gasPathIn + i);
  }
  splitter->gasPathOutMain[0] = *(splitter->gasPathIn + 0) * 1.0 / (1.0 + (*(splitter->BypassRatioIn)));
  splitter->gasPathOutBypass[0] = *(splitter->gasPathIn + 0) * (*(splitter->BypassRatioIn)) / (1.0 + (*(splitter->BypassRatioIn)));

  splitter->gasPathOutBypass[2] = *(splitter->gasPathIn + 27);
  splitter->gasPathOutBypass[1] = t2hc(splitter->gasPathOutBypass[2], splitter->gasPathOutBypass[4]);
  splitter->gasPathOutBypass[3] = *(splitter->gasPathIn + 28);

  return 0;
}
//------------------------------------------------------------------------------
int splitterFree(SplitterBlock *splitter)  //分流器部件释放内存
{
  if(splitter->BlkNm != NULL)
    free(splitter->BlkNm);
  return 0;
}
//------------------------------------------------------------------------------
int splitterOutPutHead(SplitterBlock *splitter,FILE *fOut)  //分流器部件输出参数名至文件
{
  fprintf(fOut,"%s_WOutM,",splitter->BlkNm);
  fprintf(fOut,"%s_HtOutM,",splitter->BlkNm);
  fprintf(fOut,"%s_TtOutM,",splitter->BlkNm);
  fprintf(fOut,"%s_PtOutM,",splitter->BlkNm);
  fprintf(fOut,"%s_FarOutM,",splitter->BlkNm);

  fprintf(fOut,"%s_WOutB,",splitter->BlkNm);
  fprintf(fOut,"%s_HtOutB,",splitter->BlkNm);
  fprintf(fOut,"%s_TtOutB,",splitter->BlkNm);
  fprintf(fOut,"%s_PtOutB,",splitter->BlkNm);
  fprintf(fOut,"%s_FarOutB,",splitter->BlkNm);

  fprintf(fOut,"%s_BypassRatioIn,",splitter->BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int splitterOutPutResult(SplitterBlock *splitter,FILE *fOut)//分流器部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",splitter->gasPathOutMain[i]);
  }
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",splitter->gasPathOutBypass[i]);
  }

  fprintf(fOut,"%lf,",*splitter->BypassRatioIn);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int ductInitial(DuctBlock *duct,FILE *fIn,char *name)  //从文件初始化涵道部件
{
  int i = 0;
  duct->BlkNm = NULL;
  pressureLossModelReset(&duct->pressureLossModel);

  fscanf(fIn,"%*[^=]=%lf",&duct->dP_Loss);

  i = strlen(name) + 1;  //加1为了存储最后的\0
  duct->BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(duct->BlkNm,name);
  //duct->IWork = (int*)calloc(Er1 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int ductRun(DuctBlock *duct)  //涵道部件运行函数
{
  int i = 0;
  double totalLoss;

  for(i = 0;i < gasPathWidth;i++)
  {
    duct->gasPathOut[i] = *(duct->gasPathIn + i);
  }
  if(duct->pressureLossModel.enabled != 0)
  {
    totalLoss = pressureLossModelEvaluate(
      &duct->pressureLossModel,
      *(duct->gasPathIn), *(duct->gasPathIn + 2),
      *(duct->gasPathIn + 3), duct->dP_Loss, *(duct->hpdP_Loss));
    duct->gasPathOut[3] = *(duct->gasPathIn + 3) * (1.0 - totalLoss);
  }
  else
  {	  
    double massbound1 = 0.1;		// 20230816+ liukai
    double massbound2 = 0.2;		// 20230816+ liukai
    if (duct->gasPathOut[0]> massbound2)
    {	  
	    duct->gasPathOut[3] = *(duct->gasPathIn + 3) * (1 - duct->dP_Loss - *(duct->hpdP_Loss));
    }
    else if (duct->gasPathOut[0] < massbound1)
    {
	    duct->gasPathOut[3] = *(duct->gasPathIn + 3);
    }
    else
    {
	    double sigma = 0;
	    sigma = (duct->dP_Loss - 0) / (massbound2 - massbound1)*(duct->gasPathOut[0] - massbound1) + 0;
	    duct->gasPathOut[3] = *(duct->gasPathIn + 3) * (1 - sigma);
    }
  }
  return 0;
}
//------------------------------------------------------------------------------
int ductFree(DuctBlock *duct)  //涵道部件释放内存
{
  if(duct->BlkNm != NULL)
    free(duct->BlkNm);
  return 0;
}
//------------------------------------------------------------------------------
int ductOutPutHead(DuctBlock *duct,FILE *fOut)  //涵道部件输出参数名至文件
{
  fprintf(fOut,"%s_WOut,",duct->BlkNm);
  fprintf(fOut,"%s_HtOut,",duct->BlkNm);
  fprintf(fOut,"%s_TtOut,",duct->BlkNm);
  fprintf(fOut,"%s_PtOut,",duct->BlkNm);
  fprintf(fOut,"%s_FarOut,",duct->BlkNm);

  fprintf(fOut,"%s_dP_Loss,",duct->BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int ductOutPutResult(DuctBlock *duct,FILE *fOut)//涵道部件输出参数值至文件
{
  int i = 0;
  for(i = 0;i < gasPathWidth;i++)
  {
    fprintf(fOut,"%lf,",duct->gasPathOut[i]);
  }

  fprintf(fOut,"%lf,",duct->dP_Loss);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
int FVABIInitial(FVABIBlock *FVABI, FILE *fIn, char *name)  //从文件初始化FVABI部件
{
	int i = 0;
	FVABI->BlkNm = NULL;

	fscanf(fIn, "%*[^=]=%lf", &FVABI->Amax);
	fscanf(fIn, "%*[^=]=%lf", &FVABI->Amin);

	i = strlen(name) + 1;  //加1为了存储最后的\0
	FVABI->BlkNm = (char*)calloc(i, sizeof(char));
	strcpy(FVABI->BlkNm, name);
	return 0;
}
//------------------------------------------------------------------------------
int FVABIRun(FVABIBlock *FVABI)  //FVABI部件运行函数
{
	int i = 0;

	for (i = 0; i < gasPathWidth; i++)
	{
		FVABI->u[i] = *(FVABI->gasPathIn + i);
	}
	FVABI->u[gasPathWidth + 0] = FVABI->Amax;
	FVABI->u[gasPathWidth + 1] = FVABI->Amin;
	FVABI->u[gasPathWidth + 2] = *(FVABI->beta);
	FVABI_GTESS_body(FVABI->y, FVABI->u);

	return 0;
}
//------------------------------------------------------------------------------
int FVABIFree(FVABIBlock *FVABI)  //FVABI部件释放内存
{
	if (FVABI->BlkNm != NULL)
		free(FVABI->BlkNm);
	return 0;
}
//------------------------------------------------------------------------------
int shaftInitial(ShaftBlock *shaft,FILE *fIn,char *name)  //从文件初始化轴部件
{
  int i = 0;
  shaft->BlkNm = NULL;
  fscanf(fIn,"%*[^=]=%lf",&shaft->inertia);
  fscanf(fIn, "%*[^=]=%lf", &shaft->effMech);		// 20230913+, liukai

  i = strlen(name) + 1;  //加1为了存储最后的\0
  shaft->BlkNm = (char*)calloc(i,sizeof(char));
  strcpy(shaft->BlkNm,name);
  //shaft->IWork = (int*)calloc(Er1 + 1,sizeof(int));
  return 0;
}
//------------------------------------------------------------------------------
int shaftRun(ShaftBlock *shaft)  //轴部件运行函数
{
  //shaft->nDot = ((*shaft->torqueIn) + (*shaft->powerTakeOff) / (*shaft->nMech) *(-5252.11))  //20221209-
	double Nbound = 10;
	double torquePow = 0;
	double torqbound = 200;

	// 20230818+ liuaki	
	torquePow = -(*shaft->powerTakeOff) *divby(*shaft->nMech  * PI / 30.0);
	if (*shaft->nMech < 1)		// 20230818+ liuaki
	{
		torqbound = 100;
		if (torquePow > torqbound)
			torquePow = torqbound;
	}
	else if (*shaft->nMech < 10)		// 20230818+ liuaki
	{
		torqbound = (200 - 100) / (10 - 1)*(*shaft->nMech - 1) + 100;
		if (torquePow > torqbound)
			torquePow = torqbound;
	}
	else if (*shaft->nMech < 50)		// 20230818+ liuaki
	{
		torqbound = (2000 - 200) / (50 - 10)*(*shaft->nMech - 10) + 200;
		if (torquePow > torqbound)
			torquePow = torqbound;
	}

	shaft->nDot = ((*shaft->torqueIn) + torquePow) * (30.0 / (PI * shaft->inertia));  //20221209+		// 20230818+ liuaki
                

/*  if(*shaft->isDynamicCalculating == 1)  //动态考虑转动惯量的影响
  {
    shaft->nDot = shaft->nDot - ((*shaft->nMech) - shaft->nMechOld) / (*shaft->timeStep);
  }*/
  return 0;
}
//------------------------------------------------------------------------------
int shaftFree(ShaftBlock *shaft)  //轴部件释放内存
{
  if(shaft->BlkNm != NULL)
    free(shaft->BlkNm);
  return 0;
}
//------------------------------------------------------------------------------
int shaftOutPutHead(ShaftBlock *shaft,FILE *fOut)  //轴部件输出参数名至文件
{
  fprintf(fOut,"%s_nMech,",shaft->BlkNm);

  return 0;
}
//------------------------------------------------------------------------------
int shaftOutPutResult(ShaftBlock *shaft,FILE *fOut)//轴部件输出参数值至文件
{
  fprintf(fOut,"%lf,",*shaft->nMech);

  return 0;
}
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
