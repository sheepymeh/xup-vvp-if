#!/usr/bin/env python3
"""Export exact VIO net names from probe map"""

import json
from pathlib import Path

root = Path(__file__).resolve().parent
ltx = json.loads((root / 'build/all_channels.ltx').read_text())

# hardware.tcl needs post-synthesis net names, not just RTL signal names
lines = ['set probe_names [dict create]']
count = 0

for dataset in ltx['ltx_root']['ltx_data']:
    for core in dataset['debug_cores']:
        if core['type'] != 'VIO_V2':
            continue

        # Core names follow q<quad>_control/vio in top.v
        quad = core['name'].split('_')[0][1:]
        assert quad.isdigit()
        count += 1

        for pin in core['pins']:
            net = pin['nets'][0]['name']
            # Net names are emitted as Tcl brace-quoted literals
            assert '{' not in net and '}' not in net
            lines.append(f'dict set probe_names {quad} {pin["name"]} {{{net}}}')

# Require all eight cores before writing the runtime lookup table
assert count == 8, f'Expected eight VIOs, got {count}'
(root / 'build/probes.tcl').write_text('\n'.join(lines) + '\n')
