# Vector-search accelerator progress

Last checked: 2026-10-14 (America/Los_Angeles).

## Current status

The basic single-lane exact INT8 accelerator is complete in simulation.
Modules 1–8 are implemented and simulation-verified: multiplier, accumulator,
MAC, dot product, best-result tracker, query buffer, search controller, and
top-level accelerator. Details and observed results follow.

Module 1, the combinational signed INT8 multiplier, is implemented and verified.
- Hardware: `rtl/int8_multiplier.v`.
- Simulation-only testbench: `tb/tb_int8_multiplier.v`.
- Inputs: two signed 8-bit values, each from -128 through 127.
- Output: signed 16-bit product; no clock, reset, or storage.
- Exhaustive simulation ran successfully for all 65,536 input pairs.
- Actual simulator output: `PASS: all 65,536 input combinations checked.`
- Compiler and simulator both exited successfully. No source corrections were needed.
- All baseline modules including top-level integration are implemented.
  FPGA synthesis/deployment and FP32 support have not been implemented/verified.

## Reproduce verification

Run from the vector_search directory:

```sh
iverilog -g2012 -s tb_int8_multiplier -o /tmp/vector_search_multiplier_test rtl/int8_multiplier.v tb/tb_int8_multiplier.v
vvp /tmp/vector_search_multiplier_test
```

The compiled simulation artifact is stored in `/tmp`, outside the source tree.

## Working agreement

Build and explain one module at a time. Explain widths, signedness, behavior,
and the distinction between synthesizable hardware and simulation code.
Answer the user's questions before advancing. Implement further modules only
when the user requests continuation.
Only mark tests passed after observing successful execution.
The user authorized Module 2 on 2026-10-14; it is now complete. Wait for questions
or an explicit request before implementing another module.

## Design direction (planned, not implemented)

- Exact dot-product search, returning the top-1 vector ID and score.
- Software initially normalizes vectors. Smaller ID wins equal scores.
- Runtime dimensions and database size; internal query buffer, streamed database.
- Proposed query capacity: 4,096 elements; proposed INT8 accumulator: signed 64-bit.
- Eventually four arithmetic lanes with valid/ready streams; transfer at a clock
  edge when both signals are high.
- Proposed 128-bit chunks contain four 32-bit slots. INT8 uses each slot's low
  eight bits; FP32 uses the entire slot. Ignore unused final-chunk slots.
- Lane k processes indices k, k+4, k+8, ...; proposed reduction is (A0+A1)+(A2+A3).
- Future throughput target: four element pairs per cycle, not yet achieved.
- FP32 is deferred; Berkeley HardFloat has not been integrated or verified.
  Proposed arithmetic: separate rounded multiply/add, round-to-nearest ties-even.
  Reference tests must match accumulation and reduction order.
- Planned corner cases include invalid dimensions, empty database, partial chunks,
  all-negative scores, ties, stream stalls, output backpressure, and active reset.
  Initialize the best result from the first completed vector.

## Prior discussion and complete handoff

`CONTEXT.md` preserves the supplied design context, previous questions and answers,
FP32 policy proposals, and teaching preferences. Its pre-verification status is
historical; the successful simulation recorded above supersedes that status.


## Module 2: integer accumulator (verified 2026-10-14)

- Hardware: `rtl/int8_accumulator.v`; testbench: `tb/tb_int8_accumulator.v`.
- Signed 16-bit product input; signed 64-bit running sum.
- Rising-edge updates; active-high synchronous reset and clear.
- Priority: reset > clear > enable > hold. Reset/clear discard that edge's product.
- Explicit sign extension preserves negative products before addition.
- One product accepted per enabled clock edge; no stream handshake yet.
- Actual simulation output: `PASS: accumulator checked for 9232 clock cycles.`
- Verified signed boundaries, disabled holds, synchronous reset/clear and priority,
  active reset, full 4096-element positive/negative sums, and varied sequences.
- Compiler and simulator exited successfully. Synthesis/timing have not been tested.
- Fixed-width arithmetic wraps on overflow; no saturation/overflow flag.
- Connected to the multiplier by Module 3, `rtl/int8_mac.v` (see below).
- Full line-by-line explanation and rerun commands: `docs/int8_accumulator.md`.

