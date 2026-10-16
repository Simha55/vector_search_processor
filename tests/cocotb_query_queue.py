import os
import cocotb
from queued_cocotb_utils import Bench, reset


@cocotb.test(timeout_time=100, timeout_unit='us')
async def complete_packets_full_wrap_and_simultaneous_pop(dut):
    depth=int(os.environ['TEST_DEPTH']); chunks=int(os.environ['TEST_CHUNKS'])
    b=Bench(dut,['reset','input_valid','input_data','input_id','head_chunk','pop'],
            ['input_ready','head_valid','head_id','head_data','partial','level'])
    await reset(b)
    sequence=0
    for batch in range(3):
        # Fill all slots with complete packets; partial packets remain hidden.
        for slot in range(depth):
            for chunk in range(chunks):
                before,after=await b.cycle(input_valid=1,input_data=100*sequence+chunk,input_id=sequence,pop=0)
                assert before['input_ready']==1
                assert after['level']==slot+int(chunk==chunks-1)
                if slot==0 and chunk<chunks-1: assert after['head_valid']==0
            sequence+=1
        before,after=await b.cycle(input_valid=1,input_data=9999,input_id=999,pop=0)
        assert before['input_ready']==0 and after['level']==depth
        # Read every stored chunk and remove complete packets.
        first=sequence-depth
        for slot in range(depth):
            for chunk in range(chunks):
                _,after=await b.cycle(input_valid=0,head_chunk=chunk,pop=0)
                assert after['head_id']==first+slot
                assert after['head_data']==100*(first+slot)+chunk
            await b.cycle(pop=1,input_valid=0)
        _,after=await b.cycle(pop=0,input_valid=0)
        assert after['level']==0 and after['head_valid']==0
    # Enqueue a packet, then pop it on the edge completing the next packet.
    if depth>1:
        for c in range(chunks): await b.cycle(input_valid=1,input_id=77,input_data=c,pop=0)
        for c in range(chunks):
            _,after=await b.cycle(input_valid=1,input_id=78,input_data=100+c,pop=int(c==chunks-1))
        assert after['level']==1 and after['head_id']==78
    await reset(b)
    assert int(dut.level.value)==0
