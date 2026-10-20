#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
. ./config.sh

mkdir -p build/logs build/ip

echo "Generating Vivado example project"
vivado -mode batch -source vivado/01-generate_example.tcl \
    -log build/logs/example.log -journal build/logs/example.jou

patch --batch -p1 -d build/example/xdma_0_ex/imports < vivado/xup-vvp.patch

echo "Building Vivado project"
vivado -mode batch -source vivado/02-build.tcl \
    -log build/logs/build.log -journal build/logs/build.jou

echo "PASS: built build/xdma.bit"
