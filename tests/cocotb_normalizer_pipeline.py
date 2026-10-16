import collections
import math
import random
import cocotb
from queued_cocotb_utils import Bench, reset, normalize, bits32


@cocotb.test(timeout_time=100, timeout_unit='us')
async def tagged_pipeline_stalls_and_reset(dut):
    b=Bench(dut,['reset','input_valid','dot_sum','query_norm','database_norm','input_id','output_ready'],
            ['input_ready','output_valid','score','zero_norm','output_id','inflight'])
    await reset(b)
    rng=random.Random(801)
    cases=[(1,1,1),(-1,1,1),(0,0,0),(1,1,0),(40,30,54),(-(1<<63),1,1)]
    for _ in range(120):
        q,d=rng.randrange(1,1<<32),rng.randrange(1,1<<32)
        bound=math.isqrt(q*d)
        cases.append((rng.randrange(-bound,bound+1),q,d))
    expected=collections.deque()
    sent=received=consecutive=longest=0
    for cycle in range(1000):
        valid=sent<len(cases) and cycle%7!=3
        dot,q,d=cases[sent] if sent<len(cases) else (0,1,1)
        ready=not(195<=cycle<215) and cycle%13!=5
        before,after=await b.cycle(input_valid=int(valid),dot_sum=dot,query_norm=q,database_norm=d,input_id=sent,output_ready=int(ready))
        if valid and before['input_ready']:
            score,zero=normalize(dot,q,d)
            expected.append((sent,bits32(score),zero)); sent+=1
        if before['output_valid'] and ready:
            assert expected
            assert (before['output_id'],before['score'],before['zero_norm'])==expected.popleft()
            received+=1; consecutive+=1; longest=max(longest,consecutive)
        else: consecutive=0
        if before['output_valid'] and not ready:
            assert all(after[k]==before[k] for k in ('output_valid','score','zero_norm','output_id'))
            assert before['input_ready']==0
        if received==len(cases): break
    assert received==len(cases) and not expected and longest>=5
    assert after['inflight']==0
    # Drop in-flight tags during reset; no pre-reset payload may reappear.
    for tag in range(8):
        await b.cycle(input_valid=1,dot_sum=1,query_norm=1,database_norm=1,input_id=900+tag,output_ready=1)
    await reset(b)
    await b.cycle(input_valid=1,dot_sum=-1,query_norm=1,database_norm=1,input_id=42,output_ready=1)
    for _ in range(200):
        before,_=await b.cycle(input_valid=0,output_ready=1)
        if before['output_valid']:
            assert before['output_id']==42 and before['score']==bits32(-(1<<30)); break
    else: assert False,'pipeline reset recovery timed out'
