#include "types_TMATS.h"
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include <math.h>

#ifdef MATLAB_MEX_FILE
#include "simstruc.h"
#endif

void Mixer_TMATS_body(double* y, const double* u, const MixerStruct* prm)
{
    double W1In     = u[0];     /* Input 1 Flow [pps]                     */     //20221209+ kg/s
    double ht1In    = u[1];     /* Input 1 enthalpy [BTU/lbm]             */     //20221209+ J/kg
    double Tt1In	= u[2];     /* Temperature Input 1 [degR]             */ //20221209+ K
    double Pt1In	= u[3];     /* Pressure Input 1 [psia]                */ //20221209+ N/m2 Or Pa
    double FARc1In  = u[4];     /* Combusted Fuel to Air Ratio 1 [frac]   */
    double W2In     = u[5];     /* Input 2 Flow [pps]                     */     //20221209+ kg/s
    double ht2In	= u[6];     /* Input 2 enthalpy [BTU/lbm]             */ //20221209+ J/kg
    double Tt2In	= u[7];     /* Temperature Input 1 [degR]             */ //20221209+ K
    double Pt2In	= u[8];     /* Pressure Input 1 [psia]                */ //20221209+ N/m2 Or Pa
    double FARc2In  = u[9];     /* Combusted Fuel to Air Ratio 1 [frac]   */
	double PsMixer = u[10];
	double isDyn = u[11];
	double betaRVABI = u[12];
	double hpMixerPs = u[13];
	double hpA1 = u[14];
	double hpA2 = u[15];
    
    /*--------Define Constants-------*/
    double WOut, FARcOut, TtOut, Aphyout, PtOut;
    double E1, E2, Eout1, Eout2, A1calc, A2calc, Aoutcalc, Ps1g, Ps2g, Psoutg;
    double Rt1, ht1in, Ps1, S1in, Ts1, hs1, rhos1, V1, Ps1g_new, Ps1g_old, E1_old, MN1g, gammat1g, Ts1g;
    double Rt2, ht2in, Ps2, S2in, Ts2, hs2, rhos2, V2, Ps2g_new, Ps2g_old, E2_old, MN2g, gammat2g, Ts2g;
    double erthr, gammatg, gammasg, TsMNg, PsMNg,PsMNg_new, PsMNg_old, erMN, erMN_old;
    double Rtout, htOut, Psout, Sout, Tsout, hsout, rhosout, Vout, Psoutg_new, Psoutg_old, Eout1_old, Eout2_old, MNoutg, gammatoutg, Tsoutg;
    double E1thr, E2thr, Eout1thr, Eout2thr, Ptoutg, Ptoutg_old, Ptoutg_new, Impulseoutputg, ImpulseMixed, NErrW1, NErrW2, gammas1, gammas2, MN1, MN2, W1calc, W2calc;
    double Aphy1, Aphy2;
    double Psp, Pss, Ttp, Tts, Ptp, Pts, Tsp, Tss, rhosp, rhoss, Vp, Vs, Ap, As, hsp, hss, htp, hts;
    double Ws, Wp, MNg, Sin;
    double FARp, FARs, Rtp, Rts, Rsp;
    double rhosg, Vg, hsg;
    int iter, iter1, iter2, iter3a, iter3b, maxiter;
    int interpErr = 0;

	E1 = 1.0;		// 20230914+, liukai
	E2 = 1.0;
    
    /* calculate output flow */
    WOut = W1In + W2In;
    /* calculate output fuel to air ratio */
 //   FARcOut = (FARc1In * W1In + FARc2In *W2In)*divby(WOut);		// liukai -
	if (W1In > 0 || W2In > 0)	// 20230816+ liukai
	{
		FARcOut = (W1In * FARc1In / (1 + FARc1In) + W2In * FARc2In / (1 + FARc2In)) * divby(W1In / (1 + FARc1In) + W2In / (1 + FARc2In));		// liukai +
	}
	else
	{
		FARcOut = 0;
	}
    
    /* determine gas characteristics */
    /*  Where gas constant is R = f(FAR), but NOT P & T */
 //   Rt1 = interp1Ac(prm->Y_M_FARVec,prm->T_M_RtArray,FARc1In,prm->A,&interpErr);		// liukai -
	Rt1 = Rcalc(FARc1In);		// liukai +
    if (interpErr == 1 && *(prm->IWork+Er1)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating Rt1. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er1) = 1;
    }
 //   Rt2 = interp1Ac(prm->Y_M_FARVec,prm->T_M_RtArray,FARc2In,prm->A,&interpErr);		// liukai -
	Rt2 = Rcalc(FARc2In);		// liukai +
    if (interpErr == 1 && *(prm->IWork+Er2)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating Rt2. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er2) = 1;
    }
 //   Rtout = interp1Ac(prm->Y_M_FARVec,prm->T_M_RtArray,FARcOut,prm->A,&interpErr);		// liukai -
	Rtout = Rcalc(FARcOut);		// liukai +
    if (interpErr == 1 && *(prm->IWork+Er3)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating Rtout. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er3) = 1;
    }
    
    /* determine calculated enthalpy for input flows */
    ht1in = t2hc(Tt1In,FARc1In);
    ht2in = t2hc(Tt2In,FARc2In);
    /* calculate total enthalpy */
	if (WOut > 0)		// 20230816+ liukai
	{
		htOut = (W1In*ht1in + W2In * ht2in)*divby(WOut);
	}
	else
	{
		htOut = ht1in;
	}

    /* calculate total output temperature */
    TtOut = h2tc(htOut, FARcOut);
    
    //maxiter = 20;    //20230114-
    maxiter = 200;    //20230114+
    if (prm->IDes < 0.5){
        
        /* set primary and secondary definition via switch primary-secondary */
        if (prm->SWPS < 0.5){
            /* primary inflow */
            Wp  = W1In;
            htp = ht1in;
            Ttp = Tt1In;
            Ptp = Pt1In;
            FARp = FARc1In;
            Rtp = Rt1;
            Rsp = Rtp;
            /* secondary inflow */
            Ws  = W2In;
            hts = ht2in;
            Tts = Tt2In;
            Pts = Pt2In;
            FARs = FARc2In;
            Rts = Rt2;}
        else {
            /* primary inflow */
            Wp  = W2In;
            htp = ht2in;
            Ttp = Tt2In;
            Ptp = Pt2In;
            FARp = FARc2In;
            Rtp = Rt2;
            Rsp = Rtp;
            /* secondary inflow*/
            Ws  = W1In;
            hts = ht1in;
            Tts = Tt1In;
            Pts = Pt1In;
            FARs = FARc1In;
            Rts = Rt1;}
        
        /* Determine primary flow Area and Ps */
        MNg = prm->MNp;
        gammatg = interp2Ac(prm->Y_M_FARVec,prm->X_M_TVec,prm->T_M_gammaArray,FARp,Ttp,prm->A,prm->B,&interpErr);
        if (interpErr == 1 && *(prm->IWork+Er4)==0){
            #ifdef MATLAB_MEX_FILE
            printf("Warning in %s, Error calculating gammatg. Vector definitions may need to be expanded.\n", prm->BlkNm);
            #endif
            *(prm->IWork+Er4) = 1;
        }
        TsMNg = Ttp*divby(1+MNg*MNg*(gammatg-1)/2);
        PsMNg = Ptp*powT((TsMNg*divby(Ttp)),(gammatg*divby(gammatg-1)));

        PcalcStat(Ptp, PsMNg, Ttp, htp, FARp, Rtp, &Sin, &TsMNg, &hsg, &rhosg, &Vg);
        gammasg = interp2Ac(prm->Y_M_FARVec,prm->X_M_TVec,prm->T_M_gammaArray,FARp,TsMNg,prm->A,prm->B,&interpErr);
        if (interpErr == 1 && *(prm->IWork+Er4)==0){
            #ifdef MATLAB_MEX_FILE
            printf("Warning in %s, Error calculating gammasg. Vector definitions may need to be expanded.\n", prm->BlkNm);
            #endif
            *(prm->IWork+Er4) = 1;
        }
        //MNg = Vg*divby(sqrtT(gammasg*Rsp*TsMNg*C_GRAVITY*JOULES_CONST));  //20221209-
        MNg = Vg*divby(sqrtT(gammasg*Rsp*TsMNg));  //20221209+
        
        erMN =prm->MNp - MNg;
        //PsMNg_new = PsMNg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
        PsMNg_new = PsMNg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
        iter = 0;
//        erthr = 0.0001;		// liuakai -
		erthr = 1e-10;		// liukai +
        /* if Ps is not close enough to Ps at MN = prm->MNp, iterate to find Ps at MN = prm->MNp */
        while (fabs(erMN) > erthr && iter < maxiter) {
            erMN_old = erMN;
            PsMNg_old = PsMNg;
            //if(fabs(PsMNg - PsMNg_new) < 0.03)  //20221209- 0.03的单位为lbf/in2 Or PSI
            if(fabs(PsMNg - PsMNg_new) < 0.03 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.03的单位改为N/m2 Or Pa
                //PsMNg = PsMNg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
                //PsMNg = PsMNg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa  //20230114-
                PsMNg = PsMNg - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa  //20230114+
            else
                PsMNg = PsMNg_new;
            PcalcStat(Ptp, PsMNg, Ttp, htp, FARp, Rtp, &Sin, &TsMNg, &hsg, &rhosg, &Vg);
            gammasg = interp2Ac(prm->Y_M_FARVec,prm->X_M_TVec,prm->T_M_gammaArray,FARp,TsMNg,prm->A,prm->B,&interpErr);
            if (interpErr == 1 && *(prm->IWork+Er5)==0){
                #ifdef MATLAB_MEX_FILE
                printf("Warning in %s, Error calculating iteration gammasg. Vector definitions may need to be expanded.\n", prm->BlkNm);
                #endif
                *(prm->IWork+Er5) = 1;
            }
            if (Vg <= 0) {
                //Vg = 0.00001;  //20221209- 0.00001的单位为ft/s
                Vg = 0.00001 / 3.28084;  //20221209+ 0.00001的单位改为m/s
                if(iter >= maxiter && *(prm->IWork+Er6)==0 ){
                    #ifdef MATLAB_MEX_FILE
                    printf("Warning in %s, Primary flow velocity is zero\n", prm->BlkNm);
                    #endif
                    *(prm->IWork+Er6) = 1;
                }
            }
            //MNg = Vg*divby(sqrtT(gammasg*Rsp*TsMNg*C_GRAVITY*JOULES_CONST));  //20221209-
            MNg = Vg*divby(sqrtT(gammasg*Rsp*TsMNg));  //20221209+
            erMN = prm->MNp - MNg;
            if (fabs(erMN) > erthr) {
                /* determine next guess pressure by secant algorithm */
                PsMNg_new = PsMNg - erMN *(PsMNg - PsMNg_old)*divby(erMN - erMN_old);
            }
            iter = iter + 1;
        }
        if (iter >= maxiter && *(prm->IWork+Er7)==0 ){
            #ifdef MATLAB_MEX_FILE
            printf("Warning in %s, Error calculating Ps at MN = prm->MNp. There may be error in output pressure\n", prm->BlkNm);
            #endif
            *(prm->IWork+Er7) = 1;
        }
        //Ap = Wp*divby(Vg * rhosg/C_SINtoSFT);  //20221209- in2
        Ap = Wp*divby(Vg * rhosg);  //20221209+ m2
        Vp = Vg;
        Tsp = TsMNg;
        Psp = PsMNg;
        rhosp = rhosg;
        hsp = hsg;
        /* calculate secondary flow area */
        Pss = Psp;
        PcalcStat(Pts, Pss, Tts, hts, FARs, Rts, &Sin, &TsMNg, &hsg, &rhosg, &Vg);
        if (Vg <= 0) {
            //Vg = 0.00001;  //20221209- 0.00001的单位为ft/s
            Vg = 0.00001 / 3.28084;  //20221209+ 0.00001的单位改为m/s
            if(iter >= maxiter && *(prm->IWork+Er8)==0 ){
                #ifdef MATLAB_MEX_FILE
                printf("Warning in %s, Secondary flow velocity is zero\n", prm->BlkNm);
                #endif
                *(prm->IWork+Er8) = 1;
            }
        }
        
        //MNg = Vg*divby(sqrtT(1.4*Rts*TsMNg*C_GRAVITY*JOULES_CONST));  //20221209-
        MNg = Vg*divby(sqrtT(1.4*Rts*TsMNg));  //20221209+

        //As = Ws*divby((Vg * rhosg/C_SINtoSFT));  //20221209-  in2
        As = Ws*divby((Vg * rhosg));  //20221209+ m2
        Vs = Vg;
        Tss = TsMNg;
        Pss = PsMNg;
        rhoss = rhosg;
        hss = hsg;
        
        if (prm->SWPS < 0.5){
            Aphy1 = Ap;
            V1 = Vp;
			MN1 = prm->MNp;
            Ps1 = Psp;
            Aphy2 = As;
            V2 = Vs;
			MN2 = MNg;
            Ps2 = Pss;
        }
        else {
            Aphy2 = Ap;
            V2 = Vp;
			MN2 = prm->MNp;
            Ps2 = Psp;
            Aphy1 = As;
            V1 = Vs;
			MN1 = MNg;
            Ps1 = Pss;
        }
    }
    else {
        /* Set areas to input parameter values */
	/*	if (betaRVABI > 1.5)
			betaRVABI = 1.5;
		else if (betaRVABI < 0.5)
			betaRVABI = 0.5;*/
        Aphy1 = prm->Aphy1In*(1 + hpA1)*betaRVABI;		// 对应外涵道
        Aphy2 = (prm->Aphy1In*(1 + hpA1) + prm->Aphy2In*(1 + hpA2)) - Aphy1;			// 对应LPT
        /* start iteration to find Ps1in */
        /* guess Ps1 and calculate an initial Area error */
        MN1g = 0.3;
        gammat1g = 1.4;
        Ts1g = Tt1In*divby(1+MN1g*MN1g*(gammat1g-1)/2);
        Ps1g = Pt1In*powT((Ts1g*divby(Tt1In)),(gammat1g*divby(gammat1g-1)));
        PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
        //A1calc = W1In*divby(V1 * rhos1/C_SINtoSFT);  //20221209-  in2
        A1calc = W1In*divby(V1 * rhos1);  //20221209+ m2
        E1 = fabs((Aphy1 - A1calc)*divby(Aphy1));
        
        /* iterate to find static pressure, calculated area should be close to actual area */
        iter1 = 0;
        //Ps1g_new = Ps1g + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
        Ps1g_new = Ps1g - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
        //E1thr = 0.001;   //20230114-
        E1thr = 1e-10;   //20230114+ liukai
        while ( fabs(E1) > E1thr && iter1 < maxiter) {
            E1_old = E1;
            Ps1g_old = Ps1g;
            //if(fabs(Ps1g - Ps1g_new) < 0.03) {  //20221209- 0.03的单位为lbf/in2 Or PSI
            if(fabs(Ps1g - Ps1g_new) < 0.03 / 0.2248089 * 39.3700787 * 39.3700787) {  //20221209+ 0.03的单位改为N/m2 Or Pa
                //Ps1g = Ps1g + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
                //Ps1g = Ps1g + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa   //20230114-
                //Ps1g = Ps1g - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa   //20230114+	// 20230820- liukai
				Ps1g = Ps1g_new;				// 20230820+ liukai
            }
            else {
                Ps1g = Ps1g_new;
            }
            /* calculate flow velocity and rhos */
            PcalcStat(Pt1In, Ps1g, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
            
            if (V1 < 1e-4) {		// 20230820+ liukai
                //V1 = 0.00001;  //20221209- 0.00001的单位为ft/s
                //V1 = 0.00001 / 3.28084;  //20221209+ 0.00001的单位改为m/s		// 20230820- liukai
				V1 = 0;	// 20230820+ liukai
				Ps1g = Pt1In;
				Ps1g_old = Pt1In * (1 - 1e-10);
				double S1in_old, Ts1_old, hs1_old, rhos1_old, V1_old;
				PcalcStat(Pt1In, Ps1g_old, Tt1In, ht1in, FARc1In, Rt1, &S1in_old, &Ts1_old, &hs1_old, &rhos1_old, &V1_old);
				E1_old = (Aphy1 - W1In * divby(V1_old * rhos1_old))*divby(Aphy1);

                if(iter1 >= maxiter && *(prm->IWork+Er9)==0 ){
                    #ifdef MATLAB_MEX_FILE
                    printf("Warning in %s, Input 1 flow velocity is zero\n", prm->BlkNm);
                    #endif
                    *(prm->IWork+Er9) = 1;
                }
            }
            
            /* calculated Area */
            //A1calc = W1In*divby(V1 * rhos1/C_SINtoSFT);  //20221209- in2
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
                Ps1g_new = Ps1g - E1 *(Ps1g - Ps1g_old)*divby(E1 - E1_old);
                /* limit algorthim change */
                //20230114-
//                if (Ps1g_new > 1.1*Ps1g) {
//                    Ps1g_new = 1.1 * Ps1g;
//                }
//                else if (Ps1g_new < 0.9 * Ps1g) {
//                    Ps1g_new = 0.9 * Ps1g;
//                }
                //20230114
                //20230114+ liukai
				if (Ps1g_new > Pt1In)
				{
					Ps1g_new = Pt1In;
				}
                if (Ps1g_new > 1.03*Ps1g) {
                    Ps1g_new = 1.03 * Ps1g;
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
        Ps1 = Ps1g;
        if (iter1 >= maxiter && *(prm->IWork+Er10)==0){
            #ifdef MATLAB_MEX_FILE
            printf("Warning in %s, unable to caluclate Ps1 within allowed iterations, PtOut may contain high error\n", prm->BlkNm);
            #endif
            *(prm->IWork+Er10) = 1;
        }
        /* end Ps1in iteration */
        
        /* start iteration to find Ps2in */
        /* guess Ps2 and calculate an initial Area error */
        MN2g = 0.3;
        gammat2g = 1.4;
        Ts2g = Tt2In*divby(1+MN2g*MN2g*(gammat2g-1)/2);
        Ps2g = Pt2In*powT((Ts2g*divby(Tt2In)),(gammat2g*divby(gammat2g-1)));
        PcalcStat(Pt2In, Ps2g, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
        //A2calc = W2In*divby(V2 * rhos2/C_SINtoSFT);  //20221209- in2
        A2calc = W2In*divby(V2 * rhos2);  //20221209+ m2
        E2 = fabs((Aphy2 - A2calc)*divby(Aphy2));
        
        /* iterate to find static pressure, calculated area should be close to actual area */
        iter2 = 0;
        //Ps2g_new = Ps2g + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
        Ps2g_new = Ps2g - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
        E2thr = E1thr;
        while ( fabs(E2) > E2thr  && iter2 < maxiter) {	// 20230820+ liukai 10*maxiter->maxiter
            E2_old = E2;
            Ps2g_old = Ps2g;
            //if(fabs(Ps2g - Ps2g_new) < 0.03) {  //20221209- 0.03的单位为lbf/in2 Or PSI
            if(fabs(Ps2g - Ps2g_new) < 0.03 / 0.2248089 * 39.3700787 * 39.3700787) {  //20221209+ 0.03的单位改为N/m2 Or Pa
                //Ps2g = Ps2g + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
                //Ps2g = Ps2g + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa  //20221215-
                //Ps2g = Ps2g - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa  //20221215+ // 20230820- liukai
				Ps2g = Ps2g_new;		// 20230820+ liukai
            }
            else {
                Ps2g = Ps2g_new;
            }
            /* calculate flow velocity and rhos */
            PcalcStat(Pt2In, Ps2g, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
            if (V2 < 1e-4) {		// 20230820+ liukai
                //V2 = 0.00001;  //20221209- 0.00001的单位为ft/s
                //V2 = 0.00001 / 3.28084;  //20221209+ 0.00001的单位改为m/s		// 20230820- liukai
				V2 = 0;		// 20230820+ liukai
				Ps2g = Pt2In;
				Ps2g_old = Pt2In * (1 - 1e-10);
				double S2in_old, Ts2_old, hs2_old, rhos2_old, V2_old;
				PcalcStat(Pt2In, Ps2g_old, Tt2In, ht2in, FARc2In, Rt2, &S2in_old, &Ts2_old, &hs2_old, &rhos2_old, &V2_old);
				E2_old = (Aphy2 - W2In * divby(V2_old * rhos2_old))*divby(Aphy2);

                if(iter2 >= maxiter && *(prm->IWork+Er11)==0 ){
                    #ifdef MATLAB_MEX_FILE
                    printf("Warning in %s, Input 2 flow velocity is zero\n", prm->BlkNm);
                    #endif
                    *(prm->IWork+Er11) = 1;
                }
            }
            /* calculated Area */
            //A2calc = W2In*divby(V2 * rhos2/C_SINtoSFT);  //20221209- in2
			if (W2In > 0)		// 20230820+ liukai
			{
				if (V2 < 1e-4)
					A2calc = W2In / (1e-4*rhos2);
				else
					A2calc = W2In * divby(V2 * rhos2);  //20221209+ m2
			}
			else
			{
				Ps2g = Pt2In;
				PcalcStat(Pt2In, Ps2g, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
				A2calc = Aphy2;
				E2 = 0;
				break;
			}
            /*determine error */
            E2 = (Aphy2 - A2calc)*divby(Aphy2);
            
            if (fabs(E2) > E2thr) {
                /* determine next guess pressure by secant algorithm */
                Ps2g_new = Ps2g - E2 *(Ps2g - Ps2g_old)*divby(E2 - E2_old);
                /* limit algorthim change */
                //20221215-
//                if (Ps2g_new > 1.1*Ps2g) {
//                    Ps2g_new = 1.1 * Ps2g;
//                }
//                else if (Ps2g_new < 0.9 * Ps2g) {
//                    Ps2g_new = 0.9 * Ps2g;
//                }
                //20221215
                //20221215+
				if (Ps2g_new > Pt2In)
				{
					Ps2g_new = Pt2In;
				}
                if (Ps2g_new > 1.03*Ps2g) {
                    Ps2g_new = 1.03 * Ps2g;
                }
                else if (Ps2g_new < 0.95 * Ps2g) {
                    Ps2g_new = 0.95 * Ps2g;
                }
                //20230114
            }
            iter2 = iter2 + 1;
			if (fabs(E2 - E2_old) < 1e-10)		// 20230820+ liukai 
				break;
        }
        Ps2 = Ps2g;
        //if (iter1 >= maxiter && *(prm->IWork+Er12)==0){       //20230114-
        if (iter2 >= maxiter && *(prm->IWork+Er12)==0){         //20230114+
            #ifdef MATLAB_MEX_FILE
            printf("Warning in %s, unable to caluclate Ps2 within allowed iterations, PtOut may contain high error\n", prm->BlkNm);
            #endif
            *(prm->IWork+Er12) = 1;
        }
        /* end Ps2 iteration */	
		// 20230816+ liukai
		if (W1In < 1e-6)
		{
			Ps1 = Pt1In;
			V1 = 0;
			Ts1 = Tt1In;
			E1 = 0;
		}
		if (W2In < 1e-6)
		{
			Ps2 = Pt2In;
			V2 = 0;
			Ts2 = Tt2In;
			E2 = 0;
		}
		// liukai
		if (isDyn > 0.5)
		{
			if (PsMixer <= Pt1In)
				E1 = 0;
			else
				E1 = 1;
			if (PsMixer <= Pt2In)
				E2 = 0;
			else
				E2 = 1;
			double WIn1MN1, Ps1MN1, rhos1MN1, V1MN1, WIn2MN1, Ps2MN1, rhos2MN1, V2MN1;
			calcWvsMN1_GTESS(Pt1In, Tt1In, FARc1In, Aphy1, &WIn1MN1, &Ps1MN1, &rhos1MN1, &V1MN1, &E1);
			calcWvsMN1_GTESS(Pt2In, Tt2In, FARc2In, Aphy2, &WIn2MN1, &Ps2MN1, &rhos2MN1, &V2MN1, &E2);

			if (PsMixer*(1+hpMixerPs) > Ps1MN1 && PsMixer > Ps2MN1)
			{
				Ps1 = PsMixer*(1+hpMixerPs);
				Ps2 = PsMixer;
				PcalcStat(Pt1In, Ps1, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
				PcalcStat(Pt2In, Ps2, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
				W1calc = Aphy1 * V1 * rhos1;
				W2calc = Aphy2 * V2 * rhos2;
				NErrW1 = (W1In - W1calc) * divby(W1In);
				NErrW2 = (W2In - W2calc) * divby(W2In);
			}
			else if (PsMixer*(1+hpMixerPs) <= Ps1MN1 && PsMixer > Ps2MN1)
			{
				Ps1 = Ps1MN1;
				PcalcStat(Pt1In, Ps1, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
				rhos1 = rhos1MN1;
				V1 = V1MN1;
				W1calc = WIn1MN1;

				Ps2 = PsMixer;
				PcalcStat(Pt2In, Ps2, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
				W2calc = Aphy2 * V2 * rhos2;

				NErrW1 = (W1In - W1calc) * divby(W1In);
				NErrW2 = (W2In - W2calc) * divby(W2In);
			}
			else if (PsMixer*(1+hpMixerPs) > Ps1MN1 && PsMixer <= Ps2MN1)
			{
				Ps1 = PsMixer*(1+hpMixerPs);
				PcalcStat(Pt1In, Ps1, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
				W1calc = Aphy1 * V1 * rhos1;

				Ps2 = Ps2MN1;
				PcalcStat(Pt2In, Ps2, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
				rhos2 = rhos2MN1;
				V2 = V2MN1;
				W2calc = WIn2MN1;

				NErrW1 = (W1In - W1calc) * divby(W1In);
				NErrW2 = (W2In - W2calc) * divby(W2In);
			}
			else
			{
				Ps1 = Ps1MN1;
				PcalcStat(Pt1In, Ps1, Tt1In, ht1in, FARc1In, Rt1, &S1in, &Ts1, &hs1, &rhos1, &V1);
				rhos1 = rhos1MN1;
				V1 = V1MN1;
				W1calc = WIn1MN1;

				Ps2 = Ps2MN1;
				PcalcStat(Pt2In, Ps2, Tt2In, ht2in, FARc2In, Rt2, &S2in, &Ts2, &hs2, &rhos2, &V2);
				rhos2 = rhos2MN1;
				V2 = V2MN1;
				W2calc = WIn2MN1;

				NErrW1 = (W1In - W1calc) * divby(W1In);
				NErrW2 = (W2In - W2calc) * divby(W2In);

				E1 = 2;
				E2 = 2;
				if (Ps1MN1 > Ps2MN1)		// 这里在建立影子喷管
				{
					Ps2 = PsMixer;
				}
				else
				{
					Ps1 = PsMixer*(1+hpMixerPs);
				}
			}

		}
		else
		{
			NErrW1 = (PsMixer - Ps2) / Ps2;
			NErrW2 = (Ps1 - Ps2*(1+hpMixerPs)) * divby(Ps2);
		}
		gammas1 = t2gc(Ts1, FARc1In);
		MN1 = V1 * divby(sqrtT(gammas1*Rt1*Ts1));
		gammas2 = t2gc(Ts2, FARc2In);
		MN2 = V2 * divby(sqrtT(gammas2*Rt2*Ts2));
        
        
    } /* end off-Design caulcation of Ps1, Ps2, Aphy1, Aphy2 ,V1, and V2 */
    
    
    if ((Ps1 > Pt1In || Ps2 > Pt2In) && *(prm->IWork+Er13)==0 ){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating input static pressures\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er13) = 1;
    }
    
    /* determine area */
    Aphyout = Aphy1 + Aphy2;
    
    /* start iteration to find Psout */
    /* guess a Ptout */
	if (WOut > 1)
	{
		Ptoutg = (W1In* Pt1In + W2In * Pt2In)*divby(WOut);
	}
	else
	{
		Ptoutg = (1* Pt1In + 1 * Pt2In)*divby(2);
	}
    /* guess Psout and calculate an initial Area error */
    MNoutg = 0.3;
    gammatoutg = 1.4;
    Tsoutg = TtOut*divby(1+MNoutg*MNoutg*(gammatoutg-1)/2);
    Psoutg = Ptoutg*powT((Tsoutg*divby(TtOut)),(gammatoutg*divby(gammatoutg-1)));
    PcalcStat(Ptoutg, Psoutg, TtOut, htOut, FARcOut, Rtout, &Sout, &Tsout, &hsout, &rhosout, &Vout);
    //Aoutcalc = WOut*divby(Vout * rhosout/C_SINtoSFT);  //20221209- in2
    Aoutcalc = WOut*divby(Vout * rhosout);  //20221209+ m2
    /* determine guess error for static pressure iteration */
    Eout2 = (Aphyout - Aoutcalc)*divby(Aphyout);

    /* determine guess error for total pressure iteration */

    //ImpulseMixed = prm->s_M_Imp1*(Ps1*Aphy1 + W1In * V1 * prm->s_M_V1/C_GRAVITY) + prm->s_M_Imp2*(Ps2 * Aphy2 + W2In * V2 * prm->s_M_V2/ C_GRAVITY);  //20221209-  lbf
    ImpulseMixed = prm->s_M_Imp1*(Ps1*Aphy1 + W1In * V1 * prm->s_M_V1) + prm->s_M_Imp2*(Ps2 * Aphy2 + W2In * V2 * prm->s_M_V2);  //20221209+  N
    //Impulseoutputg = Psoutg * Aphyout + WOut * Vout/C_GRAVITY;  //20221209-  lbf
    Impulseoutputg = Psoutg * Aphyout + WOut * Vout;  //20221209+ N
    Eout1 = fabs((ImpulseMixed - Impulseoutputg)*divby(ImpulseMixed));
    /* determine iteration constants */
    iter3a = 0;
    iter3b = 0;
    //Ptoutg_new = Ptoutg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
    Ptoutg_new = Ptoutg + 2e-4 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
    //Psoutg_new = Psoutg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
    Psoutg_new = Psoutg - 2e-4 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
    Eout1thr = 1e-10;
    Eout2thr = 1e-10;
    /* iterate to find total pressure, calculated from errors in Impulse  */
    while ( (fabs(Eout1) > Eout1thr || fabs(Eout2) > Eout2thr) && iter3a < maxiter) {
        Eout1_old = Eout1;
        Ptoutg_old = Ptoutg;
        //if(fabs(Ptoutg - Ptoutg_new) < 0.03) {  //20221209- 0.03的单位为lbf/in2 Or PSI
        if(fabs(Ptoutg - Ptoutg_new) < 1e-4 / 0.2248089 * 39.3700787 * 39.3700787) {  //20221209+ 0.03的单位改为N/m2 Or Pa
            //Ptoutg = Ptoutg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
            //Ptoutg = Ptoutg + 2e-6 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa	// 20230820- liukai
			Ptoutg = Ptoutg_new;			// 20230820+ liukai
        }
        else {
            Ptoutg = Ptoutg_new;
        }
        iter3b = 0;  //20230114+
			// 20230820+ liukai
		MNoutg = 0.3;
		gammatoutg = 1.4;
		Tsoutg = TtOut * divby(1 + MNoutg * MNoutg*(gammatoutg - 1) / 2);
		Psoutg = Ptoutg * powT((Tsoutg*divby(TtOut)), (gammatoutg*divby(gammatoutg - 1)));
		PcalcStat(Ptoutg, Psoutg, TtOut, htOut, FARcOut, Rtout, &Sout, &Tsout, &hsout, &rhosout, &Vout);
		Aoutcalc = WOut * divby(Vout * rhosout);  //20221209+ m2
		Eout2 = fabs(Aphyout - Aoutcalc)*divby(Aphyout);
		Psoutg_new = Psoutg - 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
        /* iterate to find static pressure, calculated area should be close to actual area */
        do{
            Eout2_old = Eout2;
            Psoutg_old = Psoutg;
            //if(fabs(Psoutg - Psoutg_new) < 0.03) {  //20221209- 0.03的单位为lbf/in2 Or PSI
            if(fabs(Psoutg - Psoutg_new) < 1e-4 / 0.2248089 * 39.3700787 * 39.3700787) {  //20221209+ 0.03的单位改为N/m2 Or Pa
                //Psoutg = Psoutg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
                //Psoutg = Psoutg + 0.05 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa   //20230114-
                //Psoutg = Psoutg - 2e-6 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa   //20230114+			// 20230820- liukai
				Psoutg = Psoutg_new;			// 20230820+ liukai
            }
            else {
                Psoutg = Psoutg_new;
            }
            /* calculate flow velocity and rhos */
            PcalcStat(Ptoutg, Psoutg, TtOut, htOut, FARcOut, Rtout, &Sout, &Tsout, &hsout, &rhosout, &Vout);
            if (Vout < 1e-4) {
                //Vout = 0.00001;  //20221209- 0.00001的单位为ft/s
                //Vout = 0.00001 / 3.28084;  //20221209+ 0.00001的单位改为m/s		// 20230820- liukai
				Vout = 0;
				Psoutg = Ptoutg;
				Psoutg_old = Ptoutg * (1 - 1e-10);
				double Sout_old, Tsout_old, hsout_old, rhosout_old, Vout_old;
				PcalcStat(Ptoutg, Psoutg_old, TtOut, htOut, FARcOut, Rtout, &Sout_old, &Tsout_old, &hsout_old, &rhosout_old, &Vout_old);
				Eout2_old = (Aphyout - WOut * divby(Vout_old * rhosout_old))*divby(Aphyout);

				if(iter3b >= maxiter && *(prm->IWork+Er14)==0 ){		// liukai: 20230214; iter这里并未使用，更换掉
                    #ifdef MATLAB_MEX_FILE
                    printf("Warning in %s, Output flow velocity is zero\n", prm->BlkNm);
                    #endif
                    *(prm->IWork+Er14) = 1;
                }
            }
            /* calculated Area */
            //Aoutcalc = WOut*divby(Vout * rhosout/C_SINtoSFT);  //20221209- in2
            //Aoutcalc = WOut*divby(Vout * rhosout);  //20221209+ m2	// 20230820- liukai
			if (WOut > 0)		// 20230820+ liukai
			{
				if (Vout < 1e-4)
					Aoutcalc = WOut / (1e-4*rhosout);
				else
					Aoutcalc = WOut * divby(Vout * rhosout);  //20221209+ m2
			}
			else
			{
				Psoutg = Ptoutg;
				PcalcStat(Ptoutg, Psoutg, TtOut, htOut, FARcOut, Rtout, &Sout, &Tsout, &hsout, &rhosout, &Vout);
				Aoutcalc = Aphyout;
				Eout2 = 0;
				break;
			}
            /*determine error */
            Eout2 = (Aphyout - Aoutcalc)*divby(Aphyout);
            if (fabs(Eout2) > Eout2thr) {
                /* determine next guess pressure by secant algorithm */
                Psoutg_new = Psoutg - Eout2 *(Psoutg - Psoutg_old)*divby(Eout2 - Eout2_old);
                /* limit algorthim change */
                //20230114-
//                if (Psoutg_new > 1.05*Psoutg) {
//                    Psoutg_new = 1.05 * Psoutg;
//                }
//                else if (Psoutg_new < 0.95 * Psoutg) {
//                    Psoutg_new = 0.95 * Psoutg;
//                }
                //20230114
                //20230114+
				if (Psoutg_new > Ptoutg)
				{
					Psoutg_new = Ptoutg;
				}
                if (Psoutg_new > 1.05*Psoutg) {
                    Psoutg_new = 1.05 * Psoutg;
                }
                else if (Psoutg_new < 0.95 * Psoutg) {
                    Psoutg_new = 0.95 * Psoutg;
                }
                //20230114
            }
            iter3b = iter3b + 1;
			if (fabs(Eout2 - Eout2_old) < 1e-10)		// 20230820+ liukai 
				break;
        } while ( fabs(Eout2) > Eout2thr && iter3b < maxiter);
        
        /* verify Ps is <= Pt */		// 20230820- liukai
  /*      if (Psoutg > Ptoutg){
            Psoutg = Ptoutg;
            if (*(prm->IWork+Er15)==0){
                #ifdef MATLAB_MEX_FILE
                printf ("Warning in %s, Error calculating Psout\n", prm->BlkNm);
                #endif
                *(prm->IWork+Er15) = 1;
            }
        }*/
        /* end Psout iteration for current Ptout guess */
        
        /* calculate impulse output based on current Pt guess */
        //Impulseoutputg = Psoutg * Aphyout + WOut * Vout/C_GRAVITY;  //20221209- 1bf
        Impulseoutputg = Psoutg * Aphyout + WOut * Vout;  //20221209+ N
        /* calculate impulse error */
        Eout1 = fabs((ImpulseMixed - Impulseoutputg)*divby(ImpulseMixed));
        if (fabs(Eout1) > Eout1thr) {
            /* determine next guess pressure by secant algorithm */
            Ptoutg_new = Ptoutg - Eout1 *(Ptoutg - Ptoutg_old)*divby(Eout1 - Eout1_old);
            /* limit algorthim change */
            if (Ptoutg_new > 1.05*Ptoutg) {
                Ptoutg_new = 1.05 * Ptoutg;
            }
            else if (Ptoutg_new < 0.95 * Ptoutg) {
                Ptoutg_new = 0.95 * Ptoutg;
            }
        }
        
        iter3a = iter3a + 1;
		if (fabs(Eout1 - Eout1_old) < 1e-10)		// 20230820+ liukai 
			break;
    }
    /* end PtOut iteration */
    Psout = Psoutg;
    PtOut = Ptoutg;
	gammatoutg = t2gc(Tsout, FARcOut);
	MNoutg = Vout * divby(sqrtT(gammatoutg*Rtout*Tsout));

	if (WOut < 1e-6)		// 20230816+ liukai 
	{
		PtOut = (Pt1In + Pt2In) / 2;
		Psout = PtOut;
		Vout = 0;
		MNoutg = 0;
		Eout1 = 0;
		Eout2 = 0;
	}

    if (iter3a >= maxiter && *(prm->IWork+Er16)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Error in %s, unable to calculate PtOut\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er16) = 1;
    }

    if (iter3b >= maxiter && *(prm->IWork+Er17)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, unable to caluclate PsOut, PtOut may contain high error\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er17) = 1;
    }
    
    /* Compute normalized error */
	if (prm->IDes < 0.5)
	{
		NErrW1 = (PsMixer - Psp) / Psp;
		NErrW2 = (W1In*divby(W2In) - prm->BPRdes)*divby(W1In*divby(W2In));
	}
        
    
    /*------Assign output values------------*/
    y[0] = WOut;      /* Output Air Flow [pps]			    */  //20221209+ kg/s
    y[1] = htOut; 	  /* Output Enthalpy [BTU/lbm] 		    */  //20221209+ J/kg
    y[2] = TtOut;     /* Output Temperature  [degR]		    */  //20221209+ K
    y[3] = PtOut;     /* Output Pressure [psia]			    */  //20221209+ N/m2 Or Pa
    y[4] = FARcOut;   /* Output Combusted Fuel to Air Ratio [frac]  */
    y[5] = NErrW1;      /* Normalized Static Pressure Error           */
    y[6] = Ps1;     /* Area of input 1 [in^2]                     */  //20221209+ m2
    y[7] = Ps2;     /* Area of input 2 [in^2]                     */  //20221209+ m2
	y[8] = NErrW2;
	y[9] = MN1;
	y[10] = MN2;
	y[11] = MNoutg;
	y[12] = E1;
	y[13] = E2;
	y[14] = Eout1;
	y[15] = Eout2;  
//	printf("E1 = %f, E2 = %f, Eout1 = %f, Eout2 = %f\n", E1, E2, Eout1, Eout2);
}
