// -----------------------------------------------------------------------------
// defs.vh  --  FALLBACK VERSION (Member C)
//
// If the repository already has rtl/defs.vh, DO NOT overwrite it with this
// file. Instead, rename the four STACK_* macros used in hardware_stack.v,
// ex_wb_register.v and tb_stack.v to the names used in the real defs.vh.
//
// stack_op encoding is taken from the Detailed Design Report (Section 6).
// -----------------------------------------------------------------------------
`ifndef DEFS_VH
`define DEFS_VH

`ifndef STACK_NONE
`define STACK_NONE     3'b000   // no stack modification
`endif
`ifndef STACK_PUSH
`define STACK_PUSH     3'b001   // mem[SP] <= data, SP + 1
`endif
`ifndef STACK_POP1
`define STACK_POP1     3'b010   // SP - 1
`endif
`ifndef STACK_REPLACE2
`define STACK_REPLACE2 3'b011   // mem[SP-2] <= result, SP - 1
`endif

`endif
