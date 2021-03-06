;;;;;;;;;;; Macros ;;;;;;;;;;;
%macro init_func 0
  push ebp           ; save previous value of ebp
  mov ebp, esp       ; set ebp to point to myFunc frame
%endmacro

%macro return_from_func 0
  mov esp, ebp      ; "delete" local variables of myFunc
  pop ebp           ; restore previous value of ebp
  RET               ; return to the caller
%endmacro

%macro print 2       ; call printf
  pusha
  push dword %1
  push dword %2
  call printf
  add esp, 8
  popa
%endmacro

;read 1 byte from file
%macro read_byte 0
    pusha
    mov eax, 3
    mov ebx, dword [FD]
    mov ecx, BUFF
    mov edx, 1
    int 0x80
    popa
%endmacro

%macro call_malloc 2
  pusha
  push %1
  call malloc
  mov %2, eax
  add esp, 4
  popa
%endmacro

%macro allocate_co 4
  pusha
  call_malloc CO_SIZE, %1
  mov eax, %1
  mov dword [eax+CODEP], %2
  mov dword [eax+FLAGSP], 0
  mov dword [eax+ARG1], %3
  mov dword [eax+ARG2], %4
  mov ecx, eax
  add ecx, CO_SIZE
  mov dword [eax+SPP], ecx
  popa
%endmacro


STKSZ equ 16*1024        ; co-routine stack size
CODEP equ 0              ; offset of pointer to co-routine function in co-routine structure
FLAGSP equ 4             ; offset of pointer to flags co-routine structure
ARG1  equ 8
ARG2 equ 12
SPP equ 16               ; offset of pointer to co-routine stack in co-routine structure
CO_SIZE equ STKSZ+20
BUFF_SIZE equ 2

;;;;;;;;;;; Read only data ;;;;;;;;;;;
section .rodata
  align 16
  global FORMAT_INT
  FORMAT_INT: db "%d", 10,0      ; int formating string
  FORMAT_STRING:  db "%s",10, 0      ; string formating string
  FORMAT_CHAR:  db "%c", 10,0      ; char formating string
  ERR_ARGS: db "Error incorrect args, expected: [optional -d] <filename> <length> <width> <t> <k>"
  TEN: dd 10
  CORS: dd 0

;;;;;;;;;;; Initialized data ;;;;;;;;;;;
section .data
  align 16
  FD: dd -1
  global DEBUG
  DEBUG: dd 0
  global WorldWidth
  WorldWidth: dd 0
  global WorldLength
  WorldLength: dd 0
  global NumGen
  NumGen: dd 0
  global NumCo
  NumCo: dd 0
  global NumCells
  NumCells: dd 0
  global PrintRate
  PrintRate: dd 0
  global state
  state: dd 0
  global cors
  cors: dd 0
  global cells
  cells: dd 0
  global secheduler
  scheduler: dd 0
  global printer
  printer: dd 0
  x: dd 0
  y: dd 0
  cur: dd 0
  current_cell: dd 0

;;;;;;;;;;; Uninitialized data ;;;;;;;;;;;
section .bss
  align 16
  CURR: resd 1
  SPT: resd 1        ; temporary stack pointer variable
  SPMAIN: resd 1     ; stack pointer of main
  STK: resb STKSZ
  STATE: resd 2
  STATE_CONT: resd 2
  BUFF: resb BUFF_SIZE

;;;;;;;;;;; CODE ;;;;;;;;;;;
section .text
  align 16
  extern printf
  extern fgets
  extern malloc
  extern free
  extern secheduler_func
  global build_structures
  global init_co_from_c
  global start_co_from_c
  global resume
  global end_co

