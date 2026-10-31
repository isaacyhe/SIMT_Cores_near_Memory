#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include "common.h"

#define KERNEL_NAME "gather"

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

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem input_memobj = NULL;
cl_mem indices_memobj = NULL;
cl_mem output_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (input_memobj) clReleaseMemObject(input_memobj);
  if (indices_memobj) clReleaseMemObject(indices_memobj);
  if (output_memobj) clReleaseMemObject(output_memobj);
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
  printf("Workload size=%d\n", size);
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
  size_t data_bytes = size * sizeof(TYPE);
  size_t idx_bytes = size * sizeof(unsigned int);
  input_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, data_bytes, NULL, &_err));
  indices_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, idx_bytes, NULL, &_err));
  output_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, data_bytes, NULL, &_err));

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));
  // GPU_and_PNM (Oct 26): PoCL builds the kernel with in-process clang, whose LLVM support library calls srand() with a
  // time-based seed, so the rand() input data below changed on every run. Restore the C default seed (1) after the build.
  srand(1);

  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&input_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&indices_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&output_memobj));

  // Generate input data and random indices
  std::vector<TYPE> h_input(size);
  std::vector<unsigned int> h_indices(size);
  std::vector<TYPE> h_output(size, 0);
  for (uint32_t i = 0; i < size; ++i) {
    h_input[i] = (TYPE)(rand() & 0xFFFF);
    h_indices[i] = rand() % size;  // Random indices into input array
  }

  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, input_memobj, CL_TRUE, 0, data_bytes, h_input.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, indices_memobj, CL_TRUE, 0, idx_bytes, h_indices.data(), 0, NULL, NULL));

  printf("Execute the kernel\n");
  size_t global_work_size[1] = {size};
  size_t local_work_size[1] = {1};
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, global_work_size, local_work_size, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, output_memobj, CL_TRUE, 0, data_bytes, h_output.data(), 0, NULL, NULL));

  printf("Verify result\n");
  int errors = 0;
  for (uint32_t i = 0; i < size; ++i) {
    TYPE expected = h_input[h_indices[i]];
    if (h_output[i] != expected) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%d, actual=%d (idx=%u)\n", i, (int)expected, (int)h_output[i], h_indices[i]);
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
