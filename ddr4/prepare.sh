#!/bin/sh
set -eu

cd "$(dirname -- "$0")"
mkdir -p build

upstream=https://raw.githubusercontent.com/d953i/Custom_Part_Data_Files/b8b941d66658f0c44013fb03469ec142d24db5c9/Boards/Bittware_CVP13
output=build/constraints
mkdir -p "$output"

for dimm in 0 1; do
    name="CVP13_DIMM$dimm.xdc"
    if [ ! -f "$output/$name" ]; then
        wget -qO "$output/$name" "$upstream/$name"
    fi

    sed -E \
        -e '/dimm0_refclk_clk_n/s/}/ PACKAGE_PIN AY17}/' \
        -e '/dimm1_refclk_clk_n/s/}/ PACKAGE_PIN BB32}/' \
        -e 's/\[get_ports ([^[:space:]]+)\]$/[get_ports {\1}]/' \
        "$output/$name" > "$output/dimm${dimm}.xdc"
done
