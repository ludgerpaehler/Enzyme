; RUN: %opt < %s %newLoadEnzyme -passes="enzyme" -enzyme-preopt=false -S | FileCheck %s

; Vector (width-2) forward mode over an op with a registered custom forward
; derivative (!enzyme_derivative) and a CONSTANT integer argument.  The
; hasconstant fixderivative wrapper must be width-aware: dup-argument shadow
; slots use the vectorized shadow type ([2 x T]) and the return is
; { T, [2 x T] }.  The registered rule ABI mirrors every argument
; (primal, shadow); constant integer arguments keep a scalar shadow slot,
; which Enzyme fills with the primal value.

declare i8* @malloc(i64)

define double* @alloc_op(double* %x, i64 %n) !enzyme_derivative !0 {
entry:
  %m = call i8* @malloc(i64 %n)
  %md = bitcast i8* %m to double*
  %v = load double, double* %x, align 8
  %vv = fadd double %v, %v
  store double %vv, double* %md, align 8
  ret double* %md
}

define { double*, [2 x double*] } @alloc_op_deriv(double* %x, [2 x double*] %dx, i64 %n, i64 %dn) {
entry:
  %m = call i8* @malloc(i64 %n)
  %md = bitcast i8* %m to double*
  %v = load double, double* %x, align 8
  %vv = fadd double %v, %v
  store double %vv, double* %md, align 8
  %dx0 = extractvalue [2 x double*] %dx, 0
  %s0 = call i8* @malloc(i64 %n)
  %s0d = bitcast i8* %s0 to double*
  %d0 = load double, double* %dx0, align 8
  %dd0 = fadd double %d0, %d0
  store double %dd0, double* %s0d, align 8
  %dx1 = extractvalue [2 x double*] %dx, 1
  %s1 = call i8* @malloc(i64 %n)
  %s1d = bitcast i8* %s1 to double*
  %d1 = load double, double* %dx1, align 8
  %dd1 = fadd double %d1, %d1
  store double %dd1, double* %s1d, align 8
  %r0 = insertvalue { double*, [2 x double*] } undef, double* %md, 0
  %r1 = insertvalue { double*, [2 x double*] } %r0, double* %s0d, 1, 0
  %r2 = insertvalue { double*, [2 x double*] } %r1, double* %s1d, 1, 1
  ret { double*, [2 x double*] } %r2
}

define double @f(double* %x, i64 %n) {
entry:
  %b = call double* @alloc_op(double* %x, i64 %n)
  %v = load double, double* %b, align 8
  ret double %v
}

%pd = type { double, [2 x double] }

define %pd @df(double* %x, double* %dx1, double* %dx2, i64 %n) {
entry:
  %r = call %pd (...) @__enzyme_fwddiff(double (double*, i64)* @f, metadata !"enzyme_width", i64 2, metadata !"enzyme_primal_return", double* %x, double* %dx1, double* %dx2, metadata !"enzyme_const", i64 %n)
  ret %pd %r
}

declare %pd @__enzyme_fwddiff(...)

!0 = !{{ double*, [2 x double*] } (double*, [2 x double*], i64, i64)* @alloc_op_deriv}

; CHECK: define internal { double, [2 x double] } @fwddiffe2f({{.*}} %x, [2 x {{.*}}] %"x'", i64 %n)
; CHECK: call { {{.*}}, [2 x {{.*}}] } @fixderivative_alloc_op({{.*}} %x, [2 x {{.*}}] %"x'", i64 %n)

; CHECK: define internal { {{.*}}, [2 x {{.*}}] } @fixderivative_alloc_op({{.*}} %x, [2 x {{.*}}] %"x'", i64 %n)
; CHECK-NEXT: entry:
; CHECK-NEXT:   %0 = call { {{.*}}, [2 x {{.*}}] } @alloc_op_deriv({{.*}} %x, [2 x {{.*}}] %"x'", i64 %n, i64 %n)
; CHECK-NEXT:   ret { {{.*}}, [2 x {{.*}}] } %0
; CHECK-NEXT: }
