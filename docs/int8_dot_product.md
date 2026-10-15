# Module 4: single-lane INT8 dot product

This module wraps the MAC with a small finite-state machine (FSM). It accepts
one vector-length command, consumes exactly that many pairs, and returns one
signed 64-bit score. Both operands are supplied externally; query storage and
searching multiple database vectors are future modules.

## Ports

| Port | Width/type | Meaning |
|---|---|---|
| clk | 1-bit input wire | Rising-edge clock. |
| reset | 1-bit input wire | Active-high synchronous reset; abort current work. |
| command_valid | 1-bit input wire | Sender has a valid dimensions command. |
| command_ready | 1-bit output wire | Engine can accept that command. |
| dimensions | Unsigned 16-bit input wire | Number of element pairs, 0 through 65535. |
| pair_valid | 1-bit input wire | Sender has a valid a/b pair. |
| pair_ready | 1-bit output wire | Engine can accept that pair. |
| a | Signed 8-bit input wire | One query element. |
| b | Signed 8-bit input wire | Corresponding database element. |
| result_valid | 1-bit output wire | score is a completed result. |
| result_ready | 1-bit input wire | Receiver can accept the result. |
| score | Signed 64-bit output wire | Running MAC sum; only a final result when result_valid=1. |

A transfer occurs on a rising edge when both the channel's valid and ready
are high. The sender must keep valid asserted and its payload stable until
accepted. There are three independent channels: command, pair, and result.
The command payload is dimensions; the pair payload is a and b; the result
payload is score. There is no last flag; the command determines the pair count.

The unsigned 16-bit length supports 0 through 65535. This streaming arithmetic
module has no query memory, so the proposed 4096-element query-buffer capacity
is not enforced here. A future search controller must validate dimensions
against the actual query buffer capacity. Four-lane 128-bit chunks are deferred.

## FSM and timing

    IDLE -> CLEAR -> RUN -> RESULT -> IDLE
                   \------> RESULT (zero dimensions)

- IDLE: command_ready=1. Latch dimensions on a command transfer.
- CLEAR: spend one rising edge clearing the MAC. No pairs accepted.
- RUN: pair_ready=1. Add each accepted product and decrement remaining.
- RESULT: result_valid=1. Hold score until result_ready=1 at a rising edge.

For length three, the command edge enters CLEAR; the next edge clears the MAC
and enters RUN. Three accepted pair edges compute the dot product. After the
third pair edge, RESULT and the final score become visible together. The result
can first be consumed at the following rising edge, even if result_ready was
already high. No new command is accepted on the result-consumption edge; it can
be accepted at the next rising edge. No overlap between different vectors yet.

Zero dimensions return score zero after CLEAR, consuming no input pairs.
Input pauses leave both remaining and score unchanged. During RESULT, extra
pairs and commands are not accepted and score is stable under backpressure.
Reset aborts pending work/results and resets the MAC sum and controller.
While reset is high, the handshake outputs are gated low; the internal state
and sum reset at the rising edge. Reset must be asserted through a rising edge
before normal use. score need only be interpreted when result_valid is high.

## Source walkthrough

The module declaration and input/output lines define the ports listed above.
All payload and control inputs are wires driven by the parent; outputs are wires
driven by the assignments below or by the child MAC. `);` closes the port list.

`localparam [1:0] IDLE = 2'd0;` gives the idle state a fixed two-bit encoding.
The next three localparams similarly encode CLEAR=1, RUN=2, RESULT=3. These
constants do not create four registers.

`reg [1:0] state;` stores the current state in two bits.
`reg [15:0] remaining;` stores the unsigned count of pairs still needed.
Both use reg because the clocked always block assigns them.
`wire clear_sum;` and `wire accept_pair;` name combinational control connections.

`assign command_ready = !reset && (state == IDLE);` continuously makes the
command ready only in IDLE outside reset. `!` means logical NOT; `&&` means
logical AND; `==` compares values.
`assign pair_ready = !reset && (state == RUN);` permits pairs only in RUN.
`assign result_valid = !reset && (state == RESULT);` marks completed scores.
`assign clear_sum = (state == CLEAR);` clears the MAC during CLEAR.
`assign accept_pair = pair_valid && pair_ready;` marks an accepted pair.

