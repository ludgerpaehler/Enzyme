//===- CApi.h - Enzyme API exported to C for external use      -----------===//
//
//                             Enzyme Project
//
// Part of the Enzyme Project, under the Apache License v2.0 with LLVM
// Exceptions. See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// If using this code in an academic setting, please cite the following:
// @incollection{enzymeNeurips,
// title = {Instead of Rewriting Foreign Code for Machine Learning,
//          Automatically Synthesize Fast Gradients},
// author = {Moses, William S. and Churavy, Valentin},
// booktitle = {Advances in Neural Information Processing Systems 33},
// year = {2020},
// note = {To appear in},
// }
//
//===----------------------------------------------------------------------===//
//
// This file declares various utility functions of Enzyme for access via C
//
//===----------------------------------------------------------------------===//
#ifndef ENZYME_CAPI_H
#define ENZYME_CAPI_H

#include "llvm-c/Core.h"
#include "llvm-c/DataTypes.h"
// #include "llvm-c/Initialization.h"
#include "llvm-c/Target.h"
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define ENZYME_CAPI_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define ENZYME_CAPI_EXPORT __attribute__((visibility("default")))
#else
#define ENZYME_CAPI_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

struct EnzymeOpaqueTypeAnalysis;
typedef struct EnzymeOpaqueTypeAnalysis *EnzymeTypeAnalysisRef;

struct EnzymeOpaqueLogic;
typedef struct EnzymeOpaqueLogic *EnzymeLogicRef;

struct EnzymeOpaqueAugmentedReturn;
typedef struct EnzymeOpaqueAugmentedReturn *EnzymeAugmentedReturnPtr;

struct EnzymeOpaqueTraceInterface;
typedef struct EnzymeOpaqueTraceInterface *EnzymeTraceInterfaceRef;

struct IntList {
  int64_t *data;
  size_t size;
};

typedef enum {
  DT_Anything = 0,
  DT_Integer = 1,
  DT_Pointer = 2,
  DT_Half = 3,
  DT_Float = 4,
  DT_Double = 5,
  DT_Unknown = 6,
  DT_X86_FP80 = 7,
  DT_BFloat16 = 8,
  DT_FP128 = 9,
} CConcreteType;

struct CDataPair {
  struct IntList offsets;
  CConcreteType datatype;
};

/*
struct CTypeTree {
  struct CDataPair *data;
  size_t size;
};
*/

typedef enum {
  VT_None = 0,
  VT_Primal = 1,
  VT_Shadow = 2,
  VT_Both = VT_Primal | VT_Shadow,
} CValueType;

struct EnzymeTypeTree;
typedef struct EnzymeTypeTree *CTypeTreeRef;
ENZYME_CAPI_EXPORT CTypeTreeRef EnzymeNewTypeTree(void);
ENZYME_CAPI_EXPORT CTypeTreeRef
EnzymeNewTypeTreeCT(CConcreteType, LLVMContextRef ctx);
ENZYME_CAPI_EXPORT CTypeTreeRef EnzymeNewTypeTreeTR(CTypeTreeRef);
ENZYME_CAPI_EXPORT void EnzymeFreeTypeTree(CTypeTreeRef CTT);
uint8_t EnzymeSetTypeTree(CTypeTreeRef dst, CTypeTreeRef src);
ENZYME_CAPI_EXPORT uint8_t EnzymeMergeTypeTree(CTypeTreeRef dst,
                                                CTypeTreeRef src);
ENZYME_CAPI_EXPORT void EnzymeTypeTreeOnlyEq(CTypeTreeRef dst, int64_t x);
ENZYME_CAPI_EXPORT void EnzymeTypeTreeData0Eq(CTypeTreeRef dst);
void EnzymeTypeTreeShiftIndiciesEq(CTypeTreeRef dst, const char *datalayout,
                                   int64_t offset, int64_t maxSize,
                                   uint64_t addOffset);
ENZYME_CAPI_EXPORT void
EnzymeTypeTreeInsertEq(CTypeTreeRef dst, const int64_t *indices, size_t len,
                       CConcreteType ct, LLVMContextRef ctx);
ENZYME_CAPI_EXPORT const char *
EnzymeTypeTreeToString(CTypeTreeRef src);
ENZYME_CAPI_EXPORT void EnzymeTypeTreeToStringFree(const char *cstr);

void EnzymeSetCLBool(void *, uint8_t);
void EnzymeSetCLInteger(void *, int64_t);
void EnzymeSetCLString(void *, const char *);

typedef struct CFnTypeInfo {
  /// Types of arguments, assumed of size len(Arguments)
  CTypeTreeRef *Arguments;

  /// Type of return
  CTypeTreeRef Return;

  /// The specific constant(s) known to represented by an argument, if constant
  // map is [arg number] => list
  struct IntList *KnownValues;
} CFnTypeInfo;

