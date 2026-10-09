/*
 * Write every word of the M7 DTCM once before any RAM access. The TCMs
 * have ECC: until a word has been written, reads and sub-word writes
 * (read-modify-write) of it fault. Runs before any stack exists, so it
 * only uses r0-r2. Safe to clear: .data is copied from ITCM and .bss is
 * zeroed later in z_prep_c.
 */
#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>
#include <zephyr/devicetree.h>

_ASM_FILE_PROLOGUE

#define DTCM_START DT_REG_ADDR(DT_NODELABEL(dtcm))
#define DTCM_END   (DTCM_START + DT_REG_SIZE(DT_NODELABEL(dtcm)))

GTEXT(soc_early_reset_hook)

SECTION_FUNC(TEXT, soc_early_reset_hook)
	ldr r0, =DTCM_START
	ldr r1, =DTCM_END
	movs r2, #0
1:
	str r2, [r0], #4
	cmp r0, r1
	blo 1b
	bx lr
