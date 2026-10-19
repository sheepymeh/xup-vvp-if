# xup-vvp-if

Reverse-engineered interfaces for the BittWare XUP-VVP/CVP-13.

## Board Overview

The XUP-VVP has a `xcvu13p-figd2104-2-e` and is identical to the mining-focused CVP-13.

USB Devices
* BittWare `2528:0004`
* Digilent/FT232H `0403:6014`
* hub `04b4:6570`
* FT232R serial device `0403:6001`

## Flashing

A volatile flash can be done via the Digilent FT232H with a Vivado hardware server.
A flash chip is present on the board with user/backup sections, and can be programmed with BittWare Toolkit.

## Programmable Clocks

Two Si5341-A grade Rev D programmable clocks with part id `41 53`, revision `00 03` are available on the card.
Clock A is index `0` at BMC endpoint `0x0E8`, clock B is index `1` at endpoint `0x0EA`.

<details><summary><strong>Verified Clock Pins</strong></summary>

These clock pins have been explicitly verified on the XUP-VVP board
by halving the clock rate via I2C, then measuring on the FPGA.

| Clock Output | FPGA destination | Input | +pin | -pin |
| --- | --- | --- | --- | --- |
| **A OUT0** | GTY233 | REFCLK0 | `D11` | `D10` |
| **A OUT1** | GTY232 | REFCLK0 | `H11` | `H10` |
| **A OUT2** | GTY229 | REFCLK0 | `Y11` | `Y10` |
| **A OUT3** | GTY228 | REFCLK0 | `AD11` | `AD10` |
| **A OUT4** | GTY129 | REFCLK0 | `AA36` | `AA37` |
| **A OUT4** | GTY133 | REFCLK0 | `R36` | `R37` |
| **A OUT6** | GTY120 | REFCLK0 | `AL36` | `AL37` |
| **A OUT6** | GTY121 | REFCLK0 | `AJ36` | `AJ37` |
| **A OUT8** | GTY230 | REFCLK0 | `T11` | `T10` |

* A5/A7 are suspected SlimSAS Tx clocks per XUP-VV4 HRG, but changing clocks did not cause the expected response
* A9 is suspected IN0 cascade to clock B, but changing clocks did not cause the expected response

| Clock Output | FPGA destination | Input | +pin | -pin | Remarks |
| --- | --- | --- | --- | --- | --- |
| **B OUT1** | Bank 70 | Clock input | `G30` | `F30` | |
| **B OUT2** | Bank 73 | Clock input | `G20` | `F19` | |
| **B OUT3** | Bank 66 | Clock input | `AY18` | `AY17` | DIMM0 source clock |
| **B OUT4** | Bank 62 | Clock input | `BB31` | `BB32` | DIMM1 source clock |
| **B OUT5** | Bank 64 | Clock input | `AV22` | `AV21` | |
| **B OUT6** | GTY233 | REFCLK1 | `B11` | `B10` | |
| **B OUT7** | GTY232 | REFCLK1 | `F11` | `F10` | |
| **B OUT8** | GTY229 | REFCLK1 | `V11` | `V10` | |
| **B OUT9** | GTY228 | REFCLK1 | `AB11` | `AB10` | |

* B0 is suspected GTY225/227 PCIe-refclk, but changing clocks did not cause the expected response

</details>

* Use BMC queries for reads (`bwmonitor --device=0 --type=Clock --read`)
* Use register offset `0x01`
* Write with `bwmonitor --i2cwrite --devaddr=0x0EA --addr=0x01 --hexval=0x00`
* Use `--hexval=0xNN` instead of bare `--hexval=NN`

## Pinout

<details><summary><strong>Pinout</strong></summary>

| Function | FPGA destination | FPGA pin(s) | Evidence source |
| --- | --- | --- | --- |
| DIMM0 DDR CK_t/CK_c | | `AV18`/`AW18` | CVP-13 XDC |
| DIMM1 DDR CK_t/CK_c | | `AV33`/`AW33` | CVP-13 XDC |
| DIMM0 RESET_n | `BB14` | | CVP-13 XDC |
| DIMM1 RESET_n | `BC31` | | CVP-13 XDC |
| PCIe REFCLK0 candidate 1 | GTY225 | `AT11`/`AT10` | 100 MHz, works with XDMA |
| PCIe REFCLK0 candidate 2 | GTY227 | `AH11`/`AH10` | 100 MHz, works with XDMA |
| PCIe PERST# | FPGA control | `AP26` | Works with XDMA |
| BMC reset | | `AW21` | XUP-VV4 HRG |
| FPGA I2C bus ownership | | `AY21` | XUP-VV4 HRG |
| QSFP management SDA/SCL | | `AN19`/`AP19` | XUP-VV4 HRG |
| FPGA-to-BMC UART | | Unresolved | XUP-VV4 HRG |
| I2C bus arbitration | | Not established | XUP-VV4 HRG |

</details>

## Comparison with XUP-VV4

The XUP-VVP is very similar to the XUP-VV4 and can be used as a source, but is not pin-compatible.
Some differences are listed below:

* The lower DIMM slots are present: J9 is marked as DIMM-1 and J13 is marked as DIMM-2 on XUP-VVP,
  the upper slots are replaced with a VRM
* The XUP-VVP has no utility USB-C port (although pads seem present on the PCB)
* Clock pins (see above)

## To-do

* Physical DIMM/QSFP/SlimSAS tests
* LED/QSFP present/reset, SlimSAS sideband GPIO pins
* Full PCIe Gen3 x16 test

## References

* Manualslib - [XUP-VV4 HRG](https://www.manualslib.com/manual/3631308/Molex-Bittware-Xup-Vv4.html), [XUP-VV8 HRG](https://www.manualslib.com/manual/3631330/Molex-Bittware-Xup-Vv8.html)
* [d953i DDR4 Examples](https://github.com/d953i/Custom_Part_Data_Files/tree/master/Boards/Bittware_CVP13)
* [XUP-VVP datasheet](https://www.zerif.co.uk/uploads/Datasheets/bittware_ds-xupvvp.pdf)
* [BittWare Toolkit](https://community.altera.com/discussions/acceleration/bittware-toolkit-lite/243190/replies/243199) - do not use the firmware included in this ZIP

---

This project is not affiliated with BittWare, AMD, or Xilinx
