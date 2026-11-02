#include <float.h>
#include <math.h>
#include <string.h>
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include "shtStartStop.h"

static SHTStartStopConfig SHT_StartStopConfig;
static SHTStartStopState SHT_StartStopState;
static int SHT_TorqueRegularizationEnabled = 0;
static int SHT_StartStopConfigValid(const SHTStartStopConfig *config);
/* [启用,模式(1功率/2轴扭矩/3双总距),W,Nm,主桨Nm,尾桨Nm,功率接入rpm]。
 * 直接测功器负载与旋翼负载互斥，机械摩擦只由本内核计算一次。 */
static double SHT_FullModeLoad[SHT_FULL_MODE_LOAD_COUNT];
/* 快照配置按具名字段排列，不把结构体强制转换为double数组。 */
#define SHT_FULL_MODE_CONFIG_FIELDS(X) \
 X(0,designNpRpm) X(1,designNgRpm) X(2,idleNgRatio) \
 X(3,lightOffNgRatio) X(4,selfSustainNgRatio) X(5,starterCutoutNgRatio) \
 X(6,ignitionDelayS) X(7,flameBuildS) X(8,starterStallTorqueNm) \
 X(9,starterZeroTorqueSpeedRatio) X(10,lightOffFuelKgPerS) X(11,idleFuelKgPerS) \
 X(12,hpsInertiaKgM2) X(13,ptEngineInertiaKgM2) X(14,rotorReflectedInertiaKgM2) \
 X(15,hpsCoulombLossNm) X(16,hpsViscousLossNmPerKrpm) X(17,hpsWindageLossNmPerKrpm2) \
 X(18,ptCoulombLossNm) X(19,ptViscousLossNmPerKrpm) X(20,ptWindageLossNmPerKrpm2) \
 X(21,gtAccessoryPowerW) X(22,designRotorPowerW) X(23,thetaZeroDeg) \
 X(24,thetaDesignDeg) X(25,profileTorqueFraction) X(26,rotorCoulombLossNm) \
 X(27,rotorViscousLossNmPerKrpm) X(28,freewheelSpeedToleranceRpm) X(29,maximumGasTemperatureK)

void shtFullModeDisable(void)
{
	memset(SHT_FullModeLoad, 0, sizeof(SHT_FullModeLoad));
}

int shtFullModeSetLoad(int version, int count, const double *v)
{
	int i;
	if (version != SHT_FULL_MODE_VERSION || count != SHT_FULL_MODE_LOAD_COUNT || v == NULL)
		return -1;
	for (i = 0; i < count; ++i) if (!_finite(v[i])) return -1;
	if ((v[0] != 0.0 && v[0] != 1.0) ||
		(v[0] != 0.0 && (v[1] < 1.0 || v[1] > 3.0 || v[1] != floor(v[1]))) ||
		v[2] < 0.0 || v[3] < 0.0 || v[4] < 0.0 || v[5] < 0.0 || v[6] <= 0.0)
		return -1;
	memcpy(SHT_FullModeLoad, v, sizeof(SHT_FullModeLoad));
	return 0;
}

/* 仅序列化有明确含义的数值，不保存地址或编译器结构体填充字节。 */
int shtFullModeExportState(int version, int count, double *v)
{
	const SHTStartStopState *s = &SHT_StartStopState;
	int i;
	if (version != SHT_FULL_MODE_VERSION || count != SHT_FULL_MODE_STATE_COUNT || v == NULL) return -1;
	memset(v, 0, count * sizeof(double));
	for (i = 0; i < 7; ++i) v[i] = SHT_FullModeLoad[i];
	v[7] = s->configured; v[8] = s->phase; v[9] = s->freewheelEngaged;
	v[10] = s->shutdownDisengaged; v[11] = s->freewheelEventPending; v[12] = s->lastEvent;
	v[13] = s->totalTimeS; v[14] = s->phaseTimeS; v[15] = s->flameFraction;
	v[16] = s->effectiveFuelKgPerS; v[17] = s->lastNgRpm; v[18] = s->lastNpRpm;
	v[19] = s->lastRotorEquivalentRpm;
#define SHT_EXPORT_CONFIG(index,field) v[20+index] = SHT_StartStopConfig.field;
	SHT_FULL_MODE_CONFIG_FIELDS(SHT_EXPORT_CONFIG)
#undef SHT_EXPORT_CONFIG
	return 0;
}

