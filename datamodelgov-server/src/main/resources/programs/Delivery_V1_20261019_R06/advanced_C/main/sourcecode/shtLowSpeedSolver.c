#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "shtLowSpeedSolver.h"

static double SHT_LowSpeedMaximum(double first, double second)
{
	return first > second ? first : second;
}

static double SHT_LowSpeedMinimum(double first, double second)
{
	return first < second ? first : second;
}

static double SHT_LowSpeedClamp(double value, double minimum, double maximum)
{
	return SHT_LowSpeedMinimum(SHT_LowSpeedMaximum(value, minimum), maximum);
}

static int SHT_LowSpeedFiniteVector(const double *value, int dimension)
{
	int i;
	for (i = 0; i < dimension; ++i)
		if (!_finite(value[i]))
			return 0;
	return 1;
}

static double SHT_LowSpeedRms(const double *residual, int dimension)
{
	double sum = 0.0;
	int i;
	for (i = 0; i < dimension; ++i)
		sum += residual[i] * residual[i];
	return sqrt(sum / (double)dimension);
}

static double SHT_LowSpeedMaxAbs(const double *value, int dimension)
{
	double maximum = 0.0;
	int i;
	for (i = 0; i < dimension; ++i)
		maximum = SHT_LowSpeedMaximum(maximum, fabs(value[i]));
	return maximum;
}

void shtLowSpeedSolverDefaultOptions(SHTLowSpeedSolverOptions *options)
{
	if (options == NULL)
		return;
	options->maxIterations = 60;
	options->maxBacktracks = 10;
	options->accuracyRequired = 1.0e-8;
	options->disturbanceFactor = 1.0e-4;
	options->minimumStepScale = 1.0 / 1024.0;
	options->pivotRelativeTolerance = 1.0e-11;
	options->rankRelativeTolerance = 1.0e-9;
}

void shtLowSpeedSolverResetDiagnostics(SHTLowSpeedSolverDiagnostics *diagnostics)
{
	if (diagnostics == NULL)
		return;
	memset(diagnostics, 0, sizeof(*diagnostics));
	diagnostics->status = SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	diagnostics->weakestVariableIndex = -1;
	diagnostics->scaledJacobianCondition = DBL_MAX;
}

static void SHT_LowSpeedToPhysical(
	const double *normalized,
	double *physical,
	const double *minimum,
	const double *maximum,
	int dimension)
{
	int i;
	for (i = 0; i < dimension; ++i)
		physical[i] = minimum[i] + normalized[i] * (maximum[i] - minimum[i]);
}

static int SHT_LowSpeedEvaluate(
	int functionModel(double *, double *, int),
	const double *normalized,
	double *physical,
	double *residual,
	const double *minimum,
	const double *maximum,
	int dimension,
	SHTLowSpeedSolverDiagnostics *diagnostics)
{
	int status;
	SHT_LowSpeedToPhysical(normalized, physical, minimum, maximum, dimension);
	status = functionModel(physical, residual, dimension);
	diagnostics->functionEvaluationCount++;
	if (status != 0 || !SHT_LowSpeedFiniteVector(residual, dimension))
		return SHT_LOW_SPEED_SOLVER_MODEL_ERROR;
	return SHT_LOW_SPEED_SOLVER_CONVERGED;
}

static int SHT_LowSpeedBuildJacobian(
	int functionModel(double *, double *, int),
	const double *normalized,
	const double *baseResidual,
	double *jacobian,
	double *physical,
	double *trialNormalized,
	double *trialResidual,
	const double *minimum,
	const double *maximum,
	int dimension,
	double disturbance,
	SHTLowSpeedSolverDiagnostics *diagnostics)
{
	int column;
	int row;
	int status;
	double signedStep;
	for (column = 0; column < dimension; ++column)
	{
		memcpy(trialNormalized, normalized,
			(size_t)dimension * sizeof(double));
		signedStep = disturbance;
		if (normalized[column] + signedStep > 1.0)
			signedStep = -disturbance;
		if (normalized[column] + signedStep < 0.0)
			return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
		trialNormalized[column] += signedStep;
		status = SHT_LowSpeedEvaluate(functionModel, trialNormalized,
			physical, trialResidual, minimum, maximum, dimension, diagnostics);
		if (status != SHT_LOW_SPEED_SOLVER_CONVERGED)
			return status;
		for (row = 0; row < dimension; ++row)
			jacobian[row * dimension + column] =
				(trialResidual[row] - baseResidual[row]) / signedStep;
	}
	diagnostics->jacobianEvaluationCount++;
	return SHT_LOW_SPEED_SOLVER_CONVERGED;
}

