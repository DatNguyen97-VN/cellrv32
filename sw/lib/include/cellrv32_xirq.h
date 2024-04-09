// #################################################################################################
// # << CELLRV32: cellrv32_xirq.h - External Interrupt controller HW Driver >>                     #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_xirq.h
 * @brief External Interrupt controller HW driver header file.
 **************************************************************************/

#ifndef cellrv32_xirq_h
#define cellrv32_xirq_h

/**********************************************************************//**
 * @name IO Device: External Interrupt Controller (XIRQ)
 **************************************************************************/
/**@{*/
/** XIRQ module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t       IER;      /**< offset 0:  IRQ input enable register */
  uint32_t       IPR;      /**< offset 4:  pending IRQ register /ack/clear */
  uint32_t       SCR;      /**< offset 8:  interrupt source register */
  const uint32_t reserved; /**< offset 12: reserved */
} cellrv32_xirq_t;

/** XIRQ module hardware access (#cellrv32_xirq_t) */
#define CELLRV32_XIRQ ((cellrv32_xirq_t*) (CELLRV32_XIRQ_BASE))
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int  cellrv32_xirq_available(void);
int  cellrv32_xirq_setup(void);
void cellrv32_xirq_global_enable(void);
void cellrv32_xirq_global_disable(void);
int  cellrv32_xirq_get_num(void);
void cellrv32_xirq_clear_pending(uint8_t ch);
void cellrv32_xirq_channel_enable(uint8_t ch);
void cellrv32_xirq_channel_disable(uint8_t ch);
int  cellrv32_xirq_install(uint8_t ch, void (*handler)(void));
int  cellrv32_xirq_uninstall(uint8_t ch);
/**@}*/


#endif // cellrv32_xirq_h
