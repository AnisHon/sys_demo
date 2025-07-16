[bits 16]

; 放弃在实模式下读取操作系统，在保护模式下直接自己写32位LBA驱动

SETUPLEN equ 4
BOOTSEG equ 0x07c0
INITSEG equ 0x9000
SETUPSEG equ 0x9020

SECTION bootsect
    mov ax, BOOTSEG
    mov ds, ax
    mov ax, INITSEG
    mov es, ax
    xor di, di
    xor si, si
    mov cx, 256
    rep movsw 

    jmp INITSEG:go          ; 为后续腾出空间

go:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFF00          ; 0x9ff00


load_setup:
    mov dx, 0x0080
    mov cx, 0x0002
    mov bx, 0x0200
    mov ax, 0x0200 + SETUPLEN 
    int 0x13
    jc die

ok_load_setup:
    mov ax, INITSEG
    mov es, ax

    mov ah, 0x41      ; 功能号：检测扩展功能
    mov bx, 0x55AA    ; 魔术字
    mov dl, 0x80      ; 驱动器号（0x80=第一块硬盘）
    int 0x13
    jc  die           ; 若CF=1，不支持LBA
    cmp bx, 0xAA55    ; 检查BX是否反转
    jne die

    
; 获取光标，打印信息
    mov ah, 0x03
    xor bh, bh
    int 0x10
    
    mov cx, 24
    mov bx, 0x0007
    mov bp, msg1
    mov ax, 0x1301
    int 0x10

    jmp SETUPSEG:0

die:
    jmp $


msg1:
    db 13, 10
    db "Loading system ...."
    db 13, 10, 13, 10 ; 回车换行

times 510-($-$$) db 0
db 0x55, 0xAA

