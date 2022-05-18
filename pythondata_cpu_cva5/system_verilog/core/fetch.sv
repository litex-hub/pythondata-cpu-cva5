/*
 * Copyright © 2017-2019 Eric Matthews,  Lesley Shannon
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Initial code developed under the supervision of Dr. Lesley Shannon,
 * Reconfigurable Computing Lab, Simon Fraser University.
 *
 * Author(s):
 *             Eric Matthews <ematthew@sfu.ca>
 */

module fetch

    import cva5_config::*;
    import riscv_types::*;
    import cva5_types::*;

    # (
        parameter cpu_config_t CONFIG = EXAMPLE_CONFIG
    )

    (
        input logic clk,
        input logic rst,

        input logic branch_flush,
        input gc_outputs_t gc,
        input logic tlb_on,
        input logic exception,

        //ID Support
        input id_t pc_id,
        input logic pc_id_available,
        output logic pc_id_assigned,
        output logic fetch_complete,
        output fetch_metadata_t fetch_metadata,

        branch_predictor_interface.fetch bp,
        ras_interface.fetch ras,

        //Instruction Metadata
        output logic early_branch_flush,
        output logic early_branch_flush_ras_adjust,
        output logic [31:0] if_pc,
        output logic [31:0] fetch_instruction,

        tlb_interface.requester tlb,
        local_memory_interface.master instruction_bram,
        wishbone_interface.master iwishbone,
        input logic icache_on,
        l1_arbiter_request_interface.master l1_request,
        l1_arbiter_return_interface.master l1_response,

        //Trace Interface
        output logic tr_early_branch_correction
    );

    localparam NUM_SUB_UNITS = int'(CONFIG.INCLUDE_ILOCAL_MEM) + int'(CONFIG.INCLUDE_ICACHE) + int'(CONFIG.INCLUDE_IBUS);
    localparam NUM_SUB_UNITS_W = (NUM_SUB_UNITS == 1) ? 1 : $clog2(NUM_SUB_UNITS);

    localparam LOCAL_MEM_ID = 0;
    localparam ICACHE_ID = int'(CONFIG.INCLUDE_ILOCAL_MEM);
    localparam BUS_ID = ICACHE_ID + int'(CONFIG.INCLUDE_ICACHE);

    localparam MAX_OUTSTANDING_REQUESTS = 2;
    localparam MAX_OUTSTANDING_REQUESTS_W = $clog2(MAX_OUTSTANDING_REQUESTS);
    //Subunit signals
    addr_utils_interface #(CONFIG.ILOCAL_MEM_ADDR.L, CONFIG.ILOCAL_MEM_ADDR.H) ilocal_mem_addr_utils ();
    addr_utils_interface #(CONFIG.ICACHE_ADDR.L, CONFIG.ICACHE_ADDR.H) icache_addr_utils ();
    addr_utils_interface #(CONFIG.IBUS_ADDR.L, CONFIG.IBUS_ADDR.H) ibus_addr_utils ();

    memory_sub_unit_interface sub_unit[NUM_SUB_UNITS-1:0]();

    logic [NUM_SUB_UNITS-1:0] sub_unit_address_match;
    logic [NUM_SUB_UNITS-1:0] unit_ready;
    logic [NUM_SUB_UNITS-1:0] unit_data_valid;
    logic [31:0] unit_data_array [NUM_SUB_UNITS-1:0];

    logic units_ready;
    logic address_valid;

    typedef struct packed{
        logic is_predicted_branch_or_jump;
        logic is_branch;
        logic address_valid;
        logic mmu_fault;
        logic [NUM_SUB_UNITS_W-1:0] subunit_id;
    } fetch_attributes_t;
    fetch_attributes_t fetch_attr_next;
    fetch_attributes_t fetch_attr;

    logic [MAX_OUTSTANDING_REQUESTS_W:0] inflight_count;
    logic [MAX_OUTSTANDING_REQUESTS_W:0] inflight_count_next;
    logic [MAX_OUTSTANDING_REQUESTS_W:0] flush_count;
    logic [MAX_OUTSTANDING_REQUESTS_W:0] flush_count_next;


    logic [31:0] pc_plus_4;
    logic [31:0] pc_mux [4];
    logic [1:0] pc_sel;
    logic [31:0] next_pc;
    logic [31:0] pc;

    logic flush_or_rst;
    fifo_interface #(.DATA_WIDTH($bits(fetch_attributes_t))) fetch_attr_fifo();

    logic update_pc;
    logic new_mem_request;
    logic exception_pending;
    logic internal_fetch_complete;

    logic [31:0] translated_address;

    genvar i;
    ////////////////////////////////////////////////////
    //Implementation
    ////////////////////////////////////////////////////
    //Fetch PC
    assign update_pc = new_mem_request | gc.fetch_flush | early_branch_flush;
    always_ff @(posedge clk) begin
        if (gc.init_clear)
            pc <= CONFIG.CSRS.RESET_VEC;
        else if (update_pc)
            pc <= {next_pc[31:2], 2'b0};
    end

    assign pc_plus_4 = pc + 4;

    priority_encoder #(.WIDTH(4))
    pc_sel_encoder (
        .priority_vector ({1'b1, (bp.use_prediction & ~early_branch_flush), branch_flush, gc.pc_override}),
        .encoded_result (pc_sel)
    );
    assign pc_mux[0] = gc.pc;
    assign pc_mux[1] = bp.branch_flush_pc;
    assign pc_mux[2] = bp.is_return ? ras.addr : bp.predicted_pc;
    assign pc_mux[3] = pc_plus_4;
    assign next_pc = pc_mux[pc_sel];

    //If an exception occurs here in the fetch logic,
    //hold the fetching of data from memory until the status of the
    //exception has been resolved
    always_ff @(posedge clk) begin
        if (flush_or_rst)
            exception_pending <= 0;
        else if (tlb.is_fault | (new_mem_request & ~address_valid))
            exception_pending <= 1;
    end

    assign bp.new_mem_request = update_pc;
    assign bp.next_pc = next_pc;
    assign bp.if_pc = pc;
    assign bp.pc_id = pc_id;
    assign bp.pc_id_assigned = pc_id_assigned;

    assign ras.pop = bp.use_prediction & bp.is_return & ~branch_flush & ~gc.pc_override & new_mem_request & (~early_branch_flush);
    assign ras.push = bp.use_prediction & bp.is_call & ~branch_flush & ~gc.pc_override & new_mem_request & (~early_branch_flush);
    assign ras.new_addr = pc_plus_4;
    assign ras.branch_fetched = bp.use_prediction & bp.is_branch & new_mem_request & (~early_branch_flush); //flush not needed as FIFO resets inside of RAS

    ////////////////////////////////////////////////////
    //TLB
    assign tlb.virtual_address = pc;
    assign tlb.execute = 1;
    assign tlb.rnw = 0;
    assign tlb.new_request = tlb.ready & (CONFIG.INCLUDE_S_MODE & tlb_on);
    assign translated_address = (CONFIG.INCLUDE_S_MODE & tlb_on) ? tlb.physical_address : pc;

    //////////////////////////////////////////////
    //Issue Control Signals
    assign flush_or_rst = (rst | gc.fetch_flush | early_branch_flush);

    assign new_mem_request = (~tlb_on | tlb.done) & pc_id_available & ~fetch_attr_fifo.full & units_ready & (~gc.fetch_hold) & (~exception_pending);
    assign pc_id_assigned = new_mem_request | tlb.is_fault;

    //////////////////////////////////////////////
    //Subunit Tracking
    assign fetch_attr_fifo.push = pc_id_assigned;
    assign fetch_attr_fifo.potential_push = pc_id_assigned;
    assign fetch_attr_fifo.pop = internal_fetch_complete;
    one_hot_to_integer #(NUM_SUB_UNITS)
    hit_way_conv (
        .one_hot (sub_unit_address_match), 
        .int_out (fetch_attr_next.subunit_id)
    );
    assign fetch_attr_next.is_predicted_branch_or_jump = bp.use_prediction;
    assign fetch_attr_next.is_branch = bp.use_prediction & bp.is_branch;
    assign fetch_attr_next.address_valid = address_valid;
    assign fetch_attr_next.mmu_fault = tlb.is_fault;

    assign fetch_attr_fifo.data_in = fetch_attr_next;

    cva5_fifo #(.DATA_WIDTH($bits(fetch_attributes_t)), .FIFO_DEPTH(MAX_OUTSTANDING_REQUESTS))
    attributes_fifo (
        .clk (clk), 
        .rst (rst), 
        .fifo (fetch_attr_fifo)
    );

    assign fetch_attr = fetch_attr_fifo.data_out;

    assign inflight_count_next = inflight_count + MAX_OUTSTANDING_REQUESTS_W'(fetch_attr_fifo.push) - MAX_OUTSTANDING_REQUESTS_W'(fetch_attr_fifo.pop);
    always_ff @(posedge clk) begin
        if (rst)
            inflight_count <= 0;
        else
            inflight_count <=  inflight_count_next;
    end

    always_ff @(posedge clk) begin
        if (rst)
            flush_count <= 0;
        else if (gc.fetch_flush)
            flush_count <= inflight_count_next;
        else if (|flush_count & fetch_attr_fifo.pop)
            flush_count <= flush_count - 1;
    end

    ////////////////////////////////////////////////////
    //Subunit Interfaces
    //In the case of a gc.fetch_flush, a request may already be in progress
    //for any sub unit.  That request can either be completed or aborted.
    //In either case, data_valid must NOT be asserted.
    generate for (i=0; i < NUM_SUB_UNITS; i++) begin : gen_fetch_sources
        assign sub_unit[i].new_request = fetch_attr_fifo.push & sub_unit_address_match[i];
        assign sub_unit[i].addr = translated_address;
        assign sub_unit[i].re = 1;
        assign sub_unit[i].we = 0;
        assign sub_unit[i].be = '0;
        assign sub_unit[i].data_in = '0;

        assign unit_ready[i] = sub_unit[i].ready;
        assign unit_data_valid[i] = sub_unit[i].data_valid;
        assign unit_data_array[i] = sub_unit[i].data_out;
    end
    endgenerate

    generate if (CONFIG.INCLUDE_ILOCAL_MEM) begin : gen_fetch_local_mem
        assign sub_unit_address_match[LOCAL_MEM_ID] = ilocal_mem_addr_utils.address_range_check(translated_address);
        local_mem_sub_unit i_local_mem (
            .clk (clk), 
            .rst (rst),
            .unit (sub_unit[LOCAL_MEM_ID]),
            .local_mem (instruction_bram)
        );
    end
    endgenerate

    generate if (CONFIG.INCLUDE_IBUS) begin : gen_fetch_ibus
        assign sub_unit_address_match[BUS_ID] = ibus_addr_utils.address_range_check(translated_address);
        wishbone_master iwishbone_bus (
            .clk (clk),
            .rst (rst),
            .wishbone (iwishbone),
            .ls (sub_unit[BUS_ID])
        );
    end
    endgenerate

    generate if (CONFIG.INCLUDE_ICACHE) begin : gen_fetch_icache
        assign sub_unit_address_match[ICACHE_ID] = icache_addr_utils.address_range_check(translated_address);
        icache #(.CONFIG(CONFIG))
        i_cache (
            .clk (clk), 
            .rst (rst),
            .gc (gc),
            .icache_on (icache_on),
            .l1_request (l1_request),
            .l1_response (l1_response),
            .fetch_sub (sub_unit[ICACHE_ID])
        );
    end
    endgenerate

    assign units_ready = &unit_ready;
    assign address_valid = |sub_unit_address_match;

    ////////////////////////////////////////////////////
    //Instruction metada updates
    logic valid_fetch_result;
    assign valid_fetch_result = CONFIG.INCLUDE_M_MODE ? (fetch_attr_fifo.valid & fetch_attr.address_valid & (~fetch_attr.mmu_fault)) : 1;

    assign if_pc = pc;
    assign fetch_metadata.ok = valid_fetch_result;
    assign fetch_metadata.error_code = INST_ACCESS_FAULT;

    assign fetch_instruction = unit_data_array[fetch_attr.subunit_id];

    assign internal_fetch_complete = fetch_attr_fifo.valid & (fetch_attr.address_valid ? |unit_data_valid : ~valid_fetch_result);//allow instruction to propagate to decode if address is invalid
    assign fetch_complete = internal_fetch_complete & ~|flush_count;

    ////////////////////////////////////////////////////
    //Branch Predictor corruption check
    //Needed if instruction memory is changed after any branches have been executed
    generate if (CONFIG.INCLUDE_IFENCE | CONFIG.INCLUDE_S_MODE) begin : gen_branch_corruption_check
        logic is_branch_or_jump;
        assign is_branch_or_jump = fetch_instruction[6:2] inside {JAL_T, JALR_T, BRANCH_T};
        assign early_branch_flush = (valid_fetch_result & (|unit_data_valid)) & fetch_attr.is_predicted_branch_or_jump & (~is_branch_or_jump);
        assign early_branch_flush_ras_adjust = (valid_fetch_result & (|unit_data_valid)) & fetch_attr.is_branch & (~is_branch_or_jump);
        if (ENABLE_TRACE_INTERFACE)
            assign tr_early_branch_correction = early_branch_flush;
    end endgenerate
    ////////////////////////////////////////////////////
    //End of Implementation
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    //Assertions
    spurious_fetch_complete_assertion:
        assert property (@(posedge clk) disable iff (rst) (|unit_data_valid) |-> (fetch_attr_fifo.valid && unit_data_valid[fetch_attr.subunit_id]))
        else $error("Spurious fetch complete detected!");

endmodule
