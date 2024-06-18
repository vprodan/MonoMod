using MonoMod.Core.Utils;
using MonoMod.Utils;
using System;

namespace MonoMod.Core.Platforms.Architectures
{
    internal sealed class Arm64Arch : IArchitecture
    {
        public ArchitectureKind Target => ArchitectureKind.Arm64;
        public ArchitectureFeature Features => ArchitectureFeature.Immediate64;

        private BytePatternCollection? lazyKnownMethodThunks;

        public BytePatternCollection KnownMethodThunks => Helpers.GetOrInit(ref lazyKnownMethodThunks, CreateKnownMethodThunks);

        public IAltEntryFactory AltEntryFactory => null!;

        private readonly ISystem System;

        public Arm64Arch(ISystem system)
        {
            System = system;
        }

        public NativeDetourInfo ComputeDetourInfo(IntPtr from, IntPtr target, int maxSizeHint)
        {
            // Should work for arm64 as well
            x86Shared.FixSizeHint(ref maxSizeHint);

            if (maxSizeHint < BranchRegisterKind.Instance.Size)
            {
                MMDbgLog.Warning($"Size too small for all known detour kinds! Defaulting to BranchRegister. provided size: {maxSizeHint}");
            }

            return new(from, target, BranchRegisterKind.Instance, null);
        }

        public int GetDetourBytes(NativeDetourInfo info, Span<byte> buffer, out IDisposable? allocationHandle)
        {
            return DetourKindBase.GetDetourBytes(info, buffer, out allocationHandle);
        }

        public NativeDetourInfo ComputeRetargetInfo(NativeDetourInfo detour, IntPtr target, int maxSizeHint = -1)
        {
            // Should work for arm64 as well
            x86Shared.FixSizeHint(ref maxSizeHint);

            if (DetourKindBase.TryFindRetargetInfo(detour, target, maxSizeHint, out var retarget))
            {
                // the detour knows how to retarget itself, we'll use that
                return retarget;
            }

            // the detour doesn't know how to retarget itself, lets just compute a new detour to our new target
            return ComputeDetourInfo(detour.From, target, maxSizeHint);
        }

        public int GetRetargetBytes(NativeDetourInfo original, NativeDetourInfo retarget, Span<byte> buffer,
            out IDisposable? allocationHandle, out bool needsRepatch, out bool disposeOldAlloc)
        {
            return DetourKindBase.DoRetarget(original, retarget, buffer, out allocationHandle, out needsRepatch, out disposeOldAlloc);
        }

        public ReadOnlyMemory<IAllocatedMemory> CreateNativeVtableProxyStubs(IntPtr vtableBase, int vtableSize)
        {
            ReadOnlySpan<byte> stubData = [
                0x00, 0x04, 0x40, 0xF9, // ldr x0, [x0, #8]
                0x08, 0x00, 0x40, 0xF9, // ldr x8, [x0]
                0x8F, 0x00, 0x00, 0x18, // ldr w15, _offset
                0x08, 0x01, 0x0F, 0x8B, // add x8, x8, x15
                0x08, 0x01, 0x40, 0xF9, // ldr x8, [x8]
                0x00, 0x01, 0x1F, 0xD6, // br x8
                0x00, 0x00, 0x00, 0x00, // _offset: .word 0x0
            ];

            return Shared.CreateVtableStubs(System, vtableBase, vtableSize, stubData, 24, true);
        }

        public IAllocatedMemory CreateSpecialEntryStub(IntPtr target, IntPtr argument)
        {
            // CreateNativeExceptionHelper should be implemented first

            throw new NotImplementedException();
        }

        private static BytePatternCollection CreateKnownMethodThunks()
        {
            const ushort An = BytePattern.SAnyValue;
            const ushort Ad = BytePattern.SAddressValue;
            const byte Bn = BytePattern.BAnyValue;
            const byte Bd = BytePattern.BAddressValue;

            if (PlatformDetection.Runtime is RuntimeKind.Framework or RuntimeKind.CoreCLR)
            {
                return new BytePatternCollection(
                    new BytePattern(
                        new AddressMeaning(AddressKind.Abs64),
                        true,
                        0x48, 0x85, 0xc9, 0x48
                    )
                );
            }
            else
            {
                // TODO: Mono
                return new();
            }
        }

        private sealed class BranchRegisterKind : DetourKindBase
        {
            public static readonly BranchRegisterKind Instance = new();

            public override int Size => 4 + 4 + 8;

            public override int GetBytes(IntPtr from, IntPtr to, Span<byte> buffer, object? data, out IDisposable? allocHandle)
            {
                // ldr x8, _target
                buffer[0] = 0x48;
                buffer[1] = 0x00;
                buffer[2] = 0x00;
                buffer[3] = 0x58;
                // br x8
                buffer[4] = 0x00;
                buffer[5] = 0x01;
                buffer[6] = 0x1F;
                buffer[7] = 0xD6;
                // _target: .quad 0x0
                Unsafe.WriteUnaligned(ref buffer[8], (ulong)to);

                allocHandle = null;
                
                MMDbgLog.Trace($"Detouring arm64 from 0x{from:X16} to 0x{to:X16}");

                return Size;
            }

            public override bool TryGetRetargetInfo(NativeDetourInfo orig, IntPtr to, int maxSize, out NativeDetourInfo retargetInfo)
            {
                // we can always trivially retarget an abs64 detour (change the absolute constant)
                retargetInfo = orig with { To = to };
                return true;
            }


            public override int DoRetarget(NativeDetourInfo origInfo, IntPtr to, Span<byte> buffer, object? data,
                out IDisposable? allocationHandle, out bool needsRepatch, out bool disposeOldAlloc)
            {
                needsRepatch = true;
                disposeOldAlloc = true;
                // the retarget logic for rel32 is just the same as the normal patch
                // the patcher should re-patch the target method with the new bytes, and dispose the old allocation, if present
                return GetBytes(origInfo.From, to, buffer, data, out allocationHandle);
            }
        }
    }
}