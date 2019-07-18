//        Copyright 2019 NaplesPU
//   
//   	 
//   Redistribution and use in source and binary forms, with or without modification,
//   are permitted provided that the following conditions are met:
//   
//   1. Redistributions of source code must retain the above copyright notice,
//      this list of conditions and the following disclaimer.
//   
//   2. Redistributions in binary form must reproduce the above copyright notice,
//      this list of conditions and the following disclaimer in the documentation
//      and/or other materials provided with the distribution.
//   
//   3. Neither the name of the copyright holder nor the names of its contributors
//      may be used to endorse or promote products derived from this software
//      without specific prior written permission.
//   
//      
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//   IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//   BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//   OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
//   OF THE POSSIBILITY OF SUCH DAMAGE.

`timescale 1ns / 1ps

module round_robin_arbiter #(
     parameter SIZE = 6
  )(
     input                   clk,
     input                   reset,
     input                   en,
     input[SIZE-1:0]         requests,
     output logic[SIZE-1:0]  decision_oh
  );

    logic [SIZE-1:0] highestPriority_oh, highestPriority_next;

    always_comb begin
        int ppos;
        for( int i=0; i<SIZE; i++) begin       // generates a combinatorial function for each output bit
            decision_oh[i] = 1'b0;             // should be a "don't care" in inconsistent cases (note: the "highestPriority" register is kept in one-hot form). However, for some reason Vivado doesn't like that (higher synthesis time and worse area)
            for( int j=0; j<SIZE; j++) begin   // iterates on priority values: scan the "highestPriority" array from the i-th position backwards (in a cyclic fashion)
                ppos = (i-j+SIZE) % SIZE;  // absolute position of the priority bit we are considering
                if (highestPriority_oh[ppos]) begin
                    logic granted;
                    granted = requests[i];
                    for( int k=ppos; (k%SIZE)!=i; k++) if (requests[k%SIZE]) granted&=1'b0;
                    decision_oh[i] = granted;
                    break;                     // Note: remaining cases should be "don't care"
                end
            end
        end
        for( int i=0; i<SIZE; i++) highestPriority_next[(i+1)%SIZE] = decision_oh[i];  // granted line will become lowest priority in the next cycle
    end
    
    always_ff @(posedge clk, posedge reset)
    begin
        if (reset)
            highestPriority_oh <= 1;  // initialize the arbiter with highest priority given to the least significant position
        else if ( en && (requests!=0) )
            highestPriority_oh <= highestPriority_next;
    end
    
endmodule
