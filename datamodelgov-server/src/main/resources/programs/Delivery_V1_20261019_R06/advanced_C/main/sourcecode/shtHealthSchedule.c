#include <math.h>
#include <string.h>
#include "shtHealthSchedule.h"

/*
 * 相邻节点之间采用分段线性插值。节点本身可以按非均匀位置和非单调
 * 增量描述复杂趋势，但插值算法不额外引入高阶曲率。运行时先用二分
 * 查找确定区间，再计算一次线性比例；覆盖域外固定到最近端点。
 */
static double shtScheduleEvaluateLinear(
	const SHTHealthScheduleTable *table,
	double coordinate)
{
	int low;
	int high;
	int middle;
	double fraction;

	/* 正常工作域以外固定到最近端点，不进行高阶外推。 */
	if(coordinate <= table->xNode[0])
		return table->deltaNode[0];
	if(coordinate >= table->xNode[table->nodeCount - 1])
		return table->deltaNode[table->nodeCount - 1];

	low = 0;
	high = table->nodeCount - 1;
	while(high - low > 1)
	{
		middle = (low + high) / 2;
		if(coordinate < table->xNode[middle])
			high = middle;
		else
			low = middle;
	}

	fraction = (coordinate - table->xNode[low]) /
		(table->xNode[low + 1] - table->xNode[low]);
	return table->deltaNode[low] + fraction *
		(table->deltaNode[low + 1] - table->deltaNode[low]);
}

void shtHealthScheduleReset(SHTHealthScheduleSystem *system)
{
	if(system != NULL)
		memset(system, 0, sizeof(*system));
}

int shtHealthScheduleSetEnabled(SHTHealthScheduleSystem *system, int enabled)
{
	if(system == NULL || (enabled != 0 && enabled != 1))
		return -1;
	if(enabled != 0 && system->configuredCount <= 0)
		return -2;
	system->enabled = enabled;
	return 0;
}

int shtHealthScheduleConfigureTable(
	SHTHealthScheduleSystem *system,
	int healthIndex,
	int axisType,
	int nodeCount,
	const double *xNode,
	const double *deltaNode)
{
	SHTHealthScheduleTable *table;
	int i;

	if(system == NULL || xNode == NULL || deltaNode == NULL)
		return -1;
	if(system->enabled != 0)
		return -4;
	if(healthIndex < 0 || healthIndex >= SHT_HEALTH_SCHEDULE_HEALTH_COUNT ||
		axisType < SHT_HEALTH_AXIS_INLET_CORRECTED_FLOW ||
		axisType > SHT_HEALTH_AXIS_PT_TOTAL_PRESSURE_RATIO ||
		nodeCount < 1 || nodeCount > SHT_HEALTH_SCHEDULE_MAX_NODES)
		return -2;
	if(system->table[healthIndex].configured == 0 &&
		system->configuredCount >= SHT_HEALTH_SCHEDULE_MAX_TABLES)
		return -3;
	for(i = 0; i < nodeCount; ++i)
	{
		if(!_finite(xNode[i]) || !_finite(deltaNode[i]) ||
			(i > 0 && xNode[i] <= xNode[i - 1]))
			return -5;
	}

	table = &system->table[healthIndex];
	if(table->configured == 0)
		++system->configuredCount;
	memset(table, 0, sizeof(*table));
	table->configured = 1;
	table->healthIndex = healthIndex;
	table->axisType = axisType;
	table->nodeCount = nodeCount;
	for(i = 0; i < nodeCount; ++i)
	{
		table->xNode[i] = xNode[i];
		table->deltaNode[i] = deltaNode[i];
	}
	return 0;
}

int shtHealthScheduleIsConfigured(
	const SHTHealthScheduleSystem *system,
	int healthIndex)
{
	if(system == NULL || healthIndex < 0 ||
		healthIndex >= SHT_HEALTH_SCHEDULE_HEALTH_COUNT)
		return 0;
	return system->table[healthIndex].configured != 0;
}

int shtHealthScheduleEvaluateIncrement(
	const SHTHealthScheduleSystem *system,
	int healthIndex,
	double coordinate,
	double *incrementValue)
{
	const SHTHealthScheduleTable *table;
	double increment;

	if(system == NULL || incrementValue == NULL || !_finite(coordinate))
		return -1;
	if(!shtHealthScheduleIsConfigured(system, healthIndex))
		return -2;
	table = &system->table[healthIndex];
	increment = shtScheduleEvaluateLinear(table, coordinate);
	if(!_finite(increment))
		return -3;
	*incrementValue = increment;
	return 0;
}
