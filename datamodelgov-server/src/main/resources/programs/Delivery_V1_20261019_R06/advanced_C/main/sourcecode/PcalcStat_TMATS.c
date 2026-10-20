/*		T-MATS -- PcalcStat_TMATS.c
% *************************************************************************
% written by Jeffryes Chapman based on work by T. Lavelle
% NASA Glenn Research Center, Cleveland, OH
% February 2nd, 2012
%
%  (S, Ts, hs, rho, V) = f(Pt, Ps, Tt, ht, FAR, Rt).
% *************************************************************************/

#include <math.h>
#include "constants_TMATS.h"
#include "functions_TMATS.h"

void PcalcStat(double Pt, double Ps, double Tt, double ht, double FAR, double Rt, double *S, double *Ts, double *hs, double *rhos, double *V)
{
            double Rs;

            /* Compute entropy */
            *S = pt2sc(Pt, Tt, FAR);
            /* Compute Static Temperature */
            *Ts = sp2tc(*S,Ps,FAR);
            if (*Ts > Tt) {
            //        *Ts = Tt;
            }
            /* Compute static enthalpy */
			ht = t2hc(Tt, FAR);
            *hs = t2hc(*Ts,FAR);
            if (*hs > ht) {
            //        *hs = ht;
            }
            /* Assume Rt = Rs */
            Rs = Rt;
            /* Compute static rho */
            //*rhos = Ps * C_PSItoPSF*divby(Rs* *Ts * JOULES_CONST);    //20221209- lbf/ft3
            *rhos = Ps * divby(Rs * *Ts);    //20221209+ kg/m3
            /* Compute Velocity */
            //*V = sqrtT(2 * (ht - *hs)*C_GRAVITY*JOULES_CONST);   //20221209-  ft/s
			if ((ht - *hs) >= 0)	// 20230820+ liukai
			{
				*V = sqrtT(2 * (ht - *hs));   //20221209+  m/s
			}
			else
			{
				*V = -sqrtT(2 * fabs(ht - *hs));
			}
}