// #################################################################################################
// # << CELLRV32: cellrv32_mtime.h - Machine System Timer (MTIME) HW Driver >>                     #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_mtime.h
 * @brief Machine System Timer (MTIME) HW driver header file.
 *
 * @note These functions should only be used if the MTIME unit was synthesized (IO_MTIME_EN = true).
 **************************************************************************/

#ifndef cellrv32_mtime_h
#define cellrv32_mtime_h

/**********************************************************************//**
 * @name IO Device: Machine System Timer (MTIME)
 **************************************************************************/
/**@{*/
/** MTIME module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t TIME_LO;    /**< offset 0:  time register low word */
  uint32_t TIME_HI;    /**< offset 4:  time register high word */
  uint32_t TIMECMP_LO; /**< offset 8:  compare register low word */
  uint32_t TIMECMP_HI; /**< offset 12: compare register high word */
} cellrv32_mtime_t;

/** MTIME module hardware access (#cellrv32_mtime_t) */
#define CELLRV32_MTIME ((cellrv32_mtime_t*) (CELLRV32_MTIME_BASE))
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int      cellrv32_mtime_available(void);
void     cellrv32_mtime_set_time(uint64_t time);
uint64_t cellrv32_mtime_get_time(void);
void     cellrv32_mtime_set_timecmp(uint64_t timecmp);
uint64_t cellrv32_mtime_get_timecmp(void);
/**@}*/


#endif // cellrv32_mtime_h
