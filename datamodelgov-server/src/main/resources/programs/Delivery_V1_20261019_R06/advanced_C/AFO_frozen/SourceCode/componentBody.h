#ifndef COMPONENTBODY_H
#define COMPONENTBODY_H

//------------------------------------------------------------------------------
void Turbine_TMATS_body(double* y, const double* u, const double* CoolFlow, const TurbineStruct* prm);
void Burner_TMATS_body(double* y, const double* u, const BurnStruct* prm);
void Nozzle_TMATS_body(double* y, const double* u, const NozzleStruct* prm);
void Compressor_TMATS_body(double* y, double* y1, double* y2, const double* u, const double* Wcust, const double* FracWbld, const CompressorStruct* prm);
void CompressorF_TMATS_body(double* y, double* y1, double* y2, const double* u, const double* Wcust, const double* FracWbld, const CompressorStruct* prm);
void Mixer_TMATS_body(double* y, const double* u, const MixerStruct* prm);
void Ambient_TMATS_body(double *y, const double *u, const AmbientStruct* prm);
void FVABI_GTESS_body(double *y, const double *u);
//------------------------------------------------------------------------------
#endif  /* COMPONENTBODY_H */
