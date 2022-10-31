﻿using MonoMod.Core.Utils;
using MonoMod.Utils;
using System;

namespace MonoMod.Core.Platforms.Architectures {
    internal sealed class x86Arch : IArchitecture {
        public ArchitectureKind Target => ArchitectureKind.x86;

        public ArchitectureFeature Features => ArchitectureFeature.None;

        private BytePatternCollection? lazyKnownMethodThunks;
        public unsafe BytePatternCollection KnownMethodThunks => Helpers.GetOrInit(ref lazyKnownMethodThunks, &CreateKnownMethodThunks);

        private static BytePatternCollection CreateKnownMethodThunks() {
            const ushort An = BytePattern.SAnyValue;
            const ushort Ad = BytePattern.SAddressValue;
            //const byte Bn = BytePattern.BAnyValue;
            //const byte Bd = BytePattern.BAddressValue;

            if (PlatformDetection.Runtime is RuntimeKind.Framework or RuntimeKind.CoreCLR) {
                return new BytePatternCollection(
                    // .NET Framework
                    new(new(AddressKind.Rel32, 0x10), // UNKNOWN mustMatchAtStart
                        // mov ... (mscorlib_ni!???)
                        0xb8, An, An, An, An,
                        // nop
                        0x90,
                        // call ... (clr!PrecodeRemotingThunk)
                        0xe8, An, An, An, An,
                        // jmp {DELTA}
                        0xe9, Ad, Ad, Ad, Ad),

                    // .NET Core
                    new(new(AddressKind.Rel32, 5), mustMatchAtStart: true,
                        // jmp {DELTA}
                        0xe9, Ad, Ad, Ad, Ad,
                        // pop rdi
                        0x5f),

                    // PrecodeFixupThunk (CLR 4+)
                    new(new(AddressKind.PrecodeFixupThunkRel32, 5), mustMatchAtStart: true,
                        // call {PRECODE FIXUP THUNK}
                        0xe8, Ad, Ad, Ad, Ad,
                        // pop rsi(?) (is this even consistent?)
                        0x5e),

                    // PrecodeFixupThunk (CLR 2)
                    new(new(AddressKind.PrecodeFixupThunkRel32, 5), mustMatchAtStart: true,
                        // call {PRECODE FIXUP THUNK}
                        0xe8, Ad, Ad, Ad, Ad,
                        // int 3
                        0xcc),

                    null
                );
            } else {
                // TODO: Mono
                return new();
            }
        }

        private sealed class Abs32Kind : DetourKindBase {
            public static readonly Abs32Kind Instance = new();

            public override int Size => 1 + 4 + 1;

            public override int GetBytes(IntPtr from, IntPtr to, Span<byte> buffer, object? data, out IDisposable? allocHandle) {
                buffer[0] = 0x68; // PUSH imm32
                Unsafe.WriteUnaligned(ref buffer[1], Unsafe.As<IntPtr, int>(ref to));
                buffer[5] = 0xc3; // RET

                allocHandle = null;
                return Size;
            }

            public override bool TryGetRetargetInfo(NativeDetourInfo orig, IntPtr to, int maxSize, out NativeDetourInfo retargetInfo) {
                // we can always trivially retarget an abs32
                retargetInfo = orig with { To = to };
                return true;
            }

            public override int DoRetarget(NativeDetourInfo origInfo, IntPtr to, Span<byte> buffer, object? data,
                out IDisposable? allocationHandle, out bool needsRepatch, out bool disposeOldAlloc) {
                needsRepatch = true;
                disposeOldAlloc = true;
                // the retarget logic for rel32 is just the same as the normal patch
                // the patcher should repatch the target method with the new bytes, and dispose the old allocation, if present
                return GetBytes(origInfo.From, to, buffer, data, out allocationHandle);
            }
        }

        public NativeDetourInfo ComputeDetourInfo(IntPtr from, IntPtr to, int maxSizeHint = -1) {
            x86Shared.FixSizeHint(ref maxSizeHint);

            if (x86Shared.TryRel32Detour(from, to, maxSizeHint, out var rel32Info))
                return rel32Info;

            if (maxSizeHint < Abs32Kind.Instance.Size) {
                MMDbgLog.Warning($"Size too small for all known detour kinds; defaulting to Abs32. provided size: {maxSizeHint}");
            }

            return new(from, to, Abs32Kind.Instance, null);
        }

        public int GetDetourBytes(NativeDetourInfo info, Span<byte> buffer, out IDisposable? allocationHandle) {
            return DetourKindBase.GetDetourBytes(info, buffer, out allocationHandle);
        }

        public NativeDetourInfo ComputeRetargetInfo(NativeDetourInfo detour, IntPtr to, int maxSizeHint = -1) {
            x86Shared.FixSizeHint(ref maxSizeHint);
            if (DetourKindBase.TryFindRetargetInfo(detour, to, maxSizeHint, out var retarget)) {
                // the detour knows how to retarget itself, we'll use that
                return retarget;
            } else {
                // the detour doesn't know how to retarget itself, lets just compute a new detour to our new target
                return ComputeDetourInfo(detour.From, to, maxSizeHint);
            }
        }

        public int GetRetargetBytes(NativeDetourInfo original, NativeDetourInfo retarget, Span<byte> buffer,
            out IDisposable? allocationHandle, out bool needsRepatch, out bool disposeOldAlloc) {
            return DetourKindBase.DoRetarget(original, retarget, buffer, out allocationHandle, out needsRepatch, out disposeOldAlloc);
        }


        public ReadOnlyMemory<IAllocatedMemory> CreateNativeVtableProxyStubs(IntPtr vtableBase, int vtableSize) {
            throw new NotImplementedException();
        }
    }
}
