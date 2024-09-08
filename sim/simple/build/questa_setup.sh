#!/usr/bin/env bash

set -e

cd $(dirname "$0")

VLIB=${VLIB:-vlib.exe}
VMAP=${VMAP:-vmap.exe}
VLOG=${VLOG:-vlog.exe}
VCOM=${VCOM:-vcom.exe}
VOPT=${VOPT:-vopt.exe}

CELLV32_LOCAL_RTL=${CELLV32_LOCAL_RTL:-../../../rtl}

$VLIB cellrv32 
$VLIB work

$VMAP work work 

$VLOG -sv -work cellrv32 \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_package.sv \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_application_image.sv \
         "$CELLV32_LOCAL_RTL"/core/cellrv32_bootloader_image.sv \
         "$CELLV32_LOCAL_RTL"/core/*.sv \
         "$CELLV32_LOCAL_RTL"/core/mem/*.sv \
         ../uart_rx.sv \
         ../cellrv32_tb.sv

$VOPT cellrv32.cellrv32_top -o optver
         
    

