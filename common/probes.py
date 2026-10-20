"""Read Vivado LTX VIO interfaces and export safely quoted Tcl dictionaries"""

import json
from pathlib import Path


def tcl_word(value):
    value = str(value)
    for old, new in (
        ("\\", "\\\\"),
        ('"', '\\"'),
        ("$", "\\$"),
        ("[", "\\["),
        ("]", "\\]"),
        ("\n", "\\n"),
        ("\r", "\\r"),
        ("\t", "\\t"),
    ):
        value = value.replace(old, new)
    return f'"{value}"'


def read_vios(path):
    data = json.loads(Path(path).read_text())
    cores = {}
    for dataset in data["ltx_root"]["ltx_data"]:
        for core in dataset.get("debug_cores", []):
            if core["type"] == "VIO_V2":
                cores[core["name"]] = {
                    pin["name"]: pin["nets"][0]["name"] for pin in core["pins"]
                }
    return cores


def write_vios(path, cores):
    lines = ["set vio_map [dict create]"]
    for core, pins in cores.items():
        for port, net in pins.items():
            lines.append(
                f"dict set vio_map {tcl_word(core)} {tcl_word(port)} {tcl_word(net)}"
            )
    Path(path).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    import sys

    write_vios(sys.argv[2], read_vios(sys.argv[1]))
