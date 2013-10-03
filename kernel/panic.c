/*
 * This function is used through-out the kernel (includeinh mm and fs)
 * to indicate a major problem.
 */
#include <linux/kernel.h>

volatile void panic(const char * s)
{
	printk("Kernel panic: %s\n\r",s);
	for(;;);
}