int shtFullModeImportState(int version, int count, const double *v)
{
	SHTStartStopState s;
	SHTStartStopConfig config;
	int i;
	if (version != SHT_FULL_MODE_VERSION || count != SHT_FULL_MODE_STATE_COUNT || v == NULL) return -1;
	for (i = 0; i < count; ++i) if (!_finite(v[i])) return -1;
	for (i = 7; i <= 12; ++i) if (v[i] != floor(v[i])) return -1;
	if (v[7] != 1 || v[8] < 0 || v[8] > 10 || v[9] < 0 || v[9] > 1 ||
		v[10] < 0 || v[10] > 1 || v[11] < 0 || v[11] > 1 || v[12] < 0 || v[12] > 9 ||
		v[13] < 0 || v[14] < 0 || v[15] < 0 || v[15] > 1 ||
		v[16] < 0 || v[17] < 0 || v[18] < 0 || v[19] < 0) return -1;
	for (i = 50; i < count; ++i) if (v[i] != 0.0) return -1;
#define SHT_IMPORT_CONFIG(index,field) config.field = v[20+index];
	SHT_FULL_MODE_CONFIG_FIELDS(SHT_IMPORT_CONFIG)
#undef SHT_IMPORT_CONFIG
	/* 验证全部完成后再提交，失败不能损坏当前会话。 */
	if (!SHT_StartStopConfigValid(&config)) return -1;
	if (shtFullModeSetLoad(version, 7, v) != 0) return -1;
	memset(&s, 0, sizeof(s));
	s.configured=(int)v[7]; s.phase=(int)v[8]; s.freewheelEngaged=(int)v[9];
	s.shutdownDisengaged=(int)v[10]; s.freewheelEventPending=(int)v[11]; s.lastEvent=(int)v[12];
	s.totalTimeS=v[13]; s.phaseTimeS=v[14]; s.flameFraction=v[15];
	s.effectiveFuelKgPerS=v[16]; s.lastNgRpm=v[17]; s.lastNpRpm=v[18]; s.lastRotorEquivalentRpm=v[19];
	SHT_StartStopConfig=config; SHT_StartStopState=s;
	return 0;
}

static double SHT_StartStopClamp(double value, double minimum, double maximum)
{
	if (value < minimum) return minimum;
	if (value > maximum) return maximum;
	return value;
}

