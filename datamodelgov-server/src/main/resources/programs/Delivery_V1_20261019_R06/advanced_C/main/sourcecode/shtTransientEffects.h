#ifndef SHT_TRANSIENT_EFFECTS_H
#define SHT_TRANSIENT_EFFECTS_H

/*
 * 2.5 三类瞬态效应的统一输入接口。
 *
 * 本文件集中定义接口解析以及可独立测试的瞬态效应纯计算核。把配置、
 * 状态和物理求值与发动机部件调用分开，可保证瞬态效应总开关为 0 时原
 * 模型完全沿用既有路径，也可按 P2/P3/P5 逐层放行新增物理通道。
 * 发动机三/六部件拓扑只由 DLL_SHT_InitialMode 决定；2502/2503 仅是
 * DLL 内部按该拓扑派生的参数布局标识，不允许由 stepIn 再次选择。
 */

#define SHT_TRANSIENT_INTERFACE_BASELINE 0
#define SHT_TRANSIENT_INTERFACE_2502 2502
#define SHT_TRANSIENT_INTERFACE_2503 2503
#define SHT_TRANSIENT_CONTROL_TOL 1.0e-6

/*
 * 标称热模型初始化接口版本。六部件 Kurzke 的固定参数在
 * DLL 初始化后一次写入，不再随每个 stepIn 重复传递。动态状态、
 * 当前工况 epsilon_ss 及个体修正量仍保留在 stepIn 中。
 */
#define SHT_THERMAL_MODEL_KURZKE 1
#define SHT_THERMAL_MODEL_VISSER 3
#define SHT_THERMAL_CONFIG_VERSION_KURZKE_1 250301
#define SHT_THERMAL_CONFIG_KURZKE_PARAMETER_COUNT 147
#define SHT_THERMAL_CONFIG_VERSION_VISSER_1 250303
#define SHT_THERMAL_CONFIG_VISSER_PARAMETER_COUNT 178
#define SHT_THERMAL_CONFIG_VERSION_LEGACY_KURZKE_1 250201
#define SHT_THERMAL_CONFIG_VERSION_LEGACY_VISSER_1 250203
/* 三部件沿用最大容量向量布局，只有拓扑有效槽位参与计算，其余填零。 */
#define SHT_COOLING_SPLIT_VERSION_1 250304
#define SHT_COOLING_SPLIT_PARAMETER_COUNT 19

#define SHT_COMPONENT_HPC 1
#define SHT_COMPONENT_BURNER 2
#define SHT_COMPONENT_GT 4
#define SHT_COMPONENT_PT 8

#define SHT_LEGACY_METAL_NODE_COUNT 10
#define SHT_LEGACY_DISK_NODE_COUNT 3
#define SHT_LEGACY_HEAT_COMPONENT_COUNT 4
#define SHT_LEGACY_CLEARANCE_COMPONENT_COUNT 3

#define SHT_SPLIT_METAL_NODE_COUNT 19
#define SHT_SPLIT_DISK_NODE_COUNT 6
#define SHT_SPLIT_HEAT_COMPONENT_COUNT 7
#define SHT_SPLIT_CLEARANCE_COMPONENT_COUNT 6
#define SHT_VISSER_GUIDE_VANE_NODE_COUNT 2
#define SHT_VISSER_METAL_NODE_COUNT \
	(SHT_SPLIT_METAL_NODE_COUNT + SHT_VISSER_GUIDE_VANE_NODE_COUNT)
#define SHT_VISSER_COOLING_BRANCH_COUNT 19
#define SHT_PHYSICAL_COOLING_ROUTE_COUNT 10

/* 公共结构按最大拓扑分配，实际参与计算的数量由 control 中的计数字段确定。 */
#define SHT_METAL_NODE_COUNT SHT_SPLIT_METAL_NODE_COUNT
#define SHT_DISK_NODE_COUNT SHT_SPLIT_DISK_NODE_COUNT
#define SHT_HEAT_COMPONENT_COUNT SHT_SPLIT_HEAT_COMPONENT_COUNT
#define SHT_CLEARANCE_COMPONENT_COUNT SHT_SPLIT_CLEARANCE_COMPONENT_COUNT
#define SHT_CLEARANCE_RATE_COUNT 8
#define SHT_COMPRESSOR_CLEARANCE_COUNT 2

