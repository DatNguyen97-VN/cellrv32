# Define the top-level module
set top_level "/cellrv32_tb_simple"

# Gets all signals of entire design
set signals_string [find signals -r /$top_level/*]

# Loop through the list, modify and add wave signal
foreach element $signals_string {
    # Remove the leading '/' and split the string into components
    set trimmed_string [string trimleft $element "/"]
    set components [split $trimmed_string "/"]

    # Remove the last element from the list
    set components [lrange $components 0 end-1]

    # Initialize the modified string
    set modified_string ""

    # Loop through the list and build the modified string
    foreach child_element $components {
        append modified_string " -group \"$child_element\""
    }

    # Replace [ with \[ and ] with \] in both strings
    set modified_string [string map {"[" "\\[" "]" "\\]"} $modified_string]
    set instance_string [string map {"[" "\\[" "]" "\\]"} $element]

    # Debug output to check the constructed strings
    puts "modified_string: $modified_string"
    puts "instance_string: $instance_string"

    # Check if element contains '#'
    if {[string first "#" $instance_string] == -1} {
        # Add wave with modified_string settings of element signal
        puts "Executing eval command: add wave $modified_string $instance_string"
        eval add wave $modified_string $instance_string
    } else {
        puts "Skipping $instance_string due to presence of '#'."
    }
}

# Output the completion message
puts "Added waves for signals in entire design"
