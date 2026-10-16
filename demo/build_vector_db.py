#!/usr/bin/env python3
"""Create an offline document/vector store and 1000 reproducible text requests.

This is a locally authored tutorial corpus, not an external benchmark. Features
are TF-IDF lexical vectors, not pretrained neural embeddings. Content stays on
host; only quantized vectors and positional document IDs enter the accelerator.
"""
import collections
import json
import math
from pathlib import Path
import random
import re

ROOT = Path(__file__).resolve().parents[1]
DIMENSIONS = 64
DOCUMENTS = [
    ("Cosine similarity", "Cosine similarity compares the directions of two vectors. Divide their dot product by the product of their Euclidean lengths. Scaling a nonzero vector by a positive constant preserves its direction. Zero vectors have no defined cosine similarity."),
    ("Dot products", "A dot product multiplies corresponding vector elements and adds the products. Signed integer inputs can produce negative scores. Dot products equal cosine similarity when both real vectors have unit length."),
    ("Ping pong buffering", "Ping pong buffering alternates between two memory banks. A producer fills the inactive bank while a consumer drains the active bank. Full and empty ownership flags prevent overwriting data that has not been consumed."),
    ("Pipeline stages", "A pipeline overlaps independent work in multiple processing stages. Registers separate stages and carry validity and transaction identifiers with the payload. Backpressure must preserve data and metadata when a downstream consumer stalls."),
    ("Query queues", "A query queue stores pending search requests before the arithmetic engine is ready. Each complete query needs a request identifier. A bounded FIFO reports full conditions and preserves request order across pointer wraparound."),
    ("Topk ranking", "Topk ranking retains several best candidates instead of a single winner. Sort similarity scores in descending order. Equal scores use ascending document identifiers so retrieval is deterministic. Return fewer entries when fewer valid candidates exist."),
    ("Memory banks", "Memory banks divide storage into independent arrays. Several banks can supply different vector elements in parallel. Banking only helps when the address mapping avoids conflicting accesses to the same memory port."),
    ("Clock timing", "Synchronous circuits sample inputs on clock edges. Combinational logic must settle before the next register captures its result. Setup and hold requirements depend on the implemented device and clock constraints."),
    ("Reset recovery", "Reset returns controllers and validity flags to a known state. Large memory arrays usually retain old contents. After an aborted search the system must reload configuration and queries before consuming stored data."),
    ("Integer quantization", "Integer quantization represents numerical vectors with compact discrete values. Signed INT8 elements range from negative 128 to positive 127. Quantization introduces numerical error, and cosine results refer to the quantized vectors actually supplied."),
    ("Fixed point", "Fixed point numbers represent fractions using an implied scale. In signed Q2.30 a real value is the stored integer divided by two to the power thirty. Arithmetic widths and rounding rules must be defined explicitly."),
    ("Square roots", "An integer square root can be built from iterative shifts, comparisons and subtractions. A fully unrolled pipeline dedicates hardware to every iteration. Fractional scaling preserves precision before cosine normalization."),
    ("Division hardware", "Binary long division processes numerator bits using comparisons and conditional subtraction. An iterative divider shares arithmetic across cycles. A spatial pipeline uses more hardware to accept independent calculations more frequently."),
    ("Adder trees", "A balanced adder tree reduces many partial sums to one total. Independent pairs add simultaneously. Registers between tree levels shorten combinational paths, while validity timing identifies when the final sum is complete."),
    ("Vector databases", "A vector database associates numerical representations with document identifiers and stored content. Retrieval compares a query representation with candidate vectors. The returned identifiers let the host fetch the original text records."),
    ("Text embeddings", "Text embeddings turn documents and questions into numerical vectors. Lexical TF-IDF features describe word usage, while learned embeddings may capture broader semantic relationships. Retrieval quality depends on the representation and corpus."),
    ("Python coroutines", "Python asynchronous coroutines suspend at await expressions while other tasks continue. Cocotb coroutines can wait for clock edges and simulator phases. They drive signals and compare hardware output against a software reference."),
    ("Simulation testing", "Simulation testing exercises hardware descriptions without an FPGA board. Directed cases cover boundaries and randomized cases explore combinations. A scoreboard compares actual transactions with expected results, including ordering and backpressure."),
    ("Database identifiers", "Document identifiers link accelerator results to original content. Request identifiers distinguish independent query responses. Keeping identifiers aligned with scores through every pipeline stage prevents returning the right score for the wrong document."),
    ("Stream handshakes", "A stream transfer occurs at a rising clock edge when valid and ready are both asserted. The sender holds its payload stable until acceptance. A receiver can pause the stream by deasserting ready without losing transactions."),
    ("FIFO storage", "FIFO storage returns entries in the same order they were inserted. Read and write pointers wrap at the configured depth. Simultaneous enqueue and dequeue should preserve the occupancy count and never expose a partially written packet."),
    ("Bandwidth limits", "Memory bandwidth limits the rate at which arithmetic receives operands. More multipliers cannot improve throughput if input data arrives too slowly. Prefetching hides some access latency, but it does not create additional physical bandwidth."),
    ("GPU parallelism", "A GPU schedules many threads across parallel execution units. Vector reductions combine thread partial results. Dedicated accelerators can specialize dataflow, but speed comparisons require measured clocks, workloads and memory systems."),
    ("Result backpressure", "A result consumer may temporarily stop accepting responses. The accelerator must hold the current score, rank and identifiers stable. Buffered pipeline stages must stop or retain pending output until the consumer becomes ready."),
]
STOP = set('a an the and or of to in on at by for is are be as its their with from while when before after can must has have both each one two three into than that this it not same more some'.split())


