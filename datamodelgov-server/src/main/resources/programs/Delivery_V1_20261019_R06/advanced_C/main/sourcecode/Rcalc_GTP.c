
#include <math.h>


double Rcalc(double fa)
{
	double R;
	R = 287.05 - 0.00990*fa + 1e-7*fa*fa;
//	R = (287.05287 + 296.376*fa) / (1 + fa);
	return R;
}