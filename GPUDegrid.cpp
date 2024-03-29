#include <Python.h>
#include <stdio.h>
#include "degrid_gpu.cuh"

extern "C" {

typedef struct {
          double x; 
          double y;
} double2;
static PyObject* py_simpleAdd(PyObject* self, PyObject* args);
static PyObject* GPUDegrid_convdegrid(PyObject* self, PyObject* args);
void initGPUDegrid();

/*
 * Test Python extension
 */
static PyObject* py_simpleAdd(PyObject* self, PyObject* args)
{
  double x, y;
  PyArg_ParseTuple(args, "dd", &x, &y);
  return Py_BuildValue("d", x*y);
}
int extractFloatList(PyObject *list_in, double** p_array_out, int argnum) {

  //Checking input type
  if (!PyList_Check(list_in)) {
     char errmsg[37];
     sprintf(errmsg,"Argument %d must be a list of float\n", argnum);
     printf("Argument %d must be a list of float\n", argnum);
     fprintf(stderr, "%s", errmsg);fflush(0);
     PyErr_SetString(PyExc_TypeError, errmsg); 
     return -1;
  }
  if (!PyFloat_Check(PyList_GetItem(list_in,0))) {
     char errmsg[37];
     sprintf(errmsg,"Argument %d must be a list of float\n", argnum);
     printf("Argument %d must be a list of float\n", argnum);
     fprintf(stderr, "%s", errmsg);fflush(0);
     PyErr_SetString(PyExc_TypeError, errmsg); 
     return -1;
  }
  int list_size = PyList_Size(list_in);
  PyObject* iter = PyObject_GetIter(list_in);
  *p_array_out = (double*)malloc(sizeof(double)*list_size);
  double* array_out = *p_array_out; 
  int q;
  PyObject* item;
  for (q=0;q<PyList_Size(list_in);q++) {
     item = PyIter_Next(iter);
     array_out[q] = PyFloat_AsDouble(item);
  }
  return 0;
}
int extractComplexList(PyObject *list_in, double2** p_array_out, int argnum) {

  //Checking input type
  if (!PyList_Check(list_in)) {
     char errmsg[37];
     sprintf(errmsg,"Argument %d must be a list of complex\n", argnum);fflush(0);
     printf("Argument %d must be a list of complex\n", argnum);fflush(0);
     fprintf(stderr, "%s", errmsg);
     PyErr_SetString(PyExc_TypeError, errmsg); 
     return -1;
  }
  if (!PyComplex_Check(PyList_GetItem(list_in,0))) {
     char errmsg[37];
     sprintf(errmsg,"Argument %d must be a list of complex\n", argnum);fflush(0);
     printf("Argument %d must be a list of complex\n", argnum);fflush(0);
     fprintf(stderr, "%s", errmsg);
     PyErr_SetString(PyExc_TypeError, errmsg); 
     return -1;
  }

  int list_size = PyList_Size(list_in);
  PyObject* iter = PyObject_GetIter(list_in);
  *p_array_out = (double2*)malloc(sizeof(double2)*list_size);
  double2* array_out = *p_array_out; 
  int q;
  PyObject* item;
  for (q=0;q<PyList_Size(list_in);q++) {
     item = PyIter_Next(iter);
     array_out[q].x = PyComplex_RealAsDouble(item);
     array_out[q].y = PyComplex_ImagAsDouble(item);
  }
  return 0;
}
void makeComplexList(double2* array_in, int list_size, PyObject *list_out) {
  if (!PyList_Check(list_out)) fprintf(stderr,"makeComplexList must take "
                                              "a Python list\n");
  int q;
  for (q=0;q<list_size;q++) {
     PyList_Append(list_out, PyComplex_FromDoubles(array_in[q].x, array_in[q].y)); 
  }
}
static PyObject* GPUDegrid_convdegrid(PyObject* self, PyObject* args)
{
  int npts, img_size, Qpx, gcf_dim, q;
  PyObject *in, *img, *gcf, *out;
  if(!PyArg_ParseTuple(args, "OiOiOii", &in, &npts, &img, &img_size, 
                                    &gcf, &Qpx, &gcf_dim)) {
    PyErr_SetString(PyExc_TypeError, "Incorrect number or type of arguments to convdegrid.\n\n"
        "Usage: convdegrid(in, npts, img, img_size, gcf, Qpx, gcf_dim)\n"
        "    in: list of float\n"
        "    npts: integer\n"
        "    img: list of complex\n"
        "    img_size: integer\n"
        "    gcf: list of complex\n"
        "    Qpx: integer\n"
        "    gcf_dim: integer\n"
    );
    printf("Incorrect number or type of arguments to convdegrid.\n");
  }

  double2 *gcf_c, *img_c, *out_c;
  double *in_c;
  if (0 != extractComplexList(img, &img_c, 3)) return Py_BuildValue("");
  if (0 != extractFloatList(in, &in_c, 1)) return Py_BuildValue("");
  if (0 != extractComplexList(gcf, &gcf_c, 5)) return Py_BuildValue("");
  out_c = (double2*)malloc(sizeof(double2)*npts);
#if 1
  degridGPU(out_c, (double2*)in_c, npts, img_c, img_size, 
                gcf_c, gcf_dim, Qpx); 
#else
  for (q=0;q<npts;q++) {
     out_c[q].x = 2.0*in_c[2*q];
     out_c[q].y = 2.0*in_c[2*q+1];
  }
#endif

  out = PyList_New(0);
  makeComplexList(out_c, npts, out);

  return Py_BuildValue("O", out);
}

/*
 * Bind Python function names to our C functions
 */
static PyMethodDef GPUDegrid_methods[] = {
  {"simpleAdd", py_simpleAdd, METH_VARARGS, "Adds two doubles"},
  {"convdegrid", GPUDegrid_convdegrid, METH_VARARGS, "Degrid on the GPU"},
  {NULL, NULL}
};

/*
 * Python calls this to let us initialize our module
 */
void initGPUDegrid()
{
  (void) Py_InitModule("GPUDegrid", GPUDegrid_methods);
}
}

