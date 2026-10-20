#!/usr/bin/env python3
"""Export the GTY image's VIO net names"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from common.probes import read_vios, write_vios

if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    write_vios(root / "build/probes.tcl", read_vios(root / "build/all_channels.ltx"))
