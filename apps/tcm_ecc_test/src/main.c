/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include <zephyr/kernel.h>

int main(void)
{
	uint32_t n = 0;

	printk("tcm_ecc_test: Hello World! %s\n", CONFIG_BOARD_TARGET);
	while (1) {
		k_msleep(1000);
		printk("alive %u\n", ++n);
	}
	return 0;
}
