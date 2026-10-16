// Sorted running top-K, descending signed score then ascending unsigned ID.
module cosine_topk #(parameter integer K=5) (
    input wire clk, reset, clear, candidate_valid,
    input wire signed [31:0] candidate_score,
    input wire [31:0] candidate_id,
    input wire [31:0] read_rank,
    output reg [31:0] count,
    output wire signed [31:0] read_score,
    output wire [31:0] read_id
);
    reg signed [31:0] scores [0:K-1];
    reg [31:0] ids [0:K-1];
    reg signed [31:0] next_scores [0:K-1];
    reg [31:0] next_ids [0:K-1];
    integer i, position;
    assign read_score=read_rank<count ? scores[read_rank] : 32'sd0;
    assign read_id=read_rank<count ? ids[read_rank] : 32'd0;
    always @* begin
        position=K;
        for(i=0;i<K;i=i+1) begin
            next_scores[i]=scores[i]; next_ids[i]=ids[i];
            if(position==K && (i>=count || candidate_score>scores[i] ||
               (candidate_score==scores[i] && candidate_id<ids[i]))) position=i;
        end
        for(i=K-1;i>0;i=i-1)
            if(i>position) begin next_scores[i]=scores[i-1]; next_ids[i]=ids[i-1]; end
        if(position<K) begin next_scores[position]=candidate_score; next_ids[position]=candidate_id; end
    end
    integer j;
    always @(posedge clk) begin
        if(reset || clear) begin
            count<=0;
            for(j=0;j<K;j=j+1) begin scores[j]<=0; ids[j]<=0; end
        end else if(candidate_valid) begin
            if(count<K) count<=count+1;
            for(j=0;j<K;j=j+1) begin scores[j]<=next_scores[j]; ids[j]<=next_ids[j]; end
        end
    end
endmodule
