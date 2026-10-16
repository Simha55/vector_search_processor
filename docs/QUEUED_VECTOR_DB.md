# Queued top-K vector database service

This revision implements the user's next system goal: resident database-vector
storage, alternating prefetch banks, a complete-query FIFO, cross-vector stage
overlap, and top-K results carrying the original request ID. Earlier single-query prototypes were removed during cleanup; the active source
tree contains only this queued service and its required arithmetic modules.

## System structure

```text
HOST                                                  HARDWARE
text documents + INT8 vectors --> database load --> resident vector memory
                                                          |
                                               pipelined memory responses
                                                          |
                                               ping-pong vector banks A/B
                                                          |
1000 query vectors + request IDs --> complete-query FIFO --> parallel MAC lanes
                                                          |
                                                  registered adder trees
                                                          |
                                            tagged sqrt/division pipeline
                                                          |
                                              sorted running top-K stage
                                                          |
request ID, rank, score, document ID <---------- held result stream
              |
       host fetches original text by document ID
```

The default `queued_cosine_search` configuration is DIMENSIONS=64, LANES=8,
DATABASE_VECTORS=24, QUERY_DEPTH=1000, TOP_K=5, MEMORY_LATENCY=2.
Parameters are hardware configuration, not per-request controls. DIMENSIONS
must be 1..65535; all counts/depths, TOP_K, LANES and MEMORY_LATENCY must be >=1.
TOP_K may exceed the number of valid database candidates: fewer results return.
A fixed dimension and fixed database size keep request framing unambiguous.

## New RTL files

| File | Responsibility |
|---|---|
| rtl/queued_cosine_search.v | Full service, scheduler, host interface, query association and result ranks. |
| rtl/cosine_query_queue.v | FIFO of complete queries, with partial-packet input tracking and request IDs. |
| rtl/cosine_database_memory.v | Host-loaded resident vector words and latency-configurable, stallable read pipeline. |
| rtl/cosine_db_ping_pong.v | Prefetch one vector into a free bank while the other bank is consumed. |
| rtl/int8_cosine_accumulator.v | Three MACs per lane and registered balanced reduction levels; emit tagged P/Q/D totals. |
| rtl/cosine_normalizer_pipeline.v | Spatial square-root/division pipeline with ordered vector tags and global backpressure. |
| rtl/cosine_topk.v | Sorted score/ID insertion, signed scores and deterministic ties. |

Existing int8_mac, int8_multiplier and int8_accumulator are reused. Superseded single-query engines and their tests have been removed. The original
dot-product baseline can still be inspected in local Git commit df57b97.

## Database storage and ping-pong ownership

A vector occupies CHUNKS=ceil(DIMENSIONS/LANES) packed words. Word address is:

    document_id * CHUNKS + chunk_index

Lane k occupies bits [8*k +: 8], as in the previous packed cosine interface.
Unused final-word lanes may contain anything; the accumulator masks them.

The resident store holds all database vectors for this local implementation.
The two additional prefetch banks each hold ONE VECTOR, not half the database.
While A is being consumed, responses for the next vector fill B. After A drains,
the consumer switches to B and the loader can reuse A for the following vector.
If a bank is still full, the loader waits; it never overwrites that bank.

The loader tracks issued requests separately from received responses. Only a
fully received vector is marked ready. Responses must arrive in request order.
The built-in memory pipeline can accept a word request each cycle; its response
latency is configurable. Full-bank/consumer stalls propagate into that pipeline.
The unit test also uses random memory/request/consumer stalls independently.

The resident store is synthesizable RTL storage, not a DDR controller or a live
external vector-database network connection. Its request/response boundary can
be replaced with a device-specific memory reader later. Physical RAM inference,
external memory bandwidth and FPGA port timing are not established by simulation.

## Query buffering

The input is a stream of fixed-size query packets, each CHUNKS packed words.
Every accepted word has query_valid && query_ready at a rising edge. The source
holds data until accepted. query_id is captured on the first word of a packet;
using the same ID throughout the packet is recommended.

A packet is invisible to the scheduler until every chunk has been written.
queued_queries counts complete pending queries INCLUDING the active query. A
partial packet occupies the current tail slot but does not increment that count.
When all QUERY_DEPTH slots are occupied, query_ready goes low. Pop happens only
when the final result item of the active query transfers, freeing its slot.
Simultaneous complete enqueue and pop leave occupancy unchanged. Slots wrap at
the configured depth, including non-power-of-two depths.

The end-to-end demo proves all 1000 queries are buffered BEFORE setting
run_enable=1. In normal use ingress can continue while searches run, provided
space remains. The FIFO is bounded, not an unlimited request collector.

