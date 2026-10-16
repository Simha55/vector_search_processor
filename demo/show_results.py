#!/usr/bin/env python3
"""Read one verified query response and its source content from the demo artifact."""
import argparse
import json
from pathlib import Path


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--request-id',type=int,default=0)
    parser.add_argument('--results',type=Path,
                        default=Path(__file__).resolve().parents[1]/'build/queued_demo/results.jsonl')
    args=parser.parse_args()
    if not args.results.exists():
        parser.error('Run .venv/bin/python tests/run_queued_search_tests.py first.')
    with args.results.open() as source:
        for line in source:
            record=json.loads(line)
            if record['request_id']==args.request_id:
                print(f"Request {record['request_id']}: {record['query']}")
                if record['error']:
                    print(f"No defined cosine candidates (error {record['error']}).")
                for hit in record['matches']:
                    print(f"\nRank {hit['rank']} | ID {hit['id']} | cosine {hit['cosine']:.6f} | {hit['title']}")
                    print(hit['content'])
                return
    parser.error(f'Request ID {args.request_id} not found.')


if __name__=='__main__':
    main()
