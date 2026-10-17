# Project progress

Last checked: 2026-10-16 (America/Los_Angeles).

## Current implementation

The active design is `rtl/queued_cosine_search.v`: exact cosine search over a
resident INT8 vector database, complete-query FIFO, two alternating vector
prefetch banks, parallel MAC lanes, registered reductions, spatial normalization
and sorted top-K results. Scores are signed Q2.30. Requests carry IDs; outputs
carry request ID, rank, candidate ID, score, count and last.

Default parameters: 64 dimensions, 8 lanes, 24 database vectors, 1000 query
slots, top-5 results and memory latency 2. Text content stays on the host.
Database writes require an idle, empty service and an explicit commit. Zero-norm
candidates are skipped; no valid candidate returns error 2. Reset flushes work
and requires database reload/recommit and fresh queries.

The scheduler handles one query at a time while overlapping different database
vectors across fetch, accumulation and normalization. Query ingress can continue
while space remains. The normalizer has 64 sqrt and 126 divide stages, with
validity/tags and global backpressure. This costs substantially more hardware
than an iterative unit. FPGA device mapping, RAM/DSP fit, clock timing, board
integration, power and GPU comparisons remain unverified.

## Verification

The corpus workload passed on 2026-10-16: all 1000 complete queries were buffered
before compute, then all 5000 top-5 scores/IDs/ranks/request tags matched the
independent Python reference. Twenty-four locally authored documents use
64-dimensional quantized TF-IDF features; requests derive from titles/snippets.
This is a controlled lexical retrieval test, not a neural semantic benchmark.
Observed source-document recall@5 was 1.0 on that workload.

Observed counters: 24000 bank consumptions, 74000 fill/consume overlap cycles,
184000 chunks overlapping normalization, 571964 active simulated cycles. The
10ns clock is assumed, not an achieved FPGA frequency. Yosys structural/process/
memory checking reported 0 problems; 25 multipliers and 5 memory cells were
inferred for the default service before cleanup.

One command runs current verification:

```sh
.venv/bin/python tests/run_queued_search_tests.py
```

It runs eight cocotb configurations plus three arithmetic Verilog unit benches.
The multiplier/MAC benches retain exhaustive INT8 input-pair coverage. The
reference model lives in tests/cosine_reference.py and does not import a legacy
runner. Results/content are in build/queued_demo/results.jsonl and summary.json.
The content viewer is demo/show_results.py --request-id 42.

## Cleanup on 2026-10-16

At the user's request, removed 31 obsolete files: 8 superseded RTL modules,
8 obsolete Verilog benches, 7 legacy Python test/runner/helper files, and
8 outdated context/design documents. Retained the ten RTL files needed by the
current queued service, its cocotb tests, three still-relevant arithmetic unit
benches, corpus/demo sources and current documentation. Simplified the common
helpers, extracted the pure reference, and refreshed README/testing instructions.

Backup of deleted files and pre-cleanup documentation:
`/tmp/vector_search_cleanup_4wlbvfbx.tar.gz`.
Original dot-product baseline is recoverable from local Git commit df57b97.
No Git commit was made for the cleanup. Generated demo results and the .venv
were retained.

Post-cleanup verification actually passed: all 10 fast tests, then the full
1000-query test with 5000 matching ranked results and reset/reload recovery.
Together these cover all 11 retained pytest cases. The independent helper
extraction required no hardware behavior changes. Documentation links and
Git whitespace checks also passed.

## Working agreement and history

Explain hardware clearly, including widths/signedness and clock behavior; work
incrementally and answer questions before advancing. Keep simulation-only code
distinct from synthesizable RTL. Never claim a test passed without running it.

Evolution: signed INT8 multiplier -> accumulator -> MAC -> single-lane dot
search -> parallel cosine -> queued/prefetched/pipelined top-K service. Earlier
prototypes are no longer in the active tree. Floating point, external DDR/DMA,
query interleaving and device-specific performance optimization are future work.

Current design: docs/QUEUED_VECTOR_DB.md. Test organization: docs/COCOTB_TESTING.md.
Arithmetic teaching notes: docs/int8_mac.md and docs/int8_accumulator.md.


## Plain-Verilog schematic compatibility (2026-10-16)

DigitalJS/Yosys rejected the SystemVerilog size cast `16'(DIMENSIONS)` in the
queued top-level. Replaced it with `localparam [15:0] VECTOR_DIMENSIONS=DIMENSIONS`
and connected that constant to the accumulator port. Behavior and width remain
unchanged. Reproduced the original error locally, then verified all RTL using
plain `read_verilog` (without -sv), hierarchy checking, proc and check: 0 problems.
All 10 fast regression cases passed; the long corpus case was not rerun for this
width-equivalent syntax change. Update the website's source copy to use the fix.
