[bits 16]
SYSSIZE equ 512
INITSEG equ 0x9000
SETUPSEG equ 0x9020

section setup vstart=0x90200
    mov ax, INITSEG     ; 段寄存器是0x9000
    mov ds, ax

; 获取光标位置
; 位置 0x90000 -> 2 bytes
    mov ah, 0x03
    xor bh, bh
    int 0x10
    mov [0], dx

; 获取内存大小 忽略了一些不可用大小会比实际小一点点
; 位置 0x90002 -> 4 bytes 
    call get_memsize
    mov [2], eax

; 无需移动内核，内核进入保护模式后加载
; 为保护模式做准备
    cli
    mov ax, INITSEG
    mov ds, ax
    lgdt [gdt_48]
    lidt [idt_48]

; 开启A20，使用fast A20而不是键盘代理8042
    call enable_a20_fast

; 设置intel 8259A IPC，和linux v0.11几乎一致
   
    ; 主片
    mov dx, 0x20
    mov al, 0x11
    out dx, al              ; icw 1
    jmp $+2                 ; 延迟
    
    mov dx, 0x21
    mov al, 0x20            
    out dx, al              ; icw 2
    jmp $+2                 ; 延迟

    mov al, 0x4             
    out dx, al              ; icw 3 00000100
    jmp $+2                 ; 延迟

    mov al, 0x1             
    out dx, al              ; icw 4
    jmp $+2                 ; 延迟

    ; 从片
    mov dx, 0xA0
    mov al, 0x11
    out dx, al              ; icw 1
    jmp $+2                 ; 延迟

    mov dx, 0xA1            
    mov al, 0x28            
    out dx, al              ; icw 2
    jmp $+2                 ; 延迟

    mov al, 0x2             
    out dx, al              ; icw 3 
    jmp $+2                 ; 延迟

    mov al, 0x1             
    out dx, al              ; icw 4
    jmp $+2                 ; 延迟

    ; ocw 1 设置屏蔽字 0xFF
    mov dx, 0x21
    mov al, 0xFF
    out dx, al
    jmp $+2                 ; 延迟

    mov dx, 0xA1
    out dx, al  

; 开启保护模式
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax 

; 跳转保护模式32位代码
    jmp dword 0x8:load_system       ; 0x8 00010000 -> Selector 1, GDT(TI=0), SUPERVISOR(RPL=00)

die:
    jmp $

; 返回内存大小结果放到eax里
get_memsize:
    mov bp, sp          ; 在栈中分配内存
    xor ebx, ebx        ; 初始偏移0
    sub sp, 24          ; 分配24个比特
    mov di, sp          ; 输出地址
    mov ax, ss          ; 输出地址定位到栈段
    mov es, ax          
    xor esi, esi        ; 临时变量存放最大的内存块
.loop_e820:             ; e820中断
    mov eax, 0xe820
    mov edx, 0x534D4150
    mov ecx, 24
    int 0x15            ; 错误处理
    jc die 
    cmp eax, 0x534D4150
    jne die

    add esi, [es:di + 8]    ; esi += mem
    test ebx, ebx           ; 判断是否结束
    jnz .loop_e820          
    
    mov sp, bp
    mov eax, esi            ; 返回参数，没有动sp，清理栈帧返回
    ret

enable_a20_fast:
    in al, 0x92        ; 读取当前值
    test al, 2         ; 检查是否已开启
    jnz .done          ; 如果已经开启，直接返回
    or al, 2           ; 设置 bit 1（开启 A20）
    and al, 0xFE       ; 清除 bit 0（避免意外复位）
    out 0x92, al       ; 写入端口
.done:
    ret


gdt:
    dd 0x00000000
    dd 0x00000000

    ; 段界限 4GB(FFFFF * 4K)
    ; 段基址 0x00000000
    ; 存在, DPL 0, 非系统段, 只执行可读,  4K颗粒度，32位段
    dw 0xFFFF      
    dw 0x0000      ; 段基址（低16位）
    db 0x00        ; 段基址（中8位）
    db 0x9A        ; P=1, DPL=00, S=1（非系统段）, Type=1010（可执行/可读）
    db 0xCF        ; G=1（4KB粒度）, D/B=1（32位段）, L=0, AVL=0, 段界限（高4位=0xF）
    db 0x00        ; 段基址（高8位）

    ; 段界限 4GB(FFFFF * 4K)
    ; 段基址 0x00000000
    ; 存在, DPL 0, 非系统段, 可读写,  4K颗粒度，32位段
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92        ; P=1, DPL=00, S=1 （非系统段）, Type=0010（可读/可写）
    db 0xCF
    db 0x00

idt_48:
    dw 0
    dd 0

gdt_48:
    dw 0x800
    dd gdt 


[bits 32]
; 此时已经进入保护模式，使用32位架构编译代码
; 此时cs为8，ds ss es 必须手动设置
; 加载系统内核直接放到0
load_system:
    mov ax, 0x10                ; 0x10 00010000 -> Selector 2, GDT(TI=0), SUPERVISOR(RPL=00)
    mov ss, ax
    mov ds, ax
    mov esp, 0x9fc00            ; 这是低端1MB内存能使用的最大地址，向下可能触碰到EBDA
    mov eax, 5
    mov ebx, 0
    mov ecx, SYSSIZE
    call read_disk

    jmp 0                       ; 进入内核


; eax=LBA selector
; ebx=output address
; ecx=selector count
read_disk:
    mov esi, eax
    mov edi, ecx

    ; selector
    mov al, cl
    mov dx, 0x1f2
    out dx, al  

    ; LBA
    mov eax, esi
    mov dx, 0x1f3   ; low
    out dx, al


    mov cl, 8
    mov dx, 0x1f4   ; mid
    shr eax, cl
    out dx, al

    mov dx, 0x1f5   ; high
    shr eax, cl     
    out dx, al  

    ; device
    mov dx, 0x1f6

    shr eax, cl     ; 23-27
    and al, 0xf
    
    or al, 0xe0     ; 1110
    out dx, al

    ; command
    mov dx, 0x1f7
    mov al, 0x20    ; 00100000
    out dx, al
    
    ; polling 
    .status_ready_polling:
        in al, dx
        and al, 0x88
        cmp al, 0x08
        jnz .status_ready_polling
    
    xor ecx, ecx
    mov eax, edi
    mov edx, 256    ; count * 512 / 4
    mul edx
    mov ecx, eax

    mov dx, 0x1f0
    
    .read:
        in ax, dx
        mov [ebx], ax
        add ebx, 2  
        nop 
        loop .read
    ret