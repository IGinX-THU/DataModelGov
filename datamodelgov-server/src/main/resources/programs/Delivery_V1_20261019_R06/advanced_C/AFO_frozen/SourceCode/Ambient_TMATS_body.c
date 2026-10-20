#include "types_TMATS.h"
#include "constants_TMATS.h"
#include "functions_TMATS.h"
#include <math.h>

#ifdef MATLAB_MEX_FILE
#include "simstruc.h"
#endif

void Ambient_TMATS_body(double *y, const double *u, const AmbientStruct* prm)
{
    double AltIn     = u[0];     /* Altitude(ft) 	*/         //20221209+ m
    double dTempIn   = u[1];     /* delta Temperature [degF] 	*/ //20221209+ K
    double MNIn      = u[2];     /* Mach Number (frac) 	*/         
    
    /*--------Define Constants-------*/
    double PsOut, TsOut, TtOut, PtOut, VengOut, TsStDayOut, Vsound;
    double Ttg, Ptg, Vg, Vsg, MNg, Sout, htg, gammasg, Rs, Rt;
    double hs, htOut, Test; 
    double er, er_old, erthr, Ptg_new, Ptg_old, FAR, FAROut;
    int iter, maxiter;
    
    int interpErr = 0;

    FAR = prm->AFARc;
    
/*  Rt = interp1Ac(prm->X_A_FARVec,prm->T_A_RtArray,FAR,prm->B,&interpErr);	// liukai -
	if (interpErr == 1 && *(prm->IWork + Er1) == 0) {
	#ifdef MATLAB_MEX_FILE
			printf("Warning in %s, Error calculating Rt. Vector definitions may need to be expanded.\n", prm->BlkNm);
	#endif
			*(prm->IWork + Er1) = 1;
	}*/
	Rt = Rcalc(FAR);		// liukai +    
    Rs = Rt;
    
    /*  Static Temperature */
    TsStDayOut = interp1Ac(prm->X_A_AltVec,prm->T_A_TsVec,AltIn,prm->A,&interpErr);
    if (interpErr == 1 && *(prm->IWork+Er2) == 0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating TsStDayOut. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er2) = 1;
    }
    TsOut = TsStDayOut + dTempIn;
    
    /* Static Pressure*/
    PsOut = interp1Ac(prm->X_A_AltVec,prm->T_A_PsVec,AltIn,prm->A,&interpErr);
    if (interpErr == 1 && *(prm->IWork+Er3) == 0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating PsOut. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er3) = 1;
    }
	TsOut = TsOut - 288.14999999999998 + C_TSTD; // 20230913+, liukai, ACE
	PsOut = PsOut - 101325.37910000001 + 101325.0;		// liukai +
    
    /* Calc output entropy */
    Sout = pt2sc(PsOut, TsOut, FAR);
    /* Determine Static enthalpy */
    hs = t2hc(TsOut,FAR);
    
    /* Pt guess */
    /*------ Total Temperature ---------*/
    Ttg = TsOut * (1+MNIn*MNIn*(C_GAMMA-1)/2);
    /*------ Total Pressure ---------*/
    Ptg = PsOut*divby((powT((TsOut*divby(Ttg)),(C_GAMMA*divby(C_GAMMA-1)))));
    
    /* calculate total temperature */
    Ttg = sp2tc(Sout,Ptg,FAR);
    /* calculate total enthalpy */
    htg = t2hc(Ttg,FAR);
    /* calculate velocity */
    //Vg = sqrtT(2 * (htg - hs)*C_GRAVITY*JOULES_CONST);   //20221209- ft/s
    Vg = sqrtT(2 * (htg - hs));   //20221209+ m/s

//    gammasg = interp2Ac(prm->X_A_FARVec,prm->Y_A_TVec,prm->T_A_gammaArray,FAR,TsOut,prm->B,prm->C,&interpErr);
	gammasg = t2gc(TsOut, FAR);
    if (interpErr == 1 && *(prm->IWork+Er4) == 0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating iteration gammasg. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er4) = 1;
    }
    //Vsg = sqrtT(gammasg*Rs*TsOut*C_GRAVITY*JOULES_CONST);  //20221209- ft/s
    Vsg = sqrtT(gammasg*Rs*TsOut);  //20221209+ m/s
    MNg = Vg*divby(Vsg);
    er = MNIn - MNg;
    //Ptg_new = Ptg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
    Ptg_new = Ptg + 0.01 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
    maxiter = 100;			// liukai
    iter = 0;
    erthr = 1e-10;			// liukai
    
    while (fabs(er) > erthr && iter < maxiter) {
        er_old = er;
        Ptg_old = Ptg;
        //if(fabs(Ptg - Ptg_new) < 0.03)  //20221209- 0.03的单位为lbf/in2 Or PSI
        if(fabs(Ptg - Ptg_new) < 0.01 / 0.2248089 * 39.3700787 * 39.3700787)  //20221209+ 0.03的单位改为N/m2 Or Pa
            //Ptg = Ptg + 0.05;  //20221209- 0.05的单位为lbf/in2 Or PSI
            Ptg = Ptg + 0.01 / 0.2248089 * 39.3700787 * 39.3700787;  //20221209+ 0.05的单位改为N/m2 Or Pa
        else
            Ptg = Ptg_new;
        /* calculate Total emperature */
        Ttg = sp2tc(Sout,Ptg,FAR);
        /* calculate total enthalpy */
        htg = t2hc(Ttg,FAR);
        /* calculate velocity */
        //Vg = sqrtT(2 * (htg - hs)*C_GRAVITY*JOULES_CONST);  //20221209- ft/s
        Vg = sqrtT(2 * (htg - hs));  //20221209+ m/s

        //Vsg = sqrtT(gammasg*Rs*TsOut*C_GRAVITY*JOULES_CONST);  //20221209- ft/s
		gammasg = t2gc(TsOut, FAR);
        Vsg = sqrtT(gammasg*Rs*TsOut);  //20221209+ m/s
        MNg = Vg*divby(Vsg);
        er = MNIn - MNg;
        if (fabs(er) > erthr) {
            /* determine next guess pressure by secant algorithm */
            Ptg_new = Ptg - er *(Ptg - Ptg_old)*divby(er - er_old);
        }
        iter = iter + 1;
    }
    if (iter == maxiter && *(prm->IWork+Er5)==0 ){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating Pt at input MN. There may be error in output pressure\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er5) = 1;
    }
    
 //   htOut = htg;		// liukai -
 //   TtOut = Ttg;		// liukai -
 //   PtOut = Ptg;		// liukai -
	TtOut = Ttg - 288.15999999999985 + 288.16;			// liukai +  ACE
	PtOut = Ptg;		// liukai +
	htOut = t2hc(TtOut, FAR);		// liukai +
    
    /*---- Engine Velocity ---------*/
    Vsound = Vsg;
    VengOut = Vsound * MNIn;
    
    FAROut = FAR;

    Test = divby(dTempIn);
    
    /*------Assign output values------------*/
    y[0] = htOut;      /* Total enthalpy */
    y[1] = TtOut;      /* Total Temperature [degR] */  //20221209+ K
    y[2] = PtOut;      /* Total Pressure [psia] */     //20221209+ N/m2 Or Pa
    y[3] = FAROut;     /* Fuel to Air Ratio */
    y[4] = PsOut;      /* Static Pressure [psia] */    //20221209+ N/m2 Or Pa
    y[5] = TsOut;      /* Static Temperature [degR] */ //20221209+ K
    y[6] = VengOut;    /* Engine Velocity [ft/sec] */  //20221209+ m/s
    y[7] = Test;       /* Test signal */
    
}
