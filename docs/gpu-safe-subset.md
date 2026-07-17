# The GPU-safe subset

A `@Compute` kernel runs on the GPU, which has **no Swift runtime**: no heap, no
ARC, no stack for arbitrary recursion, no error-box allocation, no dynamic
dispatch via witness tables. Writing an unsupported construct otherwise fails
deep in the pipeline — a SIL-verifier abort, a `metal-as` parse error, or a
driver crash — with no source location. The compiler now rejects the common
cases up front with a clear diagnostic at the offending expression.

## What's enforced

Checked on every `@Compute` function (`checkGPUKernel` in
`lib/Sema/MiscDiagnostics.cpp`, run from `performAbstractFuncDeclDiagnostics`
after the body is type-checked):

**Signature**
- `throws` — no error-box allocation on the GPU.
- `async` — no concurrency runtime.
- non-`Void` return — a kernel writes results through device buffers.

**Body** (type-based, so `InlineArray`/`SIMD` literals are fine — only the
heap-backed types are rejected):
- `class` instances → *needs ARC*
- `any P` existentials → *needs witness tables*
- `Array` / `ContiguousArray` / `String` / `Substring` / `Dictionary` / `Set`
  → *heap-allocated* (this also catches `print(...)`, whose varargs desugar to
  `[Any]`)

Example:

```
error: GPU kernel 'k' cannot be 'throws': the GPU has no runtime for it
error: this value is not available in GPU code: a class instance (needs ARC)
note: in GPU kernel 'k'
error: this value is not available in GPU code: no Array on the GPU (use InlineArray for fixed data)
```

## Design notes

- **Type-based, not syntactic.** `[1, 2, 3, 4]` is an array-literal *syntax* but
  its *type* may be `InlineArray` or `SIMD4` (both GPU-safe) or `Array` (not).
  The checks inspect the resolved type, so the fixed-size value types the GPU
  path relies on aren't false-flagged.
- **One error per location.** A `let x = <unsafe>` reports once, at the
  expression.

## The SIL call-graph check (airtight half)

The AST check above sees only the kernel's own body. A second, structural check
(`diagnoseGPUUnsafeConstructs` in `lib/SILOptimizer/Mandatory/DiagnoseGPUUnsafe.cpp`,
called from `runSILDiagnosticPasses` on the canonical SIL — after mandatory
inlining) follows the kernel's **transitive call graph** into user helper
functions and flags what the AST check can't see:

- **Heap allocation**, structurally — `alloc_ref` / `alloc_ref_dynamic` (class),
  `alloc_box` (escaping capture), `alloc_existential_box` — even inside a helper.
- **Recursion**, direct or mutual — a cycle in the call graph (the GPU has no
  call stack). Reported at the recursive function, with a note pointing to the
  kernel it's reached from.

```
error: recursion is not available in GPU code (no call stack)
note: reached from GPU kernel 'krec'
error: a class instance (needs ARC / the heap) is not available in GPU code
note: reached from GPU kernel 'kheap'
```

It scans **only user-module functions** (skips serialized stdlib) and runs after
inlining, so it sees the real de-wrapped call graph without false-flagging stdlib
internals — all examples (texture `.read`/`.write` wrappers, `InlineArray`, the
barrier, atomics) pass clean. It's a direct call on the `SILModule`, not a
pass-manager pass (the fork's pass manager is Swift-only for new passes), gated on
the module actually containing a `@Compute` kernel.

## The post-optimization backstop (airtight)

The two checks above still miss one case: a runtime dependency that returns a
GPU-*safe* type (so the AST type-check is happy) and lives entirely inside a
serialized stdlib function (so the pre-`-O` SIL check, which skips stdlib, never
sees it). For example `Int.random(in:)` returns `Int`, but bottoms out in
`swift_stdlib_random` — a runtime function with no GPU body. Left unchecked, the
symbol-strip in the AIR normalizer turns it into `call undef(...)`: the build
*succeeds* and produces a silently-broken kernel.

`diagnoseGPUUnsafePostOpt` (same file, called from `performSILProcessing` after
`performSILOptimizations`, **only under `-O`**) closes it. On the fully-optimized
SIL — after inlining, specialization, and dead-code elimination, so *what remains
is what ships* — it walks the reachable graph from each kernel (now including
stdlib) and rejects:

- any surviving **heap allocation** (`alloc_ref`/`alloc_box`/…), and
- a call to an **external function with no GPU implementation** that isn't an
  `air.*` intrinsic — the unresolvable runtime/stdlib dependency.

```
error: GPU kernel code calls 'Swift.SystemRandomNumberGenerator.init() -> …',
       which has no GPU implementation (a runtime/standard-library function)
note: reached from GPU kernel 'kslip'
```

Why `-O` only: a working GPU build *requires* `-O` regardless (un-inlined stdlib
would emit undefined AIR symbols), and only optimized SIL is "what ships" — at
`-Onone`, un-inlined trap thunks (`_assertionFailure`, which becomes `llvm.trap`
under `-O`) and other stdlib calls would false-positive. The pre-`-O` check still
runs at `-Onone` for recursion/heap. Because the pre-`-O` check bails the
pipeline on error *before* optimization, the post-`-O` check only runs on code
that already passed — no double reporting.

## Coverage

Between the three layers — AST (signature + body literals), pre-`-O` SIL (user
call graph: recursion + heap), and post-`-O` SIL (the whole reachable graph:
runtime dependencies + surviving allocation) — a `@Compute` kernel that would
reference anything unavailable on the GPU is rejected at compile time rather than
producing a broken metallib.