#define SHT_STATUS_OK 0
#define SHT_ERROR_NULL_POINTER 2501001
#define SHT_ERROR_INTERFACE_VERSION 2501002
#define SHT_ERROR_CONTROL_VALUE 2501003
#define SHT_ERROR_MODEL_MODE_NOT_IMPLEMENTED 2501004
#define SHT_ERROR_SWITCH_DEPENDENCY 2501005
#define SHT_ERROR_RESERVED_INPUT 2501006
#define SHT_ERROR_STATE_VALUE 2501007
#define SHT_ERROR_PARAMETER_VALUE 2501008
#define SHT_ERROR_FEATURE_NOT_IMPLEMENTED 2501009
#define SHT_ERROR_HEAT_EVALUATION 2501010
#define SHT_ERROR_HEAT_FEEDBACK 2501011
#define SHT_ERROR_CLEARANCE_EVALUATION 2501012
#define SHT_ERROR_CLEARANCE_FEEDBACK 2501013
#define SHT_ERROR_THERMAL_CONFIG_NOT_INITIALIZED 2501014
#define SHT_ERROR_THERMAL_CONFIG_VERSION 2501015
#define SHT_ERROR_THERMAL_CONFIG_SIZE 2501016
#define SHT_ERROR_THERMAL_CONFIG_MODEL_MISMATCH 2501017
#define SHT_ERROR_COOLING_SPLIT_NOT_INITIALIZED 2501018
#define SHT_ERROR_COOLING_SPLIT_SIZE 2501019
#define SHT_ERROR_COOLING_SPLIT_VALUE 2501020
#define SHT_ERROR_VISSER_ENERGY_BALANCE 2501021

/* stepIn 中 2.5 新接口的 C 下标。集中定义，禁止在调用点散落魔数。 */
#define SHT_INPUT_TEMPERATURE_START 300
#define SHT_INPUT_TRANSIENT_EFFECTS_ENABLE 340
#define SHT_INPUT_THERMAL_MODEL_MODE 341
#define SHT_INPUT_INERTIA_ENABLE 342
#define SHT_INPUT_HEAT_STATE_ENABLE 343
#define SHT_INPUT_HEAT_FEEDBACK_ENABLE 344
#define SHT_INPUT_CLEARANCE_ENABLE 345
#define SHT_INPUT_CLEARANCE_FEEDBACK_ENABLE 346
#define SHT_INPUT_COMPONENT_MASK 347
#define SHT_INPUT_FIXED_PARAMETER_START 350
#define SHT_INPUT_NOMINAL_CLEARANCE_RATE_START 434

typedef struct SHTTransientControl {
	/* 内部参数布局标识：0=未启用，2502=三部件，2503=六部件。 */
	int interfaceVersion;
	int modelMode;
	int thermalModelMode;
	int inertiaEnable;
	int heatStateEnable;
	int heatFeedbackEnable;
	int clearanceEnable;
	int clearanceFeedbackEnable;
	int componentMask;
	int metalNodeCount;
	int diskNodeCount;
	int guideVaneNodeCount;
	int heatComponentCount;
	int clearanceComponentCount;
} SHTTransientControl;

typedef struct SHTTransientState {
	double metalTemperature[SHT_METAL_NODE_COUNT];
	double diskTemperature[SHT_DISK_NODE_COUNT];
	double guideVaneTemperature[SHT_VISSER_GUIDE_VANE_NODE_COUNT];
} SHTTransientState;

typedef struct SHTTransientParameters {
	double tau0[SHT_METAL_NODE_COUNT];
	double heatCapacity0[SHT_METAL_NODE_COUNT];
	double beta[SHT_METAL_NODE_COUNT];
	double diskTau0[SHT_DISK_NODE_COUNT];
	double referenceFlow[SHT_HEAT_COMPONENT_COUNT];
	double referenceGasTemperature[SHT_HEAT_COMPONENT_COUNT];
	/* HPC、GT、PT 各 10 项，采用一维数组以保持 MATLAB 头文件解析稳定。 */
	double clearanceParameter[10 * SHT_CLEARANCE_COMPONENT_COUNT];
	double epsilonSS[SHT_CLEARANCE_COMPONENT_COUNT];
	double kSM[SHT_COMPRESSOR_CLEARANCE_COUNT];
	/* HPC流量、HPC效率、GT效率、PT效率的标称间隙-性能灵敏度。 */
	double nominalClearanceExchangeRate[SHT_CLEARANCE_RATE_COUNT];
	/* 模式相关输入下标只在解析层出现，发动机层统一读取这些具名修正量。 */
	double inertiaCorrection[2];
	double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT];
	double diskTimeCorrection[SHT_DISK_NODE_COUNT];
	double clearanceRateCorrection[SHT_CLEARANCE_RATE_COUNT];
	double effectiveClearanceExchangeRate[SHT_CLEARANCE_RATE_COUNT];
	/* Visser-1绝对热网络标称参数；Kurzke模式保持为零。 */
	double visserMetalHeatCapacity[SHT_VISSER_METAL_NODE_COUNT];
	double visserHotGasConductance0[SHT_VISSER_METAL_NODE_COUNT];
	double visserHotGasBeta[SHT_VISSER_METAL_NODE_COUNT];
	double visserDiskHeatCapacity[SHT_DISK_NODE_COUNT];
	double visserRootDiskConductance0[SHT_DISK_NODE_COUNT];
	double visserCoolingConductance0[SHT_VISSER_COOLING_BRANCH_COUNT];
} SHTTransientParameters;

