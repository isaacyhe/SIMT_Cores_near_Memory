#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include <algorithm>

#define KERNEL_NAME "mark_unique"

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
  fseek(fp , 0 , SEEK_END);
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
cl_mem flags_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (input_memobj) clReleaseMemObject(input_memobj);
  if (flags_memobj) clReleaseMemObject(flags_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}

uint32_t num_elements = 4096;

static void show_usage() {
  printf("Usage: [-n size] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:h")) != -1) {
    switch (c) {
    case 'n':
      num_elements = atoi(optarg);
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
}

int main(int argc, char **argv) {
  // parse command arguments
  parse_args(argc, argv);

  printf("Unique: num_elements=%d\n", num_elements);

  cl_platform_id platform_id;
  size_t kernel_size;

  // Getting platform and device information
  CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
  CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

  printf("Create context\n");
  context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL, &_err));

  // Query max work group size
  size_t max_wgs = 0;
  clGetDeviceInfo(device_id, CL_DEVICE_MAX_WORK_GROUP_SIZE, sizeof(max_wgs), &max_wgs, NULL);
  printf("Max work group size: %zu\n", max_wgs);

  // Generate input: sorted array with duplicates
  srand(42);
  std::vector<int> h_input(num_elements);
  h_input[0] = 0;
  for (uint32_t i = 1; i < num_elements; ++i) {
    // ~50% chance of duplicate, ~50% chance of increment
    if (rand() % 2 == 0) {
      h_input[i] = h_input[i-1];  // duplicate
    } else {
      h_input[i] = h_input[i-1] + 1 + (rand() % 3);  // new value
    }
  }

  printf("Allocate device buffers\n");
  size_t input_bytes = num_elements * sizeof(int);
  size_t flags_bytes = num_elements * sizeof(int);

  input_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, input_bytes, NULL, &_err));
  flags_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, flags_bytes, NULL, &_err));

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

  // Build program
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

  // Create kernel
  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  // Set kernel arguments
  int n_arg = (int)num_elements;
  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&input_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&flags_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(int), &n_arg));

  std::vector<int> h_flags(num_elements);

  // Creating command queue
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, input_memobj, CL_TRUE, 0, input_bytes, h_input.data(), 0, NULL, NULL));

  // Compute work sizes
  size_t local_ws = max_wgs;
  if (local_ws > num_elements) local_ws = num_elements;
  size_t global_ws = ((num_elements + local_ws - 1) / local_ws) * local_ws;

  printf("Execute the kernel (global_ws=%zu, local_ws=%zu)\n", global_ws, local_ws);
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, &global_ws, &local_ws, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, flags_memobj, CL_TRUE, 0, flags_bytes, h_flags.data(), 0, NULL, NULL));

  // CPU compaction using GPU-computed flags
  std::vector<int> h_gpu_unique;
  for (uint32_t i = 0; i < num_elements; ++i) {
    if (h_flags[i] != 0) {
      h_gpu_unique.push_back(h_input[i]);
    }
  }

  // CPU reference: std::unique
  std::vector<int> h_ref(h_input);
  auto it = std::unique(h_ref.begin(), h_ref.end());
  h_ref.erase(it, h_ref.end());

  // Verify
  printf("Verify result\n");
  printf("GPU unique count: %zu, CPU unique count: %zu\n",
         h_gpu_unique.size(), h_ref.size());

  int errors = 0;
  if (h_gpu_unique.size() != h_ref.size()) {
    printf("*** error: size mismatch: gpu=%zu, cpu=%zu\n",
           h_gpu_unique.size(), h_ref.size());
    errors = 1;
  } else {
    for (size_t i = 0; i < h_ref.size(); ++i) {
      if (h_gpu_unique[i] != h_ref[i]) {
        if (errors < 100) {
          printf("*** error: [%zu] expected=%d, actual=%d\n", i, h_ref[i], h_gpu_unique[i]);
        }
        ++errors;
      }
    }
  }
  if (0 == errors) {
    printf("PASSED!\n");
  } else {
    printf("FAILED! - %d errors\n", errors);
  }

  // Clean up
  cleanup();

  return errors;
}
