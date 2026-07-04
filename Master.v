//clk divider module:
module Clock_Divider (
    input wire clk,
    input wire rst,
    input wire clk_En, // for toggleging SCL
    output reg SCL
);
    reg [9:0] clk_counter;
    // For simulation: use smaller value (10) for faster testing
    // For synthesis: use 1000 to get 400KHz SCL from 400MHz clk
    parameter divider_value = 10; // Change to 1000 for actual 400KHz SCL

always @(posedge clk or negedge rst) 
begin
    if (!rst) 
    begin
        clk_counter <= 1'b0;
        SCL         <= 1'b1;
    end    
    else if (clk_En) 
    begin
        if (clk_counter == (divider_value/2)-1) 
            begin
                clk_counter <= clk_counter + 1;
                SCL <= ~SCL;
            end
        else if (clk_counter == divider_value-1) 
            begin
                clk_counter <= 0;
                SCL <= ~SCL;
            end
        else 
            begin
                clk_counter <= clk_counter + 1;
            end    
    end
    else
    begin
        clk_counter <= 1'b0;
        SCL         <= 1'b1;
    end
end

endmodule

//----------------------------------------------------------
//Master module:
module Master 
(
    inout SDA,
    inout SCL,
    input wire       start, // To start writting or reading operation.
    input wire       clk, // With fast mode rate 400MHz.
    input wire       rst, // To reset the operation.
    input wire [7:0] slave_address, // Address of slave that is comming from the desired slave(If there are many of slaves).
    input wire [7:0] data_writting, // Data is taken from test bench(CPU) that we need to send it to slave.

    output reg       ready_to_read, // This is indicator for reading data from slave.
    output reg       error_RorW, // If there is any error during reading or writting operation.
    output reg       busy, // Checking for availability to send or recieve data(if it is still reading or writting Or NOT).
    output reg [7:0] data_reading // Data is recieved from slave to test bench(CPU).

);

reg RorW; // This bit is comming after slave_address to get read or write data.
reg [7:0] Delay_counter; // counter for setup time delay.
reg ack_received; // Flag to store ACK/NACK result from slave.
reg ack_sampled; // Flag to indicate ACK bit has been sampled.

// Clock divider instantiation
reg clk_En;
wire clk_divider_out;
Clock_Divider Clock_Divider1 (
    .clk(clk),
    .rst(rst),
    .clk_En(clk_En),
    .SCL(clk_divider_out) // To generate clock with rate 400KHz for I2C.
);

// For detection of SCL edges:
reg scl_prev;
reg scl_rising;
reg scl_falling;

always @(posedge clk or negedge rst) 
begin
    if (!rst) 
    begin
        scl_prev <= 1'b1;
        scl_rising <= 1'b0;
        scl_falling <= 1'b0;
    end 
    else 
    begin
        scl_prev <= SCL;
        scl_rising <= (SCL & ~scl_prev);
        scl_falling <= (~SCL & scl_prev);
    end
end

// Tri-state SDA control: this is the idea for the function of SDA bidirectional line.
//Master read from SDA (Releasing SDA to allow slave for writing(sending) data) but write on SDA_out.
reg SDA_out;
reg SDA_En;
assign SDA = SDA_En ? SDA_out : 1'bz;

// FSM states 
localparam IDLE          = 3'b000,  // For Intialization of SCL&SDA.
           START         = 3'b001,  // Start condition.
           ADDRESS       = 3'b010,  // Address + R/W.
           ACKNOWLEDGE    = 3'b011,  // Checking for ack or not_ack. 
           DATA          = 3'b100,  // Read or Write data.
           STOP          = 3'b101;  // Stop condition.

reg [2:0] current_state, next_state;
reg [2:0] counter; // A counter to count the bits recieved to know state of RorW and state of ack.

// Tri-state SCL control: this is the idea for solving the problem of clock streching (Its occur when slave holding scl low, Master should release scl, until scl is high master can continue normal operation) and for keep SCL high at stop condition.
reg SCL_En;
wire scl_driven = SCL_En ? clk_divider_out : 1'bz;
assign SCL = scl_driven;


always @(posedge clk or negedge rst) 
begin
    if (!rst) 
    begin
        current_state <= IDLE;  
        counter <= 3'b0;
        Delay_counter <= 8'b0;
        data_reading <= 8'b0;
        ack_received <= 1'b0;
        ack_sampled <= 1'b0;
    end    
    else 
    begin
        // Reset Delay_counter on state change
        if (current_state != next_state)
        begin
            Delay_counter <= 8'b0;
            ack_sampled <= 1'b0;
        end
            
        current_state <= next_state; 
        
        case (current_state)
            IDLE: 
            begin
                counter <= 3'b0;
            end
            
            START: 
            begin
                if (Delay_counter < 10) //For setup time delay.
                begin
                    Delay_counter <= Delay_counter + 1;
                end    
            end

            ADDRESS : 
            begin
                if (scl_falling) 
                begin
                    if (counter == 3'd7) 
                    begin 
                        counter <= 3'b0;
                        RorW    <= slave_address[0];
                    end    
                    else 
                    begin
                        counter <= counter + 1;
                    end    
                end
            end
            
            ACKNOWLEDGE :
            begin
                // Sample SDA during SCL HIGH period (ACK bit)
                // According to I2C spec: ACK is sampled during HIGH SCL period
                // Using scl_rising edge for proper timing
                if (scl_rising && !ack_sampled)
                begin
                    ack_received <= ~SDA; // ACK if SDA is LOW
                    ack_sampled <= 1'b1;
                end
            end
            
            DATA :
            begin
                if (scl_falling) 
                begin
                    if (counter == 3'd7) 
                    begin 
                        counter <= 3'b0;
                    end    
                    else 
                    begin
                        counter <= counter + 1;
                    end    
                end
                if (scl_rising && RorW) //read data from slave
                begin
                    // During read operation, master samples SDA on rising edge
                    // SDA is driven by slave (Master released SDA)
                    data_reading[7-counter] <= SDA;
                end    
            end

            STOP: 
            begin
                if (Delay_counter < 20) //For stop condition timing.
                begin
                    Delay_counter <= Delay_counter + 1;
                end 
            end       
        endcase   
    end
end

always @(*) 
begin
    // To prevent any latchs creation make these default:
    next_state = current_state;   
    clk_En           = 1'b0;             
    ready_to_read    = 1'b0; 
    error_RorW       = 1'b0;
    busy             = 1'b0;
    SCL_En           = 1'b0;
    SDA_out          = 1'b0;
    SDA_En           = 1'b0;
    
    case (current_state)
        IDLE : begin
            busy = 1'b0;
            SCL_En = 1'b1;
            SDA_out = 1'b1;
            SDA_En = 1'b1;
            clk_En = 1'b0;
            if (start) 
            begin
                busy = 1'b1;
                next_state = START;
            end   
        end 

        START : begin
            SDA_En = 1'b1;
            clk_En = 1'b1;
            busy = 1'b1;
            SCL_En = 1'b1;
            SDA_out = 1'b0;  // Pull SDA LOW for START condition
            // Start condition: SDA HIGH->LOW while SCL is HIGH
            if (Delay_counter == 10) 
            begin
                next_state = ADDRESS;
            end 
        end 

        ADDRESS : begin
            clk_En = 1'b1;
            busy = 1'b1;
            SCL_En = 1'b1;
            SDA_En = 1'b1;
            
            // Bits 0-6 are Address, Bit 7 is R/W
            if (counter < 7)
            begin
                SDA_out = slave_address[7-counter];
            end    
            else
            begin
                SDA_out = slave_address[0]; // R/W bit
            end
            
            if (counter == 3'd7 && scl_falling) 
            begin
                next_state = ACKNOWLEDGE;
            end       
        end          

        ACKNOWLEDGE : begin
            clk_En  = 1'b1;
            busy    = 1'b1;
            SDA_En  = 1'b0; // Master release SDA(High-Z) for slave to send ACK.
            SCL_En  = 1'b1; 
            
            // Wait for ACK clock pulse to complete
            // ACK is sampled during SCL rising edge in sequential block
            if (scl_falling && ack_sampled) 
            begin 
                if (ack_received) // Check if Slave pulled SDA low (ACK)
                begin 
                    // After ACK, master will decide in DATA state whether to reclaim SDA
                    // For write (RorW=0): Master reclaims SDA to send data
                    // For read (RorW=1): Master keeps SDA released to receive data
                    next_state = DATA;
                end 
                else 
                begin
                    error_RorW = 1'b1; // NACK: Slave didn't respond
                    next_state = STOP;
                end
            end
        end      

        DATA : begin
            clk_En = 1'b1;
            busy   = 1'b1;
            SCL_En = 1'b1;      // Resume driving SCL.  
            
            if (!RorW) // write data from master on SDA "to slave"
            begin
                SDA_En  = 1'b1; // MASTER RECLAIMS SDA CONTROL after ACK to send data to slave.
                SDA_out = data_writting[7-counter];
            end  
            else // read data from slave "to master"
            begin
                SDA_En = 1'b0; // Master KEEPS SDA released to let slave send data that Master need to read.
                // SDA_out value doesn't matter when SDA_En is 0 (High-Z state)
            end               
            
            if (counter == 3'd7 && scl_falling) 
            begin 
                ready_to_read = 1'b1;
                next_state = STOP;
            end     
        end          

        STOP : begin
            clk_En = 1'b0;      // Stop the divider
            busy = 1'b1;
            SDA_En = 1'b1;
            SCL_En = 1'b1;      // Ensure master is driving SCL High
            
            // Stop condition: SDA LOW->HIGH while SCL is HIGH
            // Step 1: Keep SDA Low while SCL is HIGH
            if (Delay_counter < 10) 
            begin
                SDA_out = 1'b0; // Hold SDA LOW
            end 
            // Step 2: Pull SDA High (The actual STOP condition)
            else 
            begin
                SDA_out = 1'b1; // Pull SDA HIGH while SCL is HIGH (STOP condition)
            end

            if (Delay_counter == 20) 
            begin
                next_state = IDLE;
            end
        end                                                  
        
        default: begin
            next_state = IDLE;
        end
    endcase
end
    
endmodule