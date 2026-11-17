// -----------------------------------------------------------------------------
// hardware_stack.v  --  Member C
//
// 16 x 16-bit hardware stack with write-through reads.
//
//   * SP points to the NEXT EMPTY slot.  TOS = mem[SP-1], NOS = mem[SP-2].
//   * The stack is updated in the WB stage (synchronous write, rising edge).
//   * tos / nos are combinational and already show the stack AS IT WILL BE
//     after the WB operation of the current cycle (write-through), so the
//     instruction in ID sees the WB result in the same cycle.
//   * stack_depth / empty / full describe the registered state (SP).
//   * depth_eff = depth after the WB operation of this cycle, plus the effect
//     of the instruction currently in EX (design decision #3).
//   * underflow_err / overflow_err are combinational flags that report an
//     ILLEGAL valid WB operation. The illegal operation is suppressed (the
//     stack is not modified); the control FSM latches the error.
//   * freeze = 1 (control FSM in S_ERROR) blocks every stack modification.
//     rst has priority over freeze (only reset leaves ERROR).
//   * valid = 0 (bubble) never modifies the stack and never raises an error.
// -----------------------------------------------------------------------------
`include "defs.vh"

module hardware_stack #(
    parameter DATA_W = 16
) (
    input                   clk,
    input                   rst,          // synchronous, active high
    input                   freeze,       // 1 = stack frozen (ERROR state)

    // Write port (from the EX/WB register)
    input                   valid,        // 0 = bubble, ignore stack_op
    input  [2:0]            stack_op,
    input  [DATA_W-1:0]     wb_data,      // alu_result of the WB instruction

    // Instruction currently in EX (only used for depth_eff)
    input                   ex_valid,
    input  [2:0]            ex_stack_op,

    // Read port (to ID / ID-EX register), combinational + write-through
    output [DATA_W-1:0]     tos,
    output [DATA_W-1:0]     nos,

    // Status (to the control unit)
    output                  empty,
    output                  full,
    output [4:0]            stack_depth,  // registered depth (= SP)
    output [4:0]            depth_eff,    // effective depth for hazard/error checks
    output                  underflow_err,
    output                  overflow_err
);

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    reg [DATA_W-1:0] mem [0:15];
    reg [4:0]        sp;                 // next empty slot, 0..16
    integer          i;

    wire [4:0] sp_m1 = sp - 5'd1;
    wire [4:0] sp_m2 = sp - 5'd2;
    wire [4:0] sp_m3 = sp - 5'd3;

    // ------------------------------------------------------------------
    // Registered-state view of the top three elements (0 when not present)
    // ------------------------------------------------------------------
    wire [DATA_W-1:0] mem_rd1 = mem[sp_m1[3:0]];
    wire [DATA_W-1:0] mem_rd2 = mem[sp_m2[3:0]];
    wire [DATA_W-1:0] mem_rd3 = mem[sp_m3[3:0]];

    wire [DATA_W-1:0] old_tos   = (sp >= 5'd1) ? mem_rd1 : {DATA_W{1'b0}};
    wire [DATA_W-1:0] old_nos   = (sp >= 5'd2) ? mem_rd2 : {DATA_W{1'b0}};
    wire [DATA_W-1:0] old_third = (sp >= 5'd3) ? mem_rd3 : {DATA_W{1'b0}};

    // ------------------------------------------------------------------
    // Operation decode and boundary checks
    // ------------------------------------------------------------------
    wire op_push = valid && (stack_op == `STACK_PUSH);
    wire op_pop1 = valid && (stack_op == `STACK_POP1);
    wire op_rep2 = valid && (stack_op == `STACK_REPLACE2);

    // Illegal operations (reported even though they are suppressed)
    assign underflow_err = (op_pop1 && (sp < 5'd1)) ||
                           (op_rep2 && (sp < 5'd2));
    assign overflow_err  =  op_push && (sp == 5'd16);

    // Legal operations that really modify the stack
    wire do_push = !freeze && op_push && (sp != 5'd16);
    wire do_pop1 = !freeze && op_pop1 && (sp >= 5'd1);
    wire do_rep2 = !freeze && op_rep2 && (sp >= 5'd2);

    // ------------------------------------------------------------------
    // Next state (combinational) -- also used for write-through reads
    // ------------------------------------------------------------------
    reg [4:0]        sp_next;
    reg [DATA_W-1:0] tos_next;
    reg [DATA_W-1:0] nos_next;

    always @* begin
        // defaults: no change
        sp_next  = sp;
        tos_next = old_tos;
        nos_next = old_nos;

        if (do_push) begin
            sp_next  = sp + 5'd1;
            tos_next = wb_data;
            nos_next = old_tos;
        end else if (do_pop1) begin
            sp_next  = sp - 5'd1;
            tos_next = old_nos;
            nos_next = old_third;
        end else if (do_rep2) begin
            sp_next  = sp - 5'd1;
            tos_next = wb_data;
            nos_next = old_third;
        end
    end

    assign tos = tos_next;
    assign nos = nos_next;

    // ------------------------------------------------------------------
    // Status outputs
    // ------------------------------------------------------------------
    assign stack_depth = sp;
    assign empty       = (sp == 5'd0);
    assign full        = (sp == 5'd16);

    // depth_eff = depth after WB + effect of the instruction in EX
    wire ex_inc = ex_valid && (ex_stack_op == `STACK_PUSH);
    wire ex_dec = ex_valid && ((ex_stack_op == `STACK_POP1) ||
                               (ex_stack_op == `STACK_REPLACE2));

    reg [4:0] depth_eff_r;
    always @* begin
        depth_eff_r = sp_next;
        if (ex_inc)
            depth_eff_r = sp_next + 5'd1;
        else if (ex_dec && (sp_next != 5'd0))
            depth_eff_r = sp_next - 5'd1;      // clamp at 0
    end
    assign depth_eff = depth_eff_r;

    // ------------------------------------------------------------------
    // Sequential update (WB stage)
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            sp <= 5'd0;
            for (i = 0; i < 16; i = i + 1)
                mem[i] <= {DATA_W{1'b0}};
        end else begin
            if (do_push)
                mem[sp[3:0]] <= wb_data;
            else if (do_rep2)
                mem[sp_m2[3:0]] <= wb_data;
            sp <= sp_next;
        end
    end

endmodule
