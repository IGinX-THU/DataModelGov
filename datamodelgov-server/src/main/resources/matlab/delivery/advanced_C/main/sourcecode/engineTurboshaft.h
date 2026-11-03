#ifndef ENGINE_TURBOSHAFT_H
#define ENGINE_TURBOSHAFT_H

#include "blockAndFunctions.h"
#include "shtTransientEffects.h"
#include "shtHealthSchedule.h"
#include "shtLowSpeedSolver.h"
#include "shtStartStop.h"

#define SHT_STEP_IN_LENGTH 512
#define SHT_STEP_OUT_LENGTH 128

/* 轴负载模式与进口/拓扑模式独立。C零基下标，MATLAB位置加1。
 * 模式0（默认）：[5:6]为PT/GT外部功率，W；
 * 模式1：[5:6]为Mkp/Mkg外部扭矩，N*m，正值表示提取功率。
 * Mkg不包含HPC内部做功。每次运行入口均读取模式，不沿用上次设置。
 */
#define SHT_SHAFT_LOAD_MODE_INDEX 7
#define SHT_PT_LOAD_INPUT_INDEX 5
#define SHT_GT_LOAD_INPUT_INDEX 6
#define SHT_SHAFT_LOAD_POWER 0
#define SHT_SHAFT_LOAD_TORQUE 1

/*
 * 修正系数统一位于 stepIn[40:198]，对应 h0:h158。
 * 原 hlthparas[100] 保持尺寸和位置不变，以维持三部件公共结构体
 * 的已有字段偏移；六部件新增的59个量追加在结构体末尾。
 */
#define SHT_HEALTH_INPUT_OFFSET 40
#define SHT_HEALTH_BASE_COUNT 100
#define SHT_HEALTH_EXTENDED_COUNT 59
#define SHT_HEALTH_TOTAL_COUNT \
  (SHT_HEALTH_BASE_COUNT + SHT_HEALTH_EXTENDED_COUNT)

/*
 * 独立排气背压输入。这里使用 C 的 0 基下标，MATLAB 对应 stepIn(10)。
 * 取 0 时严格沿用历史行为，喷管外界压力等于当前环境静压；取有限正值
 * 时表示喷管实际承受的绝对外界背压，环境静压仍由 stepIn[15] 单独给出。
 */
#define SHT_EXHAUST_BACK_PRESSURE_INPUT_INDEX 9

/*
 * RunOnePoint/RunOneStep external-air input: stepIn[199] must be 10; stream
 * data start at stepIn[200]. Each stream is [W,h,Tt,Pt,FAR]. Legacy numbering
 * is not public.
 */
#define SHT_EXTERNAL_BLEED_COUNT_INDEX 199
#define SHT_EXTERNAL_BLEED_OFFSET 200
#define SHT_EXTERNAL_BLEED_COUNT 10
#define SHT_EXTERNAL_BLEED_STATE_WIDTH 5
#define SHT_EXTERNAL_BLEED_CC_GT1_INLET 0
#define SHT_EXTERNAL_BLEED_CC_GT1_EXIT 1
#define SHT_EXTERNAL_BLEED_CC_GT2_INLET 2
#define SHT_EXTERNAL_BLEED_CC_GT2_EXIT 3
#define SHT_EXTERNAL_BLEED_AC_PT1_INLET 4
#define SHT_EXTERNAL_BLEED_AC_PT1_EXIT 5
#define SHT_EXTERNAL_BLEED_AC_PT2_INLET 6
#define SHT_EXTERNAL_BLEED_AC_PT2_EXIT 7
#define SHT_EXTERNAL_BLEED_CC_PT2_EXIT 8
#define SHT_EXTERNAL_BLEED_AC_LEAK 9

/*
 * 进口环境边界输入字典。这里使用 C 的 0 基下标；MATLAB 对应位置均加 1。
 * stepIn[10] : 高度，m；模式0在ConditionsInit读取，模式3逐次读取。
 * stepIn[11] : 马赫数；模式0在ConditionsInit读取，模式2/3/4/5逐次读取。
 * stepIn[12] : 相对标准大气温差，K；仅模式0初始化使用。
 * stepIn[13] : 模式1为Pt1，模式4为测量Pt2，Pa。
 * stepIn[14] : Tt1，K；模式1/4/5使用。
 * stepIn[15] : 环境或发动机进口静压，Pa；模式1/2/4/5使用。
 * stepIn[16] : 进口边界模式，见 SHTInletBoundaryMode。
 * stepIn[17] : 健康修正调度开关，定义见下文。
 * stepIn[18] : 环境静温，K；模式2/3/4/5使用，其中模式3结合高度计算环境压力。
 * stepIn[19] : 模式2/5的外部装机进气总压恢复系数；0为历史兼容值，按1处理。
 *              模式2/5显式输入时取值范围为(0,1]，其他模式必须为0。
 */
#define SHT_ALTITUDE_INPUT_INDEX 10
#define SHT_MACH_INPUT_INDEX 11
#define SHT_DELTA_TEMPERATURE_INPUT_INDEX 12
#define SHT_INLET_TOTAL_PRESSURE_INPUT_INDEX 13
#define SHT_INLET_TOTAL_TEMPERATURE_INPUT_INDEX 14
#define SHT_AMBIENT_PRESSURE_INPUT_INDEX 15
#define SHT_INLET_BOUNDARY_MODE_INDEX 16
#define SHT_AMBIENT_TEMPERATURE_INPUT_INDEX 18
#define SHT_INLET_EXTERNAL_RECOVERY_INPUT_INDEX 19

