// Unique kernel: mark boundaries where consecutive elements differ.
// Each work-item checks if arr[i] != arr[i-1] and writes 1 or 0 to flags.
// Element 0 is always a boundary (flag=1).

__kernel void mark_unique(__global const int *input,
                          __global int *flags,
                          const int n)
{
    int gid = get_global_id(0);
    if (gid >= n)
        return;

    if (gid == 0) {
        flags[gid] = 1;
    } else {
        flags[gid] = (input[gid] != input[gid - 1]) ? 1 : 0;
    }
}