typedef enum {
  DFT_OUT_DIFF = 0,  // add differential to an output struct. Only for scalar
                     // values in ReverseMode variants.
  DFT_DUP_ARG = 1,   // duplicate the argument and store differential inside.
                     // For references, pointers, or integers in ReverseMode
                     // variants. For all types in ForwardMode variants.
  DFT_CONSTANT = 2,  // no differential. Usable everywhere.
  DFT_DUP_NONEED = 3 // duplicate this argument and store differential inside,
                     // but don't need the forward. Same as DUP_ARG otherwise.
} CDIFFE_TYPE;

typedef enum { BT_SCALAR = 0, BT_VECTOR = 1 } CBATCH_TYPE;

typedef enum {
  DEM_ForwardMode = 0,
  DEM_ReverseModePrimal = 1,
  DEM_ReverseModeGradient = 2,
  DEM_ReverseModeCombined = 3,
  DEM_ForwardModeSplit = 4,
  DEM_ForwardModeError = 5
} CDerivativeMode;

// Versioned, read-only description of the C ABI consumed by out-of-tree
// clients.  Keep this a plain C struct: clients deliberately query it through
// the handle that loaded Enzyme before resolving or calling the rest of the
// API.  New fields may only be appended and require StructSize to grow;
// incompatible changes increment ABIVersion.
#define ENZYME_CAPI_ABI_VERSION 1
#define ENZYME_CAPI_FEATURE_TYPE_TREES UINT64_C(1)
#define ENZYME_CAPI_FEATURE_FORWARD_DIFF UINT64_C(2)
#define ENZYME_CAPI_FEATURE_REVERSE_DIFF UINT64_C(4)
#define ENZYME_CAPI_FEATURE_AUGMENTED_RETURN UINT64_C(8)
#define ENZYME_CAPI_FEATURE_ALLOCATION_HANDLER UINT64_C(16)
#define ENZYME_CAPI_FEATURE_ATOMIC_ADD UINT64_C(32)
#define ENZYME_CAPI_FEATURE_KNOWN_VALUES_PER_ARG UINT64_C(64)
// Custom-forward rule glue preserves width-N shadow arrays and return lanes.
// EnzymeWidthAwareCustomForward remains exported as the legacy value-1 probe.
#define ENZYME_CAPI_FEATURE_WIDTH_AWARE_CUSTOM_FORWARD_V1 UINT64_C(128)
// Numba MemInfo allocations are classified/zeroed through their data pointer,
// one generated shadow reference is released with NRT_decref, and that
// decrement is not treated as proof that every alias/reference is dead.
#define ENZYME_CAPI_FEATURE_NUMBA_NRT_MEMINFO_V1 UINT64_C(256)
// A C client may install a nonthrowing diagnostic sink for one synthesis
// scope. Enzyme—not the client callback—supplies any recovery LLVM value.
#define ENZYME_CAPI_FEATURE_SCOPED_DIAGNOSTIC_HANDLER_V1 UINT64_C(512)

struct EnzymeCAPIManifest {
  uint32_t StructSize;
  uint32_t ABIVersion;
  uint32_t LLVMMajor;
  uint32_t LLVMMinor;
  uint32_t LLVMPatch;
  uintptr_t LLVMContextCreateAddress;
  uint32_t EnzymeMajor;
  uint32_t EnzymeMinor;
  uint32_t EnzymePatch;
  uint64_t FeatureBits;

  uint32_t ConcreteTypeSize;
  uint32_t ConcreteTypeAlign;
  uint32_t DiffeTypeSize;
  uint32_t DiffeTypeAlign;
  uint32_t DerivativeModeSize;
  uint32_t DerivativeModeAlign;

  uint32_t IntListSize;
  uint32_t IntListAlign;
  uint32_t IntListDataOffset;
  uint32_t IntListSizeOffset;

  uint32_t FnTypeInfoSize;
  uint32_t FnTypeInfoAlign;
  uint32_t FnTypeInfoArgumentsOffset;
  uint32_t FnTypeInfoReturnOffset;
  uint32_t FnTypeInfoKnownValuesOffset;

  int32_t ConcreteTypeValues[10];
  int32_t DiffeTypeValues[4];
  int32_t DerivativeModeValues[6];

  uint32_t ErrorTypeSize;
  uint32_t ErrorTypeAlign;
  int32_t ErrorTypeValues[13];
  uint8_t ErrorTypeFatal[13];
};

ENZYME_CAPI_EXPORT const struct EnzymeCAPIManifest *
EnzymeGetCAPIManifest(void);

