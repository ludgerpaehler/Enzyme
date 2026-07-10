; RUN: %opt < %s %newLoadEnzyme -passes="enzyme,function(mem2reg,instsimplify,adce,loop(loop-deletion),correlated-propagation,%simplifycfg)" -enzyme-preopt=false -S | FileCheck %s

; The Numba runtime (NRT) allocation functions return a pointer to a
; reference-counted MemInfo header; the allocated buffer lives behind the
; header's data field and the header is released with NRT_decref. This test
; pins the IR shape Numba emits for `v = np.empty(1)` used inside a loop:
;
;   %mi = call i8* @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
;   %fieldp = getelementptr inbounds i8, i8* %mi, i64 24  ; MemInfo::data
;   %v = load double*, double** %fieldp                   ; inlined NRT_MemInfo_data_fast
;   ...
;   call void @NRT_decref(i8* %mi)
;
; and verifies the NRT allocation/deallocation pair is registered symmetrically
; (isAllocationFunction/isDeallocationFunction/freeKnownAllocation), analogous
; to swift_allocObject/swift_release:
;  1. the shadow is allocated with the real NRT allocator,
;  2. the shadow buffer is zeroed behind the header's data field (via
;     NRT_MemInfo_data_fast) -- memsetting the returned pointer itself would
;     corrupt the header's refcount/dtor/data fields,
;  3. the shadow is released with NRT_decref, not libc free (the header is not
;     a malloc'd pointer).

declare noalias i8* @NRT_MemInfo_alloc_aligned(i64, i32)
declare void @NRT_decref(i8*)

define dso_local double @subsum(double* nocapture readonly %x, i64 %n) {
entry:
  %mi = call i8* @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
  %fieldp = getelementptr inbounds i8, i8* %mi, i64 24
  %fieldc = bitcast i8* %fieldp to double**
  %v = load double*, double** %fieldc, align 8
  store double 0.000000e+00, double* %v, align 8
  br label %for.body

for.body:                                         ; preds = %entry, %for.body
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %for.body ]
  %total = phi double [ 0.000000e+00, %entry ], [ %add, %for.body ]
  %arrayidx = getelementptr inbounds double, double* %x, i64 %iv
  %ld = load double, double* %arrayidx, align 8
  %add = fadd fast double %ld, %total
  store double %add, double* %v, align 8
  %iv.next = add nuw i64 %iv, 1
  %exitcond = icmp eq i64 %iv, %n
  br i1 %exitcond, label %cleanup, label %for.body

cleanup:                                          ; preds = %for.body
  %res = load double, double* %v, align 8
  call void @NRT_decref(i8* %mi)
  ret double %res
}

define dso_local double @sum(double* nocapture readonly %x, i64 %n) {
entry:
  %res = call double @subsum(double* %x, i64 %n)
  store double 0.000000e+00, double* %x
  ret double %res
}

define dso_local void @dsum(double* %x, double* %xp, i64 %n) {
entry:
  %0 = tail call double (double (double*, i64)*, ...) @__enzyme_autodiff(double (double*, i64)* nonnull @sum, double* %x, double* %xp, i64 %n)
  ret void
}

declare double @__enzyme_autodiff(double (double*, i64)*, ...)

; The shadow is allocated by the true NRT allocator and its buffer -- not its
; header -- is zeroed: the memset operand must be the data pointer read via
; NRT_MemInfo_data_fast, never the MemInfo pointer itself.
; CHECK: define internal void @augmented_subsum(
; CHECK-NEXT: entry:
; CHECK-NEXT:   %"mi'mi" = call noalias nonnull {{i8\*|ptr}} @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
; CHECK-NEXT:   %[[sdata:.+]] = call {{i8\*|ptr}} @NRT_MemInfo_data_fast({{i8\*|ptr}} nonnull %"mi'mi")
; CHECK-NEXT:   call void @llvm.memset{{.*}}({{i8\*|ptr}} nonnull dereferenceable(8) dereferenceable_or_null(8) %[[sdata]], i8 0, i64 8, i1 false)

; The primal allocation keeps its original free behavior in the forward pass:
; the recognized NRT_decref stays, and no other deallocation is invented.
; CHECK:   %mi = call {{i8\*|ptr}} @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
; CHECK: call void @NRT_decref({{i8\*|ptr}} %mi)
; CHECK-NOT: @free

; The reverse pass rematerializes the shadow with the NRT allocator, zeroes
; its buffer behind the data field, and releases it exactly once with
; NRT_decref (the free-equivalent of an NRT allocation), never libc free.
; CHECK: define internal void @diffesubsum(
; CHECK-NEXT: entry:
; CHECK-NEXT:   %"mi'mi" = call noalias nonnull {{i8\*|ptr}} @NRT_MemInfo_alloc_aligned(i64 8, i32 32)
; CHECK-NEXT:   %[[rdata:.+]] = call {{i8\*|ptr}} @NRT_MemInfo_data_fast({{i8\*|ptr}} nonnull %"mi'mi")
; CHECK-NEXT:   call void @llvm.memset{{.*}}({{i8\*|ptr}} nonnull dereferenceable(8) dereferenceable_or_null(8) %[[rdata]], i8 0, i64 8, i1 false)
; CHECK: call void @NRT_decref({{i8\*|ptr}} nonnull %"mi'mi")
; CHECK-NOT: @free
