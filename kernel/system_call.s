/*
 *  system_call.s  contains the system-call low-level handling routines.
 * This also contains the timer-interrupt handler, as some of the code is
 * the same. The hd-interrupt is also here.
 *
 * NOTE: This code handles signal-recognition, which happens every time
 * after a timer-interrupt and after each system call. Ordinary interrupts
 * don't handle signal-recognition, as that would clutter them up totally
 * unnecessarily.
 *
 * Stack layout in 'ret_from_system_call':
 *
 *	 0(%esp) - %eax
 *	 4(%esp) - %ebx
 *	 8(%esp) - %ecx
 *	 C(%esp) - %edx
 *	10(%esp) - %fs
 *	14(%esp) - %es
 *	18(%esp) - %ds
 *	1C(%esp) - %eip
 *	20(%esp) - %cs
 *	24(%esp) - %eflags
 *	28(%esp) - %oldesp
 *	2C(%esp) - %oldss
 */

SIG_CHLD	= 17
EAX		= 0x00
EBX		= 0x04
ECX		= 0x08
EDX		= 0x0C
FS		= 0x10
ES		= 0x14
DS		= 0x18
EIP		= 0x1C
CS		= 0x20
EFLAGS		= 0x24
OLDESP		= 0x28
OLDSS		= 0x2C

state	= 0		# these are offsets into the task-struct.
counter	= 4
priority = 8
signal	= 12
restorer = 16		# address of info-restorer
sig_fn	= 20		# table of 32 signal addresses

nr_system_calls = 67

.globl _system_call,_sys_fork,_timer_interrupt,_hd_interrupt,_sys_execve

.align 2
bad_sys_call:
	movl $-1,%eax
	iret
.align 2
reschedule:
	pushl $ret_from_sys_call
	jmp _schedule
.align 2
_system_call:
	cmpl $nr_system_calls-1,%eax
	ja bad_sys_call
	push %ds
	push %es
	push %fs
	pushl %edx
	pushl %ecx		# push %ebx,%ecx,%edx as parameters
	pushl %ebx		# to the system call
	movl $0x10,%edx		# set up ds,es to kernel space
	mov %dx,%ds
	mov %dx,%es
	movl $0x17,%edx		# fs points to local data space
	mov %dx,%fs
	call _sys_call_table(,%eax,4)
	pushl %eax
	movl _current,%eax
	cmpl $0,state(%eax)		# state
	jne reschedule
	cmpl $0,counter(%eax)		# counter
	je reschedule
ret_from_sys_call:
	movl _current,%eax		# task[0] cannot have signals
	cmpl _task,%eax
	je 3f
	movl CS(%esp),%ebx		# was old code segment supervisor
	testl $3,%ebx			# mode? If so - don't check signals
	je 3f
	cmpw $0x17,OLDSS(%esp)		# was stack segment = 0x17 ?
	jne 3f
2:	movl signal(%eax),%ebx		# signals (bitmap, 32 signals)
	bsfl %ebx,%ecx			# %ecx is signal nr, return if none
	je 3f
	btrl %ecx,%ebx			# clear it
	movl %ebx,signal(%eax)
	movl sig_fn(%eax,%ecx,4),%ebx	# %ebx is signal handler address
	cmpl $1,%ebx
	jb default_signal		# 0 is default signal handler - exit
	je 2b				# 1 is ignore - find next signal
	movl $0,sig_fn(%eax,%ecx,4)	# reset signal handler address
	incl %ecx
	xchgl %ebx,EIP(%esp)		# put new return address on stack
	subl $28,OLDESP(%esp)
	movl OLDESP(%esp),%edx		# push old return address on stack
	pushl %eax			# but first check that it's ok.
	pushl %ecx
	pushl $28
	pushl %edx
	call _verify_area
	popl %edx
	addl $4,%esp
	popl %ecx
	popl %eax
	movl restorer(%eax),%eax
	movl %eax,%fs:(%edx)		# flag/reg restorer
	movl %ecx,%fs:4(%edx)		# signal nr
	movl EAX(%esp),%eax
	movl %eax,%fs:8(%edx)		# old eax
	movl ECX(%esp),%eax
	movl %eax,%fs:12(%edx)		# old ecx
	movl EDX(%esp),%eax
	movl %eax,%fs:16(%edx)		# old edx
	movl EFLAGS(%esp),%eax
	movl %eax,%fs:20(%edx)		# old eflags
	movl %ebx,%fs:24(%edx)		# old return addr
3:	popl %eax
	popl %ebx
	popl %ecx
	popl %edx
	pop %fs
	pop %es
	pop %ds
	iret

default_signal:
	incl %ecx
	cmpl $SIG_CHLD,%ecx
	je 2b
	pushl %ecx
	call _do_exit		# remember to set bit 7 when dumping core
	addl $4,%esp
	jmp 3b

.align 2
_timer_interrupt:
	push %ds		# save ds,es and put kernel data space
	push %es		# into them. %fs is used by _system_call
	push %fs
	pushl %edx		# we save %eax,%ecx,%edx as gcc doesn't
	pushl %ecx		# save those across function calls. %ebx
	pushl %ebx		# is saved as we use that in ret_sys_call
	pushl %eax
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	incl _jiffies
	movb $0x20,%al		# EOI to interrupt controller #1
	outb %al,$0x20
	movl CS(%esp),%eax
	andl $3,%eax		# %eax is CPL (0 or 3, 0=supervisor)
	pushl %eax
	call _do_timer		# 'do_timer(long CPL)' does everything from
	addl $4,%esp		# task switching to accounting ...
	jmp ret_from_sys_call

.align 2
_sys_execve:
	lea EIP(%esp),%eax
	pushl %eax
	call _do_execve
	addl $4,%esp
	ret

.align 2
_sys_fork:
	call _find_empty_process
	testl %eax,%eax
	js 1f
	push %gs
	pushl %esi
	pushl %edi
	pushl %ebp
	pushl %eax
	call _copy_process
	addl $20,%esp
1:	ret

_hd_interrupt:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	movb $0x20,%al
	outb %al,$0x20		# EOI to interrupt controller #1
	jmp 1f			# give port chance to breathe
1:	jmp 1f
1:	outb %al,$0xA0		# same to controller #2
	movl _do_hd,%eax
	testl %eax,%eax
	jne 1f
	movl $_unexpected_hd_interrupt,%eax
1:	call *%eax		# "interesting" way of handling intr.
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