// Diagnostic callbacks are observers only: they must not throw across this C
// boundary and cannot choose the value returned to Enzyme. RecoveryValue is
// either NULL (when the reporting site accepts no value) or an Enzyme-supplied
// placeholder whose LLVM type exactly matches what that site consumes. The
// scoped adapter returns that exact value after Handler returns.
typedef void (*EnzymeDiagnosticHandler)(const char *Message,
                                        LLVMValueRef OffendingValue,
                                        int32_t ErrorType,
                                        uint8_t IsFatal,
                                        LLVMValueRef RecoveryValue,
                                        void *UserData);

struct EnzymeOpaqueDiagnosticScope;
typedef struct EnzymeOpaqueDiagnosticScope *EnzymeDiagnosticScopeRef;

// Begin holds a process-wide recursive scope lock until End. Scopes may nest
// on one thread; different threads serialize. End must run on the thread that
// began the scope. The previous CustomErrorHandler is restored before the lock
// is released. Diagnostics must be emitted synchronously on that same thread;
// direct clients that access CustomErrorHandler without this scoped API remain
// outside its concurrency contract. This observes CustomErrorHandler calls
// only: assert, llvm_unreachable, and report_fatal_error are not recoverable.
ENZYME_CAPI_EXPORT EnzymeDiagnosticScopeRef
EnzymeBeginDiagnosticScope(EnzymeDiagnosticHandler Handler, void *UserData);
ENZYME_CAPI_EXPORT uint8_t
EnzymeEndDiagnosticScope(EnzymeDiagnosticScopeRef Scope);

typedef enum {
  DEM_Trace = 0,
  DEM_Condition = 1,
} CProbProgMode;

typedef uint8_t (*CustomRuleType)(int /*direction*/, CTypeTreeRef /*return*/,
                                  CTypeTreeRef * /*args*/,
                                  struct IntList * /*knownValues*/,
                                  size_t /*numArgs*/, LLVMValueRef,
                                  void * /*TA*/);
ENZYME_CAPI_EXPORT EnzymeTypeAnalysisRef
CreateTypeAnalysis(EnzymeLogicRef Log, char **customRuleNames,
                   CustomRuleType *customRules, size_t numRules);
ENZYME_CAPI_EXPORT void ClearTypeAnalysis(EnzymeTypeAnalysisRef);
ENZYME_CAPI_EXPORT void FreeTypeAnalysis(EnzymeTypeAnalysisRef);

EnzymeLogicRef EnzymeTypeAnalysisGetLogic(EnzymeTypeAnalysisRef TAR);
EnzymeTypeAnalysisRef EnzymeGetTypeAnalysisFromTypeAnalyzer(void *TAR);

EnzymeTraceInterfaceRef FindEnzymeStaticTraceInterface(LLVMModuleRef M);
EnzymeTraceInterfaceRef CreateEnzymeStaticTraceInterface(
    LLVMContextRef C, LLVMValueRef getTraceFunction,
    LLVMValueRef getChoiceFunction, LLVMValueRef insertCallFunction,
    LLVMValueRef insertChoiceFunction, LLVMValueRef insertArgumentFunction,
    LLVMValueRef insertReturnFunction, LLVMValueRef insertFunctionFunction,
    LLVMValueRef insertChoiceGradientFunction,
    LLVMValueRef insertArgumentGradientFunction, LLVMValueRef newTraceFunction,
    LLVMValueRef freeTraceFunction, LLVMValueRef hasCallFunction,
    LLVMValueRef hasChoiceFunction);
EnzymeTraceInterfaceRef
CreateEnzymeDynamicTraceInterface(LLVMValueRef interface, LLVMValueRef F);
ENZYME_CAPI_EXPORT EnzymeLogicRef CreateEnzymeLogic(uint8_t PostOpt);
ENZYME_CAPI_EXPORT void ClearEnzymeLogic(EnzymeLogicRef);
ENZYME_CAPI_EXPORT void FreeEnzymeLogic(EnzymeLogicRef);
void EnzymeLogicSetExternalContext(EnzymeLogicRef, void *ExternalContext);
void *EnzymeLogicGetExternalContext(EnzymeLogicRef);

ENZYME_CAPI_EXPORT void
EnzymeExtractReturnInfo(EnzymeAugmentedReturnPtr ret, int64_t *data,
                        uint8_t *existed, size_t len);

ENZYME_CAPI_EXPORT LLVMValueRef
EnzymeExtractFunctionFromAugmentation(EnzymeAugmentedReturnPtr ret);
ENZYME_CAPI_EXPORT LLVMTypeRef
EnzymeExtractTapeTypeFromAugmentation(EnzymeAugmentedReturnPtr ret);