build_structures:
  mov eax, [ebp+8]  ;get argc
  mov ebx, [ebp+12] ; get argv
  init_func
    ;check debug flag
    cmp eax, 7        ; if argc = 7 and argv[1] = -d then debug flag is on
    jne .no_debug
      mov ecx, dword [ebx + 4]      ; get argv[1]
      cmp byte [ecx], '-'
      jne .no_debug
      cmp byte [ecx+1], 'd'
      jne .no_debug
      mov dword [DEBUG], 1
      add ebx, 4
      dec eax

    .no_debug:
    ; check correct number of atgs
    cmp eax, 6        ; there needs to be 6 args
    je .open_file
      ; print an error and exit
      print ERR_ARGS, FORMAT_STRING
      mov eax, 1
      xor ebx, ebx
      int 80h

    .open_file:
      ;open the file for reading
      pusha
      mov eax, 5
      mov ebx, dword [ebx + 4]  ;get argv[2] (file name)
      mov ecx, 0          ;for read only access
      mov edx, 0777       ;read, write and execute by all
      int  0x80
      mov  [FD], eax
      popa

    ; set WorldLength
    push dword [ebx + 8]
    call atoi
    mov dword [WorldLength], eax

    ; set WorldWidth
    push dword [ebx + 12]
    call atoi
    mov dword [WorldWidth], eax

    ; set NumGen
    push dword [ebx + 16]
    call atoi
    mov dword [NumGen], eax

    ; set PrintRate
    push dword [ebx + 20]
    call atoi
    mov dword [PrintRate], eax

    ; set NumCells
    mov eax, dword [WorldLength]
    mul dword [WorldWidth]
    mov dword [NumCells], eax

    ; allocate state
    call_malloc eax, dword [state]; eax still holds NumCells

    mov ecx, 0
    mov edx, dword [state]

    ; read file into state
    .read_line:
      mov ebx, 0
      inc ecx
      .read_cell:
      test ecx, 1
      jz .even_line
        ; odd line
        read_byte       ; read state of the next cell as char
        push dword BUFF
        call atoi       ; convert to int
        mov byte [edx+ebx], al
        read_byte ; read through the deviding space char (" ")
        jmp .cell_done
      .even_line:
        read_byte       ; read through the deviding space char (" ")
        read_byte ; read state of the next cell as char
        push dword BUFF
        call atoi       ; convert to int
        mov byte [edx+ebx], al
      .cell_done:
        inc ebx
        cmp ebx, dword [WorldWidth]
        jnz .read_cell
      .seek_to_end_of_line:
        read_byte ; read through the deviding new line char
        cmp byte [BUFF], 10
        jnz .seek_to_end_of_line
      add edx, dword [WorldWidth]
      cmp ecx, dword [WorldLength]
      jnz .read_line

    ; allocate cors and set NumCo
    mov eax, dword [NumCells]
    add eax, 2
    mov dword [NumCo], eax
    shl eax, 2
    call_malloc eax, dword [cors]

    ; set cells
    mov ebx, dword[cors]
    add ebx, 8
    mov dword [cells], ebx

    ; allocate scheduler co-routine and set a pointer to it in cors
    mov ebx, dword[cors]  ; set ebx to point to start of cors
    mov ecx, dword[NumGen]
    mov edx, dword[PrintRate]
    allocate_co dword [ebx], secheduler_func, ecx, edx
    mov ecx, dword [ebx]
    mov dword [scheduler], ecx

    ; allocate printer co-routine and set a pointer to it in cors
    add ebx, 4
    mov ecx, dword[WorldLength]
    mov edx, dword[WorldWidth]
    allocate_co dword [ebx], printer_func, ecx, edx
    mov ecx, dword [ebx]
    mov dword[printer], ecx

    ; allocate space for all cell co-routines and set pointers to them in cors
    add ebx, 4
    mov edx, 0
    .next_row:
      mov ecx, 0
      .next_cell:
        ;print edx, FORMAT_INT
        allocate_co dword [ebx], cell_func, ecx, edx
        add ebx, 4
        add ecx, 1
        cmp ecx, dword [WorldWidth]
        jnz .next_cell
      inc edx
      cmp edx, dword [WorldLength]
      jnz .next_row
  return_from_func


atoi:
  init_func
    push ecx
    push edx
    push ebx
    mov ecx, dword [ebp+8]  ; Get argument (pointer to string)
    xor eax,eax
    xor ebx,ebx
  .atoi_loop:
    xor edx,edx
    cmp byte[ecx],0
    jz  .atoi_end
    imul dword [TEN]
    mov bl,byte[ecx]
    sub bl,'0'
    add eax,ebx
    inc ecx
    jmp .atoi_loop
  .atoi_end:
    pop ebx                 ; Restore registers
    pop edx
    pop ecx
  return_from_func


init_co_from_c:
  init_func
    mov ebx, dword [ebp+8] ; ebx contains the index of the co-routine to be initialized
    mov eax, dword [cors]
    mov ebx, dword [eax + 4*ebx]
    call co_init
  return_from_func