```sh
iverilog -g2012 -s tb_int8_accumulator -o /tmp/vector_search_accumulator_test rtl/int8_accumulator.v tb/tb_int8_accumulator.v
vvp /tmp/vector_search_accumulator_test
```


## Module 3: multiply-accumulate (verified 2026-10-14)

- User requested the next module; implemented one single-lane MAC.
- Hardware: `rtl/int8_mac.v`; testbench: `tb/tb_int8_mac.v`.
- Instantiates the existing signed INT8 multiplier and 64-bit accumulator.
- Signed 8-bit a/b inputs, internal signed 16-bit product, signed 64-bit sum.
- Enabled rising edges add a*b; reset > clear > enable > hold.
- No product pipeline register; the clock path includes multiplication and addition.
- Clear on a separate edge before consuming the first pair of a new vector.
- Actual simulator output: `PASS: MAC checked for 73743 clock cycles, including all 65,536 INT8 pairs.`
- Verified known dot product -24, stalls, zero products, controls and priorities,
  reset during a sum, exhaustive input pairs, and 4096-element extreme vectors.
- Compiler and simulator exited successfully; synthesis/timing not measured.
- No dimensions, done flag, query storage, stream handshake, or search FSM yet.
- Detailed explanation and commands: `docs/int8_mac.md`.
- Wait for the user's questions or request before implementing another module.


## Module 4: single-lane dot product (verified 2026-10-14)

- User authorized the next module: `rtl/int8_dot_product.v`.
- Testbench: `tb/tb_int8_dot_product.v`; explanation: `docs/int8_dot_product.md`.
- Runtime unsigned 16-bit dimensions, signed INT8 pairs, signed 64-bit score.
- Three valid/ready channels: command, pair, result. One command active at a time.
- FSM: IDLE -> CLEAR -> RUN -> RESULT -> IDLE; zero length skips RUN.
- MAC accepts exactly dimensions pairs; input stalls hold sum/count.
- Completed score remains stable until result handshake; extra pairs are blocked.
- Synchronous reset aborts work and pending results; handshake outputs gated low
  while reset is asserted. Reset through a rising edge before use.
- No query memory here; 0..65535 pairs supported by the count width. Future
  query-buffer/search controller must enforce its actual capacity (proposed 4096).
- Actual output: `PASS: dot product checked 8 completed vectors over 4521 clock cycles, including stalls and reset recovery.`
- Covers lengths 0,1,3,6,257,4096, signed values, input/output stalls, busy commands,
  early/extra pairs, latched length, and reset during CLEAR/RUN/RESULT.
- Compiler and simulator exited successfully. No synthesis/timing verification.
- Still one lane; query storage, full search FSM, vector IDs and top-1 selection
  are not implemented. Wait for questions or an explicit continuation request.


## Module 5: best-result tracker (verified 2026-10-14)

- User authorized the next module: `rtl/best_result_tracker.v`.
- Testbench: `tb/tb_best_result_tracker.v`; explanation: `docs/best_result_tracker.md`.
- Signed 64-bit candidate score and unsigned 32-bit vector ID.
- Stores highest score; smaller unsigned ID wins equal scores.
- First candidate accepted via !best_valid so all-negative searches work.
- Enable-controlled; synchronous reset > clear > enable > hold.
- Reset/clear invalidate result and zero placeholders; candidate on that edge
  is discarded. Empty search remains best_valid=0.
- best_valid marks a running winner, not search completion.
- Actual output: `PASS: best-result tracker checked for 28 clock cycles.`
- Checks cover negative scores, signed limits, unsigned ID boundaries, ties,
  duplicate candidates, disabled inputs, controls and clearing between searches.
- Compiler and simulator exited successfully; synthesis/timing not tested.
- Not yet wired to dot-product results; future controller coordinates enable.
- Roughly three baseline modules remain: query buffer, search controller, top-level
  integration, each with tests plus end-to-end verification. Four lanes and FP32
  remain deferred. Wait for questions or an explicit request to continue.


## Module 6: INT8 query buffer (verified 2026-10-14)

- User authorized the next module: `rtl/int8_query_buffer.v`.
- Testbench: `tb/tb_int8_query_buffer.v`; walkthrough: `docs/int8_query_buffer.md`.
- Parameterized capacity, default 4096 signed INT8 elements (4 KiB), default
  12-bit unsigned addresses. Capacity must be >=1; leave address width derived.
