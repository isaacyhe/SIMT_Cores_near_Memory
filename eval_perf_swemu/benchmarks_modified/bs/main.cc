#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include <algorithm>

#define KERNEL_NAME "binary_search"

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

// CPU reference binary search
static int binary_search_cpu(const int *sorted_array, int array_size, int target) {
  int lo = 0, hi = array_size - 1;
  while (lo <= hi) {
    int mid = lo + (hi - lo) / 2;
    if (sorted_array[mid] == target)
      return mid;
    else if (sorted_array[mid] < target)
      lo = mid + 1;
    else
      hi = mid - 1;
  }
  return -1;
}

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem arr_memobj = NULL;
cl_mem query_memobj = NULL;
cl_mem result_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (arr_memobj) clReleaseMemObject(arr_memobj);
  if (query_memobj) clReleaseMemObject(query_memobj);
  if (result_memobj) clReleaseMemObject(result_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}

uint32_t array_size = 4096;
uint32_t num_queries = 256;

static void show_usage() {
  printf("Usage: [-n array_size] [-q num_queries] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:q:h")) != -1) {
    switch (c) {
    case 'n':
      array_size = atoi(optarg);
      break;
    case 'q':
      num_queries = atoi(optarg);
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

  printf("Binary Search: array_size=%d, num_queries=%d\n", array_size, num_queries);

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

  // Generate sorted array with unique values
  std::vector<int> h_sorted(array_size);
  srand(42);
  h_sorted[0] = rand() % 10;
  for (uint32_t i = 1; i < array_size; ++i) {
    h_sorted[i] = h_sorted[i-1] + 1 + (rand() % 5);
  }

  // Generate queries: mix of values that exist and values that don't
  std::vector<int> h_queries(num_queries);
  for (uint32_t i = 0; i < num_queries; ++i) {
    if (i % 4 == 0) {
      // Pick a value NOT in the array (value between two consecutive elements)
      uint32_t idx = rand() % (array_size - 1);
      h_queries[i] = h_sorted[idx] + 1;
      // Check if this is actually in the array
      if (h_queries[i] == h_sorted[idx + 1]) {
        h_queries[i] = h_sorted[0] - 1; // guaranteed not in array
      }
    } else {
      // Pick a value that IS in the array
      uint32_t idx = rand() % array_size;
      h_queries[i] = h_sorted[idx];
    }
  }

  printf("Allocate device buffers\n");
  size_t arr_bytes = array_size * sizeof(int);
  size_t query_bytes = num_queries * sizeof(int);
  size_t result_bytes = num_queries * sizeof(int);

  arr_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, arr_bytes, NULL, &_err));
  query_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, query_bytes, NULL, &_err));
  result_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, result_bytes, NULL, &_err));

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
  int arr_size_arg = (int)array_size;
  int num_q_arg = (int)num_queries;
  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&arr_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&query_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&result_memobj));
  CL_CHECK(clSetKernelArg(kernel, 3, sizeof(int), &arr_size_arg));
  CL_CHECK(clSetKernelArg(kernel, 4, sizeof(int), &num_q_arg));

  std::vector<int> h_results(num_queries);

  // Creating command queue
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, arr_memobj, CL_TRUE, 0, arr_bytes, h_sorted.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, query_memobj, CL_TRUE, 0, query_bytes, h_queries.data(), 0, NULL, NULL));

  // Compute work sizes
  size_t local_ws = max_wgs;
  if (local_ws > num_queries) local_ws = num_queries;
  size_t global_ws = ((num_queries + local_ws - 1) / local_ws) * local_ws;

  printf("Execute the kernel (global_ws=%zu, local_ws=%zu)\n", global_ws, local_ws);
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, &global_ws, &local_ws, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, result_memobj, CL_TRUE, 0, result_bytes, h_results.data(), 0, NULL, NULL));

  printf("Verify result\n");
  int errors = 0;
  for (uint32_t i = 0; i < num_queries; ++i) {
    int expected = binary_search_cpu(h_sorted.data(), array_size, h_queries[i]);
    if (h_results[i] != expected) {
      if (errors < 100) {
        printf("*** error: query[%d]=%d, expected index=%d, got=%d\n",
               i, h_queries[i], expected, h_results[i]);
      }
      ++errors;
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
