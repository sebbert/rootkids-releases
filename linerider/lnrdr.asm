; linerider by sebbert ^ rootkids
;
; Comments:
;     Developed on and targeting DOSBox 0.74-3 on win32.
;     Not tested/supported on FreeDOS, sorry. Might release an update later on.
;
; Greetings:
;     Desire, Alcatraz, Řrřola, Marquee Design, Sensenstahl, Abaddon, lft, and everyone else in the sizecoding scene
;
; Special thanks:
;     Lovebyte organizers, for the x86 sizecoding starter pack: https://www.lovebyte.party/#GetStarted
;     HellMood, for their excellent writeup: http://www.sizecoding.org/wiki/Memories
;     sizecoding.org, for providing an invaluable learning resource: https://sizecoding.org/
;     Revision organizers, for making it all happen every easter <3


; Maximum number of agents
%define MAX_AGENTS 32

; Size of agent data structure
%define AGENT_SIZE 3

; Number of melody tracks
%define NUM_TRACKS 3

; Root note for melody
%define ROOT_NOTE 54

; Compatibility mode with slightly less dirty hacks
%ifdef COMPAT
    ; Don't assume cx = 0x00FF at entry
    %define INIT_CX_00FF

    ; Don't assume that MPU401 is already configured in UART mode
    %define INIT_MPU401_UART

    ; Clear agent data at entry, to avoid being affected by garbage data previously in memory
    %define CLEAR_AGENT_MEMORY
%endif


use16
org 100h

; Assumed register values:
; AX=0000 / BX=0000 / CX=00FF / DS=CS=SI=100h/ DI=FFFE / BP=09xx

%ifdef CLEAR_AGENT_MEMORY
    mov di, agents
    mov cx, MAX_AGENTS*AGENT_SIZE
    xor al, al
    rep stosb
    mov cx, 0xff
%elifdef INIT_CX_00FF
    mov cx, 0xff
%endif 

; Set ES segment to A000 (framebuffer)
push 0a000h
pop es

; Init 320x200x256 colors
mov al,0x13
int 0x10

xor bp, bp ; frame = 0

paletteloop:
    mov dx, 0x3c8 ; dx = color write port
    mov al, cl
    out dx, al

    inc dx ; dx = color data port

    ; red = index / 2
    shr al, 1
    out dx, al

    ; green, blue = index / 4
    shr al, 1
    out dx, al
    out dx, al

    loop paletteloop

frameloop:

%ifdef INIT_MPU401_UART
    mov al, 0x3f  ; al = Set UART mode command
    mov dx, 0x331 ; dx = MIDI control port
    out dx, al    ; send
    dec dx        ; dx = MIDI data port
%else
    ; Assume MPU401 is already in UART mode
    mov dx, 0x330 ; dx = MIDI Data Port
