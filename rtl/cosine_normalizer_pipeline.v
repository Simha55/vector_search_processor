// Fully spatial fixed-point normalizer: 64 sqrt stages + 126 divide stages.
// Accepts one tagged sum tuple per cycle when ready. Global backpressure freezes
// every stage, including payload and metadata. Resource cost is intentionally
// much greater than the previous single iterative normalizer.
module cosine_normalizer_pipeline (
    input wire clk, reset,
    input wire input_valid,
    output wire input_ready,
    input wire signed [63:0] dot_sum,
    input wire [31:0] query_norm, database_norm, input_id,
    output wire output_valid,
    input wire output_ready,
    output wire signed [31:0] score,
    output wire zero_norm,
    output wire [31:0] output_id,
    output reg [31:0] inflight
);
    localparam integer STAGES=190;
    reg [STAGES:0] valid, negative, zero;
    reg [31:0] tags [0:STAGES];
    wire advance=!valid[STAGES] || output_ready;
    wire [63:0] product={32'd0,query_norm}*{32'd0,database_norm};
    wire [63:0] magnitude=dot_sum[63] ? ~dot_sum+64'd1 : dot_sum;
    wire [127:0] rad [0:64];
    wire [129:0] rem [0:64];
    wire [63:0] root [0:64];
    wire [125:0] numerator [0:64];
    reg [127:0] rad0;
    reg [125:0] num0;
    assign rad[0]=rad0; assign rem[0]=0; assign root[0]=0; assign numerator[0]=num0;
    assign input_ready=!reset && advance;
    assign output_valid=!reset && valid[STAGES];
    assign zero_norm=output_valid && zero[STAGES];
    assign output_id=output_valid ? tags[STAGES] : 32'd0;
    integer k;
    always @(posedge clk) begin
        if(reset) begin valid<=0; negative<=0; zero<=0; inflight<=0; end
        else begin
            if(advance) begin
                valid[0]<=input_valid;
                negative[0]<=dot_sum[63];
                zero[0]<=query_norm==0 || database_norm==0;
                tags[0]<=input_id;
                rad0<={product,64'd0}; num0<={magnitude,62'd0};
                for(k=1;k<=STAGES;k=k+1) begin
                    valid[k]<=valid[k-1]; negative[k]<=negative[k-1]; zero[k]<=zero[k-1]; tags[k]<=tags[k-1];
                end
            end
            case({input_valid && input_ready,output_valid && output_ready})
                2'b10: inflight<=inflight+1;
                2'b01: inflight<=inflight-1;
                default: inflight<=inflight;
            endcase
        end
    end
    genvar s;
    generate
        for(s=0;s<64;s=s+1) begin: sqrt_stage
            reg [127:0] r;
            reg [129:0] m;
            reg [63:0] q;
            reg [125:0] n;
            wire [129:0] shifted=(rem[s]<<2)|{128'd0,rad[s][127:126]};
            wire [129:0] trial=({66'd0,root[s]}<<2)|130'd1;
            wire subtract=shifted>=trial;
            always @(posedge clk) if(advance) begin
                r<=rad[s]<<2; m<=subtract ? shifted-trial : shifted;
                q<=(root[s]<<1)|{63'd0,subtract}; n<=numerator[s];
            end
            assign rad[s+1]=r; assign rem[s+1]=m;
            assign root[s+1]=q; assign numerator[s+1]=n;
        end
    endgenerate
    wire [125:0] div_num [0:126];
    wire [125:0] quotient [0:126];
    wire [126:0] remainder [0:126];
    wire [63:0] denominator [0:126];
    assign div_num[0]=numerator[64]; assign quotient[0]=0; assign remainder[0]=0;
    // Zero norm payloads still traverse the same pipeline without division by zero.
    assign denominator[0]=root[64]==0 ? 64'd1 : root[64];
    generate
        for(s=0;s<126;s=s+1) begin: divide_stage
            reg [125:0] n,q;
            reg [126:0] r;
            reg [63:0] d;
            wire [126:0] shifted=(remainder[s]<<1)|{126'd0,div_num[s][125]};
            wire subtract=shifted>={63'd0,denominator[s]};
            always @(posedge clk) if(advance) begin
                n<=div_num[s]<<1; q<=(quotient[s]<<1)|{125'd0,subtract};
                r<=subtract ? shifted-{63'd0,denominator[s]} : shifted; d<=denominator[s];
            end
            assign div_num[s+1]=n; assign quotient[s+1]=q;
            assign remainder[s+1]=r; assign denominator[s+1]=d;
        end
    endgenerate
    wire [31:0] magnitude_score=quotient[126]>=(126'd1<<30) ? 32'd1073741824 : quotient[126][31:0];
    assign score=(!output_valid || zero[STAGES]) ? 32'sd0 :
                 (negative[STAGES] ? -$signed(magnitude_score) : $signed(magnitude_score));
endmodule
