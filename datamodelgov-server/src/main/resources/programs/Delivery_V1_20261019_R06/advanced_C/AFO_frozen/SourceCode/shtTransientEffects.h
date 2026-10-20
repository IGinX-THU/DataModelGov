#ifndef SHT_TRANSIENT_EFFECTS_H
#define SHT_TRANSIENT_EFFECTS_H

/*
 * 2.5 三类瞬态效应的统一输入接口。
 *
 * 本文件集中定义接口解析以及可独立测试的瞬态效应纯计算核。把配置、
 * 状态和物理求值与发动机部件调用分开，可保证 interfaceVersion=0 时原
 * 模型完全沿用既有路径，也可按 P2/P3/P5 逐层放行新增物理通道。
 */

#define SHT_TRANSIENT_INTERFACE_BASELINE 0
#define SHT_TRANSIENT_INTERFACE_2502 2502
#define SHT_TRANSIENT_CONTROL_TOL 1.0e-6

#define SHT_COMPONENT_HPC 1
#define SHT_COMPONENT_BURNER 2
#define SHT_COMPONENT_GT 4
#define SHT_COMPONENT_PT 8

#define SHT_METAL_NODE_COUNT 10
#define SHT_DISK_NODE_COUNT 3
#define SHT_HEAT_COMPONENT_COUNT 4
#define SHT_CLEARANCE_COMPONENT_COUNT 3

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

/* stepIn 中 2.5 新接口的 C 下标。集中定义，禁止在调用点散落魔数。 */
#define SHT_INPUT_TEMPERATURE_START 300
#define SHT_INPUT_INTERFACE_VERSION 340
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
	int interfaceVersion;
	int thermalModelMode;
	int inertiaEnable;
	int heatStateEnable;
	int heatFeedbackEnable;
	int clearanceEnable;
	int clearanceFeedbackEnable;
	int componentMask;
} SHTTransientControl;

typedef struct SHTTransientState {
	double metalTemperature[10];
	double diskTemperature[3];
} SHTTransientState;

typedef struct SHTTransientParameters {
	double tau0[10];
	double heatCapacity0[10];
	double beta[10];
	double diskTau0[3];
	double referenceFlow[4];
	double referenceGasTemperature[4];
	/* HPC、GT、PT 各 10 项，采用一维数组以保持 MATLAB 头文件解析稳定。 */
	double clearanceParameter[30];
	double epsilonSS[3];
	double kSMHPC;
	/* HPC流量、HPC效率、GT效率、PT效率的标称间隙-性能灵敏度。 */
	double nominalClearanceExchangeRate[4];
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
	double surgeMarginMultiplier;
	int feedbackApplied[SHT_CLEARANCE_COMPONENT_COUNT];
} SHTTransientClearanceEvaluation;

void SHT_ResetTransientData(
	SHTTransientControl *control,
	SHTTransientState *state,
	SHTTransientParameters *parameters,
	SHTTransientDiagnostics *diagnostics);

int SHT_ParseTransientInput(
	const double *stepIn,
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
	const double exchangeRate[4],
	double kSMHPC,
	SHTTransientClearanceEvaluation *evaluation,
	SHTTransientDiagnostics *diagnostics);

#endif

