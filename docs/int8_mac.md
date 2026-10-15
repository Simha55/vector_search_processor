# Module 3: signed INT8 multiply-accumulate (MAC)

A MAC combines multiplication and accumulation. For every rising clock edge
where enable is high and reset/clear are low, it performs:

    sum_next = sum_previous + a * b

This module instantiates the existing multiplier and accumulator. It adds no
new storage. The 64-bit sum register is inside the accumulator.

## Ports and widths

| Port | Type | Meaning |
|---|---|---|
| clk | 1-bit input wire | Rising-edge clock for the accumulator. |
| reset | 1-bit input wire | Active-high synchronous reset to zero. |
| clear | 1-bit input wire | Synchronous clear before a new vector. |
| enable | 1-bit input wire | Consume the current input pair on this edge. |
| a | Signed 8-bit input wire | One query element, -128 through 127. |
| b | Signed 8-bit input wire | One database element, -128 through 127. |
| sum | Signed 64-bit output wire | Running dot-product total from the accumulator. |

## Every source line explained

- `module int8_mac (` begins the module and its port list.
- `input wire clk,` accepts the clock signal.
- `input wire reset,` accepts reset.
- `input wire clear,` accepts the per-vector clear signal.
- `input wire enable,` accepts permission to add the current product.
- `input wire signed [7:0] a,` declares the signed 8-bit first operand.
- `input wire signed [7:0] b,` declares the signed 8-bit second operand.
- `output wire signed [63:0] sum` declares a signed 64-bit output driven by
  the child accumulator. It is a wire here because this module does not assign
  it in an always block. The underlying storage remains the child's register.
- `);` closes the port list.
- `wire signed [15:0] product;` declares the internal connection between
  multiplier and accumulator. Sixteen signed bits preserve any INT8 product.
- `int8_multiplier multiplier (` creates an instance of the multiplier module.
  `int8_multiplier` is the module type; `multiplier` is this instance's name.
- `.a(a),` connects the child's port a (left) to this module's signal a (right).
- `.b(b),` connects the child's b port to this module's b signal.
- `.product(product)` connects the multiplier output to the internal product wire.
- `);` closes the multiplier instance's connection list.
- `int8_accumulator accumulator (` creates an instance named accumulator.
- `.clk(clk),` routes the clock to that instance.
- `.reset(reset),` routes reset.
- `.clear(clear),` routes clear.
- `.enable(enable),` routes enable.
- `.product(product),` supplies the product wire as the accumulator input.
- `.sum(sum)` connects the accumulator output to this module's output.
- `);` closes the accumulator instance's connection list.
- `endmodule` ends the module. Blank lines are visual spacing.

The two module instances describe hardware that exists concurrently. Their
source-code order does not mean the multiplier is called and then the
accumulator is called as software functions would be.

`dut` in the testbench is also an instance name: it stands for device under test.
It is a conventional label, not a Verilog keyword.

## Datapath and timing

    a, b -> combinational multiplier -> signed 16-bit product
         -> sign extension -> adder -> signed 64-bit sum register
                                  ^                |
                                  +--- previous sum+

Inputs must settle before the enabled rising edge, and satisfy hardware setup
and hold timing. Multiplication and addition lie in the same register-to-register
combinational path; there is no product pipeline register. After that edge's
register update, sum includes the pair just consumed. Simulation checks wait
briefly after the edge to observe the nonblocking assignment.

Reset > clear > enable > hold. Reset and clear take effect on rising edges.
If clear and enable are both high, the product is discarded. Use a separate
clear edge before the first pair of a new vector. Reset/clear must initialize
sum before it is used.

The design accepts one pair per enabled cycle in simulation; achievable clock
frequency has not been measured by synthesis or timing analysis. There is no
ready/valid interface, dimension counter, done flag, or query memory yet. A
future controller will supply the pairs, count them, and mark the final score.
The fixed-width sum wraps on 64-bit overflow; it has no overflow flag.

## Worked dot product

Query [1, -2, 3] and database [4, 5, -6]:

| Rising edge action | Product | Sum afterward |
|---|---:|---:|
| Clear | ignored | 0 |
| Enable a=1, b=4 | 4 | 4 |
| Disable (pause) | ignored | 4 |
| Enable a=-2, b=5 | -10 | -6 |
| Enable a=3, b=-6 | -18 | -24 |

The final dot product is -24. Clear again before the next vector.

## Verification

`rtl/int8_mac.v` describes synthesizable connections to synthesizable child
modules. `tb/tb_int8_mac.v` is simulation-only: it generates clock/input signals
and checks the output against integer reference multiplication and a 64-bit sum.
Inputs change on falling edges; outputs are checked after rising-edge updates.

Observed on 2026-10-14:
`PASS: MAC checked for 73743 clock cycles, including all 65,536 INT8 pairs.`

Checks cover a known dot product, zero products, input pauses, synchronous
controls, clear/reset priority, reset during accumulation, exhaustive INT8
pairs through the connected datapath, and separate 4096-element positive and
negative vectors.

Run from vector_search:

```sh
iverilog -g2012 -s tb_int8_mac -o /tmp/vector_search_mac_test rtl/int8_multiplier.v rtl/int8_accumulator.v rtl/int8_mac.v tb/tb_int8_mac.v
vvp /tmp/vector_search_mac_test
```
