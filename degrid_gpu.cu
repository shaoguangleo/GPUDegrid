#include "Defines.h"
#include "cucommon.cuh"
#include <iostream>

void CUDA_CHECK_ERR(unsigned lineNumber, const char* fileName) {

   cudaError_t err = cudaGetLastError();
   if (err) std::cout << "Error " << err << " on line " << lineNumber << " of " << fileName << ": " << cudaGetErrorString(err) << std::endl;
}

float getElapsed(cudaEvent_t start, cudaEvent_t stop) {
   float elapsed;
   cudaEventRecord(stop);
   cudaEventSynchronize(stop);
   cudaEventElapsedTime(&elapsed, start, stop);
   return elapsed;
}
__device__ int2 convert(int asize, int Qpx, float pin) {

   float frac; float round;
   //TODO add the 1 afterward?
   frac = modf((pin+1)*asize, &round);
   return make_int2(int(round), int(frac*Qpx));
}

__device__ double atomicAdd(double* address, double val)
{
    unsigned long long int* address_as_ull =
                             (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;
    do {
        assumed = old;
        old = atomicCAS(address_as_ull, assumed,
                        __double_as_longlong(val +
                                             __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
}

__device__ double make_zero(double2* in) { return (double)0.0;}
__device__ float make_zero(float2* in) { return (float)0.0;}

template <int gcf_dim, class CmplxType>
__global__ void 
//__launch_bounds__(256, 6)
degrid_kernel(CmplxType* out, CmplxType* in, size_t npts, CmplxType* img, 
                              size_t img_dim, CmplxType* gcf) {
   
   //TODO remove hard-coded 32
#ifdef __COMPUTE_GCF
   double T = gcf[0].x;
   double w = gcf[0].y;
#endif
   for (int n = 32*blockIdx.x; n<npts; n+= 32*gridDim.x) {
   for (int q=threadIdx.y;q<32;q+=blockDim.y) {
      CmplxType inn = in[n+q];
      int sub_x = floorf(GCF_GRID*(inn.x-floorf(inn.x)));
      int sub_y = floorf(GCF_GRID*(inn.y-floorf(inn.y)));
      int main_x = floorf(inn.x); 
      int main_y = floorf(inn.y); 
      auto sum_r = make_zero(img);
      auto sum_i = make_zero(img);
      for(int a = threadIdx.x-gcf_dim/2;a<gcf_dim/2;a+=blockDim.x)
      for(int b = -gcf_dim/2;b<gcf_dim/2;b++)
      {
         //auto this_img = img[main_x+a+img_dim*(main_y+b)]; 
         //auto r1 = this_img.x;
         //auto i1 = this_img.y;
         auto r1 = img[main_x+a+img_dim*(main_y+b)].x; 
         auto i1 = img[main_x+a+img_dim*(main_y+b)].y; 
         if (main_x+a < 0 || main_y+b < 0 || 
             main_x+a >= IMG_SIZE  || main_y+b >= IMG_SIZE) {
            r1=i1=0.0;
         }
         //auto this_gcf = __ldg(&gcf[gcf_dim*gcf_dim*(GCF_GRID*sub_y+sub_x) + 
         //               gcf_dim*b+a]);
         //auto r2 = this_gcf.x;
         //auto i2 = this_gcf.y;
#ifdef __COMPUTE_GCF
         double phase = 2*3.1415926*w*(1-T*sqrt((main_x-inn.x)*(main_x-inn.x)+(main_y-inn.y)*(main_y-inn.y)));
         double r2 = sin(phase);
         double i2 = cos(phase);
#else
         auto r2 = __ldg(&gcf[gcf_dim*gcf_dim*(GCF_GRID*sub_y+sub_x) + 
                        gcf_dim*b+a].x);
         auto i2 = __ldg(&gcf[gcf_dim*gcf_dim*(GCF_GRID*sub_y+sub_x) + 
                        gcf_dim*b+a].y);
#endif
         sum_r += r1*r2 - i1*i2; 
         sum_i += r1*i2 + r2*i1;
      }

      for(int s = blockDim.x < 16 ? blockDim.x : 16; s>0;s/=2) {
         sum_r += __shfl_down(sum_r,s);
         sum_i += __shfl_down(sum_i,s);
      }
      CmplxType tmp;
      tmp.x = sum_r;
      tmp.y = sum_i;
      if (threadIdx.x == 0) {
         out[n+q] = tmp;
      }
   }
   }
}
__device__ void warp_reduce(double &in, int sz = 16) {
   if (16<sz) sz=16;
   for(int s = sz; s>0;s/=2) {
      in += __shfl_down(in,s);
   }
}
__device__ void warp_reduce(float &in, int sz = 16) {
   if (16<sz) sz=16;
   for(int s = sz; s>0;s/=2) {
      in += __shfl_down(in,s);
   }
}
__device__ void warp_reduce2(float &in, int sz = 32) {
   if (32<sz) sz=32;
   for(int s=1; s<sz; s*=2) {
      in += __shfl_down(in,s);
   } 
}
__device__ void warp_reduce2(double &in, int sz = 32) {
   if (32<sz) sz=32;
   for(int s=1; s<sz; s*=2) {
      in += __shfl_down(in,s);
   } 
}
template <class CmplxType>
__global__ void vis2ints(CmplxType *vis_in, int2* vis_out, int npts) {
   for (int q=threadIdx.x+blockIdx.x*blockDim.x; 
        q<npts; 
        q+=gridDim.x*blockDim.x) {
      CmplxType inn = vis_in[q];
      int main_y = floorf(inn.y); 
      int sub_y = floorf(GCF_GRID*(inn.y-main_y));
      int main_x = floorf(inn.x); 
      int sub_x = floorf(GCF_GRID*(inn.x-main_x));
      vis_out[q].x = main_x*GCF_GRID+sub_x;
      vis_out[q].y = main_y*GCF_GRID+sub_y;
   }
}
//Make sure visibilities are sorted by  main_x/blocksize then main_y/blocksize
// blockgrid should be img_dim/blocksize
__global__ void set_bookmarks(int2* vis_in, int npts, int blocksize, int blockgrid, int* bookmarks) {
   for (int q=threadIdx.x+blockIdx.x*blockDim.x;q<=npts;q+=gridDim.x*blockDim.x) {
      int2 this_vis = vis_in[q];
      int2 last_vis = vis_in[q-1];
      int main_x = this_vis.x/GCF_GRID/blocksize;
      int main_x_last = last_vis.x/GCF_GRID/blocksize;
      int main_y = this_vis.y/GCF_GRID/blocksize;
      int main_y_last = last_vis.y/GCF_GRID/blocksize;
      if (0==q) {
         main_y_last=0;
         main_x_last=-1;
      }
      if (npts==q) main_x = main_y = blockgrid;
      if (main_x != main_x_last || main_y != main_y_last)  { 
         for (int z=main_y_last*blockgrid+main_x_last+1;
                  z<=main_y*blockgrid+main_x; z++) {
            bookmarks[z] = q;
         }
      }
   }
}
template <int gcf_dim, class CmplxType>
__global__ void 
__launch_bounds__(1024, 1)
degrid_kernel2(CmplxType* out, int2* in, size_t npts, CmplxType* img, 
                              int img_dim, CmplxType* gcf, int* bookmarks) {
   
   CmplxType __shared__ shm[gcf_dim][gcf_dim/4];
   int2 __shared__ inbuff[32];
   int left = blockIdx.x*blockDim.x;
   int top = blockIdx.y*blockDim.y;
   int this_x = left+threadIdx.x;
   int this_y = top+threadIdx.y;
   auto r1 = img[this_x + img_dim * this_y].x;
   auto i1 = img[this_x + img_dim * this_y].y;
   auto sum_r = make_zero(img);
   auto sum_i = make_zero(img);
   int half_gcf = gcf_dim/2;
   
   int bm_x = left/half_gcf-1;
   int bm_y = top/half_gcf-1;
   for (int y=bm_y<0?0:bm_y;(y<bm_y+2+(blockDim.y+half_gcf-1)/half_gcf)&&(y<img_dim/half_gcf);y++) {
   for (int x=bm_x<0?0:bm_x;(x<bm_x+2+(blockDim.x+half_gcf-1)/half_gcf)&&(x<img_dim/half_gcf);x++) {
   for (int n=bookmarks[y*img_dim/half_gcf+x];
            n<bookmarks[y*img_dim/half_gcf+x+1]; n+=32) {
      if (threadIdx.x<32 && threadIdx.y==0) inbuff[threadIdx.x]=in[n+threadIdx.x];
      __syncthreads(); //1438
      
      //TODO remove
      //if (threadIdx.y==0 && threadIdx.x==22) shm[threadIdx.y][threadIdx.x].x = 4.44;
      shm[threadIdx.x][threadIdx.y].x = 0.00;
      shm[threadIdx.x][threadIdx.y].y = 0.00;
      //if (threadIdx.y==0 && threadIdx.x==22) shm[threadIdx.y][threadIdx.x].x = 4.04;
   for (int q = 0; q<32 && n+q < bookmarks[y*img_dim/half_gcf+x+1]; q++) {
      int2 inn = inbuff[q];
      //TODO Don't floorf initially, just compare
      int main_y = inn.y/GCF_GRID;
      int b = this_y - main_y;
      //Skip the whole block?
      //if (top-main_y >= gcf_dim/2 || top-main_y+gcf_dim < -gcf_dim/2) continue;
      int main_x = inn.x/GCF_GRID;
      int a = this_x - main_x;
      //Skip the whole block?
      //if (left-main_x >= gcf_dim/2 || left-main_x+gcf_dim < -gcf_dim/2) continue;
      if (a >= half_gcf || a < -half_gcf ||
          b >= half_gcf || b < -half_gcf) {
         sum_r = 0.00;
         sum_i = 0.00;
      } else {
         int sub_x = inn.x%GCF_GRID;
         int sub_y = inn.y%GCF_GRID;
         auto r2 = __ldg(&gcf[gcf_dim*gcf_dim*(GCF_GRID*sub_y+sub_x) + 
                        gcf_dim*b+a].x);
         auto i2 = __ldg(&gcf[gcf_dim*gcf_dim*(GCF_GRID*sub_y+sub_x) + 
                        gcf_dim*b+a].y);
         //TODO remove
         //if (a!=0 || b!=0) {
         //   sum_r = sum_i = 0;
         //} else {
         //sum_r = (n+q)*1.0;//r2;
         //sum_i = (n+q)*1.0;//i2;
         //}
         //TODO restore
         sum_r = r1*r2 - i1*i2; 
         sum_i = r1*i2 + r2*i1;
      }

     //reduce in two directions
      //WARNING: Adjustments must be made if blockDim.y and blockDim.x are no
      //         powers of 2 
      //Reduce using shuffle first
#if 1
      warp_reduce2(sum_r);
      warp_reduce2(sum_i);
      int stripe_width_x = blockDim.x/32; //number of rows in shared memory that 
                                          //contain data for a single visibility
      int n_stripe = blockDim.y/stripe_width_x; //the number of stripes that fit
      if (0 == threadIdx.x%32) {
         shm[threadIdx.x/32+stripe_width_x*(q%n_stripe)][threadIdx.y].x = sum_r;
         shm[threadIdx.x/32+stripe_width_x*(q%n_stripe)][threadIdx.y].y = sum_i;
      }
      //Once we've accumulated a full set, or this is the last q, reduce more
      if (q+1==n_stripe || q==31 || n+q == bookmarks[y*img_dim/half_gcf+x+1]-1) {
         int stripe_width_y = blockDim.y/32;
         if (stripe_width_y < 1) stripe_width_y=1;
         __syncthreads(); 
         if (threadIdx.y<(q+1)*stripe_width_x) {
            sum_r = shm[threadIdx.y][threadIdx.x].x;
            sum_i = shm[threadIdx.y][threadIdx.x].y;
            warp_reduce2(sum_r, blockDim.y<32 ? blockDim.y:32);
            warp_reduce2(sum_i, blockDim.y<32 ? blockDim.y:32);
            if (0 == threadIdx.x%32) {
               shm[0][threadIdx.y*stripe_width_y + (threadIdx.x/32)].x = sum_r;
               shm[0][threadIdx.y*stripe_width_y + (threadIdx.x/32)].y = sum_i;
            }
         }
         __syncthreads(); 
         //Warning: trouble if gcf_dim > sqrt(32*32*32) = 128
         int idx = threadIdx.x + threadIdx.y*blockDim.x;
         if (idx < stripe_width_x*stripe_width_y*(q+1)) {
            sum_r = shm[0][idx].x;
            sum_i = shm[0][idx].y;
            warp_reduce2(sum_r, stripe_width_x*stripe_width_y);
            warp_reduce2(sum_i, stripe_width_x*stripe_width_y);
            if (0 == idx%(stripe_width_x*stripe_width_y)) {
               atomicAdd(&(out[n+idx/(stripe_width_x*stripe_width_y)].x),sum_r);
               atomicAdd(&(out[n+idx/(stripe_width_x*stripe_width_y)].y),sum_i);
            }
         }
      }
      
#else
      
      shm[threadIdx.y][threadIdx.x].x = sum_r;
      shm[threadIdx.y][threadIdx.x].y = sum_i;
      __syncthreads();
      //Reduce in y
      for(int s = blockDim.y/2;s>0;s/=2) {
         if (threadIdx.y < s) {
           shm[threadIdx.y][threadIdx.x].x += shm[threadIdx.y+s][threadIdx.x].x;
           shm[threadIdx.y][threadIdx.x].y += shm[threadIdx.y+s][threadIdx.x].y;
         }
         __syncthreads();
      }

      //Reduce the top row
      for(int s = blockDim.x/2;s>16;s/=2) {
         if (0 == threadIdx.y && threadIdx.x < s) 
                    shm[0][threadIdx.x].x += shm[0][threadIdx.x+s].x;
         if (0 == threadIdx.y && threadIdx.x < s) 
                    shm[0][threadIdx.x].y += shm[0][threadIdx.x+s].y;
         __syncthreads();
      }
      if (threadIdx.y == 0) {
         //Reduce the final warp using shuffle
         CmplxType tmp = shm[0][threadIdx.x];
         for(int s = blockDim.x < 16 ? blockDim.x : 16; s>0;s/=2) {
            tmp.x += __shfl_down(tmp.x,s);
            tmp.y += __shfl_down(tmp.y,s);
         }
         if (threadIdx.x == 0) {
            atomicAdd(&(out[n+q].x),tmp.x);
            atomicAdd(&(out[n+q].y),tmp.y);
         }
      }
#endif
   }
   } //n
   } //x
   } //y
}

template <class CmplxType>
void degridGPU(CmplxType* out, CmplxType* in, size_t npts, CmplxType *img, size_t img_dim, 
               CmplxType *gcf, size_t gcf_dim) {
//degrid on the GPU
//  out (out) - the output values for each location
//  in  (in)  - the locations to be interpolated 
//  npts (in) - number of locations
//  img (in) - the image
//  img_dim (in) - dimension of the image
//  gcf (in) - the gridding convolution function
//  gcf_dim (in) - dimension of the GCF

   CmplxType *d_out, *d_in, *d_img, *d_gcf;

   cudaEvent_t start, stop;
   cudaEventCreate(&start); cudaEventCreate(&stop);

   CUDA_CHECK_ERR(__LINE__,__FILE__);
#ifdef __MANAGED
   d_img = img;
   d_gcf = gcf;
   d_out = out;
   d_in = in;
   std::cout << "img size = " << (img_dim*img_dim+2*img_dim*gcf_dim+2*gcf_dim)*
                                                                 sizeof(CmplxType) << std::endl;
   std::cout << "out size = " << sizeof(CmplxType)*npts << std::endl;
#else
   //img is padded to avoid overruns. Subtract to find the real head
   img -= img_dim*gcf_dim+gcf_dim;

   //Pin CPU memory
   cudaHostRegister(img, sizeof(CmplxType)*(img_dim*img_dim+2*img_dim*gcf_dim+2*gcf_dim), cudaHostRegisterMapped);
   cudaHostRegister(gcf, sizeof(CmplxType)*64*gcf_dim*gcf_dim, cudaHostRegisterMapped);
   cudaHostRegister(out, sizeof(CmplxType)*npts, cudaHostRegisterMapped);
   cudaHostRegister(in, sizeof(CmplxType)*npts, cudaHostRegisterMapped);

   //Allocate GPU memory
   std::cout << "img size = " << (img_dim*img_dim+2*img_dim*gcf_dim+2*gcf_dim)*
                                                                 sizeof(CmplxType) << std::endl;
   cudaMalloc(&d_img, sizeof(CmplxType)*(img_dim*img_dim+2*img_dim*gcf_dim+2*gcf_dim));
   cudaMalloc(&d_gcf, sizeof(CmplxType)*64*gcf_dim*gcf_dim);
   cudaMalloc(&d_out, sizeof(CmplxType)*npts);
   cudaMalloc(&d_in, sizeof(CmplxType)*npts);
   std::cout << "out size = " << sizeof(CmplxType)*npts << std::endl;
   CUDA_CHECK_ERR(__LINE__,__FILE__);

   //Copy in img, gcf and out
   cudaEventRecord(start);
   cudaMemcpy(d_img, img, 
              sizeof(CmplxType)*(img_dim*img_dim+2*img_dim*gcf_dim+2*gcf_dim), 
              cudaMemcpyHostToDevice);
   cudaMemcpy(d_gcf, gcf, sizeof(CmplxType)*64*gcf_dim*gcf_dim, 
              cudaMemcpyHostToDevice);
   cudaMemcpy(d_in, in, sizeof(CmplxType)*npts,
              cudaMemcpyHostToDevice);
   CUDA_CHECK_ERR(__LINE__,__FILE__);
   std::cout << "memcpy time: " << getElapsed(start, stop) << std::endl;

   //move d_img and d_gcf to remove padding
   d_img += img_dim*gcf_dim+gcf_dim;
#endif
   //offset gcf to point to the middle of the first GCF for cleaner code later
   d_gcf += gcf_dim*(gcf_dim+1)/2;

#ifdef __SCATTER
   int2* in_ints;
   int* bookmarks;
   cudaMalloc(&in_ints, sizeof(int2)*npts);
   cudaMalloc(&bookmarks, sizeof(int)*((img_dim/gcf_dim)*(img_dim/gcf_dim)*4+1));
   vis2ints<<<4,256>>>(d_in, in_ints, npts);
   CUDA_CHECK_ERR(__LINE__,__FILE__);
   set_bookmarks<<<4,256>>>(in_ints, npts, gcf_dim/2, img_dim/gcf_dim*2, 
                               bookmarks);
   CUDA_CHECK_ERR(__LINE__,__FILE__);
   
   
   cudaMemset(d_out, 0, sizeof(CmplxType)*npts);
   cudaEventRecord(start);
   degrid_kernel2<GCF_DIM>
            <<<dim3((img_dim+gcf_dim-1)/gcf_dim, (img_dim+gcf_dim/4-1)/(gcf_dim/4)),
               dim3(gcf_dim, gcf_dim/4)>>>
                             (d_out,in_ints,npts,d_img,img_dim,d_gcf,bookmarks); 
#else
   cudaEventRecord(start);
   degrid_kernel<GCF_DIM>
               <<<npts/32,dim3(32,8)>>>(d_out,d_in,npts,d_img,img_dim,d_gcf); 
#endif
   float kernel_time = getElapsed(start,stop);
   std::cout << "Processed " << npts << " complex points in " << kernel_time << " ms." << std::endl;
   std::cout << npts / 1000000.0 / kernel_time * gcf_dim * gcf_dim * 8 << "Gflops" << std::endl;
   CUDA_CHECK_ERR(__LINE__,__FILE__);

#ifdef __MANAGED
   cudaDeviceSynchronize();
#else
   cudaMemcpy(out, d_out, sizeof(CmplxType)*npts, cudaMemcpyDeviceToHost);
   CUDA_CHECK_ERR(__LINE__,__FILE__);

   //Unpin CPU memory
   cudaHostUnregister(img);
   cudaHostUnregister(gcf);
   cudaHostUnregister(out);
   cudaHostUnregister(in);

   //Restore d_img and d_gcf for deallocation
   d_img -= img_dim*gcf_dim+gcf_dim;
   d_gcf -= gcf_dim*(gcf_dim+1)/2;
   cudaFree(d_out);
   cudaFree(d_img);
#ifdef __SCATTER
   cudaFree(in_ints);
   cudaFree(bookmarks);
#endif
#endif
   cudaEventDestroy(start); cudaEventDestroy(stop);
   CUDA_CHECK_ERR(__LINE__,__FILE__);
}
template void degridGPU<double2>(double2* out, double2* in, size_t npts, double2 *img, 
                                 size_t img_dim, double2 *gcf, size_t gcf_dim); 
template void degridGPU<float2>(float2* out, float2* in, size_t npts, float2 *img, 
                                size_t img_dim, float2 *gcf, size_t gcf_dim); 
