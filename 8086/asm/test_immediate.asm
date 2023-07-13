bits 16

mov dx, 6
mov bp, 1000

mov si, 0
init_loop_start:
	mov word [bp + si], si
	add si, 2
	cmp si, dx
	jnz init_loop_start