static double SHT_StartStopSmoothStep(double value)
{
	double x = SHT_StartStopClamp(value, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

static double SHT_StartStopSmoothSign(double speedRpm)
{
	/* 20 rpm只控制近零连续性，不代表物理静摩擦转速。 */
	return tanh(speedRpm / 20.0);
}

static double SHT_StartStopPowerLossTorque(double powerW, double speedRpm)
{
	double omega = speedRpm * PI / 30.0;
	double omegaRegularization = 20.0 * PI / 30.0;
	if (powerW <= 0.0)
		return 0.0;
	return powerW * omega /
		(omega * omega + omegaRegularization * omegaRegularization);
}

void shtStartStopDefaultConfig(SHTStartStopConfig *config)
{
	if (config == NULL) return;
	memset(config, 0, sizeof(*config));
	config->designNpRpm = 20800.0;
	config->designNgRpm = 38000.0;
	config->idleNgRatio = 0.65;
	config->lightOffNgRatio = 0.12;
	config->selfSustainNgRatio = 0.42;
	config->starterCutoutNgRatio = 0.55;
	config->ignitionDelayS = 0.50;
	config->flameBuildS = 1.50;
	config->starterStallTorqueNm = 95.0;
	config->starterZeroTorqueSpeedRatio = 0.62;
	config->lightOffFuelKgPerS = 0.025;
	config->idleFuelKgPerS = 0.070;
	config->hpsInertiaKgM2 = 0.283;
	config->ptEngineInertiaKgM2 = 0.40;
	config->rotorReflectedInertiaKgM2 = 1.20;
	config->hpsCoulombLossNm = 2.5;
	config->hpsViscousLossNmPerKrpm = 0.30;
	config->hpsWindageLossNmPerKrpm2 = 0.015;
	config->ptCoulombLossNm = 1.0;
	config->ptViscousLossNmPerKrpm = 0.12;
	config->ptWindageLossNmPerKrpm2 = 0.008;
	config->gtAccessoryPowerW = 3000.0;
	config->designRotorPowerW = 2176600.0;
	config->thetaZeroDeg = 0.0;
	config->thetaDesignDeg = 12.0;
	config->profileTorqueFraction = 0.15;
	config->rotorCoulombLossNm = 2.0;
	config->rotorViscousLossNmPerKrpm = 0.05;
	config->freewheelSpeedToleranceRpm = 5.0;
	/* 旧29项接口保留原值；新接口显式传入项目控制限温配置。 */
	config->maximumGasTemperatureK = 1250.0;
}

static int SHT_StartStopConfigValid(const SHTStartStopConfig *config)
{
	if (config == NULL) return 0;
	return config->designNpRpm > 0.0 && config->designNgRpm > 0.0 &&
		config->idleNgRatio > config->starterCutoutNgRatio &&
		config->starterCutoutNgRatio > config->selfSustainNgRatio &&
		config->selfSustainNgRatio > config->lightOffNgRatio &&
		config->lightOffNgRatio > 0.0 && config->ignitionDelayS >= 0.0 &&
		config->flameBuildS > 0.0 && config->starterStallTorqueNm > 0.0 &&
		config->starterZeroTorqueSpeedRatio > config->starterCutoutNgRatio &&
		config->hpsInertiaKgM2 > 0.0 &&
		config->ptEngineInertiaKgM2 > 0.0 &&
		config->rotorReflectedInertiaKgM2 > 0.0 &&
		config->thetaDesignDeg > config->thetaZeroDeg &&
		config->profileTorqueFraction >= 0.0 &&
		config->profileTorqueFraction < 1.0 &&
		config->rotorCoulombLossNm >= 0.0 &&
		config->rotorViscousLossNmPerKrpm >= 0.0 &&
		_finite(config->maximumGasTemperatureK) &&
		config->maximumGasTemperatureK > 0.0;
}

int shtStartStopConfigure(const SHTStartStopConfig *config)
{
	if (!SHT_StartStopConfigValid(config))
		return -1;
	SHT_StartStopConfig = *config;
	SHT_StartStopState.configured = 1;
	return 0;
}

void shtStartStopReset(double ngRpm, double npRpm,
	double rotorEquivalentRpm, int freewheelEngaged)
{
	int configured = SHT_StartStopState.configured;
	memset(&SHT_StartStopState, 0, sizeof(SHT_StartStopState));
	SHT_StartStopState.configured = configured;
	SHT_StartStopState.phase = SHT_START_STOP_PHASE_STOPPED;
	SHT_StartStopState.freewheelEngaged = freewheelEngaged ? 1 : 0;
	SHT_StartStopState.lastNgRpm = ngRpm;
	SHT_StartStopState.lastNpRpm = npRpm;
	SHT_StartStopState.lastRotorEquivalentRpm = rotorEquivalentRpm;
	shtFullModeDisable();
}

const SHTStartStopState *shtStartStopGetState(void)
{
	return &SHT_StartStopState;
}

void shtStartStopRestoreState(const SHTStartStopState *state)
{
	if (state != NULL)
		SHT_StartStopState = *state;
}

void shtStartStopSetTorqueRegularizationEnabled(int enabled)
{
	SHT_TorqueRegularizationEnabled = enabled ? 1 : 0;
}

int shtStartStopTorqueRegularizationEnabled(void)
{
	return SHT_TorqueRegularizationEnabled;
}

double shtStartStopPowerToTorque(double powerW, double speedRpm,
	double transitionSpeedRpm)
{
	double speedMagnitude;
	double ratio;
	double shape;
	double omegaReference;
	if (!SHT_TorqueRegularizationEnabled)
	{
		double denominatorRpm = speedRpm > transitionSpeedRpm ?
			speedRpm : transitionSpeedRpm;
        /* 普通入口保留原部件P*divby(omega)的计算顺序及除法保护。 */
        return powerW * divby(denominatorRpm * PI / 30.0);
	}
	if (transitionSpeedRpm <= 0.0 || !_finite(powerW) || !_finite(speedRpm))
		return 0.0;
	speedMagnitude = fabs(speedRpm);
	if (speedMagnitude >= transitionSpeedRpm)
		return powerW / (speedRpm * PI / 30.0);
	ratio = speedMagnitude / transitionSpeedRpm;
	/* 扩展图在锁转线上给出有限等效焓降功率，该量必须转换为有限的
	 * 锁转转矩，否则自由涡轮将永远不能从严格零速起步。多项式满足
	 * f(0)=1、f(1)=1、f'(1)=-1，并与高转速P/omega分支一阶衔接。 */
	shape = 1.0 + ratio - ratio * ratio;
	omegaReference = transitionSpeedRpm * PI / 30.0;
	return (speedRpm < 0.0 ? -1.0 : 1.0) * powerW / omegaReference * shape;
}

static void SHT_StartStopSetPhase(int phase, int eventCode)
{
	if (SHT_StartStopState.phase != phase)
	{
		SHT_StartStopState.phase = phase;
		SHT_StartStopState.phaseTimeS = 0.0;
	}
	SHT_StartStopState.lastEvent = eventCode;
}

static double SHT_StartStopCombustionEfficiency(double ngRatio)
{
	double denominator = SHT_StartStopConfig.idleNgRatio -
		SHT_StartStopConfig.lightOffNgRatio;
	double progress = (ngRatio - SHT_StartStopConfig.lightOffNgRatio) /
		denominator;
	return 0.25 + 0.75 * SHT_StartStopSmoothStep(progress);
}

int shtStartStopPrepare(const SHTStartStopInput *input,
	double *effectiveFuelKgPerS, int *phase)
{
	double ngRatio;
	double combustionEfficiency;
	if (input == NULL || effectiveFuelKgPerS == NULL || phase == NULL ||
		!SHT_StartStopState.configured || !_finite(input->timeStepS) ||
		input->timeStepS < 0.0 || !_finite(input->ngRpm) ||
		!_finite(input->npRpm) || !_finite(input->rotorEquivalentRpm) ||
		!_finite(input->commandedFuelKgPerS) || !_finite(input->collectivePitchDeg) ||
		!_finite(input->measuredGasTemperatureK) || !_finite(input->hpsAccessoryPowerW) ||
		input->ngRpm < 0.0 || input->npRpm < 0.0 ||
		input->rotorEquivalentRpm < 0.0 || input->commandedFuelKgPerS < 0.0 ||
		input->command < SHT_START_STOP_COMMAND_HOLD ||
		input->command > (SHT_FullModeLoad[0] != 0.0 ? 6 : SHT_START_STOP_COMMAND_SHUTDOWN))
		return -1;
	SHT_StartStopState.lastEvent = SHT_START_STOP_EVENT_NONE;
	ngRatio = input->ngRpm / SHT_StartStopConfig.designNgRpm;
	/* 新合同4=人工慢车、5=无点火冷吹、6=退出冷吹；旧合同不接受这些值。 */
	if (SHT_FullModeLoad[0] != 0.0 && input->command == 4 &&
		SHT_StartStopState.phase == SHT_START_STOP_PHASE_RUN)
		SHT_StartStopSetPhase(SHT_START_STOP_PHASE_IDLE, SHT_START_STOP_EVENT_NONE);
	if (input->command == SHT_START_STOP_COMMAND_SHUTDOWN || input->command == 6)
	{
		if (SHT_StartStopState.phase != SHT_START_STOP_PHASE_SHUTDOWN &&
			SHT_StartStopState.phase != SHT_START_STOP_PHASE_STOP_COMPLETE)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_SHUTDOWN,
				SHT_START_STOP_EVENT_SHUTDOWN_COMMAND);
	}
	else if (input->command == SHT_START_STOP_COMMAND_START ||
		input->command == SHT_START_STOP_COMMAND_RUN || input->command == 5 || input->command == 4)
	{
		/* RUN指令不能绕过未完成的起动序列。只有显式START可从停车态
		 * 发起冷转；已经起动后，即使上层提前给出RUN，仍按转速门限依次
		 * 经过点火、自持、起动机切除和慢车。 */
		if ((input->command == SHT_START_STOP_COMMAND_START || input->command == 5) &&
			(SHT_StartStopState.phase == SHT_START_STOP_PHASE_STOPPED ||
			SHT_StartStopState.phase == SHT_START_STOP_PHASE_STOP_COMPLETE)
			)
		{
			SHT_StartStopState.freewheelEngaged = 1;
			SHT_StartStopState.shutdownDisengaged = 0;
			SHT_StartStopState.freewheelEventPending = 0;
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_COLD_CRANK,
				SHT_START_STOP_EVENT_START_COMMAND);
		}
		if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_COLD_CRANK &&
			input->ignitionEnabled && input->command != 5 &&
			ngRatio >= SHT_StartStopConfig.lightOffNgRatio)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_IGNITION_DELAY,
				SHT_START_STOP_EVENT_IGNITION_BEGIN);
		if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_IGNITION_DELAY &&
			SHT_StartStopState.phaseTimeS >= SHT_StartStopConfig.ignitionDelayS)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_LIGHT_OFF,
				SHT_START_STOP_EVENT_LIGHT_OFF);
		if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_LIGHT_OFF &&
			SHT_StartStopState.flameFraction >= 1.0 - 1.0e-12)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_ACCELERATION,
				SHT_START_STOP_EVENT_NONE);
		if ((SHT_StartStopState.phase == SHT_START_STOP_PHASE_ACCELERATION ||
			 SHT_StartStopState.phase == SHT_START_STOP_PHASE_LIGHT_OFF) &&
			ngRatio >= SHT_StartStopConfig.selfSustainNgRatio)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_SELF_SUSTAIN,
				SHT_START_STOP_EVENT_SELF_SUSTAIN);
		/* 转速门限不能代替点火和火焰建立。冷转阶段即使由外部设备拖到
		 * 较高转速，也必须保持零有效燃油，不能跳转到起动机切除或慢车。 */
		if (SHT_StartStopState.phase >= SHT_START_STOP_PHASE_LIGHT_OFF &&
			SHT_StartStopState.phase <= SHT_START_STOP_PHASE_SELF_SUSTAIN &&
			ngRatio >= SHT_StartStopConfig.starterCutoutNgRatio)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_STARTER_CUTOUT,
				SHT_START_STOP_EVENT_STARTER_CUTOUT);
		if (SHT_StartStopState.phase >= SHT_START_STOP_PHASE_LIGHT_OFF &&
			ngRatio >= SHT_StartStopConfig.idleNgRatio &&
			SHT_StartStopState.phase < SHT_START_STOP_PHASE_IDLE)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_IDLE,
				SHT_START_STOP_EVENT_IDLE_REACHED);
		if (input->command == SHT_START_STOP_COMMAND_RUN &&
			SHT_StartStopState.phase == SHT_START_STOP_PHASE_IDLE &&
			SHT_StartStopState.phaseTimeS > 0.0)
			SHT_StartStopSetPhase(SHT_START_STOP_PHASE_RUN,
				SHT_START_STOP_EVENT_NONE);
	}

	if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_LIGHT_OFF)
		SHT_StartStopState.flameFraction = SHT_StartStopClamp(
			SHT_StartStopState.phaseTimeS / SHT_StartStopConfig.flameBuildS,
			0.0, 1.0);
	else if (SHT_StartStopState.phase >= SHT_START_STOP_PHASE_ACCELERATION &&
		SHT_StartStopState.phase < SHT_START_STOP_PHASE_SHUTDOWN)
		SHT_StartStopState.flameFraction = 1.0;
	else if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_SHUTDOWN ||
		SHT_StartStopState.phase == SHT_START_STOP_PHASE_STOPPED ||
		SHT_StartStopState.phase == SHT_START_STOP_PHASE_STOP_COMPLETE)
		SHT_StartStopState.flameFraction = 0.0;

	combustionEfficiency = SHT_StartStopCombustionEfficiency(ngRatio);
	SHT_StartStopState.effectiveFuelKgPerS =
		(input->command == SHT_START_STOP_COMMAND_SHUTDOWN || input->command == 6 || input->command == 5 ||
		 SHT_StartStopState.phase < SHT_START_STOP_PHASE_LIGHT_OFF) ? 0.0 :
		SHT_StartStopClamp(input->commandedFuelKgPerS, 0.0,
			10.0 * SHT_StartStopConfig.idleFuelKgPerS) *
		SHT_StartStopState.flameFraction * combustionEfficiency;
	*effectiveFuelKgPerS = SHT_StartStopState.effectiveFuelKgPerS;
	*phase = SHT_StartStopState.phase;
	return 0;
}

