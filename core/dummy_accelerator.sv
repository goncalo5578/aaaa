module dummy_accelerator
  import acc_pkg::*;
  import riscv::*;
(
    input  logic             clk_i,
    input  logic             rst_ni,

    // Pedido do dispatcher
    input  accelerator_req_t acc_req_i,
    // Resposta ao dispatcher
    output accelerator_resp_t acc_resp_o
);

  // ---------------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------------
  typedef enum logic [0:0] {IDLE, RESP} state_e;
  state_e state_d, state_q;

  // Registro de resposta (tudo o que o dispatcher lê)
  accelerator_resp_t resp_d, resp_q;

  // Saída direta
  assign acc_resp_o = resp_q;

  // Função de utilidade para manipular o bit req_ready
  function automatic accelerator_resp_t set_ready(input accelerator_resp_t r, input logic ready);
    accelerator_resp_t t = r;
    t.req_ready = ready;
    return t;
  endfunction

  // ---------------------------------------------------------------------------
  // Lógica Combinacional
  // ---------------------------------------------------------------------------
  always_comb begin
    // Handshake locais – DEVEM vir antes de qualquer statement!
    logic req_fire;
    logic resp_fire;

    // Defaults
    resp_d  = resp_q;
    state_d = state_q;

    // Sinalizamos disponibilidade para novo pedido somente em IDLE
    resp_d = set_ready(resp_d, (state_q == IDLE));

    // Calcula handshakes
    req_fire  = acc_req_i.req_valid && resp_d.req_ready;     // pedido aceite
    resp_fire = resp_q.resp_valid   && acc_req_i.resp_ready; // resposta aceite

    case (state_q)
      // ---------------------------------------------------------------------
      IDLE: begin
        resp_d.resp_valid = 1'b0; // nada para devolver ainda

        if (req_fire) begin
          // Prepara resposta (2 × rs1) para o próximo ciclo
          resp_d.result         = acc_req_i.rs1 + acc_req_i.rs1; // 2×rs1
          resp_d.trans_id       = acc_req_i.trans_id;
          resp_d.error          = 1'b0;
          resp_d.fflags_valid   = 1'b0;
          resp_d.load_complete  = 1'b0;
          resp_d.store_complete = 1'b0;
          resp_d.inval_valid    = 1'b0;
          resp_d.resp_valid     = 1'b0; // ficará 1 no estado RESP

          state_d = RESP;
        end
      end

      // ---------------------------------------------------------------------
      RESP: begin
        resp_d.resp_valid = 1'b1; // resposta pronta

        if (resp_fire) begin
          resp_d.resp_valid = 1'b0; // limpa para o próximo ciclo
          state_d           = IDLE;
        end
      end

      default: state_d = IDLE;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Registos Sequenciais
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      resp_q  <= '0;
    end else begin
      state_q <= state_d;
      resp_q  <= resp_d;
    end
  end

endmodule : dummy_accelerator
