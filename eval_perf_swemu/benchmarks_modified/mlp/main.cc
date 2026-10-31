#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>

#define KERNEL_NAME "gemv_relu"

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

// CPU reference: GEMV + ReLU
static void gemv_relu_cpu(float *output, const float *matrix, const float *input,
                          int rows, int cols) {
  for (int i = 0; i < rows; ++i) {
    float sum = 0.0f;
    for (int j = 0; j < cols; ++j) {
      sum += matrix[i * cols + j] * input[j];
    }
    output[i] = (sum > 0.0f) ? sum : 0.0f;
  }
}

static bool compare_float(float a, float b, int index, int errors) {
  // Use relative + absolute tolerance for accumulated float results
  float diff = fabsf(a - b);
  float abs_tol = 1e-5f;
  float rel_tol = 1e-3f;
  float max_val = fmaxf(fabsf(a), fabsf(b));
  if (diff > abs_tol && diff > rel_tol * max_val) {
    if (errors < 100) {
      printf("*** error: [%d] expected=%f, actual=%f, diff=%e\n", index, a, b, diff);
    }
    return false;
  }
  return true;
}

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem mat_memobj = NULL;
cl_mem in_memobj = NULL;
cl_mem out_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (mat_memobj) clReleaseMemObject(mat_memobj);
  if (in_memobj) clReleaseMemObject(in_memobj);
  if (out_memobj) clReleaseMemObject(out_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}

uint32_t num_rows = 256;
uint32_t num_cols = 128;
uint32_t num_layers = 2;

static void show_usage() {
  printf("Usage: [-n rows] [-m cols] [-l layers] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:m:l:h")) != -1) {
    switch (c) {
    case 'n':
      num_rows = atoi(optarg);
      break;
    case 'm':
      num_cols = atoi(optarg);
      break;
    case 'l':
      num_layers = atoi(optarg);
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

  printf("MLP: rows=%d, cols=%d, layers=%d\n", num_rows, num_cols, num_layers);

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

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

  // Build program
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

  // Create kernel
  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  // Creating command queue
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  // For MLP we run multiple layers.
  // Layer 0: matrix [num_rows x num_cols] * input [num_cols] -> output [num_rows]
  // Layer 1+: matrix [num_rows x num_rows] * input [num_rows] -> output [num_rows]
  // (Square matrices for hidden layers)

  // Allocate host data for largest matrix needed
  uint32_t max_mat_size = num_rows * num_cols;
  if (num_rows * num_rows > max_mat_size)
    max_mat_size = num_rows * num_rows;

  std::vector<float> h_matrix(max_mat_size);
  std::vector<float> h_input(num_cols > num_rows ? num_cols : num_rows);
  std::vector<float> h_output(num_rows);
  std::vector<float> h_ref_input(num_cols > num_rows ? num_cols : num_rows);
  std::vector<float> h_ref_output(num_rows);

  // Initialize input vector with small random values
  srand(42);
  for (uint32_t i = 0; i < (num_cols > num_rows ? num_cols : num_rows); ++i) {
    float val = static_cast<float>(rand()) / RAND_MAX * 2.0f - 1.0f;
    h_input[i] = val;
    h_ref_input[i] = val;
  }

  // Allocate device buffers for max sizes
  size_t mat_bytes = max_mat_size * sizeof(float);
  size_t vec_bytes = (num_cols > num_rows ? num_cols : num_rows) * sizeof(float);
  size_t out_bytes = num_rows * sizeof(float);

  mat_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, mat_bytes, NULL, &_err));
  in_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_WRITE, vec_bytes, NULL, &_err));
  out_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_WRITE, out_bytes, NULL, &_err));

  // Upload initial input vector
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, in_memobj, CL_TRUE, 0,
                                 vec_bytes, h_input.data(), 0, NULL, NULL));

  // Compute local work size
  size_t local_ws = max_wgs;
  if (local_ws > num_rows) local_ws = num_rows;
  // Ensure global work size is a multiple of local work size
  size_t global_ws = ((num_rows + local_ws - 1) / local_ws) * local_ws;

  printf("Execute %d layers (global_ws=%zu, local_ws=%zu)\n",
         num_layers, global_ws, local_ws);

  auto time_start = std::chrono::high_resolution_clock::now();

  int errors = 0;

  for (uint32_t layer = 0; layer < num_layers; ++layer) {
    uint32_t cur_cols = (layer == 0) ? num_cols : num_rows;
    uint32_t cur_rows = num_rows;
    uint32_t cur_mat_size = cur_rows * cur_cols;

    // Generate random weights for this layer (deterministic per layer)
    srand(100 + layer);
    for (uint32_t i = 0; i < cur_mat_size; ++i) {
      // Small weights to avoid overflow across layers
      h_matrix[i] = (static_cast<float>(rand()) / RAND_MAX * 2.0f - 1.0f) / (float)cur_cols;
    }

    // Upload matrix
    CL_CHECK(clEnqueueWriteBuffer(commandQueue, mat_memobj, CL_TRUE, 0,
                                   cur_mat_size * sizeof(float), h_matrix.data(), 0, NULL, NULL));

    // Set kernel arguments
    CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&mat_memobj));
    CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&in_memobj));
    CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&out_memobj));
    CL_CHECK(clSetKernelArg(kernel, 3, sizeof(int), &cur_rows));
    CL_CHECK(clSetKernelArg(kernel, 4, sizeof(int), &cur_cols));

    // Adjust global work size for current layer
    size_t cur_global_ws = ((cur_rows + local_ws - 1) / local_ws) * local_ws;

    // Launch kernel
    CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL,
                                     &cur_global_ws, &local_ws, 0, NULL, NULL));
    CL_CHECK(clFinish(commandQueue));

    // CPU reference for this layer
    gemv_relu_cpu(h_ref_output.data(), h_matrix.data(), h_ref_input.data(),
                  cur_rows, cur_cols);

    // Copy output to input for next layer (both GPU and CPU)
    if (layer < num_layers - 1) {
      // GPU: read output back, write to input buffer (avoids clEnqueueCopyBuffer)
      std::vector<float> h_tmp(cur_rows);
      CL_CHECK(clEnqueueReadBuffer(commandQueue, out_memobj, CL_TRUE, 0,
                                    cur_rows * sizeof(float), h_tmp.data(), 0, NULL, NULL));
      CL_CHECK(clEnqueueWriteBuffer(commandQueue, in_memobj, CL_TRUE, 0,
                                     cur_rows * sizeof(float), h_tmp.data(), 0, NULL, NULL));

      // CPU: copy reference output to reference input
      for (uint32_t i = 0; i < cur_rows; ++i) {
        h_ref_input[i] = h_ref_output[i];
      }
    }
  }

  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  // Download final output
  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, out_memobj, CL_TRUE, 0,
                                num_rows * sizeof(float), h_output.data(), 0, NULL, NULL));

  // Verify result
  printf("Verify result\n");
  for (uint32_t i = 0; i < num_rows; ++i) {
    if (!compare_float(h_output[i], h_ref_output[i], i, errors)) {
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
