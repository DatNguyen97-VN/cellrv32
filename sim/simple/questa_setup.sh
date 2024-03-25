#!/usr/bin/env bash

set -e

cd $(dirname "$0")

NEOV32_LOCAL_RTL=${NEOV32_LOCAL_RTL:-../../rtl}
CELLV32_LOCAL_RTL=${CELLV32_LOCAL_RTL:-../../rtl}

rm -rf neorv32 work
vlib.exe neorv32 
vlib.exe work

vmap.exe work work

vlog.exe -sv -work neorv32 \
         "$CELLV32_LOCAL_RTL/core/cellrv32_package.sv" \
         "$CELLV32_LOCAL_RTL/core/*.sv"
         
vcom.exe -work neorv32 "$NEOV32_LOCAL_RTL"/core/neorv32_package.vhd \
         "$NEOV32_LOCAL_RTL"/core/*.vhd \
         "$NEOV32_LOCAL_RTL"/core/mem/*.vhd \
         uart_rx.simple.vhd \
         neorv32_tb.simple.vhd

vopt.exe neorv32.neorv32_top -o optver
         
    

