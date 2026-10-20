#include "types_TMATS.h"
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include <math.h>

#ifdef MATLAB_MEX_FILE
#include "simstruc.h"
#endif

void Nozzle_TMATS_body(double* y, const double* u, const NozzleStruct* prm)
{
    double WIn       = u[0];     /* Input Flow [pps] 	*/         //20221209+ kg/s
    double htIn      = u[1];     /* enthaply [BTU/lbm] 	*/         //20221209+ J/kg
    double TtIn      = u[2];     /* Temperature Input [degR] 	*/ //20221209+ K
    double PtIn      = u[3];     /* Pressure Input [psia] 	*/ //20221209+ N/m2 Or Pa
    double FARcIn    = u[4];     /* Combusted Fuel to Air Ratio [frac] 	*/
    double PambIn    = u[5];     /* Ambient Pressure [psia] 	*/ //20221209+ N/m2 Or Pa
    double AthroatIn = u[6];     /* Throat area [in2] 	*/         //20221209+ m2
    double AexitIn   = u[7];     /* Exit area [in2] 	*/         //20221209+ m2
	double hpA8		 = u[8];
	//jrt,20241106
	double hpA9 = u[12];

	double fDrag	 = u[9];
	double afterFVABI = u[10];
	double betaFVABI = u[11];
	AthroatIn = AthroatIn * (1 + hpA8);
	//jrt,20241106
	AexitIn = AexitIn * (1 + hpA9);


    /*--------Define Constants-------*/
    double choked, Ts, rhos, V, Test, Ptin;
    double CdTh, Cv, Cfg, Therm_growth, PQPa, PQPaMap, AthroatHot;
    double Rt, TsMN1, PsMN1, Woutcalc;
    double WOut, FgOut, NErrorOut, Ath, Vth, Psth, Ax, Vx, Psx, Tsx, gammasx, MNx;
    double gammatg, gammasth,gammasMN1, gammasg, MNg, TsMNg, PsMNg, PsMNg_new, PsMNg_old, VMN1;
    double MNth, Tsth, rhosth, rhosMN1, rhosx;
    double Axcalc, Psxg, Psxg_new, Psxg_old, Exthr;
    double Sin, hsg, hs, htin, rhosg, Rs, Vg;
    double gammas_s, MN_s, V_s, rhos_s, Ts_s;
    double Ex, Ex_old;
    double erMN_old, erMN, erthr;
    int maxiter, iter, maxiterx, iterx, CDNoz;
    int interpErr = 0;
	/*jrt begin++*/
	double Psx1, Psx2, Psx3, WthMN1, MNxg, coe, Ptxg, Ptxg_new, Ptxg_old;
	Ex = 0;
	Ptxg = 0;
	/*jrt end*/

	/* Warn if there is the potential for back flow */
	Ptin = PtIn;
	if (Ptin <= PambIn) {
		//Ptin = PambIn + 0.1;		// 20230820- liukai
		//Ptin = PambIn;				// 20230820+ liukai
		if (*(prm->IWork + Er2) == 0) {
#ifdef MATLAB_MEX_FILE
			printf("Warning in %s, Backflow warning PtIn <= Pamb\n", prm->BlkNm);
#endif
			*(prm->IWork + Er2) = 1;
		}
	}


    /* Determine Nozzle Type                  */
    /*prm->SwitchType:                             */
    /*        1: Convergent Nozzle            */
    /*        2: Convergent-Divergent Nozzle  */
    if (prm->SwitchType < 1.5)
        CDNoz = 0;
    else
        CDNoz = 1;

	/* jrt_begin modify */
	/* if the thoat area is larger then the exit area of a CD nozzle it is a convergent nozzle */
	if (CDNoz == 1 && AthroatIn > AexitIn)
	{
		Ath = AexitIn;
		CDNoz = 0;
	}
	/* jrt_end modify */
	
	/* jrt_begin modify */
	/* Pressure before nozzle/P ambient */
	PQPa = Ptin * divby(PambIn);
	/* cacluate Thermal Constants */
	PQPaMap = PQPa;
	/* look up Flow Coefficient */
	CdTh = interp1Ac(prm->X_N_PEQPaVec, prm->T_N_CdThArray, PQPaMap, prm->B1, &interpErr);
	if (interpErr == 1 && *(prm->IWork + Er9) == 0) {
#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating CdTh. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
		*(prm->IWork + Er9) = 1;
	}
	Therm_growth = interp1Ac(prm->X_N_TtVecTG, prm->T_N_TGArray, TtIn, prm->C, &interpErr);
	if (interpErr == 1 && *(prm->IWork + Er10) == 0) {
#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating Therm_growth. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
		*(prm->IWork + Er10) = 1;
	}
	/* jrt_end modify */

    /* Calc entropy */
    Sin = pt2sc(Ptin, TtIn, FARcIn);

    /*-- Compute Input enthalpy --------*/
    htin = t2hc(TtIn,FARcIn);

    /*  Where gas constant is R = f(FAR), but NOT P & T */
/*/    Rt = interp1Ac(prm->Y_N_FARVec,prm->T_N_RtArray,FARcIn,prm->A,&interpErr);		// liukai -
	if (interpErr == 1 && *(prm->IWork + Er1) == 0) {
#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating Rt1. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
		*(prm->IWork + Er1) = 1;
	}/*/
	Rt = Rcalc(FARcIn);		// liukai +
    Rs = Rt;


    /* Determine ideal velocity defined by perfect expansion to Pambient */
    PcalcStat(Ptin, PambIn, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
//    gammas_s = interp2Ac(prm->Y_N_FARVec,prm->X_N_TtVec,prm->T_N_MAP_gammaArray,FARcIn,Ts,prm->A,prm->B,&interpErr);		// liukai -
	gammas_s = t2gc(Ts, FARcIn);		// liukai +

    //MN_s = V*divby(sqrtT(gammas_s*Rs*Ts*C_GRAVITY*JOULES_CONST));  //20221209-
    MN_s = V*divby(sqrtT(gammas_s*Rs*Ts));  //20221209+
    Ts_s = Ts;
    V_s = V;
    rhos_s = rhos;


    /* Determine if nozzle throat is choked by comparing pressure when MN = 1 to ambient pressure
     * ---- set MN = 1 and calc throat Ps for iteration IC --------*/
    MNg = 1;
/*/    gammatg = interp2Ac(prm->Y_N_FARVec,prm->X_N_TtVec,prm->T_N_MAP_gammaArray,FARcIn,TtIn,prm->A,prm->B,&interpErr);		// liukai -
	if (interpErr == 1 && *(prm->IWork + Er4) == 0) {
#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating gammatg. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
		*(prm->IWork + Er4) = 1;
	}/*/
	gammatg = t2gc(TtIn, FARcIn);		// liukai +
    /* use isentropic equations for a first cut guess */
    TsMNg = TtIn*divby(1+MNg*MNg*(gammatg-1)/2);
    PsMNg = Ptin*powT((TsMNg*divby(TtIn)),(gammatg*divby(gammatg-1)));

    /* Calculate velcocity and MN using guessed static pressure */
    PcalcStat(Ptin, PsMNg, TtIn, htin, FARcIn, Rt, &Sin, &TsMNg, &hsg, &rhosg, &Vg);
//    gammasg = interp2Ac(prm->Y_N_FARVec,prm->X_N_TtVec,prm->T_N_MAP_gammaArray,FARcIn,TsMNg,prm->A,prm->B,&interpErr);		// liukai -
	gammasg = t2gc(TsMNg, FARcIn);		// liukai +

    //MNg = Vg*divby(sqrtT(gammasg*Rs*TsMNg*C_GRAVITY*JOULES_CONST));  //20221209-
    MNg = Vg*divby(sqrtT(gammasg*Rs*TsMNg));  //20221209+

    /* determine error based on calculated MN and 1 */
    erMN =1 - MNg;

    //PsMNg_new = PsMNg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
    PsMNg_new = PsMNg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
    maxiter = 200;
    iter = 0;
//    erthr = 0.001;		// liukai -
	erthr = 1e-8;		// liukai +

    /* if Ps is not close enough to Ps at MN = 1, iterate to find Ps at MN = 1 */
    while (fabs(erMN) > erthr && iter < maxiter) {
        erMN_old = erMN;
        PsMNg_old = PsMNg;
        //if(fabs(PsMNg - PsMNg_new) < 0.003)  //20221209- 0.003的单位为lbf/in2 Or PSI
        if(fabs(PsMNg - PsMNg_new) < 0.003 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.003的单位改为N/m2 Or Pa
            //PsMNg = PsMNg + 0.005;  //20221209- 0.005的单位为lbf/in2 Or PSI
            //PsMNg = PsMNg + 0.005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.005的单位改为N/m2 Or P  //20230114-
            PsMNg = PsMNg + 0.005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.005的单位改为N/m2 Or P  //20230114+
        else
            PsMNg = PsMNg_new;
        PcalcStat(Ptin, PsMNg, TtIn, htin, FARcIn, Rt, &Sin, &TsMNg, &hsg, &rhosg, &Vg);
//        gammasg = interp2Ac(prm->Y_N_FARVec,prm->X_N_TtVec,prm->T_N_MAP_gammaArray,FARcIn,TsMNg,prm->A,prm->B,&interpErr);		// liukai -
		gammasg = t2gc(TsMNg, FARcIn);		// liukai +
        if (interpErr == 1 && *(prm->IWork+Er5)==0){
#ifdef MATLAB_MEX_FILE
            printf("Warning in %s, Error calculating iteration gammasg. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
            *(prm->IWork+Er5) = 1;
        }
        //MNg = Vg*divby(sqrtT(gammasg*Rs*TsMNg*C_GRAVITY*JOULES_CONST));  //20221209-
        MNg = Vg*divby(sqrtT(gammasg*Rs*TsMNg));  //20221209+
        erMN =1 - MNg;
        if (fabs(erMN) > erthr) {
            /* determine next guess pressure by secant algorithm */
            PsMNg_new = PsMNg - erMN *(PsMNg - PsMNg_old)*divby(erMN - erMN_old);
        }
        //20230114+
        if (PsMNg_new > 1.05*PsMNg) {
            PsMNg_new = 1.05 * PsMNg;
        }
        else if (PsMNg_new < 0.9 * PsMNg) {
            PsMNg_new = 0.9 * PsMNg;
        }
        //20230114
        iter = iter + 1;
    }
    if (iter == maxiter && *(prm->IWork+Er6)==0 ){
#ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating Ps at MN = 1.\n", prm->BlkNm);
#endif
        *(prm->IWork+Er6) = 1;
    }
    /*  MN = 1 parameters */
    TsMN1 = TsMNg;
    PsMN1 = PsMNg;
    rhosMN1 = rhosg;
    gammasMN1 = gammasg;
    VMN1 = Vg;
    

	/* jrt_begin modify */
	/* determining if the throttle is choked */
	if (CDNoz == 0) {
		/* Determine if Nozzle is choked  */
		if (PsMN1 < PambIn)
			choked = 0;
		else {
			choked = 1;
		}
	}
	else { //CDNoz=1;
		/* caculate P3_jrt++ */
		Ath = AthroatIn;
		AthroatHot = Ath * Therm_growth;
		WthMN1 = (1 - prm->flowLoss / 100)*AthroatHot*CdTh*rhosMN1*VMN1;  //20221209+ kg/s

		/* Generate exit area */
		if (prm->IDes < 0.5)
			//Ax = WIn * C_PSItoPSF*divby(Therm_growth *(1-prm->flowLoss/100)*CdTh*rhos_s*V_s);  //20221209- in2
			Ax = WthMN1 * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhos_s*V_s);  //20221209+ m2
		else /* Use calculated area value when using Cv method  */
			Ax = AexitIn;

		/* start iteration to find Psx */
		coe = 0.3;
		Psxg = Ptin * (1 - coe);
		do {
			PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
			//Axcalc = WIn*divby(V * rhos/C_SINtoSFT); /* Will not be used for the Cfg method */  //20221209- in2
			Axcalc = WthMN1 * divby(V * rhos); /* Will not be used for the Cfg method */  //20221209+ m2

			Ex = fabs((Ax - Axcalc)*divby(Ax));
			/* iterate to find static pressure, calculated area should be close to actual area */
			maxiterx = 200;
			iterx = 0;
			//Psxg_new = Psxg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
			Psxg_new = Psxg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
			Exthr = 1e-8;
			while (fabs(Ex) > Exthr && iterx < maxiter) {
				Ex_old = Ex;
				Psxg_old = Psxg;
				//if (fabs(Psxg - Psxg_new) < 0.0003)  //20221209- 0.00003的单位为lbf/in2 Or PSI
				if (fabs(Psxg - Psxg_new) < 0.0003 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.00003的单位改为N/m2 Or Pa
					//Psxg = Psxg + 0.0005;  //20221209- 0.00005的单位为lbf/in2 Or PSI
					//Psxg = Psxg + 0.0005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.00005的单位改为N/m2 Or Pa //20230114-
					Psxg = Psxg + 0.0005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.00005的单位改为N/m2 Or Pa //20230114+
				else
					Psxg = Psxg_new;

				/* calculate flow velocity and rhos */
				PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
				/* calculated Area */
				//Axcalc = WIn*divby(V * rhos/C_SINtoSFT);  //20221209- in2
				Axcalc = WthMN1 * divby(V * rhos);  //20221209+ m2
				/*determine error */
				Ex = (Ax - Axcalc)*divby(Ax);
				if (fabs(Ex) > Exthr) {
					/* determine next guess pressure by secant algorithm */
					Psxg_new = Psxg - Ex * (Psxg - Psxg_old)*divby(Ex - Ex_old);
					/* limit algorthim change */
					if (Psxg_new > 1.1*Psxg) {
						Psxg_new = 1.1 * Psxg;
					}
					else if (Psxg_new < 0.9 * Psxg) {
						Psxg_new = 0.9 * Psxg;
					}
				}
				iterx = iterx + 1;
			}
			if (iterx == maxiterx && *(prm->IWork + Er12) == 0) {
#ifdef MATLAB_MEX_FILE
				printf("Warning in %s, Error calculating Ps at exit.\n", prm->BlkNm);
#endif
				*(prm->IWork + Er12) = 1;
			}
			Psx3 = Psxg;
			PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
			gammasx = t2gc(Ts, FARcIn);
			MNxg = V * divby(sqrtT(gammasx*Rs*Ts));  //20221209+
			coe = coe * 0.9;
			Psxg = Ptin * (1 - coe);
		} while (MNxg > 1);
			/* change > to < begin_jrt*/
		if (Psx3 < PambIn) {
			/* if Psxg is less than Pamb, the throttle is not choked */
			choked = 0;
		}
		else {
			choked = 1;
		}
	}
	/* jrt_end*/
		
	/* jrt_begin*/
	/* computing the flow parameters */
	if (CDNoz == 0)	{
		/* throat not choked, set Psth to ideal expansion to Pambient values */
		if (choked == 0) {
			Psth = PambIn;
			Tsth = Ts_s;
			Vth = V_s;
			rhosth = rhos_s;
			MNth = MN_s;
		}
		else {  /* If nozzle is choked, determine throat parameters based on MN = 1 values */
			Psth = PsMN1;
			Tsth = TsMN1;
			MNth = 1;
			gammasth = t2gc(Tsth, FARcIn);		// liukai +
			Vth = MNth * sqrtT(gammasth*Rs*Tsth);  //20221209+ m/s
			rhosth = rhosMN1;
		}

		/* error('Nozzle Error: Negative Mach number!!') */
		if (MNth < 0 && *(prm->IWork + Er8) == 0) {
#ifdef MATLAB_MEX_FILE
			printf("Error in %s: negative throat mach number,  MN = %f.\n", prm->BlkNm, MNth);
#endif
			*(prm->IWork + Er8) = 1;
		}

		/* Determine throat area in^2 */
		if (prm->IDes < 0.5) {
			//Ath = WIn * C_PSItoPSF*divby(Therm_growth *(1-prm->flowLoss/100)*CdTh*rhosth*Vth);  //20221209- in2
			Ath = WIn * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhosth*Vth);  //20221209+ m2
			if (choked == 0 && *(prm->IWork + Er11) == 0) {
#ifdef MATLAB_MEX_FILE
				printf("Warning in %s, Calculating prm->IDes Area with un-choked nozzle.\n", prm->BlkNm);
#endif
				*(prm->IWork + Er11) = 1;
			}
		}
		else
			Ath = AthroatIn;

		/* Calculate Flow out of nozzle */
		/* Calculated flow is always determined based on the throat velocity
		 * defined at MN = 1 when choked or at the throat area when unchoked */
		AthroatHot = Ath * Therm_growth;
		//Woutcalc = (1-prm->flowLoss/100)*AthroatHot*CdTh*rhosth*Vth/C_PSItoPSF;  //20221209- 1bm/s
		Woutcalc = (1 - prm->flowLoss / 100)*AthroatHot*CdTh*rhosth*Vth;  //20221209+ kg/s

		Psx = Psth;
		Tsx = Tsth;
		MNx = MNth;
		Vx = Vth;
		Ax = Ath;
	}
	else if (CDNoz == 1 && choked == 0)	{
		Tsx = Ts_s;
		Vx = V_s;
		Psx = PambIn;
		rhosx = rhos_s;
		gammasx = gammas_s;		// liukai +
		MNx = MN_s;  //20221209+

		Tsth = Ts_s;
		Vth = V_s;
		Psth = PambIn;
		rhosth = rhos_s;
		gammasth = gammas_s;		// liukai +
		MNth = MN_s;

		/* Determine throat area in^2 */
		if (prm->IDes < 0.5) {
			//Ath = WIn * C_PSItoPSF*divby(Therm_growth *(1-prm->flowLoss/100)*CdTh*rhosth*Vth);  //20221209- in2
			Ath = WIn * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhosth*Vth);  //20221209+ m2
			if (choked == 0 && *(prm->IWork + Er11) == 0) {
#ifdef MATLAB_MEX_FILE
				printf("Warning in %s, Calculating prm->IDes Area with un-choked nozzle.\n", prm->BlkNm);
#endif
				*(prm->IWork + Er11) = 1;
			}
		}
		else
			Ath = AthroatIn;

		/* Generate exit area */
		if (prm->IDes < 0.5)
			//Ax = WIn * C_PSItoPSF*divby(Therm_growth *(1-prm->flowLoss/100)*CdTh*rhos_s*V_s);  //20221209- in2
			Ax = WIn * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhos_s*V_s);  //20221209+ m2
		else /* Use calculated area value when using Cv method  */
			Ax = AexitIn;

		Woutcalc = Ax*rhosx*Vx;  //20221209+ kg/s
	}
	else  {		/* if (CDNoz == 1 && choked == 1) */
		/* if the nozzle is choked and convergent-divergent calculate values after the nozzle throat */
		Psth = PsMN1;
		Tsth = TsMN1;
		MNth = 1;
		gammasth = t2gc(Tsth, FARcIn);		// liukai +
		Vth = MNth * sqrtT(gammasth*Rs*Tsth);  //20221209+ m/s
		rhosth = rhosMN1;


		/* Determine throat area in^2 */
		if (prm->IDes < 0.5) {
			Ath = WIn * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhosth*Vth);  //20221209+ m2
			if (choked == 0 && *(prm->IWork + Er11) == 0) {
#ifdef MATLAB_MEX_FILE
				printf("Warning in %s, Calculating prm->IDes Area with un-choked nozzle.\n", prm->BlkNm);
#endif
				*(prm->IWork + Er11) = 1;
			}
		}
		else
			Ath = AthroatIn;

		/* Calculate Flow out of nozzle */
		AthroatHot = Ath * Therm_growth;
		Woutcalc = (1 - prm->flowLoss / 100)*AthroatHot*CdTh*rhosth*Vth;  //20221209+ kg/s


		/* Generate exit area */
		if (prm->IDes < 0.5)
			//Ax = WIn * C_PSItoPSF*divby(Therm_growth *(1-prm->flowLoss/100)*CdTh*rhos_s*V_s);  //20221209- in2
			Ax = WIn * divby(Therm_growth *(1 - prm->flowLoss / 100)*CdTh*rhos_s*V_s);  //20221209+ m2
		else /* Use calculated area value when using Cv method  */
			Ax = AexitIn;

		/* start iteration to find Psx */
		coe = 0.4;
		Psxg = Ptin * coe;
		do {
			PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
			//Axcalc = WIn*divby(V * rhos/C_SINtoSFT); /* Will not be used for the Cfg method */  //20221209- in2
			Axcalc = WIn * divby(V * rhos); /* Will not be used for the Cfg method */  //20221209+ m2

			Ex = fabs((Ax - Axcalc)*divby(Ax));
			/* iterate to find static pressure, calculated area should be close to actual area */
			maxiterx = 200;
			iterx = 0;
			//Psxg_new = Psxg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
			Psxg_new = Psxg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
			Exthr = 1e-8;
			while (fabs(Ex) > Exthr && iterx < maxiter) {
				Ex_old = Ex;
				Psxg_old = Psxg;
				//if (fabs(Psxg - Psxg_new) < 0.0003)  //20221209- 0.00003的单位为lbf/in2 Or PSI
				if (fabs(Psxg - Psxg_new) < 0.0003 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.00003的单位改为N/m2 Or Pa
					//Psxg = Psxg + 0.0005;  //20221209- 0.00005的单位为lbf/in2 Or PSI
					//Psxg = Psxg + 0.0005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.00005的单位改为N/m2 Or Pa //20230114-
					Psxg = Psxg + 0.0005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.00005的单位改为N/m2 Or Pa //20230114+
				else
					Psxg = Psxg_new;

				/* calculate flow velocity and rhos */
				PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
				/* calculated Area */
				//Axcalc = WIn*divby(V * rhos/C_SINtoSFT);  //20221209- in2
				Axcalc = WIn * divby(V * rhos);  //20221209+ m2
				/*determine error */
				Ex = (Ax - Axcalc)*divby(Ax);
				if (fabs(Ex) > Exthr) {
					/* determine next guess pressure by secant algorithm */
					Psxg_new = Psxg - Ex * (Psxg - Psxg_old)*divby(Ex - Ex_old);
					/* limit algorthim change */
					//20230114-
	//                if (Psxg_new > 1.1*Psxg) {
	//                    Psxg_new = 1.1 * Psxg;
	//                }
	//                else if (Psxg_new < 0.9 * Psxg) {
	//                    Psxg_new = 0.9 * Psxg;
	//                }
					//20230114
					//20230114+
					if (Psxg_new > 1.05*Psxg) {
						Psxg_new = 1.05 * Psxg;
					}
					else if (Psxg_new < 0.9 * Psxg) {
						Psxg_new = 0.9 * Psxg;
					}
					//20230114
				}
				iterx = iterx + 1;
			} 
			if (iterx == maxiterx && *(prm->IWork + Er12) == 0) {
#ifdef MATLAB_MEX_FILE
				printf("Warning in %s, Error calculating Ps at exit.\n", prm->BlkNm);
#endif
				*(prm->IWork + Er12) = 1;
			}
			PcalcStat(Ptin, Psxg, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
			gammasx = t2gc(Ts, FARcIn);		// liukai +
			MNxg = V * divby(sqrtT(gammasx*Rs*Ts));  //20221209+
			coe = coe * 0.9;
			Psxg = Ptin * coe;
		} while (MNxg < 1);

		Psx1 = Psxg;
		Psx2 = Psx1 * ( 2*gammasx/(gammasx+1)*MNxg*MNxg - (gammasx-1)/(gammasx+1) );
		/* Collect data from the expansion to exit area: */
		if (PambIn <= Psx1  ) {
			/* if Psx1 is greater than Pamb, under-expanded state, Psx > Pamb */
			Tsx = Ts;
			Vx = V;
			Psx = Psxg;
			rhosx = rhos;
			//            gammasx = interp2Ac(prm->Y_N_FARVec,prm->X_N_TtVec,prm->T_N_MAP_gammaArray,FARcIn,Ts,prm->A,prm->B,&interpErr);		// liukai -
			gammasx = t2gc(Tsx, FARcIn);		// liukai +
			//MNx = Vx*divby(sqrtT(gammasx*Rs*Tsx*C_GRAVITY*JOULES_CONST));  //20221209-
			MNx = Vx * divby(sqrtT(gammasx*Rs*Tsx));  //20221209+
		}
		else if (Psx1 < PambIn && PambIn <= Psx2){
			/* if Psx1 is less than Pamb, and Pamb is less than Psx2, over-expanded state, Psx < Pamb */
			Tsx = Ts;
			Vx = V;
			Psx = Psxg;
			rhosx = rhos;
			gammasx = t2gc(Tsx, FARcIn);		// liukai +
			MNx = Vx * divby(sqrtT(gammasx*Rs*Tsx));  //20221209+
		}
		else {
			/* if Psx2 is less than Pamb, and Pamb is less than Psx3, with shockwave in the nozzle divergent section , Psx == Pamb */
			Psx = PambIn;
			/* start iteration to find Ptx */
			coe = 0.3;
			Ptxg = Psx / (1-coe);
			do {
				PcalcStat(Ptxg, Psx, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
				Axcalc = WIn * divby(V * rhos); /* Will not be used for the Cfg method */  //20221209+ m2

				Ex = fabs((Ax - Axcalc)*divby(Ax));
				/* iterate to find static pressure, calculated area should be close to actual area */
				maxiterx = 200;
				iterx = 0;
				//Psxg_new = Psxg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
				Ptxg_new = Ptxg - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
				Exthr = 1e-8;
				while (fabs(Ex) > Exthr && iterx < maxiter) {
					Ex_old = Ex;
					Ptxg_old = Ptxg;
					if (fabs(Ptxg - Ptxg_new) < 0.0003 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.00003的单位改为N/m2 Or Pa
						Ptxg = Ptxg + 0.0005 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.00005的单位改为N/m2 Or Pa //20230114+
					else
						Ptxg = Ptxg_new;

					/* calculate flow velocity and rhos */
					PcalcStat(Ptxg, Psx, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
					/* calculated Area */
					Axcalc = WIn * divby(V * rhos);  //20221209+ m2
					/*determine error */
					Ex = (Ax - Axcalc)*divby(Ax);
					if (fabs(Ex) > Exthr) {
						/* determine next guess pressure by secant algorithm */
						Ptxg_new = Ptxg - Ex * (Ptxg - Ptxg_old)*divby(Ex - Ex_old);
						/* limit algorthim change */
						if (Ptxg_new > 1.1*Ptxg) {
							Ptxg_new = 1.1 * Ptxg;
						}
						else if (Ptxg_new < 0.9 * Ptxg) {
							Ptxg_new = 0.9 * Ptxg;
						}
						//20230114
					}
					iterx = iterx + 1;
				}
				if (iterx == maxiterx && *(prm->IWork + Er12) == 0) {
#ifdef MATLAB_MEX_FILE
					printf("Warning in %s, Error calculating Pt at exit.\n", prm->BlkNm);
#endif
					*(prm->IWork + Er12) = 1;
				}
				PcalcStat(Ptxg, Psx, TtIn, htin, FARcIn, Rt, &Sin, &Ts, &hs, &rhos, &V);
				gammasx = t2gc(Ts, FARcIn);		// liukai +
				MNxg = V * divby(sqrtT(gammasx*Rs*Ts));  //20221209+
				coe = coe * 0.9;
				Ptxg = Psx / (1 - coe);
			} while (MNxg > 1);
			Tsx = Ts;
			Vx = V;
			rhosx = rhos;
			gammasx = t2gc(Tsx, FARcIn);		// liukai +
			MNx = Vx * divby(sqrtT(gammasx*Rs*Tsx));  //20221209+
		}
	}
	/* jrt_end */


	/* error('Nozzle Error: Negative Mach number!!') */
	if (MNx < 0 && *(prm->IWork + Er14) == 0) {
#ifdef MATLAB_MEX_FILE
		printf("Error in %s: negative exit mach number,  MN = %f.\n", prm->BlkNm, MNx);
#endif
		*(prm->IWork + Er14) = 1;
	}

	WOut = WIn;
	Test = Psx;

	/* look up Thrust and velocity coefficients */
	if (prm->CfgEn < 0.5) {
		Cv = interp1Ac(prm->X_N_PEQPaVec, prm->T_N_CvArray, PQPaMap, prm->B1, &interpErr);
		if (interpErr == 1 && *(prm->IWork + Er15) == 0) {
#ifdef MATLAB_MEX_FILE
			printf("Warning in %s, Error calculating Cv. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
			*(prm->IWork + Er15) = 1;
		}
		Cfg = 1;
	}
	else {
		Cfg = interp1Ac(prm->X_N_PEQPaVec, prm->T_N_CfgArray, PQPaMap, prm->B1, &interpErr);
		if (interpErr == 1 && *(prm->IWork + Er16) == 0) {
#ifdef MATLAB_MEX_FILE
			printf("Warning in %s, Error calculating Cfg. Vector definitions may need to be expanded.\n", prm->BlkNm);
#endif
			*(prm->IWork + Er16) = 1;
		}
		Cv = 1;
	}

	/*----- calc gross thrust -----------*/
	if (CDNoz == 1) {
		if (prm->CfgEn > 0.5)
			//FgOut = (WOut/C_GRAVITY)*V_s*Cfg;  //20221209- 1bf
			FgOut = WOut * V_s*Cfg - fDrag;  //20221209+ N
		else
			//FgOut = (WOut/C_GRAVITY)*Vx*Cv + (Psx-PambIn)*Ax;  //20221209- 1bf
			FgOut = WOut * Vx*Cv + (Psx - PambIn)*Ax - fDrag;  //20221209+ N
	}
	else {
		if (prm->CfgEn > 0.5)
			//FgOut = (WOut/C_GRAVITY)*V_s*Cfg;  //20221209- 1bf
			FgOut = WOut * V_s*Cfg - fDrag;  //20221209+ N
		else
			//FgOut = (WOut/C_GRAVITY)*Vth*Cv + (Psth-PambIn)*Ath;  //20221209- 1bf
			FgOut = WOut * Vth*Cv + (Psth - PambIn)*Ath - fDrag;  //20221209+ N
	}
	/* ----- Compute Normalized Flow Error ----- */
	if (prm->IDes < 0.5 && prm->WDes == 0)
		NErrorOut = 100;
	else if (prm->IDes < 0.5)
		NErrorOut = (WIn - prm->WDes)*divby(prm->WDes);
	/*    else if (WIn == 0) // 20230816- liukai
		{
			NErrorOut = 100; // 20230816- liukai
			NErrorOut = 0;	// 20230816+ liukai
		}*/
	else {	// 20230816+ liukai	
		if (fabs(WIn) > 1)
		{
			NErrorOut = (WIn - Woutcalc)*divby(fabs(WIn));
		}
		else
		{
			NErrorOut = (WIn - Woutcalc)*divby(1);
		}
		if (afterFVABI > 0.5)
		{
			if (betaFVABI < 1e-4)
			{
				NErrorOut = (Ptin - PambIn)*divby(PambIn);
				Woutcalc = 0;
			}
		}
	}
    /*------Assign output values------------*/
    y[0] = WOut;          /* Outlet Total Flow [pps]	*/         //20221209+ kg/s
    y[1] = FgOut;         /* Gross Thrust [lbf] */                 //20221209+ N
    y[2] = NErrorOut;     /* Normalized Flow Error [frac] */
    y[3] = Ath;           /* Throat Area [in^2] */                 //20221209+ m2
    y[4] = Ax;            /* Exit Area [in^2] */
    y[5] = Psth;          /* Throat static pressure [psi] */       //20221209+ N/m2 Or Pa
    y[6] = Tsth;          /* Throat static temperature [R] */      //20221209+ K
    y[7] = MNth;          /* Throat Mach Number */
    y[8] = Vth;           /* Throat velocity */                    //20221209+ m/s
    y[9] = Psx;           /* Exit static pressure [psi]*/          //20221209+ N/m2 Or Pa
    y[10] = Ptxg;          /* Exit static temperature [R]*/         //20221209+ K
    y[11] = MNx;          /* Exit Mach Number */
    y[12] = Vx;           /* Exit velocity */                      //20221209+ m/s
    y[13] = Woutcalc;     /* Calculated mass flow [pps] */         //20221209+ kg/s
    y[14] = choked ;      /* nozzle is choked at the throat */
    y[15] = Ex;          /* ideal velocity expanded to ambient */ //20221209+ m/s
    y[16] = erMN;
}