/* 带相对主元门限的高斯消元。矩阵和右端项均为工作副本。 */
static int SHT_LowSpeedSolveLinear(
	double *matrix,
	double *rightHandSide,
	double *solution,
	int dimension,
	double relativePivotTolerance)
{
	double matrixMaximum = SHT_LowSpeedMaxAbs(matrix, dimension * dimension);
	double pivotTolerance = relativePivotTolerance *
		SHT_LowSpeedMaximum(matrixMaximum, DBL_MIN);
	int column;
	int row;
	int k;
	int pivotRow;
	double pivot;
	double factor;
	double temporary;
	if (!_finite(matrixMaximum) || matrixMaximum <= DBL_MIN)
		return 0;
	for (column = 0; column < dimension; ++column)
	{
		pivotRow = column;
		pivot = fabs(matrix[column * dimension + column]);
		for (row = column + 1; row < dimension; ++row)
		{
			if (fabs(matrix[row * dimension + column]) > pivot)
			{
				pivot = fabs(matrix[row * dimension + column]);
				pivotRow = row;
			}
		}
		if (pivot <= pivotTolerance)
			return 0;
		if (pivotRow != column)
		{
			for (k = column; k < dimension; ++k)
			{
				temporary = matrix[column * dimension + k];
				matrix[column * dimension + k] =
					matrix[pivotRow * dimension + k];
				matrix[pivotRow * dimension + k] = temporary;
			}
			temporary = rightHandSide[column];
			rightHandSide[column] = rightHandSide[pivotRow];
			rightHandSide[pivotRow] = temporary;
		}
		for (row = column + 1; row < dimension; ++row)
		{
			factor = matrix[row * dimension + column] /
				matrix[column * dimension + column];
			matrix[row * dimension + column] = 0.0;
			for (k = column + 1; k < dimension; ++k)
				matrix[row * dimension + k] -=
					factor * matrix[column * dimension + k];
			rightHandSide[row] -= factor * rightHandSide[column];
		}
	}
	for (row = dimension - 1; row >= 0; --row)
	{
		temporary = rightHandSide[row];
		for (k = row + 1; k < dimension; ++k)
			temporary -= matrix[row * dimension + k] * solution[k];
		solution[row] = temporary / matrix[row * dimension + row];
	}
	return SHT_LowSpeedFiniteVector(solution, dimension);
}

/*
 * 对列归一化后的 J^T J 做对称Jacobi特征分解。维数最多9，使用该
 * 直接算法比引入外部线性代数依赖更透明，也足以给出秩、条件数和
 * 最弱右奇异方向诊断。它不参与Newton步计算，只用于说明病态来源。
 */