typedef enum SHTInletBoundaryMode
{
	SHT_INLET_BOUNDARY_STANDARD_ATMOSPHERE = 0,
	SHT_INLET_BOUNDARY_DIRECT_TOTAL = 1,
	SHT_INLET_BOUNDARY_STATIC_RECONSTRUCTION = 2,
	SHT_INLET_BOUNDARY_ALTITUDE_STATIC_TEMPERATURE = 3,
	SHT_INLET_BOUNDARY_MEASURED_TT_PT2_REPLAY = 4,
	SHT_INLET_BOUNDARY_MEASURED_STATIC_TT_REPLAY = 5
} SHTInletBoundaryMode;

/*
 * 健康修正调度运行开关。stepIn[17]=0 时，h0:h158 保持历史常值语义；
 * stepIn[17]=1 时，六部件模型按已经初始化的31张表计算 K_eff。
 * 该位置不占用共同工作猜值、修正系数或外部气流区域。
 */
#define SHT_HEALTH_SCHEDULE_ENABLE_INDEX 17

/* 起停专用入口的扩展输入。20:28仍为六部件共同工作初值。 */
#define SHT_START_STOP_TIME_STEP_INDEX 29
#define SHT_START_STOP_COMMAND_INDEX 30
#define SHT_START_STOP_ROTOR_EQUIVALENT_SPEED_INDEX 31
#define SHT_START_STOP_COLLECTIVE_PITCH_INDEX 32
#define SHT_START_STOP_IGNITION_ENABLE_INDEX 33
#define SHT_START_STOP_GAS_TEMPERATURE_INDEX 34
#define SHT_START_STOP_SEED_ENABLE_INDEX 35
/*
 * 起停专用入口的热状态导数输出。stepOut[24:50]在阶段六中为保留区，
 * 阶段七按Visser 29状态拓扑写入19个金属、6个转盘和2个导向器导数。
 * 关闭热状态时该区域仍由SHT_ClearStepOut保持为零。
 */
#define SHT_START_STOP_METAL_DERIVATIVE_START_INDEX 24
#define SHT_START_STOP_DISK_DERIVATIVE_START_INDEX 43
#define SHT_START_STOP_GUIDE_DERIVATIVE_START_INDEX 49
#define SHT_START_STOP_THERMAL_DERIVATIVE_COUNT 27
#define SHT_LOW_SPEED_SOLVER_CONFIG_VERSION 26082503
#define SHT_LOW_SPEED_SOLVER_CONFIG_COUNT 13
#define SHT_LOW_SPEED_DIAGNOSTIC_COUNT 97

//------------------------------------------------------------------------------
struct EngineTurboshaft {
  char   *engineName;
  int    offDesignMode;
  int    modelMode;          /* 0: original model; 1: six-component split model */
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
  CompressorBlock HPC2;
  BurnBlock       Burner;
  TurbineBlock    HPT;
  TurbineBlock    HPT2;
  DuctBlock       Duct2;
  TurbineBlock    LPT;
  TurbineBlock    LPT2;
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
  double varStartInput[9];   /* mode 0 uses 6 variables; mode 1 uses 9 variables */
  double varStartStore[9];
  double varMin[9];
  double varMax[9];
  double varDelLim[9];

  double inletMassFlow;
  double HPC_Rline;
  double HPC2_Rline;
  double HPT_PRin;
  double HPT2_PRin;
  double LPT_PRin;
  double LPT2_PRin;
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
  double varIte[9];
  double errOut[9];
  char * filePath;
  double InletOutTt;	//T1
  double InletOutPt;	//P1
  double AmbientPs;		//Pamb: ambient static pressure
  double InletInTt;		//Tt1: inlet entrance total temperature
  double InletInPt;		//Pt1: inlet entrance total pressure
  double useInletBoundaryInput;	//SHTInletBoundaryMode value; kept as double for ABI compatibility
  SHTTransientControl transientControl;
  SHTTransientState transientState;
  SHTTransientParameters transientParameters;
  SHTTransientDiagnostics transientDiagnostics;
  SHTTransientHeatEvaluation transientHeatEvaluation;
  SHTTransientClearanceEvaluation transientClearanceEvaluation;
  double hlthparasExtended[SHT_HEALTH_EXTENDED_COUNT];
};
typedef struct EngineTurboshaft EngineTurboshaft;

struct EngineSHTPointer {
	EngineTurboshaft * eng;
};
typedef struct EngineSHTPointer EngineSHTPointer;
//------------------------------------------------------------------------------

int engineTurboshaftInitial(EngineTurboshaft *eng);
int engineTurboshaftInitialMode(EngineTurboshaft *eng, int modelMode);
int engineTurboshaftSetIdes(EngineTurboshaft *eng, double iDes);
int engineTurboshaftFree(EngineTurboshaft *eng);
int engineTurboshaftLink(EngineTurboshaft *eng);

//------------------------------------------------------------------------------
#endif  /* ENGINEMIXEDFAN */
