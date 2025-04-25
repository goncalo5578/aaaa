//
// ariane_regfile_uve.sv
//
// Adaptação do ariane_regfile para suportar registos da UVE:
//   - 32 registos vetoriais (u0..u31), cada um com largura parametrizável
//   - 16 registos de predicado (p0..p15), com largura menor ou igual 
//     (depende da forma de implementação de predicados).
//   - p0 fixo em '1 (hardwired)
//

module ariane_regfile_uve #(
    // Mantemos a compatibilidade com a estrutura do Ariane/CVA6
    parameter config_pkg::cva6_cfg_t CVA6Cfg           = config_pkg::cva6_cfg_empty,

    // Largura de cada REGISTRO VETORIAL, ex: 128, 256, 512...
    parameter int unsigned           VEC_DATA_WIDTH    = 128,

    // Largura de cada REGISTRO DE PREDICADO, ex: 64 (ou poderia ser 1 bit/“lane”).
    // Ajuste conforme sua necessidade ou use outro design p/ p regs.
    parameter int unsigned           PRED_DATA_WIDTH   = 64,

    // Número de portas de leitura para vetores e predicados, se quiser adaptável
    parameter int unsigned           NR_VEC_READ_PORTS = 2,
    parameter int unsigned           NR_PRED_READ_PORTS= 1,

    // Se p0 é hardwired em 1 e não pode ser sobrescrito
    parameter bit                    P0_HARDWIRED      = 1
) (
    // clock e reset
    input  logic                                              clk_i,
    input  logic                                              rst_ni,
    // disable clock gates for testing
    input  logic                                              test_en_i,

    // -----------------------------------------------------------
    //  Sinais de LEITURA dos registos VETORIAIS
    // -----------------------------------------------------------
    input  logic [NR_VEC_READ_PORTS-1:0][4:0]                 v_raddr_i,
    output logic [NR_VEC_READ_PORTS-1:0][VEC_DATA_WIDTH-1:0]  v_rdata_o,

    // -----------------------------------------------------------
    //  Sinais de LEITURA dos registos de PREDICADO
    // -----------------------------------------------------------
    input  logic [NR_PRED_READ_PORTS-1:0][3:0]                p_raddr_i,
    output logic [NR_PRED_READ_PORTS-1:0][PRED_DATA_WIDTH-1:0] p_rdata_o,

    // -----------------------------------------------------------
    //  Sinais de ESCRITA dos registos VETORIAIS
    // -----------------------------------------------------------
    input  logic [CVA6Cfg.NrCommitPorts-1:0][4:0]             v_waddr_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0][VEC_DATA_WIDTH-1:0] v_wdata_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0]                  v_we_i,

    // -----------------------------------------------------------
    //  Sinais de ESCRITA dos registos de PREDICADO
    // -----------------------------------------------------------
    input  logic [CVA6Cfg.NrCommitPorts-1:0][3:0]             p_waddr_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0][PRED_DATA_WIDTH-1:0] p_wdata_i,
    input  logic [CVA6Cfg.NrCommitPorts-1:0]                  p_we_i
);

  // -----------------------------------------------------------
  // Definições de quantos registos temos
  // -----------------------------------------------------------
  localparam int unsigned NUM_VREGS  = 32; // u0..u31
  localparam int unsigned NUM_PREGS  = 16; // p0..p15

  // Memória para registrar VETORIAIS
  logic [NUM_VREGS-1:0][VEC_DATA_WIDTH-1:0] vec_mem;

  // Memória para registos de PREDICADO
  logic [NUM_PREGS-1:0][PRED_DATA_WIDTH-1:0] pred_mem;

  // Precisamos de decodificadores de escrita:
  logic [CVA6Cfg.NrCommitPorts-1:0][NUM_VREGS-1:0] v_we_dec;
  logic [CVA6Cfg.NrCommitPorts-1:0][NUM_PREGS-1:0] p_we_dec;

  // ----------------------------------------------------------------------
  // DECODER de escrita p/ VETORIAIS
  // ----------------------------------------------------------------------
  always_comb begin : v_we_decoder
    for (int unsigned j = 0; j < CVA6Cfg.NrCommitPorts; j++) begin
      for (int unsigned i = 0; i < NUM_VREGS; i++) begin
        if (v_waddr_i[j] == i) v_we_dec[j][i] = v_we_i[j];
        else                   v_we_dec[j][i] = 1'b0;
      end
    end
  end

  // ----------------------------------------------------------------------
  // DECODER de escrita p/ PREDICADOS
  // ----------------------------------------------------------------------
  always_comb begin : p_we_decoder
    for (int unsigned j = 0; j < CVA6Cfg.NrCommitPorts; j++) begin
      for (int unsigned i = 0; i < NUM_PREGS; i++) begin
        if (p_waddr_i[j] == i) p_we_dec[j][i] = p_we_i[j];
        else                   p_we_dec[j][i] = 1'b0;
      end
    end
  end

  // ----------------------------------------------------------------------
  // Escrita SÍNCRONA nos registos
  // ----------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin : register_write_behavioral
    if (~rst_ni) begin
      // Zera vetor
      vec_mem  <= '{default: '0};
      // Zera predicados
      pred_mem <= '{default: '0};

      // Se quiser p0 = '1 no reset, pode forçar aqui
      if (P0_HARDWIRED) begin
        pred_mem[0] <= '1; 
      end

    end else begin
      // ======================================================
      // VETORES
      // ======================================================
      for (int unsigned j = 0; j < CVA6Cfg.NrCommitPorts; j++) begin
        for (int unsigned i = 0; i < NUM_VREGS; i++) begin
          if (v_we_dec[j][i]) begin
            vec_mem[i] <= v_wdata_i[j];
          end
        end
      end

      // ======================================================
      // PREDICADOS
      // ======================================================
      for (int unsigned j = 0; j < CVA6Cfg.NrCommitPorts; j++) begin
        for (int unsigned i = 0; i < NUM_PREGS; i++) begin
          // Se p0 é hardwired, não escrevemos caso i==0
          if (p_we_dec[j][i]) begin
            if (P0_HARDWIRED && (i == 0)) begin
              // ignora escrita em p0
            end else begin
              pred_mem[i] <= p_wdata_i[j];
            end
          end
        end
      end

      if (P0_HARDWIRED) begin
        pred_mem[0] <= '1;
      end
    end
  end

  // ----------------------------------------------------------------------
  // LEITURAS COMBINACIONAIS
  // ----------------------------------------------------------------------
  // Vetoriais
  for (genvar rv = 0; rv < NR_VEC_READ_PORTS; rv++) begin : gen_vec_read
    assign v_rdata_o[rv] = vec_mem[v_raddr_i[rv]];
  end

  // Predicados
  for (genvar rp = 0; rp < NR_PRED_READ_PORTS; rp++) begin : gen_pred_read
    assign p_rdata_o[rp] = pred_mem[p_raddr_i[rp]];
  end

endmodule
