import os
import random
import cocotb
from queued_cocotb_utils import Bench, reset, bits32


@cocotb.test(timeout_time=100, timeout_unit='us')
async def signed_sorted_ties_and_clear(dut):
    k=int(os.environ['TEST_K'])
    b=Bench(dut,['reset','clear','candidate_valid','candidate_score','candidate_id','read_rank'],['count','read_score','read_id'])
    await reset(b)
    cases=[(-30,7),(-40,1),(-10,9),(-10,3),(0,20),(100,8),(100,2),(-(1<<30),0)]
    rng=random.Random(803)
    cases += [(rng.randrange(-(1<<30),(1<<30)+1),i+100) for i in range(30)]
    reference=[]
    for score,ident in cases:
        await b.cycle(candidate_valid=1,candidate_score=score,candidate_id=ident,read_rank=0)
        reference=sorted(reference+[(score,ident)],key=lambda x:(-x[0],x[1]))[:k]
        for rank,(wanted_score,wanted_id) in enumerate(reference):
            _,after=await b.cycle(candidate_valid=0,read_rank=rank)
            assert (after['count'],after['read_score'],after['read_id'])==(len(reference),bits32(wanted_score),wanted_id)
    _,after=await b.cycle(clear=1,candidate_valid=1,candidate_score=999,candidate_id=0)
    assert after['count']==0
    await b.cycle(clear=0,candidate_valid=1,candidate_score=-9,candidate_id=1)
    _,after=await b.cycle(candidate_valid=0,read_rank=0)
    assert (after['count'],after['read_score'],after['read_id'])==(1,bits32(-9),1)
