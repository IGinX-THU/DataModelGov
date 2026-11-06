/*
 * Body of calculations for Burner_TMATS S-function
 */

#include "types_TMATS.h"
#include "functions_TMATS.h"
#include <math.h>			// liukai +

/* For clarity: */
//20221116-
//#define WfIn   (u[0])     /* Input Fuel Flow[pps] */
//#define WIn    (u[1])     /* Input Flow [pps] */
//#define htIn   (u[2])     /* Input enthalpy [BTU/lbm] */
//#define TtIn   (u[3])     /* Temperature Input [degR] */
//#define PtIn   (u[4])     /* Pressure Input [psia] */
//#define FARcIn (u[5])     /* Combusted Fuel to Air Ratio [frac] */
//20221116-

extern double t2hc(double a, double b);
extern double h2tc(double c, double d);
extern double t2hc_theta(double a, double b);

void Burner_TMATS_body(double* y, const double* u, const BurnStruct* prm)
{
    //20221116+
	double hpWf       = u[6];
	double hpEf		  = u[7];
	double hpdP_Loss  = u[8];
    double WfIn       = u[0] * (1 + hpWf);    /* Input Fuel Flow[pps] */   //20221209+ kg/s
    double WIn        = u[1];    /* Input Flow [pps] */                   //20221209+ kg/s
    double htIn       = u[2];    /* Input enthalpy [BTU/lbm] */           //20221209+ J/kg
    double TtIn       = u[3];    /* Temperature Input [degR] */           //20221209+ K
    double PtIn       = u[4];    /* Pressure Input [psia] */              //20221209+ N/m2 Or Pa
    double FARcIn     = u[5];    /* Combusted Fuel to Air Ratio [frac] */
    //20221116+

    /* Define constants */
    double htin;
    double htOut, TtOut, PtOut, FARcOut, WOut;
    double Test, FAR1, FAR2, FAR3, FARg, TtOutg, htOutg, err, erthr, TtOutg_new, TtOutg_old, err_old;
	int iter, maxiter;
	double TtOut1;
    

     /*-- Compute Input enthalpy (empirical) --------*/
    
    htin = t2hc(TtIn,FARcIn);
    
    /*-- Compute Flow output  --------*/
    
    WOut = WIn + WfIn;     /*Perfect combustion*/
    
    /*-- Compute Input fuel to air ratio --*/
	if (WIn > 0)
		FARcOut = (WIn* FARcIn/(1+FARcIn) + WfIn)*divby(WIn/(1+FARcIn));
	else
		FARcOut = 0;
    
    /*------ Compute enthalpy output ---------*/
    if (prm->LHVEn < 0.5)
        htOut = (WIn*htin + WfIn*prm->hFuel)*divby(WOut);
    else
	{
        //htOut = (WIn*htin + WfIn*prm->LHV*prm->Eff*(1+hpEf))*divby(WOut);		// 20230815- liukai 
		if (WfIn > 0)			// 20230815+ liukai
		{
			htOut = (WIn*htin + WfIn * prm->LHV*prm->Eff*(1 + hpEf))*divby(WOut);
		}
		else
		{
			htOut = htin;
		}
	}
    
    /*------ Compute Temperature output ---------*/
    
    TtOut = h2tc(htOut,FARcOut);
	TtOut1 = TtOut;
    
    /*------ Compute pressure output ---------*/
    //PtOut = (1- prm->dPnormBurnerH) * PtIn;		// 20230816- liukai 
	if (WfIn < 1e-5)		// 20230815+ liukai
	{
	//	PtOut = (1 - prm->dPnormBurnerC) * PtIn;
		double massbound1 = 0.1;		// 20230816+ liukai
		double massbound2 = 0.2;		// 20230816+ liukai
		if (WIn > massbound2)
		{
			PtOut = (1 - prm->dPnormBurnerC) * PtIn;
		}
		else if (WIn < massbound1)
		{
			PtOut = PtIn;
		}
		else
		{
			double sigma = 0;
			sigma = (prm->dPnormBurnerC - 0) / (massbound2 - massbound1)*(WIn - massbound1) + 0;
			PtOut = (1 - sigma) * PtIn;
		}
	}
	else
	{
		PtOut = (1 - prm->dPnormBurnerH - hpdP_Loss) * PtIn;
	}

	// liukai +
	/*-------*/
	double qf4;
	TtOutg = TtOut - 100;

	qf4 = prm->LHV + t2hc(288.15, 0) - t2hc(TtOutg, 0) + t2hc_theta(288.15, 0) - t2hc_theta(TtOutg, 0);
	FARg = ( (1+FARcIn)*(t2hc(TtOutg, 0) - t2hc(TtIn, 0)) + FARcIn*(t2hc_theta(TtOutg,0)-t2hc_theta(TtIn,0)) ) / (qf4*prm->Eff*(1 + hpEf)) ;
	if (FARcOut < 1e-5)
		err = (FARcOut - FARcIn - FARg) / (1e-5);
	else
		err = (FARcOut - FARcIn - FARg) / fabs(FARcOut);

	maxiter = 200;		iter = 0;		erthr = 1e-10;
	TtOutg_new = TtOutg + 10;
	while (fabs(err) > erthr && iter < maxiter) {
		err_old = err;
		TtOutg_old = TtOutg;
		if (fabs(TtOutg - TtOutg_new) < 1e-5)
			TtOutg = TtOutg + 1e-3;
		else
			TtOutg = TtOutg_new;

		qf4 = prm->LHV + t2hc(288.15, 0) - t2hc(TtOutg, 0) + t2hc_theta(288.15, 0) - t2hc_theta(TtOutg, 0);
		FARg = ((1 + FARcIn)*(t2hc(TtOutg, 0) - t2hc(TtIn, 0)) + FARcIn * (t2hc_theta(TtOutg, 0) - t2hc_theta(TtIn, 0))) / (qf4*prm->Eff*(1 + hpEf)) ;
		if (FARcOut < 1e-5)
			err = (FARcOut - FARcIn - FARg) / 1e-5;
		else
			err = (FARcOut - FARcIn - FARg) / fabs(FARcOut);

		if (fabs(err) > erthr) {
			TtOutg_new = TtOutg - err * (TtOutg - TtOutg_old)*divby(err - err_old);
		}
		iter = iter + 1;
	}
	TtOut = TtOutg;
//	TtOut = (TtOutg + TtOut1) / 2;		// 20241128-, liukai
	htOut = t2hc(TtOut, FARcOut);
	/*-------*/
/*/	double H3, H4;
	double L0 = 14.76;
	TtOutg = TtOut - 10;

	H3 = t2hc_theta(TtIn, 0) + t2hc(TtIn, 0);
	H4 = t2hc_theta(TtOutg, 0) + t2hc(TtOutg, 0);
	FARg = ((t2hc(TtOutg, 0) - t2hc(TtIn, 0)) + FARcIn*(H4-H3)) / (prm->LHV*prm->Eff*(1 + hpEf) - H4 + t2hc(TtIn, 0));
	err = (FARcOut - FARcIn - FARg) / (FARcOut);

	maxiter = 200;		iter = 0;		erthr = 1e-10;
	TtOutg_new = TtOutg + 10;
	while (fabs(err) > erthr && iter < maxiter) {
		err_old = err;
		TtOutg_old = TtOutg;
		if (fabs(TtOutg - TtOutg_new) < 1e-5)
			TtOutg = TtOutg + 1e-3;
		else
			TtOutg = TtOutg_new;

		H4 = t2hc_theta(TtOutg, 0) + t2hc(TtOutg, 0);
		FARg = ((t2hc(TtOutg, 0) - t2hc(TtIn, 0)) + FARcIn * (H4 - H3)) / (prm->LHV*prm->Eff*(1 + hpEf) - H4 + t2hc(TtIn, 0));
		err = (FARcOut - FARcIn - FARg) / (FARcOut);

		if (fabs(err) > erthr) {
			TtOutg_new = TtOutg - err * (TtOutg - TtOutg_old)*divby(err - err_old);
		}
		iter = iter + 1;
	}
	TtOut = TtOutg;
	htOut = t2hc(TtOut, FARcOut);/*/
	


	if (WfIn < 1e-5)		// 20230815+ liukai
	{
		TtOut = TtIn;
	}

    
    Test = htin;
    
    /*------Assign output values------------*/
    y[0] = WOut;     /* Output Air Flow [pps]	*/                     //20221209+ kg/s
    y[1] = htOut; 	  /* Output Enthalpy [BTU/lbm] */              //20221209+ J/kg
    y[2] = TtOut;     /* Output Temperature  [degR]*/                  //20221209+ K
    y[3] = PtOut;     /* Output Pressure [psia]	*/                     //20221209+ N/m2 Or Pa
    y[4] = FARcOut;   /* Output Combusted Fuel to Air Ratio [frac] */
    y[5] = Test;      /* Output Test Point */
}
