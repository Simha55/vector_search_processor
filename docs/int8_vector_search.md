# Module 8: top-level INT8 vector-search accelerator

`rtl/int8_vector_search.v` packages the existing modules as one synthesizable
hardware block. It adds connections, not a new state machine or pipeline stage.
The external system now instantiates only int8_vector_search.

## Hardware hierarchy

```text
int8_vector_search
  controller: int8_search_controller
  query_buffer: int8_query_buffer
  dot_product: int8_dot_product
    mac: int8_mac
      multiplier: int8_multiplier
      accumulator: int8_accumulator
  tracker: best_result_tracker
```

The query buffer is inside this hierarchy. The database is NOT stored here:
an external sender streams its elements into database_data. The testbench
provides the sender in simulation. A DDR/AXI/DMA memory reader is future work.

## External ports

| Port | Width/type | Meaning |
|---|---|---|
| clk | 1-bit input | Rising-edge clock shared by all modules. |
| reset | 1-bit input | Active-high synchronous reset, shared by all modules. |
| command_valid | 1-bit input | Sender has a search command. |
| command_ready | 1-bit output | Accelerator can accept the command. |
| dimensions | Unsigned 16-bit input | Elements in each vector. |
| vector_count | Unsigned 32-bit input | Database vectors to process. |
| query_valid | 1-bit input | Query element available. |
| query_ready | 1-bit output | Accelerator can accept query element. |
| query_data | Signed 8-bit input | Query element. |
| database_valid | 1-bit input | Database element available. |
| database_ready | 1-bit output | Accelerator can accept database element. |
| database_data | Signed 8-bit input | Database element. |
| result_valid | 1-bit output | Completed response is available. |
| result_ready | 1-bit input | Receiver can accept response. |
| result_error | Unsigned 2-bit output | 0 success; 1 invalid dimensions; 2 empty database. |
| result_found | 1-bit output | A winner exists for the completed successful search. |
| result_score | Signed 64-bit output | Winning dot product. |
| result_id | Unsigned 32-bit output | Winning database position, starting at zero. |

For each channel, transfer occurs at a rising edge with valid AND ready high.
Hold input payload/valid until accepted. Interpret response fields only when
result_valid is high. The accelerator holds response fields stable under result
backpressure; a ready receiver consumes them at the transfer edge.

## Source explained in order

`module int8_vector_search #(` opens the module and parameter list.
`parameter integer MAX_ELEMENTS = 4096` sets the default query capacity.
`) (` ends parameters and opens external ports. All ports are wires because
this wrapper only connects modules; its children contain the registers.
The individual port declarations are described in the table above.
`);` closes the external port list.

`localparam integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS);`
derives the address width internally. At 4096 locations it is 12 bits. At one
location it is one bit to avoid a zero-width port. Keep MAX_ELEMENTS between
1 and 65535 to match the controller's length interface. The same derived width
and capacity are passed to both controller and query buffer.

The following wire declarations name internal connections. They do not create
new copies of stored data or new registers:

- buffer_write_enable: one-bit query write permission.
- buffer_write_address: unsigned ADDRESS_WIDTH-bit query write address.
- buffer_write_data: signed INT8 query element.
- buffer_read_enable: one-bit synchronous read request.
- buffer_read_address: unsigned ADDRESS_WIDTH-bit query read address.
- buffer_read_valid: one-bit read-response marker.
- buffer_read_data: signed INT8 read response.
- dot_command_valid/ready: one-bit dot command handshake.
- dot_dimensions: unsigned 16-bit length supplied by controller.
- dot_pair_valid/ready: one-bit pair handshake.
- dot_a/dot_b: signed INT8 query/database operands.
- dot_result_valid/ready: one-bit completed vector score handshake.
- dot_score: signed 64-bit dot-product score.
- tracker_clear/enable: one-bit tracker controls.
- tracker_candidate_score: signed 64-bit completed vector score.
- tracker_candidate_id: unsigned 32-bit current vector ID.
- tracker_best_valid: one-bit running-winner flag.
- tracker_best_score: signed 64-bit running best score.
- tracker_best_id: unsigned 32-bit running best vector ID.