static double SHT_StartStopStarterTorque(double ngRpm)
{
	double zeroTorqueSpeed = SHT_StartStopConfig.designNgRpm *
		SHT_StartStopConfig.starterZeroTorqueSpeedRatio;
	double ratio;
	if (SHT_StartStopState.phase < SHT_START_STOP_PHASE_COLD_CRANK ||
		SHT_StartStopState.phase > SHT_START_STOP_PHASE_SELF_SUSTAIN)
		return 0.0;
	ratio = SHT_StartStopClamp(ngRpm / zeroTorqueSpeed, 0.0, 1.0);
	return SHT_StartStopConfig.starterStallTorqueNm *
		(1.0 - SHT_StartStopSmoothStep(ratio));
}

static double SHT_StartStopShaftLoss(double speedRpm, double coulomb,
	double viscousPerKrpm, double windagePerKrpm2, double accessoryPowerW)
{
	double krpm = fabs(speedRpm) / 1000.0;
	return coulomb * SHT_StartStopSmoothSign(speedRpm) +
		viscousPerKrpm * krpm + windagePerKrpm2 * krpm * krpm +
		SHT_StartStopPowerLossTorque(accessoryPowerW, speedRpm);
}

static double SHT_StartStopRotorLoad(double rotorEquivalentRpm,
	double collectivePitchDeg)
{
	double designOmega = SHT_StartStopConfig.designNpRpm * PI / 30.0;
	double designTorque = SHT_StartStopConfig.designRotorPowerW / designOmega;
	double speedRatio = SHT_StartStopClamp(
		fabs(rotorEquivalentRpm) / SHT_StartStopConfig.designNpRpm, 0.0, 1.5);
	double pitchRatio = SHT_StartStopClamp(
		(collectivePitchDeg - SHT_StartStopConfig.thetaZeroDeg) /
		(SHT_StartStopConfig.thetaDesignDeg - SHT_StartStopConfig.thetaZeroDeg),
		0.0, 1.5);
	double pitchLoad = SHT_StartStopConfig.profileTorqueFraction +
		(1.0 - SHT_StartStopConfig.profileTorqueFraction) *
		pow(pitchRatio, 1.5);
	return designTorque * pitchLoad * speedRatio * speedRatio +
		SHT_StartStopConfig.rotorCoulombLossNm *
			SHT_StartStopSmoothSign(rotorEquivalentRpm) +
		SHT_StartStopConfig.rotorViscousLossNmPerKrpm *
			fabs(rotorEquivalentRpm) / 1000.0;
}

