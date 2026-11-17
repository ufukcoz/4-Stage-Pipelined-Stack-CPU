// -----------------------------------------------------------------------------
// tb_stack.v  --  Member C self-checking testbench
//
// DUT 1: hardware_stack  (driven directly, WB-side signals)
// DUT 2: wb_stage        (EX/WB register + stack, driven from the EX side)
//
// Timing convention:
//   * inputs change 1 time unit after a rising edge (never at the edge)
//   * "drive" sets inputs, waits 1 unit, then combinational outputs
//     (write-through tos/nos, depth_eff, error flags) are checked
//   * "tick" waits for the next rising edge, then returns all per-cycle
//     inputs to idle; registered outputs are checked afterwards
// Prints "ALL TESTS PASSED" or a message naming the failed checks.
// -----------------------------------------------------------------------------
`include "defs.vh"

module tb_stack;

    // ---------------- clock ----------------
    reg clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------- DUT 1 : hardware_stack ----------------
    reg         rst, freeze, valid, ex_valid;
    reg  [2:0]  stack_op, ex_stack_op;
    reg  [15:0] wb_data;
    wire [15:0] tos, nos;
    wire        empty, full, underflow_err, overflow_err;
    wire [4:0]  stack_depth, depth_eff;

    hardware_stack dut (
        .clk(clk), .rst(rst), .freeze(freeze),
        .valid(valid), .stack_op(stack_op), .wb_data(wb_data),
        .ex_valid(ex_valid), .ex_stack_op(ex_stack_op),
        .tos(tos), .nos(nos), .empty(empty), .full(full),
        .stack_depth(stack_depth), .depth_eff(depth_eff),
        .underflow_err(underflow_err), .overflow_err(overflow_err)
    );

    // ---------------- DUT 2 : wb_stage ----------------
    reg         w_rst, w_flush, w_freeze, w_ex_valid;
    reg  [2:0]  w_ex_op;
    reg  [15:0] w_ex_alu;
    wire [15:0] w_tos, w_nos;
    wire        w_empty, w_full, w_uf, w_of;
    wire [4:0]  w_depth, w_depth_eff;

    wb_stage wdut (
        .clk(clk), .rst(w_rst), .flush(w_flush), .freeze(w_freeze),
        .ex_alu_result(w_ex_alu), .ex_stack_op(w_ex_op), .ex_valid(w_ex_valid),
        .tos(w_tos), .nos(w_nos), .empty(w_empty), .full(w_full),
        .stack_depth(w_depth), .depth_eff(w_depth_eff),
        .underflow_err(w_uf), .overflow_err(w_of)
    );

    // ---------------- bookkeeping ----------------
    integer errors;
    integer checks;
    reg [8*40-1:0] cur_test;

    task chk;
        input [8*24-1:0] what;
        input [15:0]     actual;
        input [15:0]     expected;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0s] %0s: got 0x%h, expected 0x%h (time %0t)",
                         cur_test, what, actual, expected, $time);
            end
        end
    endtask

    // Wait for the next rising edge, then put all per-cycle inputs to idle.
    task tick;
        begin
            @(posedge clk);
            #1;
            valid       = 1'b0;
            stack_op    = `STACK_NONE;
            wb_data     = 16'h0000;
            ex_valid    = 1'b0;
            ex_stack_op = `STACK_NONE;
            w_ex_valid  = 1'b0;
            w_ex_op     = `STACK_NONE;
            w_ex_alu    = 16'h0000;
        end
    endtask

    // Apply reset to both DUTs for one clock edge.
    task do_reset;
        begin
            rst   = 1'b1;
            w_rst = 1'b1;
            tick;
            rst   = 1'b0;
            w_rst = 1'b0;
        end
    endtask

    // Set the WB-side inputs of DUT 1 and let combinational logic settle.
    task drive;
        input        v;
        input [2:0]  op;
        input [15:0] data;
        begin
            valid    = v;
            stack_op = op;
            wb_data  = data;
            #1;
        end
    endtask

    // One full WB operation on DUT 1 with write-through and state checks.
    //   exp_* describe the stack AFTER the operation (also what the
    //   write-through outputs must show BEFORE the clock edge).
    task do_op;
        input        v;
        input [2:0]  op;
        input [15:0] data;
        input        exp_uf;
        input        exp_of;
        input [4:0]  exp_d;
        input [15:0] exp_t;
        input [15:0] exp_n;
        begin
            drive(v, op, data);
            // combinational view, before the clock edge
            chk("wt depth_eff",   depth_eff,     exp_d);
            chk("wt tos",         tos,           exp_t);
            chk("wt nos",         nos,           exp_n);
            chk("underflow_err",  underflow_err, exp_uf);
            chk("overflow_err",   overflow_err,  exp_of);
            tick;
            // registered view, after the clock edge (inputs idle again)
            chk("depth",          stack_depth,   exp_d);
            chk("tos",            tos,           exp_t);
            chk("nos",            nos,           exp_n);
            chk("empty",          empty,         (exp_d == 5'd0));
            chk("full",           full,          (exp_d == 5'd16));
            chk("underflow idle", underflow_err, 16'h0000);
            chk("overflow idle",  overflow_err,  16'h0000);
        end
    endtask

    // State check with idle inputs (registered state only).
    task expect_state;
        input [4:0]  exp_d;
        input [15:0] exp_t;
        input [15:0] exp_n;
        begin
            #1;
            chk("depth",         stack_depth,   exp_d);
            chk("tos",           tos,           exp_t);
            chk("nos",           nos,           exp_n);
            chk("empty",         empty,         (exp_d == 5'd0));
            chk("full",          full,          (exp_d == 5'd16));
            chk("underflow_err", underflow_err, 16'h0000);
            chk("overflow_err",  overflow_err,  16'h0000);
        end
    endtask

    // Push 16 values 0x0101 .. 0x0110 (stack becomes full).
    task fill_stack;
        integer k;
        begin
            for (k = 1; k <= 16; k = k + 1)
                do_op(1'b1, `STACK_PUSH, 16'h0100 + k, 1'b0, 1'b0,
                      k, 16'h0100 + k,
                      (k == 1) ? 16'h0000 : (16'h0100 + k - 1));
        end
    endtask

    // ---------------- watchdog ----------------
    initial begin
        #200000;
        $display("FAIL: testbench timeout");
        $finish;
    end

    // ---------------- main sequence ----------------
    initial begin
        $dumpfile("tb_stack.vcd");
        $dumpvars(0, tb_stack);

        errors = 0;
        checks = 0;
        cur_test = "init";

        rst = 1'b1;  freeze = 1'b0;
        valid = 1'b0; stack_op = `STACK_NONE; wb_data = 16'h0000;
        ex_valid = 1'b0; ex_stack_op = `STACK_NONE;
        w_rst = 1'b1; w_flush = 1'b0; w_freeze = 1'b0;
        w_ex_valid = 1'b0; w_ex_op = `STACK_NONE; w_ex_alu = 16'h0000;

        // power-up reset
        tick;
        rst = 1'b0; w_rst = 1'b0;

        // ---------------------------------------------------------
        cur_test = "T1 reset / T2 initial empty";
        expect_state(5'd0, 16'h0000, 16'h0000);
        // data written before a reset must be gone afterwards
        do_op(1'b1, `STACK_PUSH, 16'hAAAA, 1'b0, 1'b0, 5'd1, 16'hAAAA, 16'h0000);
        do_op(1'b1, `STACK_PUSH, 16'hBBBB, 1'b0, 1'b0, 5'd2, 16'hBBBB, 16'hAAAA);
        do_reset;
        expect_state(5'd0, 16'h0000, 16'h0000);

        // ---------------------------------------------------------
        cur_test = "T3 single PUSH";
        do_op(1'b1, `STACK_PUSH, 16'h00A1, 1'b0, 1'b0, 5'd1, 16'h00A1, 16'h0000);

        cur_test = "T4/T5 multiple PUSH, TOS/NOS";
        do_op(1'b1, `STACK_PUSH, 16'h00B2, 1'b0, 1'b0, 5'd2, 16'h00B2, 16'h00A1);
        do_op(1'b1, `STACK_PUSH, 16'h00C3, 1'b0, 1'b0, 5'd3, 16'h00C3, 16'h00B2);
        do_op(1'b1, `STACK_PUSH, 16'h00D4, 1'b0, 1'b0, 5'd4, 16'h00D4, 16'h00C3);

        cur_test = "T6 POP1";
        do_op(1'b1, `STACK_POP1, 16'h0000, 1'b0, 1'b0, 5'd3, 16'h00C3, 16'h00B2);

        cur_test = "T7 REPLACE2";
        do_op(1'b1, `STACK_REPLACE2, 16'h00FF, 1'b0, 1'b0, 5'd2, 16'h00FF, 16'h00A1);
        do_op(1'b1, `STACK_REPLACE2, 16'h0123, 1'b0, 1'b0, 5'd1, 16'h0123, 16'h0000);
        // memory really holds the replaced value
        do_op(1'b1, `STACK_PUSH, 16'h0456, 1'b0, 1'b0, 5'd2, 16'h0456, 16'h0123);
        do_op(1'b1, `STACK_POP1, 16'h0000, 1'b0, 1'b0, 5'd1, 16'h0123, 16'h0000);

        cur_test = "T9 depth tracking down to empty";
        do_op(1'b1, `STACK_POP1, 16'h0000, 1'b0, 1'b0, 5'd0, 16'h0000, 16'h0000);

        // ---------------------------------------------------------
        cur_test = "T8 write-through (PUSH 7, PUSH 3, SUB=4)";
        do_op(1'b1, `STACK_PUSH,     16'h0007, 1'b0, 1'b0, 5'd1, 16'h0007, 16'h0000);
        do_op(1'b1, `STACK_PUSH,     16'h0003, 1'b0, 1'b0, 5'd2, 16'h0003, 16'h0007);
        do_op(1'b1, `STACK_REPLACE2, 16'h0004, 1'b0, 1'b0, 5'd1, 16'h0004, 16'h0000);
        do_op(1'b1, `STACK_POP1,     16'h0000, 1'b0, 1'b0, 5'd0, 16'h0000, 16'h0000);

        // ---------------------------------------------------------
        cur_test = "T10 full detection (depth 16)";
        do_reset;
        fill_stack;
        chk("full flag", full,  16'h0001);
        chk("empty flag", empty, 16'h0000);
        chk("depth 16", stack_depth, 16'd16);

        cur_test = "T11 overflow detection";
        do_op(1'b1, `STACK_PUSH, 16'hDEAD, 1'b0, 1'b1, 5'd16, 16'h0110, 16'h010F);

        cur_test = "T13 boundary depth 16 <-> 15";
        do_op(1'b1, `STACK_REPLACE2, 16'h0BEE, 1'b0, 1'b0, 5'd15, 16'h0BEE, 16'h010E);
        do_op(1'b1, `STACK_PUSH,     16'h0556, 1'b0, 1'b0, 5'd16, 16'h0556, 16'h0BEE);
        do_op(1'b1, `STACK_POP1,     16'h0000, 1'b0, 1'b0, 5'd15, 16'h0BEE, 16'h010E);

        // ---------------------------------------------------------
        cur_test = "T12/T13 underflow at depth 0 and 1";
        do_reset;
        do_op(1'b1, `STACK_POP1,     16'h0000, 1'b1, 1'b0, 5'd0, 16'h0000, 16'h0000);
        do_op(1'b1, `STACK_REPLACE2, 16'h1111, 1'b1, 1'b0, 5'd0, 16'h0000, 16'h0000);
        do_op(1'b1, `STACK_PUSH,     16'h0042, 1'b0, 1'b0, 5'd1, 16'h0042, 16'h0000);
        // arithmetic operation with only one element must be rejected
        do_op(1'b1, `STACK_REPLACE2, 16'h2222, 1'b1, 1'b0, 5'd1, 16'h0042, 16'h0000);
        do_op(1'b1, `STACK_POP1,     16'h0000, 1'b0, 1'b0, 5'd0, 16'h0000, 16'h0000);

        // ---------------------------------------------------------
        cur_test = "T14 frozen (ERROR) stack";
        do_reset;
        do_op(1'b1, `STACK_PUSH, 16'h0011, 1'b0, 1'b0, 5'd1, 16'h0011, 16'h0000);
        do_op(1'b1, `STACK_PUSH, 16'h0022, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        freeze = 1'b1;
        do_op(1'b1, `STACK_PUSH,     16'h0033, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        do_op(1'b1, `STACK_POP1,     16'h0000, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        do_op(1'b1, `STACK_REPLACE2, 16'h0044, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        // only reset leaves the frozen state
        do_reset;
        expect_state(5'd0, 16'h0000, 16'h0000);
        freeze = 1'b0;
        // stack works again after unfreeze
        do_op(1'b1, `STACK_PUSH, 16'h0055, 1'b0, 1'b0, 5'd1, 16'h0055, 16'h0000);

        // ---------------------------------------------------------
        cur_test = "T15 bubbles do not modify the stack";
        do_reset;
        do_op(1'b1, `STACK_PUSH, 16'h0011, 1'b0, 1'b0, 5'd1, 16'h0011, 16'h0000);
        do_op(1'b1, `STACK_PUSH, 16'h0022, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        do_op(1'b0, `STACK_PUSH,     16'hDEAD, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        do_op(1'b0, `STACK_POP1,     16'hDEAD, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        do_op(1'b0, `STACK_REPLACE2, 16'hDEAD, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        // valid entry with NONE leaves the stack alone as well
        do_op(1'b1, `STACK_NONE,     16'hBEEF, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        // bubbles must not raise errors on empty / full stacks
        do_reset;
        do_op(1'b0, `STACK_POP1,     16'h0000, 1'b0, 1'b0, 5'd0, 16'h0000, 16'h0000);
        do_op(1'b0, `STACK_REPLACE2, 16'h0000, 1'b0, 1'b0, 5'd0, 16'h0000, 16'h0000);
        fill_stack;
        do_op(1'b0, `STACK_PUSH,     16'hDEAD, 1'b0, 1'b0, 5'd16, 16'h0110, 16'h010F);

        // ---------------------------------------------------------
        cur_test = "T16 depth_eff includes EX instruction";
        do_reset;
        do_op(1'b1, `STACK_PUSH, 16'h0011, 1'b0, 1'b0, 5'd1, 16'h0011, 16'h0000);
        do_op(1'b1, `STACK_PUSH, 16'h0022, 1'b0, 1'b0, 5'd2, 16'h0022, 16'h0011);
        // depth 2, nothing in EX
        #1; chk("no EX", depth_eff, 16'd2);
        ex_valid = 1'b1; ex_stack_op = `STACK_PUSH;     #1;
        chk("EX PUSH",     depth_eff, 16'd3);
        ex_stack_op = `STACK_POP1;                      #1;
        chk("EX POP1",     depth_eff, 16'd1);
        ex_stack_op = `STACK_REPLACE2;                  #1;
        chk("EX REPLACE2", depth_eff, 16'd1);
        ex_stack_op = `STACK_NONE;                      #1;
        chk("EX NONE",     depth_eff, 16'd2);
        ex_stack_op = `STACK_PUSH; ex_valid = 1'b0;     #1;
        chk("EX bubble",   depth_eff, 16'd2);
        // WB PUSH + EX PUSH in the same cycle
        ex_valid = 1'b1;
        drive(1'b1, `STACK_PUSH, 16'h0033);
        chk("WB+EX PUSH",  depth_eff, 16'd4);
        tick;
        do_reset;
        // EX POP1 on an empty stack clamps at 0
        ex_valid = 1'b1; ex_stack_op = `STACK_POP1;     #1;
        chk("EX POP1 empty", depth_eff, 16'd0);
        tick;

        // ---------------------------------------------------------
        cur_test = "T17 EX/WB register and wb_stage";
        do_reset;
        // (a) bubble from EX never reaches the stack
        w_ex_alu = 16'hBEEF; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b0; #1;
        tick;
        tick;
        chk("bubble depth", w_depth, 16'd0);
        chk("bubble tos",   w_tos,   16'h0000);
        // (b) valid PUSH: visible via write-through when it is in WB,
        //     committed one edge later
        w_ex_alu = 16'h00AB; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1; #1;
        tick;                                   // entry is now in EX/WB
        chk("wt tos",       w_tos,       16'h00AB);
        chk("wt depth",     w_depth,     16'd0);
        chk("wt depth_eff", w_depth_eff, 16'd1);
        tick;                                   // WB commits
        chk("depth 1",      w_depth, 16'd1);
        chk("tos",          w_tos,   16'h00AB);
        // (c) flush replaces the incoming entry with a bubble
        w_ex_alu = 16'h00CD; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1;
        w_flush = 1'b1; #1;
        tick;
        w_flush = 1'b0;
        tick;
        chk("flush depth",  w_depth, 16'd1);
        chk("flush tos",    w_tos,   16'h00AB);
        // (d) back-to-back PUSH entries
        w_ex_alu = 16'h0011; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1; #1;
        tick;
        w_ex_alu = 16'h0022; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1; #1;
        tick;
        tick;
        chk("b2b depth",    w_depth, 16'd3);
        chk("b2b tos",      w_tos,   16'h0022);
        chk("b2b nos",      w_nos,   16'h0011);
        // (e) frozen stack ignores the WB entry
        w_ex_alu = 16'h0033; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1; #1;
        tick;
        w_freeze = 1'b1;
        tick;
        tick;
        chk("freeze depth", w_depth, 16'd3);
        chk("freeze tos",   w_tos,   16'h0022);
        w_freeze = 1'b0;
        // (f) reset clears both the stack and the EX/WB entry
        w_ex_alu = 16'h0044; w_ex_op = `STACK_PUSH; w_ex_valid = 1'b1; #1;
        tick;
        do_reset;
        tick;
        chk("reset depth",  w_depth, 16'd0);
        chk("reset tos",    w_tos,   16'h0000);

        // ---------------------------------------------------------
        $display("Checks executed: %0d", checks);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d of %0d checks failed", errors, checks);
        $finish;
    end

endmodule
