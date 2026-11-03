#ifndef TMATS_FUNCTIONS_H
#define TMATS_FUNCTIONS_H

/*		T-MATS -- functions.h
 * % *************************************************************************
 * % written by Jeffryes Chapman
 * % NASA Glenn Research Center, Cleveland, OH
 * % August 2nd, 2016
 * %
 * %  This is a file that contains various functions for use in the T-MATS C-code
 * % *************************************************************************/

/* functions_TMATS.c */
extern double sqrtT(double A);
extern double divby(double B);
extern double powT(double A, double N);

/* t2hc_TMATS.c */
extern double t2hc(double a, double b);
extern double t2hc_theta(double a, double b);
extern double t2gc(double a, double b);
/* h2tc_TMATS.c */
extern double h2tc(double c, double d);

/* pt2sc_TMATS.c */
extern double pt2sc(double aa, double ba, double ca);
/* sp2tc_TMATS.c */
extern double sp2tc(double da, double ea, double fa);

/* interp1Ac_TMATS.c */
extern double interp1Ac(double a1[], double b1[], double c1, int d1,int *error);
/* interp2Ac_TMATS.c */
extern double interp2Ac(double a2[], double b2[], double c2[], double d2, double e2,int f2, int g2, int *error);
/* interp3Ac_TMATS.c */
extern double interp3Ac(double a3[], double b3[], double c3[], double d3[], double e3, double f3, double g3,int h3, int i3, int j3, int *error);

/* PcalcStat_TMATS.c */
extern void PcalcStat(double A1,double B1,double C1,double D1,double E1,double F1,double *G1,double *H1,double *I1,double *J1,double *K1);

/* functions for PHY valve only */
/*------------------------------------------------- */
/* calc_Pstatic_TMATS.c */
extern void calcPs_GTESS(double W1In, double Pt1In, double Tt1In, double FARc1In, double Aphy1, double *Ps, double *MN, double *rhos, double *V, double *E);
extern void calcWvsMN1_GTESS(double Pt1In, double Tt1In, double FARc1In, double Aphy1, double *WInMN1, double *PsMN1, double *rhosMN1, double *VMN1, double *EMN1);
/*-----------------------------------------------*/


extern double Rcalc(double fa);
extern double t2gc(double T, double fa);

#endif  /* TMATS_FUNCTIONS_H */
