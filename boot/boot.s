|
|	boot.s
|
| boot.s is loaded at 0x7c00 by the bios-startup routines, and moves itself
| out of the way to address 0x90000, and jumps there.
|
| It then loads the system at 0x10000, using BIOS interrupts. Thereafter
| it disables all interrupts, moves the system down to 0x0000, changes
| to protected mode, and calls the start of system. System then must
| RE-initialize the protected mode in it's own tables, and enable
| interrupts as needed.
|
| NOTE! currently system is at most 8*65536 bytes long. This should be no
| problem, even in the future. I want to keep it simple. This 512 kB
| kernel size should be enough - in fact more would mean we'd have to move
| not just these start-up routines, but also do something about the cache-
| memory (block IO devices). The area left over in the lower 640 kB is meant
| for these. No other memory is assumed to be "physical", ie all memory
| over 1Mb is demand-paging. All addresses under 1Mb are guaranteed to match
| their physical addresses.
|
| NOTE1 abouve is no longer valid in it's entirety. cache-memory is allocated
| above the 1Mb mark as well as below. Otherwise it is mainly correct.
|
| NOTE 2! The boot disk type must be set at compile-time, by setting
| the following equ. Having the boot-up procedure hunt for the right
| disk type is severe brain-damage.
| The loader has been made as simple as possible (had to, to get it
| in 512 bytes with the code to move to protected mode), and continuos
| read errors will result in a unbreakable loop. Reboot by hand. It
| loads pretty fast by getting whole sectors at a time whenever possible.

| 1.44Mb disks:
sectors = 18
| 1.2Mb disks:
| sectors = 15
| 720kB disks:
| sectors = 9

.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

BOOTSEG = 0x07c0
INITSEG = 0x9000
SYSSEG  = 0x1000			| system loaded at 0x10000 (65536).
ENDSEG	= SYSSEG + SYSSIZE

entry start
start:
	mov	ax,#BOOTSEG
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	rep
	movw
	jmpi	go,INITSEG
go:	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	mov	sp,#0x400		| arbitrary value >>512

	mov	ah,#0x03	| read cursor pos
	xor	bh,bh
	int	0x10
	
	mov	cx,#24
	mov	bx,#0x0007	| page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301	| write string, move cursor
	int	0x10

| ok, we've written the message, now
| we want to load the system (at 0x10000)

	mov	ax,#SYSSEG
	mov	es,ax		| segment of 0x010000
	call	read_it
	call	kill_motor

| if the read went well we get current cursor position ans save it for
| posterity.

	mov	ah,#0x03	| read cursor pos
	xor	bh,bh
	int	0x10		| save it in known place, con_init fetches
	mov	[510],dx	| it from 0x90510.
		
| now we want to move to protected mode ...

	cli			| no interrupts allowed !

| first we move the system to it's rightful place

	mov	ax,#0x0000
	cld			| 'direction'=0, movs moves forward
do_move:
	mov	es,ax		| destination segment
	add	ax,#0x1000
	cmp	ax,#0x9000
	jz	end_move
	mov	ds,ax		| source segment
	sub	di,di
	sub	si,si
	mov 	cx,#0x8000
	rep
	movsw
	j	do_move

| then we load the segment descriptors

end_move:

	mov	ax,cs		| right, forgot this at first. didn't work :-)
	mov	ds,ax
	lidt	idt_48		| load idt with 0,0
	lgdt	gdt_48		| load gdt with whatever appropriate

| that was painless, now we enable A20

	call	empty_8042
	mov	al,#0xD1		| command write
	out	#0x64,al
	call	empty_8042
	mov	al,#0xDF		| A20 on
	out	#0x60,al
	call	empty_8042

| well, that went ok, I hope. Now we have to reprogram the interrupts :-(
| we put them right after the intel-reserved hardware interrupts, at
| int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
| messed this up with the original PC, and they haven't been able to
| rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
| which is used for the internal hardware interrupts as well. We just
| have to reprogram the 8259's, and it isn't fun.

	mov	al,#0x11		| initialization sequence
	out	#0x20,al		| send it to 8259A-1
	.word	0x00eb,0x00eb		| jmp $+2, jmp $+2
	out	#0xA0,al		| and to 8259A-2
	.word	0x00eb,0x00eb
	mov	al,#0x20		| start of hardware int's (0x20)
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x28		| start of hardware int's 2 (0x28)
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x04		| 8259-1 is master
	out	#0x21,al
	.word	0x00eb,0x00eb
	mov	al,#0x02		| 8259-2 is slave
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0x01		| 8086 mode for both
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al
	.word	0x00eb,0x00eb
	mov	al,#0xFF		| mask off all interrupts for now
	out	#0x21,al
	.word	0x00eb,0x00eb
	out	#0xA1,al

| well, that certainly wasn't fun :-(. Hopefully it works, and we don't
| need no steenking BIOS anyway (except for the initial loading :-).
| The BIOS-routine wants lots of unnecessary data, and it's less
| "interesting" anyway. This is how REAL programmers do it.
|
| Well, now's the time to actually move into protected mode. To make
| things as simple as possible, we do no register set-up or anything,
| we let the gnu-compiled 32-bit programs do that. We just jump to
| absolute address 0x00000, in 32-bit protected mode.

	mov	ax,#0x0001	| protected mode (PE) bit
	lmsw	ax		| This is it!
	jmpi	0,8		| jmp offset 0 of segment 8 (cs)

| This routine checks that the keyboard command queue is empty
| No timeout is used - if this hangs there is something wrong with
| the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	al,#0x64	| 8042 status port
	test	al,#2		| is input buffer full?
	jnz	empty_8042	| yes - loop
	ret

| This routine loads the system at address 0x10000, making sure
| no 64kB boundaries are crossed. We try to load it as fast as
| possible, loading whole tracks whenever we can.
|
| in:	es - starting address segment (normally 0x1000)
|
| This routine has to be recompiled to fit another drive type,
| just change the "sectors" variable at the start of the file
| (originally 18, for a 1.44Mb drive)
|
sread:	.word 1			| sectors read of current track
head:	.word 0			| current head
track:	.word 0			| current track
read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			| es must be at 64kB boundary
	xor bx,bx		| bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		| have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	mov ax,#sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	cmp ax,#sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	push ax
	push bx
	push cx
	push dx
	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

gdt:
	.word	0,0,0,0		| dummy

	.word	0x07FF		| 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		| base address=0
	.word	0x9A00		| code read/exec
	.word	0x00C0		| granularity=4096, 386

	.word	0x07FF		| 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		| base address=0
	.word	0x9200		| data read/write
	.word	0x00C0		| granularity=4096, 386

idt_48:
	.word	0			| idt limit=0
	.word	0,0			| idt base=0L

gdt_48:
	.word	0x800		| gdt limit=2048, 256 GDT entries
	.word	gdt,0x9		| gdt base = 0X9xxxx
	
msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.text
endtext:
.data
enddata:
.bss
endbss:
