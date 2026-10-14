#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
. ./config.sh
SYSFS=/sys/bus/pci/devices
DMA_BYTES=524288
BENCH_COUNT=256

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Check PCIe identity and capabilities
dev=$SYSFS/$BDF
if [[
    "$(< "$dev/vendor")" != "0x${PCI_VENDOR_ID,,}" ||
    "$(< "$dev/device")" != "0x${PCI_DEVICE_ID,,}"
]]; then
    fail "Refusing unexpected PCIe function at $BDF"
fi

maximum_speed="$(< "$dev/max_link_speed")"
maximum_width="$(< "$dev/max_link_width")"
printf 'Endpoint capability: %s x%s\n' "$maximum_speed" "$maximum_width"
if [[
    "$maximum_speed" != "$ENDPOINT_LINK_SPEED GT/s"* ||
    "$maximum_width" != "$ENDPOINT_LINK_WIDTH"
]]; then
    fail "Endpoint does not advertise $ENDPOINT_LINK_SPEED GT/s x$ENDPOINT_LINK_WIDTH capability"
fi

actual_speed="$(< "$dev/current_link_speed")"
actual_width="$(< "$dev/current_link_width")"
printf 'Negotiated link:     %s x%s\n' "$actual_speed" "$actual_width"
if [[
    "$actual_speed" != "$LINK_SPEED"* ||
    "$actual_width" != "$LINK_WIDTH"
]]; then
    fail "Negotiated link is not $LINK_SPEED x$LINK_WIDTH"
fi

driver="$(readlink -f "$dev/driver")"
command_bits="$(setpci -s "$BDF" COMMAND)"
printf 'PCIe COMMAND: 0x%s\n' "$command_bits"
if (( (16#$command_bits & 0x0006) != 0x0006 )); then
    # 0x0002	Memory Space Enable - allow responses to memory-space accesses
    # 0x0004	Bus Master Enable - allow the device to initiate transactions
    fail "Mem+ and BusMaster+ required. See remove/rescan in README.md"
fi
if [[ ${driver##*/} != xdma ]]; then
    fail "XDMA kernel driver is not bound"
fi
if [[ ! -e "/dev/xdma${XDMA_INDEX}_h2c_0" || ! -e "/dev/xdma${XDMA_INDEX}_c2h_0" ]]; then
    fail "XDMA PCI function is not enabled"
fi
echo "PASS: $LINK_SPEED x$LINK_WIDTH link with XDMA kernel driver bound to $BDF"

# Test DMA round-trip
h2c=/dev/xdma${XDMA_INDEX}_h2c_0
c2h=/dev/xdma${XDMA_INDEX}_c2h_0
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
head -c "$DMA_BYTES" /dev/urandom > "$temp/tx.bin"

dma_to_device -d "$h2c" -a 0 -s "$DMA_BYTES" -f "$temp/tx.bin"
dma_from_device -d "$c2h" -a 0 -s "$DMA_BYTES" -f "$temp/rx.bin"
if ! cmp -s "$temp/tx.bin" "$temp/rx.bin"; then
    fail "DMA round-trip failed, H2C/C2H data mismatch"
fi
echo "PASS: $DMA_BYTES-byte AXI-MM DMA round-trip at address 0"

printf "H2C (MB/s): "
dma_to_device -d "$h2c" -a 0 -s "$DMA_BYTES" -c "$BENCH_COUNT" -f "$temp/tx.bin"
printf "C2H (MB/s): "
dma_from_device -d "$c2h" -a 0 -s "$DMA_BYTES" -c "$BENCH_COUNT"
