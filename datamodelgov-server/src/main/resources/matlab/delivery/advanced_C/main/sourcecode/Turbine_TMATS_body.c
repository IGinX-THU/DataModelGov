#include "types_TMATS.h"
#include "constants_TMATS.h"
#include "shtStartStop.h"
#include "functions_TMATS.h"
#include <math.h>

#ifdef MATLAB_MEX_FILE
#include "simstruc.h"
#endif

static double TurbineFullPressureMapAtBetaNode(
    const TurbineStruct* prm, double ncMap, int betaIndex)
{
    int row = prm->A - 2;
    int i;
    double fraction;
    for (i = prm->A - 2; i >= 0; --i)
    {
        if (ncMap >= prm->Y_T_NcVec[i])
        {
            row = i;
            break;
        }
        row = 0;
    }
    fraction = (ncMap - prm->Y_T_NcVec[row]) /
        (prm->Y_T_NcVec[row + 1] - prm->Y_T_NcVec[row]);
    return prm->T_T_Map_PRArray[betaIndex + prm->B * row] + fraction *
        (prm->T_T_Map_PRArray[betaIndex + prm->B * (row + 1)] -
         prm->T_T_Map_PRArray[betaIndex + prm->B * row]);
}

static double TurbineFullPressureMapBeta(
    const TurbineStruct* prm, double ncMap, double pressureRatio)
{
    int j;
    int interval = -1;
    double p0 = TurbineFullPressureMapAtBetaNode(prm, ncMap, 0);
    double p1 = p0;
    double pLast;

    for (j = 0; j < prm->B - 1; ++j)
    {
        p0 = TurbineFullPressureMapAtBetaNode(prm, ncMap, j);
        p1 = TurbineFullPressureMapAtBetaNode(prm, ncMap, j + 1);
        if ((pressureRatio >= p0 && pressureRatio <= p1) ||
            (pressureRatio <= p0 && pressureRatio >= p1))
        {
            interval = j;
            break;
        }
    }

    if (interval < 0)
    {
        p0 = TurbineFullPressureMapAtBetaNode(prm, ncMap, 0);
        pLast = TurbineFullPressureMapAtBetaNode(prm, ncMap, prm->B - 1);
        interval = fabs(pressureRatio - p0) <= fabs(pressureRatio - pLast) ?
            0 : prm->B - 2;
        p0 = TurbineFullPressureMapAtBetaNode(prm, ncMap, interval);
        p1 = TurbineFullPressureMapAtBetaNode(prm, ncMap, interval + 1);
    }

    if (fabs(p1 - p0) < 1.0e-14)
        return prm->X_T_betaVec[interval];
    return prm->X_T_betaVec[interval] +
        (pressureRatio - p0) / (p1 - p0) *
        (prm->X_T_betaVec[interval + 1] - prm->X_T_betaVec[interval]);
}