`int8_mac mac (` instantiates the existing MAC with instance name mac.
`.clk(clk)` and `.reset(reset)` pass the clock and reset into it.
`.clear(clear_sum)` connects the FSM's clear control to the MAC's clear port.
`.enable(accept_pair)` adds products only for accepted pairs.
`.a(a)` and `.b(b)` pass the signed operands through.
`.sum(score)` drives the output score directly from the MAC's sum register.
Commas separate named connections; `);` ends the instance declaration.

`always @(posedge clk) begin` updates controller registers on rising edges.
`if (reset) begin` gives synchronous reset priority over all normal work.
`state <= IDLE;` schedules the idle state.
`remaining <= 16'd0;` schedules unsigned 16-bit zero.
`end else begin` selects normal work when reset is low.
`case (state)` selects behavior according to the stored state.

Within IDLE, `if (command_valid && command_ready)` tests command transfer.
`remaining <= dimensions;` captures the length so later input changes cannot
alter this vector. `state <= CLEAR;` schedules the clearing phase.
With no command transfer, the registers hold their values.

Within CLEAR, `if (remaining == 16'd0)` detects an empty vector.
`state <= RESULT;` returns its zero score. The else branch sets `state <= RUN;`
for nonempty vectors. On this same edge, the separate MAC sees clear_sum=1 and
sets its sum to zero. Concurrent clocked hardware uses the pre-edge state.

Within RUN, `if (accept_pair)` prevents pauses from changing anything.
`remaining <= remaining - 16'd1;` schedules the count minus one.
`if (remaining == 16'd1)` tests the OLD count, before that decrement.
`state <= RESULT;` marks completion when this edge consumes the last pair.
The MAC adds that last product on this same edge. Testing the old count against
one avoids consuming an extra element. For non-final pairs state stays RUN.

Within RESULT, `if (result_valid && result_ready)` detects result acceptance.
`state <= IDLE;` permits a subsequent command. Without acceptance, state and the
MAC sum hold; the MAC enable is low because pair_ready is low.

The default branch sets state to IDLE and remaining to zero if the case has no
matching state. It does not replace proper reset initialization.
`endcase` ends state selection; the following end statements close the normal
branch and always block; `endmodule` ends the module. Other begin/end pairs
group their conditional/state statements; blank lines only separate code.

Nonblocking assignments (`<=`) evaluate from current values and schedule
register updates after the blocks evaluate. They are essential to understanding
why the FSM and MAC both use the old state on the same clock edge.

## Example

Command dimensions=3, then provide [1,-2,3] paired with [4,5,-6]:

| Action at rising edge | Score after edge | result_valid |
|---|---:|---:|
| Accept command | previous score | 0 |
| CLEAR | 0 | 0 |
| Accept 1,4 | 4 | 0 |
| Pause pair_valid=0 | 4 | 0 |
| Accept -2,5 | -6 | 0 |
| Accept 3,-6 | -24 | 1 |
| Receiver not ready | -24 | 1 |
| Receiver accepts result | -24 | 0 |

## Verification and limits

The RTL and child modules describe synthesizable hardware. The testbench uses
simulation-only tasks, delays, clock generation, reference arithmetic and fatal
assertions. Inputs normally change on falling edges and outputs are sampled
after rising-edge register updates. A timeout catches stalled simulations.

Observed on 2026-10-14:
`PASS: dot product checked 8 completed vectors over 4521 clock cycles, including stalls and reset recovery.`

Checks cover dimensions 0,1,3,6,257,4096, varied signed values, known score -24,
input pauses, latched dimensions, early/extra pairs, busy commands, stalled
results, an already-ready result receiver, and reset in CLEAR/RUN/RESULT.
An initial testbench failure in the already-ready scenario was corrected:
the test waited an extra edge while leaving an early pair valid, unintentionally
consuming that pair before sending the intended one. The RTL was unchanged.

Run from vector_search:

```sh
iverilog -g2012 -s tb_int8_dot_product -o /tmp/vector_search_dot_product_test rtl/int8_multiplier.v rtl/int8_accumulator.v rtl/int8_mac.v rtl/int8_dot_product.v tb/tb_int8_dot_product.v
vvp /tmp/vector_search_dot_product_test
```

Synthesis and clock timing have not been measured. The multiplier and adder
remain in one combinational clock path. No new arithmetic pipeline stages,
query memory, top-1 comparison, vector IDs, or full-search controller are added.
