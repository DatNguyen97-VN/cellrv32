# Define the top-level module
set top_level "/cellrv32_tb_simple"

# Gets all signals of entire design
set signals_string [find signals -r /$top_level/*]

# Initialize a list to store previously added instance strings
set added_signals_list {}

# Loop through the list, modify and add wave signal
foreach element $signals_string {
    # Remove the leading '/' and split the string into components
    set trimmed_string [string trimleft $element "/"]
    set components [split $trimmed_string "/"]

    # Remove the last element from the list
    set components [lrange $components 0 end-1]

    # Initialize the modified string
    set modified_string ""
    set new_instance_string ""

    # Loop through the list and build the modified string
    foreach child_element $components {
        append modified_string " -group \"$child_element\""
        append new_instance_string "/$child_element"
    }

    # Replace [ with \[ and ] with \] in both strings
    set modified_string [string map {"[" "\\[" "]" "\\]"} $modified_string]
    set new_instance_string [string map {"[" "\\[" "]" "\\]"} $new_instance_string]

    # Debug output to check the constructed strings
    #puts "modified_string: $modified_string"
    #puts "new_instance_string: $new_instance_string"

    # Check if element contains '#' and if it's already added
    if {[string first "#" $new_instance_string] == -1 && [lsearch -exact $added_signals_list $new_instance_string] == -1} {
        # Add wave with modified_string settings of element signal
        #puts "Executing eval command: add wave $modified_string $new_instance_string"
        eval add wave $modified_string $new_instance_string/*

        # Add this instance string to the list of added signals
        lappend added_signals_list $new_instance_string
    } else {
        #puts "Skipping $new_instance_string (already added or invalid)."
    }
}

# Additional signals
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_cpu_inst" -group "cellrv32_cpu_regfile_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_cpu_inst" -group "cellrv32_cpu_regfile_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_regfile_inst/reg_file_emb
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_int_dmem_inst_ON" -group "cellrv32_int_dmem_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/mem_ram_b0
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_int_dmem_inst_ON" -group "cellrv32_int_dmem_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/mem_ram_b1
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_int_dmem_inst_ON" -group "cellrv32_int_dmem_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/mem_ram_b2
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_int_dmem_inst_ON" -group "cellrv32_int_dmem_inst" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_int_dmem_inst_ON/cellrv32_int_dmem_inst/mem_ram_b3
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" /cellrv32_tb_simple/cellrv32_top_inst/resp_bus
add wave -group "cellrv32_tb_simple" -group "cellrv32_top_inst" -group "cellrv32_cpu_inst" -group "cellrv32_cpu_alu_inst" -group "cellrv32_cpu_cp_vector_inst_ON" -group "cellrv32_cpu_cp_vector_inst" -group "vis" -group "vrf" /cellrv32_tb_simple/cellrv32_top_inst/cellrv32_cpu_inst/cellrv32_cpu_alu_inst/cellrv32_cpu_cp_vector_inst_ON/cellrv32_cpu_cp_vector_inst/vis/vrf/memory
# Output the completion message
puts "Added waves for signals in entire design"