typedef struct SHTTransientDiagnostics {
	int errorCode;
	int configurationValid;
	int evaluationValid;
	int offendingStepInIndex;
	double offendingValue;
	int hpcSelected;
	int burnerSelected;
	int gtSelected;
	int ptSelected;
	/* P4 局部热反馈求解诊断，部件顺序固定为 HPC/Burner/GT/PT。 */
	int heatFeedbackApplied[SHT_HEAT_COMPONENT_COUNT];
	int heatFeedbackConverged[SHT_HEAT_COMPONENT_COUNT];
	int heatFeedbackIterationCount[SHT_HEAT_COMPONENT_COUNT];
	double heatFeedbackIterationResidual[SHT_HEAT_COMPONENT_COUNT];
	double heatFeedbackEnergyResidual[SHT_HEAT_COMPONENT_COUNT];
} SHTTransientDiagnostics;

/*
 * P3/P4 热状态纯求值结果。所有量均对应本次 DLL 调用的当前状态，不在 C 端
 * 积分或跨调用累积。heatFlow>0 表示气体向金属传热。
 */
typedef struct SHTTransientHeatEvaluation {
	double gasTemperature[SHT_METAL_NODE_COUNT];
	double componentRNIStar[SHT_HEAT_COMPONENT_COUNT];
	double timeConstant[SHT_METAL_NODE_COUNT];
	double heatConductance[SHT_METAL_NODE_COUNT];
	double heatFlow[SHT_METAL_NODE_COUNT];
	double componentHeatFlow[SHT_HEAT_COMPONENT_COUNT];
	double metalTemperatureDerivative[SHT_METAL_NODE_COUNT];
	double diskTimeConstant[SHT_DISK_NODE_COUNT];
	double diskTemperatureDerivative[SHT_DISK_NODE_COUNT];
	/* Visser追加状态和守恒诊断。正冷却热流表示金属向冷却气放热。 */
	double guideVaneTemperatureDerivative[SHT_VISSER_GUIDE_VANE_NODE_COUNT];
	double visserGuideVaneGasTemperature[SHT_VISSER_GUIDE_VANE_NODE_COUNT];
	double visserGuideVaneHeatFlow[SHT_VISSER_GUIDE_VANE_NODE_COUNT];
	double visserMainGasHeatFlow[SHT_HEAT_COMPONENT_COUNT];
	double visserMainGasFrontHeatFlow[SHT_HEAT_COMPONENT_COUNT];
	double visserMainGasRearHeatFlow[SHT_HEAT_COMPONENT_COUNT];
	double visserMetalCoolingHeatFlow[SHT_VISSER_METAL_NODE_COUNT];
	double visserDiskCoolingHeatFlow[SHT_DISK_NODE_COUNT];
	double visserRootDiskHeatFlow[SHT_DISK_NODE_COUNT];
	double visserCoolingBranchHeatFlow[SHT_VISSER_COOLING_BRANCH_COUNT];
	double visserCoolingInletTemperature[SHT_PHYSICAL_COOLING_ROUTE_COUNT];
	double visserCoolingOutletTemperature[SHT_PHYSICAL_COOLING_ROUTE_COUNT];
	double visserEnergyResidual;
	double visserNormalizedEnergyResidual;
} SHTTransientHeatEvaluation;

/*
 * P5 归一化叶尖间隙纯求值结果。部件顺序固定为 HPC、GT、PT。
 * flow/efficiencyMultiplier 是本次部件调用使用的动态倍率；关闭反馈时恒为 1。
 */
