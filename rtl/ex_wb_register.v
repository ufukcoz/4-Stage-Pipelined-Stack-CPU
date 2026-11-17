// -----------------------------------------------------------------------------
// ex_wb_register.v  --  Member C
//
// EX/WB pipeline register. Carries alu_result, stack_op and valid.
//
// Bubble definition (design decision #6): stack_op = NONE, valid = 0,
// alu_result = 0. The register is forced to a bubble on reset, on flush, and
// whenever the incoming EX entry is not valid. A bubble can never modify the
// stack.
// -----------------------------------------------------------------------------
`include "defs.vh"

module ex_wb_register #(
    parameter DATA_W = 16
) (
    input                       clk,
    input                       rst,            // synchronous, active high
    input                       flush,          // 1 = load a bubble

    // From the EX stage
    input  [DATA_W-1:0]         ex_alu_result,
    input  [2:0]                ex_stack_op,
    input                       ex_valid,

    // To the WB stage / hardware_stack
    output reg [DATA_W-1:0]     wb_alu_result,
    output reg [2:0]            wb_stack_op,
    output reg                  wb_valid
);

    always @(posedge clk) begin
        if (rst || flush || !ex_valid) begin
            wb_alu_result <= {DATA_W{1'b0}};
            wb_stack_op   <= `STACK_NONE;
            wb_valid      <= 1'b0;
        end else begin
            wb_alu_result <= ex_alu_result;
            wb_stack_op   <= ex_stack_op;
            wb_valid      <= 1'b1;
        end
    end

endmodule
