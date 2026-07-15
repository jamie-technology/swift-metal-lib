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

## Not yet

- Heap allocation via APIs that surface neither an unsafe *type* at the call site
  (AST) nor an `alloc_*` in user code (SIL) — e.g. an unsafe construct entirely
  inside a serialized stdlib function that isn't inlined. Rare in practice.
