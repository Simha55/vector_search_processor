import collections
import os
import random
import cocotb
from queued_cocotb_utils import Bench, reset


@cocotb.test(timeout_time=100, timeout_unit='us')
async def alternating_banks_latency_and_backpressure(dut):
    chunks=int(os.environ['TEST_CHUNKS']); vectors=int(os.environ['TEST_VECTORS'])
    b=Bench(dut,['reset','start_valid','request_ready','response_valid','response_data','output_ready'],
            ['start_ready','request_valid','request_address','response_ready','output_valid','output_data','output_vector','output_chunk','output_last','filling_bank','consuming_bank'])
    await reset(b)
    rng=random.Random(802)
    for repetition in range(2):
        await b.cycle(start_valid=1)
        pending=collections.deque(); received=issued=overlap=0
        for cycle in range(1000):
            response=bool(pending and pending[0][0]<=cycle)
            data=pending[0][1]*17+3 if response else 0
            ready=rng.randrange(4)!=0
            memory_ready=rng.randrange(5)!=0
            before,_=await b.cycle(start_valid=0,request_ready=int(memory_ready),response_valid=int(response),response_data=data,output_ready=int(ready))
            if before['request_valid'] and memory_ready:
                address=before['request_address']; assert address==issued
                pending.append((cycle+3,address)); issued+=1
            if response and before['response_ready']: pending.popleft()
            if before['output_valid'] and ready:
                assert before['output_vector']==received//chunks
                assert before['output_chunk']==received%chunks
                assert before['output_data']==received*17+3
                assert before['output_last']==int(received%chunks==chunks-1)
                received+=1
                if response and before['response_ready']:
                    assert before['filling_bank']!=before['consuming_bank']; overlap+=1
            if received==chunks*vectors: break
        assert received==chunks*vectors and issued==chunks*vectors and not pending
        assert overlap>0
        _,after=await b.cycle(response_valid=0,output_ready=0)
        assert after['start_ready']==1
    # Flush ownership and any half-filled bank on reset.
    await b.cycle(start_valid=1)
    await b.cycle(start_valid=0,request_ready=1)
    await reset(b)
    assert int(dut.output_valid.value)==0 and int(dut.start_ready.value)==1
