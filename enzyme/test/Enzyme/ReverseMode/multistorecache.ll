; RUN: %opt < %s %newLoadEnzyme -passes="enzyme" -enzyme-preopt=false -S | FileCheck %s

; Regression test: branch-selector caches written by more than one
; predecessor ("last store wins") must NOT carry !invariant.group.
;
; branchToCorrespondingTarget's fallback path records which predecessor of a
; merge block ran by storing a distinct selector constant per predecessor
; into a single cache slot. Tagging those stores (and the reverse-pass load)
; with !invariant.group asserts that every store to the slot writes the same
; value -- which is false, hence UB. LLVM's GVN exploits it: the reverse-pass
; selector load is folded to one predecessor's constant and the remaining
; invert blocks are dead-code eliminated, silently dropping their adjoint
; contributions (observed with >=3-offset stencil loops under LLVM 20
; runtime unrolling).
;
; The merge block below has four predecessors reached through a chain of
; two-way branches, so no single equivalent terminator exists and the
; fallback selector cache is used. Single-store value caches (the cache of
; %v) must keep !invariant.group.

define double @f(double* %x, i64 %n) {
entry:
  br label %loop

loop:
  %i = phi i64 [ 0, %entry ], [ %inext, %merge ]
  %sum = phi double [ 0.000000e+00, %entry ], [ %nsum, %merge ]
  %gep = getelementptr inbounds double, double* %x, i64 %i
  %v = load double, double* %gep, align 8
  %r = urem i64 %i, 4
  %c0 = icmp eq i64 %r, 0
  br i1 %c0, label %b0, label %t1

t1:
  %c1 = icmp eq i64 %r, 1
  br i1 %c1, label %b1, label %t2

t2:
  %c2 = icmp eq i64 %r, 2
  br i1 %c2, label %b2, label %b3

b0:
  %m0 = fmul double %v, %v
  br label %merge

b1:
  %m1 = fmul double %v, 2.000000e+00
  br label %merge

b2:
  %m2 = fmul double %v, 3.000000e+00
  br label %merge

b3:
  %m3 = fmul double %v, 4.000000e+00
  br label %merge

merge:
  %val = phi double [ %m0, %b0 ], [ %m1, %b1 ], [ %m2, %b2 ], [ %m3, %b3 ]
  store double 0.000000e+00, double* %gep, align 8
  %nsum = fadd double %sum, %val
  %inext = add nuw nsw i64 %i, 1
  %done = icmp eq i64 %inext, %n
  br i1 %done, label %exit, label %loop

exit:
  ret double %nsum
}

declare double @__enzyme_autodiff(...)

define void @caller(double* %x, double* %dx, i64 %n) {
entry:
  %r = call double (...) @__enzyme_autodiff(double (double*, i64)* @f, metadata !"enzyme_dup", double* %x, double* %dx, i64 %n)
  ret void
}

; CHECK-LABEL: define internal void @diffef(

; The overwritten load %v is cached once per iteration (single store), so
; its cache store keeps !invariant.group.
; CHECK: store double %v, {{double\*|ptr}} %{{.+}}, align 8, !invariant.group

; The selector caches are written by all four predecessors of %merge with
; distinct constants; neither the phi-selector cache nor the branch-selector
; cache store may carry !invariant.group (the {{[[:space:]]*$}} anchors
; assert there is no trailing metadata).
; CHECK: store i8 0, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 0, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 1, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 1, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 2, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 2, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 3, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: store i8 3, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}

; Reverse pass: the cached value of %v is reloaded with !invariant.group ...
; CHECK: load double, {{double\*|ptr}} %{{.+}}, align 8, !alias.scope !{{[0-9]+}}, !noalias !{{[0-9]+}}, !invariant.group

; ... but the two selector loads must stay untagged.
; CHECK: load i8, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
; CHECK: load i8, {{i8\*|ptr}} %{{.+}}, align 1{{[[:space:]]*$}}
