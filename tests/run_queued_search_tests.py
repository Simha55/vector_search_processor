#!/usr/bin/env python3
"""Build the offline text/vector workload, then run direct cocotb verification."""
import os
from pathlib import Path
import runpy
import sys


def main():
    root=Path(__file__).resolve().parents[1]
    runpy.run_path(str(root/'demo/build_vector_db.py'),run_name='__main__')
    os.environ['PYTEST_DISABLE_PLUGIN_AUTOLOAD']='1'
    import pytest
    return pytest.main([str(root/'tests/test_queued_cosine.py'),'-q',*sys.argv[1:]])


if __name__=='__main__':
    raise SystemExit(main())
