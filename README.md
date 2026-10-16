# Queued cosine vector-search accelerator

The hardware entry point is **rtl/queued_cosine_search.v**. It searches a
resident INT8 vector database, buffers complete query requests, and returns
tagged top-K IDs and signed Q2.30 cosine scores.

Default configuration: 64 dimensions, 8 lanes, 24 database vectors, 1000 query
slots, top-5 results. Two prefetch banks alternate filling and consumption.
Registered reductions feed a spatial square-root/division pipeline so later
vectors can accumulate while earlier ones normalize.

## Run tests and view results

```sh
.venv/bin/python tests/run_queued_search_tests.py
.venv/bin/python demo/show_results.py --request-id 42
```

The single test runner executes eight cocotb configurations and three retained
Verilog arithmetic unit benches. The full 1000-query configuration takes about
four minutes on this environment. For a fast check without that workload:

```sh
.venv/bin/python tests/run_queued_search_tests.py -k 'not queued_cosine_search_7'
```

Dependencies are Python 3, Icarus Verilog (iverilog/vvp), and the packages in
requirements-dev.txt. The existing .venv already contains those Python packages.

## Project layout

| Directory | Contents |
|---|---|
| rtl/ | Current queued service and its nine required submodules. |
| tests/ | Current cocotb tests, independent reference, and one runner. |
| tb/ | Multiplier, accumulator, and MAC arithmetic unit tests. |
| demo/ | Reproducible corpus builder and result-content viewer. |
| data/ | Text documents, INT8 vectors, and 1000 query requests. |
| docs/ | Current service/testing guides and arithmetic explanations. |
| build/queued_demo/ | Generated results, summary, and readable sample report. |

The demo uses 24 locally authored documents and quantized lexical TF-IDF
features, not neural embeddings or an external production benchmark. Text
content stays on the host; hardware result IDs retrieve the original documents.

The verified workload contains 1000 requests and 5000 top-5 entries matching
the independent Python reference, with observed fetch/compute and
normalize/compute overlap. See build/queued_demo/summary.json and results.jsonl.

Read [the service design](docs/QUEUED_VECTOR_DB.md) for interfaces and pipeline
behavior, [the testing guide](docs/COCOTB_TESTING.md) for test organization, and
[PROGRESS.md](PROGRESS.md) for status and decisions.

Earlier single-query/dot-product prototypes and their superseded tests have
been removed from the working tree. The original baseline remains in local
Git commit df57b97. FPGA device mapping, achieved clock timing, power, external
DDR/DMA integration, and GPU comparisons remain unverified.
