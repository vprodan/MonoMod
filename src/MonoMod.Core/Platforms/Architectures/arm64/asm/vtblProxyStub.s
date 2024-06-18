// ./get-bytes.sh vtblProxyStub

.text
.global _main

_main:
    // brk #0
    ldr x0, [x0, #8]
    ldr x8, [x0]
    ldr w15, _offset
    add x8, x8, x15
    ldr x8, [x8]
    br x8
    
_offset: .word 0x0