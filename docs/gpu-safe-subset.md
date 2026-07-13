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

## Not yet

- **Transitive call graph.** Only the `@Compute` function's own body is checked;
  an unsafe construct in a *helper* it calls isn't flagged at the source yet
  (it'll still fail downstream). A SIL-level pass over the kernel's reachable
  call tree would close this — and also catch recursion (no GPU stack) and heap
  allocation that only appears after inlining.
- Recursion, and heap allocation via APIs that don't surface an unsafe *type* at
  the call (custom allocators, `Unmanaged`, etc.).
