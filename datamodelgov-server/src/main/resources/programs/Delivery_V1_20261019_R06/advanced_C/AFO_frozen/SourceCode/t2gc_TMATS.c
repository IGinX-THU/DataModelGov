/*
* =============================================================
* t2gc.c -
*
*      Computes gamma for specified temperature (t)
			   & fuel-air ratio (fa)
*
*        Liu Kai
* =============================================================
*/

#include <math.h>
extern double t2hc(double a, double b);

double t2gc(double T, double fa)
{
	double R, dT, H1, H2, H3, CP, gamma;

	R = (287.05 - 0.00990*fa + 1e-7*fa*fa);
	dT = 0.1;
	H1 = t2hc(T - dT, fa);
	H2 = t2hc(T, fa);
	H3 = t2hc(T + dT, fa);

	CP = ((H2 - H1) / (1 * dT) + (H3 - H2) / (1 * dT)) / 2;
	gamma = CP / (CP - R);

	return gamma;
	/*
	double A[10] = { -0.30183674e6, 0.10489652e7, -0.23284057e6, 0.45288431e6, -0.31308477e6, 0.11341362e6, -0.21298087e5, 0.16363600e4, 0, 0.80558643e4 };
	double B[10] = { -0.11152575e6, -0.31020206e6, 0.29961197e7, -0.27934788e7, 0.18746407e7, -0.73499597e6, 0.15062602e6, -0.12510984e5, 0, -0.17800633e4 };
	double C[10] = { -0.25179888e6, 0.33930851e5, 0.43630281e4, 0.10594936e5, -0.54952291e4, 0.14949330e4, 0.22772255e3, 0.17874978e2, -0.53236046e0, 0.23113968e3 };
	
	double R, TZ, CP, gamma, CPa, CPf;

	R = (287.05 - 0.00990*fa + 1e-7*fa*fa);
//	R = (287.05287 + 296.376*fa) / (1 + fa);

	CPa = 0;
	CPf = 0;
	TZ = T / 1000;
	for (int i = 1; i < 9; i++)
	{
		CPa = CPa + 1e-3*A[i]*i * pow(TZ, i-1);
		CPf = CPf + 1e-3*B[i]*i * pow(TZ, i-1);
	}
	CP = CPa + (CPf * fa) / (1 + fa);

	gamma = CP / (CP - R);
	return gamma;*/
}