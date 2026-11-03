/*		
 * % *************************************************************************
 * % written by Liu Kai
 * %
 * %  (S, Ts, hs, rho, V) = f(Pt, Ps, Tt, ht, FAR, Rt).
 * % *************************************************************************/

#include <math.h>
#include "constants_TMATS.h"
#include "functions_TMATS.h"

/*------ the following code uses secant method to calc static pressure ----*/
void calcPs_GTESS(double W1In, double Pt1In, double Tt1In, double FARc1In, double Aphy1, double *Ps, double *MN, double *rhos, double *V, double *E)
{
	double MN1g, gammat1g, Ts1g, Ps1g, ht1in, Rt1, S1in, Ts1, hs1, rhos1, V1, gammas1;
	double A1calc, E1, E1_old, Ps1g_new, Ps1g_old, E1thr;
	int iter1, maxiter;

	ht1in = t2hc(Tt1In, FARc1In);
	Rt1 = Rcalc(FARc1In);
	/* start iteration to find Ps1in */
	/* guess Ps1 and calculate an initial Area error */
	MN1g = 0.3;
	gammat1g = 1.4;
	Ts1g = Tt1In * divby(1 + MN1g * MN1g*(gammat1g - 1) / 2);
	Ps1g = Pt1In * powT((Ts1g*divby(Tt1In)), (gammat1g*divby(gammat1g - 1)));
	PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
	A1calc = W1In * divby(V1 * rhos1);  //20221209+ m2
	E1 = (Aphy1 - A1calc)*divby(Aphy1);

	/* iterate to find static pressure, calculated area should be close to actual area */
	maxiter = 200;
	iter1 = 0;
	Ps1g_new = Ps1g - 0.1;  //20221209+ 0.05的单位改为N/m2 Or Pa
	E1thr = 1e-10;   //20230114+ liukai
	while (fabs(E1) > E1thr && iter1 < maxiter) {
		E1_old = E1;
		Ps1g_old = Ps1g;
	/*	if (fabs(Ps1g - Ps1g_new) < 1e-5) {  
			Ps1g = Ps1g_new - 1e-5;				// 20230820+ liukai
		}
		else {
			Ps1g = Ps1g_new;
		}*/
		Ps1g = Ps1g_new;
		/* calculate flow velocity and rhos */
		PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);

		if (V1 < 1e-4) {
		//	V1 = 0;	// 20230820+ liukai
			Ps1g = Pt1In;
			PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);

			Ps1g_old = Pt1In * (1 - 1e-10);
			double S1in_old, Ts1_old, hs1_old, rhos1_old, V1_old;
			PcalcStat(Pt1In, Ps1g_old, Tt1In, ht1in, FARc1In, Rt1, &S1in_old, &Ts1_old, &hs1_old, &rhos1_old, &V1_old);
			E1_old = (Aphy1 - W1In * divby(V1_old * rhos1_old))*divby(Aphy1);
		}

		/* calculated Area */
		if (W1In > 0)		// 20230820+ liukai
		{
			if (V1 < 1e-4)
				A1calc = W1In / (1e-4*rhos1);
			else
				A1calc = W1In * divby(V1 * rhos1);  //20221209+ m2
		}
		else
		{
			Ps1g = Pt1In;
			PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
			A1calc = Aphy1;
			E1 = 0;
			break;
		}
		/*determine error */
		E1 = (Aphy1 - A1calc)*divby(Aphy1);
		if (fabs(E1) > E1thr) {
			/* determine next guess pressure by secant algorithm */
			Ps1g_new = Ps1g - E1 * (Ps1g - Ps1g_old)*divby(E1 - E1_old);
			if (Ps1g_new > Pt1In)
			{
				Ps1g_new = Pt1In;
			}
			if (Ps1g_new > 1.05*Ps1g) {
				Ps1g_new = 1.05 * Ps1g;
			}
			else if (Ps1g_new < 0.95 * Ps1g) {
				Ps1g_new = 0.95 * Ps1g;
			}
			//20221215
		}
		iter1 = iter1 + 1;
		if (fabs(E1 - E1_old) < 1e-10)		// 20230820+ liukai 
			break;
	}
	*Ps = Ps1g;
	gammas1 = t2gc(Ts1, FARc1In);
	*MN = V1 * divby(sqrtT(gammas1*Rt1*Ts1));
	*rhos = rhos1;
	*V = V1;
	*E = E1;
    return;
}

/*------ the following code uses secant method to calc static pressure ----*/
void calcWvsMN1_GTESS(double Pt1In, double Tt1In, double FARc1In, double Aphy1, double *WInMN1, double *PsMN1, double *rhosMN1, double *VMN1, double *EMN1)
{
	double MN1, MN1g, gammat1g, Ts1g, Ps1g, ht1in, Rt1, S1in, Ts1, hs1, rhos1, V1, gammas1;
	double A1calc, E1, E1_old, Ps1g_new, Ps1g_old, E1thr;
	int iter1, maxiter;

	ht1in = t2hc(Tt1In, FARc1In);
	Rt1 = Rcalc(FARc1In);
	MN1 = 1;
	/* start iteration to find Ps1in */
	/* guess Ps1 and calculate an initial Area error */
	gammat1g = 1.4;
	Ts1g = Tt1In * divby(1 + MN1 * MN1*(gammat1g - 1) / 2);
	Ps1g = Pt1In * powT((Ts1g*divby(Tt1In)), (gammat1g*divby(gammat1g - 1)));
	PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
	gammas1 = t2gc(Ts1, FARc1In);
	MN1g = V1 * divby(sqrtT(gammas1*Rt1*Ts1));

	E1 = MN1g - MN1;

	/* iterate to find static pressure, calculated area should be close to actual area */
	maxiter = 200;
	iter1 = 0;
	Ps1g_new = Ps1g - 0.1;  //20221209+ 0.05的单位改为N/m2 Or Pa
	E1thr = 1e-10;   //20230114+ liukai
	while (fabs(E1) > E1thr && iter1 < maxiter) {
		E1_old = E1;
		Ps1g_old = Ps1g;
		if (fabs(Ps1g - Ps1g_new) < 1e-5) {
			Ps1g = Ps1g_new - 1e-5;				// 20230820+ liukai
		}
		else {
			Ps1g = Ps1g_new;
		}
		/* calculate flow velocity and rhos */
		PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
		gammas1 = t2gc(Ts1, FARc1In);
		MN1g = V1 * divby(sqrtT(gammas1*Rt1*Ts1));
		E1 = MN1g - MN1;

		if (fabs(E1) > E1thr) {
			/* determine next guess pressure by secant algorithm */
			Ps1g_new = Ps1g - E1 * (Ps1g - Ps1g_old)*divby(E1 - E1_old);
			if (Ps1g_new > Pt1In)
			{
				Ps1g_new = Pt1In;
			}
			if (Ps1g_new > 1.1*Ps1g) {
				Ps1g_new = 1.1 * Ps1g;
			}
			else if (Ps1g_new < 0.9 * Ps1g) {
				Ps1g_new = 0.9 * Ps1g;
			}
			//20221215
		}
		iter1 = iter1 + 1;
		if (fabs(E1 - E1_old) < 1e-10)		// 20230820+ liukai 
			break;
	}
	*WInMN1 = Aphy1 * V1 * rhos1;
	*PsMN1 = Ps1g;
	*rhosMN1 = rhos1;
	*VMN1 = V1;
	*EMN1 = E1;
	return;
}
