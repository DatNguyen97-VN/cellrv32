#!/usr/bin/env bash

set -e

cd $(dirname "$0")

#echo "Tip: Compile application with USER_FLAGS+=-DUART[0/1]_SIM_MODE to auto-enable UART[0/1]'s simulation mode (redirect UART output to simulator console)."

# Prepare simulation output files for UART0 and UART 1
# - Testbench receiver log file (cellrv32.testbench_uart?.out)
# - Direct simulation output (cellrv32.uart?.sim_mode.[text|data].out)
for uart in 0 1; do
  for item in \
    testbench_uart"$uart" \
    uart"$uart".sim_mode.text \
    uart"$uart".sim_mode.data; do
    touch cellrv32."$item".out
    chmod 777 cellrv32."$item".out
  done
done

# Start simulation
QUESTA_RUN_ARGS="${@:---stop-time=20ms}"
echo "Using simulation runtime args: $QUESTA_RUN_ARGS";

# -voptargs="+acc" option for debug mode to add wave internal signal
vsim.exe neorv32.neorv32_tb_simple  -debugdb -do "source add_wave_debug.tcl; run 5ms; exit"

# verify results of processor check: sw/example/processor_check
cat cellrv32.uart0.sim_mode.text.out | grep "PROCESSOR TEST COMPLETED SUCCESSFULLY!"
