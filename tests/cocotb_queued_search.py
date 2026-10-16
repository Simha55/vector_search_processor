"""Resident DB -> double buffers -> parallel accumulation -> pipeline -> top-K.

The corpus test fills 1000 COMPLETE queries before enabling the hardware and
checks every returned ID, Q2.30 score, rank, request ID, and end-of-result flag.
"""
import json
import os
from pathlib import Path
import random

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly, with_timeout

from queued_cocotb_utils import Bench, reset, chunks, reference, bits32


def expected_hits(query, database, k):
    scores=[]
    for ident,vector in enumerate(database):
        score,error=reference(query,vector)
        if not error: scores.append((score,ident))
    return sorted(scores,key=lambda item:(-item[0],item[1]))[:k]


@cocotb.test(timeout_time=50, timeout_unit='ms')
async def queued_requests_prefetch_and_topk(dut):
    root=Path(os.environ['VECTOR_SEARCH_ROOT'])
    corpus=os.environ['TEST_WORKLOAD']=='corpus'
    dimensions=int(os.environ['TEST_DIMENSIONS']); lanes=int(os.environ['TEST_LANES'])
    depth=int(os.environ['TEST_DEPTH']); k=int(os.environ['TEST_K'])
    if corpus:
        model=json.loads((root/'data/vector_database.json').read_text())
        database=model['vectors']
        requests=[json.loads(line) for line in (root/'data/queries_1000.jsonl').read_text().splitlines()]
        documents=[json.loads(line) for line in (root/'data/documents.jsonl').read_text().splitlines()]
    else:
        database=[[1,0,0,0,0,0,0],[-1,0,0,0,0,0,0],[0]*7,[1]*7,[0,1,0,0,0,0,0]]
        vectors=[[1,0,0,0,0,0,0],[-1,0,0,0,0,0,0],[0]*7,[1]*7,[0,1,0,0,0,0,0],[-1]*7,[127]*7,[-128]*7]
        requests=[{'request_id':i+100,'vector':vector,'text':str(vector)} for i,vector in enumerate(vectors)]
        documents=[{'id':i,'title':f'directed vector {i}','content':str(vector)} for i,vector in enumerate(database)]
    assert len(database)==int(os.environ['TEST_VECTORS'])
    b=Bench(dut,
            ['reset','database_write_valid','database_write_address','database_write_data','database_commit',
             'query_valid','query_data','query_id','run_enable','result_ready'],
            ['database_write_ready','database_loaded','query_ready','queued_queries','result_valid',
             'result_query_id','result_rank','result_count','result_vector_id','result_score','result_last','result_error'])
    await reset(b)
    assert int(dut.query_ready.value)==0

    async def load_database():
        address=0
        for vector in database:
            for word in chunks(vector,lanes):
                before,_=await b.cycle(database_write_valid=1,database_write_address=address,database_write_data=word)
                assert before['database_write_ready']==1
                address+=1
        await b.cycle(database_write_valid=0,database_commit=1)
        _,after=await b.cycle(database_commit=0)
        assert after['database_loaded']==1

    await load_database()
    rng=random.Random(804)
    records=[]; full_proven=False; partial_frozen=False
    for base in range(0,len(requests),depth):
        batch=requests[base:base+depth]
        await b.cycle(run_enable=0,result_ready=0)
        # Fill the complete-query FIFO first; no search may consume it yet.
        for index,request in enumerate(batch):
            for chunk,word in enumerate(chunks(request['vector'],lanes)):
                before,after=await b.cycle(query_valid=1,query_data=word,query_id=request['request_id'])
                assert before['query_ready']==1
                assert after['queued_queries']==index+int(chunk==(dimensions+lanes-1)//lanes-1)
                if index==0 and chunk==0 and (dimensions+lanes-1)//lanes>1:
                    before,_=await b.cycle(query_valid=0,database_write_valid=1,database_write_address=0,database_write_data=0)
                    assert before['database_write_ready']==0
                    await b.cycle(database_write_valid=0)
                    partial_frozen=True
        if len(batch)==depth:
            for _ in range(3):
                before,after=await b.cycle(query_valid=1,query_data=0,query_id=0xFFFFFFFF)
                assert before['query_ready']==0 and after['queued_queries']==depth
            full_proven=True
        # A frozen database write must not damage the stored vector.
        before,_=await b.cycle(query_valid=0,database_write_valid=1,database_write_address=0,database_write_data=0)
        assert before['database_write_ready']==0
        await b.cycle(database_write_valid=0,run_enable=1)
        for request in batch:
            hits=expected_hits(request['vector'],database,k)
            wanted=hits or [(0,0)]
            if not int(dut.result_valid.value):
                await with_timeout(RisingEdge(dut.result_valid),1000000,'ns')
                await ReadOnly()
            actual_hits=[]
            for rank,(score,ident) in enumerate(wanted):
                expected={'result_query_id':request['request_id'],'result_rank':rank,
                          'result_count':len(hits),'result_vector_id':ident,'result_score':bits32(score),
                          'result_last':int(rank==len(wanted)-1),'result_error':0 if hits else 2}
                for _ in range(rng.randrange(3)):
                    _,after=await b.cycle(result_ready=0)
                    assert after['result_valid']==1
                    assert {name:after[name] for name in expected}==expected
                before,_=await b.cycle(result_ready=1)
                assert before['result_valid']==1
                assert {name:before[name] for name in expected}==expected, (request['request_id'],before,expected)
                if hits:
                    actual_hits.append({'rank':rank,'id':ident,'score_q30':score,'cosine':score/(1<<30),
                                        'title':documents[ident]['title'],'content':documents[ident]['content']})
            await b.cycle(result_ready=0)
            records.append({'request_id':request['request_id'],'query':request['text'],
                            'source_document_id':request.get('source_document_id'),
                            'error':0 if hits else 2,'matches':actual_hits})
            if len(records)%100==0: dut._log.info('Verified %d query responses',len(records))
        _,after=await b.cycle(run_enable=0)
        assert after['queued_queries']==0
    assert len(records)==len(requests) and full_proven and partial_frozen
    assert int(dut.normalizer_inflight.value)==0
    stats={name:int(getattr(dut,name).value) for name in
           ('bank_switches','fetch_compute_overlap','normalize_compute_overlap','active_cycles')}
    assert stats['bank_switches']==len(requests)*len(database)
    assert stats['fetch_compute_overlap']>0, 'no observed fill/consume overlap'
    assert stats['normalize_compute_overlap']>0, 'no observed normalize/accumulate overlap'
    summary={'requests':len(records),'documents':len(database),'dimensions':dimensions,'lanes':lanes,'top_k':k,
             'query_depth':depth,'all_ranked_ids_and_scores_match_reference':True,
             'full_query_queue_verified':full_proven,'database_frozen_during_partial_query':partial_frozen,
             'statistics':stats,'clock_period_ns':10,'simulated_active_time_ns':stats['active_cycles']*10,
             'embedding':'locally authored corpus; quantized lexical TF-IDF',
             'hardware_clock_timing_verified':False}
    if corpus:
        summary['source_document_recall_at_k']=sum(record['source_document_id'] in [hit['id'] for hit in record['matches']] for record in records)/len(records)
        out=root/'build/queued_demo'; out.mkdir(parents=True,exist_ok=True)
        (out/'results.jsonl').write_text(''.join(json.dumps(record)+'\n' for record in records))
        (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    dut._log.info('Queued service summary: %s',summary)
    # Reset invalidates the queue/database commit and flushes every pipeline.
    # Reloading permits a fresh request without leaking any old tags/results.
    await reset(b)
    assert int(dut.queued_queries.value)==0 and int(dut.database_loaded.value)==0
    await load_database()
    request=requests[0]
    for word in chunks(request['vector'],lanes):
        await b.cycle(query_valid=1,query_data=word,query_id=0x12345678)
    await b.cycle(query_valid=0,run_enable=1)
    await with_timeout(RisingEdge(dut.result_valid),1000000,'ns')
    await ReadOnly()
    assert int(dut.result_query_id.value)==0x12345678
    for rank,(score,ident) in enumerate(expected_hits(request['vector'],database,k) or [(0,0)]):
        before,_=await b.cycle(result_ready=1)
        assert before['result_rank']==rank and before['result_score']==bits32(score) and before['result_vector_id']==ident
