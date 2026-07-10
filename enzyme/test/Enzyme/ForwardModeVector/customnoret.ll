; RUN: %opt < %s %newLoadEnzyme -passes="enzyme" -enzyme-preopt=false -S | FileCheck %s

; Vector (width-2) forward mode over an op with a registered custom forward
; derivative (!enzyme_derivative) whose PRIMAL value is unused in the
; derivative function: the !returnUsed fixderivative wrapper must return the
; vectorized shadow type ([2 x T]), extracted from the registered rule's
; { T, [2 x T] } return.

declare i8* @malloc(i64)

define double* @dup_op(double* %x) !enzyme_derivative !0 {
entry:
  %m = call i8* @malloc(i64 8)
  %md = bitcast i8* %m to double*
  %v = load double, double* %x, align 8
  %vv = fadd double %v, %v
  store double %vv, double* %md, align 8
  ret double* %md
}

define { double*, [2 x double*] } @dup_op_deriv(double* %x, [2 x double*] %dx) {
entry:
  %m = call i8* @malloc(i64 8)
  %md = bitcast i8* %m to double*
  %v = load double, double* %x, align 8
  %vv = fadd double %v, %v
  store double %vv, double* %md, align 8
  %dx0 = extractvalue [2 x double*] %dx, 0
  %s0 = call i8* @malloc(i64 8)
  %s0d = bitcast i8* %s0 to double*
  %d0 = load double, double* %dx0, align 8
  %dd0 = fadd double %d0, %d0
  store double %dd0, double* %s0d, align 8
  %dx1 = extractvalue [2 x double*] %dx, 1
  %s1 = call i8* @malloc(i64 8)
  %s1d = bitcast i8* %s1 to double*
  %d1 = load double, double* %dx1, align 8
  %dd1 = fadd double %d1, %d1
  store double %dd1, double* %s1d, align 8
  %r0 = insertvalue { double*, [2 x double*] } undef, double* %md, 0
  %r1 = insertvalue { double*, [2 x double*] } %r0, double* %s0d, 1, 0
  %r2 = insertvalue { double*, [2 x double*] } %r1, double* %s1d, 1, 1
  ret { double*, [2 x double*] } %r2
}

define double @f(double* %x) {
entry:
  %b = call double* @dup_op(double* %x)
  %v = load double, double* %b, align 8
  ret double %v
}

define [2 x double] @df(double* %x, double* %dx1, double* %dx2) {
entry:
  %r = call [2 x double] (...) @__enzyme_fwddiff(double (double*)* @f, metadata !"enzyme_width", i64 2, double* %x, double* %dx1, double* %dx2)
  ret [2 x double] %r
}

declare [2 x double] @__enzyme_fwddiff(...)

!0 = !{{ double*, [2 x double*] } (double*, [2 x double*])* @dup_op_deriv}

; CHECK: define internal [2 x double] @fwddiffe2f({{.*}} %x, [2 x {{.*}}] %"x'")
; CHECK: call [2 x {{.*}}] @fixderivative_dup_op({{.*}} %x, [2 x {{.*}}] %"x'")

; CHECK: define internal [2 x {{.*}}] @fixderivative_dup_op({{.*}} %x, [2 x {{.*}}] %dx)
; CHECK-NEXT: entry:
; CHECK-NEXT:   %0 = call { {{.*}}, [2 x {{.*}}] } @dup_op_deriv({{.*}} %x, [2 x {{.*}}] %dx)
; CHECK-NEXT:   %1 = extractvalue { {{.*}}, [2 x {{.*}}] } %0, 1
; CHECK-NEXT:   ret [2 x {{.*}}] %1
; CHECK-NEXT: }