def tokens(text):
    return [word for word in re.findall(r'[a-z][a-z0-9_]*', text.lower()) if word not in STOP]


def build():
    docs = [{"id": i, "title": title, "content": text, "source": "locally authored tutorial corpus"}
            for i, (title, text) in enumerate(DOCUMENTS)]
    # Anchor each topic in the vocabulary, then fill remaining dimensions by frequency.
    vocab = []
    for doc in docs:
        for term in tokens(doc['title']):
            if term not in vocab and len(vocab) < DIMENSIONS:
                vocab.append(term)
    frequency = collections.Counter(term for doc in docs for term in tokens(doc['title']+' '+doc['content']))
    for term, _ in sorted(frequency.items(), key=lambda item: (-item[1], item[0])):
        if term not in vocab and len(vocab) < DIMENSIONS:
            vocab.append(term)
    assert len(vocab) == DIMENSIONS
    df = {term: sum(term in set(tokens(doc['title']+' '+doc['content'])) for doc in docs) for term in vocab}
    idf = [math.log((1+len(docs))/(1+df[term]))+1 for term in vocab]

    def embed(text):
        counts = collections.Counter(tokens(text))
        values = [counts[term]*weight for term, weight in zip(vocab, idf)]
        maximum = max(values)
        return [round(127*value/maximum) for value in values] if maximum else [0]*DIMENSIONS

    vectors = [embed(doc['title']+' '+doc['content']) for doc in docs]
    queries = []
    rng = random.Random(20261016)
    for request_id in range(1000):
        target = request_id % len(docs)
        doc = docs[target]
        words = doc['content'].split()
        start = rng.randrange(max(1, len(words)-10))
        text = f"Explain {doc['title'].lower()}: " + ' '.join(words[start:start+rng.randrange(6, 15)])
        vector = embed(text)
        assert any(vector)
        queries.append({"request_id": request_id, "text": text, "source_document_id": target, "vector": vector})
    out = ROOT/'data'
    out.mkdir(exist_ok=True)
    (out/'documents.jsonl').write_text(''.join(json.dumps(doc)+'\n' for doc in docs))
    (out/'vector_database.json').write_text(json.dumps({"dimensions": DIMENSIONS, "embedding": "INT8 quantized TF-IDF", "vocabulary": vocab, "idf": idf, "vectors": vectors}, indent=2)+'\n')
    (out/'queries_1000.jsonl').write_text(''.join(json.dumps(query)+'\n' for query in queries))
    print(f'Prepared {len(docs)} text documents, {DIMENSIONS}-dimensional INT8 vectors, and {len(queries)} requests.')


if __name__ == '__main__':
    build()
