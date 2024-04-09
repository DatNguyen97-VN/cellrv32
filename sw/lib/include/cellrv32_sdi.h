// #################################################################################################
// # << CELLRV32: cellrv32_sdi.h - Serial Data Interface Controller (SDI) HW Driver >>             #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_sdi.h
 * @brief Serial data interface controller (SPPI) HW driver header file.
 *
 * @note These functions should only be used if the SDI unit was synthesized (IO_SDI_EN = true).
 **************************************************************************/

#ifndef cellrv32_sdi_h
#define cellrv32_sdi_h

/**********************************************************************//**
 * @name IO Device: Serial Data Interface (SDI)
 **************************************************************************/
/**@{*/
/** SDI module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL; /**< offset 0: control register (#CELLRV32_SDI_CTRL_enum) */
  uint32_t DATA; /**< offset 4: data register */
} cellrv32_sdi_t;

/** SDI module hardware access (#cellrv32_sdi_t) */
#define CELLRV32_SDI ((cellrv32_sdi_t*) (CELLRV32_SDI_BASE))

/** SDI control register bits */
enum CELLRV32_SDI_CTRL_enum {
  SDI_CTRL_EN           =  0, /**< SDI control register(00) (r/w): SID module enable */
  SDI_CTRL_CLR_RX       =  1, /**< SDI control register(01) (-/w): Clear RX FIFO when set, auto-clear */

  SDI_CTRL_FIFO_LSB     =  4, /**< SDI control register(04) (r/-): log2 of SDI FIFO size, LSB */
  SDI_CTRL_FIFO_MSB     =  7, /**< SDI control register(07) (r/-): log2 of SDI FIFO size, MSB */

  SDI_CTRL_IRQ_RX_AVAIL = 15, /**< SDI control register(15) (r/w): IRQ when RX FIFO not empty */
  SDI_CTRL_IRQ_RX_HALF  = 16, /**< SDI control register(16) (r/w): IRQ when RX FIFO at least half full */
  SDI_CTRL_IRQ_RX_FULL  = 17, /**< SDI control register(17) (r/w): IRQ when RX FIFO full */
  SDI_CTRL_IRQ_TX_EMPTY = 18, /**< SDI control register(18) (r/w): IRQ when TX FIFO empty */

  SDI_CTRL_RX_AVAIL     = 23, /**< SDI control register(23) (r/-): RX FIFO not empty */
  SDI_CTRL_RX_HALF      = 24, /**< SDI control register(24) (r/-): RX FIFO at least half full */
  SDI_CTRL_RX_FULL      = 25, /**< SDI control register(25) (r/-): RX FIFO full */
  SDI_CTRL_TX_EMPTY     = 26, /**< SDI control register(26) (r/-): TX FIFO empty */
  SDI_CTRL_TX_FULL      = 27  /**< SDI control register(27) (r/-): TX FIFO full */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int     cellrv32_sdi_available(void);
void    cellrv32_sdi_setup(uint32_t irq_mask);
void    cellrv32_sdi_rx_clear(void);
void    cellrv32_sdi_disable(void);
void    cellrv32_sdi_enable(void);
int     cellrv32_sdi_get_fifo_depth(void);
int     cellrv32_sdi_put(uint8_t data);
void    cellrv32_sdi_put_nonblocking(uint8_t data);
int     cellrv32_sdi_get(uint8_t* data);
uint8_t cellrv32_sdi_get_nonblocking(void);
/**@}*/


#endif // cellrv32_sdi_h
