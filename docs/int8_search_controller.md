# Module 7: INT8 search controller

The controller coordinates a complete exact INT8 search. It does not instantiate
storage or arithmetic: its child-facing ports connect to the existing query
buffer, dot-product engine, and best-result tracker. The testbench makes those
connections using real modules. A reusable accelerator top-level remains next.

## External interface

| Port | Type | Meaning |
|---|---|---|
| clk, reset | One-bit inputs | Rising-edge clock, active-high synchronous reset. |
| command_valid, command_ready | Input/output bits | Accept one search configuration on a rising-edge handshake. |
| dimensions | Unsigned 16-bit input | Query length, validated against MAX_ELEMENTS. |
| vector_count | Unsigned 32-bit input | Number of database vectors to scan. |
| query_valid, query_ready | Input/output bits | Query element stream handshake. |
| query_data | Signed INT8 input | Query elements in increasing element order. |
| database_valid, database_ready | Input/output bits | Database element stream handshake. |
| database_data | Signed INT8 input | All elements of vector 0, then vector 1, etc. |
| result_valid, result_ready | Output/input bits | One completed search response, held until accepted. |
| result_error | Unsigned 2-bit output | 0 success, 1 invalid dimensions, 2 empty database. |
| result_found | Output bit | Successful search has a winner. Meaningful with result_valid. |
| result_score | Signed 64-bit output | Winning dot-product score. Meaningful for a successful result. |
| result_id | Unsigned 32-bit output | Winning vector's zero-based position in the database stream. |

A transfer occurs only at a rising edge with both valid and ready high. A sender
holds valid and payload until accepted. Each command loads a fresh query.
Database senders can assert valid before ready and wait; the controller accepts
only after loading the complete query. Extra inputs remain unaccepted at RESULT.
No 128-bit slots, floating point, or multiple lanes yet.

MAX_ELEMENTS defaults to 4096; ADDRESS_WIDTH defaults to enough address bits,
with a one-bit minimum. Keep 1 <= MAX_ELEMENTS <= 65535 for this controller and
leave ADDRESS_WIDTH derived. Use the same parameters for the connected buffer.
The arithmetic module can count more than the buffer holds; this controller
validates the full dimensions value before using narrowed memory addresses.

## Error policy

Zero dimensions or dimensions greater than MAX_ELEMENTS produce error 1.
A zero vector count produces error 2. Dimension errors have priority if both
are invalid. Invalid commands consume NO query or database elements, clear the
previous winner, and produce a response with result_found=0. The receiver must
still accept the error response using result_ready. The reusable dot-product
engine's zero-length operation returns zero; the search-level policy rejects
zero-length queries instead. This makes the interfaces explicit at each level.

## Child-facing ports

- buffer_write_enable/address/data drive the query buffer's write port.
- buffer_read_enable/address request a synchronous read. buffer_read_valid/data
  return the response. The controller waits and registers the response.
- dot_command_valid/ready and dot_dimensions start each database dot product.
- dot_pair_valid/ready and dot_a/b transfer one aligned query/database pair.
- dot_result_valid/ready and dot_score transfer each completed vector score.
- tracker_clear invalidates the previous search winner.
- tracker_enable and tracker_candidate_score/id evaluate an accepted dot result.
- tracker_best_valid/score/id feed the final response back to the controller.

All four connected blocks MUST receive the same reset. Resetting the controller
alone while leaving the dot engine busy would violate the integration contract.
Reset aborts the search and pending response. The buffer memory is preserved,
but the controller restarts from IDLE and requires a newly loaded query.

## Controller state sequence

    IDLE -> VALIDATE -> LOAD_QUERY -> DOT_COMMAND
      -> RECEIVE_ELEMENT -> READ_QUERY -> WAIT_QUERY -> SEND_PAIR
          ^                                              |
          +------------ more elements -------------------+
                                                         |
                                                    final pair
                                                         v
                                                     WAIT_SCORE
                                                         |
                             more vectors -> DOT_COMMAND |
                             final vector -> RESULT -> IDLE

Invalid commands go from VALIDATE directly to RESULT.

- IDLE accepts/latches dimensions and vector_count, zeros indices/error.
- VALIDATE clears the tracker and checks dimensions/count.
- LOAD_QUERY writes one element per accepted query transfer. The last resets
  element_index to zero and proceeds to the first dot command.
- DOT_COMMAND holds a command valid until the dot engine accepts it.
- RECEIVE_ELEMENT accepts one database element and stores it in a register.
- READ_QUERY requests the matching query element from the buffer.
- WAIT_QUERY waits for buffer_read_valid and stores its data in another register.
- SEND_PAIR holds both stored operands and valid until dot_pair_ready.
  On transfer, either advance element_index or wait for the completed score.
