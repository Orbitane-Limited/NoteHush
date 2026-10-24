#!/usr/bin/env python3
"""Run one bounded, generated Arabic/emoji paragraph opening diagnostic."""
import argparse

from test_large_open import main


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bytes", type=int, default=10 * 1024 * 1024,
        help="exact UTF-8 fixture size (16 bytes–10 MiB; divisible by 8)")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(main(paragraph_bytes=parse_arguments().bytes))