int shtStartStopAdvance(const SHTStartStopInput *input,
	SHTStartStopOutput *output)
{
	double starterTorque;
	double hpsLoss;
	double ptLoss;
	double rotorLoad;
	double hpsNet;
	double ptAvailable;
	double commonAngularAcceleration;
	double requiredFreewheelTorque;
	double rotorNet;
	double accessoryPower;
	double accessorySpeedRatio;
	double ngRatio;
	double directTorque = 0.0;
	int directLoad = SHT_FullModeLoad[0] != 0.0 && SHT_FullModeLoad[1] != 3.0;
	if (input == NULL || output == NULL || !SHT_StartStopState.configured ||
		!_finite(input->timeStepS) || input->timeStepS < 0.0)
		return -1;
	memset(output, 0, sizeof(*output));
	/* 若停车指令与自由轮解脱发生在同一计算步，先输出停车事件，下一步再
	 * 输出解脱事件。物理解脱本身不延迟，因而不会产生负向传递转矩。 */
	if (SHT_StartStopState.freewheelEventPending &&
		SHT_StartStopState.lastEvent == SHT_START_STOP_EVENT_NONE)
	{
		SHT_StartStopState.lastEvent =
			SHT_START_STOP_EVENT_FREEWHEEL_DISENGAGED;
		SHT_StartStopState.freewheelEventPending = 0;
	}
	starterTorque = SHT_StartStopStarterTorque(input->ngRpm);
	accessoryPower = input->hpsAccessoryPowerW >= 0.0 ?
		input->hpsAccessoryPowerW : SHT_StartStopConfig.gtAccessoryPowerW;
	/* 起动过程中发电机等恒功率负载尚未全部接入，泵类负载也随转速下降。
	 * 用慢车转速归一化的平滑门控使附件功率从零连续建立，避免把额定功率
	 * 在近零转速直接除以角速度而产生非物理的大转矩。慢车及以上保持额定值。 */
	accessorySpeedRatio = fabs(input->ngRpm) /
		(SHT_StartStopConfig.idleNgRatio * SHT_StartStopConfig.designNgRpm);
	accessoryPower *= SHT_StartStopSmoothStep(accessorySpeedRatio);
	hpsLoss = SHT_StartStopShaftLoss(input->ngRpm,
		SHT_StartStopConfig.hpsCoulombLossNm,
		SHT_StartStopConfig.hpsViscousLossNmPerKrpm,
		SHT_StartStopConfig.hpsWindageLossNmPerKrpm2, accessoryPower);
	ptLoss = SHT_StartStopShaftLoss(input->npRpm,
		SHT_StartStopConfig.ptCoulombLossNm,
		SHT_StartStopConfig.ptViscousLossNmPerKrpm,
		SHT_StartStopConfig.ptWindageLossNmPerKrpm2, 0.0);
	rotorLoad = SHT_StartStopRotorLoad(input->rotorEquivalentRpm,
		input->collectivePitchDeg);
	if (SHT_FullModeLoad[0] != 0.0)
	{
		/* 双总距气动扭矩由M端纯负载函数计算，包含独立旋翼侧转速。
		 * 恒功率/恒扭矩为测功器直接轴负载，不再扣旋翼气动负载。 */
		rotorLoad = SHT_StartStopConfig.rotorCoulombLossNm *
			SHT_StartStopSmoothSign(input->rotorEquivalentRpm) +
			SHT_StartStopConfig.rotorViscousLossNmPerKrpm * input->rotorEquivalentRpm / 1000.0;
		if (!directLoad) rotorLoad += SHT_FullModeLoad[4] + SHT_FullModeLoad[5];
		else if (SHT_FullModeLoad[1] == 2.0) directTorque = SHT_FullModeLoad[3];
		else if (input->npRpm >= SHT_FullModeLoad[6])
			directTorque = SHT_FullModeLoad[2] / (input->npRpm * PI / 30.0);
		/* 低于显式接入转速时测功器功率负载脱开，不使用小分母。 */
	}
	hpsNet = input->hpsGasNetTorqueNm + starterTorque - hpsLoss;
	output->ngDotRpmPerS = hpsNet / SHT_StartStopConfig.hpsInertiaKgM2 *
		30.0 / PI;
	ptAvailable = input->ptGasTorqueNm - ptLoss;
	commonAngularAcceleration = (ptAvailable - rotorLoad) /
		(SHT_StartStopConfig.ptEngineInertiaKgM2 +
		 SHT_StartStopConfig.rotorReflectedInertiaKgM2);
	requiredFreewheelTorque =
		SHT_StartStopConfig.rotorReflectedInertiaKgM2 *
		commonAngularAcceleration + rotorLoad;
	if ((SHT_StartStopState.phase == SHT_START_STOP_PHASE_SHUTDOWN ||
		(SHT_FullModeLoad[0] != 0.0 && !directLoad)) &&
		SHT_StartStopState.freewheelEngaged &&
		(input->rotorEquivalentRpm > input->npRpm +
		 SHT_StartStopConfig.freewheelSpeedToleranceRpm ||
		 requiredFreewheelTorque < 0.0))
	{
		SHT_StartStopState.freewheelEngaged = 0;
		SHT_StartStopState.shutdownDisengaged = 1;
		if (SHT_StartStopState.lastEvent == SHT_START_STOP_EVENT_NONE)
			SHT_StartStopState.lastEvent =
				SHT_START_STOP_EVENT_FREEWHEEL_DISENGAGED;
		else
			SHT_StartStopState.freewheelEventPending = 1;
	}
	if (SHT_FullModeLoad[0] != 0.0 && !directLoad &&
		!SHT_StartStopState.freewheelEngaged && SHT_StartStopState.phase < 9 &&
		input->npRpm >= input->rotorEquivalentRpm && requiredFreewheelTorque >= 0.0)
		SHT_StartStopState.freewheelEngaged = 1;
	if (directLoad)
	{
		SHT_StartStopState.freewheelEngaged = 0;
		output->npDotRpmPerS = (ptAvailable - directTorque) /
			SHT_StartStopConfig.ptEngineInertiaKgM2 * 30.0 / PI;
		rotorNet = -rotorLoad;
		output->rotorEquivalentDotRpmPerS = rotorNet /
			SHT_StartStopConfig.rotorReflectedInertiaKgM2 * 30.0 / PI;
		output->freewheelTorqueNm = directTorque;
		requiredFreewheelTorque = directTorque;
	}
	else if (SHT_StartStopState.freewheelEngaged)
	{
		output->npDotRpmPerS = commonAngularAcceleration * 30.0 / PI;
		output->rotorEquivalentDotRpmPerS = output->npDotRpmPerS;
		output->freewheelTorqueNm = requiredFreewheelTorque;
		rotorNet = requiredFreewheelTorque - rotorLoad;
	}
	else
	{
		output->npDotRpmPerS = ptAvailable /
			SHT_StartStopConfig.ptEngineInertiaKgM2 * 30.0 / PI;
		rotorNet = -rotorLoad;
		output->rotorEquivalentDotRpmPerS = rotorNet /
			SHT_StartStopConfig.rotorReflectedInertiaKgM2 * 30.0 / PI;
		output->freewheelTorqueNm = 0.0;
	}
	ngRatio = input->ngRpm / SHT_StartStopConfig.designNgRpm;
	if (SHT_StartStopState.phase == SHT_START_STOP_PHASE_SHUTDOWN &&
		input->ngRpm <= 0.5 && input->npRpm <= 0.5)
		SHT_StartStopSetPhase(SHT_START_STOP_PHASE_STOP_COMPLETE,
			SHT_START_STOP_EVENT_STOP_COMPLETE);
	output->phase = SHT_StartStopState.phase;
	output->starterTorqueNm = starterTorque;
	output->effectiveFuelKgPerS = SHT_StartStopState.effectiveFuelKgPerS;
	output->flameFraction = SHT_StartStopState.flameFraction;
	output->hpsLossTorqueNm = hpsLoss;
	output->ptLossTorqueNm = ptLoss;
	output->rotorLoadTorqueNm = rotorLoad;
	output->freewheelEngaged = SHT_StartStopState.freewheelEngaged;
	output->eventCode = SHT_StartStopState.lastEvent;
	output->hotStartFlag = input->measuredGasTemperatureK >
		SHT_StartStopConfig.maximumGasTemperatureK;
	output->hungStartFlag =
		SHT_StartStopState.phase == SHT_START_STOP_PHASE_ACCELERATION &&
		SHT_StartStopState.phaseTimeS > 30.0 &&
		ngRatio < SHT_StartStopConfig.selfSustainNgRatio;
	output->flameoutFlag =
		SHT_StartStopState.phase >= SHT_START_STOP_PHASE_LIGHT_OFF &&
		SHT_StartStopState.phase < SHT_START_STOP_PHASE_SHUTDOWN &&
		input->commandedFuelKgPerS < 0.5 * SHT_StartStopConfig.lightOffFuelKgPerS;
	output->requiredFreewheelTorqueNm = requiredFreewheelTorque;
	output->hpsNetTorqueNm = hpsNet;
	output->ptNetTorqueNm = ptAvailable - (directLoad ? directTorque :
		(SHT_StartStopState.freewheelEngaged ? requiredFreewheelTorque : 0.0));
	output->rotorNetTorqueNm = rotorNet;
	output->phaseTimeS = SHT_StartStopState.phaseTimeS;
	output->totalTimeS = SHT_StartStopState.totalTimeS;
	output->combustionEfficiency = SHT_StartStopCombustionEfficiency(ngRatio);
	output->valid = _finite(output->ngDotRpmPerS) &&
		_finite(output->npDotRpmPerS) &&
		_finite(output->rotorEquivalentDotRpmPerS);
	SHT_StartStopState.totalTimeS += input->timeStepS;
	SHT_StartStopState.phaseTimeS += input->timeStepS;
	SHT_StartStopState.lastNgRpm = input->ngRpm;
	SHT_StartStopState.lastNpRpm = input->npRpm;
	SHT_StartStopState.lastRotorEquivalentRpm = input->rotorEquivalentRpm;
	return output->valid ? 0 : -1;
}
