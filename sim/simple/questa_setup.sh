#!/usr/bin/env bash

set -e

# Enable alias expansion
shopt -s expand_aliases
# Source the setup file of questasim's command
source /home/tools/.myclr

cd $(dirname "$0")

CELLV32_LOCAL_RTL=${CELLV32_LOCAL_RTL:-../../../rtl}

# Create and map the library
vlib cellrv32 
vlib work
vmap work work 

# Compile the package and sv files
vlog  -sv -mfcu -work cellrv32 \
      "$CELLV32_LOCAL_RTL"/core/packages/*.svh \
      "$CELLV32_LOCAL_RTL"/core/*.sv \
      "$CELLV32_LOCAL_RTL"/core/mem/*.sv \
      ../*.sv

# Optimize design
vopt cellrv32.cellrv32_top -o optver
         
    