- WAIT_SCORE accepts the dot result and enables the tracker on the same edge.
  If more vectors remain, increment vector_index, zero element_index, and start
  another dot product. Otherwise enter RESULT.
- RESULT holds the final response until accepted, then returns to IDLE.

The final score's tracker update and controller transition to RESULT occur on
the same edge. After the nonblocking updates, the final winner is available
along with result_valid. Do not read it before result_valid.

## Source walkthrough

The parameter list and port declarations specify the interfaces above.
The localparam state declarations encode ten states in four bits. The second
localparam group names three two-bit error values.

The reg declarations store state, accepted configuration, the current element
and vector indices, one pending database element, one query response, and the
error code. Signed qualifiers preserve negative INT8 operands; dimensions and
indices are unsigned. No vector-sized array is inside the controller.

The assign statements are continuously evaluated combinational connections:
- command/query/database ready decode the matching state and gate off in reset.
- result_valid similarly decodes RESULT. The other result outputs route the
  error register and tracker outputs; only interpret them as a response when valid.
- buffer write enable equals query_valid && query_ready. The address is the
  low ADDRESS_WIDTH bits of element_index; valid dimensions keep it in range.
- buffer_read_enable decodes READ_QUERY; the address uses the same index.
- dot command/pair valid and result ready decode their respective states.
- dot_dimensions uses the captured length, not the changing external input.
- dot_a/b use stored operands so stalls cannot alter a pending pair.
- tracker_clear decodes VALIDATE; tracker_enable equals the dot result handshake.
- tracker candidate score comes from the dot engine; candidate ID is vector_index.

The always block updates registers on rising edges only. Reset initializes all
controller registers and takes priority over the case statement. Nonblocking
<= assignments use current values and schedule updates after evaluation.

IDLE's if condition recognizes a command transfer. VALIDATE compares the full
16-bit length against zero/capacity before LOAD_QUERY can write anything.
LOAD_QUERY's transfer condition also drives the child write enable. Comparing
index against saved_dimensions-1 identifies the last accepted query element.
DOT_COMMAND waits for command acceptance, not a fixed assumed latency.
RECEIVE_ELEMENT stores one database element only on a handshake.
READ_QUERY advances after its request edge; WAIT_QUERY captures the registered
response at a later edge. SEND_PAIR waits as long as necessary, advances only
on acceptance, and recognizes the final pair by the current element index.
WAIT_SCORE uses the same handshake as tracker_enable so each vector is compared
exactly once. Its vector index test recognizes the last configured vector.
RESULT waits for response acceptance. Registers without assignments hold their
values. default returns the state to IDLE; it is not a substitute for reset.
The endcase, end, and endmodule statements close the selection, blocks, and module.

## Example

Query [1,-2,3], three database vectors:

| ID | Database vector | Dot product |
|---|---|---:|
| 0 | [4,5,-6] | -24 |
| 1 | [1,1,1] | 2 |
| 2 | [1,1,1] | 2 |

Command dimensions=3, vector_count=3. Load the three query elements, then stream
nine database elements in the shown vector order. The response is error=0,
found=1, score=2, ID=1: smaller ID wins the equal-score tie.

## Performance and verification

This correctness-first controller processes one element at a time. In the
steady sequence, database accept, read request, read response capture, and pair
accept occupy four successive edges, so database accepts are four cycles apart
without stalls. There is also per-vector command/result overhead. It does not
achieve the later four-pairs-per-cycle target. Query loading itself accepts an
element per cycle when the sender is ready. Synthesis/timing is not measured.

The testbench instantiates the actual controller, buffer, dot engine, and
tracker; it computes expected scores independently using integer products and
64-bit reference totals. It verifies input pauses, pending input handshakes,
latched commands, result backpressure and blocked extra inputs, all-negative
scores/ties, signed INT8 boundaries, invalid length/empty database errors, and
reset during partial query loading, in-flight processing, and pending results.
It then reloads and checks a fresh search after reset.

Observed successful outputs on 2026-10-14:

```text
PASS: search controller capacity=5 checked 9 searches plus reset recovery.
PASS: search controller capacity=1 checked 9 searches plus reset recovery.
PASS: search controller capacity=4096 checked 9 searches plus reset recovery.
```

Run from vector_search:

```sh
iverilog -g2012 -s tb_int8_search_controller -o /tmp/vector_search_controller_test rtl/*.v tb/tb_int8_search_controller.v
vvp /tmp/vector_search_controller_test
```

Add -Ptb_int8_search_controller.MAX_ELEMENTS=1 or =4096 when compiling for the
other tested capacities. This is simulation evidence, not FPGA deployment.