`int8_search_controller #(...) controller (` creates the controller instance.
`.MAX_ELEMENTS(MAX_ELEMENTS)` and `.ADDRESS_WIDTH(ADDRESS_WIDTH)` pass the
wrapper configuration to the child. `.port(signal)` connects the named child
port on the left to this wrapper's signal in parentheses.

The controller's external ports connect directly to the wrapper's corresponding
ports. Its buffer_*, dot_*, and tracker_* ports connect to the internal wires
listed above. The closing `);` ends its connection list.

`int8_query_buffer #(...) query_buffer (` creates the actual internal query
memory using the same parameters. Its write_enable/address/data connect to
buffer_write_*; its read_enable/address connect to buffer_read_*. read_valid/data
return through buffer_read_valid/data.

`int8_dot_product dot_product (` creates the dot engine. Its command ports
connect to dot_command_* and dot_dimensions, its pair ports connect to dot_pair_*
and dot_a/b, and its result ports connect to dot_result_* and dot_score.
The engine contains the existing MAC, multiplier, and accumulator.

`best_result_tracker tracker (` creates the winner register/comparison block.
Its clear/enable and candidate inputs connect to the tracker control/candidate
wires. Its best_valid/score/id outputs feed the controller through the tracker
best wires. The controller routes the final response to the external interface.

Every instance receives the same clk and reset. Each `);` ends that instance's
connections. `endmodule` closes the wrapper. Blank lines provide spacing.
There is no always block: all sequencing remains inside the existing children.
The instances exist concurrently; source-code order is not execution order.

## Using the accelerator

1. Assert reset through a rising edge, then release it.
2. Transfer a command containing dimensions and vector_count.
3. Transfer exactly dimensions query elements in increasing index order.
4. Transfer database elements: all elements of vector 0, then vector 1, etc.
5. Accept the final result using result_valid/result_ready.
6. Start the next command and load its new query.

Example query [1,-2,3] with database [4,5,-6], [1,1,1], [1,1,1]:
command dimensions=3, vector_count=3; stream query 1,-2,3, then database
4,5,-6,1,1,1,1,1,1. Result: error=0, found=1, score=2, ID=1.
The equal score for vector 2 loses to smaller ID 1.

Zero/over-capacity dimensions return error 1. Zero vector_count returns error 2.
Dimension errors have priority. Error commands consume no query/database data.
Still accept the response. Reset aborts work or pending output; a fresh query
must be loaded afterward, even though the buffer's memory itself is not reset.

## Verification

The new simulation-only testbench instantiates only this wrapper and drives/checks
its public ports. It does not access child registers or internal connections.
It checks known scores/IDs, all-negative scores and ties, INT8 extremes, varied
searches, full-capacity queries, configuration capture, query/database pauses,
result backpressure, blocked extra inputs, invalid commands, reset/abort/reload,
continuous database valid with early input, and an already-ready result receiver.

Observed successful results on 2026-10-14:

```text
PASS: top-level vector search capacity=5 checked 24 searches plus reset recovery.
PASS: top-level vector search capacity=1 checked 23 searches plus reset recovery.
PASS: top-level vector search capacity=4096 checked 24 searches plus reset recovery.
```

Capacity 1 omits the known three-element example. All eight module testbenches
were rerun successfully, along with the additional top-level capacity 1/4096
runs: ten successful simulations total. Compiler and simulator exited zero.

Run from vector_search:

```sh
iverilog -g2012 -s tb_int8_vector_search -o /tmp/vector_search_top_test rtl/*.v tb/tb_int8_vector_search.v
vvp /tmp/vector_search_top_test
```

The testbench defaults to capacity 5; the hardware module defaults to 4096.
Add `-Ptb_int8_vector_search.MAX_ELEMENTS=4096` to compilation for the full
capacity test, or `=1` for the minimum capacity test.

The basic single-lane exact INT8 design is complete in simulation. Synthesis,
RAM mapping, clock timing, board integration, and real-memory input have not
been verified. Four lanes, packed/wide streams, pipelining improvements and
FP32 support are deferred. Sustained processing remains one pair per four
cycles plus per-vector overhead.
