// Needleman-Wunsch kernel
// Processes one anti-diagonal of the scoring matrix at a time.
// Each work-item computes one cell on the current anti-diagonal.
//
// The scoring matrix has dimensions size x size.
// Row 0 and column 0 are boundary conditions (initialized on host).
// Inner cells are at (i, j) for i in [1, size-1], j in [1, size-1].
//
// Anti-diagonal d (0-indexed) contains cells where i + j = d + 2.
// Total anti-diagonals: 2*(size-1) - 1, i.e., d in [0, 2*(size-2)].

__kernel void nw_fill1(__global int *score_matrix,
                       __global const int *seq_a,
                       __global const int *seq_b,
                       const int size,
                       const int penalty,
                       const int anti_diag)
{
    int gid = get_global_id(0);

    // Compute range of row indices for this anti-diagonal
    int sum = anti_diag + 2;  // i + j = sum
    int i_start = sum - (size - 1);
    if (i_start < 1) i_start = 1;
    int i_end = sum - 1;
    if (i_end > size - 1) i_end = size - 1;

    int diag_len = i_end - i_start + 1;
    if (gid >= diag_len)
        return;

    int i = i_start + gid;
    int j = sum - i;

    int match = score_matrix[(i-1) * size + (j-1)] + ((seq_a[i] == seq_b[j]) ? 1 : -1);
    int del   = score_matrix[(i-1) * size + j] + penalty;
    int ins   = score_matrix[i * size + (j-1)] + penalty;

    int val = match;
    if (del > val) val = del;
    if (ins > val) val = ins;

    score_matrix[i * size + j] = val;
}
