#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <vector>
#include <algorithm>

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

// CPU reference: Needleman-Wunsch DP
static void nw_cpu(int *score, const int *seq_a, const int *seq_b,
                   int size, int penalty) {
  // Initialize first row and column
  for (int i = 0; i < size; ++i) {
    score[i * size + 0] = i * penalty;
    score[0 * size + i] = i * penalty;
  }

  // Fill the scoring matrix
  for (int i = 1; i < size; ++i) {
    for (int j = 1; j < size; ++j) {
      int match = score[(i-1) * size + (j-1)] + ((seq_a[i] == seq_b[j]) ? 1 : -1);
      int del   = score[(i-1) * size + j] + penalty;
      int ins   = score[i * size + (j-1)] + penalty;
      int val = match;
      if (del > val) val = del;
      if (ins > val) val = ins;
      score[i * size + j] = val;
    }
  }
}

cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel_fill = NULL;
cl_mem score_memobj = NULL;
cl_mem seqa_memobj = NULL;
cl_mem seqb_memobj = NULL;
uint8_t *kernel_bin = NULL;

static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel_fill) clReleaseKernel(kernel_fill);
  if (program) clReleaseProgram(program);
  if (score_memobj) clReleaseMemObject(score_memobj);
  if (seqa_memobj) clReleaseMemObject(seqa_memobj);
  if (seqb_memobj) clReleaseMemObject(seqb_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}

uint32_t matrix_size = 128;
int penalty = -2;

static void show_usage() {
  printf("Usage: [-n size] [-p penalty] [-h: help]\n");
}

static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:p:h")) != -1) {
    switch (c) {
    case 'n':
      matrix_size = atoi(optarg);
      break;
    case 'p':
      penalty = -abs(atoi(optarg));
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

  // size includes the boundary row/column, so actual sequences are (matrix_size-1) long
  int size = (int)matrix_size;
  printf("Needleman-Wunsch: size=%d, penalty=%d\n", size, penalty);

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

  // Generate random sequences (values 0-3, like DNA bases)
  srand(42);
  std::vector<int> h_seq_a(size);
  std::vector<int> h_seq_b(size);
  for (int i = 0; i < size; ++i) {
    h_seq_a[i] = rand() % 4;
    h_seq_b[i] = rand() % 4;
  }

  // Initialize scoring matrix with boundary conditions
  uint32_t mat_elems = (uint32_t)size * (uint32_t)size;
  std::vector<int> h_score(mat_elems, 0);
  for (int i = 0; i < size; ++i) {
    h_score[i * size + 0] = i * penalty;
    h_score[0 * size + i] = i * penalty;
  }

  printf("Allocate device buffers\n");
  size_t mat_bytes = mat_elems * sizeof(int);
  size_t seq_bytes = size * sizeof(int);

  score_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_WRITE, mat_bytes, NULL, &_err));
  seqa_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, seq_bytes, NULL, &_err));
  seqb_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, seq_bytes, NULL, &_err));

  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

  // Build program
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

  // Create kernel
  kernel_fill = CL_CHECK2(clCreateKernel(program, "nw_fill1", &_err));

  // Creating command queue
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, score_memobj, CL_TRUE, 0, mat_bytes, h_score.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, seqa_memobj, CL_TRUE, 0, seq_bytes, h_seq_a.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, seqb_memobj, CL_TRUE, 0, seq_bytes, h_seq_b.data(), 0, NULL, NULL));

  // Process anti-diagonals
  // Total number of anti-diagonals: 2*(size-1) - 1
  int num_diags = 2 * (size - 1) - 1;
  printf("Execute kernel across %d anti-diagonals\n", num_diags);

  auto time_start = std::chrono::high_resolution_clock::now();

  for (int d = 0; d < num_diags; ++d) {
    // Compute range of row indices for this anti-diagonal (must match kernel)
    int sum = d + 2;
    int i_start = sum - (size - 1);
    if (i_start < 1) i_start = 1;
    int i_end = sum - 1;
    if (i_end > size - 1) i_end = size - 1;
    int diag_len = i_end - i_start + 1;

    if (diag_len <= 0) continue;

    size_t local_ws = max_wgs;
    if (local_ws > (size_t)diag_len) local_ws = (size_t)diag_len;
    size_t global_ws = (((size_t)diag_len + local_ws - 1) / local_ws) * local_ws;

    CL_CHECK(clSetKernelArg(kernel_fill, 0, sizeof(cl_mem), (void *)&score_memobj));
    CL_CHECK(clSetKernelArg(kernel_fill, 1, sizeof(cl_mem), (void *)&seqa_memobj));
    CL_CHECK(clSetKernelArg(kernel_fill, 2, sizeof(cl_mem), (void *)&seqb_memobj));
    CL_CHECK(clSetKernelArg(kernel_fill, 3, sizeof(int), &size));
    CL_CHECK(clSetKernelArg(kernel_fill, 4, sizeof(int), &penalty));
    CL_CHECK(clSetKernelArg(kernel_fill, 5, sizeof(int), &d));

    CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel_fill, 1, NULL,
                                     &global_ws, &local_ws, 0, NULL, NULL));
    CL_CHECK(clFinish(commandQueue));
  }

  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  printf("Download destination buffer\n");
  std::vector<int> h_result(mat_elems);
  CL_CHECK(clEnqueueReadBuffer(commandQueue, score_memobj, CL_TRUE, 0, mat_bytes, h_result.data(), 0, NULL, NULL));

  // CPU reference
  printf("Verify result\n");
  std::vector<int> h_ref(mat_elems, 0);
  for (int i = 0; i < size; ++i) {
    h_ref[i * size + 0] = i * penalty;
    h_ref[0 * size + i] = i * penalty;
  }
  nw_cpu(h_ref.data(), h_seq_a.data(), h_seq_b.data(), size, penalty);

  int errors = 0;
  for (uint32_t i = 0; i < mat_elems; ++i) {
    if (h_result[i] != h_ref[i]) {
      if (errors < 100) {
        int row = i / size;
        int col = i % size;
        printf("*** error: [%d,%d] expected=%d, actual=%d\n", row, col, h_ref[i], h_result[i]);
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
