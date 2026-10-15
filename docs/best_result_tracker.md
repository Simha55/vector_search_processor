# Module 5: best-result tracker

This synthesizable module receives completed dot-product scores and remembers
the highest score and its vector ID. Equal scores select the smaller unsigned
ID. It is separate from the dot-product engine until the search controller and
top-level wiring are implemented.

## Ports and widths

| Signal | Width/type | Purpose |
|---|---|---|
| clk | 1-bit input wire | Rising-edge clock. |
| reset | 1-bit input wire | Active-high synchronous reset. |
| clear | 1-bit input wire | Synchronous clear before a new search. |
| enable | 1-bit input wire | Evaluate one candidate on this rising edge. |
| candidate_score | Signed 64-bit input wire | Completed dot-product score. |
| candidate_id | Unsigned 32-bit input wire | Database vector identifier. |
| best_valid | 1-bit output reg | At least one candidate has been accepted. |
| best_score | Signed 64-bit output reg | Highest accepted score. |
| best_id | Unsigned 32-bit output reg | Winning vector ID. |

Reset > clear > enable > hold. Clear/reset discard a candidate on that edge.
Clear on a separate edge before enabling the first candidate of a new search.
Initialize with reset or clear through a rising edge before reading outputs.
When best_valid=0, best_score/best_id are zero placeholders, not a search result.
An empty search remains invalid; later controller logic must decide its external
error/result behavior.

This is an enable-controlled register block, not a valid/ready interface.
It accepts one candidate on every enabled edge when reset/clear are low.
It has no knowledge of vector count and no search-done output: best_valid means
there is a running winner, not that the whole search is complete. A future
controller will enable it only for an accepted completed dot-product result and
will finish the search after the configured number of vectors.

## Source walkthrough

- `module best_result_tracker (` begins the module and port list.
- `input wire clk,` accepts the clock.
- `input wire reset,` accepts synchronous reset.
- `input wire clear,` accepts the per-search clear.
- `input wire enable,` permits candidate evaluation at an edge.
- `input wire signed [63:0] candidate_score,` accepts a signed 64-bit score.
- `input wire [31:0] candidate_id,` accepts an unsigned 32-bit ID.
- `output reg best_valid,` declares a one-bit stored validity flag.
- `output reg signed [63:0] best_score,` declares the stored signed best score.
- `output reg [31:0] best_id` declares the stored unsigned winning ID.
- `);` closes the port list.
- `always @(posedge clk) begin` updates storage at rising edges only.
- `if (reset) begin` selects the highest-priority reset branch.
- `best_valid <= 1'b0;` marks the stored result invalid; 1'b0 is one binary bit.
- `best_score <= 64'sd0;` writes signed 64-bit decimal zero as a placeholder.
- `best_id <= 32'd0;` writes unsigned 32-bit decimal zero as a placeholder.
- `end else if (clear) begin` handles a new-search clear when reset is low.
  Its three assignments perform the same invalidation and zeroing as reset.
- `end else if (enable) begin` processes a candidate only if neither clear nor
  reset is active and enable is high.
- `if (!best_valid ||` accepts the first candidate regardless of its score.
  ! means logical NOT; || means logical OR.
- `(candidate_score > best_score) ||` accepts a strictly higher score. Both
  operands are signed, so -10 correctly beats -30.
- `((candidate_score == best_score) && (candidate_id < best_id))) begin`
  accepts an equal score only when its ID is smaller. && means logical AND.
  ID comparison is unsigned: 0x7fffffff is smaller than 0x80000000.
- `best_valid <= 1'b1;` records that there is now an accepted winner.
- `best_score <= candidate_score;` stores the new winning score.
- `best_id <= candidate_id;` stores that score's ID on the same edge.
- The three following end statements close the winning-candidate condition,
  enable branch, and always block.
- `endmodule` ends the module. Blank lines provide spacing.

Nonblocking <= assignments update registers after evaluating current values.
No final else is needed: these clocked registers retain their values when
nothing wins or enable is low. All outputs hold between rising edges.

The first candidate must be accepted independently of the zero placeholder.
Otherwise an all-negative database could incorrectly keep zero as the winner.
No arithmetic is performed here, so there is no addition overflow. Signed score
limits are -2^63 through 2^63-1; unsigned ID limits are 0 through 2^32-1.

## Example

| Candidate score | ID | Best score | Best ID | Reason |
|---:|---:|---:|---:|---|
| -30 | 5 | -30 | 5 | First candidate |
| -40 | 0 | -30 | 5 | Lower score loses |
| -10 | 9 | -10 | 9 | Higher score wins |
| -10 | 3 | -10 | 3 | Equal score, smaller ID wins |
| -10 | 12 | -10 | 3 | Equal score, larger ID loses |

## Verification

The simulation-only testbench drives candidates and controls at falling edges,
checks that outputs remain unchanged before the next rising edge, then checks
explicit expected results after register updates. A timeout catches hangs.

Observed result on 2026-10-14:
`PASS: best-result tracker checked for 28 clock cycles.`

Checks cover all-negative candidates, higher/lower scores, ties and duplicates,
unsigned ID boundaries, signed 64-bit minimum/maximum scores, disabled inputs,
reset and clear priority, empty searches, and new-search recovery.

Run from vector_search:

```sh
iverilog -g2012 -s tb_best_result_tracker -o /tmp/vector_search_best_result_test rtl/best_result_tracker.v tb/tb_best_result_tracker.v
vvp /tmp/vector_search_best_result_test
```

Simulation passed. Synthesis and clock timing have not been tested.