typedef struct SHTTransientClearanceEvaluation {
	double normalizedSpeed[SHT_CLEARANCE_COMPONENT_COUNT];
	double actualClearance[SHT_CLEARANCE_COMPONENT_COUNT];
	double steadyClearance[SHT_CLEARANCE_COMPONENT_COUNT];
	double dynamicClearance[SHT_CLEARANCE_COMPONENT_COUNT];
	double flowMultiplier[SHT_CLEARANCE_COMPONENT_COUNT];
	double efficiencyMultiplier[SHT_CLEARANCE_COMPONENT_COUNT];
	double surgeMarginMultiplier[SHT_COMPRESSOR_CLEARANCE_COUNT];
	int feedbackApplied[SHT_CLEARANCE_COMPONENT_COUNT];
} SHTTransientClearanceEvaluation;

void SHT_ResetTransientData(
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics);

/*
 * 只清除一次部件/气路求值产生的诊断，不改变已经解析并校验通过的
 * 瞬态配置、拓扑选择和部件选择标志。Newton及其有限差分每次调用
 * 物理模型前均应执行本函数，避免某个试探点的失败状态污染后续点。
 */
void SHT_ResetTransientEvaluationDiagnostics(
	SHTTransientDiagnostics *diagnostics);

/*
 * 共用标称热模型初始化边界。候选配置先在局部结构中完成全量
 * 校验，只有全部通过后才覆盖当前有效配置，避免失败调用留下半更新状态。
 */
void SHT_ResetThermalConfiguration(void);
/* 只允许起停零流量热浸入口临时打开，普通气路仍要求正流量。 */
void SHT_SetZeroFlowHeatEvaluationEnabled(int enabled);

int SHT_InitializeThermalConfiguration(
	int modelMode,
	int thermalModelMode,
	int configVersion,
	int parameterCount,
	const double *parameterVector);

int SHT_GetThermalConfigurationStatus(
	int modelMode,
	int thermalModelMode);

int SHT_ParseTransientInput(
	const double *stepIn,
	int modelMode,
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics);

void SHT_ResetHeatEvaluation(SHTTransientHeatEvaluation *evaluation);

void SHT_ResetClearanceEvaluation(SHTTransientClearanceEvaluation *evaluation);

/*
 * 求一个部件的单边界热体，不调用发动机部件、不推进状态。P4 包装层和
 * P3/P4 全状态求值共用此函数，避免热流公式出现两套实现。
 */
int SHT_EvaluateHeatComponent(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

int SHT_EvaluateHeatStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double componentFlow[SHT_HEAT_COMPONENT_COUNT],
	const double inletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double outletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT],
	const double diskTimeCorrection[SHT_DISK_NODE_COUNT],
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

/*
 * Visser主流热流和完整节点导数纯计算核。冷却气换热由发动机路由层
 * 使用实际焓函数计算，再把正的“金属向冷却气”热流传入本函数。
 */
int SHT_EvaluateVisserMainGasComponent(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	int componentIndex,
	double componentFlow,
	double inletTemperature,
	double outletTemperature,
	double heatTimeCorrection,
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

int SHT_EvaluateVisserHeatStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double componentFlow[SHT_HEAT_COMPONENT_COUNT],
	const double inletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double outletTemperature[SHT_HEAT_COMPONENT_COUNT],
	const double heatTimeCorrection[SHT_HEAT_COMPONENT_COUNT],
	const double diskTimeCorrection[SHT_DISK_NODE_COUNT],
	const double metalCoolingHeatFlow[SHT_VISSER_METAL_NODE_COUNT],
	const double diskCoolingHeatFlow[SHT_DISK_NODE_COUNT],
	SHTTransientHeatEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

/*
 * 用当前温度状态和绝对机械转速计算三个实际归一化间隙。epsilonSS 已由
 * M 端在本个已接受积分步开始时查询，并在本步全部子阶段中保持不变。
 */
int SHT_EvaluateClearanceStates(
	const SHTTransientControl *control,
	const SHTTransientState *state,
	const SHTTransientParameters *parameters,
	const double currentSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	const double designSpeed[SHT_CLEARANCE_COMPONENT_COUNT],
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

/*
 * 把四个有效动态间隙交换率转换为部件倍率。交换率顺序为
 * k_W_HPC、k_eta_HPC、k_eta_GT、k_eta_PT；有效值已经在发动机包装层
 * 按 k_eff=k_0*(1+K_k) 合成，本函数不做任何静默限幅。
 */
int SHT_EvaluateClearanceFeedback(
	const SHTTransientControl *control,
	const double exchangeRate[SHT_CLEARANCE_RATE_COUNT],
	const double kSM[SHT_COMPRESSOR_CLEARANCE_COUNT],
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

#endif

