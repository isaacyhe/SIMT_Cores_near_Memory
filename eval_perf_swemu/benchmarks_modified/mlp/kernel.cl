// MLP inference kernel: GEMV (matrix-vector multiply) + ReLU activation
// Each work-item computes one output element: dot product of matrix row with input vector

__kernel void gemv_relu(__global const float *matrix,
                        __global const float *input,
                        __global float *output,
                        const int rows,
                        const int cols)
{
    int gid = get_global_id(0);
    if (gid >= rows)
        return;

    float sum = 0.0f;
    for (int j = 0; j < cols; ++j) {
        sum += matrix[gid * cols + j] * input[j];
    }

    // ReLU activation
    output[gid] = (sum > 0.0f) ? sum : 0.0f;
}
