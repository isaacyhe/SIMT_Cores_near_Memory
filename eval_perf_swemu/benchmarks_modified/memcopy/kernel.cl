#include "common.h"

__kernel void memcopy(__global const TYPE *src,
                      __global TYPE *dst)
{
  int gid = get_global_id(0);
  dst[gid] = src[gid];
}
