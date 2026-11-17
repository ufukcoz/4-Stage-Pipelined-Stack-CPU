// -----------------------------------------------------------------------------
// wb_stage.v  --  Member C
//
// WB stage wrapper: EX/WB register + hardware stack.
// Member A may instantiate this module in top_stack_cpu.v, or instantiate
// ex_wb_register and hardware_stack separately -- the signals are the same.
//
//   EX stage --> [ex_wb_register] --> wb_data / wb_stack_op / wb_valid
//                                          |
//                                          v
//                                  [hardware_stack] --> tos, nos, depth ...
// -----------------------------------------------------------------------------
module wb_stage #(
    parameter DATA_W = 16
) (
    input                   clk,
    input                   rst,
    input                   flush,          // bubble into EX/WB (normally tied to 0)
    input                   freeze,         // control FSM in S_ERROR

    // From the EX stage
    input  [DATA_W-1:0]     ex_alu_result,
    input  [2:0]            ex_stack_op,
    input                   ex_valid,

    // To ID / control unit
    output [DATA_W-1:0]     tos,
    output [DATA_W-1:0]     nos,
    output                  empty,
    output                  full,
    output [4:0]            stack_depth,
    output [4:0]            depth_eff,
    output                  underflow_err,
    output                  overflow_err
);

    wire [DATA_W-1:0] wb_data;
    wire [2:0]        wb_stack_op;
    wire              wb_valid;

    ex_wb_register #(.DATA_W(DATA_W)) u_ex_wb (
        .clk           (clk),
        .rst           (rst),
        .flush         (flush),
        .ex_alu_result (ex_alu_result),
        .ex_stack_op   (ex_stack_op),
        .ex_valid      (ex_valid),
        .wb_alu_result (wb_data),
        .wb_stack_op   (wb_stack_op),
        .wb_valid      (wb_valid)
    );

    hardware_stack #(.DATA_W(DATA_W)) u_stack (
        .clk           (clk),
        .rst           (rst),
        .freeze        (freeze),
        .valid         (wb_valid),
        .stack_op      (wb_stack_op),
        .wb_data       (wb_data),
        .ex_valid      (ex_valid),
        .ex_stack_op   (ex_stack_op),
        .tos           (tos),
        .nos           (nos),
        .empty         (empty),
        .full          (full),
        .stack_depth   (stack_depth),
        .depth_eff     (depth_eff),
        .underflow_err (underflow_err),
        .overflow_err  (overflow_err)
    );

endmodule
