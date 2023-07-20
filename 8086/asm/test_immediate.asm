bits 16

; Start image after one row, to avoid overwriting our code!
mov bp, 64*4

mov dx, 0
y_loop_start:
	
	mov cx, 0
	x_loop_start:
		; Fill pixel
		mov word [bp + 0], cx ; Red
		mov word [bp + 2], dx ; Blue
		mov byte [bp + 3], 255 ; Alpha
			
		; Advance pixel location
		add bp, 4
			
		; Advance X coordinate and loop
		add cx, 1
		cmp cx, 2
		jnz x_loop_start
	
	; Advance Y coordinate and loop
	add dx, 1
	cmp dx, 1
	jnz y_loop_start
