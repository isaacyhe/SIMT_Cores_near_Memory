#include "common.h"
#include "soft_math_cl.h"

// Each work-item counts occurrences for one bin by scanning all input.
// This is a data-scanning pattern typical of analytics near memory.
__kernel void histogram(__global const unsigned int *input,
                        __global unsigned int *bins,
                        const unsigned int n)
{
  int bin_id = get_global_id(0);
  if (bin_id < NUM_BINS) {
    unsigned int count = 0;
    for (unsigned int i = 0; i < n; ++i) {
      if (UMOD(input[i], NUM_BINS) == (unsigned int)bin_id) {
        count++;
      }
    }
    bins[bin_id] = count;
  }
}
