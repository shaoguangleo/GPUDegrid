PRECISION ?= double

all:  degrid

degrid: degrid.cu cucommon.cuh degrid_gpu.cuh degrid_gpu.o
	nvcc -arch=sm_35 -std=c++11 -DPRECISION=${PRECISION} -o degrid degrid.cu degrid_gpu.o

degrid_gpu.o: degrid_gpu.cu degrid_gpu.cuh cucommon.cuh
	nvcc -c -arch=sm_35 -std=c++11 -o degrid_gpu.o degrid_gpu.cu

degrid-debug: degrid.cu degrid_gpu-debug.o cucommon.cuh
	nvcc -arch=sm_35 -std=c++11 -DPRECISION=${PRECISION} -g -G -lineinfo -o degrid-debug degrid_gpu-debug.o degrid.cu

degrid_gpu-debug.o: degrid_gpu.cu degrid_gpu.cuh cucommon.cuh
	nvcc -c -arch=sm_35 -std=c++11 -g -G -lineinfo -o degrid_gpu-debug.o degrid_gpu.cu

