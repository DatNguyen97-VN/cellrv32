add wave -group "Test Bench" /neorv32_tb_simple/*

add wave -group "Top Module" /neorv32_tb_simple/cellrv32_top_inst/*

add wave -group "Top Module" /neorv32_tb_simple/cellrv32_top_inst/resp_bus

add wave -group "Cpu Control" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_control_inst/*

add wave -group "Cpu Bus" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_bus_inst/*
 
add wave -group "Cpu Decompressor" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_control_inst/cellrv32_cpu_decompressor_inst_true/cellrv32_cpu_decompressor_inst/*

add wave -group "Cpu Alu" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_alu_inst/*

add wave -group "Cpu Regfile" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/*

add wave -group "Cpu Regfile" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file

add wave -group "Cpu Regfile" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file_emb

add wave -group "Bus Switch" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_busswitch_inst/*

add wave -group "SDI" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/*

add wave -group "Tx_fifo" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/tx_fifo_inst/*

add wave -group "Rx_fifo" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_sdi_inst_ON/cellrv32_sdi_inst/rx_fifo_inst/*

add wave -group "SPI" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_spi_inst_ON/cellrv32_spi_inst/*

add wave -group "XIRQ" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_xirq_inst_ON/cellrv32_xirq_inst/*

add wave -group "Sysinfo" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_sysinfo_inst/*

add wave -group "Bus Switch" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_busswitch_inst/*

add wave -group "Icahe" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_icache_inst_ON/cellrv32_icache_inst/*

add wave -group "Imem" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_int_imem_inst_ON/cellrv32_int_imem_inst/*

add wave -group "Dmem" /neorv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/*
