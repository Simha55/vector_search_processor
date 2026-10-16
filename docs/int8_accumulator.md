# Signed INT8 product accumulator

An accumulator stores a running total. This module accepts the signed 16-bit
output of the INT8 multiplier and adds it to a signed 64-bit register.
It is instantiated by int8_mac, which is used by the queued service's parallel accumulator.

## Ports

| Port | Width and type | Meaning |
|---|---|---|
| clk | 1-bit input wire | Rising edges trigger updates. |
| reset | 1-bit input wire | Active-high synchronous reset; set the sum to zero. |
| clear | 1-bit input wire | Set the sum to zero before a new vector. |
| enable | 1-bit input wire | Add the current product when high. |
| product | Signed 16-bit input wire | One multiplication result. |
| sum | Signed 64-bit output reg | Stored running total. |

Reset and clear are synchronous: changing them alone does not change the sum.
They must be high at a rising clock edge. Priority is reset, then clear, then
enable, then hold. Clear and enable together clear the sum and discard that
edge's product. Clear one edge before accepting the first product of a vector.
The sum has no defined startup value until a reset or clear clock edge occurs.
This module has no ready/valid handshake or done output. The parallel accumulator
controls enable and element counting; the MAC passes accepted products to it.

## Every source line explained

- `module int8_accumulator (` begins the module and its port list.
- `input wire clk,` declares the clock input.
- `input wire reset,` declares the reset input.
- `input wire clear,` declares the per-vector clear input.
- `input wire enable,` declares the addition permission input.
- `input wire signed [15:0] product,` declares a signed 16-bit number.
  Bit 15 is its sign bit; the type can represent -32768 through 32767.
- `output reg signed [63:0] sum` declares a signed 64-bit output assigned
  inside a procedural block. Here it becomes hardware storage because the
  assignments occur in a clocked block. Its range is -2^63 through 2^63-1.
- `);` closes the port list.
- `wire signed [63:0] extended_product;` names a signed 64-bit combinational signal.
- `assign extended_product = {{48{product[15]}}, product};` continuously
  sign-extends the product. The inner replication repeats its sign bit 48 times;
  the outer concatenation puts those bits above the original 16 bits.
  The total is 48+16=64 bits. Positive numbers gain zeros; negative numbers gain
  ones. Thus -8 remains -8. Adding zeros above a negative input would instead
  turn its 16-bit pattern into a positive number (for -8, that would be 65528).
- `always @(posedge clk) begin` runs the block on every rising clock edge.
- `if (reset)` checks the highest-priority control.
- `sum <= 64'sd0;` schedules signed 64-bit zero into the sum register.
- `else if (clear)` checks clear only when reset is low.
- Its `sum <= 64'sd0;` also schedules zero.
- `else if (enable)` permits addition only when reset and clear are low.
- `sum <= sum + extended_product;` computes the next total from the old sum
  and the current sign-extended product. Both operands are signed 64-bit values.
  `<=` is a nonblocking assignment: it updates storage after the clocked block
  evaluates, allowing clocked hardware to use the old register values together.
- `end` closes the clocked block. No final else is needed: when all controls
  are low, the register keeps its previous value. This describes a clock enable,
  not a combinational latch.
- `endmodule` closes the module. Blank lines only separate the code visually.

## Example

Each row shows the sum after the rising edge and its register update.

| Edge | reset | clear | enable | product | sum |
|---|---|---|---|---|---|
| 1 | 1 | 0 | 0 | ignored | 0 |
| 2 | 0 | 0 | 1 | 6 | 6 |
| 3 | 0 | 0 | 1 | -8 | -2 |
| 4 | 0 | 0 | 0 | 100 | -2 |
| 5 | 0 | 0 | 1 | 10 | 8 |
| 6 | 0 | 1 | 1 | 99 | 0 |

The adder is combinational logic feeding a 64-bit register. At each enabled
edge, the register captures the next total. The accumulator can accept one
product per clock in this simple design, subject to meeting clock timing.
There are no added pipeline stages or measured synthesis timing results yet.

For the proposed 4096-element limit, even 4096 copies of the largest INT8
product, (-128)*(-128)=16384, sum to only 67108864. The chosen 64 bits leave
ample room. This fixed-width adder wraps if its 64-bit range is exceeded;
there is no saturation or overflow flag.

## Simulation versus hardware

`rtl/int8_accumulator.v` describes synthesizable hardware. The testbench uses
`initial`, `#` delays, tasks, and simulation reporting to generate clock/input
signals and check results; it is not the accelerator hardware.

The testbench drives inputs at falling edges and checks outputs after rising
edges so it avoids races with register updates. It verifies signed boundaries,
hold behavior, synchronous controls, clear/reset priority, reset during an
active sum, 4096-element positive and negative sums, and varied input sequences.

Run from the project directory:

```sh
iverilog -g2012 -s tb_int8_accumulator -o /tmp/vector_search_accumulator_test rtl/int8_accumulator.v tb/tb_int8_accumulator.v
vvp /tmp/vector_search_accumulator_test
```

Observed result on 2026-10-14: `PASS: accumulator checked for 9232 clock cycles.`
