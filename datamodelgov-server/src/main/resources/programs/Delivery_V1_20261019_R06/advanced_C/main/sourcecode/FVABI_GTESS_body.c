#include "types_TMATS.h"
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include <math.h>

#ifdef MATLAB_MEX_FILE
#include "simstruc.h"
#endif

void FVABI_GTESS_body(double *y, const double *u)
{
	double WIn = u[0];    
	double TtIn = u[2];
	double PtIn = u[3];     
	double FARcIn = u[4];
	double Amax = u[5];
	double Amin = u[6];
	double beta = u[7];
	double sigRecov = 1;

	double htIn = t2hc(TtIn, FARcIn);
	double Rt = Rcalc(FARcIn);

	double Psth, Tsth, MNth, Vth, rhosth, Ath, ksi, dP_Loss, Eth, Eth_old, MNg, gammatg, gammasth, Tsthg, Psthg, Psthg_new, Psthg_old, Sth, hsth, dP_Lossg, Eththr, PtOutg, sigRecovcalc;
	double WInMN1, PsMN1, rhosMN1, VMN1, EMN1, sigRecovMN1;
	double WOut, htOut, TtOut, PtOut, FARcOut, MNOut, PsOut, rhosOut, VOut, sigmaP, EOut, NErrorOut, Wcalc;
	int maxiter, iter;
	Wcalc = 0;

	if (beta > 1)
		beta = 1;
	else if (beta < 0)
		beta = 0;
	Ath = (Amax - Amin)*beta + Amin;
	ksi = (1 - Ath / Amax)*(1 - Ath / Amax);
	EMN1 = 0;
	Eth = 0;
	sigRecovMN1 = 0;

//	if (beta > 0.95)
//	{
		calcPs_GTESS(WIn, PtIn, TtIn, FARcIn, Ath, &Psth, &MNth, &rhosth, &Vth, &Eth);
		PcalcStat(PtIn, Psth, TtIn, htIn, FARcIn, Rt, &Sth, &Tsth, &hsth, &rhosth, &Vth);
		dP_Loss = ksi * 0.5 * rhosth * Vth * Vth;
		PtOut = PtIn - dP_Loss;
		sigRecovcalc = PtOut/PtIn ;
		NErrorOut = (sigRecovcalc - sigRecov)*divby(sigRecovcalc);
		WOut = WIn;
		TtOut = TtIn;
		htOut = htIn;
		FARcOut = FARcIn;
		gammasth = t2gc(Tsth, FARcIn);
		MNth = Vth * divby(sqrtT(gammasth*Rt*Tsth));
//	}
/*	else
	{
		PtOut = PtIn * sigRecov;
		calcWvsMN1_GTESS(PtIn, TtIn, FARcIn, Ath, &WInMN1, &PsMN1, &rhosMN1, &VMN1, &EMN1);
		dP_Loss = ksi * 0.5 * rhosMN1 * VMN1 * VMN1;
		sigRecovMN1 = (PtIn - dP_Loss) / PtIn;
		if (sigRecov <= sigRecovMN1)
		{
			WOut = WInMN1;
			TtOut = TtIn;
			htOut = htIn;
			FARcOut = FARcIn;
			if (fabs(WInMN1) > 1e-5)
				NErrorOut = (WIn - WInMN1)*divby(fabs(WInMN1));
			else
				NErrorOut = (WIn - WInMN1) / 1e-5;
			MNth = 1;
		}
		else
		{		
			MNg = 0.5;
			gammatg = 1.4;
			Tsthg = TtIn * divby(1 + MNg * MNg*(gammatg - 1) / 2);
			Psthg = PtIn * powT((Tsthg*divby(TtIn)), (gammatg*divby(gammatg - 1)));
			PcalcStat(PtIn, Psthg, TtIn, htIn, FARcIn, Rt, &Sth, &Tsth, &hsth, &rhosth, &Vth);
			dP_Lossg = ksi * 0.5 * rhosth * Vth * Vth;		
			PtOutg = PtIn - dP_Lossg;
			Eth = (PtOut - PtOutg)*divby(PtOut);

			// iterate to find static pressure, calculated area should be close to actual area 
			maxiter = 200;
			iter = 0;
			Psthg_new = Psthg - 1;  //20221209+ 0.05的单位改为N/m2 Or Pa
			Eththr = 1e-10;   //20230114+ liukai
			while ((fabs(Eth) > Eththr && iter < maxiter)|| iter<2) {
				Eth_old = Eth;
				Psthg_old = Psthg;
				if (fabs(Psthg - Psthg_new) < 1e-5) {
					Psthg = Psthg_new - 1e-5;				// 20230820+ liukai
				}
				else {
					Psthg = Psthg_new;
				}
				// calculate flow velocity and rhos 
				PcalcStat(PtIn, Psthg, TtIn, htIn, FARcIn, Rt, &Sth, &Tsth, &hsth, &rhosth, &Vth);
				dP_Lossg = ksi * 0.5 * rhosth * Vth * Vth;
				PtOutg = PtIn - dP_Lossg;
				Eth = (PtOut - PtOutg)*divby(PtOut);

				if (fabs(Eth) > Eththr) {
					// determine next guess pressure by secant algorithm 
					Psthg_new = Psthg - Eth * (Psthg - Psthg_old)*divby(Eth - Eth_old);
					if (Psthg_new > PtIn)
					{
						Psthg_new = PtIn;
					}
					if (Psthg_new > 1.1*Psthg) {
						Psthg_new = 1.1 * Psthg;
					}
					else if (Psthg_new < 0.9 * Psthg) {
						Psthg_new = 0.9 * Psthg;
					}
				}
				iter = iter + 1;
				if (fabs(Eth - Eth_old) < 1e-10)		// 20230820+ liukai 
					break;
			}

			Psth = Psthg;
			WOut = Ath * Vth * rhosth;
			Wcalc = WOut;
			TtOut = TtIn;
			htOut = htIn;
			FARcOut = FARcIn;
			if (fabs(WOut) > 1)
				NErrorOut = (WIn - WOut)*divby(fabs(WOut));
			else
				NErrorOut = (WIn - WOut) / 1;
			gammasth = t2gc(Tsth, FARcIn);
			MNth = Vth * divby(sqrtT(gammasth*Rt*Tsth));
			WOut = WIn;
		}
	}*/

	calcPs_GTESS(WOut, PtOut, TtOut, FARcOut, Amax, &PsOut, &MNOut, &rhosOut, &VOut, &EOut);

	/*------Assign output values------------*/
	y[0] = WOut;
	y[1] = htOut;
	y[2] = TtOut;
	y[3] = PtOut;
	y[4] = FARcOut;
	y[5] = NErrorOut;
	y[6] = MNth;
	y[7] = MNOut;
	y[8] = EMN1;
	y[9] = Eth;
	y[10] = EOut;
	y[11] = sigRecov;
	y[12] = sigRecovMN1;
	y[13] = Wcalc;
}
