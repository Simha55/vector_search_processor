"""Block and end-to-end tests for queued, double-buffered top-K cosine search."""
import os
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET
import pytest
from cocotb_tools.runner import get_runner

ROOT=Path(__file__).resolve().parents[1]
CASES=[
    ('cosine_normalizer_pipeline','cocotb_normalizer_pipeline',{},{}),
    *[('cosine_query_queue','cocotb_query_queue',{'WIDTH':64,'CHUNKS':3,'DEPTH':depth},
       {'TEST_DEPTH':depth,'TEST_CHUNKS':3}) for depth in (1,3)],
    ('cosine_db_ping_pong','cocotb_db_ping_pong',{'WIDTH':64,'CHUNKS':5,'VECTORS':7},
     {'TEST_CHUNKS':5,'TEST_VECTORS':7}),
    *[('cosine_topk','cocotb_topk',{'K':k},{'TEST_K':k}) for k in (1,5)],
    ('queued_cosine_search','cocotb_queued_search',
     {'DIMENSIONS':7,'LANES':3,'DATABASE_VECTORS':5,'QUERY_DEPTH':3,'TOP_K':7,'MEMORY_LATENCY':3},
     {'TEST_WORKLOAD':'small','TEST_DIMENSIONS':7,'TEST_LANES':3,'TEST_VECTORS':5,'TEST_DEPTH':3,'TEST_K':7}),
    ('queued_cosine_search','cocotb_queued_search',
     {'DIMENSIONS':64,'LANES':8,'DATABASE_VECTORS':24,'QUERY_DEPTH':1000,'TOP_K':5,'MEMORY_LATENCY':2},
     {'TEST_WORKLOAD':'corpus','TEST_DIMENSIONS':64,'TEST_LANES':8,'TEST_VECTORS':24,'TEST_DEPTH':1000,'TEST_K':5}),
]

@pytest.mark.parametrize('top,module,parameters,environment',CASES,
                         ids=[f'{top}_{index}' for index,(top,_,_,_) in enumerate(CASES)])
def test_queued(top,module,parameters,environment,tmp_path):
    runner=get_runner('icarus')
    runner.build(sources=sorted((ROOT/'rtl').glob('*.v')),hdl_toplevel=top,parameters=parameters,
                 build_dir=tmp_path,timescale=('1ns','1ps'),always=True)
    env={'PYTHONPATH':str(ROOT/'tests')+os.pathsep+os.environ.get('PYTHONPATH',''),
         'VECTOR_SEARCH_ROOT':str(ROOT),**{key:str(value) for key,value in environment.items()}}
    report=runner.test(hdl_toplevel=top,test_module=module,build_dir=tmp_path,test_dir=tmp_path,
                       results_xml=str(tmp_path/'results.xml'),extra_env=env)
    result=ET.parse(report)
    assert result.findall('.//testcase')
    assert not result.findall('.//failure') and not result.findall('.//error')


@pytest.mark.parametrize('unit', ['int8_multiplier', 'int8_accumulator', 'int8_mac'])
def test_arithmetic_unit(unit, tmp_path):
    """Keep the original useful arithmetic unit checks in the single test command."""
    executable = tmp_path / unit
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_' + unit, '-o', str(executable),
                    *map(str, sorted((ROOT / 'rtl').glob('*.v'))),
                    str(ROOT / 'tb' / ('tb_' + unit + '.v'))], check=True)
    result = subprocess.run(['vvp', str(executable)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'PASS:' in result.stdout, result.stdout