void Turbine_TMATS_body(double* y, const double* u, const double* CoolFlow, const TurbineStruct* prm)
{
    double WIn      = u[0];     /* Input Flow [pps]	*/                //20221209+ kg/s
    double htIn     = u[1];     /* input enthalpy [BTU/lbm]*/             //20221209+ J/kg
    double TtIn     = u[2];     /* Temperature Input [degR]  */           //20221209+ K
    double PtIn     = u[3];     /* Pressure Input [psia] 	 */       //20221209+ N/m2 Or Pa
    double FARcIn   = u[4];     /* Compusted Fuel to Air Ratio [frac] */
    double Nmech    = u[5];     /* Mechancial Shaft Speed [rpm]*/
    double PRIn     = u[6];     /* Pressure Ratio [NA] 	 */
    double s_T_Nc   = u[7];     /* Nc map scalar [NA]	*/
    double s_T_Wc   = u[8];     /* Wc map scalar [NA]	*/
    double s_T_PR   = u[9];     /* PR map scalar [NA]	*/
    double s_T_Eff  = u[10];     /* Eff map scalar [NA]	*/
    int    cfWidth  = u[11];     /* Cooling Flow vector length	*/
	double hpW = u[12];
	double hpEf = u[13];
	double hpPR = u[14];
	double Amean = u[15];
	double Cmean = u[16];
	double Kcla = u[17];
	double Kwe = u[18];
    
    /*--------Define Constants-------*/
    double WOut, htOut, TtOut, PtOut, FARcOut, TorqueOut, NErrorOut;
    double WcCalcin, WcMap, theta,delta, Pwrout, Wcin, Wcs1in, EDIdeal, ED, EDc, EDcRead;
    double ptheta, pdelta;
    double TtIdealout, Test, htIdealout, Sout, NcMap, Nc, EffMap, Eff;
    double dHcools1, dHcoolout, Wfcools1, Wfcoolout, dPtcools1, dPtcoolout, Ws1in,hts1in, Pts1in, Tts1in, FARs1in, hts2out, Tts2out, Pts2out;
    double Ss1in, Wcoolout, Wcools1, PRmapRead, EDcmapRead;
    double C_Eff, C_PR, C_Nc, C_Wc, C_EDc, C_PR_EDc;
    
    int interpErr = 0;
    double Wcool[100];
    double htcool[100];
    double Ttcool[100];
    double Ptcool[100];
    double FARcool[100];
    int Vtest, i;

    //20221116+
    double PRmaxFromMap = 1;
    double PRminFromMap = 1;
    double PRmapDes = 1;
	double pressureBetaExponent = 1;
	double pressureBetaInverseExponent = 1;
	double pressureBetaMinRoot = 1;
	double pressureBetaMaxRoot = 1;
	double EDcmaxFromMap = 1;
	double EDcminFromMap = 1;
	double EDcmapDes = 1;
    double betaRead = 0.5;
	double EED = 0;
    //20221116

	double Re, VIS;

    /* Verify input bleed vector is a multiple of 5 */
    Vtest = cfWidth/5;
    if(5*Vtest != cfWidth && prm->CoolFlwEn > 0.5 && *(prm->IWork+Er1)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Error in %s, one or more of the cooling flow input vector elements is missing(Vector form; 5x1: W,ht,Tt,Pt,FAR)\n",prm->BlkNm);
        #endif
        *(prm->IWork+Er1) = 1;
    }
    else if(prm->BldPosLeng != cfWidth/5 && prm->CoolFlwEn > 0.5 && *(prm->IWork+Er2)==0){
        //eflag = prm->IWork[Er2];
        #ifdef MATLAB_MEX_FILE
        printf("Error in %s, number of cooling flow inputs does not match the length of the Cooling flow postion vector in the mask\n",prm->BlkNm);
        #endif
        *(prm->IWork+Er2) = 1;
    }
    
    /* unpack CoolFlow vector */
    for (i = 0; i < cfWidth/5; i++)
    {
        if (prm->CoolFlwEn < 0.5){
            Wcool[i] = 0;
            htcool[i] = 0;
            Ttcool[i] = 0;
            Ptcool[i] = 0;
            FARcool[i] = 0;
        }
        else {
            Wcool[i] = CoolFlow[5*i];
            Ttcool[i] = CoolFlow[5*i+2];
            Ptcool[i] = CoolFlow[5*i+3];
            FARcool[i] = CoolFlow[5*i+4];
            htcool[i] = t2hc(Ttcool[i],FARcool[i]);
        }
    }
    
    /* Initialize cooling flow sum constants */
    
    dHcools1 = 0;   /* enthalpy * mass cooling flow rate at stage 1 of turbine */
    dHcoolout = 0;   /* enthalpy * mass cooling flow rate at exit of turbine */
    Wcools1 = 0;    /* total cooling flow at stage 1 of turbine*/
    Wcoolout = 0;    /* total cooling flow at output of turbine */
    Wfcools1 = 0;  /* combusted fuel flow in cooling at stage 1 of turbine */
    Wfcoolout = 0;  /* combusted fuel flow in cooling at exit of turbine */
	dPtcools1 = 0;
	dPtcoolout = 0;
    
    /* calc cooling flow constants for stage 1 and output of the turbine */
    for (i = 0; i < cfWidth/5; i++)
    {
        if ((prm->T_BldPos[i] > 1 || prm->T_BldPos[i] < 0) && prm->CoolFlwEn > 0.5 && *(prm->IWork+Er3)==0){
            #ifdef MATLAB_MEX_FILE
            printf(" Error in %s, cooling flow postion element %i needs to be defined as a 0 or 1\n",prm->BlkNm,i+1);
            #endif
            *(prm->IWork+Er3) = 1;
        }
        
        /* calc mass flow for cooling flows */
        Wcools1 = Wcools1 + Wcool[i]*(1-prm->T_BldPos[i]);
        Wcoolout = Wcoolout + Wcool[i];
        
        /* calc fuel mass flow for cooling flows*/
        Wfcools1 = Wfcools1 + FARcool[i]*Wcool[i]*(1-prm->T_BldPos[i])*divby(1+FARcool[i]);
        Wfcoolout = Wfcoolout + FARcool[i]*Wcool[i]*divby(1+FARcool[i]);
    }
    /*-- Compute Total Flow  --------*/
    
    Ws1in = WIn + Wcools1;  /* mass flow at station 1 */
    WOut = WIn + Wcoolout;   /* mass flow at turbine exit */
    
    /*-- Compute Fuel to Air Ratios ---*/
    
	if (WIn > 0)		// 20230816+ liukai
	{
		FARs1in = (FARcIn* WIn*divby(1 + FARcIn) + Wfcools1)*divby(WIn*divby(1 + FARcIn) + Wcools1 - Wfcools1);
		FARcOut = (FARcIn* WIn*divby(1 + FARcIn) + Wfcoolout)*divby(WIn*divby(1 + FARcIn) + Wcoolout - Wfcoolout);
	}
	else
	{
		FARs1in = 0;
		FARcOut = 0;
	}
    /* calc input enthalpy of cooling flow for stage 1 */
    for (i = 0; i < cfWidth/5; i++)
    {
        /* Compute cooling flow dH at stage 1  */
        dHcools1 = dHcools1 + htcool[i]*Wcool[i]*(1-prm->T_BldPos[i]);
        /* Compute cooling flow dH for the exit of the turbine assuming input htcool = htcoolout for turbine rear bleeds  */
        dHcoolout = dHcoolout + htcool[i]*Wcool[i]*prm->T_BldPos[i];
    }
	// 20230913+, liukai, ACE
	for (i = 0; i < cfWidth / 5; i++)
	{
		/* Compute cooling flow dH at stage 1  */
		dPtcools1 = dPtcools1 + Ptcool[i] * Wcool[i] * (1 - prm->T_BldPos[i]);
		/* Compute cooling flow dH for the exit of the turbine assuming input htcool = htcoolout for turbine rear bleeds  */
		dPtcoolout = dPtcoolout + Ptcool[i] * Wcool[i] * prm->T_BldPos[i];
	}
    
    /*-- Compute avg enthalpy at stage 1 --------*/
    htIn = t2hc(TtIn,FARcIn);
	if (Ws1in > 0)		// 20230816+ liukai
	{
		hts1in = (htIn* WIn + dHcools1)*divby(Ws1in);
		/*/ 气流掺混的总压掺混方式计算过于粗糙，不再使用
		Pts1in = (PtIn*WIn + dPtcools1)*divby(Ws1in);		// 20230913+, liukai, ACE
		double massbound = 0.1;
		if (Ws1in > massbound)
			Pts1in = (PtIn*WIn + dPtcools1)*divby(Ws1in);		// 20230913+, liukai, ACE
		else
			Pts1in = PtIn;		/*/
		Pts1in = PtIn;			// liukai  -
	}
	else
	{
		hts1in = htIn;
		Pts1in = PtIn;
	}
    
    /*-- Compute  stage 1 total temp--------*/
    
    Tts1in = h2tc(hts1in,FARs1in);
    
    /*-- Compute Stage 1 entropy, assuming PtIn = Pts1in  --------*/
    Ss1in = pt2sc(Pts1in,Tts1in,FARs1in);

    /*---- calculate misc. fluid condition related variables --------*/
	delta = Pts1in / C_PSTD;
    pdelta = Pts1in;
//    theta = TtIn / C_TSTD;		// liukai -
	theta = Tts1in / C_TSTD;			// liukai +
    ptheta = TtIn;
    
    /*------ Calculate corrected speed ---------*/
//    if (prm->ConfigNPSS > 0.5) /* In NPSS, turbine corrected values do not include standard day temp or pres. */		// 20230911-, liukai
//        Nc = Nmech*divby(sqrtT(ptheta));
//    else
        Nc = Nmech*divby(sqrtT(theta));
    
    
    if(prm->IDes < 0.5)
        C_Nc = Nc*divby(prm->NcDes);
    else
        C_Nc = s_T_Nc;

    
    NcMap = Nc*divby(C_Nc);

	/*------ enthalpy calculations ---------*/		// 20230911+, liukai: ConfigTurbine=0, 压比特性图; ConfigTurbine=1, 焓降特性图
	/* ---- Ideal enthalpy  ----*/
	if (prm->ConfigTurbine < 0.5)
	{
		//20221116+
		/*------ Prepare PressureRatio --------*/
		PRminFromMap = interp1Ac(prm->Y_T_NcVec, prm->T_T_minPRVec, NcMap, prm->A, &interpErr);
		PRmaxFromMap = interp1Ac(prm->Y_T_NcVec, prm->T_T_maxPRVec, NcMap, prm->A, &interpErr);
		pressureBetaExponent = prm->pressureBetaExponent > 0 ?
			prm->pressureBetaExponent : 1.0;
		if (prm->T_T_Map_PRArray != NULL &&
			prm->PRMapRw == prm->A && prm->PRMapCol == prm->B)
		{
			if (prm->IDes < 0.5)
				PRmapDes = interp2Ac(prm->Y_T_NcVec, prm->X_T_betaVec,
					prm->T_T_Map_PRArray, NcMap, prm->betaDes,
					prm->A, prm->B, &interpErr);
		}
		else if (pressureBetaExponent == 1.0)
		{
			/* Keep the legacy arithmetic path bit-for-bit unchanged. */
			if (prm->IDes < 0.5)
				PRmapDes = PRminFromMap + prm->betaDes * (PRmaxFromMap - PRminFromMap);
		}
		else
		{
			/*
			 * Equivalent split-turbine maps store endpoint pressure ratios.
			 * Interpolate in the pre-exponent pressure coordinate so that two
			 * serial stages with exponents q and 1-q reconstruct the original
			 * aggregate beta-pressure relation.
			 */
			pressureBetaInverseExponent = 1.0 / pressureBetaExponent;
			pressureBetaMinRoot = pow(PRminFromMap, pressureBetaInverseExponent);
			pressureBetaMaxRoot = pow(PRmaxFromMap, pressureBetaInverseExponent);
			if (prm->IDes < 0.5)
				PRmapDes = pow(pressureBetaMinRoot + prm->betaDes *
					(pressureBetaMaxRoot - pressureBetaMinRoot),
					pressureBetaExponent);
		}
		//20221116

		/*------ Compute pressure output --------*/
		if (prm->IDes < 0.5)
			C_PR = (PRIn - 1)*divby(PRmapDes - 1);          //20221116+
			//C_PR = (PRIn - 1)*divby(prm->PRmapDes -1);   //20221116-
		else
			C_PR = s_T_PR;
		C_PR_EDc = C_PR;

		PRmapRead = ((PRIn - 1)*divby(C_PR*(1 + hpPR))) + 1;
		if (prm->T_T_Map_PRArray != NULL &&
			prm->PRMapRw == prm->A && prm->PRMapCol == prm->B)
			betaRead = TurbineFullPressureMapBeta(prm, NcMap, PRmapRead);
		else if (pressureBetaExponent == 1.0)
			betaRead = (PRmapRead - PRminFromMap) / (PRmaxFromMap - PRminFromMap);  //20221116+
		else
			betaRead = (pow(PRmapRead, pressureBetaInverseExponent) - pressureBetaMinRoot) /
				(pressureBetaMaxRoot - pressureBetaMinRoot);

		Pts2out = Pts1in * divby(PRIn);	/* using PR from input */

		Sout = Ss1in;
		//    TtIdealout = sp2tc(Sout,Pts2out,FARcOut);			// liukai 
		//    htIdealout = t2hc(TtIdealout,FARcOut); /* may need to be updated due to TtIdealout not being correct */	// liukai
		TtIdealout = sp2tc(Sout, Pts2out, FARs1in);		// liukai
		htIdealout = t2hc(TtIdealout, FARs1in); /* may need to be updated due to TtIdealout not bei		ng correct */		// liukai
		
	}
	else
	{
		/* 认为特性图中是理想焓降 */
		Pts2out = Pts1in * divby(PRIn);	// using PR from input 
		Sout = Ss1in;
		TtIdealout = sp2tc(Sout, Pts2out, FARs1in);		// liukai
		htIdealout = t2hc(TtIdealout, FARs1in); 		// liukai
		EDIdeal = hts1in - htIdealout;
		EDc = EDIdeal / Tts1in;
		//------ Prepare PressureRatio --------
		EDcminFromMap = interp1Ac(prm->Y_T_NcVec, prm->T_T_minPRVec, NcMap, prm->A, &interpErr);
		EDcmaxFromMap = interp1Ac(prm->Y_T_NcVec, prm->T_T_maxPRVec, NcMap, prm->A, &interpErr);
		if (prm->IDes < 0.5)
			EDcmapDes = EDcminFromMap + prm->betaDes * (EDcmaxFromMap - EDcminFromMap);
		//------ Compute pressure output --------
		if (prm->IDes < 0.5)
			C_EDc = EDc * divby(EDcmapDes);          //20221116+
		else
			C_EDc = s_T_PR;
		C_PR_EDc = C_EDc;
		EDcmapRead = EDc * divby(C_EDc*(1 + hpPR));
		betaRead = (EDcmapRead - EDcminFromMap) / (EDcmaxFromMap - EDcminFromMap);  //20221116+
	}


    /*-- Compute Total Flow input (from Turbine map)  --------*/
    //WcMap = interp2Ac(prm->X_T_PRVec,prm->Y_T_NcVec,prm->T_T_Map_WcArray,PRmapRead,NcMap,prm->B,prm->A,&interpErr);   //20221116-
    //WcMap = interp2Ac(prm->X_T_betaVec,prm->Y_T_NcVec,prm->T_T_Map_WcArray,betaRead,NcMap,prm->B,prm->A,&interpErr);  //20221116+   //20221202-
    WcMap = interp2Ac(prm->Y_T_NcVec,prm->X_T_betaVec,prm->T_T_Map_WcArray,NcMap,betaRead,prm->A,prm->B,&interpErr);    //20221116+   //20221202+
    /* 起停新增的beta<0区以物理压比作为插值坐标。不同转速线的
     * PR=1落在不同beta位置，直接双线性插值会在中间转速处产生非零
     * 截距。这里连接(PR=1,Wc=0)和原图beta=0边界，不改原图区。 */
    if (shtStartStopTorqueRegularizationEnabled() &&
        prm->ConfigTurbine < 0.5 && pressureBetaExponent == 1.0 &&
        prm->T_T_Map_PRArray == NULL && prm->X_T_betaVec[0] < 0.0 &&
        betaRead < 0.0 && PRminFromMap > 1.0 + 1e-12)
    {
        double boundaryFlow = interp2Ac(prm->Y_T_NcVec,prm->X_T_betaVec,
            prm->T_T_Map_WcArray,NcMap,0.0,prm->A,prm->B,&interpErr);
        double pressureFraction = (PRmapRead - 1.0)/(PRminFromMap - 1.0);
        WcMap = boundaryFlow * (pressureFraction > 0.0 ? pressureFraction : 0.0);
    }
    if ((prm->WcMapCol != prm->B || prm->WcMapRw != prm->A) && *(prm->IWork+Er4)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating WcMap. Table size does not match axis vector lengths.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er4) = 1;
    }
    else if (interpErr == 1 && *(prm->IWork+Er4)==0){
        #ifdef MATLAB_MEX_FILE
        printf("Warning in %s, Error calculating WcMap. Vector definitions may need to be expanded.\n", prm->BlkNm);
        #endif
        *(prm->IWork+Er4) = 1;
    }
    if(prm->IDes < 0.5) {
    //    if (prm->ConfigNPSS > 0.5) /* In NPSS, turbine corrected values do not include standard day temp or pres. */			// 20230911-, liukai
    //        C_Wc = WIn  *sqrtT(ptheta)*divby(pdelta)*divby(WcMap);
    //    else
            C_Wc = Ws1in*sqrtT( theta)*divby( delta)*divby(WcMap);
    }
    else {
        C_Wc = s_T_Wc;
    }
    
    WcCalcin = WcMap * C_Wc * (1 + hpW);
