# Module 6: INT8 query buffer

Store a query once, then reread its elements for each database vector. This
module supplies the storage only; the future search controller will track how
many elements are loaded and coordinate query reads with database input.

## Ports and parameters

| Name | Width/type | Purpose |
|---|---|---|
| MAX_ELEMENTS | Integer parameter, default 4096 | Number of signed INT8 locations. Must be at least 1. |
| ADDRESS_WIDTH | Integer parameter, derived by default | Enough bits to address the locations; normally leave it derived. |
| clk | 1-bit input wire | Rising-edge clock. |
| reset | 1-bit input wire | Synchronous reset of read output/valid; suppresses reads and writes. |
| write_enable | 1-bit input wire | Write one location at this edge. |
| write_address | Unsigned ADDRESS_WIDTH-bit input wire | Location to write. |
| write_data | Signed 8-bit input wire | Query element to store, -128 through 127. |
| read_enable | 1-bit input wire | Request one read at this edge. |
| read_address | Unsigned ADDRESS_WIDTH-bit input wire | Location to read. |
| read_data | Signed 8-bit output reg | Registered read value. |
| read_valid | 1-bit output reg | This cycle contains the response to an accepted read. |

4096 elements need 4096*8=32768 bits, or 4096 bytes (4 KiB).
The default address width is 12, allowing addresses 0 through 4095.
Do not override ADDRESS_WIDTH with a value too small for MAX_ELEMENTS.

This module has independent read/write enables, not valid/ready streams. It
can service one read and one write per cycle when not reset. There is no
response-ready input: read_valid cannot wait for the consumer. A future
controller must arrange to consume/buffer the response or pause read requests.

## Source explained from top to bottom

`module int8_query_buffer #(` begins a parameterized module. The #(...) list
sets hardware configuration at elaboration, not at runtime.

`parameter integer MAX_ELEMENTS = 4096,` chooses the default storage depth.
`parameter integer ADDRESS_WIDTH = (MAX_ELEMENTS <= 1) ? 1 : $clog2(MAX_ELEMENTS)`
calculates address bits. The ternary expression means choose 1 for capacity 1,
otherwise choose ceiling(log2(capacity)). For capacity 5, this produces 3 bits;
for 4096 it produces 12. The minimum of one bit avoids an invalid zero-width
port when capacity is one.

`) (` ends the parameter list and opens the port list. The port declarations
are described in the table. Input wire values are driven externally. Output
reg values are assigned in the clocked block. `);` closes the port list.

`reg signed [7:0] memory [0:MAX_ELEMENTS-1];` declares an array of MAX_ELEMENTS
signed eight-bit words. The [7:0] describes each word; the second range describes
the array indices. This is one query element per address. It is synthesizable
storage, not a software allocation. Actual FPGA memory mapping is tool/device
dependent and has not been checked by synthesis.

`always @(posedge clk) begin` samples controls and addresses on rising edges.
`if (reset) begin` gives synchronous reset priority.
`read_data <= 8'sd0;` sets signed 8-bit read output to zero.
`read_valid <= 1'b0;` marks that output invalid. Reset does not loop through or
clear the memory array. With reset high, the normal branch is skipped, so no
read or write occurs.

`end else begin` selects normal operation.
`read_valid <= 1'b0;` defaults the response-valid bit low for this edge.

`if (write_enable && (write_address < MAX_ELEMENTS))` requires write permission
and an in-range address. && is logical AND; < compares unsigned address values
against capacity.
`memory[write_address] <= write_data;` stores one element at the selected address.

`if (read_enable && (read_address < MAX_ELEMENTS)) begin` similarly checks a read.
`read_data <= memory[read_address];` schedules the selected stored value into
the output register.
`read_valid <= 1'b1;` marks the new read response valid. This later assignment
overrides the earlier default-to-zero assignment in the same block.

The three end statements close the read branch, normal-operation branch, and
clocked block. `endmodule` closes the module. Blank lines separate code visually.

All <= assignments are nonblocking: right sides use pre-edge values before
updates take effect. Therefore a read and write to the same address on one edge
return the OLD value and store the new value. Reading that address on a later
edge returns the new value. Synthesis must preserve this read-first behavior;
no device mapping/timing claims have been verified yet.

## Read timing

1. Set read_enable=1 and provide an address before rising edge E.
2. At E, the buffer samples the request.
3. After E's register update, read_data contains that location and read_valid=1.
4. Another synchronous module can capture this response at the following edge.

A continuous sequence of requests gives one response each cycle after the
initial synchronous-read latency. When requests stop, read_valid goes low on
the next edge and read_data retains its last value. read_valid may stay high
across consecutive responses; it need not pulse low between reads.

Example: load [1,-2,3] at addresses [0,1,2], then request those addresses in
order for each database vector. Pair the resulting elements with the matching
database elements before handing them to int8_dot_product. The future search
controller must account for the read latency and dot-product pair_ready.

## Bounds, initialization, and reset

For capacity 5 with 3-bit addresses, 5,6,7 are representable but invalid. Writes
to them are ignored. Reads return no valid response and retain read_data.
For capacity 4096 every 12-bit address is in range. The comparison cannot detect
an address already truncated by the caller: assigning 4096 to 12 bits becomes
zero. The controller must validate dimensions and addresses before truncation.

Memory contents are undefined until written. read_valid indicates an in-range
read response; it does NOT certify that a location was previously initialized.
Only read loaded locations. Reset clears the response registers and preserves
stored memory, but future search control must invalidate its load state and
require the appropriate query loading after an aborted search.

## Verification

`rtl/int8_query_buffer.v` describes synthesizable hardware. The testbench uses
simulation-only tasks, delays, generated clocks, assertions, and a timeout.
It writes and reads every location and checks signed patterns, disabled writes,
read-output hold, synchronous timing, simultaneous same/different address
operations, representable out-of-range accesses, and reset preserving memory
while suppressing a write.

Observed successful results on 2026-10-14:

```text
PASS: query buffer capacity=5 checked for 24 clock cycles.
PASS: query buffer capacity=1 checked for 14 clock cycles.
PASS: query buffer capacity=4096 checked for 8204 clock cycles.
```

Run from vector_search (default test capacity is 5):

```sh
iverilog -g2012 -s tb_int8_query_buffer -o /tmp/vector_search_query_buffer_test rtl/int8_query_buffer.v tb/tb_int8_query_buffer.v
vvp /tmp/vector_search_query_buffer_test
```

Add `-Ptb_int8_query_buffer.MAX_ELEMENTS=1` or
`-Ptb_int8_query_buffer.MAX_ELEMENTS=4096` to compilation to test other capacities.
No synthesis, FPGA memory inference, or clock timing has been verified.
