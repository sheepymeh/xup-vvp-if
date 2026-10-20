# Implementation only, STARTUPE3 pins are inside the reset module at synthesis
# Assumed oscillator period, CFGMCLK is not a precision clock
create_clock -period 20.000 -name startup_cfgmclk [get_pins -hier -filter {REF_PIN_NAME == CFGMCLK}]

# Only first-stage EOS/DCI synchronizer inputs are asynchronous
set_false_path -to [get_pins -hier -regexp {.*(eos_meta_reg|locked_sync_reg\[0\])/D}]