//    if (prm->ConfigNPSS > 0.5) {/* In NPSS, turbine corrected values do not include standard day temp or pres. */		// 20230911-, liukai
//        Wcin  =  WIn*sqrtT(ptheta)*divby(pdelta);
//        Wcs1in=  Ws1in*sqrtT(ptheta)*divby(pdelta);
//    }
//    else {
       Wcin   =  WIn*sqrtT( theta)*divby( delta);
       Wcs1in =  Ws1in*sqrtT( theta)*divby( delta);
//    }

	/*-- Compute Turbine Efficiency (from Turbine map)  --------*/
	//EffMap = interp2Ac(prm->X_T_PRVec,prm->Y_T_NcVec,prm->T_T_Map_EffArray,PRmapRead,NcMap,prm->B,prm->A,&interpErr);   //20221116-
	//EffMap = interp2Ac(prm->X_T_betaVec,prm->Y_T_NcVec,prm->T_T_Map_EffArray,betaRead,NcMap,prm->B,prm->A,&interpErr);  //20221116+   //20221202-
	EffMap = interp2Ac(prm->Y_T_NcVec, prm->X_T_betaVec, prm->T_T_Map_EffArray, NcMap, betaRead, prm->A, prm->B, &interpErr);    //20221116+   //20221202+
	if ((prm->EffMapCol != prm->B || prm->EffMapRw != prm->A) && *(prm->IWork + Er5) == 0) {
		#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating EffMap. Table size does not match axis vector lengths.\n", prm->BlkNm);
		#endif
		*(prm->IWork + Er5) = 1;
	}
	else if (interpErr == 1 && *(prm->IWork + Er5) == 0) {
		#ifdef MATLAB_MEX_FILE
		printf("Warning in %s, Error calculating EffMap. Vector definitions may need to be expanded.\n", prm->BlkNm);
		#endif
		*(prm->IWork + Er5) = 1;
	}
	if (prm->IDes < 0.5)
		C_Eff = prm->EffDes*divby(EffMap);
	else
		C_Eff = s_T_Eff;

	Eff = EffMap * C_Eff * (1 + hpEf);

	/*-Compute power output only takes into account cooling flow that enters at front of engine (stage 1)-*/

	//Pwrout = ((hts1in - htIdealout)*Eff)*Ws1in * C_BTU_PER_SECtoHP;  //20221209- hp
	//Pwrout = ((hts1in - htIdealout)*Eff)*Ws1in;  //20221209- J/s		// 20230823- liukai
	if ((hts1in - htIdealout) > 0)		// 20230823+ liukai
		Pwrout = ((hts1in - htIdealout)*Eff)*Ws1in;  //20221209- J/s
	else
		Pwrout = (fabs(hts1in - htIdealout)*Eff)*Ws1in;  //20221209- J/s

	hts2out = (htIdealout - hts1in)*Eff + hts1in;			// liukai
	Tts2out = h2tc(hts2out, FARs1in);				// liukai

	/* ---- enthalpy output ----*/
    
    //htOut = ((((htIdealout - hts1in)*Eff) + hts1in)*Ws1in + dHcoolout)*divby(WOut);	// 20230816- liukai
	if (WOut > 0)		// 20230816+ liukai
	{
		htOut = ((((htIdealout - hts1in)*Eff) + hts1in)*Ws1in + dHcoolout)*divby(WOut);
/*/		PtOut = (Pts2out*Ws1in + dPtcoolout)*divby(WOut);		// 20230913+, liukai, ACE
		double massbound = .1;
		if (Ws1in > massbound)									// 20241128-, liukai, SHT
			PtOut = (Pts2out*Ws1in + dPtcoolout)*divby(WOut);		// 20230913+, liukai, ACE
		else
			PtOut = Pts1in;/*/
		PtOut = Pts2out;			// liukai,  -, ACE-VD, 222PT
	}
	else
	{
		PtOut = Pts1in;
		htOut = hts1in;
	}
    
    /*------ Compute Temperature output (empirical) ---------*/
    
    TtOut = h2tc(htOut,FARcOut);
    
    /*----- Compute output Torque to shaft ----*/
    //TorqueOut = C_HP_PER_RPMtoFT_LBF * Pwrout*divby(Nmech);  //20221209- 1bf*ft
	/* 常规入口逐值复现原2 rpm分支；起停入口才启用连续近零公式。 */
	TorqueOut = shtStartStopPowerToTorque(Pwrout, Nmech, 2.0);
	//if (WIn < 0.01)
	//	TorqueOut = 0;
    
    /* ----- Compute Normalized Flow Error ----- */
    if (prm->IDes < 0.5 && prm->NDes == 0)
        NErrorOut = 100;
    else if (prm->IDes < 0.5)
        NErrorOut = (Nmech - prm->NDes)*divby(prm->NDes);
 /*   else if (Ws1in == 0) {		// 20230815- liukai for startup
		//NErrorOut = 100;		// 20230815- liukai for startup
		NErrorOut = 0;		// 20230815+ liukai for startup
    }*/
    else {
    //    if (prm->ConfigNPSS > 0.5){		// 20230911-, liukai
            /* map contains turbine input flow only */
    //        NErrorOut = (Wcin-WcCalcin)*divby(Wcin);
    //    }
    //    else {
            /* map contains turbine input flow and input bleed flow */
            //NErrorOut = (Wcs1in-WcCalcin)*divby(Wcs1in);		// 20230816- liukai
			if (Wcs1in > 1)		// 20230816+ liukai
			{
				NErrorOut = (Wcs1in - WcCalcin)*divby(Wcs1in);
			}
			else
			{
				NErrorOut = (Wcs1in - WcCalcin)*divby(1);
			}
    //    }
    }
