// ./get-bytes.sh detour

.text
.global _main

_main:
    ldr x8, _target
    br x8

_target: .quad 0x0