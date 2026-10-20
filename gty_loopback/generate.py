#!/usr/bin/env python3
"""Generate GTY wiring, constraints and Tcl mapping from the local board map"""

import json
from pathlib import Path
from string import Template

VIO_INPUTS = [4, 4, 4, 4, 64, 4, 4, 4]
VIO_OUTPUTS = [1, 1, 1, 3, 1, 1, 1, 4, 10, 1, 4]


def generate(board, template, output):
    quads = json.loads(Path(board).read_text())["quads"]
    template = Template(Path(template).read_text())
    ports, blocks, constraints = [], [], []
    mapping = [
        "set quads {}",
        "set ports [dict create]",
        f"set vio_inputs {{{' '.join(map(str, VIO_INPUTS))}}}",
        f"set vio_outputs {{{' '.join(map(str, VIO_OUTPUTS))}}}",
    ]
    for quad in quads:
        number = quad["number"]
        prefix = f"q{number}"
        ports.extend(
            [
                f"    input wire {prefix}_ref_p",
                f"    input wire {prefix}_ref_n",
                f"    input wire [3:0] {prefix}_rx_p",
                f"    input wire [3:0] {prefix}_rx_n",
                f"    output wire [3:0] {prefix}_tx_p",
                f"    output wire [3:0] {prefix}_tx_n",
            ]
        )
        blocks.append(
            template.substitute(
                number=number,
                port=quad["port"],
                first_channel=quad["channels"][0],
                last_channel=quad["channels"][-1],
            )
        )
        for key, pins in quad["pins"].items():
            if key.startswith("ref"):
                constraints.append(
                    f"set_property PACKAGE_PIN {pins} [get_ports {prefix}_{key}]"
                )
            else:
                for lane, pin in enumerate(pins):
                    constraints.append(
                        f"set_property PACKAGE_PIN {pin} [get_ports {{{prefix}_{key}[{lane}]}}]"
                    )
        constraints.extend(
            [
                f"create_clock -name {prefix}_ref -period 3.103030303 [get_ports {prefix}_ref_p]",
                f"set_property LOC {quad['common']} [get_cells {prefix}_refbuf]",
                f"set_property BEL {quad['bel']} [get_cells {prefix}_refbuf]",
                "",
            ]
        )
        mapping.append(
            f"lappend quads {{{number} {{{' '.join(quad['channels'])}}} {quad['refclk']}}}"
        )
        mapping.append(f"dict lappend ports {quad['port'].upper()} {number}")
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "top.v").write_text(
        "module all_channels_top (\n"
        + ",\n".join(ports)
        + "\n);\n\n"
        + "".join(blocks)
        + "endmodule\n"
    )
    (output / "constraints.xdc").write_text("\n".join(constraints))
    (output / "mapping.tcl").write_text("\n".join(mapping) + "\n")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    generate(root / "board.json", root / "quad.v.in", root / "build")
