# vortex_32t_32w_fpnew (Oct 28, wave 2b): recipe of vortex_16t_8w_fpnew (util/density/halo/margins below); netlist spr_eval/build/32t_32w_be_fpnew
export DESIGN_NAME = Vortex
export DESIGN_NICKNAME = vortex_32t_32w_slang_fpnew
export PLATFORM = asap7
export CORNER = TC
export VERILOG_FILES = $(DESIGN_DIR)/src/VX_trace_pkg.sv \
    $(DESIGN_DIR)/src/cb_filter_pkg.sv \
    $(DESIGN_DIR)/src/VX_gpu_pkg.sv \
    $(DESIGN_DIR)/src/cf_math_pkg.sv \
    $(DESIGN_DIR)/src/VX_fpu_pkg.sv \
    $(DESIGN_DIR)/src/fpnew_pkg.sv \
    $(DESIGN_DIR)/src/ecc_pkg.sv \
    $(DESIGN_DIR)/src/VX_toggle_buffer.sv \
    $(DESIGN_DIR)/src/VX_operands_if.sv \
    $(DESIGN_DIR)/src/fpnew_top.sv \
    $(DESIGN_DIR)/src/VX_fncp_unit.sv \
    $(DESIGN_DIR)/src/norm_div_sqrt_mvp.sv \
    $(DESIGN_DIR)/src/pa_fdsu_top.v \
    $(DESIGN_DIR)/src/div_sqrt_top_mvp.sv \
    $(DESIGN_DIR)/src/popcount.sv \
    $(DESIGN_DIR)/src/VX_commit_csr_if.sv \
    $(DESIGN_DIR)/src/VX_onehot_encoder.sv \
    $(DESIGN_DIR)/src/fpnew_opgroup_block.sv \
    $(DESIGN_DIR)/src/stream_omega_net.sv \
    $(DESIGN_DIR)/src/VX_bits_concat.sv \
    $(DESIGN_DIR)/src/VX_uuid_gen.sv \
    $(DESIGN_DIR)/src/isochronous_spill_register.sv \
    $(DESIGN_DIR)/src/VX_gbar_unit.sv \
    $(DESIGN_DIR)/src/VX_mem_data_adapter.sv \
    $(DESIGN_DIR)/src/VX_cluster.sv \
    $(DESIGN_DIR)/src/VX_scope_switch.sv \
    $(DESIGN_DIR)/src/VX_cache_init.sv \
    $(DESIGN_DIR)/src/VX_fifo_queue.sv \
    $(DESIGN_DIR)/src/cb_filter.sv \
    $(DESIGN_DIR)/src/VX_stream_unpack.sv \
    $(DESIGN_DIR)/src/binary_to_gray.sv \
    $(DESIGN_DIR)/src/preprocess_mvp.sv \
    $(DESIGN_DIR)/src/VX_cache_data.sv \
    $(DESIGN_DIR)/src/VX_divider.sv \
    $(DESIGN_DIR)/src/VX_fetch.sv \
    $(DESIGN_DIR)/src/VX_serial_mul.sv \
    $(DESIGN_DIR)/src/VX_scan.sv \
    $(DESIGN_DIR)/src/VX_split_join.sv \
    $(DESIGN_DIR)/src/VX_bypass_buffer.sv \
    $(DESIGN_DIR)/src/VX_mux.sv \
    $(DESIGN_DIR)/src/id_queue.sv \
    $(DESIGN_DIR)/src/sync.sv \
    $(DESIGN_DIR)/src/VX_reduce_tree.sv \
    $(DESIGN_DIR)/src/serial_deglitch.sv \
    $(DESIGN_DIR)/src/VX_demux.sv \
    $(DESIGN_DIR)/src/stream_intf.sv \
    $(DESIGN_DIR)/src/VX_uop_sequencer.sv \
    $(DESIGN_DIR)/src/VX_fpu_div.sv \
    $(DESIGN_DIR)/src/lfsr_8bit.sv \
    $(DESIGN_DIR)/src/VX_writeback_if.sv \
    $(DESIGN_DIR)/src/stream_xbar.sv \
    $(DESIGN_DIR)/src/fpnew_rounding.sv \
    $(DESIGN_DIR)/src/sub_per_hash.sv \
    $(DESIGN_DIR)/src/control_mvp.sv \
    $(DESIGN_DIR)/src/VX_core.sv \
    $(DESIGN_DIR)/src/fpnew_divsqrt_multi.sv \
    $(DESIGN_DIR)/src/VX_mem_switch.sv \
    $(DESIGN_DIR)/src/nrbd_nrsc_mvp.sv \
    $(DESIGN_DIR)/src/iteration_div_sqrt_mvp.sv \
    $(DESIGN_DIR)/src/VX_gbar_bus_if.sv \
    $(DESIGN_DIR)/src/VX_stream_xpoint.sv \
    $(DESIGN_DIR)/src/VX_index_buffer.sv \
    $(DESIGN_DIR)/src/shift_reg.sv \
    $(DESIGN_DIR)/src/VX_lmem_switch.sv \
    $(DESIGN_DIR)/src/VX_edge_trigger.sv \
    $(DESIGN_DIR)/src/VX_fpu_unit.sv \
    $(DESIGN_DIR)/src/VX_stream_omega.sv \
    $(DESIGN_DIR)/src/fpnew_classifier.sv \
    $(DESIGN_DIR)/src/rr_arb_tree.sv \
    $(DESIGN_DIR)/src/VX_decode_if.sv \
    $(DESIGN_DIR)/src/stream_fifo.sv \
    $(DESIGN_DIR)/src/pa_fdsu_srt_single.v \
    $(DESIGN_DIR)/src/stream_filter.sv \
    $(DESIGN_DIR)/src/ecc_decode.sv \
    $(DESIGN_DIR)/src/VX_pipe_buffer.sv \
    $(DESIGN_DIR)/src/lzc.sv \
    $(DESIGN_DIR)/src/VX_schedule_if.sv \
    $(DESIGN_DIR)/src/VX_rr_arbiter.sv \
    $(DESIGN_DIR)/src/VX_stream_arb.sv \
    $(DESIGN_DIR)/src/VX_ibuffer_if.sv \
    $(DESIGN_DIR)/src/div_sqrt_mvp_wrapper.sv \
    $(DESIGN_DIR)/src/unread.sv \
    $(DESIGN_DIR)/src/fpnew_fma.sv \
    $(DESIGN_DIR)/src/VX_operands.sv \
    $(DESIGN_DIR)/src/VX_lzc.sv \
    $(DESIGN_DIR)/src/VX_shift_register.sv \
    $(DESIGN_DIR)/src/gated_clk_cell.v \
    $(DESIGN_DIR)/src/VX_fpu_fpnew.sv \
    $(DESIGN_DIR)/src/VX_mem_bank_adapter.sv \
    $(DESIGN_DIR)/src/VX_csr_unit.sv \
    $(DESIGN_DIR)/src/VX_gather_unit.sv \
    $(DESIGN_DIR)/src/VX_matrix_arbiter.sv \
    $(DESIGN_DIR)/src/VX_dispatch.sv \
    $(DESIGN_DIR)/src/cdc_2phase.sv \
    $(DESIGN_DIR)/src/VX_priority_arbiter.sv \
    $(DESIGN_DIR)/src/VX_pending_size.sv \
    $(DESIGN_DIR)/src/VX_sched_csr_if.sv \
    $(DESIGN_DIR)/src/edge_propagator_tx.sv \
    $(DESIGN_DIR)/src/VX_stream_switch.sv \
    $(DESIGN_DIR)/src/fpnew_noncomp.sv \
    $(DESIGN_DIR)/src/VX_mem_coalescer.sv \
    $(DESIGN_DIR)/src/VX_wctl_unit.sv \
    $(DESIGN_DIR)/src/stream_arbiter.sv \
    $(DESIGN_DIR)/src/gray_to_binary.sv \
    $(DESIGN_DIR)/src/cdc_fifo_2phase.sv \
    $(DESIGN_DIR)/src/VX_placeholder.sv \
    $(DESIGN_DIR)/src/edge_detect.sv \
    $(DESIGN_DIR)/src/fpnew_divsqrt_th_32.sv \
    $(DESIGN_DIR)/src/stream_arbiter_flushable.sv \
    $(DESIGN_DIR)/src/VX_cache.sv \
    $(DESIGN_DIR)/src/VX_nz_iterator.sv \
    $(DESIGN_DIR)/src/VX_commit_sched_if.sv \
    $(DESIGN_DIR)/src/VX_alu_int.sv \
    $(DESIGN_DIR)/src/VX_scope_tap.sv \
    $(DESIGN_DIR)/src/VX_cache_flush.sv \
    $(DESIGN_DIR)/src/VX_onehot_mux.sv \
    $(DESIGN_DIR)/src/VX_axi_adapter.sv \
    $(DESIGN_DIR)/src/VX_onehot_shift.sv \
    $(DESIGN_DIR)/src/VX_dispatch_unit.sv \
    $(DESIGN_DIR)/src/fpnew_cast_multi.sv \
    $(DESIGN_DIR)/src/counter.sv \
    $(DESIGN_DIR)/src/VX_lsu_mem_arb.sv \
    $(DESIGN_DIR)/src/VX_local_mem.sv \
    $(DESIGN_DIR)/src/VX_decode.sv \
    $(DESIGN_DIR)/src/stream_delay.sv \
    $(DESIGN_DIR)/src/VX_elastic_buffer.sv \
    $(DESIGN_DIR)/src/VX_priority_encoder.sv \
    $(DESIGN_DIR)/src/VX_find_first.sv \
    $(DESIGN_DIR)/src/VX_commit.sv \
    $(DESIGN_DIR)/src/VX_lsu_unit.sv \
    $(DESIGN_DIR)/src/VX_sp_ram.sv \
    $(DESIGN_DIR)/src/VX_cache_wrap.sv \
    $(DESIGN_DIR)/src/VX_dcr_bus_if.sv \
    $(DESIGN_DIR)/src/stream_fork_dynamic.sv \
    $(DESIGN_DIR)/src/VX_fpu_ncp.sv \
    $(DESIGN_DIR)/src/fall_through_register.sv \
    $(DESIGN_DIR)/src/VX_fpu_sqrt.sv \
    $(DESIGN_DIR)/src/lfsr.sv \
    $(DESIGN_DIR)/src/VX_allocator.sv \
    $(DESIGN_DIR)/src/VX_cache_tags.sv \
    $(DESIGN_DIR)/src/exp_backoff.sv \
    $(DESIGN_DIR)/src/VX_commit_if.sv \
    $(DESIGN_DIR)/src/pa_fpu_frbus.v \
    $(DESIGN_DIR)/src/VX_gbar_arb.sv \
    $(DESIGN_DIR)/src/VX_skid_buffer.sv \
    $(DESIGN_DIR)/src/plru_tree.sv \
    $(DESIGN_DIR)/src/VX_lsu_slice.sv \
    $(DESIGN_DIR)/src/pa_fdsu_round_single.v \
    $(DESIGN_DIR)/src/VX_fetch_if.sv \
    $(DESIGN_DIR)/src/onehot_to_bin.sv \
    $(DESIGN_DIR)/src/pa_fdsu_ff1.v \
    $(DESIGN_DIR)/src/VX_stream_pack.sv \
    $(DESIGN_DIR)/src/stream_mux.sv \
    $(DESIGN_DIR)/src/clk_div.sv \
    $(DESIGN_DIR)/src/VX_bits_insert.sv \
    $(DESIGN_DIR)/src/VX_issue_slice.sv \
    $(DESIGN_DIR)/src/VX_cyclic_arbiter.sv \
    $(DESIGN_DIR)/src/lfsr_16bit.sv \
    $(DESIGN_DIR)/src/VX_transpose.sv \
    $(DESIGN_DIR)/src/VX_schedule.sv \
    $(DESIGN_DIR)/src/VX_fp_rounding.sv \
    $(DESIGN_DIR)/src/delta_counter.sv \
    $(DESIGN_DIR)/src/rstgen_bypass.sv \
    $(DESIGN_DIR)/src/VX_ticket_lock.sv \
    $(DESIGN_DIR)/src/VX_opc_unit.sv \
    $(DESIGN_DIR)/src/VX_async_ram_patch.sv \
    $(DESIGN_DIR)/src/stream_join.sv \
    $(DESIGN_DIR)/src/pa_fpu_dp.v \
    $(DESIGN_DIR)/src/VX_fpu_cvt.sv \
    $(DESIGN_DIR)/src/VX_pe_serializer.sv \
    $(DESIGN_DIR)/src/VX_scoreboard.sv \
    $(DESIGN_DIR)/src/VX_axi_write_ack.sv \
    $(DESIGN_DIR)/src/VX_mem_bus_if.sv \
    $(DESIGN_DIR)/src/VX_fpu_dpi.sv \
    $(DESIGN_DIR)/src/addr_decode.sv \
    $(DESIGN_DIR)/src/stream_fork.sv \
    $(DESIGN_DIR)/src/edge_propagator.sv \
    $(DESIGN_DIR)/src/VX_ipdom_stack.sv \
    $(DESIGN_DIR)/src/VX_alu_muldiv.sv \
    $(DESIGN_DIR)/src/fpnew_opgroup_multifmt_slice.sv \
    $(DESIGN_DIR)/src/pa_fdsu_pack_single.v \
    $(DESIGN_DIR)/src/VX_lsu_mem_if.sv \
    $(DESIGN_DIR)/src/pa_fpu_src_type.v \
    $(DESIGN_DIR)/src/VX_sfu_unit.sv \
    $(DESIGN_DIR)/src/VX_scoreboard_if.sv \
    $(DESIGN_DIR)/src/cdc_fifo_gray.sv \
    $(DESIGN_DIR)/src/VX_fpu_dsp.sv \
    $(DESIGN_DIR)/src/VX_ibuffer.sv \
    $(DESIGN_DIR)/src/VX_index_queue.sv \
    $(DESIGN_DIR)/src/fpnew_fma_multi.sv \
    $(DESIGN_DIR)/src/max_counter.sv \
    $(DESIGN_DIR)/src/VX_mem_scheduler.sv \
    $(DESIGN_DIR)/src/VX_cache_cluster.sv \
    $(DESIGN_DIR)/src/VX_elastic_adapter.sv \
    $(DESIGN_DIR)/src/VX_alu_unit.sv \
    $(DESIGN_DIR)/src/mv_filter.sv \
    $(DESIGN_DIR)/src/VX_cache_bypass.sv \
    $(DESIGN_DIR)/src/VX_issue.sv \
    $(DESIGN_DIR)/src/ecc_encode.sv \
    $(DESIGN_DIR)/src/VX_popcount.sv \
    $(DESIGN_DIR)/src/VX_mem_arb.sv \
    $(DESIGN_DIR)/src/VX_csr_data.sv \
    $(DESIGN_DIR)/src/fifo_v3.sv \
    $(DESIGN_DIR)/src/VX_dispatch_if.sv \
    $(DESIGN_DIR)/src/stream_register.sv \
    $(DESIGN_DIR)/src/VX_result_if.sv \
    $(DESIGN_DIR)/src/VX_generic_arbiter.sv \
    $(DESIGN_DIR)/src/stream_demux.sv \
    $(DESIGN_DIR)/src/pa_fdsu_prepare.v \
    $(DESIGN_DIR)/src/VX_cache_mshr.sv \
    $(DESIGN_DIR)/src/VX_decode_sched_if.sv \
    $(DESIGN_DIR)/src/VX_stream_buffer.sv \
    $(DESIGN_DIR)/src/VX_pipe_register.sv \
    $(DESIGN_DIR)/src/VX_issue_sched_if.sv \
    $(DESIGN_DIR)/src/VX_serial_div.sv \
    $(DESIGN_DIR)/src/VX_cache_repl.sv \
    $(DESIGN_DIR)/src/VX_avs_adapter.sv \
    $(DESIGN_DIR)/src/VX_dcr_data.sv \
    $(DESIGN_DIR)/src/VX_fcvt_unit.sv \
    $(DESIGN_DIR)/src/VX_bits_remove.sv \
    $(DESIGN_DIR)/src/edge_propagator_rx.sv \
    $(DESIGN_DIR)/src/VX_lsu_adapter.sv \
    $(DESIGN_DIR)/src/VX_warp_ctl_if.sv \
    $(DESIGN_DIR)/src/VX_mem_unit.sv \
    $(DESIGN_DIR)/src/pa_fdsu_ctrl.v \
    $(DESIGN_DIR)/src/VX_cache_bank.sv \
    $(DESIGN_DIR)/src/VX_reset_relay.sv \
    $(DESIGN_DIR)/src/VX_fpu_fma.sv \
    $(DESIGN_DIR)/src/Vortex.sv \
    $(DESIGN_DIR)/src/VX_fpu_csr_if.sv \
    $(DESIGN_DIR)/src/pa_fdsu_special.v \
    $(DESIGN_DIR)/src/spill_register.sv \
    $(DESIGN_DIR)/src/fpnew_opgroup_fmt_slice.sv \
    $(DESIGN_DIR)/src/VX_execute.sv \
    $(DESIGN_DIR)/src/VX_multiplier.sv \
    $(DESIGN_DIR)/src/VX_stream_xbar.sv \
    $(DESIGN_DIR)/src/VX_dp_ram.sv \
    $(DESIGN_DIR)/src/VX_execute_if.sv \
    $(DESIGN_DIR)/src/VX_socket.sv \
    $(DESIGN_DIR)/src/VX_pe_switch.sv \
    $(DESIGN_DIR)/src/defs_div_sqrt_mvp.sv \
    $(DESIGN_DIR)/src/sync_wedge.sv \
    $(DESIGN_DIR)/src/VX_fp_classifier.sv \
    $(DESIGN_DIR)/src/VX_branch_ctl_if.sv \
    $(DESIGN_DIR)/src/stream_to_mem.sv \
    $(DESIGN_DIR)/src/rstgen.sv \
    $(PLATFORM_DIR)/verilog/fakeram7_2x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_4x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_8x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_16x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_32x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_64x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_128x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_256x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_512x32_be.v \
    $(PLATFORM_DIR)/verilog/fakeram7_1024x32_be.v
