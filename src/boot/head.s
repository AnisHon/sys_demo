[bits 32]
global _start, _gdt, _idt
extern main, _printk


; linux会将这段代码将被覆盖为页目录，但是我选择使用页表自映射
; 该程序不会检测数学协处理器，现代处理器有更快的SIMD AVX指令集，且全线兼容x87
; 对于DMA或其他将采用伙伴系统进行物理内存分配，所以需要流出充足的静态内存实现伙伴系统
; 系统段设在 0xC0000000，占据1/4空间，前3/4为用户空间
; 该段在启动时所有标签的绝对地址都是0xC0000000开头的，在加载页表时要格外小心
section .head
_start:
    mov ax, 0x10                ; 保险起见重新设置
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax              
    ; esp 可以先暂时使用，后续可能需要将栈设置到方便切换的地方

; 检查是否存在循环a20
; linux内核非常有意思的一段代码，写入eax检查是否相等，防止偶然事件，采用循环递增的方法
; 利用8086的环回地址，如果没有开启A20会卡死在这里
    xor eax, eax
a20_loop:
    inc eax 
    mov [0], eax 
    cmp eax, [0x100000]
    je a20_loop


    call setup_pt
    jmp dword 0x08:into_high

into_high:
    mov esp, 0xC009FC00             ; 暂时这样设置 0x9fc00(BIOS拓展区首地址)
    call setup_idt
    call setup_gdt

; 进入main函数，这三个0是C的main默认参数
    push 0
    push 0
    push 0
    push no_return              ; 兜底代码，如果main返回，将会进入死循环
    push main                   ; 直接用ret 结束自己的控制权
    ret

no_return:
    hlt                         ; 方便定位是哪里的死循环

; 不能确定中断原子8259A还是内部中断，所以选择直接忽略，不发送EOI
; 必须保证所有的内部异常不会来到这个处理器，内部错误会压入ERROR CODE导致错误
int_msg: db "Unknown interrupt", 10, 0 ; 使用C风格字符串，结尾换行
ignore_int:
    pushad
    push ds
    push fs
    push gs

    mov ax, 0x10
    mov ds, ax
    mov gs, ax
    mov fs, ax

    ; c dec 调用协定
    push int_msg
    call _printk
    add esp, 4      ; 清理栈帧

    pop gs
    pop fs
    pop ds
    popad       
    iret  

; 过于简单的函数
setup_gdt:
    lgdt [gdt_descr]
    ret

; 初始化IDT，全部处理器都设置为ignore_int
setup_idt:              
    lea edx, ignore_int
    mov eax, 0x00080000         
    mov ax, dx                  ; 小端机 内存排布 先地址后选择子
    mov dx, 0x8E00              ; 小端机 内存排布 先属性再地址， 0x8E -> P 1 ; DPL 00 ; 01110(IDT固定标记) 

    lea edi, _idt
    mov ecx, 256                ; 256 个中断

.do_fill_idt:
    mov [edi], eax
    mov [edi + 4], edx
    add edi, 8
    loop .do_fill_idt
    
    lidt [idt_descr]
    ret
; 0001 0000 0111

; 手动设置三个页目录映射，和1MB的页表映射
setup_pt:
    mov eax, pdt - $$               ; 只能手动算偏移 
    mov ebx, pg - $$                ; 只能手动算偏移
    or ebx, 0x3                     ; US=0  RW=1 P=1
    mov [eax], ebx
    mov [eax + 4 * 768], ebx

    mov ebx, eax
    or ebx, 0x3
    mov [eax + 4 * 1023], ebx

    mov ebx, pg - $$            ; 只能手动算偏移
    xor edi, edi
    mov ecx, 512
    mov eax, 0x3

.setup_pte:
    mov [ebx + 4 * edi], eax
    add eax, 0x00001000
    inc edi
    loop .setup_pte

    mov eax, pdt - $$               ; 只能手动算偏移 
    mov cr3, eax                ; 加载寄存器

    mov eax, cr0
    or eax, 0x80000000      
    mov cr0, eax                ; 开启分页

    ret



gdt_descr:
    dw 256 * 8 - 1
    dd _gdt

idt_descr:
    dw 256 * 8 - 1
    dd _idt


; 总共256个gdt用处其实不大，这个内核设计不用LDT和TSS，所以无LDT，只有一个TSS
; 该描述符和 setup.s 的描述符没有区别，都是4GB寻址空间
_gdt:
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
    times 252 dq 0

; IDT空间，所有IDT都将获得默认处理器
_idt:
    times 256 dq 0

; 为操作系统预留最多4MB空间，对齐到 4KB 边界
section .data
    align 4096            
    pdt:      
        times 4096 db 0
    align 4096    
    pg:           
        times 4096 db 0    
    
