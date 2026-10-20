#ifndef NEWTONSOLVER_H
#define NEWTONSOLVER_H

//------------------------------------------------------------------------------
int newtonSolver(int functionModel(double *varIn,double *errOut,int dime),
                 int dime,
                 double *varStart,double *varMin,double *varMax,double *varDelLim,
                 double accuracyReq,
                 double distuFactor,
                 int maxIterations);
//------------------------------------------------------------------------------
#endif  /* NEWTONSOLVER_H */
