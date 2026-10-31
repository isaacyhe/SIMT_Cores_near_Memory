// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <vx_spawn.h>
#include <vx_intrinsics.h>
#include <vx_print.h>

// GPU_and_PNM (Oct 28): divisions by runtime values go through VX_UDIV/VX_UMOD. Default: plain C operators (object code unchanged).
// VX_SOFT_IDIV (soft-IDIV CAL configs, hardware without an integer divider): shift-subtract software division (multiply stays).
#ifdef VX_SOFT_IDIV
// Branch-free: on Vortex a branch decision comes from one lane for the whole warp (no split/join in this GCC-built library),
// so the per-lane subtract decision must be data flow (sltu/and), never a branch. The loop count is the same in every lane.
static uint32_t vx_soft_udiv32(uint32_t n, uint32_t d) {
  uint32_t q = 0, r = 0;
  for (int i = 31; i >= 0; --i) {
    r = (r << 1) | ((n >> i) & 1u);
    uint32_t m = -(uint32_t)(r >= d);
    r -= d & m;
    q |= m & (1u << i);
  }
  return q;
}
#define VX_UDIV(a, b) vx_soft_udiv32((uint32_t)(a), (uint32_t)(b))
#define VX_UMOD(a, b) ((uint32_t)(a) - vx_soft_udiv32((uint32_t)(a), (uint32_t)(b)) * (uint32_t)(b))
#else
#define VX_UDIV(a, b) ((a) / (b))
#define VX_UMOD(a, b) ((a) % (b))
#endif

// GPU_and_PNM (Oct 28, user: same indexing in every runtime): the per-task index loops divide by launch-fixed divisors through a
// reciprocal m = floor((2^32-1)/d) prepared once per call (hardware divu in the stock runtime, the soft division under
// VX_SOFT_IDIV); per task q0 = mulhu(n, m) is q or q-1 and one branch-free correction gives q. So the stock and soft-IDIV
// runtimes run the same per-task code and differ only in how the few per-call reciprocals are computed. d >= 1 always here.
typedef struct { uint32_t d, m; } vx_udiv_t;
static inline vx_udiv_t vx_udiv_prep(uint32_t d) {
  vx_udiv_t v; v.d = d; v.m = VX_UDIV(0xFFFFFFFFu, d); return v;
}
static inline uint32_t vx_udiv_q(uint32_t n, vx_udiv_t v) {
  uint32_t q = (uint32_t)(((uint64_t)n * v.m) >> 32);
  uint32_t r = n - q * v.d;
  return q + (uint32_t)(r >= v.d);
}

