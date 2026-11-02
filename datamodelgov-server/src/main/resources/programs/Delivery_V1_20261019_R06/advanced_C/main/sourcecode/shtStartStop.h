#ifndef SHT_START_STOP_H
#define SHT_START_STOP_H

#define SHT_START_STOP_CONFIG_VERSION 26091204
#define SHT_START_STOP_CONFIG_COUNT 30
#define SHT_START_STOP_CONFIG_LEGACY_VERSION 26082401
#define SHT_START_STOP_CONFIG_LEGACY_COUNT 29
#define SHT_START_STOP_PHYSICS_INPUT_COUNT 12
#define SHT_START_STOP_PHYSICS_OUTPUT_COUNT 24
/* 独立会话合同，不改变Engine布局或旧512/128接口。 */
#define SHT_FULL_MODE_VERSION 26100701
#define SHT_FULL_MODE_LOAD_COUNT 7
#define SHT_FULL_MODE_STATE_COUNT 64

enum SHTStartStopCommand
{
	SHT_START_STOP_COMMAND_HOLD = 0,
	SHT_START_STOP_COMMAND_START = 1,
	SHT_START_STOP_COMMAND_RUN = 2,
	SHT_START_STOP_COMMAND_SHUTDOWN = 3
};

enum SHTStartStopPhase
{
	SHT_START_STOP_PHASE_STOPPED = 0,
	SHT_START_STOP_PHASE_COLD_CRANK = 1,
	SHT_START_STOP_PHASE_IGNITION_DELAY = 2,
	SHT_START_STOP_PHASE_LIGHT_OFF = 3,
	SHT_START_STOP_PHASE_ACCELERATION = 4,
	SHT_START_STOP_PHASE_SELF_SUSTAIN = 5,
	SHT_START_STOP_PHASE_STARTER_CUTOUT = 6,
	SHT_START_STOP_PHASE_IDLE = 7,
	SHT_START_STOP_PHASE_RUN = 8,
	SHT_START_STOP_PHASE_SHUTDOWN = 9,
	SHT_START_STOP_PHASE_STOP_COMPLETE = 10
};

enum SHTStartStopEvent
{
	SHT_START_STOP_EVENT_NONE = 0,
	SHT_START_STOP_EVENT_START_COMMAND = 1,
	SHT_START_STOP_EVENT_IGNITION_BEGIN = 2,
	SHT_START_STOP_EVENT_LIGHT_OFF = 3,
	SHT_START_STOP_EVENT_SELF_SUSTAIN = 4,
	SHT_START_STOP_EVENT_STARTER_CUTOUT = 5,
	SHT_START_STOP_EVENT_IDLE_REACHED = 6,
	SHT_START_STOP_EVENT_SHUTDOWN_COMMAND = 7,
	SHT_START_STOP_EVENT_FREEWHEEL_DISENGAGED = 8,
	SHT_START_STOP_EVENT_STOP_COMPLETE = 9
};

typedef struct SHTStartStopConfig
{
	double designNpRpm;
	double designNgRpm;
	double idleNgRatio;
	double lightOffNgRatio;
	double selfSustainNgRatio;
	double starterCutoutNgRatio;
	double ignitionDelayS;
	double flameBuildS;
	double starterStallTorqueNm;
	double starterZeroTorqueSpeedRatio;
	double lightOffFuelKgPerS;
	double idleFuelKgPerS;
	double hpsInertiaKgM2;
	double ptEngineInertiaKgM2;
	double rotorReflectedInertiaKgM2;
	double hpsCoulombLossNm;
	double hpsViscousLossNmPerKrpm;
	double hpsWindageLossNmPerKrpm2;
	double ptCoulombLossNm;
	double ptViscousLossNmPerKrpm;
	double ptWindageLossNmPerKrpm2;
	double gtAccessoryPowerW;
	double designRotorPowerW;
	double thetaZeroDeg;
	double thetaDesignDeg;
	double profileTorqueFraction;
	double rotorCoulombLossNm;
	double rotorViscousLossNmPerKrpm;
	double freewheelSpeedToleranceRpm;
	double maximumGasTemperatureK;
} SHTStartStopConfig;

typedef struct SHTStartStopState
{
	int configured;
	int phase;
	int freewheelEngaged;
	int shutdownDisengaged;
	int freewheelEventPending;
	int lastEvent;
	double totalTimeS;
	double phaseTimeS;
	double flameFraction;
	double effectiveFuelKgPerS;
	double lastNgRpm;
	double lastNpRpm;
	double lastRotorEquivalentRpm;
} SHTStartStopState;

typedef struct SHTStartStopInput
{
	double timeStepS;
	int command;
	double ngRpm;
	double npRpm;
	double rotorEquivalentRpm;
	double hpsGasNetTorqueNm;
	double ptGasTorqueNm;
	double commandedFuelKgPerS;
	double collectivePitchDeg;
	int ignitionEnabled;
	double measuredGasTemperatureK;
	double hpsAccessoryPowerW;
} SHTStartStopInput;

typedef struct SHTStartStopOutput
{
	double ngDotRpmPerS;
	double npDotRpmPerS;
	double rotorEquivalentDotRpmPerS;
	int phase;
	double starterTorqueNm;
	double effectiveFuelKgPerS;
	double flameFraction;
	double hpsLossTorqueNm;
	double ptLossTorqueNm;
	double rotorLoadTorqueNm;
	double freewheelTorqueNm;
	int freewheelEngaged;
	int eventCode;
	int hotStartFlag;
	int hungStartFlag;
	int flameoutFlag;
	double requiredFreewheelTorqueNm;
	double hpsNetTorqueNm;
	double ptNetTorqueNm;
	double rotorNetTorqueNm;
	double phaseTimeS;
	double totalTimeS;
	double combustionEfficiency;
	int valid;
} SHTStartStopOutput;

void shtStartStopDefaultConfig(SHTStartStopConfig *config);
int shtStartStopConfigure(const SHTStartStopConfig *config);
void shtStartStopReset(double ngRpm, double npRpm,
	double rotorEquivalentRpm, int freewheelEngaged);
int shtStartStopPrepare(const SHTStartStopInput *input,
	double *effectiveFuelKgPerS, int *phase);
int shtStartStopAdvance(const SHTStartStopInput *input,
	SHTStartStopOutput *output);
const SHTStartStopState *shtStartStopGetState(void);
void shtStartStopRestoreState(const SHTStartStopState *state);

void shtStartStopSetTorqueRegularizationEnabled(int enabled);
int shtStartStopTorqueRegularizationEnabled(void);
double shtStartStopPowerToTorque(double powerW, double speedRpm,
	double transitionSpeedRpm);

int shtFullModeSetLoad(int version, int count, const double *values);
int shtFullModeExportState(int version, int count, double *values);
int shtFullModeImportState(int version, int count, const double *values);
void shtFullModeDisable(void);

#endif
