#!/usr/bin/env python3
"""Capture selected live Si5341 registers through BwMonitor.

Writes Si5341 PAGE register 0x01 to select pages
Does not change frequency dividers, PLL configuration, or reset bits

Examples:
  python3 si5341_snapshot.py --clock B -o vvp_si5341_b.json
  python3 si5341_snapshot.py --clock A --profile expanded -o vvp_si5341_a.json
"""

import argparse
import datetime
import json
import re
import signal
import subprocess
import time
from pathlib import Path

# Endpoints inclusive. Core covers device ID, most clock-related registers,
# output drivers, M/N/R/P settings and selected related registers.
CORE_RANGES = {
    0x00: [(0x02, 0x08), (0x16, 0x18), (0x21, 0x43)],
    0x01: [(0x02, 0x3F)],
    0x02: [(0x02, 0x7F)],
    0x03: [(0x02, 0x3F)],
    0x05: [(0x02, 0x20)],
    0x09: [(0x02, 0x17)],
    0x0A: [(0x02, 0x10)],
    0x0B: [(0x24, 0x25), (0x40, 0x58)],
}
# Expanded collects broader blocks of configuration data; not every address
# is writable, meaningful, or part of a ClockBuilder export.
EXPANDED_RANGES = {
    0x00: [(0x02, 0x6F)],
    0x01: [(0x02, 0x4F)],
    0x02: [(0x02, 0x7F)],
    0x03: [(0x02, 0x4F)],
    0x04: [(0x02, 0x30)],
    0x05: [(0x02, 0x3F)],
    0x09: [(0x02, 0x6F)],
    0x0A: [(0x02, 0x20)],
    0x0B: [(0x02, 0x5F)],
}


def run_bwmonitor(device, devaddr, operation, register, count_or_value, timeout):
    cmd = [
        "bwmonitor",
        f"--device={device}",
        operation,
        f"--devaddr=0x{devaddr:03X}",
        f"--addr=0x{register:02X}",
    ]
    if operation == "--i2cread":
        cmd.append(f"--count={count_or_value}")
    else:
        cmd.append(f"--hexval=0x{count_or_value:02X}")
    try:
        # BwMonitor's hexdump may contain raw non-UTF-8 bytes in the ASCII preview
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="latin-1",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(
            f"BwMonitor timed out for {operation} offset 0x{register:02X}"
        ) from e
    output = (r.stdout or "") + "\n" + (r.stderr or "")
    if r.returncode != 0 or re.search(
        r"I2C\s+(?:Read|Write)\s+failed", output, re.IGNORECASE
    ):
        raise RuntimeError(f"BwMonitor failed: {' '.join(cmd)}\n{output.strip()}")
    if operation == "--i2cwrite":
        if not re.search(r"\bWrote\s+1\s+bytes?\b", output, re.IGNORECASE):
            raise RuntimeError(f"Could not confirm page write: {output.strip()}")
        return None
    match = re.search(
        r"Read\s+(\d+)\s+bytes?\s+from\s+i2c\s+device\s+[0-9a-f]+\s+offset\s+[0-9a-f]+\s*:\s*\n",
        output,
        re.IGNORECASE,
    )
    if not match or int(match.group(1)) != count_or_value:
        raise RuntimeError(f"Unexpected read response: {output.strip()}")
    hexdump = output[match.end() :]
    values = []
    for line in hexdump.splitlines():
        # BwMonitor separates ASCII preview from hex bytes by several spaces.
        prefix = re.split(r"\s{3,}", line.strip(), maxsplit=1)[0]
        for token in prefix.split():
            if not re.fullmatch(r"[0-9a-fA-F]{2}", token):
                break
            values.append(int(token, 16))
            if len(values) == count_or_value:
                return values
    raise RuntimeError(f"Could not parse {count_or_value} bytes from: {output.strip()}")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--clock",
        choices=["A", "B"],
        default="B",
        help="Si5341-A (0xE8) or Si5341-B (0xEA)",
    )
    ap.add_argument(
        "--device", type=int, default=0, help="BittWare PCIe board number, default 0"
    )
    ap.add_argument("--profile", choices=["core", "expanded"], default="core")
    ap.add_argument(
        "--output", "-o", required=True, help="New JSON filename for readback"
    )
    ap.add_argument(
        "--timeout", type=int, default=10, help="Timeout per BwMonitor call (seconds)"
    )
    ap.add_argument(
        "--pause", type=float, default=0.05, help="Pause between read blocks (seconds)"
    )
    args = ap.parse_args()
    # Turn ordinary termination into an exception so finally can restore PAGE
    signal.signal(
        signal.SIGTERM, lambda signum, frame: (_ for _ in ()).throw(KeyboardInterrupt())
    )
    if args.timeout < 1 or args.pause < 0:
        ap.error("--timeout must be >= 1 and --pause must be >= 0")
    path = Path(args.output)
    if path.exists():
        ap.error(f"Refusing to overwrite existing file: {path}")
    addr = 0x0E8 if args.clock == "A" else 0x0EA
    ranges = CORE_RANGES if args.profile == "core" else EXPANDED_RANGES

    def rd(reg, count):
        return run_bwmonitor(args.device, addr, "--i2cread", reg, count, args.timeout)

    def wr_page(page):
        run_bwmonitor(args.device, addr, "--i2cwrite", 0x01, page, args.timeout)
        actual = rd(0x01, 1)[0]
        if actual != page:
            raise RuntimeError(
                f"Page selector did not change to 0x{page:02X}: got 0x{actual:02X}"
            )

    original_page = rd(0x01, 1)[0]
    current_page = original_page
    print(f"Si5341-{args.clock} at 0x{addr:03X}; original page 0x{original_page:02X}")
    snapshot = {
        "type": "si5341_register_snapshot_not_programming_header",
        "timestamp_utc": datetime.datetime.now(datetime.UTC).isoformat(),
        "clock": args.clock,
        "board_device": args.device,
        "bwmonitor_devaddr": f"0x{addr:03X}",
        "original_page": f"0x{original_page:02X}",
        "profile": args.profile,
        "registers": {},
    }
    try:
        wr_page(0x00)
        current_page = 0x00
        ident = rd(0x02, 4)
        if ident[:2] != [0x41, 0x53] or ident[3] != 0x03 or ident[2] > 3:
            raise RuntimeError(
                f"Unexpected Si5341 ID {ident!r}; expected Si5341 revision D. Aborting."
            )
        print(
            f"Verified Si5341 grade {chr(ord('A') + ident[2])}, revision D: "
            + " ".join(f"{b:02X}" for b in ident)
        )
        for page, blocks in ranges.items():
            if current_page != page:
                wr_page(page)
                current_page = page
            for start, end in blocks:
                for low in range(start, end + 1, 16):
                    count = min(16, end - low + 1)
                    print(
                        f"  page {page:02X} offset {low:02X}: {count} bytes", flush=True
                    )
                    values = rd(low, count)
                    for i, value in enumerate(values):
                        full_addr = (page << 8) | (low + i)
                        snapshot["registers"][f"0x{full_addr:04X}"] = f"0x{value:02X}"
                    time.sleep(args.pause)
        print(f"Captured {len(snapshot['registers'])} registers.")
    finally:
        # Restore the original page even after read errors.
        print(f"Restoring original page 0x{original_page:02X}...", flush=True)
        wr_page(original_page)
        print("Page restored and verified.")

    path.write_text(json.dumps(snapshot, indent=2, sort_keys=False) + "\n")
    print(f"Saved snapshot: {path} (not a programmable .h file)")


if __name__ == "__main__":
    main()
