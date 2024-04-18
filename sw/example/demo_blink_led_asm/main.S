/* ################################################################################################# */
/* # << CELLRV32 - Blink LED - Assembly-Only Demo Program >>                                       # */
/* ################################################################################################# */


/**********************************************************************//**
 * @file demo_blink_led_asm/main.S
 * @author Stephan Nolting
 * @brief Simple assembly-only demo program. Implements a simple counter that
 * uses the lowest 8 bits of the GPIO's output port. The CPU cycle counter is
 * used as time base. Hence, this program requires the GPIO controller and the
 * CPU Zicsr and Zicnt ISA extensions.
 **************************************************************************/
.file "main.S"
.section .text
.balign 4
.global main

// Memory map
.set GPIO_OUTPUT_LO, 0xFFFFFFC8U // address of the GPIO.OUTPUT_LO register
.set SYSINFO_CKLK,   0xFFFFFFE0U // address of SYSINFO.CLK


/**********************************************************************//**
 * Entry point = main
 **************************************************************************/
main:
    li a0,  GPIO_OUTPUT_LO       // address of the GPIO.OUTPUT_LO register
    li a1,  0                    // clear counter

loop:
    andi a1, a1, 0xff            // mask: just keep the lowest 8 bits
    sw   a1, 0(a0)               // output current counter
    call delay                   // call delay subroutine
    addi a1, a1, 1               // increment counter
    j    loop


/**********************************************************************//**
 * Delay subroutine using mcycle (waiting for 0.25s)
 **************************************************************************/
delay:
    li   t0, SYSINFO_CKLK        // address of SYSINFO.CLK
    lw   t0, 0(t0)               // read SYSINFO.CLK (= CPU clock speed in Hz = tick per second)
    srli t0, t0, 2               // = ticks per 0.25 seconds
    csrr t1, mcycle              // get current cycle counter (low word)
    add  t1, t1, t0

delay_loop:
    csrr t0, mcycle              // get current cycle counter (low word)
    bltu t0, t1, delay_loop      // restart loop if mcycle < t1

    ret                          // return to main

.end