//    Test = PRmapRead;
	VIS = 1.5105e-6*powT(TtOut, 1.5) / (TtOut + 120);
	Re = WIn * Cmean * divby(Amean*VIS);
    /*------Assign output values------------        */
    y[0] = WOut;            /* Outlet Total Flow [pps]   */             //20221209+ kg/s
    y[1] = htOut;           /* Outlet Enthalpy [BTU/lbm]*/              //20221209+ J/kg
    y[2] = TtOut;           /* Outlet Temperature [degR]      */        //20221209+ K
    y[3] = PtOut;           /* Outlet Pressure  [psia]     */           //20221209+ N/m2 Or Pa
    y[4] = FARcOut;         /* Outlet Fuel to Air Ratio [NA]	*/
    y[5] = TorqueOut;       /* Torque Output [lbf*ft]       */          //20221209+ N*m
    y[6] = NErrorOut;       /* Normalized turbine Error [frac]*/
    y[7] = C_Nc;            /* Corrected Shaft Speed Scalar */
    y[8] = C_Wc;            /* Corrected Flow Scalar */
    y[9] = C_PR_EDc;            /* Pressure Ratio Scalar */
    y[10] = C_Eff;          /* Efficiency Scalar */
    y[11] = Wcin;           /* Corrected input flow [pps] */            //20221209+ kg/s
    y[12] = Wcs1in;         /* Station 1 corrected input flow [pps] */  //20221209+ kg/s
    y[13] = Nc;             /* Corrected speed [rpm]*/
    y[14] = NcMap;          /* Map corrected speed */
    y[15] = WcMap;          /* Map corrected flow */
    y[16] = betaRead;       /* Map beta */
    y[17] = EffMap;         /* Map efficiency */
    y[18] = Pwrout;         /* Output power [hp]*/                      //20221209+ J/s
    y[19] = Eff;
	y[20] = Ws1in;
	y[21] = Tts1in;
	y[22] = Pts1in;
	y[23] = Re;
	y[24] = EED;
}
