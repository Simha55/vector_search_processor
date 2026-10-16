"""Clock, cycle and reset helpers for the current queued-service tests."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, ReadOnly, Timer

from cosine_reference import bits32, chunks, normalize, reference


class Bench:
    """Drive at falling edges; sample transfers BEFORE and results AFTER rising edges.

    Sampling only after an edge can miss a handshake when ready drops on that
    edge. The before snapshot records exactly what the DUT is about to accept.
    ReadOnly ensures combinational and nonblocking updates have settled.
    """
    def __init__(self, dut, inputs, outputs):
        self.dut = dut
        self.inputs = inputs
        self.outputs = outputs
        dut.clk.value = 0
        for name in inputs:
            getattr(dut, name).value = 0
        self.clock = cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start(start_high=False))

    def sample(self):
        return {name: int(getattr(self.dut, name).value) for name in self.outputs}

    async def cycle(self, **values):
        await FallingEdge(self.dut.clk)
        for name, value in values.items():
            handle = getattr(self.dut, name)
            handle.value = value & ((1 << len(handle)) - 1)
        await Timer(1, unit="ns")
        await ReadOnly()
        before = self.sample()
        await RisingEdge(self.dut.clk)
        await ReadOnly()
        return before, self.sample()


async def reset(b):
    await FallingEdge(b.dut.clk)
    for name in b.inputs:
        getattr(b.dut, name).value = int(name == 'reset')
    await RisingEdge(b.dut.clk)
    await ReadOnly()
    return await b.cycle(reset=0)