static void SHT_LowSpeedAnalyzeJacobian(
	const double *jacobian,
	int dimension,
	double rankRelativeTolerance,
	SHTLowSpeedSolverDiagnostics *diagnostics)
{
	double normal[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION *
		SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double vector[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION *
		SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double eigenvalue[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double largest;
	double smallestPositive = DBL_MAX;
	double threshold;
	double app;
	double aqq;
	double apq;
	double angle;
	double cosine;
	double sine;
	double valueP;
	double valueQ;
	int i;
	int j;
	int k;
	int sweep;
	int p = 0;
	int q = 1;
	int weakest = 0;
	for (j = 0; j < dimension; ++j)
	{
		double sum = 0.0;
		for (i = 0; i < dimension; ++i)
			sum += jacobian[i * dimension + j] *
				jacobian[i * dimension + j];
		diagnostics->jacobianColumnNorm[j] = sqrt(sum);
	}
	for (i = 0; i < dimension; ++i)
	{
		vector[i * dimension + i] = 1.0;
		for (j = 0; j < dimension; ++j)
		{
			double sum = 0.0;
			double scaleI = SHT_LowSpeedMaximum(
				diagnostics->jacobianColumnNorm[i], DBL_MIN);
			double scaleJ = SHT_LowSpeedMaximum(
				diagnostics->jacobianColumnNorm[j], DBL_MIN);
			for (k = 0; k < dimension; ++k)
				sum += jacobian[k * dimension + i] *
					jacobian[k * dimension + j];
			normal[i * dimension + j] = sum / (scaleI * scaleJ);
		}
	}
	for (sweep = 0; sweep < 60 * dimension * dimension; ++sweep)
	{
		double maximumOffDiagonal = 0.0;
		for (i = 0; i < dimension; ++i)
			for (j = i + 1; j < dimension; ++j)
				if (fabs(normal[i * dimension + j]) > maximumOffDiagonal)
				{
					maximumOffDiagonal = fabs(normal[i * dimension + j]);
					p = i;
					q = j;
				}
		if (maximumOffDiagonal <= 64.0 * DBL_EPSILON)
			break;
		app = normal[p * dimension + p];
		aqq = normal[q * dimension + q];
		apq = normal[p * dimension + q];
		angle = 0.5 * atan2(2.0 * apq, aqq - app);
		cosine = cos(angle);
		sine = sin(angle);
		for (k = 0; k < dimension; ++k)
		{
			if (k != p && k != q)
			{
				valueP = normal[k * dimension + p];
				valueQ = normal[k * dimension + q];
				normal[k * dimension + p] = cosine * valueP - sine * valueQ;
				normal[p * dimension + k] = normal[k * dimension + p];
				normal[k * dimension + q] = sine * valueP + cosine * valueQ;
				normal[q * dimension + k] = normal[k * dimension + q];
			}
			valueP = vector[k * dimension + p];
			valueQ = vector[k * dimension + q];
			vector[k * dimension + p] = cosine * valueP - sine * valueQ;
			vector[k * dimension + q] = sine * valueP + cosine * valueQ;
		}
		normal[p * dimension + p] = cosine * cosine * app -
			2.0 * sine * cosine * apq + sine * sine * aqq;
		normal[q * dimension + q] = sine * sine * app +
			2.0 * sine * cosine * apq + cosine * cosine * aqq;
		normal[p * dimension + q] = 0.0;
		normal[q * dimension + p] = 0.0;
	}
	largest = 0.0;
	for (i = 0; i < dimension; ++i)
	{
		eigenvalue[i] = SHT_LowSpeedMaximum(normal[i * dimension + i], 0.0);
		largest = SHT_LowSpeedMaximum(largest, eigenvalue[i]);
	}
	threshold = rankRelativeTolerance * rankRelativeTolerance * largest;
	diagnostics->effectiveRank = 0;
	for (i = 0; i < dimension; ++i)
	{
		if (eigenvalue[i] > threshold)
		{
			diagnostics->effectiveRank++;
			smallestPositive = SHT_LowSpeedMinimum(smallestPositive, eigenvalue[i]);
		}
		if (eigenvalue[i] < eigenvalue[weakest])
			weakest = i;
	}
	if (diagnostics->effectiveRank == dimension && smallestPositive > 0.0)
		diagnostics->scaledJacobianCondition = sqrt(largest / smallestPositive);
	else
		diagnostics->scaledJacobianCondition = DBL_MAX;
	for (i = 0; i < dimension; ++i)
		diagnostics->weakestDirection[i] = vector[i * dimension + weakest];
	{
		double maximumComponent = 0.0;
		for (i = 0; i < dimension; ++i)
			if (fabs(diagnostics->weakestDirection[i]) > maximumComponent)
			{
				maximumComponent = fabs(diagnostics->weakestDirection[i]);
				diagnostics->weakestVariableIndex = i;
			}
	}
}

static void SHT_LowSpeedFinalizeDiagnostics(
	const double *normalized,
	const double *physical,
	const double *residual,
	const double *minimum,
	const double *maximum,
	int dimension,
	SHTLowSpeedSolverDiagnostics *diagnostics)
{
	int i;
	diagnostics->dimension = dimension;
	diagnostics->finalRms = SHT_LowSpeedRms(residual, dimension);
	diagnostics->finalMaximumAbsoluteResidual =
		SHT_LowSpeedMaxAbs(residual, dimension);
	diagnostics->boundaryHitCount = 0;
	for (i = 0; i < dimension; ++i)
	{
		diagnostics->variable[i] = physical[i];
		diagnostics->residual[i] = residual[i];
		diagnostics->boundaryHit[i] = normalized[i] <= 64.0 * DBL_EPSILON ||
			normalized[i] >= 1.0 - 64.0 * DBL_EPSILON;
		diagnostics->boundaryHitCount += diagnostics->boundaryHit[i];
		(void)minimum;
		(void)maximum;
	}
}

int shtLowSpeedNewtonSolver(
	int functionModel(double *, double *, int),
	int dimension,
	double *variable,
	const double *minimum,
	const double *maximum,
	const double *maximumStep,
	const SHTLowSpeedSolverOptions *options,
	SHTLowSpeedSolverDiagnostics *diagnostics)
{
	double normalized[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double trialNormalized[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double bestNormalized[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double physical[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double residual[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double trialResidual[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double bestResidual[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double jacobian[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION *
		SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double matrixWork[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION *
		SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double rightHandSide[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double step[SHT_LOW_SPEED_SOLVER_MAX_DIMENSION] = { 0.0 };
	double rms;
	double trialRms;
	double stepScale;
	double normalizedStepLimit;
	int i;
	int iteration;
	int backtrack;
	int status;
	int finalEvaluationStatus;
	int accepted;
	if (functionModel == NULL || variable == NULL || minimum == NULL ||
		maximum == NULL || maximumStep == NULL || options == NULL ||
		diagnostics == NULL || dimension <= 0 ||
		dimension > SHT_LOW_SPEED_SOLVER_MAX_DIMENSION ||
		options->disturbanceFactor <= 0.0 ||
		options->minimumStepScale <= 0.0)
		return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
	shtLowSpeedSolverResetDiagnostics(diagnostics);
	diagnostics->dimension = dimension;
	for (i = 0; i < dimension; ++i)
	{
		if (!_finite(variable[i]) || !_finite(minimum[i]) ||
			!_finite(maximum[i]) || maximum[i] <= minimum[i])
			return SHT_LOW_SPEED_SOLVER_INVALID_INPUT;
		normalized[i] = SHT_LowSpeedClamp(
			(variable[i] - minimum[i]) / (maximum[i] - minimum[i]), 0.0, 1.0);
	}
	status = SHT_LowSpeedEvaluate(functionModel, normalized, physical,
		residual, minimum, maximum, dimension, diagnostics);
	if (status != SHT_LOW_SPEED_SOLVER_CONVERGED)
	{
		diagnostics->status = status;
		return status;
	}
	rms = SHT_LowSpeedRms(residual, dimension);
	diagnostics->initialRms = rms;
	diagnostics->bestRms = rms;
	memcpy(bestNormalized, normalized, (size_t)dimension * sizeof(double));
	memcpy(bestResidual, residual, (size_t)dimension * sizeof(double));
	for (iteration = 0; iteration < options->maxIterations; ++iteration)
	{
		if (rms <= options->accuracyRequired)
		{
			status = SHT_LOW_SPEED_SOLVER_CONVERGED;
			break;
		}
		status = SHT_LowSpeedBuildJacobian(functionModel, normalized, residual,
			jacobian, physical, trialNormalized, trialResidual, minimum, maximum,
			dimension, options->disturbanceFactor, diagnostics);
		if (status != SHT_LOW_SPEED_SOLVER_CONVERGED)
			break;
		memcpy(matrixWork, jacobian,
			(size_t)dimension * (size_t)dimension * sizeof(double));
		for (i = 0; i < dimension; ++i)
		{
			rightHandSide[i] = -residual[i];
			step[i] = 0.0;
		}
		if (!SHT_LowSpeedSolveLinear(matrixWork, rightHandSide, step,
			dimension, options->pivotRelativeTolerance))
		{
			status = SHT_LOW_SPEED_SOLVER_SINGULAR_JACOBIAN;
			break;
		}
		stepScale = 1.0;
		for (i = 0; i < dimension; ++i)
		{
			normalizedStepLimit = maximumStep[i] /
				(maximum[i] - minimum[i]);
			if (fabs(step[i]) > normalizedStepLimit && normalizedStepLimit > 0.0)
				stepScale = SHT_LowSpeedMinimum(stepScale,
					normalizedStepLimit / fabs(step[i]));
		}
		accepted = 0;
		for (backtrack = 0; backtrack <= options->maxBacktracks; ++backtrack)
		{
			for (i = 0; i < dimension; ++i)
				trialNormalized[i] = SHT_LowSpeedClamp(
					normalized[i] + stepScale * step[i], 0.0, 1.0);
			status = SHT_LowSpeedEvaluate(functionModel, trialNormalized,
				physical, trialResidual, minimum, maximum, dimension, diagnostics);
			if (status == SHT_LOW_SPEED_SOLVER_CONVERGED)
			{
				trialRms = SHT_LowSpeedRms(trialResidual, dimension);
				if (trialRms < rms)
				{
					accepted = 1;
					break;
				}
			}
			diagnostics->rejectedStepCount++;
			stepScale *= 0.5;
			if (stepScale < options->minimumStepScale)
				break;
		}
		if (!accepted)
		{
			status = SHT_LOW_SPEED_SOLVER_STALLED;
			break;
		}
		memcpy(normalized, trialNormalized, (size_t)dimension * sizeof(double));
		memcpy(residual, trialResidual, (size_t)dimension * sizeof(double));
		rms = trialRms;
		diagnostics->acceptedStepCount++;
		diagnostics->lastAcceptedStepScale = stepScale;
		diagnostics->iterationCount = iteration + 1;
		if (rms < diagnostics->bestRms)
		{
			diagnostics->bestRms = rms;
			memcpy(bestNormalized, normalized,
				(size_t)dimension * sizeof(double));
			memcpy(bestResidual, residual,
				(size_t)dimension * sizeof(double));
		}
	}
	if (iteration >= options->maxIterations)
		status = SHT_LOW_SPEED_SOLVER_MAX_ITERATIONS;
	memcpy(normalized, bestNormalized, (size_t)dimension * sizeof(double));
	memcpy(residual, bestResidual, (size_t)dimension * sizeof(double));
	SHT_LowSpeedToPhysical(normalized, physical, minimum, maximum, dimension);
	memcpy(variable, physical, (size_t)dimension * sizeof(double));
	/* 最终点重新形成Jacobian，保证线性诊断对应返回解。 */
	if (SHT_LowSpeedBuildJacobian(functionModel, normalized, residual,
		jacobian, physical, trialNormalized, trialResidual, minimum, maximum,
		dimension, options->disturbanceFactor, diagnostics) ==
		SHT_LOW_SPEED_SOLVER_CONVERGED)
		SHT_LowSpeedAnalyzeJacobian(jacobian, dimension,
			options->rankRelativeTolerance, diagnostics);
	/*
	 * Jacobian有限差分会把带内部状态的模型停留在最后一个扰动点。
	 * 无论诊断Jacobian是否完整形成，返回前都必须重新求值最终接受根，
	 * 使部件输出、轴转矩和Visser诊断与variable严格属于同一物理解。
	 */
	finalEvaluationStatus = SHT_LowSpeedEvaluate(functionModel, normalized,
		physical, residual, minimum, maximum, dimension, diagnostics);
	if (finalEvaluationStatus != SHT_LOW_SPEED_SOLVER_CONVERGED)
		status = finalEvaluationStatus;
	memcpy(variable, physical, (size_t)dimension * sizeof(double));
	diagnostics->status = status;
	diagnostics->converged = status == SHT_LOW_SPEED_SOLVER_CONVERGED;
	SHT_LowSpeedFinalizeDiagnostics(normalized, physical, residual,
		minimum, maximum, dimension, diagnostics);
	return status;
}