co_init:
    pusha
    bts dword [ebx+FLAGSP],0 ; test if already initialized
    jc .init_done
    mov eax, dword [ebx+CODEP] ; get initial PC
    mov [SPT], esp ; save original SP
    mov esp, dword [ebx+SPP] ; get initial SP
    push dword[ebx+ARG2]  ; push second argument
    push dword[ebx+ARG1]  ; push first argument
    push 0
    push 0
    mov ebp, esp ; also use as EBP
    push eax ; push initial "return" address (initial PC)
    pushfd ; push flags
    pushad ; push all other registers
    mov [ebx+SPP],esp ; save new SP in structure
    mov esp, [SPT] ; restore original SP
  .init_done:
    popa
    ret

start_co_from_c:
  init_func
  pusha
  mov dword[SPMAIN], esp
  mov ebx, dword[scheduler] ; get a pointer to the scheduler structure
  jmp do_resume

end_co:
  mov esp, dword [SPMAIN]
  popa
  return_from_func


resume:       ;save caller state
  pushfd
  pushad
  mov edx, dword [CURR]
  mov dword [edx+SPP], esp ; save current SP

do_resume:  ; load SP in order to resume co-routine
  mov esp, dword [ebx+SPP]
  mov [CURR], ebx
  popad   ; restore resumed co-routine state
  popfd
  ret     ; "return" to resumed co-routine



check_neighbors:
  init_func
  mov ebx, [ebp+8]  ;get neighbor
  cmp ebx, 1  ;if neighbor is alive
  jnz .is_dead
  add eax, 1
  .is_dead:
  ret

calc_neighbor:
init_func
  mov ebx, [esp+8]                ; x+1 ||  x-1
  mov eax, dword[x] 
  add eax, ebx
  mov ebx, dword[WorldWidth]
  idiv ebx                        ; (x+1 || x-1) modulu width
  mov ecx, edx
b7:

  mov edx, [esp+12]               ; y+1  || y-1
  mov eax, dword[y]
  add eax, edx
  mov edx, dword[WorldLength]
  idiv edx                        ; (y+1 || y-1) modulu length
b8:
  mov eax, edx                    ; save y modulu
  mov ebx, dword[WorldWidth]
  mul ebx                         ; [(y+1 || y-1) modulu (length)] * width
  add eax, ecx                    ; {[(y+1 || y-1) modulu (length)] * width} + [(x+1 || x-1) modulu (width)]
  push eax
  call check_neighbors
b9:
  ret


cell_func:
  mov edx, [ebp+8]  ;get x
  mov eax, [ebp+12] ; get y
  mov dword[x], edx
  mov dword[y], eax
  mov ebx, dword[WorldWidth] ; get width
b1:
  push edx
  mul ebx ; (y-1) * width --> get row
  pop edx
  add eax, edx ;((y-1) * width) + x --> get core
b2:
  mov ecx, [state+eax] ; get current cell content
  mov dword[cur], ecx ; save current cell content
b3:
  mov dword[current_cell], eax ; save current cell

.neighbors:
  mov edx, dword[y]
  test edx, 1
  jz .is_even

  .is_odd:
    mov eax, 1
    mov ebx, -1
    push ebx
    push eax
    call calc_neighbor

    mov eax, 1
    mov ebx, 1
    push ebx
    push eax
    call calc_neighbor
    jmp .all

  .is_even:
    mov eax, -1
    mov ebx, -1
    push ebx
    push eax
    call calc_neighbor

    mov eax, -1
    mov ebx, 1
    push ebx
    push eax
    call calc_neighbor
    jmp .all

  .all:
    mov eax, 0
    mov ebx, -1
    push ebx
    push eax
    call calc_neighbor

    mov eax, 0
    mov ebx, 1
    push ebx
    push eax
    call calc_neighbor

    mov eax, 1
    mov ebx, 0
    push ebx
    push eax
    call calc_neighbor

    mov eax, -1
    mov ebx, 0
    push ebx
    push eax
    call calc_neighbor

  cmp dword[cur], 1
  jnz .dead
  cmp eax, 4 ; if cell is alive
  jz .will_be_alive
  cmp eax, 3
  jz .will_be_alive
  mov dword[cur], 0
  jmp .end
  .will_be_alive:
  mov dword[cur], 1
  jmp .end
  .dead: ;if cell is dead
  cmp eax, 2
  jnz .will_be_dead
  mov dword[cur], 1
  jmp .end
  .will_be_dead:
  mov dword[cur], 0
  mov ebx, dword[scheduler]
  call resume
  .end:
  mov ecx, dword[cur]
  mov edx, dword[current_cell]
  mov dword[state+edx], ecx
  mov ebx, dword[scheduler]
  call resume
  jmp cell_func

printer_func:
