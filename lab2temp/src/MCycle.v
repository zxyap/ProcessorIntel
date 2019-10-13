`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: NUS
// Engineer: Shahzor Ahmad, Rajesh C Panicker
// 
// Create Date: 27.09.2016 10:59:44
// Design Name: 
// Module Name: MCycle
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
/* 
----------------------------------------------------------------------------------
--	(c) Shahzor Ahmad, Rajesh C Panicker
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate any intellectual property of ARM Holdings or other entities.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

module MCycle

    #(parameter width = 4) // Keep this at 4 to verify your algorithms with 4 bit numbers (easier). When using MCycle as a component in ARM, generic map it to 32.
    (
        input CLK,
        input RESET, // Connect this to the reset of the ARM processor.
        input Start, // Multi-cycle Enable. The control unit should assert this when an instruction with a multi-cycle operation is detected.
        input [1:0] MCycleOp, // Multi-cycle Operation. "00" for signed multiplication, "01" for unsigned multiplication, "10" for signed division, "11" for unsigned division. Generated by Control unit
        input [width-1:0] Operand1, // Multiplicand / Dividend / the original number
        input [width-1:0] Operand2, // Multiplier / Divisor
        output reg [width-1:0] Result1, // LSW of Product / Quotient
        output reg [width-1:0] Result2, // MSW of Product / Remainder
        output reg Busy // Set immediately when Start is set. Cleared when the Results become ready. This bit can be used to stall the processor while multi-cycle operations are on.
    );
    
// use the Busy signal to reset WE_PC to 0 in ARM.v (aka "freeze" PC). The two signals are complements of each other
// since the IDLE_PROCESS is combinational, instantaneously asserts Busy once Start is asserted
  
    parameter IDLE = 1'b0 ;  // will cause a warning which is ok to ignore - [Synth 8-2507] parameter declaration becomes local in MCycle with formal parameter declaration list...

    parameter COMPUTING = 1'b1 ; // this line will also cause the above warning
    reg state = IDLE ;
    reg n_state = IDLE ;
   
    reg done ;
    reg [7:0] count = 0 ; // assuming no computation takes more than 256 cycles.
    reg [2*width-1:0] temp_sum = 0 ;
    reg [2*width-1:0] shifted_op1 = 0 ;
    reg [2*width-1:0] shifted_op2 = 0 ;
    reg [2*width-1:0] shifted_op2D = 0;
    reg [2*width:0] pad_shifted_op2D = 0;
    reg [2*width:0] pad_shifted_op1 = 0 ;
    reg [width-1:0] quotient = 0;     
    reg [2*width-1:0] temporary = 0;
    reg [width-1:0] positiveOperand1 = 0;
    reg [width-1:0] positiveOperand2 = 0;
    reg [2*width-1:0] tempSum = 0;
    reg [2*width:0] fullSum = 0;
    reg [width-1:0] multicand_bar = 0;
   
    always@( state, done, Start, RESET ) begin : IDLE_PROCESS  
		// Note : This block uses non-blocking assignments to get around an unpredictable Verilog simulation behaviour.
        // default outputs
        Busy <= 1'b0 ;
        n_state <= IDLE ;
        
        // reset
        if(~RESET)
            case(state)
                IDLE: begin
                    if(Start) begin // note: a mealy machine, since output depends on current state (IDLE) & input (Start)
                        n_state <= COMPUTING ;
                        Busy <= 1'b1 ;
                    end
                end
                COMPUTING: begin
                    if(~done) begin
                        n_state <= COMPUTING ;
                        Busy <= 1'b1 ;
                    end
                end        
            endcase    
    end


    always@( posedge CLK ) begin : STATE_UPDATE_PROCESS // state updating
        state <= n_state ;    
    end

    
    always@( posedge CLK ) begin : COMPUTING_PROCESS // process which does the actual computation
        // n_state == COMPUTING and state == IDLE implies we are just transitioning into COMPUTING
        if( RESET | (n_state == COMPUTING & state == IDLE) ) begin // 2nd condition is true during the very 1st clock cycle of the multiplication
            count = 0 ;
            temp_sum = 0 ;
            if (~MCycleOp[0]) begin //signed variables
                if(Operand1[width-1])begin
                    positiveOperand1 = ~Operand1 + 1'b1;         //convert to positive    
                    shifted_op1 = { {width{1'b0}}, positiveOperand1 } ;
                end
                else begin
                    shifted_op1 = { {width{1'b0}}, Operand1 } ;
                end
                if(Operand2[width-1])begin
                    positiveOperand2 = ~Operand2 + 1'b1;             //convert to positive
                    shifted_op2 = { {width{1'b0}}, positiveOperand2 } ;
                    shifted_op2D = { positiveOperand2, {width{1'b0}}} ; //padding 'width'
                    
                end
                else begin
                    shifted_op2 = { {width{1'b0}}, Operand2 } ;
                    shifted_op2D = { Operand2, {width{1'b0}}} ; //padding 'width'
                end
            end
            else if(MCycleOp[0])begin //variables for unsigned
                    shifted_op1 = { {width{~MCycleOp[0] & Operand1[width-1]}}, Operand1 } ; // sign extend the operands, both dividend and multiplicand are pad left shift left.
                    shifted_op2 = { {width{~MCycleOp[0] & Operand2[width-1]}}, Operand2 } ; //sign extend the multipler as well
                    shifted_op2D = { Operand2, {width{~MCycleOp[0] & Operand2[width-1]}}} ; //padding 'width'
                    if (~MCycleOp[1]) begin
                        shifted_op1 = {1'b0, shifted_op1};
                    end
                    pad_shifted_op2D = { 1'b0, shifted_op2D} ;
                    pad_shifted_op1 = { 1'b0, shifted_op1} ;
            end
//            else begin
//                shifted_op1 = { {width{~MCycleOp[0] & Operand1[width-1]}}, Operand1 } ; // sign extend the operands, both dividend and multiplicand are pad left shift left.
//                shifted_op2 = { {width{~MCycleOp[0] & Operand2[width-1]}}, Operand2 } ; //sign extend the multipler as well
                
//            end
            
        end ;
        done <= 1'b0 ;   
        
        if( ~MCycleOp[1] ) begin // Multiply
            if(MCycleOp[0])begin
             //if( ~MCycleOp[0] ), takes 2*'width' cycles to execute, returns signed(Operand1)*signed(Operand2)
             //if( MCycleOp[0] ), takes 'width' cycles to execute, returns unsigned(Operand1)*unsigned(Operand2)        
                if( shifted_op2[0] ) // add only if b0 = 1
                    temp_sum = temp_sum + shifted_op1 ; // partial product for multiplication
                    
                shifted_op2 = {1'b0, shifted_op2[2*width-1 : 1]} ; //multipler shift right
                shifted_op1 = {shifted_op1[2*width-2 : 0], 1'b0} ;    //multiplicand shift left
                    
                if(count == width-1) begin// last cycle?
                    if (Operand1[width-1:0] ^ Operand2[width-1:0])begin
                        temp_sum = ~temp_sum + 1;
                    end
                    done <= 1'b1 ;   
                end
                   
                count = count + 1;    
            end
            else begin
            //Booths algo for signed mul, initialize variables
                if (count == 0)begin
                    multicand_bar = ~shifted_op1[width-1:0] + 1;  
                    fullSum[width:1] = shifted_op2[width-1:0]; //set the multipler
                end
                else begin
                 
                    case(fullSum[1:0])
                        2'b01:
                            begin
                                fullSum[2*width:width+1] = fullSum[2*width:width+1] + shifted_op1[width-1:0]; //A < A + M
                                fullSum[2*width:0] = {fullSum[2*width], fullSum[2*width:1]}; //ASR
                            end
                        2'b10:
                            begin 
                                fullSum[2*width:width+1] = fullSum[2*width:width+1] + multicand_bar; //A < A - M
                                fullSum[2*width:0] = {fullSum[2*width], fullSum[2*width:1]}; //ASR
                            end
                        
                        default:
                            begin
                                fullSum[2*width:0] = {fullSum[2*width], fullSum[2*width:1]}; //ASR
                            end
                    endcase
               
                end
                
                if(count == width)begin 
                    if (Operand1[width-1:0] ^ Operand2[width-1:0]) //check if the signs are opposite
                    begin
                        fullSum[2*width:1] = ~fullSum[2*width:1] + 1;
                    end
                    temp_sum[2*width-1:width] = fullSum[2*width:width+1]; 
                    temp_sum[width-1:0] = fullSum[width:1];
                    done <= 1'b1 ;
                  end
                count = count + 1 ;
            end
        end 
        else begin // Supposed to be Divide. The dummy code below takes 1 cycle to execute, just returns the operands. Change this to signed [ if(~MCycleOp[0]) ] and unsigned [ if(MCycleOp[0]) ] division.
            if (MCycleOp[0]) begin //unsigned division
               pad_shifted_op1 = pad_shifted_op1 - pad_shifted_op2D; //remainder - divisor
               if (~pad_shifted_op1[2*width]) begin
                    quotient = { quotient[width-2:0], 1'b1 }; //shift the quotient to the left, remainder >= 0
               end
               else begin
                    pad_shifted_op1 = pad_shifted_op1 + pad_shifted_op2D; //restorative division for remainder < 0
                    quotient = { quotient[width-2:0], 1'b0 };
               end
               pad_shifted_op2D = { 1'b0, pad_shifted_op2D[2*width:1] }; //right shift one divisor
               if( count == width ) //last cycle?
                    done <= 1'b1; 
                    
               count = count + 1;
            end
            else if (~MCycleOp[0]) begin //signed division

               shifted_op1 = shifted_op1 - shifted_op2D ; //remainder - divisor
               if (~shifted_op1[2*width - 1]) begin
                    quotient = { quotient[width-1:0], 1'b1 }; //shift the quotient to the left, remainder >= 0
               end
               else begin
                    shifted_op1 = shifted_op1 + shifted_op2D; //restorative division for remainder < 0
                    quotient = { quotient[width-1:0], 1'b0 };
               end
               shifted_op2D = { 1'b0, shifted_op2D[2*width-1:1] }; //right shift one divisor
                
               if( count == width ) begin//last cycle?
                    if (Operand1[width-1:0] ^ Operand2[width-1:0])begin //if both signs are different, negate
                        quotient = ~quotient + 1'b1;
                    end
                    done <= 1'b1;
                end
                    
                count = count + 1;  
            end
                    
        end ;
        if (~MCycleOp[1]) begin //multiply
            Result2 <= temp_sum[2*width-1 : width] ;
            Result1 <= temp_sum[width-1 : 0] ;
        end
        else begin
            if(MCycleOp[0])begin // unsigned div
                Result1 <= quotient;
                Result2 <= pad_shifted_op1[width-1 : 0];
            end
            else begin 
                Result1 <= quotient;
                Result2 <= shifted_op1[width-1 : 0];
            end
        end
    end
   
endmodule

















