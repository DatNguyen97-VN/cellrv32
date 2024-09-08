#!/usr/bin/env bash

# `QUESTASIM` is used to check all SystemVerilog files for syntax errors and to simulate the default testbench. The previously
# installed CPU test program is executed and the console output (UART0 primary UART) is dumped to a text file. After the
# simulation has finished, the text file is searched for a specific string. If the string is found, the CPU test was
# successful.

# Abort if any command returns != 0
set -e

cd $(dirname "$0")

./questa_setup.sh
./questa_sim.sh

