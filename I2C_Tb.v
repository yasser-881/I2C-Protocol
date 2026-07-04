`timescale 1ns / 1ps

module I2C_Tb();

    // Inputs to Master
    reg clk;
    reg rst;
    reg start;
    reg [7:0] slave_address;
    reg [7:0] data_writting;

    // Outputs from Master
    wire ready_to_read;
    wire error_RorW;
    wire busy;
    wire [7:0] data_reading;

    // Bidirectional Pins
    wire SDA;
    wire SCL;

    // Slave simulation signals
    reg slave_sda_en;
    reg slave_sda_out;
    reg [7:0] received_data;  // Store data received by slave
    integer i;                 // Loop variable
    
    // Instantiate the Master module
    Master uut (
        .SDA(SDA),
        .SCL(SCL),
        .start(start),
        .clk(clk),
        .rst(rst),
        .slave_address(slave_address),
        .data_writting(data_writting),
        .ready_to_read(ready_to_read),
        .error_RorW(error_RorW),
        .busy(busy),
        .data_reading(data_reading)
    );

    // Clock Generation: 400MHz (2.5ns period)
    always #1.25 clk = ~clk;

    // Tri-state SDA control for slave with weak pull-up
    // Using manual weak pull-up for better simulator compatibility
    wire weak_pullup = 1'b1;
    assign SDA = slave_sda_en ? slave_sda_out : 1'bz;
    
    // Weak pull-up simulation (works in all Verilog simulators)
    pullup (SDA);
    pullup (SCL);

    // -----------------------------------------------------------------
    // Simple slave that responds with ACK
    // -----------------------------------------------------------------
    initial begin
        slave_sda_en = 1'b0;
        slave_sda_out = 1'b0;
        received_data = 8'h00;
        
        // Wait for reset to complete
        wait(rst == 1'b1);
        
        // Wait for START condition (SDA falling while SCL HIGH)
        @(negedge SDA);
        if (SCL == 1'b1) begin
            $display("[SLAVE] START detected at %0t", $time);
            
            // Skip 8 address bits
            repeat (8) @(posedge SCL);
            
            // Send ACK for address (pull SDA low during 9th bit)
            @(negedge SCL);
            slave_sda_en = 1'b1;
            slave_sda_out = 1'b0;
            $display("[SLAVE] Sending ACK for address at %0t", $time);
            
            // Hold ACK through SCL HIGH period
            @(posedge SCL);
            @(negedge SCL);
            
            // Release SDA after ACK
            slave_sda_en = 1'b0;
            
            // Receive 8 data bits from master (WRITE operation)
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge SCL);
                received_data[i] = SDA;
            end
            $display("[SLAVE] Received data: 0x%h at %0t", received_data, $time);
            
            // Send ACK for data
            @(negedge SCL);
            slave_sda_en = 1'b1;
            slave_sda_out = 1'b0;
            $display("[SLAVE] Sending ACK for data at %0t", $time);
            
            // Hold ACK through SCL HIGH period
            @(posedge SCL);
            @(negedge SCL);
            
            // Release SDA after ACK
            slave_sda_en = 1'b0;
            
            // Wait for STOP condition (SDA rising while SCL HIGH)
            @(posedge SDA);
            if (SCL == 1'b1) begin
                $display("[SLAVE] STOP detected at %0t", $time);
            end
        end
    end

    // -----------------------------------------------------------------
    // Monitor Master State Machine for debugging
    // -----------------------------------------------------------------
    always @(uut.current_state) begin
        case (uut.current_state)
            3'b000: $display("[MASTER] State: IDLE at time %0t", $time);
            3'b001: $display("[MASTER] State: START at time %0t", $time);
            3'b010: $display("[MASTER] State: ADDRESS at time %0t", $time);
            3'b011: $display("[MASTER] State: ACKNOWLEDGE at time %0t", $time);
            3'b100: $display("[MASTER] State: DATA at time %0t", $time);
            3'b101: $display("[MASTER] State: STOP at time %0t", $time);
        endcase
    end

    // -----------------------------------------------------------------
    // Main Test Sequence - WRITE Operation
    // -----------------------------------------------------------------
    initial begin
        clk = 0;
        rst = 0;
        start = 0;
        slave_address = 8'b11001000;   // 0xC8 = address 0x64 + write (0)
        data_writting = 8'b10100101;   // 0xA5

        $display("========================================");
        $display("       I2C MASTER WRITE TEST");
        $display("========================================");
        
        // Apply reset
        #100 rst = 0;
        #500 rst = 1;
        #1000;
        
        $display("[TEST] Starting WRITE operation at time %0t", $time);
        $display("[TEST] Slave Address: 0x%h (7-bit: 0x%h, R/W: WRITE)", slave_address, slave_address[7:1]);
        $display("[TEST] Data to write: 0x%h", data_writting);
        $display("========================================");

        // Start the transaction
        #100 start = 1;
        #500 start = 0;

        // Wait for transaction to complete
        wait(busy == 1'b0);
        #2000;
        
        // Check results
        $display("========================================");
        $display("            TEST RESULTS");
        $display("========================================");
        if (received_data == data_writting) begin
            $display("[TEST] RESULT: PASSED");
            $display("[TEST] Data correctly transmitted!");
            $display("[TEST] Sent: 0x%h, Received: 0x%h", data_writting, received_data);
        end else begin
            $display("[TEST] RESULT: FAILED");
            $display("[TEST] Data mismatch detected!");
            $display("[TEST] Sent: 0x%h, Received: 0x%h", data_writting, received_data);
        end
        
        if (error_RorW) begin
            $display("[TEST] ERROR: error_RorW signal asserted!");
        end else begin
            $display("[TEST] No error detected (error_RorW = 0)");
        end
        $display("========================================");
        
        #1000;
        $finish;
    end

    // -----------------------------------------------------------------
    // Waveform Dump for Debugging
    // -----------------------------------------------------------------
    initial begin
        $dumpfile("i2c_master_wave.vcd");
        $dumpvars(0, Master_tb);
    end

    // -----------------------------------------------------------------
    // Timeout Protection
    // -----------------------------------------------------------------
    initial begin
        #100000;
        $display("[ERROR] Simulation timeout at %0t!", $time);
        $finish;
    end

endmodule