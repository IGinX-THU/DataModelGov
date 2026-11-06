#ifndef SHT_LOW_SPEED_SOLVER_H
#define SHT_LOW_SPEED_SOLVER_H

#define SHT_LOW_SPEED_SOLVER_MAX_DIMENSION 16

typedef struct SHTLowSpeedSolverOptions
{
	int maxIterations;
	int maxBacktracks;
	double accuracyRequired;
	double disturbanceFactor;
	double minimumStepScale;
	double pivotRelativeTolerance;
	double rankRelativeTolerance;
} SHTLowSpeedSolverOptions;

typedef struct SHTLowSpeedSolverDiagnostics
{
	int status;
	int converged;
	int dimension;
	int iterationCount;
	int functionEvaluationCount;
	int jacobianEvaluationCount;
	int acceptedStepCount;
	int rejectedStepCount;
	int effectiveRank;
	int weakestVariableIndex;
	int boundaryHitCount;
	double initialRms;
	double finalRms;
	double finalMaximumAbsoluteResidual;
	double bestRms;
	double lastAcceptedStepScale;
	double scaledJacobianCondition;
	double variable[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION];
	double residual[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION];
	double jacobianColumnNorm[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION];
	double weakestDirection[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION];
	int boundaryHit[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION];
} SHTLowSpeedSolverDiagnostics;

enum SHTLowSpeedSolverStatus
{
	SHT_LOW_SPEED_SOLVER_CONVERGED = 0,
	SHT_LOW_SPEED_SOLVER_MAX_ITERATIONS = 1,
	SHT_LOW_SPEED_SOLVER_STALLED = 2,
	SHT_LOW_SPEED_SOLVER_MODEL_ERROR = 3,
	SHT_LOW_SPEED_SOLVER_SINGULAR_JACOBIAN = 4,
	SHT_LOW_SPEED_SOLVER_INVALID_INPUT = 5,
	SHT_LOW_SPEED_SOLVER_ZERO_HOLD = 6
};

void shtLowSpeedSolverDefaultOptions(SHTLowSpeedSolverOptions *options);
void shtLowSpeedSolverResetDiagnostics(SHTLowSpeedSolverDiagnostics *diagnostics);

int shtLowSpeedNewtonSolver(
	int functionModel(double *variable, double *residual, int dimension),
	int dimension,
	double *variable,
	const double *minimum,
	const double *maximum,
	const double *maximumStep,
	const SHTLowSpeedSolverOptions *options,
	SHTLowSpeedSolverDiagnostics *diagnostics);

#endif
