# Testing the current queued service

One command runs all retained tests:

```sh
.venv/bin/python tests/run_queued_search_tests.py
```

The runner rebuilds the deterministic text/vector dataset, disables unrelated
inherited ROS pytest plugins, and starts tests/test_queued_cosine.py. It does not
change system settings. Python packages are pinned in requirements-dev.txt;
Icarus Verilog must be installed separately. Simulator builds and JUnit reports
use pytest temporary directories; generated retrieval results use build/.

## Coverage

There are eleven pytest cases:

| Cases | What is tested |
|---:|---|
| 1 | Spatial normalizer: independent numerical references, ordered tags, backpressure and reset. |
| 2 | Complete-query FIFO: depths 1 and 3, partial packets, full state, wraparound and simultaneous enqueue/pop. |
| 1 | Ping-pong prefetch: random memory/consumer stalls, in-order data, alternating ownership and overlap. |
| 2 | Top-K: K=1 and K=5, signed scores, ties, ordering and clear. |
| 1 | Small integrated service: partial chunks, negative/zero vectors, queue wrap, K greater than candidate count. |
| 1 | 1000-query corpus service: full FIFO before run, every top-5 field, frozen DB, stage overlap, reset/reload. |
| 3 | Existing Verilog multiplier, accumulator and MAC unit benches; exhaustive INT8 pairs remain covered. |

The first eight cases use cocotb to drive current RTL directly through public
ports. The last three compile/run the small arithmetic benches in tb/.

Useful selections:

```sh
# All fast checks, excluding the ~four-minute corpus workload:
.venv/bin/python tests/run_queued_search_tests.py -k 'not queued_cosine_search_7'
# Only the corpus workload, with simulator progress:
.venv/bin/python tests/run_queued_search_tests.py -k queued_cosine_search_7 -s
# Only arithmetic unit benches:
.venv/bin/python tests/run_queued_search_tests.py -k arithmetic
```

## Python files

| File | Purpose |
|---|---|
| tests/run_queued_search_tests.py | Dataset preparation and pytest entry point. |
| tests/test_queued_cosine.py | Parameter matrix, simulator builds, XML checks, arithmetic bench runner. |
| tests/cosine_reference.py | Pure independent fixed-point cosine model, packing and signed-bit helpers. |
| tests/queued_cocotb_utils.py | Clock, cycle snapshots, signal driving and reset. |
| tests/cocotb_normalizer_pipeline.py | Pipelined normalization tests. |
| tests/cocotb_query_queue.py | Complete-query FIFO tests. |
| tests/cocotb_db_ping_pong.py | Prefetch bank tests using a variable-stall memory responder. |
| tests/cocotb_topk.py | Ranking tests. |
| tests/cocotb_queued_search.py | Integrated small and 1000-query scoreboards, content artifacts. |

The independent reference uses Python products, math.isqrt and integer division;
it does not copy the hardware's iterative/spatial stage operations. Nonzero
vector references are also compared with mathematical cosine within 2/2^30.
Packed partial chunks use deliberately nonzero padding to verify lane masking.

## Clock and sampling

Bench starts a 10 ns simulated clock. Its cycle helper:

1. Waits for a falling edge and drives inputs.
2. Waits for combinational settling and captures a pre-edge snapshot.
3. Waits for the rising edge and ReadOnly, then captures updated outputs.

Pre-edge ready/valid values identify transfers. Post-edge values check register
updates. Drivers hold stalled transactions stable. Results are checked under
backpressure, and simulation-time timeouts catch deadlocks. Reset is applied
before converting initially unknown data to Python integers.

All simulation helpers are now local to the current tests. They have no imports
from removed legacy runners. Earlier single-query test suites were removed;
the exhaustive primitive arithmetic benches were retained because the current
lane datapath still uses those modules.

## Result artifacts and scope

The corpus test records verified matches with original text in
build/queued_demo/results.jsonl and counters in summary.json. demo/show_results.py
prints one request. docs/QUEUED_VECTOR_DB.md describes the protocol and workload.
Simulation timing uses an assumed clock; it does not establish FPGA clock fit.


Post-cleanup verification on 2026-10-16: all 10 fast cases passed, followed by
the full 1000-query integration case with all 5000 ranked entries matching.
All eleven retained cases therefore pass with legacy files removed.