#ifdef __cplusplus
extern "C" {
#endif

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

__thread dim3_t blockIdx;
__thread dim3_t threadIdx;
dim3_t gridDim;
dim3_t blockDim;

__thread uint32_t __local_group_id;
uint32_t __warps_per_group;

typedef struct {
	vx_kernel_func_cb callback;
	const void* arg;
	uint32_t group_offset;
	uint32_t warp_batches;
	uint32_t remaining_warps;
  uint32_t warps_per_group;
  uint32_t groups_per_core;
  uint32_t remaining_mask;
} wspawn_groups_args_t;

typedef struct {
	vx_kernel_func_cb callback;
	const void* arg;
	uint32_t all_tasks_offset;
  uint32_t remain_tasks_offset;
	uint32_t warp_batches;
	uint32_t remaining_warps;
} wspawn_threads_args_t;

static void __attribute__ ((noinline)) process_threads() {
  wspawn_threads_args_t* targs = (wspawn_threads_args_t*)csr_read(VX_CSR_MSCRATCH);

  uint32_t threads_per_warp = vx_num_threads();
  uint32_t warp_id = vx_warp_id();
  uint32_t thread_id = vx_thread_id();

  uint32_t remaining_warps = targs->remaining_warps;
  uint32_t warp_batches = targs->warp_batches;

  uint32_t start_warp_add = (warp_id < remaining_warps) ? warp_id : remaining_warps;
  uint32_t start_warp = warp_id * warp_batches + start_warp_add;
  uint32_t iterations = warp_batches + (warp_id < remaining_warps);

  uint32_t start_task_id = targs->all_tasks_offset + start_warp * threads_per_warp + thread_id;
  uint32_t end_task_id = start_task_id + iterations * threads_per_warp;

  uint32_t gridDim_x = gridDim.x;
  uint32_t gridDim_y = gridDim.y;

  vx_kernel_func_cb callback = targs->callback;
  const void* arg = targs->arg;

  vx_udiv_t dgx = vx_udiv_prep(gridDim_x), dgy = vx_udiv_prep(gridDim_y), dgxy = vx_udiv_prep(gridDim_x * gridDim_y);
  for (uint32_t task_id = start_task_id; task_id < end_task_id; task_id += threads_per_warp) {
    uint32_t qx = vx_udiv_q(task_id, dgx);
    blockIdx.x = task_id - qx * gridDim_x;
    blockIdx.y = qx - vx_udiv_q(qx, dgy) * gridDim_y;
    blockIdx.z = vx_udiv_q(task_id, dgxy);
    callback((void*)arg);
  }
}

static void __attribute__ ((noinline)) process_remaining_threads() {
  wspawn_threads_args_t* targs = (wspawn_threads_args_t*)csr_read(VX_CSR_MSCRATCH);

  uint32_t thread_id = vx_thread_id();
  uint32_t task_id = targs->remain_tasks_offset + thread_id;
  blockIdx.x = VX_UMOD(task_id, gridDim.x);
  blockIdx.y = VX_UMOD(VX_UDIV(task_id, gridDim.x), gridDim.y);
  blockIdx.z = VX_UDIV(task_id, gridDim.x * gridDim.y);
  (targs->callback)((void*)targs->arg);
}

static void __attribute__ ((noinline)) process_threads_stub() {
  // activate all threads
  vx_tmc(-1);

  // process all tasks
  process_threads();

  // disable warp
  vx_tmc_zero();
}

///////////////////////////////////////////////////////////////////////////////

static void __attribute__ ((noinline)) process_thread_groups() {
  wspawn_groups_args_t* targs = (wspawn_groups_args_t*)csr_read(VX_CSR_MSCRATCH);

  uint32_t threads_per_warp = vx_num_threads();
  uint32_t warp_id = vx_warp_id();
  uint32_t thread_id = vx_thread_id();
  uint32_t warps_per_group = targs->warps_per_group;
  uint32_t groups_per_core = targs->groups_per_core;
  uint32_t remaining_warps = targs->remaining_warps;
  uint32_t warp_batches = targs->warp_batches;

  uint32_t blockDim_x = blockDim.x;
  uint32_t blockDim_y = blockDim.y;
  uint32_t blockDim_xy = blockDim_x * blockDim_y;
  uint32_t gridDim_x = gridDim.x;
  uint32_t gridDim_y = gridDim.y;
  uint32_t gridDim_xy = gridDim_x * gridDim_y;

  uint32_t iterations = warp_batches + (warp_id < remaining_warps);

  uint32_t local_group_id = VX_UDIV(warp_id, warps_per_group);
  uint32_t group_warp_id = warp_id - local_group_id * warps_per_group;
  uint32_t local_task_id = group_warp_id * threads_per_warp + thread_id;

  __local_group_id = local_group_id;
  threadIdx.x = VX_UMOD(local_task_id, blockDim_x);
  threadIdx.y = VX_UMOD(VX_UDIV(local_task_id, blockDim_x), blockDim_y);
  threadIdx.z = VX_UDIV(local_task_id, blockDim_xy);

  uint32_t start_group = targs->group_offset + local_group_id;
  uint32_t group_stride = groups_per_core;
  uint32_t end_group = start_group + iterations * group_stride;

  vx_kernel_func_cb callback = targs->callback;
  const void* arg = targs->arg;

  vx_udiv_t dgx = vx_udiv_prep(gridDim_x), dgy = vx_udiv_prep(gridDim_y), dgxy = vx_udiv_prep(gridDim_x * gridDim_y);
  for (uint32_t group_id = start_group; group_id < end_group; group_id += group_stride) {
    uint32_t qx = vx_udiv_q(group_id, dgx);
    blockIdx.x = group_id - qx * gridDim_x;
    blockIdx.y = qx - vx_udiv_q(qx, dgy) * gridDim_y;
    blockIdx.z = vx_udiv_q(group_id, dgxy);
    callback((void*)arg);
  }
}

static void __attribute__ ((noinline)) process_thread_groups_stub() {
  wspawn_groups_args_t* targs = (wspawn_groups_args_t*)csr_read(VX_CSR_MSCRATCH);
  uint32_t warps_per_group = targs->warps_per_group;
  uint32_t remaining_mask = targs->remaining_mask;
  uint32_t warp_id = vx_warp_id();
  uint32_t group_warp_id = VX_UMOD(warp_id, warps_per_group);
  uint32_t threads_mask = (group_warp_id == warps_per_group-1) ? remaining_mask : -1;

  // activate threads
  vx_tmc(threads_mask);

  // process thread groups
  process_thread_groups();

  // disable all warps except warp0
  vx_tmc(0 == vx_warp_id());
}

///////////////////////////////////////////////////////////////////////////////

int vx_spawn_threads(uint32_t dimension,
                     const uint32_t* grid_dim,
                     const uint32_t * block_dim,
                     vx_kernel_func_cb kernel_func,
                     const void* arg) {
  // calculate number of groups and group size
  uint32_t num_groups = 1;
  uint32_t group_size = 1;
  for (uint32_t i = 0; i < 3; ++i) {
    uint32_t gd = (grid_dim && (i < dimension)) ? grid_dim[i] : 1;
    uint32_t bd = (block_dim && (i < dimension)) ? block_dim[i] : 1;
    num_groups *= gd;
    group_size *= bd;
    gridDim.m[i] = gd;
    blockDim.m[i] = bd;
  }

  // device specifications
  uint32_t num_cores = vx_num_cores();
  uint32_t warps_per_core = vx_num_warps();
  uint32_t threads_per_warp = vx_num_threads();
  uint32_t core_id = vx_core_id();

  // check group size
  uint32_t threads_per_core = warps_per_core * threads_per_warp;
  if (threads_per_core < group_size) {
    vx_printf("error: group_size > threads_per_core (%d,%d)\n", group_size, threads_per_core);
    return -1;
  }

  if (group_size > 1) {
    // calculate number of warps per group
    uint32_t warps_per_group = VX_UDIV(group_size, threads_per_warp);
    uint32_t remaining_threads = group_size - warps_per_group * threads_per_warp;
    uint32_t remaining_mask = -1;
    if (remaining_threads != 0) {
      remaining_mask = (1 << remaining_threads) - 1;
      ++warps_per_group;
    }

    // calculate necessary active cores
    uint32_t needed_warps = num_groups * warps_per_group;
    uint32_t needed_cores = VX_UDIV(needed_warps + warps_per_core-1, warps_per_core);
    uint32_t active_cores = MIN(needed_cores, num_cores);

    // only active cores participate
    if (core_id >= active_cores)
      return 0;

    // total number of groups per core
    uint32_t total_groups_per_core = VX_UDIV(num_groups, active_cores);
    uint32_t remaining_groups_per_core = num_groups - active_cores * total_groups_per_core;
    if (core_id < remaining_groups_per_core)
      ++total_groups_per_core;

    // calculate number of warps to activate
    uint32_t groups_per_core = VX_UDIV(warps_per_core, warps_per_group);
    uint32_t total_warps_per_core = total_groups_per_core * warps_per_group;
    uint32_t active_warps = total_warps_per_core;
    uint32_t warp_batches = 1, remaining_warps = 0;
    if (active_warps > warps_per_core) {
      active_warps = groups_per_core * warps_per_group;
      warp_batches = VX_UDIV(total_warps_per_core, active_warps);
      remaining_warps = total_warps_per_core - warp_batches * active_warps;
    }

    // calculate offsets for group distribution
    uint32_t group_offset = core_id * total_groups_per_core + MIN(core_id, remaining_groups_per_core);

    // set scheduler arguments
    wspawn_groups_args_t wspawn_args = {
      kernel_func,
      arg,
      group_offset,
      warp_batches,
      remaining_warps,
      warps_per_group,
      groups_per_core,
      remaining_mask
    };
    csr_write(VX_CSR_MSCRATCH, &wspawn_args);

    // set global variables
    __warps_per_group = warps_per_group;

    // execute callback on other warps
    vx_wspawn(active_warps, process_thread_groups_stub);

    // execute callback on warp0
    process_thread_groups_stub();
  } else {
    // set constant workitem attributes.
    // A work-group of one work-item occupies one warp: barriers in such a
    // group must count one warp (a count of 0 never releases: 1t_1w deadlock).
    __warps_per_group = 1;
    __local_group_id = 0;
    threadIdx.x = 0;
    threadIdx.y = 0;
    threadIdx.z = 0;

    uint32_t num_tasks = num_groups;

    // calculate necessary active cores
    uint32_t needed_cores = VX_UDIV(num_tasks + threads_per_core - 1, threads_per_core);
    uint32_t active_cores = MIN(needed_cores, num_cores);

    // only active cores participate
    if (core_id >= active_cores)
      return 0;

    // number of tasks per core
    uint32_t tasks_per_core = VX_UDIV(num_tasks, active_cores);
    uint32_t remaining_tasks_per_core = num_tasks - tasks_per_core * active_cores;
    if (core_id < remaining_tasks_per_core)
      ++tasks_per_core;

    // calculate number of warps to activate
    uint32_t total_warps_per_core = VX_UDIV(tasks_per_core, threads_per_warp);
    uint32_t remaining_tasks = tasks_per_core - total_warps_per_core * threads_per_warp;
    uint32_t active_warps = total_warps_per_core;
    uint32_t warp_batches = 1, remaining_warps = 0;
    if (active_warps > warps_per_core) {
      active_warps = warps_per_core;
      warp_batches = VX_UDIV(total_warps_per_core, active_warps);
      remaining_warps = total_warps_per_core - warp_batches * active_warps;
    }

    // calculate offsets for task distribution
    uint32_t all_tasks_offset = core_id * tasks_per_core + MIN(core_id, remaining_tasks_per_core);
    uint32_t remain_tasks_offset = all_tasks_offset + (tasks_per_core - remaining_tasks);

    // prepare scheduler arguments
    wspawn_threads_args_t wspawn_args = {
      kernel_func,
      arg,
      all_tasks_offset,
      remain_tasks_offset,
      warp_batches,
      remaining_warps
    };
    csr_write(VX_CSR_MSCRATCH, &wspawn_args);

    if (active_warps >= 1) {
      // execute callback on other warps
      vx_wspawn(active_warps, process_threads_stub);

      // activate all threads
      vx_tmc(-1);

      // process threads
      process_threads();

      // back to single-threaded
      vx_tmc_one();
    }

    if (remaining_tasks != 0) {
      // activate remaining threads
      uint32_t tmask = (1 << remaining_tasks) - 1;
      vx_tmc(tmask);

      // process remaining threads
      process_remaining_threads();

      // back to single-threaded
      vx_tmc_one();
    }
  }

  // wait for spawned warps to complete
  vx_wspawn(1, 0);

  return 0;
}

#ifdef __cplusplus
}
#endif
