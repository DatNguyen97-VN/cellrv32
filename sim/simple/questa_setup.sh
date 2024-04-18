#!/usr/bin/env bash

set -e

cd $(dirname "$0")

NEOV32_LOCAL_RTL=${NEOV32_LOCAL_RTL:-../../rtl}
CELLV32_LOCAL_RTL=${CELLV32_LOCAL_RTL:-../../rtl}

rm -rf cellrv32 work
vlib.exe cellrv32 
vlib.exe work

vmap.exe work work

vlog.exe -sv -work cellrv32 \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_package.sv \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_application_image.sv \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_bootloader_image.sv \
         "$CELLV32_LOCAL_RTL"/core/*.sv \
         "$CELLV32_LOCAL_RTL"/core/mem/*.sv
         
vcom.exe -work cellrv32 "$NEOV32_LOCAL_RTL"/core/neorv32_package.vhd \
         "$NEOV32_LOCAL_RTL"/core/*.vhd \
         uart_rx.simple.vhd \
         neorv32_tb.simple.vhd

vopt.exe cellrv32.cellrv32_top -o optver
         
    

