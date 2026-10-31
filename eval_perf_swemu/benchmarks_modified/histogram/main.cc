#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include "common.h"

#define KERNEL_NAME "histogram"

#define CL_CHECK(_expr)                                                \
   do {                                                                \
     cl_int _err = _expr;                                              \
     if (_err == CL_SUCCESS)                                           \
       break;                                                          \
     printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);   \
     cleanup();                                                        \
     exit(-1);                                                         \
   } while (0)

#define CL_CHECK2(_expr)                                               \
   ({                                                                  \
     cl_int _err = CL_INVALID_VALUE;                                   \
     decltype(_expr) _ret = _expr;                                     \
     if (_err != CL_SUCCESS) {                                         \
       printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
       cleanup();                                                      \
       exit(-1);                                                       \
     }                                                                 \
     _ret;                                                             \
   })

static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
    return -1;
  FILE* fp = fopen(filename, "r");
  if (NULL == fp) {
    fprintf(stderr, "Failed to load kernel.");
    return -1;
  }
  fseek(fp, 0, SEEK_END);
  long fsize = ftell(fp);
  rewind(fp);
  *data = (uint8_t*)malloc(fsize);
  *size = fread(*data, 1, fsize, fp);
  fclose(fp);
  return 0;
}

static void histogram_cpu(unsigned int *bins, const unsigned int *input, int n) {
  memset(bins, 0, NUM_BINS * sizeof(unsigned int));
  for (int i = 0; i < n; ++i) {
    bins[input[i] % NUM_BINS]++;
  }
}

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem input_memobj = NULL;
cl_mem bins_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (input_memobj) clReleaseMemObject(input_memobj);
  if (bins_memobj) clReleaseMemObject(bins_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}

uint32_t size = 1024;

static void show_usage() {
  printf("Usage: [-n size] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:h")) != -1) {
    switch (c) {
    case 'n':
      size = atoi(optarg);
      break;
    case 'h':
      show_usage();
      exit(0);
      break;
    default:
      show_usage();
      exit(-1);
    }
  }
  printf("Workload size=%d, bins=%d\n", size, NUM_BINS);
}

int main(int argc, char **argv) {
  parse_args(argc, argv);

  cl_platform_id platform_id;
  size_t kernel_size;

  CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
  CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

  printf("Create context\n");
  context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL, &_err));

  printf("Allocate device buffers\n");
  size_t input_bytes = size * sizeof(unsigned int);
  size_t bins_bytes = NUM_BINS * sizeof(unsigned int);
  input_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, input_bytes, NULL, &_err));
  bins_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_WRITE, bins_bytes, NULL, &_err));

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));
  // Inject kernel defines from VORTEX_KERNEL_DEFINES env var
  const char* kernel_defs = getenv("VORTEX_KERNEL_DEFINES");
  CL_CHECK(clBuildProgram(program, 1, &device_id, (kernel_defs && kernel_defs[0]) ? kernel_defs : NULL, NULL, NULL));
  // GPU_and_PNM (Oct 28, as vortex/tests/opencl 67a22f0): PoCL builds the kernel with in-process clang, whose LLVM support
  // library calls srand() with a time-based seed, so the rand() input data below changed on every run. Restore the C
  // default seed (1) after the build.
  srand(1);

  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&input_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&bins_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_uint), (void *)&size));

  // Generate input data
  std::vector<unsigned int> h_input(size);
  std::vector<unsigned int> h_bins(NUM_BINS, 0);
  for (uint32_t i = 0; i < size; ++i) {
    h_input[i] = rand();
  }

  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, input_memobj, CL_TRUE, 0, input_bytes, h_input.data(), 0, NULL, NULL));
  // Zero out bins on device
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, bins_memobj, CL_TRUE, 0, bins_bytes, h_bins.data(), 0, NULL, NULL));

  printf("Execute the kernel\n");
  size_t global_work_size[1] = {NUM_BINS};
  size_t local_work_size[1] = {1};
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, bins_memobj, CL_TRUE, 0, bins_bytes, h_bins.data(), 0, NULL, NULL));

  printf("Verify result\n");
  std::vector<unsigned int> h_ref(NUM_BINS);
  histogram_cpu(h_ref.data(), h_input.data(), size);
  int errors = 0;
  for (int i = 0; i < NUM_BINS; ++i) {
    if (h_bins[i] != h_ref[i]) {
      if (errors < 100) {
        printf("*** error: bin[%d] expected=%u, actual=%u\n", i, h_ref[i], h_bins[i]);
      }
      ++errors;
    }
  }
  if (0 == errors) {
    printf("PASSED!\n");
  } else {
    printf("FAILED! - %d errors\n", errors);
  }

  cleanup();
  return errors;
}
