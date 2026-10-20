module all_channels_top (
    // QSFP0, GTY233
    input wire q233_ref_p,
    input wire q233_ref_n,
    input wire [3:0] q233_rx_p,
    input wire [3:0] q233_rx_n,
    output wire [3:0] q233_tx_p,
    output wire [3:0] q233_tx_n,

    // QSFP1, GTY232
    input wire q232_ref_p,
    input wire q232_ref_n,
    input wire [3:0] q232_rx_p,
    input wire [3:0] q232_rx_n,
    output wire [3:0] q232_tx_p,
    output wire [3:0] q232_tx_n,

    // QSFP2, GTY229
    input wire q229_ref_p,
    input wire q229_ref_n,
    input wire [3:0] q229_rx_p,
    input wire [3:0] q229_rx_n,
    output wire [3:0] q229_tx_p,
    output wire [3:0] q229_tx_n,

    // QSFP3, GTY228
    input wire q228_ref_p,
    input wire q228_ref_n,
    input wire [3:0] q228_rx_p,
    input wire [3:0] q228_rx_n,
    output wire [3:0] q228_tx_p,
    output wire [3:0] q228_tx_n,

    // SlimSAS1 lanes 0-3, GTY129
    input wire q129_ref_p,
    input wire q129_ref_n,
    input wire [3:0] q129_rx_p,
    input wire [3:0] q129_rx_n,
    output wire [3:0] q129_tx_p,
    output wire [3:0] q129_tx_n,

    // SlimSAS1 lanes 4-7, GTY133
    input wire q133_ref_p,
    input wire q133_ref_n,
    input wire [3:0] q133_rx_p,
    input wire [3:0] q133_rx_n,
    output wire [3:0] q133_tx_p,
    output wire [3:0] q133_tx_n,

    // SlimSAS2 lanes 0-3, GTY120
    input wire q120_ref_p,
    input wire q120_ref_n,
    input wire [3:0] q120_rx_p,
    input wire [3:0] q120_rx_n,
    output wire [3:0] q120_tx_p,
    output wire [3:0] q120_tx_n,

    // SlimSAS2 lanes 4-7, GTY121
    input wire q121_ref_p,
    input wire q121_ref_n,
    input wire [3:0] q121_rx_p,
    input wire [3:0] q121_rx_n,
    output wire [3:0] q121_tx_p,
    output wire [3:0] q121_tx_n
);

    // ---- GTY233: QSFP0, channels X1Y52-X1Y55 ----

    // Reference input and 161.1328125 MHz control clock
    wire q233_ref, q233_odiv, q233_clk, q233_txclk, q233_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q233_refbuf (
        .I(q233_ref_p), .IB(q233_ref_n), .CEB(1'b0),
        .O(q233_ref), .ODIV2(q233_odiv));
    BUFG_GT q233_freerun (.I(q233_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q233_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q233_power, q233_txpma, q233_rxpma;
    wire [3:0] q233_locked, q233_prbserr, q233_cntreset, q233_forceerr, q233_polarity;
    wire q233_reset, q233_rxreset, q233_pmareset;
    wire q233_txdone, q233_rxdone, q233_qplllock;
    wire [2:0] q233_loopback;
    wire [39:0] q233_drpaddr;
    wire [3:0] q233_drpen, q233_drprdy;
    wire [63:0] q233_drpdo;
    gty_quad_233 q233_gt (
        .gtyrxn_in(q233_rx_n), .gtyrxp_in(q233_rx_p),
        .gtytxn_out(q233_tx_n), .gtytxp_out(q233_tx_p),
        .gtrefclk00_in(q233_ref),
        .gtwiz_userclk_tx_reset_in(~(&q233_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q233_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q233_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q233_rxclk),
        .gtwiz_reset_clk_freerun_in(q233_clk),
        .gtwiz_reset_all_in(q233_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q233_rxreset),
        .gtwiz_reset_tx_done_out(q233_txdone),
        .gtwiz_reset_rx_done_out(q233_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q233_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q233_forceerr), .rxpolarity_in(q233_polarity),
        .rxprbscntreset_in(q233_cntreset),
        .rxpmareset_in({4{q233_pmareset}}),
        .rxprbslocked_out(q233_locked), .rxprbserr_out(q233_prbserr),
        .gtpowergood_out(q233_power), .txpmaresetdone_out(q233_txpma),
        .rxpmaresetdone_out(q233_rxpma),
        .qpll0lock_out(q233_qplllock),
        .drpaddr_in(q233_drpaddr), .drpclk_in({4{q233_clk}}),
        .drpdi_in(64'd0), .drpen_in(q233_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q233_drpdo), .drprdy_out(q233_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q233_control (
        .clk(q233_clk), .txclk(q233_txclk), .rxclk(q233_rxclk),
        .powergood(q233_power), .txpma(q233_txpma), .rxpma(q233_rxpma),
        .txdone(q233_txdone), .rxdone(q233_rxdone),
        .qplllock(q233_qplllock),
        .locked(q233_locked), .prbserr(q233_prbserr),
        .reset_all(q233_reset), .reset_rx(q233_rxreset), .reset_pma(q233_pmareset),
        .loopback(q233_loopback), .count_reset(q233_cntreset),
        .force_error(q233_forceerr), .rxpolarity(q233_polarity), .drpaddr(q233_drpaddr),
        .drpen(q233_drpen), .drpdo(q233_drpdo), .drprdy(q233_drprdy));

    // ---- GTY232: QSFP1, channels X1Y48-X1Y51 ----

    // Reference input and 161.1328125 MHz control clock
    wire q232_ref, q232_odiv, q232_clk, q232_txclk, q232_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q232_refbuf (
        .I(q232_ref_p), .IB(q232_ref_n), .CEB(1'b0),
        .O(q232_ref), .ODIV2(q232_odiv));
    BUFG_GT q232_freerun (.I(q232_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q232_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q232_power, q232_txpma, q232_rxpma;
    wire [3:0] q232_locked, q232_prbserr, q232_cntreset, q232_forceerr, q232_polarity;
    wire q232_reset, q232_rxreset, q232_pmareset;
    wire q232_txdone, q232_rxdone, q232_qplllock;
    wire [2:0] q232_loopback;
    wire [39:0] q232_drpaddr;
    wire [3:0] q232_drpen, q232_drprdy;
    wire [63:0] q232_drpdo;
    gty_quad_232 q232_gt (
        .gtyrxn_in(q232_rx_n), .gtyrxp_in(q232_rx_p),
        .gtytxn_out(q232_tx_n), .gtytxp_out(q232_tx_p),
        .gtrefclk00_in(q232_ref),
        .gtwiz_userclk_tx_reset_in(~(&q232_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q232_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q232_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q232_rxclk),
        .gtwiz_reset_clk_freerun_in(q232_clk),
        .gtwiz_reset_all_in(q232_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q232_rxreset),
        .gtwiz_reset_tx_done_out(q232_txdone),
        .gtwiz_reset_rx_done_out(q232_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q232_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q232_forceerr), .rxpolarity_in(q232_polarity),
        .rxprbscntreset_in(q232_cntreset),
        .rxpmareset_in({4{q232_pmareset}}),
        .rxprbslocked_out(q232_locked), .rxprbserr_out(q232_prbserr),
        .gtpowergood_out(q232_power), .txpmaresetdone_out(q232_txpma),
        .rxpmaresetdone_out(q232_rxpma),
        .qpll0lock_out(q232_qplllock),
        .drpaddr_in(q232_drpaddr), .drpclk_in({4{q232_clk}}),
        .drpdi_in(64'd0), .drpen_in(q232_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q232_drpdo), .drprdy_out(q232_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q232_control (
        .clk(q232_clk), .txclk(q232_txclk), .rxclk(q232_rxclk),
        .powergood(q232_power), .txpma(q232_txpma), .rxpma(q232_rxpma),
        .txdone(q232_txdone), .rxdone(q232_rxdone),
        .qplllock(q232_qplllock),
        .locked(q232_locked), .prbserr(q232_prbserr),
        .reset_all(q232_reset), .reset_rx(q232_rxreset), .reset_pma(q232_pmareset),
        .loopback(q232_loopback), .count_reset(q232_cntreset),
        .force_error(q232_forceerr), .rxpolarity(q232_polarity), .drpaddr(q232_drpaddr),
        .drpen(q232_drpen), .drpdo(q232_drpdo), .drprdy(q232_drprdy));

    // ---- GTY229: QSFP2, channels X1Y36-X1Y39 ----

    // Reference input and 161.1328125 MHz control clock
    wire q229_ref, q229_odiv, q229_clk, q229_txclk, q229_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q229_refbuf (
        .I(q229_ref_p), .IB(q229_ref_n), .CEB(1'b0),
        .O(q229_ref), .ODIV2(q229_odiv));
    BUFG_GT q229_freerun (.I(q229_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q229_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q229_power, q229_txpma, q229_rxpma;
    wire [3:0] q229_locked, q229_prbserr, q229_cntreset, q229_forceerr, q229_polarity;
    wire q229_reset, q229_rxreset, q229_pmareset;
    wire q229_txdone, q229_rxdone, q229_qplllock;
    wire [2:0] q229_loopback;
    wire [39:0] q229_drpaddr;
    wire [3:0] q229_drpen, q229_drprdy;
    wire [63:0] q229_drpdo;
    gty_quad_229 q229_gt (
        .gtyrxn_in(q229_rx_n), .gtyrxp_in(q229_rx_p),
        .gtytxn_out(q229_tx_n), .gtytxp_out(q229_tx_p),
        .gtrefclk00_in(q229_ref),
        .gtwiz_userclk_tx_reset_in(~(&q229_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q229_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q229_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q229_rxclk),
        .gtwiz_reset_clk_freerun_in(q229_clk),
        .gtwiz_reset_all_in(q229_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q229_rxreset),
        .gtwiz_reset_tx_done_out(q229_txdone),
        .gtwiz_reset_rx_done_out(q229_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q229_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q229_forceerr), .rxpolarity_in(q229_polarity),
        .rxprbscntreset_in(q229_cntreset),
        .rxpmareset_in({4{q229_pmareset}}),
        .rxprbslocked_out(q229_locked), .rxprbserr_out(q229_prbserr),
        .gtpowergood_out(q229_power), .txpmaresetdone_out(q229_txpma),
        .rxpmaresetdone_out(q229_rxpma),
        .qpll0lock_out(q229_qplllock),
        .drpaddr_in(q229_drpaddr), .drpclk_in({4{q229_clk}}),
        .drpdi_in(64'd0), .drpen_in(q229_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q229_drpdo), .drprdy_out(q229_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q229_control (
        .clk(q229_clk), .txclk(q229_txclk), .rxclk(q229_rxclk),
        .powergood(q229_power), .txpma(q229_txpma), .rxpma(q229_rxpma),
        .txdone(q229_txdone), .rxdone(q229_rxdone),
        .qplllock(q229_qplllock),
        .locked(q229_locked), .prbserr(q229_prbserr),
        .reset_all(q229_reset), .reset_rx(q229_rxreset), .reset_pma(q229_pmareset),
        .loopback(q229_loopback), .count_reset(q229_cntreset),
        .force_error(q229_forceerr), .rxpolarity(q229_polarity), .drpaddr(q229_drpaddr),
        .drpen(q229_drpen), .drpdo(q229_drpdo), .drprdy(q229_drprdy));

    // ---- GTY228: QSFP3, channels X1Y32-X1Y35 ----

    // Reference input and 161.1328125 MHz control clock
    wire q228_ref, q228_odiv, q228_clk, q228_txclk, q228_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q228_refbuf (
        .I(q228_ref_p), .IB(q228_ref_n), .CEB(1'b0),
        .O(q228_ref), .ODIV2(q228_odiv));
    BUFG_GT q228_freerun (.I(q228_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q228_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q228_power, q228_txpma, q228_rxpma;
    wire [3:0] q228_locked, q228_prbserr, q228_cntreset, q228_forceerr, q228_polarity;
    wire q228_reset, q228_rxreset, q228_pmareset;
    wire q228_txdone, q228_rxdone, q228_qplllock;
    wire [2:0] q228_loopback;
    wire [39:0] q228_drpaddr;
    wire [3:0] q228_drpen, q228_drprdy;
    wire [63:0] q228_drpdo;
    gty_quad_228 q228_gt (
        .gtyrxn_in(q228_rx_n), .gtyrxp_in(q228_rx_p),
        .gtytxn_out(q228_tx_n), .gtytxp_out(q228_tx_p),
        .gtrefclk00_in(q228_ref),
        .gtwiz_userclk_tx_reset_in(~(&q228_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q228_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q228_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q228_rxclk),
        .gtwiz_reset_clk_freerun_in(q228_clk),
        .gtwiz_reset_all_in(q228_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q228_rxreset),
        .gtwiz_reset_tx_done_out(q228_txdone),
        .gtwiz_reset_rx_done_out(q228_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q228_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q228_forceerr), .rxpolarity_in(q228_polarity),
        .rxprbscntreset_in(q228_cntreset),
        .rxpmareset_in({4{q228_pmareset}}),
        .rxprbslocked_out(q228_locked), .rxprbserr_out(q228_prbserr),
        .gtpowergood_out(q228_power), .txpmaresetdone_out(q228_txpma),
        .rxpmaresetdone_out(q228_rxpma),
        .qpll0lock_out(q228_qplllock),
        .drpaddr_in(q228_drpaddr), .drpclk_in({4{q228_clk}}),
        .drpdi_in(64'd0), .drpen_in(q228_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q228_drpdo), .drprdy_out(q228_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q228_control (
        .clk(q228_clk), .txclk(q228_txclk), .rxclk(q228_rxclk),
        .powergood(q228_power), .txpma(q228_txpma), .rxpma(q228_rxpma),
        .txdone(q228_txdone), .rxdone(q228_rxdone),
        .qplllock(q228_qplllock),
        .locked(q228_locked), .prbserr(q228_prbserr),
        .reset_all(q228_reset), .reset_rx(q228_rxreset), .reset_pma(q228_pmareset),
        .loopback(q228_loopback), .count_reset(q228_cntreset),
        .force_error(q228_forceerr), .rxpolarity(q228_polarity), .drpaddr(q228_drpaddr),
        .drpen(q228_drpen), .drpdo(q228_drpdo), .drprdy(q228_drprdy));

    // ---- GTY129: SlimSAS1 lanes 0-3, channels X0Y36-X0Y39 ----

    // Reference input and 161.1328125 MHz control clock
    wire q129_ref, q129_odiv, q129_clk, q129_txclk, q129_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q129_refbuf (
        .I(q129_ref_p), .IB(q129_ref_n), .CEB(1'b0),
        .O(q129_ref), .ODIV2(q129_odiv));
    BUFG_GT q129_freerun (.I(q129_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q129_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q129_power, q129_txpma, q129_rxpma;
    wire [3:0] q129_locked, q129_prbserr, q129_cntreset, q129_forceerr, q129_polarity;
    wire q129_reset, q129_rxreset, q129_pmareset;
    wire q129_txdone, q129_rxdone, q129_qplllock;
    wire [2:0] q129_loopback;
    wire [39:0] q129_drpaddr;
    wire [3:0] q129_drpen, q129_drprdy;
    wire [63:0] q129_drpdo;
    gty_quad_129 q129_gt (
        .gtyrxn_in(q129_rx_n), .gtyrxp_in(q129_rx_p),
        .gtytxn_out(q129_tx_n), .gtytxp_out(q129_tx_p),
        .gtrefclk00_in(q129_ref),
        .gtwiz_userclk_tx_reset_in(~(&q129_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q129_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q129_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q129_rxclk),
        .gtwiz_reset_clk_freerun_in(q129_clk),
        .gtwiz_reset_all_in(q129_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q129_rxreset),
        .gtwiz_reset_tx_done_out(q129_txdone),
        .gtwiz_reset_rx_done_out(q129_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q129_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q129_forceerr), .rxpolarity_in(q129_polarity),
        .rxprbscntreset_in(q129_cntreset),
        .rxpmareset_in({4{q129_pmareset}}),
        .rxprbslocked_out(q129_locked), .rxprbserr_out(q129_prbserr),
        .gtpowergood_out(q129_power), .txpmaresetdone_out(q129_txpma),
        .rxpmaresetdone_out(q129_rxpma),
        .qpll0lock_out(q129_qplllock),
        .drpaddr_in(q129_drpaddr), .drpclk_in({4{q129_clk}}),
        .drpdi_in(64'd0), .drpen_in(q129_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q129_drpdo), .drprdy_out(q129_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q129_control (
        .clk(q129_clk), .txclk(q129_txclk), .rxclk(q129_rxclk),
        .powergood(q129_power), .txpma(q129_txpma), .rxpma(q129_rxpma),
        .txdone(q129_txdone), .rxdone(q129_rxdone),
        .qplllock(q129_qplllock),
        .locked(q129_locked), .prbserr(q129_prbserr),
        .reset_all(q129_reset), .reset_rx(q129_rxreset), .reset_pma(q129_pmareset),
        .loopback(q129_loopback), .count_reset(q129_cntreset),
        .force_error(q129_forceerr), .rxpolarity(q129_polarity), .drpaddr(q129_drpaddr),
        .drpen(q129_drpen), .drpdo(q129_drpdo), .drprdy(q129_drprdy));

    // ---- GTY133: SlimSAS1 lanes 4-7, channels X0Y52-X0Y55 ----

    // Reference input and 161.1328125 MHz control clock
    wire q133_ref, q133_odiv, q133_clk, q133_txclk, q133_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q133_refbuf (
        .I(q133_ref_p), .IB(q133_ref_n), .CEB(1'b0),
        .O(q133_ref), .ODIV2(q133_odiv));
    BUFG_GT q133_freerun (.I(q133_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q133_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q133_power, q133_txpma, q133_rxpma;
    wire [3:0] q133_locked, q133_prbserr, q133_cntreset, q133_forceerr, q133_polarity;
    wire q133_reset, q133_rxreset, q133_pmareset;
    wire q133_txdone, q133_rxdone, q133_qplllock;
    wire [2:0] q133_loopback;
    wire [39:0] q133_drpaddr;
    wire [3:0] q133_drpen, q133_drprdy;
    wire [63:0] q133_drpdo;
    gty_quad_133 q133_gt (
        .gtyrxn_in(q133_rx_n), .gtyrxp_in(q133_rx_p),
        .gtytxn_out(q133_tx_n), .gtytxp_out(q133_tx_p),
        .gtrefclk00_in(q133_ref),
        .gtwiz_userclk_tx_reset_in(~(&q133_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q133_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q133_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q133_rxclk),
        .gtwiz_reset_clk_freerun_in(q133_clk),
        .gtwiz_reset_all_in(q133_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q133_rxreset),
        .gtwiz_reset_tx_done_out(q133_txdone),
        .gtwiz_reset_rx_done_out(q133_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q133_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q133_forceerr), .rxpolarity_in(q133_polarity),
        .rxprbscntreset_in(q133_cntreset),
        .rxpmareset_in({4{q133_pmareset}}),
        .rxprbslocked_out(q133_locked), .rxprbserr_out(q133_prbserr),
        .gtpowergood_out(q133_power), .txpmaresetdone_out(q133_txpma),
        .rxpmaresetdone_out(q133_rxpma),
        .qpll0lock_out(q133_qplllock),
        .drpaddr_in(q133_drpaddr), .drpclk_in({4{q133_clk}}),
        .drpdi_in(64'd0), .drpen_in(q133_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q133_drpdo), .drprdy_out(q133_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q133_control (
        .clk(q133_clk), .txclk(q133_txclk), .rxclk(q133_rxclk),
        .powergood(q133_power), .txpma(q133_txpma), .rxpma(q133_rxpma),
        .txdone(q133_txdone), .rxdone(q133_rxdone),
        .qplllock(q133_qplllock),
        .locked(q133_locked), .prbserr(q133_prbserr),
        .reset_all(q133_reset), .reset_rx(q133_rxreset), .reset_pma(q133_pmareset),
        .loopback(q133_loopback), .count_reset(q133_cntreset),
        .force_error(q133_forceerr), .rxpolarity(q133_polarity), .drpaddr(q133_drpaddr),
        .drpen(q133_drpen), .drpdo(q133_drpdo), .drprdy(q133_drprdy));

    // ---- GTY120: SlimSAS2 lanes 0-3, channels X0Y0-X0Y3 ----

    // Reference input and 161.1328125 MHz control clock
    wire q120_ref, q120_odiv, q120_clk, q120_txclk, q120_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q120_refbuf (
        .I(q120_ref_p), .IB(q120_ref_n), .CEB(1'b0),
        .O(q120_ref), .ODIV2(q120_odiv));
    BUFG_GT q120_freerun (.I(q120_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q120_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q120_power, q120_txpma, q120_rxpma;
    wire [3:0] q120_locked, q120_prbserr, q120_cntreset, q120_forceerr, q120_polarity;
    wire q120_reset, q120_rxreset, q120_pmareset;
    wire q120_txdone, q120_rxdone, q120_qplllock;
    wire [2:0] q120_loopback;
    wire [39:0] q120_drpaddr;
    wire [3:0] q120_drpen, q120_drprdy;
    wire [63:0] q120_drpdo;
    gty_quad_120 q120_gt (
        .gtyrxn_in(q120_rx_n), .gtyrxp_in(q120_rx_p),
        .gtytxn_out(q120_tx_n), .gtytxp_out(q120_tx_p),
        .gtrefclk00_in(q120_ref),
        .gtwiz_userclk_tx_reset_in(~(&q120_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q120_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q120_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q120_rxclk),
        .gtwiz_reset_clk_freerun_in(q120_clk),
        .gtwiz_reset_all_in(q120_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q120_rxreset),
        .gtwiz_reset_tx_done_out(q120_txdone),
        .gtwiz_reset_rx_done_out(q120_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q120_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q120_forceerr), .rxpolarity_in(q120_polarity),
        .rxprbscntreset_in(q120_cntreset),
        .rxpmareset_in({4{q120_pmareset}}),
        .rxprbslocked_out(q120_locked), .rxprbserr_out(q120_prbserr),
        .gtpowergood_out(q120_power), .txpmaresetdone_out(q120_txpma),
        .rxpmaresetdone_out(q120_rxpma),
        .qpll0lock_out(q120_qplllock),
        .drpaddr_in(q120_drpaddr), .drpclk_in({4{q120_clk}}),
        .drpdi_in(64'd0), .drpen_in(q120_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q120_drpdo), .drprdy_out(q120_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q120_control (
        .clk(q120_clk), .txclk(q120_txclk), .rxclk(q120_rxclk),
        .powergood(q120_power), .txpma(q120_txpma), .rxpma(q120_rxpma),
        .txdone(q120_txdone), .rxdone(q120_rxdone),
        .qplllock(q120_qplllock),
        .locked(q120_locked), .prbserr(q120_prbserr),
        .reset_all(q120_reset), .reset_rx(q120_rxreset), .reset_pma(q120_pmareset),
        .loopback(q120_loopback), .count_reset(q120_cntreset),
        .force_error(q120_forceerr), .rxpolarity(q120_polarity), .drpaddr(q120_drpaddr),
        .drpen(q120_drpen), .drpdo(q120_drpdo), .drprdy(q120_drprdy));

    // ---- GTY121: SlimSAS2 lanes 4-7, channels X0Y4-X0Y7 ----

    // Reference input and 161.1328125 MHz control clock
    wire q121_ref, q121_odiv, q121_clk, q121_txclk, q121_rxclk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) q121_refbuf (
        .I(q121_ref_p), .IB(q121_ref_n), .CEB(1'b0),
        .O(q121_ref), .ODIV2(q121_odiv));
    BUFG_GT q121_freerun (.I(q121_odiv), .CE(1'b1), .CEMASK(1'b0),
        .CLR(1'b0), .CLRMASK(1'b0), .DIV(3'b001), .O(q121_clk));

    // Four GT lanes, native PRBS31 generators and checkers
    wire [3:0] q121_power, q121_txpma, q121_rxpma;
    wire [3:0] q121_locked, q121_prbserr, q121_cntreset, q121_forceerr, q121_polarity;
    wire q121_reset, q121_rxreset, q121_pmareset;
    wire q121_txdone, q121_rxdone, q121_qplllock;
    wire [2:0] q121_loopback;
    wire [39:0] q121_drpaddr;
    wire [3:0] q121_drpen, q121_drprdy;
    wire [63:0] q121_drpdo;
    gty_quad_121 q121_gt (
        .gtyrxn_in(q121_rx_n), .gtyrxp_in(q121_rx_p),
        .gtytxn_out(q121_tx_n), .gtytxp_out(q121_tx_p),
        .gtrefclk00_in(q121_ref),
        .gtwiz_userclk_tx_reset_in(~(&q121_txpma)),
        .gtwiz_userclk_rx_reset_in(~(&q121_rxpma)),
        .gtwiz_userclk_tx_usrclk2_out(q121_txclk),
        .gtwiz_userclk_rx_usrclk2_out(q121_rxclk),
        .gtwiz_reset_clk_freerun_in(q121_clk),
        .gtwiz_reset_all_in(q121_reset),
        .gtwiz_reset_tx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_tx_datapath_in(1'b0),
        .gtwiz_reset_rx_pll_and_datapath_in(1'b0),
        .gtwiz_reset_rx_datapath_in(q121_rxreset),
        .gtwiz_reset_tx_done_out(q121_txdone),
        .gtwiz_reset_rx_done_out(q121_rxdone),
        .gtwiz_userdata_tx_in(256'd0),
        .loopback_in({4{q121_loopback}}),
        .txprbssel_in({4{4'b0101}}), .rxprbssel_in({4{4'b0101}}),
        .txprbsforceerr_in(q121_forceerr), .rxpolarity_in(q121_polarity),
        .rxprbscntreset_in(q121_cntreset),
        .rxpmareset_in({4{q121_pmareset}}),
        .rxprbslocked_out(q121_locked), .rxprbserr_out(q121_prbserr),
        .gtpowergood_out(q121_power), .txpmaresetdone_out(q121_txpma),
        .rxpmaresetdone_out(q121_rxpma),
        .qpll0lock_out(q121_qplllock),
        .drpaddr_in(q121_drpaddr), .drpclk_in({4{q121_clk}}),
        .drpdi_in(64'd0), .drpen_in(q121_drpen), .drprst_in(4'd0),
        .drpwe_in(4'd0), .drpdo_out(q121_drpdo), .drprdy_out(q121_drprdy));

    // JTAG control, lane markers, polarity and read-only counter access
    quad_control q121_control (
        .clk(q121_clk), .txclk(q121_txclk), .rxclk(q121_rxclk),
        .powergood(q121_power), .txpma(q121_txpma), .rxpma(q121_rxpma),
        .txdone(q121_txdone), .rxdone(q121_rxdone),
        .qplllock(q121_qplllock),
        .locked(q121_locked), .prbserr(q121_prbserr),
        .reset_all(q121_reset), .reset_rx(q121_rxreset), .reset_pma(q121_pmareset),
        .loopback(q121_loopback), .count_reset(q121_cntreset),
        .force_error(q121_forceerr), .rxpolarity(q121_polarity), .drpaddr(q121_drpaddr),
        .drpen(q121_drpen), .drpdo(q121_drpdo), .drprdy(q121_drprdy));

endmodule
