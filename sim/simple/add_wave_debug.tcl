add wave -group "Test Bench" /cellrv32_tb_simple/*

add wave -group "Top Module" /cellrv32_tb_simple/cellrv32_top_inst/*

add wave -group "Top Module" /cellrv32_tb_simple/cellrv32_top_inst/resp_bus

#create top-level CPU
add wave -group "CPU" -group "Cpu Control" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_control_inst/*
 
add wave -group "CPU" -group "Cpu Control" -group "Cpu Control Decompressor" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_control_inst/cellrv32_cpu_decompressor_inst_true/cellrv32_cpu_decompressor_inst/*

add wave -group "CPU" -group "Cpu Regfile" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/*

add wave -group "CPU" -group "Cpu Regfile" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file

add wave -group "CPU" -group "Cpu Regfile" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file_emb

add wave -group "CPU" -group "Cpu Alu" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_alu_inst/*

add wave -group "CPU" -group "Cpu Bus" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_bus_inst/*

#create top-level ICACHE
add wave -group "Icache" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_icache_inst_ON/cellrv32_icache_inst/*

add wave -group "Bus Switch" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_busswitch_inst/*

add wave -group "SDI" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/*

add wave -group "Tx_fifo" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/tx_fifo_inst/*

add wave -group "Rx_fifo" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/rx_fifo_inst/*

add wave -group "SPI" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_spi_inst_ON/cellrv32_spi_inst/*

add wave -group "XIRQ" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_xirq_inst_ON/cellrv32_xirq_inst/*

add wave -group "Sysinfo" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_sysinfo_inst/*

add wave -group "Bus Switch" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_busswitch_inst/*

add wave -group "Icahe" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_icache_inst_ON/cellrv32_icache_inst/*

add wave -group "Imem" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_imem_inst_ON/cellrv32_int_imem_inst/*

add wave -group "Dmem" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/*
