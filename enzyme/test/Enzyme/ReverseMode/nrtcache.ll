; RUN: %opt < %s %newLoadEnzyme -passes="enzyme,function(mem2reg,instsimplify,adce,loop(loop-deletion),correlated-propagation,%simplifycfg)" -enzyme-preopt=false -S | FileCheck %s

; Cache analysis exempts allocations with a guaranteed free from caching-from-
; origin, using the guaranteed free as a proxy for "not captured, so a caller
; cannot overwrite it between the augmented and reverse passes". A guaranteed
; NRT_decref is no such proof: it only decrements a refcount, so if the object
; was retained elsewhere (NRT_incref / storing the MemInfo into an escaping
; array struct, both of which Numba emits routinely) the object stays live and
; writable through other references.
;
; Here @capture models the escape of the MemInfo (as when Numba stores it into
; a returned array struct), and the scoped alias metadata mirrors what Numba
; emits for the header/data split. The data pointer %v loaded from the MemInfo
; header must therefore be cached into the tape by the augmented pass; the
; reverse pass must consume the taped value rather than re-loading it through
; the possibly-mutated header.

declare noalias i8* @NRT_MemInfo_alloc_aligned(i64, i32)
declare void @NRT_decref(i8*)
declare void @capture(i8*) #1

define dso_local double @user(double* nocapture readonly %p) #0 {
entry:
  %l = load double, double* %p, align 8
  %s = fmul double %l, %l
  ret double %s
}

define dso_local double @h(double* nocapture readonly %x) {
entry:
  %mi = call i8* @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
  call void @capture(i8* %mi)
  %fieldp = getelementptr inbounds i8, i8* %mi, i64 24
  %fieldc = bitcast i8* %fieldp to double**
  %v = load double*, double** %fieldc, align 8, !noalias !1
  %x0 = load double, double* %x, align 8
  store double %x0, double* %v, align 8, !alias.scope !1
  %r = call double @user(double* %v)
  call void @NRT_decref(i8* %mi)
  ret double %r
}

define dso_local double @top(double* %x) {
entry:
  %r = call double @h(double* %x)
  store double 0.000000e+00, double* %x
  ret double %r
}

define dso_local void @dtop(double* %x, double* %xp) {
entry:
  %0 = tail call double (double (double*)*, ...) @__enzyme_autodiff(double (double*)* nonnull @top, double* %x, double* %xp)
  ret void
}

declare double @__enzyme_autodiff(double (double*)*, ...)

attributes #0 = { nounwind readonly }
attributes #1 = { nofree nounwind "enzyme_inactive" }

!0 = distinct !{!0, !"nrt"}
!1 = !{!2}
!2 = distinct !{!2, !0, !"nrtbuf"}

; The augmented pass loads the data pointer, stores it into the tape, and
; keeps the original NRT_decref (original free behavior in the forward pass).
; CHECK: define internal { double, {{.*}} } @augmented_h(
; CHECK: %v = load {{.*}}%fieldp
; CHECK: store {{double\*|ptr}} %v,
; CHECK: call void @NRT_decref({{i8\*|ptr}} %mi)

; The reverse pass takes %v from the tape; it must not re-derive it by
; re-loading the header field of the (captured, possibly mutated) MemInfo.
; CHECK: define internal void @diffeh(
; CHECK-NOT: %fieldp
; CHECK: %v = extractvalue { double, {{.*}} } %tapeArg, {{[0-9]+}}
; CHECK-NOT: %fieldp
; CHECK: call void @diffeuser({{double\*|ptr}} %v,
; CHECK-NOT: %fieldp
