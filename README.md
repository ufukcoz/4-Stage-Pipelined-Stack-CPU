
## Member C – Hardware Stack and Write-Back Stage

### Overview

Member C is responsible for implementing the hardware stack and the Write-Back (WB) stage of the 4-stage pipelined stack CPU.

The hardware stack stores 16-bit data values and provides the Top of Stack (TOS) and Next of Stack (NOS) values to the instruction decode stage.

The stack is updated in the Write-Back stage. A write-through mechanism allows the ID stage to observe the result of the current WB operation without waiting for another clock cycle.

### Implemented Modules

#### 1. Hardware Stack (`hardware_stack.v`)

The hardware stack is implemented as a 16-entry memory with a 16-bit data width.

Main features:

- 16-bit stack data width.
- 16 stack entries.
- Stack Pointer (SP) points to the next empty location.
- TOS and NOS are provided through combinational read logic.
- Write-through support for WB operations.
- Stack status signals: `empty`, `full`, and `stack_depth`.
- Effective stack depth calculation using `depth_eff`.
- Underflow and overflow detection.
- Stack freeze support during the ERROR state.
- Synchronous, active-high reset.

#### 2. EX/WB Pipeline Register (`ex_wb_register.v`)

This module transfers information from the Execute (EX) stage to the Write-Back (WB) stage.

It stores:

- `ex_alu_result`
- `ex_stack_op`
- `ex_valid`

The register supports synchronous reset and flush operations.

Invalid pipeline entries (bubbles) are converted into valid-free entries with `STACK_NONE`, preventing unintended stack modifications.

#### 3. Write-Back Stage (`wb_stage.v`)

The WB stage connects the EX/WB pipeline register to the hardware stack.

Its main responsibilities are:

- Receiving ALU results and stack operations from EX.
- Registering the incoming instruction information.
- Sending valid stack operations to the hardware stack.
- Providing TOS and NOS values to the rest of the processor.
- Forwarding stack status and error signals to the control unit.

#### 4. Stack Operation Definitions (`defs.vh`)

The stack operation codes are defined as follows:

| Operation | Code | Description |
|---|---|---|
| NONE | `000` | No stack modification |
| PUSH | `001` | Push a new value |
| POP1 | `010` | Remove the top element |
| REPLACE2 | `011` | Replace the top two elements with one result |

### Stack Operation Behavior

- **PUSH:** Writes the incoming data to `mem[SP]` and increments SP by one.
- **POP1:** Decrements SP by one without writing new data.
- **REPLACE2:** Writes the result to `mem[SP-2]` and decrements SP by one. This operation is used for arithmetic and logical instructions.
- **NONE:** Does not modify the stack.

### Error Handling

The hardware stack detects invalid operations:

- Underflow occurs when POP1 is attempted on an empty stack or REPLACE2 is attempted with fewer than two elements.
- Overflow occurs when PUSH is attempted while the stack is full.
- Invalid operations are suppressed to prevent stack corruption.
- The control FSM is responsible for entering the ERROR state.
- The `freeze` signal prevents stack modifications while the processor is in the ERROR state.

### Testing (`tb_stack.v`)

A self-checking testbench is provided to verify the hardware stack and WB stage.

The testbench covers:

1. Reset and initial empty state.
2. Single and multiple PUSH operations.
3. TOS and NOS correctness.
4. POP1 operation.
5. REPLACE2 operation.
6. Write-through behavior.
7. Full stack detection.
8. Overflow detection.
9. Underflow detection.
10. Stack freeze behavior.
11. Bubble handling.
12. Effective stack depth calculation.
13. EX/WB register and WB stage integration.

The testbench reports `ALL TESTS PASSED` when all checks succeed.

### File Structure

```text
rtl/
├── defs.vh
├── hardware_stack.v
├── ex_wb_register.v
└── wb_stage.v

tb/
└── tb_stack.v
```

### Compilation and Simulation

Using Icarus Verilog:

```bash
mkdir -p build

iverilog -g2012 -Wall -I rtl -o build/tb_stack.vvp \
rtl/hardware_stack.v \
rtl/ex_wb_register.v \
rtl/wb_stage.v \
tb/tb_stack.v

vvp build/tb_stack.vvp
```

Expected successful output:

```text
ALL TESTS PASSED
```
