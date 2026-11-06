#ifndef BLOCKANDFUNCTIONS_H
#define BLOCKANDFUNCTIONS_H

#include <stdio.h>
#include "types_TMATS.h"

#define gasPathWidth 				 5		

//------------------------------------------------------------------------------
/*
 * 总压损失基准模型。
 *
 * nominalLossDes 仍由各部件原有 MDL 字段给出；本结构只保存该部件的
 * 设计点流量/总温/总压参考量、低流量平滑区间以及最近一次求值诊断。
 * enabled=0 时，各部件继续走原有计算支路，从而不改变涡轴发动机以外
 * 的既有模型。enabled=1 时采用
 *
 *   L = G(W/Wdes) * Ldes * PhiHat^2 + KdP_eff
 *
 * 其中 PhiHat=(W/Wdes)*sqrt(Tt/TtDes)*(PtDes/Pt)。
 */
struct PressureLossModel {
  int enabled;
  double massFlowDes;
  double totalTemperatureDes;
  double totalPressureDes;
  double gateZeroFlowRatio;
  double gateFullFlowRatio;
  /* 调度修正已经形成最终值时，禁止再次乘名义压损低流量门。 */
  int correctionBypassNominalGate;

  double lastMassFlowRatio;
  double lastCorrectedFlowRatio;
  double lastGate;
  double lastNominalLoss;
  double lastCorrectionLoss;
  double lastTotalLoss;
};
typedef struct PressureLossModel PressureLossModel;

//------------------------------------------------------------------------------
struct TurbineBlock {
  TurbineStruct turbineStruct;
  //输入接口的指针
  double *gasPathIn;
  double *nMech;
  double *PressureRatioIn;
  double *coolingFlow;
  double *extCoolingFlow;
  double *hpW;
  double *hpEf;
  double *hpPR;
  double extSecAirSys;

  double coolingFlowWidth;
  double Amean, Cmean, Kcla, Kwe;

  double u[19];
  double y[25];

  double IDesInput;
  double s_T_Nc_des;
  double s_T_Wc_des;
  double s_T_PR_des;
  double s_T_Eff_des;
  char mapPath[1000];
};
typedef struct TurbineBlock TurbineBlock;

struct BurnBlock {
  BurnStruct burnStruct;
  PressureLossModel pressureLossModel;
  //输入接口的指针
  double *gasPathIn;
  double *fuelFlowIn;
  double *hpWf;
  double *hpEf;
  double *hpdP_Loss;	// 20241108+, liukai

  double u[9];
  double y[6];

  char *BlkNm;
};
typedef struct BurnBlock BurnBlock;

struct NozzleBlock {
  NozzleStruct nozzleStruct;
  //输入接口的指针
  double *gasPathIn;
  double *pAmbIn;
  double *hpA8;
  //jrt,20241106
  double *hpA9;

  double *fDrag;
  double afterFVABI;
  double *betaFVABI;

  //jrt,20241106
  double u[13];

  double y[17];

  double IDesInput;
  double areaThroatIn,areaThroatDes;
  double areaExitIn,areaExitDes;
};
typedef struct NozzleBlock NozzleBlock;

struct CompressorBlock {
  CompressorStruct compressorStruct;
  //输入接口的指针
  double *gasPathIn;
  double *rLineIn;
  double *nMech;
  double *fractionalBleedsDemand;
  double *customerBleedsDemand;
  double *BypassRatioIn;
  double *hpW;
  double *hpEf;
  double *hpPR;
  double *hpAFT;		// 20241108+, liukai
  //jrt,20241105
  double *hpPR_TipRootRatio;
  double *hpEf_TipRootRatio;
  double *hpWbld;
  double *hpBldPRec;
  double *hpBldht;
  double *hp_alf2W;
  double *hp_alf2PR;
  double *hp_alf2Ef;

  //输出接口的指针，引气数量不确定，内存分配与核心代码保持一致
  double fractionalBleeds[2501];    //500*5 + 1最后一位存数组长度
  double customerBleeds[2501];      //500*5 + 1
  double Amean, Cmean, Kcla, Kwe, AFT;		// 20241108+, liukai
  //jrt,20241105
  double u[100];
  double y[31];

  double IDesInput;
  double s_C_Nc_in,s_C_Nc_des;
  double s_C_Wc_in,s_C_Wc_des;
  double s_C_PR_in,s_C_PR_des, s_C_PRTip_in, s_C_PRTip_des;
  double s_C_Eff_in,s_C_Eff_des, s_C_EffTip_in, s_C_EffTip_des;
  int  is3dMap;
  double alphaIn;
  char mapPath[1000];
};
typedef struct CompressorBlock CompressorBlock;

struct MixerBlock {
  MixerStruct mixerStruct;
  //输入接口的指针
  double *gasPathIn1;
  double *gasPathIn2;
  double *MixerPs;
  double *isDynamicCalculating;
  double *betaRVABI;		// liukai
  double *hpMixerPs;
  double *hpA1;
  double *hpA2;

  double u[16];		// liukai
  double y[16];		// liukai

  double IDesInput;
  double Aphy1In,Aphy1Des;
  double Aphy2In,Aphy2Des;

};
typedef struct MixerBlock MixerBlock;

struct AmbientBlock {
  AmbientStruct ambientStruct;
  //输入接口的指针
  double *wIn;
  double *altIn;
  double *dTambIn;
  double *machNumber;

  double u[3];
  double y[8];

  double gasPathOut[5];
  double fDrag;
};
typedef struct AmbientBlock AmbientBlock;

struct InletBlock {

  char *BlkNm;
  double eRamBase;
  PressureLossModel pressureLossModel;
  int X_eRamVecDime;
  double *X_eRamVec;
  double *T_eRamTbl;
  //输入接口的指针
  double *gasPathIn;
  double *pAmbIn;
  double *hpdP_Loss;