At the default dimensions/depth, query vector storage is 64,000 bytes, plus
4,000 bytes of request IDs. Prefetch banks add 128 bytes and resident database
vectors add 1,536 bytes. These are logical payload capacities, not device resource
utilization estimates; pointers, ranking state and deep normalization registers
also consume resources.

## Overlap and pipeline behavior

There are three observable forms of concurrency:

1. Input queries can be queued while existing work is processed.
2. One database bank is filled while the other bank supplies MAC operands.
3. New vectors accumulate while older vectors traverse normalization.

Each lane contains dot, query-square and database-square MACs. Registered tree
levels reduce their totals. The accumulator waits the required tree depth before
emitting a stable tagged sum tuple, then can start another vector without waiting
for its cosine score. There are vector command/clear/reduction boundary bubbles;
the accumulator does not accept a new VECTOR every cycle.

The new normalizer has an input register, 64 registered square-root steps, and
126 registered divide steps. It can accept an independent sum tuple every cycle
when ready. Validity, sign, zero-norm status and vector ID advance alongside the
numerical data. If the final output is blocked, every pipeline stage freezes,
including its payload and metadata. This is a fully spatial pipeline, not the
previous shared iterative arithmetic unit.

The normalization arithmetic is still the exact same Q2.30 approximation:

    denominator = isqrt((Q*D) << 64)
    magnitude = min(2^30, (abs(P) << 62) // denominator)
    score = sign(P) * magnitude

A zero denominator is replaced internally with one solely to keep the pipeline
safe; its zero-norm flag causes the candidate to be excluded from ranking.
No Verilog real, behavioral sqrt or behavioral division implements this path.
The square-root stages use shifts/compare/subtract; division stages use binary
long division. Resource cost is much larger than the original iterative block.

The scheduler processes one QUERY at a time, with many DATABASE VECTORS in
flight through its stages. It waits for the active query's pipeline to drain
and its result list to transfer before activating the next query. It does not
interleave several queries through the same ranking state. Query-to-query drain
latency and per-vector bubbles remain optimization opportunities.

No FPGA frequency or GPU speedup claim follows from accepting a packed beat
per active accumulation cycle. Deep registers, memory ports and wide arithmetic
must be mapped and timed on the target device.

## Host protocol

All transfers occur on rising edges with both valid and ready high.

1. Assert reset through a rising edge, then release it.
2. Keep run_enable=0. Load every database word with database_write_valid,
   database_write_address and database_write_data, honoring database_write_ready.
3. Deassert write_valid, then pulse database_commit. database_loaded goes high.
   Commit is a host guarantee that ALL required locations were loaded; the RTL
   does not maintain a per-location initialization bitmap.
4. Submit query packets. query_ready remains low until the database is committed.
5. Set run_enable=1. It stays enabled to process the complete queue autonomously.
6. Consume the result stream, honoring result_valid/result_ready.

Database writes/commit are blocked while there is an active, queued or partially
written query. They are also blocked with run_enable=1. To update the database,
first finish/drain all work and disable run. An accepted write invalidates the
commit; recommit after the full desired contents are valid. Query acceptance is
blocked during a host write or commit to avoid simultaneous reconfiguration.

run_enable gates starting the next query. Lowering it does not abort an already
active query. Reset aborts all work, clears FIFO/validity/ownership and invalidates
the database commit. Large memory arrays are not cleared. Reload/recommit and
submit fresh requests after reset; old pending responses are discarded.

## Results and top-K semantics

Each response item contains:

| Port | Meaning |
|---|---|
| result_query_id | Original request ID, not the database ID. |
| result_rank | Zero-based rank within this response list. |
| result_count | Number of valid returned candidates, at most TOP_K. |
| result_vector_id | Zero-based database/document position. |
| result_score | Signed 32-bit Q2.30 cosine score. |
| result_last | Final item for this query. |
| result_error | 0 success; 2 no defined cosine candidates. |

Scores descend; equal fixed-point scores use ascending unsigned document ID.
All-negative scores remain valid. Database zero vectors are skipped. A zero
query, or an entirely zero database, yields a SINGLE error response with count=0,
rank=0, last=1, score=0 and ID=0 placeholders. This differs intentionally from the
earlier prototype's abort-on-first-zero policy: the queued service drains every
database vector for each query to preserve continuous request framing.

Response payloads are stable while ready is low. An active query remains in its
FIFO slot until the final item transfers. TOP_K is a compile-time parameter.
The ranking stage uses combinational insertion into K registered entries; large
K may require a different architecture for timing.

## Text/vector demo and honest scope

Run:

    .venv/bin/python tests/run_queued_search_tests.py

Or run only the 1000-query integration configuration with visible progress:

    .venv/bin/python tests/run_queued_search_tests.py -k queued_cosine_search_7 -s

`demo/build_vector_db.py` creates:

- data/documents.jsonl: 24 locally authored tutorial documents with real text,
  titles and positional IDs.
- data/vector_database.json: 64-dimensional INT8 TF-IDF vectors, vocabulary,
  IDF weights and representation metadata.
- data/queries_1000.jsonl: 1000 deterministic text requests and their vectors.

These are lexical TF-IDF representations, not neural embeddings or a public
production benchmark. Requests are generated from document titles and snippets,
so this is a controlled retrieval/integration workload rather than an independent
semantic generalization test. No model download or hosted service is needed.

Only vectors enter RTL. Text content lives in the host document store. Returned
IDs select original documents in the result artifact, demonstrating the usual
ID-to-content retrieval step of a vector database.

The integration scoreboard independently calculates all database cosine scores
with Python integer arithmetic, sorts top-K, and checks every hardware score,
ID, rank, request ID, count and last flag. It tests full-queue backpressure,
partial-packet protection, database write freezing, nonzero padding, output stalls,
queue wraparound in the small configuration, negative and zero vectors, and
reset/reload recovery. Block tests separately exercise reset with in-flight
normalization, bank fill and partial queue state.

Generated reviewable outputs are:

- build/queued_demo/results.jsonl: each query plus actual verified matches and
  their original document text.
- build/queued_demo/summary.json: request counts, correctness, retrieval metric,
  hardware counters and simulated cycle totals.

The 10 ns testbench clock is an assumption for simulation. Its cycle-based time
is not an achieved FPGA implementation frequency or a hardware benchmark.

## Observability

- bank_switches counts completed bank consumptions (one per database vector,
  including the final bank release of each query).
- fetch_compute_overlap counts cycles where a memory response fills one bank
  while a word from the other bank is accepted by the accumulator.
- normalize_compute_overlap counts accepted input words while earlier vectors
  are in the normalization pipeline.
- normalizer_inflight counts tagged candidates currently in that pipeline.
- active_cycles counts cycles with a query active, including result backpressure.

The integration test requires both overlap counters to be nonzero, proving
actual concurrent stage activity rather than merely relying on the architecture
picture. Exact observed results are recorded below, in PROGRESS.md and summary.json.


## Verification completed on 2026-10-16

- Six block configurations passed: query queue at depths 1/3, randomized
  ping-pong stalls/latency, pipelined normalization with tags/backpressure/reset,
  and top-K at K=1/5. The normalizer test verifies consecutive output transfers.
- The integrated directed configuration passed with DIMENSIONS=7, LANES=3,
  DATABASE_VECTORS=5, QUERY_DEPTH=3, TOP_K=7, MEMORY_LATENCY=3. It exercises
  partial chunks, queue wraparound, K larger than the candidate count, negative
  scores, zero queries, and zero database vectors.
- The corpus configuration passed with ALL 1000 complete requests buffered
  before run_enable. It verified 1000 responses containing 5000 top-5 entries,
  and the score/ID/rank/count/request metadata for each item matched the reference.
- The complete integration test also reset the service, reloaded its database,
  and verified a new tagged search without stale output.
- Recorded counters: 24000 bank consumptions; 74000 simultaneous bank-fill and
  consumption cycles; 184000 accepted chunks overlapping normalization;
  571964 active cycles including result backpressure.
- The 1000-query simulation passed in 250.03 seconds of wall time. Its assumed
  10 ns test clock corresponds to 5,719,640 ns of active simulated time, which
  is not a hardware performance measurement.
- Before cleanup, the historical single-query cosine suite also passed. Current
  verification uses only the retained queued-service suite and arithmetic benches.
- Yosys read_verilog -sv, hierarchy -check, proc, opt, memory -nomap, opt, check,
  stat completed for queued_cosine_search and reported 0 problems. Default
  hierarchy has 24 INT8 MAC paths plus a norm-product multiplier (25 $mul cells)
  and 5 memory cells. This is technology-independent structural checking only;
  no target-device resource utilization or achieved timing is claimed.

Read one query's verified content results:

```sh
.venv/bin/python demo/show_results.py --request-id 42
```

A readable sample report is build/queued_demo/report.md. The raw result and
summary artifacts live in the ignored build/ directory; the corpus, workload
builder, RTL, tests and instructions are source files that reproduce them.


## Source cleanup

The current tree has one service top-level, ten RTL files total, one Python test
entry point, eight cocotb configurations and three arithmetic unit benches.
Legacy single-query controllers, buffers, engines, trackers and their associated
tests/documentation were removed. The pure Python reference now lives in
tests/cosine_reference.py; the current cycle/reset helpers are self-contained
in tests/queued_cocotb_utils.py. See docs/COCOTB_TESTING.md for the retained suite.
