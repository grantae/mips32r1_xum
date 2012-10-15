`timescale 1ns / 1ps
/*
 * File         : ALU.v
 * Project      : University of Utah, XUM Project MIPS32 core
 * Creator(s)   : Grant Ayers (ayers@cs.utah.edu)
 *
 * Modification History:
 *   Rev   Date         Initials  Description of Change
 *   1.0   7-Jun-2011   GEA       Initial design.
 *   2.0   26-Jul-2012  GEA       Many changes have been made.
 *
 * Standards/Formatting:
 *   Verilog 2001, 4 soft tab, wide column.
 *
 * Description:
 *   An Arithmetic Logic Unit for a MIPS32 processor. This module computes all
 *   arithmetic operations, including the following:
 *
 *   Add, Subtract, Multiply, And, Or, Nor, Xor, Shift, Count leading 1s/0s.
 */
module ALU(
    input  clock,
    input  reset,
    input  EX_Stall,
    input  EX_Flush,
    input  [31:0] A, B,
    input  [4:0]  Operation,
    input  signed [4:0] Shamt,
    output reg signed [31:0] Result,
    output BZero,  // Used for Movc
    output reg EXC_Ov
    );

    `include "MIPS_Parameters.v"
    
    /***
     Performance Notes:
     
     The ALU is the longest delay path in the Execute stage, and one of the longest
     in the entire processor. This path varies based on the logic blocks that are
     chosen to implement various functions, but there is certainly room to improve
     the speed of arithmetic operations. The ALU could also be placed in a separate
     pipeline stage after the Execute forwarding has completed.
    ***/
    
    wire signed [31:0] As = A;
    wire signed [31:0] Bs = B;
    
    reg  [63:0] HILO;
    wire [31:0] HI = HILO[63:32];
    wire [31:0] LO = HILO[31:0];
    wire HILO_Commit = ~(EX_Stall | EX_Flush);
    
    wire AddSub_Add = ((Operation == AluOp_Add) | (Operation == AluOp_Addu));
    wire signed [31:0] AddSub_Result = (AddSub_Add) ? (A + B) : (A - B);
    
    wire signed [63:0] Mult_Result = As * Bs;
    wire [63:0] Multu_Result = A * B;
    
    reg  [5:0] CLO_Result, CLZ_Result;
    
    assign BZero = (B == 32'h00000000);
    
    always @(*) begin
        case (Operation)
            AluOp_Add   : Result <= AddSub_Result;
            AluOp_Addu  : Result <= AddSub_Result;
            AluOp_And   : Result <= A & B;
            AluOp_Clo   : Result <= {26'b0, CLO_Result};
            AluOp_Clz   : Result <= {26'b0, CLZ_Result};
            AluOp_Div   : Result <= 32'hdeafbeef;   // XXX implement division
            AluOp_Divu  : Result <= 32'hdeadbeef;   // XXX implement division
            AluOp_Mfhi  : Result <= HI;
            AluOp_Mflo  : Result <= LO;
            AluOp_Mul   : Result <= Mult_Result[31:0];
            AluOp_Nor   : Result <= ~(A | B);
            AluOp_Or    : Result <= A | B;
            AluOp_Sll   : Result <= B << Shamt;
            AluOp_Sllc  : Result <= {B[15:0], 16'b0};
            AluOp_Sllv  : Result <= B << A[4:0];
            AluOp_Slt   : Result <= (As < Bs) ? 32'h00000001 : 32'h00000000;
            AluOp_Sltu  : Result <= (A < B)   ? 32'h00000001 : 32'h00000000;
            AluOp_Sra   : Result <= Bs >>> Shamt;
            AluOp_Srav  : Result <= Bs >>> As[4:0];
            AluOp_Srl   : Result <= B >> Shamt;
            AluOp_Srlv  : Result <= B >> A[4:0];
            AluOp_Sub   : Result <= AddSub_Result;
            AluOp_Subu  : Result <= AddSub_Result;
            AluOp_Xor   : Result <= A ^ B;
            default     : Result <= 32'bx;
        endcase
    end
    
    
    always @(posedge clock) begin
        if (reset) begin
            HILO <= 64'h00000000_00000000;
        end
        else if (HILO_Commit) begin
            case (Operation)
                AluOp_Mult  : HILO <= Mult_Result;
                AluOp_Multu : HILO <= Multu_Result;
                AluOp_Madd  : HILO <= HILO + Mult_Result;
                AluOp_Maddu : HILO <= HILO + Multu_Result;
                AluOp_Msub  : HILO <= HILO - Mult_Result;
                AluOp_Msubu : HILO <= HILO - Multu_Result;
                AluOp_Mthi  : HILO <= {A, LO};
                AluOp_Mtlo  : HILO <= {HI, B};
                default     : HILO <= HILO;
            endcase
        end
        else begin
            HILO <= HILO;
        end
    end
    
    // Detect overflow for signed operations. Note that MIPS32 has no overflow
    // detection for multiplication/division operations.
    always @(*) begin
        case (Operation)
            AluOp_Add : EXC_Ov <= ((A[31] ~^ B[31]) & (A[31] ^ AddSub_Result[31]));
            AluOp_Sub : EXC_Ov <= ((A[31]  ^ B[31]) & (A[31] ^ AddSub_Result[31]));
            default   : EXC_Ov <= 0;
        endcase
    end
    
    
    // Count Leading Ones
    always @(A) begin
        casex (A)
            32'b0xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd0;
            32'b10xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd1;
            32'b110x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd2;
            32'b1110_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd3;
            32'b1111_0xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd4;
            32'b1111_10xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd5;
            32'b1111_110x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd6;
            32'b1111_1110_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd7;
            32'b1111_1111_0xxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd8;
            32'b1111_1111_10xx_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd9;
            32'b1111_1111_110x_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd10;
            32'b1111_1111_1110_xxxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd11;
            32'b1111_1111_1111_0xxx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd12;
            32'b1111_1111_1111_10xx_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd13;
            32'b1111_1111_1111_110x_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd14;
            32'b1111_1111_1111_1110_xxxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd15;
            32'b1111_1111_1111_1111_0xxx_xxxx_xxxx_xxxx : CLO_Result <= 6'd16;
            32'b1111_1111_1111_1111_10xx_xxxx_xxxx_xxxx : CLO_Result <= 6'd17;
            32'b1111_1111_1111_1111_110x_xxxx_xxxx_xxxx : CLO_Result <= 6'd18;
            32'b1111_1111_1111_1111_1110_xxxx_xxxx_xxxx : CLO_Result <= 6'd19;
            32'b1111_1111_1111_1111_1111_0xxx_xxxx_xxxx : CLO_Result <= 6'd20;
            32'b1111_1111_1111_1111_1111_10xx_xxxx_xxxx : CLO_Result <= 6'd21;
            32'b1111_1111_1111_1111_1111_110x_xxxx_xxxx : CLO_Result <= 6'd22;
            32'b1111_1111_1111_1111_1111_1110_xxxx_xxxx : CLO_Result <= 6'd23;
            32'b1111_1111_1111_1111_1111_1111_0xxx_xxxx : CLO_Result <= 6'd24;
            32'b1111_1111_1111_1111_1111_1111_10xx_xxxx : CLO_Result <= 6'd25;
            32'b1111_1111_1111_1111_1111_1111_110x_xxxx : CLO_Result <= 6'd26;
            32'b1111_1111_1111_1111_1111_1111_1110_xxxx : CLO_Result <= 6'd27;
            32'b1111_1111_1111_1111_1111_1111_1111_0xxx : CLO_Result <= 6'd28;
            32'b1111_1111_1111_1111_1111_1111_1111_10xx : CLO_Result <= 6'd29;
            32'b1111_1111_1111_1111_1111_1111_1111_110x : CLO_Result <= 6'd30;
            32'b1111_1111_1111_1111_1111_1111_1111_1110 : CLO_Result <= 6'd31;
            32'b1111_1111_1111_1111_1111_1111_1111_1111 : CLO_Result <= 6'd32;
            default : CLO_Result <= 6'd0;
        endcase
    end

    // Count Leading Zeros
    always @(A) begin
        casex (A)
            32'b1xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd0;
            32'b01xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd1;
            32'b001x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd2;
            32'b0001_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd3;
            32'b0000_1xxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd4;
            32'b0000_01xx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd5;
            32'b0000_001x_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd6;
            32'b0000_0001_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd7;
            32'b0000_0000_1xxx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd8;
            32'b0000_0000_01xx_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd9;
            32'b0000_0000_001x_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd10;
            32'b0000_0000_0001_xxxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd11;
            32'b0000_0000_0000_1xxx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd12;
            32'b0000_0000_0000_01xx_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd13;
            32'b0000_0000_0000_001x_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd14;
            32'b0000_0000_0000_0001_xxxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd15;
            32'b0000_0000_0000_0000_1xxx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd16;
            32'b0000_0000_0000_0000_01xx_xxxx_xxxx_xxxx : CLZ_Result <= 6'd17;
            32'b0000_0000_0000_0000_001x_xxxx_xxxx_xxxx : CLZ_Result <= 6'd18;
            32'b0000_0000_0000_0000_0001_xxxx_xxxx_xxxx : CLZ_Result <= 6'd19;
            32'b0000_0000_0000_0000_0000_1xxx_xxxx_xxxx : CLZ_Result <= 6'd20;
            32'b0000_0000_0000_0000_0000_01xx_xxxx_xxxx : CLZ_Result <= 6'd21;
            32'b0000_0000_0000_0000_0000_001x_xxxx_xxxx : CLZ_Result <= 6'd22;
            32'b0000_0000_0000_0000_0000_0001_xxxx_xxxx : CLZ_Result <= 6'd23;
            32'b0000_0000_0000_0000_0000_0000_1xxx_xxxx : CLZ_Result <= 6'd24;
            32'b0000_0000_0000_0000_0000_0000_01xx_xxxx : CLZ_Result <= 6'd25;
            32'b0000_0000_0000_0000_0000_0000_001x_xxxx : CLZ_Result <= 6'd26;
            32'b0000_0000_0000_0000_0000_0000_0001_xxxx : CLZ_Result <= 6'd27;
            32'b0000_0000_0000_0000_0000_0000_0000_1xxx : CLZ_Result <= 6'd28;
            32'b0000_0000_0000_0000_0000_0000_0000_01xx : CLZ_Result <= 6'd29;
            32'b0000_0000_0000_0000_0000_0000_0000_001x : CLZ_Result <= 6'd30;
            32'b0000_0000_0000_0000_0000_0000_0000_0001 : CLZ_Result <= 6'd31;
            32'b0000_0000_0000_0000_0000_0000_0000_0000 : CLZ_Result <= 6'd32;
            default : CLZ_Result <= 6'd0;
        endcase
    end

endmodule

