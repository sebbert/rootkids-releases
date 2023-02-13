	include  "vectrex.inc"

MAX_VECTORS equ 0x7f


	bss
	org $c880

	; RAM

rand_seed: rmb 2

vectors: rmb MAX_VECTORS*2
vectors_end equ vectors+MAX_VECTORS*2



	data
	org 0


	; Header

	fcb $67, " GCE 64B", $6a, $80 ; $67 is copyright sign, $6a is smiley face
	fdb $FF8F                     ; Address of music in ROM
	fcb -$4, $7f, $00, -$7f       ; Title size/position: height, width, y, x
	fcb "PROTEINSYNTESE", $80     ; Title text, ending with $80
	fcb 0                         ; End of header 


	; Code

	direct $d0

start:

frame_loop:
	jsr Wait_Recal

	; Dammit, could have saved two bytes, since we also set
	; the scale factor when calling Moveto_ix_b below...
	sta <VIA_t1_cnt_lo

	; X = #rand_seed
	ldx #rand_seed

	; Ensure seed is non-zero
	inc ,x

	; X = #vectors, Y = #rand_seed
	leay ,x++
update_loop:

	; xorshift PRNG, thanks to John Metcalf:
	; https://github.com/impomatic/xorshift798/blob/0af7547/6809.asm
	ldd ,y
	rora
	rorb
	eorb ,y
	stb ,y
	rorb
	eorb 1,y
	tfr b,a
	eora ,y
	std ,y

	; Limit delta to +/- 7
	andb #$0e
	subb #$07

	; Add delta to coordinate
	addb ,x
	
	; Avoid jumping by ignoring updated coordinate on overflow
	bvc update_nooverflow
	ldb ,x
update_nooverflow:

	; Store updated coordinate
	stb ,x+
	
	; Loop while there are more coordinates to update
	cmpx #vectors_end
	blo update_loop

	; Disable ZERO and set scale factor
	ldb #$07
	jsr Moveto_ix_b

	; Set brightness to avoid fading out over time
	jsr Intensity_7F

	; Draw vector list
	ldx #vectors
	lda #MAX_VECTORS-1
	jsr Draw_VL_a

	; Next frame
	bra frame_loop

end:
CODE_SIZE: equ end-start