export SDC_FILE = $(DESIGN_DIR)/constraint.sdc
export ADDITIONAL_LEFS = \
    $(PLATFORM_DIR)/lef/fakeram7_2x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_4x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_8x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_16x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_32x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_64x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_128x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_256x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_512x32_be.lef \
    $(PLATFORM_DIR)/lef/fakeram7_1024x32_be.lef
export ADDITIONAL_LIBS = \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_2x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_4x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_8x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_16x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_32x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_64x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_128x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_256x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_512x32_be.lib \
    $(PLATFORM_DIR)/lib/NLDM/fakeram7_1024x32_be.lib
export PDN_TCL = $(DESIGN_DIR)/pdn.tcl
export CORE_UTILIZATION = 25
export PLACE_DENSITY = 0.40
export MACRO_PLACE_HALO = 4 4
export NUM_CORES = 4
export SYNTH_MEMORY_MAX_BITS = 131072
export GPL_TIMING_DRIVEN = 0  # Oct 25: timing-driven GPL hit RSZ-1008 (FixedDelay -inf); timing is repaired at CTS/GRT
# Oct 28: flat synthesis crashed in ABC (vecPtr.h:388 assertion, 5.3 h, 53 GB); hierarchical synthesis maps module by module
# Oct 31: util 25 / density 0.40 and the placement fix, as every other wide design
export GLOBAL_PLACEMENT_ARGS = -max_phi_coef 1.03
export GLOBAL_ROUTE_ARGS = -congestion_iterations 15 -congestion_report_iter_step 5 -verbose -allow_congestion
# Oct 31 (user): 32t_32w slang variant, a speed-mapped attempt beside the area variant (vortex_32t_32w_area_fpnew). ABC's speed
# script crashed three times on the flat sv2v netlist (sv2v folds the interface-port modules core/caches/issue into Vortex, so
# nothing could be kept). Here the same RTL (spr_eval/build/32t_32w_be_fpnew/src, the sv2v input, same defines as sources.txt) is
# read with the slang frontend, which keeps the module hierarchy, and modules above 50k gate equivalents are kept so ABC maps
# each separately. The netlist needs an equivalence check against project.v before its numbers are used.
export SYNTH_HDL_FRONTEND = slang
export VERILOG_DEFINES = -DSYNTHESIS -DYOSYS -DXLEN_32 -DUSE_FAKERAM -DFPU_FPNEW -DNUM_THREADS=32 -DNUM_WARPS=32
export VERILOG_INCLUDE_DIRS = $(DESIGN_DIR)/src
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE = 50000
# Oct 31: the five *_top.sv test tops and Vortex_axi.sv are left out (not in the Vortex tree; sv2v -tVortex dropped them too); slang rejected VX_issue_top hierarchical references