%endif
    
    ; Trigger kick and other static midi messages if frame % 16 == 0
    test bp, 0b1111
    jnz nokick

        mov si, midicmds
        mov cx, midicmds.length
        rep outsb
    nokick:

    mov di, NUM_TRACKS-1
    midiloop:
        movzx ax, [track_timing_masks + di] ; ax = track timing mask
        test bp, ax
        jnz skip_track ; Only play note if frame % mask == 0

        lea si, [track_positions + di] ; si = &track_positions[track_index]

        movzx bx, byte [si] ; bx = sequence position

        ; Move backwards to next step in sequence
        dec byte [si]

        ; Wrap around if we've reached the end
        jns no_track_rewind
        mov byte [si], notes.length-1

    no_track_rewind:

        mov ax, di  ; ax = track index
        or ax, 0x90 ; ax = 0x90 (send note) | track index (channel)
        out dx, al  ; send status byte

        mov al, [notes+bx] ; al = pitch

        ; pitch += transpositions[(frame/256) % 4]
        mov bx, bp
        shr bx, 8
        and bl, 0b11
        add al, [transpositions+bx]

        out dx, al   ; send pitch
        mov al, 0x50 ; al = velocity
        out dx, al   ; send velocity

    skip_track:

        ; while (--track >= 0)
        dec di
        jns midiloop

    inc bp ; Increment frame counter

    mov si, agents
    mov cx, MAX_AGENTS
    agentloop:

        lodsw       ; ax = agent position
        mov di, ax  ; di = agent position

        xor ax, ax
        lodsb       ; ax = direction index

        and al, 7   ; ax =  index % 8
        add ax, ax  ; ax = (index % 8) * 2 byte word
        mov bx, ax

        mov ax, [ds:directions+bx] ; ax = direction vector

        ; even-numbered agents skip every other frame
        mov bx, bp
        or bx, cx
        test bl, 1
        jz dontmove

        ; Ramp up number of moving agents from 0 .. MAX_AGENTS by one every 16th frame
        shr bx, 4
        cmp cx, bx
        jg dontmove
        
        add di, ax ; position += velocity
        dontmove:

        mov [si-3], di ; Store new agent position
        dec byte [es:di] ; Leave trail in framebuffer (previous value is usually 0, decrement to 0xff)

        ; Check ahead for collisions
        add di, ax           ; position += velocity
        mov dl, byte [es:di] ; dl = fb[position]
        add di, ax           ; position += velocity
        or dl, [es:di]       ; dl |= fb[position]
        add di, ax           ; position += velocity
        or dl, [es:di]       ; dl |= fb[position]
        je nochdir           ; Change direction if (dl != 0)

            ; Change direction by 45 degrees CW or CCW

            ; Cheap "hash" based on current frame number and agent index
            mov ax, bp ; ax = frame
            add ax, cx ; ax += agentindex
            shr ax, 4  ; ax /= 16

            and ax, 2  ; Mask to either 0 or 2
            dec ax     ; Decrement to either -1 or +1

            add [si-1], ax ; Add delta to current direction index

        nochdir:

        loop agentloop

    ; Loop over framebuffer and fade pixels down to zero
    xor di, di
    mov cx, 320*200
    fadeloop:
        mov al, [es:di] ; al = fb[index]

        test al, al
        je zero         ; if (al > 0)
        dec al          ;     al -= 1
        zero:

        stosb           ; fb[index++] = al

        test di, di
        jne fadeloop


    ; Check keyboard, exit on ESC
    in al,0x60
    dec al
    jnz frameloop

ret



; Movement vectors represented as framebuffer offsets
directions:
;  5 6 7
;  4   0
;  3 2 1
    dw  1
    dw  320+1
    dw  320
    dw  320-1
    dw -1
    dw -320-1
    dw -320
    dw -320+1

; Timing mask for melody tracks
track_timing_masks:
    db 0b00000000 ; Strings
    db 0b00000011 ; Lead
    db 0b00010111 ; Voice

; Current sequence position for each track
track_positions:
    db notes.length-1
    db 3
    db 2

; Note sequence, shared between all tracks
notes:
    db ROOT_NOTE +  22
    db ROOT_NOTE +  19
    db ROOT_NOTE +  17
    db ROOT_NOTE +  15
    db ROOT_NOTE +  14
    db ROOT_NOTE + -12
    db ROOT_NOTE +  10
    db ROOT_NOTE +  7
    db ROOT_NOTE +  2
    db ROOT_NOTE + -12
    db ROOT_NOTE + -24
    db ROOT_NOTE +  0

notes.length: equ $ - notes

; Static MIDI messages to be sent every quarter note
midicmds:
    ; Trigger kick drum
    db 0x99 ; Note on, channel 10 (drums)
    db   36 ; Note (kick)
    db 0x7f ; Velocity

    ; Setup instruments
    db 0xc0, 50 ; Change instrument on channel 0 (Synth Strings 1)
    db 0xc1, 38 ; Change instrument on channel 1 (Synth Bass 1)
    db 0xc2, 53 ; Change instrument on channel 2 (Voice Oohs)
 
    ; All notes off on string channel
    db 0xb0 ; Channel mode message, channel 0 (strings)
    db 123  ; All notes off
transpositions:
    db 0 ; Both the last byte of the last midi message, and the first byte in the transposition array
midicmds.length: equ $ - midicmds
    db -5, 5, 7

; Agent buffer
%ifdef CLEAR_AGENT_MEMORY
    agents:
%else
    ; This is a (poor) attempt to find some memory area that is unlikely to have been touched before us in a fresh dosbox session,
    ; which would otherwise affect the initial state of the simulation in an unpredictable way.
    ; In compatibility mode, we just spend the extra few bytes initializing the agent memory to zero.
    agents: equ -MAX_AGENTS*AGENT_SIZE - 0x1000
%endif
