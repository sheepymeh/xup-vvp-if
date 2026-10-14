#!/bin/sh

alias bwdocker='docker run --rm --privileged -v "${HOME}/.bwtk":/root/.bwtk -v /dev/bus/usb:/dev/bus/usb bwtk'
alias bwconfig='bwdocker bwconfig'
alias bwmonitor='bwdocker bwmonitor'

voltage () {
	if [ "$#" = 0 ]; then
		echo "Querying FPGA voltage status..."
		bwmonitor --fpgacorev_override=255 --fpgacorev_mv=65535
	elif [ "$#" = 1 ] && [ "$1" = "restore" ]; then
		echo "Restoring FPGA voltage to default..."
		bwmonitor --fpgacorev_override=0 --fpgacorev_mv=850
	elif [ "$#" = 2 ] && [ "$1" = "set" ]; then
		mv="$2"
		if [ "$mv" -lt 825 ] || [ "$mv" -gt 850 ]; then
			echo "Error: Voltage must be between 825 and 850 mV"
			return 1
		fi
		echo "Setting FPGA voltage to $mv mV..."
		bwmonitor --fpgacorev_override=1 --fpgacorev_mv="$mv"
	else
		echo "Usage:"
		echo "  $0 set <millivolts>"
		echo "  $0 restore"
		return 1
	fi
}
