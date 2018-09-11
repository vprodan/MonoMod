﻿using System;
using System.Reflection;
using System.Reflection.Emit;
using System.Linq.Expressions;
using MonoMod.Utils;
using System.Collections.Generic;
using Mono.Cecil;

namespace MonoMod.RuntimeDetour.HookGen {
    public sealed class HookEndpoint<T> where T : class {

        // This delegate will be cloned into the wrapper inside of the generated assembly.
        public delegate void ILManipulator(Mono.Cecil.Cil.MethodBody body, Mono.Cecil.Cil.ILProcessor il);

        // This code will be additionally generated in the wrapper inside of the generated assembly.
        /*
        public event ILManipulator IL {
            add {
                Modify(value);
            }
            remove {
                Modify(value);
            }
        }
        */

        internal ulong ID = 0;
        internal readonly MethodBase Method;
        private readonly Dictionary<Delegate, Stack<Hook>> HookMap = new Dictionary<Delegate, Stack<Hook>>();
        private readonly Queue<QueueEntry> Queue = new Queue<QueueEntry>();

        internal HookEndpoint(MethodBase method) {
            Method = method;
        }

        internal HookEndpoint(HookEndpoint<T> prev) {
            Method = prev.Method;
            HookMap.AddRange(prev.HookMap);
            Queue.EnqueueRange(prev.Queue);
        }

        public void Add(Delegate hookDelegate) {
            // Note: This makes the current instance unusable for any further operations.
            HookEndpointManager.Verify(this)._Add(hookDelegate);
        }
        internal void _Add(Delegate hookDelegate) {
            if (hookDelegate == null)
                return;

            Stack<Hook> hooks;
            if (!HookMap.TryGetValue(hookDelegate, out hooks))
                HookMap[hookDelegate] = hooks = new Stack<Hook>();

            hooks.Push(new Hook(Method, hookDelegate));
        }

        public void Remove(Delegate hookDelegate) {
            // Note: This makes the current instance unusable for any further operations.
            HookEndpointManager.Verify(this)._Remove(hookDelegate);
        }
        internal void _Remove(Delegate hookDelegate) {
            if (hookDelegate == null)
                return;

            // Note: A hook delegate can be applied multiple times.
            // The following code removes the last hook of that delegate type.
            Stack<Hook> hooks;
            if (!HookMap.TryGetValue(hookDelegate, out hooks))
                return;

            hooks.Pop().Dispose();

            if (hooks.Count == 0)
                HookMap.Remove(hookDelegate);
        }

        public void Modify(Delegate callback) {
            // Note: This makes the current instance unusable for any further operations.
            HookEndpointManager.Verify(this)._Modify(callback);
        }
        internal void _Modify(Delegate callback) {
            if (callback == null)
                return;

            // TODO: HookEndpoint IL manipulation!
            // callback.DynamicInvoke(body, il);
        }

        public void Unmodify(Delegate callback) {
            // Note: This makes the current instance unusable for any further operations.
            HookEndpointManager.Verify(this)._Unmodify(callback);
        }
        internal void _Unmodify(Delegate callback) {
            // Note: This makes the current instance unusable for any further operations.
            HookEndpointManager.Verify(this);

            if (callback == null)
                return;

            // TODO: HookEndpoint IL manipulation!
        }

        internal void ApplyQueue() {
            foreach (QueueEntry entry in Queue) {
                switch (entry.Operation) {
                    case QueueOperation.Add:
                        _Add(entry.Delegate);
                        break;
                    case QueueOperation.Remove:
                        _Remove(entry.Delegate);
                        break;
                    case QueueOperation.Modify:
                        _Modify(entry.Delegate);
                        break;
                    case QueueOperation.Unmodify:
                        _Unmodify(entry.Delegate);
                        break;
                }
            }
            Queue.Clear();
        }

        public static HookEndpoint<T> operator +(HookEndpoint<T> prev, T hookDelegate) {
            HookEndpoint<T> next = new HookEndpoint<T>(prev);
            next.Queue.Enqueue(new QueueEntry(QueueOperation.Add, hookDelegate as Delegate));
            return next;
        }
        public static HookEndpoint<T> operator -(HookEndpoint<T> prev, T hookDelegate) {
            HookEndpoint<T> next = new HookEndpoint<T>(prev);
            next.Queue.Enqueue(new QueueEntry(QueueOperation.Remove, hookDelegate as Delegate));
            return next;
        }

        private struct QueueEntry {
            public QueueOperation Operation;
            public Delegate Delegate;

            public QueueEntry(QueueOperation operation, Delegate @delegate) {
                Operation = operation;
                Delegate = @delegate;
            }

            public override int GetHashCode() {
                return Operation.GetHashCode() ^ Delegate.GetHashCode();
            }

            public override bool Equals(object obj) {
                if (!(obj is QueueEntry other))
                    return false;
                return Operation == other.Operation && ReferenceEquals(Delegate, other.Delegate);
            }

            public override string ToString() {
                return $"[QueueEntry ({Operation}) ({Delegate})]";
            }
        }

        private class HookKeyEqualityComparer : EqualityComparer<QueueEntry> {
            public override bool Equals(QueueEntry x, QueueEntry y) {
                return x.Operation == y.Operation && ReferenceEquals(x.Delegate, y.Delegate);
            }

            public override int GetHashCode(QueueEntry obj) {
                return obj.Operation.GetHashCode() ^ obj.Delegate.GetHashCode();
            }
        }

        private enum QueueOperation {
            Add,
            Remove,
            Modify,
            Unmodify
        }

    }
}
