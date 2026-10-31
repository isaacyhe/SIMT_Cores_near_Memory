// Binary Search kernel
// Each work-item performs a binary search for one query in the sorted array

__kernel void binary_search(__global const int *sorted_array,
                            __global const int *queries,
                            __global int *results,
                            const int array_size,
                            const int num_queries)
{
    int gid = get_global_id(0);
    if (gid >= num_queries)
        return;

    int target = queries[gid];
    int lo = 0;
    int hi = array_size - 1;
    int found = -1;

    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        int val = sorted_array[mid];
        if (val == target) {
            found = mid;
            break;
        } else if (val < target) {
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }

    results[gid] = found;
}
