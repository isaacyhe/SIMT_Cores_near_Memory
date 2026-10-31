#include "common.h"

// Gather: output[i] = input[indices[i]]
// This is an indirect/random memory access pattern typical of
// graph analytics, sparse matrix operations, and database joins.
__kernel void gather(__global const TYPE *input,
                     __global const unsigned int *indices,
                     __global TYPE *output)
{
  int gid = get_global_id(0);
  output[gid] = input[indices[gid]];
}
