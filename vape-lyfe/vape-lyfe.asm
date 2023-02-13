	include  "vectrex.inc"


MAX_LINES equ 3
SEEDS_SIZE equ 2*MAX_LINES
STATE_SIZE equ $60
LINE_DY equ 30


; The TFR instruction has well-defined behavior when transferring between 8- and 16-bit registers.
; But asmj tries to be "helpful", and does not allow TFR between registers of different size,
; so we have to implement it ourselves with a macro...

OP_TFR	equ	$1f
REG_D	equ	%0000
REG_X	equ	%0001
REG_Y	equ	%0010
REG_U	equ	%0011
REG_S	equ	%0100
REG_PC	equ	%0101
REG_A	equ	%1000
REG_B	equ	%1001
REG_CC	equ	%1010
REG_DP	equ	%1011

tfr_but_it_works macro
	fcb OP_TFR
	fcb ((\1)<<4)|(\2)
	endm



	bss
	org $c880	; Start of user RAM area


	
	org $c900	; Align the curve buffer address to $100 bytes, so that the LSB is the index
curve: rmb STATE_SIZE
curve_end:


seeds: rmb SEEDS_SIZE
seeds_end:



	data
	org 0


	; Header

	fcb $67, " GCE 128B", $80     ; $67 is copyright sign
	fdb $FF8F                     ; Address of music in ROM
	fcb -$20, $7f, $00, -$00      ; Title size/position: height, width, y, x
	fcb $80                       ; Title text, ending with $80
	fcb 0                         ; End of header 


	; Code

	direct $d0

start:
	; Initialize seeds
	ldy #seeds
	sty ,y++
	sty ,y++
	sty ,y++

frame_loop:
	jsr Wait_Recal
	
	; Y = #seeds
	leay -SEEDS_SIZE,y

line_loop:
	; Skip to next frame if all 3 lines have been drawn
	cmpy #seeds_end
	beq frame_loop

	; Update curve backwards from end to start
	ldx #curve_end

curve_gen_loop:

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

	; Capture PRNG seed after the first iteration in the U register.
	; This is then used as the starting seed for this line in the next frame.
	cmpx #curve_end
	bne curve_no_store_seed
	ldu ,y
curve_no_store_seed:

	; Copy the LSB of the address of the current coordinate to the A register.
	; Since the curve buffer is aligned to $100, the A register now contains the index.
	tfr_but_it_works REG_X,REG_A

	; Multiply index with PRNG value
	mul

	; Multiply by 2
	lsla

	; Store into curve buffer
	sta ,-x

	; Loop while there are more coordinates to generate
	cmpx #curve
	bhs curve_gen_loop

	; Store captured seed for next frame, and move to next line/seed.
	stu ,y++

	; Zero integrators (move to center)
	jsr Reset0Ref

	; Disable ZERO and move to starting position
	ldd #((-128<<8)|(-64&$ff))
	jsr Moveto_d_7F


	; Vector setup

	lda #%00011000 
	;     ^^-------- Change the T1 timer control mode, to disable T1 control of PB7
	sta <VIA_aux_cntl

	; Port A: DAC value, Port B: Enable mux and set to Y channel (00)
	ldd #($8000+LINE_DY)
	std <VIA_port_b 

	; Configure shift register to be constantly on (no pattern).
	ldb #$ff
	stb <VIA_shift_reg

	; Disable mux, activate ramp
	lda #1
	sta <VIA_port_b

vector_loop:
	; Write value from curve buffer to DAC, which is fed to the X integrator.
	lda ,x+
	sta <VIA_port_a
	
	; Delay for 3 cycles
	brn $0

	; Loop while we have more coordinates
	cmpx #curve_end
	blo vector_loop
vector_done:
	; Turn off the beam
	clr <VIA_shift_reg


	lda #%10011000 
	;     ^^-------- Reset T1 cntl mode
	sta <VIA_aux_cntl

	; Move to next line
	bra line_loop


end:
CODE_SIZE: equ end