  double gasPathOut[5];
};
typedef struct InletBlock InletBlock;

struct SplitterBlock {

  char *BlkNm;
  double BypassRatioDes;  //预留接口
  //输入接口的指针
  double *gasPathIn;
  double *BypassRatioIn;

  double gasPathOutMain[5];
  double gasPathOutBypass[5];
};
typedef struct SplitterBlock SplitterBlock;

struct DuctBlock {

  char *BlkNm;
  double dP_Loss;
  PressureLossModel pressureLossModel;
  //输入接口的指针
  double *gasPathIn;
  double *hpdP_Loss;

  double gasPathOut[5];
};
typedef struct DuctBlock DuctBlock;

struct ShaftBlock {

  char *BlkNm;
  double inertia;
  double effMech;	// 20230913+, liukai

  double nMechOld;
  //输入接口的指针
  double *torqueIn;
  double *powerTakeOff;
  double *nMech;
  double *timeStep;

  double nDot;
};
typedef struct ShaftBlock ShaftBlock;

struct FVABIBlock {
	char *BlkNm;
	double *beta;
	double Amax;
	double Amin;
	double dP_Loss;
	//输入接口的指针
	double *gasPathIn;
	double u[10];
	double y[20];
};
typedef struct FVABIBlock FVABIBlock;

//------------------------------------------------------------------------------
void pressureLossModelReset(PressureLossModel *model);
int pressureLossModelConfigure(
  PressureLossModel *model,
  double massFlowDes,
  double totalTemperatureDes,
  double totalPressureDes,
  double gateZeroFlowRatio,
  double gateFullFlowRatio);
double pressureLossModelEvaluate(
  PressureLossModel *model,
  double massFlow,
  double totalTemperature,
  double totalPressure,
  double nominalLossDes,
  double correctionLoss);

//------------------------------------------------------------------------------
int turbineInitial(TurbineBlock *turbine,FILE *fIn,char *name, char *path);
int turbineRun(TurbineBlock *turbine);
int turbineFree(TurbineBlock *turbine);
int turbineOutPutHead(TurbineBlock *turbine,FILE *fOut);
int turbineOutPutResult(TurbineBlock *turbine,FILE *fOut);

int burnInitial(BurnBlock *burn,FILE *fIn,char *name);
int burnRun(BurnBlock *burn);
int burnFree(BurnBlock *burn);
int burnOutPutHead(BurnBlock *burn,FILE *fOut);
int burnOutPutResult(BurnBlock *burn,FILE *fOut);

int nozzleInitial(NozzleBlock *nozzle,FILE *fIn,char *name);
int nozzleRun(NozzleBlock *nozzle);
int nozzleFree(NozzleBlock *nozzle);
int nozzleOutPutHead(NozzleBlock *nozzle,FILE *fOut);
int nozzleOutPutResult(NozzleBlock *nozzle,FILE *fOut);

int compressorInitial(CompressorBlock *compressor,FILE *fIn,char *name, char *path);
int compressorFInitial(CompressorBlock *compressor, FILE *fIn, char *name, char *path);
int compressorRun(CompressorBlock *compressor);
int compressorFRun(CompressorBlock *compressor);
int compressorFree(CompressorBlock *compressor);
int compressorOutPutHead(CompressorBlock *compressor,FILE *fOut);
int compressorOutPutResult(CompressorBlock *compressor,FILE *fOut);

int mixerInitial(MixerBlock *mixer,FILE *fIn,char *name);
int mixerRun(MixerBlock *mixer);
int mixerFree(MixerBlock *mixer);
int mixerOutPutHead(MixerBlock *mixer,FILE *fOut);
int mixerOutPutResult(MixerBlock *mixer,FILE *fOut);

int ambientInitial(AmbientBlock *ambient,FILE *fIn,char *name);
int ambientRun(AmbientBlock *ambient);
int ambientFree(AmbientBlock *ambient);
int ambientOutPutHead(AmbientBlock *ambient,FILE *fOut);
int ambientOutPutResult(AmbientBlock *ambient,FILE *fOut);

int inletInitial(InletBlock *inlet,FILE *fIn,char *name);
int inletRun(InletBlock *inlet);
int inletFree(InletBlock *inlet);
int inletOutPutHead(InletBlock *inlet,FILE *fOut);
int inletOutPutResult(InletBlock *inlet,FILE *fOut);

int splitterInitial(SplitterBlock *splitter,FILE *fIn,char *name);
int splitterRun(SplitterBlock *splitter);
int splitterFree(SplitterBlock *splitter);
int splitterOutPutHead(SplitterBlock *splitter,FILE *fOut);
int splitterOutPutResult(SplitterBlock *splitter,FILE *fOut);

int ductInitial(DuctBlock *duct,FILE *fIn,char *name);
int ductRun(DuctBlock *duct);
int ductFree(DuctBlock *duct);
int ductOutPutHead(DuctBlock *duct,FILE *fOut);
int ductOutPutResult(DuctBlock *duct,FILE *fOut);

int FVABIInitial(FVABIBlock *FVABI, FILE *fIn, char *name);
int FVABIRun(FVABIBlock *FVABI);
int FVABIFree(FVABIBlock *FVABI);

int shaftInitial(ShaftBlock *shaft,FILE *fIn,char *name);
int shaftRun(ShaftBlock *shaft);
int shaftFree(ShaftBlock *shaft);
int shaftOutPutHead(ShaftBlock *shaft,FILE *fOut);
int shaftOutPutResult(ShaftBlock *shaft,FILE *fOut);
//------------------------------------------------------------------------------
#endif  /* BLOCKANDFUNCTIONS_H */
