#ifndef __DEGRID_CUH
#define __DEGRID_CUH
template <class CmplxType>
void degridGPU(CmplxType* out, CmplxType* in, int npts, CmplxType *img, int img_dim, 
               CmplxType *gcf, int gcf_dim, int gcf_grid); 
template <class CmplxType>
void degridCPU_tmp(CmplxType* out, CmplxType* in, int npts, CmplxType *img, int img_dim, 
               CmplxType *gcf, int gcf_dim, int gcf_grid); 
#endif