- One synchronous read and one write per clock; enables rather than handshakes.
- read_valid marks the response after the read-request edge. Controller must
  account for latency, buffer responses if needed, and align database elements.
- Simultaneous same-address read/write returns old data (read-first).
- Invalid representable addresses: ignore writes, return no valid read response.
- Reset clears output/valid and suppresses reads/writes; memory is not reset.
- Unwritten locations remain undefined; controller must track query loading and
  validate lengths before address truncation. No loaded-state tracking here.
- Actual results: capacity=5 passed 24 cycles; capacity=1 passed 14 cycles;
  capacity=4096 passed 8204 cycles. Compiler and simulator exited successfully.
- Checks cover every location, signed data, latency, hold, simultaneous accesses,
  reset/write priority, memory preservation, and out-of-range accesses.
- Synthesizable RTL; FPGA RAM inference and timing not yet measured.
- Still standalone. Roughly two baseline modules remain: search controller and
  top-level integration, plus their tests and full accelerator verification.
- Wait for questions or an explicit request before proceeding.


## Module 7: INT8 search controller (verified 2026-10-14)

- User authorized next module: `rtl/int8_search_controller.v`.
- Testbench: `tb/tb_int8_search_controller.v`; walkthrough: `docs/int8_search_controller.md`.
- Controller is separate RTL with explicit child interfaces; testbench wires actual
  query buffer, dot-product engine and tracker to verify integrated behavior.
- Command: unsigned 16-bit dimensions, unsigned 32-bit vector_count.
- Query/data streams: one signed INT8 element per valid/ready transfer.
- Query loaded once per command, reused for database vectors, IDs assigned 0..N-1.
- Single outstanding database element; synchronous buffer latency handled via
  READ_QUERY/WAIT_QUERY and registered operands held until dot pair acceptance.
- Final result includes signed 64-bit score, unsigned 32-bit ID, found and error.
- Search policy now concrete: dimensions 0 or >capacity => error 1; empty database
  => error 2; dimensions checked first. Invalid commands consume no elements.
- Error/success responses held until result_ready. best_valid is not completion.
- All children must share reset; reset aborts work and requires fresh query load.
- Actual simulation results: capacities 1,5,4096 each passed 9 searches plus reset
  recovery, including negative ties, varied values, full capacity, input/output
  pauses, invalid commands, latched configuration and reset during activity.
- Compiler/simulator exited successfully. No synthesis/timing measurement.
- Baseline processes one pair every four cycles plus per-vector overhead; no
  performance target claim. Four lanes, 128-bit chunks, and FP32 are deferred.
- Remaining baseline work: reusable top-level wrapper and its external-interface
  integration test. Do not implement another module until the user requests it.


## Module 8: top-level accelerator (verified 2026-10-14)

- User authorized next module: `rtl/int8_vector_search.v`.
- Testbench: `tb/tb_int8_vector_search.v`; walkthrough: `docs/int8_vector_search.md`.
- Instantiates controller, query buffer, dot engine (with MAC children), and
  tracker, sharing clock/reset and matching capacity/address configuration.
- Public interface contains only command, query stream, database stream, and
  result response. No new arithmetic, pipeline stages, or FSM behavior added.
- Query storage is internal; database remains external streamed input.
- Testbench uses only public ports, no internal hierarchy references.
- Actual passes: capacity=5, 24 searches; capacity=1, 23 searches; capacity=4096,
  24 searches; each also verified reset recovery. Capacity 1 skips the 3D example.
- All eight module testbenches also passed the regression. Ten successful runs
  total including the two additional top-level parameter configurations.
- Tests include known score/ID, negative ties, signed extremes, full capacity,
  varied consecutive commands, input/output stalls, invalid commands, resets,
  early/continuous database valid, and an already-ready result receiver.
- Baseline RTL/integration complete in simulation. Synthesis, memory mapping,
  timing, board deployment and external database reader/DMA remain unverified.
- Later improvements remain optional: more throughput, four lanes, 128-bit or
  packed transfers, FP32. Wait for questions or explicit follow-up instructions.