ENZYME_CAPI_EXPORT EnzymeAugmentedReturnPtr EnzymeCreateAugmentedPrimal(
    EnzymeLogicRef Logic, LLVMValueRef request_req, LLVMBuilderRef request_ip,
    LLVMValueRef todiff, CDIFFE_TYPE retType, CDIFFE_TYPE *constant_args,
    size_t constant_args_size, EnzymeTypeAnalysisRef TA, uint8_t returnUsed,
    uint8_t shadowReturnUsed, CFnTypeInfo typeInfo,
    uint8_t subsequent_calls_may_write, uint8_t *_overwritten_args,
    size_t overwritten_args_size, uint8_t forceAnonymousTape,
    uint8_t runtimeActivity, uint8_t strongZero, unsigned width,
    uint8_t AtomicAdd);

#ifdef __cplusplus
class GradientUtils;
class DiffeGradientUtils;
#else
typedef struct GradientUtils GradientUtils;
typedef struct DiffeGradientUtils DiffeGradientUtils;
#endif

typedef LLVMValueRef (*CustomShadowAlloc)(LLVMBuilderRef, LLVMValueRef,
                                          size_t /*numArgs*/, LLVMValueRef *,
                                          GradientUtils *);
typedef LLVMValueRef (*CustomShadowFree)(LLVMBuilderRef, LLVMValueRef);

ENZYME_CAPI_EXPORT void
EnzymeRegisterAllocationHandler(char *Name, CustomShadowAlloc AHandle,
                                CustomShadowFree FHandle);

typedef uint8_t (*CustomFunctionForward)(LLVMBuilderRef, LLVMValueRef,
                                         GradientUtils *, LLVMValueRef *,
                                         LLVMValueRef *);

typedef uint8_t (*CustomFunctionDiffUse)(LLVMValueRef, const GradientUtils *,
                                         LLVMValueRef, uint8_t, CDerivativeMode,
                                         uint8_t *);

typedef uint8_t (*CustomAugmentedFunctionForward)(LLVMBuilderRef, LLVMValueRef,
                                                  GradientUtils *,
                                                  LLVMValueRef *,
                                                  LLVMValueRef *,
                                                  LLVMValueRef *);

typedef void (*CustomFunctionReverse)(LLVMBuilderRef, LLVMValueRef,
                                      DiffeGradientUtils *, LLVMValueRef);

ENZYME_CAPI_EXPORT LLVMValueRef EnzymeCreateForwardDiff(
    EnzymeLogicRef Logic, LLVMValueRef request_req, LLVMBuilderRef request_ip,
    LLVMValueRef todiff, CDIFFE_TYPE retType, CDIFFE_TYPE *constant_args,
    size_t constant_args_size, EnzymeTypeAnalysisRef TA, uint8_t returnValue,
    CDerivativeMode mode, uint8_t freeMemory, uint8_t runtimeActivity,
    uint8_t strongZero, unsigned width, LLVMTypeRef additionalArg,
    CFnTypeInfo typeInfo, uint8_t subsequent_calls_may_write,
    uint8_t *_overwritten_args, size_t overwritten_args_size,
    EnzymeAugmentedReturnPtr augmented);

ENZYME_CAPI_EXPORT LLVMValueRef EnzymeCreatePrimalAndGradient(
    EnzymeLogicRef Logic, LLVMValueRef request_req, LLVMBuilderRef request_ip,
    LLVMValueRef todiff, CDIFFE_TYPE retType, CDIFFE_TYPE *constant_args,
    size_t constant_args_size, EnzymeTypeAnalysisRef TA, uint8_t returnValue,
    uint8_t dretUsed, CDerivativeMode mode, uint8_t runtimeActivity,
    uint8_t strongZero, unsigned width, uint8_t freeMemory,
    LLVMTypeRef additionalArg, uint8_t forceAnonymousTape, CFnTypeInfo typeInfo,
    uint8_t subsequent_calls_may_write, uint8_t *_overwritten_args,
    size_t overwritten_args_size, EnzymeAugmentedReturnPtr augmented,
    uint8_t AtomicAdd);

void EnzymeRegisterCallHandler(const char *Name,
                               CustomAugmentedFunctionForward FwdHandle,
                               CustomFunctionReverse RevHandle);

LLVMValueRef EnzymeGradientUtilsNewFromOriginal(GradientUtils *gutils,
                                                LLVMValueRef val);

// TODO: Other API functions that are defined in CApi.cpp for GradientUtils
void *EnzymeGradientUtilsGetExternalContext(GradientUtils *gutils);
EnzymeLogicRef EnzymeTypeAnalyzerGetLogic(void *analyzer);
EnzymeLogicRef EnzymeGradientUtilsGetLogic(GradientUtils *gutils);
uint8_t EnzymeGradientUtilsGetAtomicAdd(GradientUtils *gutils);

#ifdef __cplusplus
}
#endif

#endif
