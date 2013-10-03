#ifndef _CONFIG_H
#define _CONFIG_H

/* #define LASU_HD */
#define LINUS_HD

/*
 * Amount of ram memory (in bytes, 640k-1M not discounted). Currently 8Mb.
 * Don't make this bigger without making sure that there are enough page
 * directory entries (boot/head.s)
 */
#if	defined(LINUS_HD)
#define HIGH_MEMORY (0x800000)
#elif	defined(LASU_HD)
#define HIGH_MEMORY (0x400000)
#else
#error "must define hd"
#endif

/* End of buffer memory. Must be 0xA0000, or > 0x100000, 4096-byte aligned */
#if (HIGH_MEMORY>=0x600000)
#define BUFFER_END 0x200000
#else
#define BUFFER_END 0xA0000
#endif

/* Root device at bootup. */
#if	defined(LINUS_HD)
#define ROOT_DEV 0x306
#elif	defined(LASU_HD)
#define ROOT_DEV 0x302
#else
#error "must define HD"
#endif

/*
 * HD type. If 2, put 2 structures with a comma. If just 1, put
 * only 1 struct. The structs are { HEAD, SECTOR, TRACKS, WPCOM, LZONE, CTL }
 *
 * NOTE. CTL is supposed to be 0 for drives with less than 8 heads, and
 * 8 if heads >= 8. Don't know why, and I haven't tested it on a drive with
 * more than 8 heads, but that is what the bios-listings seem to imply. I
 * just love not having a manual.
 */
#if	defined(LASU_HD)
#define HD_TYPE { 7,35,915,65536,920,0 }
#elif	defined(LINUS_HD)
#define HD_TYPE { 5,17,980,300,980,0 },{ 5,17,980,300,980,0 }
#else
#error "must define a hard-disk type"
#endif

#endif
