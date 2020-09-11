// RUN: %target-run-simple-swift(-Xfrontend -enable-experimental-forward-mode-differentiation)
// REQUIRES: executable_test

import StdlibUnittest
import DifferentiationUnittest

var ForwardModeTests = TestSuite("ForwardModeDifferentiation")

//===----------------------------------------------------------------------===//
// Basic tests.
//===----------------------------------------------------------------------===//

ForwardModeTests.test("Identity") {
  func func_to_diff(x: Float) -> Float {
    return x
  }
  let (y, differential) = valueWithDifferential(at: 4, in: func_to_diff)
  expectEqual(4, y)
  expectEqual(1, differential(1))
}

ForwardModeTests.test("Unary") {
  func func_to_diff(x: Float) -> Float {
    return x * x
  }
  let (y, differential) = valueWithDifferential(at: 4, in: func_to_diff)
  expectEqual(16, y)
  expectEqual(8, differential(1))
}

ForwardModeTests.test("Binary") {
  func func_to_diff(x: Float, y: Float) -> Float {
    return x * y
  }
  let (y, differential) = valueWithDifferential(at: 4, 5, in: func_to_diff)
  expectEqual(20, y)
  expectEqual(9, differential(1, 1))
}

ForwardModeTests.test("BinaryWithLets") {
  func func_to_diff(x: Float, y: Float) -> Float {
    let a = x + y
    let b = a
    return b * -y
  }
  let (y, differential) = valueWithDifferential(at: 4, 5, in: func_to_diff)
  expectEqual(-45, y)
  expectEqual(-19, differential(1, 1))
}

ForwardModeTests.test("SubsetParametersDiff") {
  func func_to_diff1(x: Int, y: Float, z: Int) -> Float {
    return y
  }
  let (y1, differential1) = valueWithDifferential(at: 5) { y in
    func_to_diff1(x: 0, y: y, z: 0)
  }
  expectEqual(5, y1)
  expectEqual(1, differential1(1))

  func func_to_diff2(x: Float, y: Int, z: Int) -> Float {
    return 2 * x
  }
  let (y2, differential2) = valueWithDifferential(at: 6) { x in
    func_to_diff2(x: x, y: 0, z: 0)
  }
  expectEqual(12, y2)
  expectEqual(2, differential2(1))

  func func_to_diff3(x: Int, y: Int, z: Float) -> Float {
    return 3 * z
  }
  let (y3, differential3) = valueWithDifferential(at: 7) { z in
    func_to_diff3(x: 0, y: 0, z: z)
  }
  expectEqual(21, y3)
  expectEqual(3, differential3(1))
}

//===----------------------------------------------------------------------===//
// Functions with variables
//===----------------------------------------------------------------------===//

ForwardModeTests.test("UnaryWithVars") {
  func unary(x: Float) -> Float {
    var a = x
    a = x
    var b = a + 2
    b = b - 1
    let c: Float = 3
    var d = a + b + c - 1
    d = d + d
    return d
  }

  let (y, differential) = valueWithDifferential(at: 4, in: unary)
  expectEqual(22, y)
  expectEqual(4, differential(1))
}

//===----------------------------------------------------------------------===//
// Functions with basic struct
//===----------------------------------------------------------------------===//

struct A: Differentiable & AdditiveArithmetic {
  var x: Float
}

ForwardModeTests.test("StructInit") {
  func structInit(x: Float) -> A {
    return A(x: 2 * x)
  }

  let (y, differential) = valueWithDifferential(at: 4, in: structInit)
  expectEqual(A(x: 8), y)
  expectEqual(A(x: 2), differential(1))
}

ForwardModeTests.test("StructExtract") {
  func structExtract(x: A) -> Float {
    return 2 * x.x
  }

  let (y, differential) = valueWithDifferential(
    at: A(x: 4),
    in: structExtract)
  expectEqual(8, y)
  expectEqual(2, differential(A(x: 1)))
}

ForwardModeTests.test("LocalStructVariable") {
  func structExtract(x: A) -> A {
    let a = A(x: 2 * x.x) // 2x
    var b = A(x: a.x + 2) // 2x + 2
    b = A(x: b.x + a.x) // 2x + 2 + 2x = 4x + 2
    return b
  }

  let (y, differential) = valueWithDifferential(
    at: A(x: 4),
    in: structExtract)
  expectEqual(A(x: 18), y)
  expectEqual(A(x: 4), differential(A(x: 1)))
}

//===----------------------------------------------------------------------===//
// Functions with methods
//===----------------------------------------------------------------------===//

extension A {
  func noParamMethodA() -> A {
    return A(x: 2 * x)
  }

  func noParamMethodx() -> Float {
    return 2 * x
  }

  static func *(lhs: A, rhs: A) -> A {
    return A(x: lhs.x * rhs.x)
  }

  func complexBinaryMethod(u: A, v: Float) -> A {
    var b: A = u * A(x: 2)  // A(x: u * 2)
    b.x = b.x * v        // A(x: u * 2 * v)
    let c = b.x + 1      // u * 2 * v + 1

    // A(x: u * 2 * v + 1 + u * 2 * v) = A(x: x * (4uv + 1))
    return A(x: x * (c + b.x))
  }
}

ForwardModeTests.test("noParamMethodA") {
  let (y, differential) = valueWithDifferential(at: A(x: 4)) { x in
    x.noParamMethodA()
  }
  expectEqual(A(x: 8), y)
  expectEqual(A(x: 2), differential(A(x: 1)))
}

ForwardModeTests.test("noParamMethodx") {
  let (y, differential) = valueWithDifferential(at: A(x: 4)) { x in
    x.noParamMethodx()
  }
  expectEqual(8, y)
  expectEqual(2, differential(A(x: 1)))
}

ForwardModeTests.test("complexBinaryMethod") {
  let (y, differential) = valueWithDifferential(at: A(x: 4), A(x: 5), 3) {
    (x, y, z) in
    // derivative = A(x: 4uv + 4xv + 4ux + 1) = 4*5*3 + 4*4*3 + 4*5*4 + 1 = 189
    x.complexBinaryMethod(u: y, v: z)
  }
  expectEqual(A(x: 244), y)
  expectEqual(A(x: 189), differential(A(x: 1), A(x: 1), 1))
}

//===----------------------------------------------------------------------===//
// Tracked struct
//===----------------------------------------------------------------------===//

ForwardModeTests.testWithLeakChecking("TrackedIdentity") {
  func identity(x: Tracked<Float>) -> Tracked<Float> {
    return x
  }
  let (y, differential) = valueWithDifferential(at: 4, in: identity)
  expectEqual(4, y)
  expectEqual(1, differential(1))
}

ForwardModeTests.testWithLeakChecking("TrackedAddition") {
  func add(x: Tracked<Float>, y: Tracked<Float>) -> Tracked<Float> {
    return x + y
  }
  let (y, differential) = valueWithDifferential(at: 4, 5, in: add)
  expectEqual(9, y)
  expectEqual(2, differential(1, 1))
}

ForwardModeTests.testWithLeakChecking("TrackedDivision") {
  func divide(x: Tracked<Float>, y: Tracked<Float>) -> Tracked<Float> {
    return x / y
  }
  let (y, differential) = valueWithDifferential(at: 10, 5, in: divide)
  expectEqual(2, y)
  expectEqual(-0.2, differential(1, 1))
}

ForwardModeTests.testWithLeakChecking("TrackedMultipleMultiplication") {
  func add(x: Tracked<Float>, y: Tracked<Float>) -> Tracked<Float> {
    return x * y * x
  }
  let (y, differential) = valueWithDifferential(at: 4, 5, in: add)
  expectEqual(80, y)
  // 2yx+xx
  expectEqual(56, differential(1, 1))
}

ForwardModeTests.testWithLeakChecking("TrackedWithLets") {
  func add(x: Tracked<Float>, y: Tracked<Float>) -> Tracked<Float> {
    let a = x + y
    let b = a * a // (x+y)^2
    let c = b / x + y // (x+y)^2/x+y
    return c
  }
  // (3x^2+2xy-y^2)/x^2+1
  let (y, differential) = valueWithDifferential(at: 4, 5, in: add)
  expectEqual(25.25, y)
  expectEqual(4.9375, differential(1, 1))
}

//===----------------------------------------------------------------------===//
// Tuples
//===----------------------------------------------------------------------===//

ForwardModeTests.test("TupleLet") {
  do {
    func tupleLet(_ x: Float) -> Float {
      let tuple = (2 * x, x)
      return tuple.0
    }
    let (value, derivative) = valueWithDerivative(at: 4, in: tupleLet)
    expectEqual(8, value)
    expectEqual(2, derivative)
  }
}

ForwardModeTests.test("TupleVar") {
  do {
    func tupleVar(_ x: Float) -> Float {
      var tuple = (2 * x, x)
      return tuple.0
    }
    let (value, derivative) = valueWithDerivative(at: 4, in: tupleVar)
    expectEqual(8, value)
    expectEqual(2, derivative)
  }

  do {
    // TF-964: Test tuple with non-tuple-typed adjoint value.
    func TF_964(_ x: Float) -> Float {
      var tuple = (2 * x, 1)
      return tuple.0
    }
    let (value, derivative) = valueWithDerivative(at: 4, in: TF_964)
    expectEqual(8, value)
    expectEqual(2, derivative)
  }
}

ForwardModeTests.test("TupleMutation") {
  func foo(_ x: Float) -> Float {
    var tuple = (x, x)
    tuple.0 = tuple.0 * x
    return x * tuple.0
  }
  expectEqual(27, derivative(at: 3, in: foo))

  func fifthPower(_ x: Float) -> Float {
    var tuple = (x, x)
    tuple.0 = tuple.0 * x
    tuple.1 = tuple.0 * x
    return tuple.0 * tuple.1
  }
  expectEqual(405, derivative(at: 3, in: fifthPower))

  func nested(_ x: Float) -> Float {
    var tuple = ((x, x), x)
    tuple.0.0 = tuple.0.0 * x
    tuple.0.1 = tuple.0.0 * x
    return tuple.0.0 * tuple.0.1
  }
  expectEqual(405, derivative(at: 3, in: nested))

  func generic<T: Differentiable & AdditiveArithmetic>(_ x: T) -> T {
    var tuple = (x, x)
    return tuple.0
  }
  expectEqual(1, derivative(at: 3.0, in: generic))

  // FIXME(TF-1033): Fix forward-mode ownership error for tuple with non-active
  // initial values.
  /*
  func genericInitialNonactive<T: Differentiable & AdditiveArithmetic>(
    _ x: T
  ) -> T {
    var tuple = (T.zero, T.zero)
    tuple.0 = x
    tuple.1 = x
    return tuple.0
  }
  expectEqual(1, derivative(at: 3.0, in: genericInitialNonactive))
  */
}

// Tests TF-321.
ForwardModeTests.test("TupleNonDifferentiableElements") {
  // TF-964: Test tuple with non-tuple-typed adjoint value.
  func tupleLet(_ x: Tracked<Float>) -> Tracked<Float> {
    let tuple = (2 * x, 1)
    return tuple.0
  }
  expectEqual((8, 2), valueWithDerivative(at: 4, in: tupleLet))

  func tupleVar(_ x: Tracked<Float>) -> Tracked<Float> {
    var tuple = (x, 1)
    tuple.0 = x
    tuple.1 = 1
    return tuple.0
  }
  expectEqual((3, 1), valueWithDerivative(at: 3, in: tupleVar))

  @differentiable
  func nested(_ x: Tracked<Float>) -> Tracked<Float> {
    // Convoluted function computing `x * x`.
    var tuple: (Int, (Int, Tracked<Float>), Tracked<Float>) = (1, (1, 0), 0)
    tuple.0 = 1
    tuple.1.0 = 1
    tuple.1.1 = x
    tuple.2 = x
    return tuple.1.1 * tuple.2
  }
  // FIXME(SR-12911): Fix runtime segfault.
  // expectEqual((16, 8), valueWithDerivative(at: 4, in: nested))

  struct Wrapper<T> {
    @differentiable(where T : Differentiable)
    func baz(_ x: T) -> T {
      var tuple = (1, 1, x, 1)
      tuple.0 = 1
      tuple.2 = x
      tuple.3 = 1
      return tuple.2
    }
  }
  func wrapper(_ x: Tracked<Float>) -> Tracked<Float> {
    let w = Wrapper<Tracked<Float>>()
    return w.baz(x)
  }
  expectEqual((3, 1), valueWithDerivative(at: 3, in: wrapper))
}

//===----------------------------------------------------------------------===//
// Generics
//===----------------------------------------------------------------------===//

struct Tensor<Scalar : FloatingPoint & Differentiable>
  : AdditiveArithmetic, Differentiable {
  // NOTE: `value` must have type with known size (e.g. `Float`, not `Scalar`)
  // until differentiation has indirect passing support.
  var value: Float
  init(_ value: Float) { self.value = value }
}

ForwardModeTests.test("GenericIdentity") {
  func identity<T : Differentiable>(_ x: T) -> T {
    return x
  }
  let (y, differential) = valueWithDifferential(at: 4) { (x: Float) in
    identity(x)
  }
  expectEqual(4, y)
  expectEqual(1, differential(1))
}

ForwardModeTests.test("GenericTensorIdentity") {
  func identity<T : FloatingPoint & Differentiable>(
    _ x: Tensor<T>) -> Tensor<T> {
    return x
  }
  let (y, differential) = valueWithDifferential(at: 4) { (x: Float) in
    identity(Tensor<Float>(x))
  }
  expectEqual(Tensor<Float>(4), y)
  expectEqual(Tensor<Float>(1), differential(1))
}

ForwardModeTests.test("GenericTensorPlus") {
  func plus<T : FloatingPoint & Differentiable>(_ x: Tensor<T>) -> Float {
    return x.value + x.value
  }
  let (y, differential) = valueWithDifferential(at: 4) { (x: Float) in
    plus(Tensor<Float>(x))
  }
  expectEqual(8, y)
  expectEqual(2, differential(1))
}

ForwardModeTests.test("GenericTensorBinaryInput") {
  func binary<T : FloatingPoint & Differentiable>(
    _ x: Tensor<T>, _ y: Tensor<T>) -> Float {
    return x.value * y.value
  }
  let (y, differential) = valueWithDifferential(at: 4, 5) {
    (x: Float, y: Float) in
    binary(Tensor<Float>(x), Tensor<Float>(y))
  }
  expectEqual(20, y)
  expectEqual(9, differential(1, 1))
}

ForwardModeTests.test("GenericTensorWithLets") {
  func binary<T : FloatingPoint & Differentiable>(
    _ x: Tensor<T>, _ y: Tensor<T>) -> Float {
    let a = Tensor<T>(x.value)
    let b = Tensor<T>(y.value)
    return a.value * b.value
  }
  let (y, differential) = valueWithDifferential(at: 4, 5) {
    (x: Float, y: Float) in
    binary(Tensor<Float>(x), Tensor<Float>(y))
  }
  expectEqual(20, y)
  expectEqual(9, differential(1, 1))
}

ForwardModeTests.test("GenericTensorWithVars") {
  func binary<T : FloatingPoint & Differentiable>(
    _ x: Tensor<T>, _ y: Tensor<T>) -> Float {
    var a = Tensor<T>(x.value)
    var b = Tensor<T>(y.value)
    b = a
    a = Tensor<T>(y.value)
    return a.value * b.value
  }
  let (y, differential) = valueWithDifferential(at: 4, 5) {
    (x: Float, y: Float) in
    binary(Tensor<Float>(x), Tensor<Float>(y))
  }
  expectEqual(20, y)
  expectEqual(9, differential(1, 1))
}

// Test case where associated derivative function's requirements are met.
extension Tensor where Scalar : Numeric {
  @differentiable(wrt: self where Scalar : Differentiable & FloatingPoint)
  func mean() -> Tensor {
    return self
  }

  @differentiable(wrt: self where Scalar : Differentiable & FloatingPoint)
  func variance() -> Tensor {
    return mean() // ok
  }
}
_ = differential(at: Tensor<Float>(1), in: { $0.variance() })

// Tests TF-508: differentiation requirements with dependent member types.
protocol TF_508_Proto {
  associatedtype Scalar
}
extension TF_508_Proto where Scalar : FloatingPoint {
  @differentiable(
    where Self : Differentiable, Scalar : Differentiable,
          // Conformance requirement with dependent member type.
          Self.TangentVector : TF_508_Proto
  )
  static func +(lhs: Self, rhs: Self) -> Self {
    return lhs
  }

  @differentiable(
    where Self : Differentiable, Scalar : Differentiable,
          // Same-type requirement with dependent member type.
          Self.TangentVector == Float
  )
  static func -(lhs: Self, rhs: Self) -> Self {
    return lhs
  }
}
extension TF_508_Proto where Self : Differentiable,
                             Scalar : FloatingPoint & Differentiable,
                             Self.TangentVector : TF_508_Proto {
  @derivative(of: +)
  static func jvpAdd(lhs: Self, rhs: Self)
      -> (value: Self, differential: (TangentVector, TangentVector) -> TangentVector) {
    return (lhs, { (dlhs, drhs) in dlhs })
  }
}
extension TF_508_Proto where Self : Differentiable,
                             Scalar : FloatingPoint & Differentiable,
                             Self.TangentVector == Float {
  @derivative(of: -)
  static func jvpSubtract(lhs: Self, rhs: Self)
      -> (value: Self, differential: (TangentVector, TangentVector) -> TangentVector) {
    return (lhs, { (dlhs, drhs) in dlhs })
  }
}

struct TF_508_Struct<Scalar : AdditiveArithmetic>
  : TF_508_Proto, AdditiveArithmetic {}
extension TF_508_Struct : Differentiable where Scalar : Differentiable {
  typealias TangentVector = TF_508_Struct
}

// func TF_508() {
//   let x = TF_508_Struct<Float>()
//   // Test conformance requirement with dependent member type.
//   _ = differential(at: x, in: {
//     (x: TF_508_Struct<Float>) -> TF_508_Struct<Float> in
//     return x + x
//   })
//   // Test same-type requirement with dependent member type.
//   _ = differential(at: x, in: {
//     (x: TF_508_Struct<Float>) -> TF_508_Struct<Float> in
//     return x - x
//   })
// }

// TF-523
struct TF_523_Struct : Differentiable & AdditiveArithmetic {
  var a: Float = 1
  typealias TangentVector = TF_523_Struct
  typealias AllDifferentiableVariables = TF_523_Struct
}

@differentiable
func TF_523_f(_ x: TF_523_Struct) -> Float {
  return x.a * 2
}

// TF-534: Thunk substitution map remapping.
protocol TF_534_Layer : Differentiable {
  associatedtype Input : Differentiable
  associatedtype Output : Differentiable

  @differentiable
  func callAsFunction(_ input: Input) -> Output
}
struct TF_534_Tensor<Scalar> : Differentiable {}

func TF_534<Model: TF_534_Layer>(
  _ model: inout Model, inputs: Model.Input
) -> TF_534_Tensor<Float> where Model.Output == TF_534_Tensor<Float> {
  return valueWithDifferential(at: model) { model -> Model.Output in
    return model(inputs)
  }.0
}

// TODO: uncomment once control flow is supported in forward mode.
// TF-652: Test VJPEmitter substitution map generic signature.
// The substitution map should have the VJP's generic signature, not the
// original function's.
// struct TF_652<Scalar> {}
// extension TF_652 : Differentiable where Scalar : FloatingPoint {}

// @differentiable(wrt: x where Scalar: FloatingPoint)
// func test<Scalar: Numeric>(x: TF_652<Scalar>) -> TF_652<Scalar> {
//   for _ in 0..<10 {
//     let _ = x
//   }
//   return x
// }

//===----------------------------------------------------------------------===//
// Tracked Generic.
//===----------------------------------------------------------------------===//

ForwardModeTests.test("GenericTrackedIdentity") {
  func identity<T : Differentiable>(_ x: Tracked<T>) -> Tracked<T> {
    return x
  }
  let (y, differential) = valueWithDifferential(at: 4) { (x: Float) in
    identity(Tracked(x))
  }
  expectEqual(4, y)
  expectEqual(1, differential(1))
}

ForwardModeTests.test("GenericTrackedBinaryAdd") {
  func add<T>(_ x: Tracked<T>, _ y: Tracked<T>) -> Tracked<T>
    where T: Differentiable, T == T.TangentVector {
    return x + y
  }
  let (y, differential) = valueWithDifferential(at: 4, 5) {
    (x: Float, y: Float) in
    add(Tracked(x), Tracked(y))
  }
  expectEqual(9, y)
  expectEqual(2, differential(1, 1))
}

ForwardModeTests.test("GenericTrackedBinaryLets") {
  func add<T>(_ x: Tracked<T>, _ y: Tracked<T>) -> Tracked<T>
    where T: Differentiable & SignedNumeric,
          T == T.TangentVector,
          T == T.Magnitude {
    let a = x * y // xy
    let b = a + a // 2xy
    return b + b // 4xy
  }
  // 4y + 4x
  let (y, differential) = valueWithDifferential(at: 4, 5) { (x: Float, y: Float) in
    add(Tracked(x), Tracked(y))
  }
  expectEqual(80, y)
  expectEqual(36, differential(1, 1))
}

ForwardModeTests.test("GenericTrackedBinaryVars") {
  func add<T>(_ x: Tracked<T>, _ y: Tracked<T>) -> Tracked<T>
    where T: Differentiable & SignedNumeric,
          T == T.TangentVector,
          T == T.Magnitude {
    var a = x * y // xy
    a = a + a // 2xy
    var b = x
    b = a
    return b + b // 4xy
  }
  // 4y + 4x
  let (y, differential) = valueWithDifferential(at: 4, 5) { (x: Float, y: Float) in
    add(Tracked(x), Tracked(y))
  }
  expectEqual(80, y)
  expectEqual(36, differential(1, 1))
}

ForwardModeTests.testWithLeakChecking("TrackedDifferentiableFuncType") {
  func valAndDeriv(
    f: @escaping @differentiable (Tracked<Float>) -> Tracked<Float>
  ) -> (Tracked<Float>, Tracked<Float>) {
    let (y, diff) = valueWithDifferential(at: 5, in: f)
    return (y, diff(1))
  }

  func func1(_ x: Tracked<Float>) -> Tracked<Float> {
    let a = x + x // 2x
    let b = a + a // 4x
    return b * b // 16x^2
  }
  let (val1, dv1) = valAndDeriv(f: func1)
  expectEqual(400, val1)
  expectEqual(160, dv1)
}

//===----------------------------------------------------------------------===//
// Classes
//===----------------------------------------------------------------------===//

ForwardModeTests.test("Final") {
  final class Final : Differentiable {
    func method(_ x: Float) -> Float {
      return x * x
    }
  }

  for i in -5...5 {
    expectEqual(
      Float(i) * 2,
      derivative(at: Float(i)) { x in Final().method(x) })
  }
}

ForwardModeTests.test("Simple") {
  class Super {
    @differentiable(wrt: x)
    func f(_ x: Float) -> Float {
      return 2 * x
    }
    @derivative(of: f)
    final func jvpf(_ x: Float) -> (value: Float, differential: (Float) -> Float) {
      return (f(x), { v in 2 * v })
    }
    @derivative(of: f)
    final func vjpf(_ x: Float) -> (value: Float, pullback: (Float) -> Float) {
      return (f(x), { v in 2 * v })
    }
  }

  class SubOverride : Super {
    @differentiable(wrt: x)
    override func f(_ x: Float) -> Float {
      return 3 * x
    }
  }

  class SubOverrideCustomDerivatives : Super {
    @differentiable(wrt: x)
    override func f(_ x: Float) -> Float {
      return 3 * x
    }
    @derivative(of: f)
    final func jvpf2(_ x: Float) -> (value: Float, differential: (Float) -> Float) {
      return (f(x), { v in 3 * v })
    }
    @derivative(of: f)
    final func vjpf2(_ x: Float) -> (value: Float, pullback: (Float) -> Float) {
      return (f(x), { v in 3 * v })
    }
  }

  func classValueWithDerivative(_ c: Super) -> (Float, Float) {
    return valueWithDerivative(at: 1) { c.f($0) }
  }

  expectEqual((2, 2), classValueWithDerivative(Super()))
  expectEqual((3, 3), classValueWithDerivative(SubOverride()))
  expectEqual((3, 3), classValueWithDerivative(SubOverrideCustomDerivatives()))
}

ForwardModeTests.test("SimpleWrtSelf") {
  class Super : Differentiable {
    var base: Float
    // FIXME(TF-648): Dummy to make `Super.AllDifferentiableVariables` be nontrivial.
    var _nontrivial: [Float] = []

    // FIXME(SR-12175): Fix forward-mode differentiation tangent buffer crash.
    // @differentiable
    required init(base: Float) {
      self.base = base
    }

    @differentiable(wrt: (self, x))
    func f(_ x: Float) -> Float {
      return base * x
    }
    @derivative(of: f)
    final func jvpf(_ x: Float) -> (value: Float, differential: (TangentVector, Float) -> Float) {
      return (f(x), { (dself, dx) in dself.base * dx })
    }
    @derivative(of: f)
    final func vjpf(_ x: Float) -> (value: Float, pullback: (Float) -> (TangentVector, Float)) {
      let base = self.base
      return (f(x), { v in
        (TangentVector(base: v * x, _nontrivial: []), base * v)
      })
    }
  }

  class SubOverride : Super {
    @differentiable(wrt: (self, x))
    override func f(_ x: Float) -> Float {
      return 3 * x
    }
  }

  class SubOverrideCustomDerivatives : Super {
    @differentiable(wrt: (self, x))
    @differentiable(wrt: x)
    override func f(_ x: Float) -> Float {
      return 3 * x
    }
    @derivative(of: f, wrt: x)
    final func jvpf2(_ x: Float) -> (value: Float, differential: (Float) -> Float) {
      return (f(x), { v in 3 * v })
    }
    @derivative(of: f, wrt: x)
    final func vjpf2(_ x: Float) -> (value: Float, pullback: (Float) -> Float) {
      return (f(x), { v in 3 * v })
    }
  }

    // FIXME(SR-12175): Fix forward-mode differentiation tangent buffer crash.
  // let v = Super.TangentVector(base: 100, _nontrivial: [])
  // expectEqual(100, pullback(at: 1337) { x in Super(base: x) }(v))
  // expectEqual(100, pullback(at: 1337) { x in SubOverride(base: x) }(v))
  // expectEqual(100, pullback(at: 1337) { x in SubOverrideCustomDerivatives(base: x) }(v))

  // `valueWithDerivative` is not used because the derivative requires `Super`
  // to conform to `FloatingPoint`.
  func classDifferential(
    _ c: Super
  ) -> (Float, (Super.TangentVector, Float) -> Float) {
    return valueWithDifferential(at: c, 10) { (c: Super, x: Float) in c.f(x) }
  }

  let (y1, diff1) = classDifferential(Super(base: 5))
  expectEqual(50, y1)
  let c1 = Super.TangentVector(base: 1, _nontrivial: [])
  expectEqual(1, diff1(c1, 1))
  let (y2, diff2) = classDifferential(SubOverride(base: 5))
  expectEqual(30, y2)
  let c2 = SubOverride.TangentVector(base: 1, _nontrivial: [])
  expectEqual(3, diff2(c2, 1))
  let (y3, diff3) = classDifferential(SubOverrideCustomDerivatives(base: 5))
  expectEqual(30, y3)
  let c3 = SubOverrideCustomDerivatives.TangentVector(base: 1, _nontrivial: [])
  expectEqual(3, diff3(c3, 1))
}

//===----------------------------------------------------------------------===//
// Protocols
//===----------------------------------------------------------------------===//

protocol Prot : Differentiable {
  @differentiable(wrt: x)
  func foo(x: Float) -> Float
}
ForwardModeTests.test("Simple Protocol") {
  struct Linear: Prot, AdditiveArithmetic {
    typealias TangentVector = Linear

    let m: Float
    let b: Float

    @differentiable(wrt: x)
    func foo(x: Float) -> Float {
      return m * x + b
    }
  }

  func genericFoo<T: Prot>(_ t: T, _ x: Float) -> Float {
    t.foo(x: x)
  }
  let inst = Linear(m: 5, b: -2)
  let (y1, diff1) = valueWithDifferential(at: 5) { x in genericFoo(inst, x) }
  expectEqual(23, y1)
  expectEqual(5, diff1(1))
}

protocol DiffReq : Differentiable {
  @differentiable(wrt: (self, x))
  func f(_ x: Float) -> Float
}

extension DiffReq where TangentVector : AdditiveArithmetic {
  @inline(never)  // Prevent specialization, to test all witness code.
  func derivF(at x: Float) -> Float {
    return (valueWithDifferential(at: x) { x in self.f(x) }).1(1)
  }
}

struct Quadratic : DiffReq, AdditiveArithmetic {
  typealias TangentVector = Quadratic

  @differentiable
  let a: Float

  @differentiable
  let b: Float

  @differentiable
  let c: Float

  init(_ a: Float, _ b: Float, _ c: Float) {
    self.a = a
    self.b = b
    self.c = c
  }

  @differentiable(wrt: (self, x))
  func f(_ x: Float) -> Float {
    return a * x * x + b * x + c
  }
}

ForwardModeTests.test("ProtocolFunc") {
  expectEqual(12, Quadratic(11, 12, 13).derivF(at: 0))
  expectEqual(2 * 11 + 12, Quadratic(11, 12, 13).derivF(at: 1))
  expectEqual(2 * 11 * 2 + 12, Quadratic(11, 12, 13).derivF(at: 2))
}

// MARK: Constructor, accessor, and subscript requirements.

protocol FunctionsOfX: Differentiable {
  @differentiable
  init(x: Float)

  @differentiable
  var x: Float { get }

  @differentiable
  var y: Float { get }

  @differentiable
  var z: Float { get }

  @differentiable
  subscript() -> Float { get }
}

struct TestFunctionsOfX: FunctionsOfX {
  @differentiable
  init(x: Float) {
    self.x = x
    self.y = x * x
  }

  /// x = x
  var x: Float

  /// y = x * x
  var y: Float

  /// z = x * x + x
  var z: Float {
    return y + x
  }

  @differentiable
  subscript() -> Float {
    return z
  }
}

@inline(never)  // Prevent specialization, to test all witness code.
func derivatives<F: FunctionsOfX>(at x: Float, in: F.Type)
  -> (Float, Float, Float, Float)
{
  let dxdx = derivative(at: x) { x in F(x: x).x }
  let dydx = derivative(at: x) { x in F(x: x).y }
  let dzdx = derivative(at: x) { x in F(x: x).z }
  let dsubscriptdx = derivative(at: x) { x in F(x: x)[] }
  return (dxdx, dydx, dzdx, dsubscriptdx)
}

ForwardModeTests.test("constructor, accessor, subscript") {
  expectEqual(
    (1.0, 4.0, 5.0, 5.0),
    derivatives(at: 2.0, in: TestFunctionsOfX.self))
}

// MARK: - Test witness method SIL type computation.

protocol P : Differentiable {
  @differentiable(wrt: (x, y))
  func foo(_ x: Float, _ y: Double) -> Float
}
struct S : P {
  @differentiable(wrt: (x, y))
  func foo(_ x: Float, _ y: Double) -> Float {
    return x
  }
}

// MARK: - Overridden protocol method adding differentiable attribute.

public protocol Distribution {
  associatedtype Value
  func logProbability(of value: Value) -> Float
}

public protocol DifferentiableDistribution: Differentiable, Distribution {
  @differentiable(wrt: self)
  func logProbability(of value: Value) -> Float
}

struct Foo: DifferentiableDistribution {
  @differentiable(wrt: self)
  func logProbability(of value: Float) -> Float {
    .zero
  }
}

@differentiable
func blah<T: DifferentiableDistribution>(_ x: T) -> Float where T.Value: AdditiveArithmetic {
  x.logProbability(of: .zero)
}

// Adding a more general `@differentiable` attribute.
public protocol DoubleDifferentiableDistribution: DifferentiableDistribution
  where Value: Differentiable {
  @differentiable(wrt: self)
  @differentiable(wrt: (self, value))
  func logProbability(of value: Value) -> Float
}

@differentiable
func blah2<T: DoubleDifferentiableDistribution>(_ x: T, _ value: T.Value) -> Float
  where T.Value: AdditiveArithmetic {
  x.logProbability(of: value)
}

protocol DifferentiableFoo {
  associatedtype T: Differentiable
  @differentiable(wrt: x)
  func foo(_ x: T) -> Float
}

protocol MoreDifferentiableFoo: Differentiable, DifferentiableFoo {
  @differentiable(wrt: (self, x))
  func foo(_ x: T) -> Float
}

struct MoreDifferentiableFooStruct: MoreDifferentiableFoo {
  @differentiable(wrt: (self, x))
  func foo(_ x: Float) -> Float {
    x
  }
}

//===----------------------------------------------------------------------===//
// Simple Math
//===----------------------------------------------------------------------===//

ForwardModeTests.test("Arithmetics") {
  func foo1(x: Float, y: Float) -> Float {
    return x * y
  }
  expectEqual(7, derivative(at: 3, 4, in: foo1))
  func foo2(x: Float, y: Float) -> Float {
    return -x * y
  }
  expectEqual(-7, derivative(at: 3, 4, in: foo2))
  func foo3(x: Float, y: Float) -> Float {
    return -x + y
  }
  expectEqual(0, derivative(at: 3, 4, in: foo3))
}

ForwardModeTests.test("Fanout") {
  func foo1(x: Float) -> Float {
     x - x
  }
  expectEqual(0, derivative(at: 100, in: foo1))
  func foo2(x: Float) -> Float {
     x + x
  }
  expectEqual(2, derivative(at: 100, in: foo2))
  func foo3(x: Float, y: Float) -> Float {
    x + x + x * y
  }
  expectEqual(7, derivative(at: 3, 2, in: foo3))
}

ForwardModeTests.test("FunctionCall") {
  func foo(_ x: Float, _ y: Float) -> Float {
    return 3 * x + { $0 * 3 }(3) * y
  }
  expectEqual(12, derivative(at: 3, 4, in: foo))
  expectEqual(3, derivative(at: 3) { x in foo(x, 4) })
}

ForwardModeTests.test("ResultSelection") {
  func tuple(_ x: Float, _ y: Float) -> (Float, Float) {
    return (x + 1, y + 2)
  }
  expectEqual(1, derivative(at: 3, 3, in: { x, y in tuple(x, y).0 }))
  expectEqual(1, derivative(at: 3, 3, in: { x, y in tuple(x, y).1 }))

  // FIXME(SR-12175): Fix forward-mode differentiation tangent buffer crash.
  /*
  func tupleGeneric<T>(_ x: T, _ y: T) -> (T, T) {
    return (x, y)
  }
  func tupleGenericFirst<T>(_ x: T, _ y: T) -> T { tupleGeneric(x, y).0 }
  func tupleGenericSecond<T>(_ x: T, _ y: T) -> T { tupleGeneric(x, y).1 }
  expectEqual(1, derivative(at: 3, 3, in: tupleGenericFirst))
  expectEqual(1, derivative(at: 3, 3, in: tupleGenericSecond))
  */
}

// TODO(TF-983): Support forward-mode differentiation of multiple results.
/*
ForwardModeTests.test("MultipleResults") {
  // Test function returning a tuple of active results.
  func tuple(_ x: Float, _ y: Float) -> (Float, Float) {
    return (x, y)
  }
  func multiply(_ x: Float, _ y: Float) -> Float {
    let z = tuple(x, y)
    // Note: both results (tuple elements) are active.
    return z.0 * z.1
  }
  expectEqual((4, 3), gradient(at: 3, 4, in: multiply))
  expectEqual((10, 5), gradient(at: 5, 10, in: multiply))

  // Test function with multiple `inout` parameters.
  func swap(_ x: inout Float, _ y: inout Float) {
    let tmp = x; x = y; y = tmp
  }
  func multiply_swap(_ x: Float, _ y: Float) -> Float {
    var tuple = (x, y)
    swap(&tuple.0, &tuple.1)
    return tuple.0 * tuple.1
  }
  expectEqual((4, 3), gradient(at: 3, 4, in: multiply_swap))
  expectEqual((10, 5), gradient(at: 5, 10, in: multiply_swap))

  // Test function with multiple `inout` parameters.
  func swapGeneric<T>(_ x: inout T, _ y: inout T) {
    let tmp = x; x = y; y = tmp
  }
  func multiply_swapGeneric(_ x: Float, _ y: Float) -> Float {
    var tuple = (x, y)
    swapGeneric(&tuple.0, &tuple.1)
    return tuple.0 * tuple.1
  }
  expectEqual((4, 3), gradient(at: 3, 4, in: multiply_swapGeneric))
  expectEqual((10, 5), gradient(at: 5, 10, in: multiply_swapGeneric))

  // Test function with multiple `inout` parameters and a formal result.
  func swapAndReturnProduct(_ x: inout Float, _ y: inout Float) -> Float {
    let tmp = x
    x = y
    y = tmp
    return x * y
  }
  func multiply_swapAndReturnProduct(_ x: Float, _ y: Float) -> Float {
    var x2 = x
    var y2 = y
    let result = swapAndReturnProduct(&x2, &y2)
    return result
  }
  expectEqual((4, 3), gradient(at: 3, 4, in: multiply_swapAndReturnProduct))
  expectEqual((4, 3), gradient(at: 3, 4, in: multiply_swapAndReturnProduct))
}
*/

ForwardModeTests.test("CaptureLocal") {
  let z: Float = 10
  func foo(_ x: Float) -> Float {
    return z * x
  }
  expectEqual(10, derivative(at: 0, in: foo))
}

var globalVar: Float = 10
ForwardModeTests.test("CaptureGlobal") {
  func foo(x: Float) -> Float {
    globalVar += 20
    return globalVar * x
  }
  expectEqual(30, derivative(at: 0, in: foo))
}

ForwardModeTests.test("Mutation") {
  func fourthPower(x: Float) -> Float {
    var a = x
    a = a * x
    a = a * x
    return a * x
  }
  expectEqual(4 * 27, derivative(at: 3, in: fourthPower))
}

// Tests TF-21.
ForwardModeTests.test("StructMemberwiseInitializer") {
  struct Foo : AdditiveArithmetic, Differentiable {
    var stored: Float
    var computed: Float {
      return stored * stored
    }
  }

  let derivFoo = differential(at: Float(4), in: { input -> Foo in
    let foo = Foo(stored: input)
    let foo2 = foo + foo
    return Foo(stored: foo2.stored)
  })(1)
  expectEqual(Foo.TangentVector(stored: 2), derivFoo)

  let computed = derivative(at: Float(4)) { input -> Float in
    let foo = Foo(stored: input)
    return foo.computed
  }
  expectEqual(8, computed)

  let derivProduct = derivative(at: Float(4)) { input -> Float in
    let foo = Foo(stored: input)
    return foo.computed * foo.stored
  }
  expectEqual(48, derivProduct)

  struct Custom : AdditiveArithmetic, Differentiable {
    var x: Float

    // Custom initializer with `@differentiable`.
    @differentiable
    init(x: Float) {
      self.x = x
    }
  }

  let derivCustom = differential(at: Float(4), in: { input -> Custom in
    let foo = Custom(x: input)
    return foo + foo
  })(1)
  expectEqual(Custom.TangentVector(x: 2), derivCustom)
}

// Tests TF-319: struct with non-differentiable constant stored property.
ForwardModeTests.test("StructConstantStoredProperty") {
  struct TF_319 : Differentiable {
    var x: Float
    @noDerivative let constant = Float(2)

    @differentiable
    init(x: Float) {
      self.x = x
    }

    @differentiable(wrt: (self, input))
    func applied(to input: Float) -> Float {
      return x * constant * input
    }
  }
  func testStructInit(to input: Float) -> Float {
    let model = TF_319(x: 10)
    return model.applied(to: input)
  }
  expectEqual(6, derivative(at: 10, in: { TF_319(x: $0).applied(to: 3) }))
  expectEqual(20, derivative(at: 3, in: testStructInit))
}

ForwardModeTests.test("StructMutation") {
  struct Point : AdditiveArithmetic, Differentiable {
    var x: Float
    var y: Float
    var z: Float
  }

  func double(_ input: Float) -> Point {
    let point = Point(x: input, y: input, z: input)
    return point + point
  }
  expectEqual(Point(x: 2, y: 2, z: 2), differential(at: 4, in: double)(1))

  func fifthPower(_ input: Float) -> Float {
    var point = Point(x: input, y: input, z: input)
    point.x = point.x * input
    point.y = point.x * input
    return point.x * point.y
  }
  expectEqual(405, derivative(at: 3, in: fifthPower))

  func mix(_ input: Float) -> Float {
    var tuple = (point: Point(x: input, y: input, z: input), float: input)
    tuple.point.x = tuple.point.x * tuple.float
    tuple.point.y = tuple.point.x * input
    return tuple.point.x * tuple.point.y
  }
  expectEqual(405, derivative(at: 3, in: mix))

  // Test TF-282.
  struct Add : Differentiable {
    var bias: Float
    func applied(to input: Float) -> Float {
      var tmp = input
      tmp = tmp + bias
      return tmp
    }
  }
  expectEqual(1, derivative(at: 1) { m in Add(bias: m).applied(to: 1) })
}

ForwardModeTests.test("StructGeneric") {
  struct Generic<T : AdditiveArithmetic & Differentiable> : AdditiveArithmetic, Differentiable {
    var x: T
    var y: T
    var z: T
  }

  let deriv = differential(at: Float(3), in: { input -> Generic<Float> in
    var generic = Generic(x: input, y: input, z: input)
    return generic
  })(1)
  expectEqual(Generic<Float>.TangentVector(x: 1, y: 1, z: 1), deriv)

  func fifthPower(_ input: Float) -> Float {
    var generic = Generic(x: input, y: input, z: input)
    generic.x = generic.x * input
    generic.y = generic.x * input
    return generic.x * generic.y
  }
  expectEqual(405, derivative(at: 3, in: fifthPower))
}

ForwardModeTests.test("SubsetIndices") {
  func deriv(_ lossFunction: @differentiable (Float, Float) -> Float) -> Float {
    return derivative(at: 1) { x in lossFunction(x * x, 10.0) }
  }
  expectEqual(2, deriv { x, y in x + y })

  func derivWRTNonDiff(_ lossFunction: @differentiable (Float, @noDerivative Int) -> Float) -> Float {
    return derivative(at: 2) { x in lossFunction(x * x, 10) }
  }
  expectEqual(4, derivWRTNonDiff { x, y in x + Float(y) })
}

ForwardModeTests.test("ForceUnwrapping") {
  func forceUnwrap<T: Differentiable & FloatingPoint>(_ t: T) -> Float where T == T.TangentVector {
    derivative(at: t, Float(3)) { (x, y) in
      (x as! Float) * y
    }
  }
  expectEqual(5, forceUnwrap(Float(2)))
}

ForwardModeTests.test("NonVariedResult") {
  @differentiable(wrt: x)
  func nonWrtInoutParam<T: Differentiable>(_ x: T, _ y: inout T) {
    y = x
  }

  @differentiable
  func wrtInoutParam<T: Differentiable>(_ x: T, _ y: inout T) {
    y = x
  }

  @differentiable(wrt: x)
  func nonWrtInoutParamNonVaried<T: Differentiable>(_ x: T, _ y: inout T) {}

  @differentiable(wrt: x)
  func wrtInoutParamNonVaried<T: Differentiable>(_ x: T, _ y: inout T) {}

  @differentiable
  func variedResultTracked(_ x: Tracked<Float>) -> Tracked<Float> {
    var result: Tracked<Float> = 0
    nonWrtInoutParam(x, &result)
    return result
  }

  @differentiable
  func variedResultTracked2(_ x: Tracked<Float>) -> Tracked<Float> {
    var result: Tracked<Float> = 0
    wrtInoutParam(x, &result)
    return result
  }

  @differentiable
  func nonVariedResultTracked(_ x: Tracked<Float>) -> Tracked<Float> {
    var result: Tracked<Float> = 0
    nonWrtInoutParamNonVaried(x, &result)
    return result
  }

  @differentiable
  func nonVariedResultTracked2(_ x: Tracked<Float>) -> Tracked<Float> {
    // expected-warning @+1 {{variable 'result' was never mutated}}
    var result: Tracked<Float> = 0
    return result
  }

  @differentiable
  func nonVariedResultTracked3(_ x: Tracked<Float>) -> Tracked<Float> {
    return 0
  }

  @differentiable
  func nonVariedResultTracked4(_ x: Tracked<Float>) -> Tracked<Float> {
    var result: Tracked<Float> = 0
    wrtInoutParamNonVaried(x, &result)
    return result
  }
}

ForwardModeTests.test("ApplyNonActiveIndirectResult") {
  func identity<T: Differentiable>(_ x: T) -> T { x }

  @differentiable
  func applyNonactiveArgumentActiveIndirectResult(_ x: Tracked<Float>) -> Tracked<Float> {
    var y = identity(0 as Tracked<Float>)
    y = x
    return y
  }
  expectEqual(1.0, derivative(at: 2, in: applyNonactiveArgumentActiveIndirectResult))
}

//===----------------------------------------------------------------------===//
// Array methods from ArrayDifferentiation.swift
//===----------------------------------------------------------------------===//

typealias FloatArrayTan = Array<Float>.TangentVector

ForwardModeTests.test("Array.+") {
  func sumFirstThreeConcatenating(_ a: [Float], _ b: [Float]) -> Float {
    let c = a + b
    return c[0] + c[1] + c[2]
  }

  expectEqual(3, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([1, 1]), .init([1, 1])))
  expectEqual(0, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([0, 0]), .init([0, 1])))
  expectEqual(1, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([0, 1]), .init([0, 1])))
  expectEqual(1, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([1, 0]), .init([0, 1])))
  expectEqual(1, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([0, 0]), .init([1, 1])))
  expectEqual(2, differential(at: [0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([1, 1]), .init([0, 1])))

  expectEqual(
    3,
    differential(at: [0, 0, 0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([1, 1, 1, 1]), .init([1, 1])))
  expectEqual(
    3,
    differential(at: [0, 0, 0, 0], [0, 0], in: sumFirstThreeConcatenating)(.init([1, 1, 1, 0]), .init([0, 0])))
  
  expectEqual(
    3,
    differential(at: [], [0, 0, 0, 0], in: sumFirstThreeConcatenating)(.init([]), .init([1, 1, 1, 1])))
  expectEqual(
    0,
    differential(at: [], [0, 0, 0, 0], in: sumFirstThreeConcatenating)(.init([]), .init([0, 0, 0, 1])))
}

ForwardModeTests.test("Array.init(repeating:count:)") {
  @differentiable
  func repeating(_ x: Float) -> [Float] {
    Array(repeating: x, count: 10)
  }
  expectEqual(Float(10), derivative(at: .zero) { x in
    repeating(x).differentiableReduce(0, {$0 + $1})
  })
  expectEqual(Float(20), differential(at: .zero, in: { x in
    repeating(x).differentiableReduce(0, {$0 + $1})
  })(2))
}

ForwardModeTests.test("Array.DifferentiableView.init") {
  @differentiable
  func constructView(_ x: [Float]) -> Array<Float>.DifferentiableView {
    return Array<Float>.DifferentiableView(x)
  }

  let forward = differential(at: [5, 6, 7, 8], in: constructView)
  expectEqual(
    FloatArrayTan([1, 2, 3, 4]),
    forward(FloatArrayTan([1, 2, 3, 4])))
}

ForwardModeTests.test("Array.DifferentiableView.base") {
  @differentiable
  func accessBase(_ x: Array<Float>.DifferentiableView) -> [Float] {
    return x.base
  }

  let forward = differential(
    at: Array<Float>.DifferentiableView([5, 6, 7, 8]),
    in: accessBase)
  expectEqual(
    FloatArrayTan([1, 2, 3, 4]),
    forward(FloatArrayTan([1, 2, 3, 4])))
}

ForwardModeTests.test("Array.differentiableMap") {
  let x: [Float] = [1, 2, 3]
  let tan = Array<Float>.TangentVector([1, 1, 1])

  func multiplyMap(_ a: [Float]) -> [Float] {
    return a.differentiableMap({ x in 3 * x })
  }
  expectEqual([3, 3, 3], differential(at: x, in: multiplyMap)(tan))

  func squareMap(_ a: [Float]) -> [Float] {
    return a.differentiableMap({ x in x * x })
  }
  expectEqual([2, 4, 6], differential(at: x, in: squareMap)(tan))
}

ForwardModeTests.test("Array.differentiableReduce") {
  let x: [Float] = [1, 2, 3]
  let tan = Array<Float>.TangentVector([1, 1, 1])

  func sumReduce(_ a: [Float]) -> Float {
    return a.differentiableReduce(0, { $0 + $1 })
  }
  expectEqual(1 + 1 + 1, differential(at: x, in: sumReduce)(tan))

  func productReduce(_ a: [Float]) -> Float {
    return a.differentiableReduce(1, { $0 * $1 })
  }
  expectEqual(x[1] * x[2] + x[0] * x[2] + x[0] * x[1], differential(at: x, in: productReduce)(tan))

  func sumOfSquaresReduce(_ a: [Float]) -> Float {
    return a.differentiableReduce(0, { $0 + $1 * $1 })
  }
  expectEqual(2 * x[0] + 2 * x[1] + 2 * x[2], differential(at: x, in: sumOfSquaresReduce)(tan))
}

//===----------------------------------------------------------------------===//
// SIMD methods from SIMDDifferentiation.swift.gyb
// Tests replicate reverse mode tests from test/AutoDiff/stdlib/simd.swift
//===----------------------------------------------------------------------===//

ForwardModeTests.test("init(repeating:)") {
  func foo1(x: Float) -> SIMD4<Float> {
    return SIMD4<Float>(repeating: 2 * x)
  }
  let (val1, df1) = valueWithDifferential(at: 5, in: foo1)
  expectEqual(SIMD4<Float>(10, 10, 10, 10), val1)
  expectEqual(SIMD4<Float>(6, 6, 6, 6), df1(3))
}

ForwardModeTests.test("Identity") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let g = SIMD4<Float>(1, 1, 1, 1)

  func foo1(x: SIMD4<Float>) -> SIMD4<Float> {
    return x
  }
  let (val1, df1) = valueWithDifferential(at: a, in: foo1)
  expectEqual(a, val1)
  expectEqual(g, df1(.init(g)))
}

ForwardModeTests.test("Negate") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let g = SIMD4<Float>(1, 1, 1, 1)

  func foo1(x: SIMD4<Float>) -> SIMD4<Float> {
    return -x
  }
  let (val1, df1) = valueWithDifferential(at: a, in: foo1)
  expectEqual(-a, val1)
  expectEqual(-g, df1(.init(g)))
}

ForwardModeTests.test("subscript") {
  let a = SIMD4<Float>(1, 2, 3, 4)

  func foo1(x: SIMD4<Float>) -> Float {
    return x[3]
  }

  let (val1, df1) = valueWithDifferential(at: a, in: foo1)
  expectEqual(4, val1)
  expectEqual(4, df1(a))
}

ForwardModeTests.test("Addition") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let g = SIMD4<Float>(1, 1, 1, 1)

  // SIMD + SIMD
  func foo1(x: SIMD4<Float>, y: SIMD4<Float>) -> SIMD4<Float> {
    return x + y
  }
  let (val1, df1) = valueWithDifferential(at: a, a, in: foo1)
  expectEqual(SIMD4<Float>(2, 4, 6, 8), val1)
  expectEqual(a + g, df1(a, g))

  // SIMD + Scalar
  func foo2(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return x + y
  }
  let (val2, df2) = valueWithDifferential(at: a, 5, in: foo2)
  expectEqual(SIMD4<Float>(6, 7, 8, 9), val2)
  expectEqual(g + 1, df2(g, 1))

  // Scalar + SIMD
  func foo3(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return y + x
  }
  let (val3, df3) = valueWithDifferential(at: a, 5, in: foo3)
  expectEqual(SIMD4<Float>(6, 7, 8, 9), val3)
  expectEqual(2 + g, df3(g, 2))
}

ForwardModeTests.test("Subtraction") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let g = SIMD4<Float>(1, 1, 1, 1)

  // SIMD - SIMD
  func foo1(x: SIMD4<Float>, y: SIMD4<Float>) -> SIMD4<Float> {
    return x - y
  }
  let (val1, df1) = valueWithDifferential(at: a, a, in: foo1)
  expectEqual(SIMD4<Float>(0, 0, 0, 0), val1)
  expectEqual(g - a, df1(g, a))

  // SIMD - Scalar
  func foo2(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return x - y
  }
  let (val2, df2) = valueWithDifferential(at: a, 5, in: foo2)
  expectEqual(SIMD4<Float>(-4, -3, -2, -1), val2)
  expectEqual(g - 1, df2(g, 1))

  // Scalar - SIMD
  func foo3(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return y - x
  }
  let (val3, df3) = valueWithDifferential(at: a, 5, in: foo3)
  expectEqual(SIMD4<Float>(4, 3, 2, 1), val3)
  expectEqual(2 - g, df3(g, 2))
}

ForwardModeTests.test("Multiplication") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let a2 = SIMD4<Float>(4, 3, 2, 1)
  let g = SIMD4<Float>(1, 1, 1, 1)
  let g2 = SIMD4<Float>(0, 2, 1, 3)

  // SIMD * SIMD
  func foo1(x: SIMD4<Float>, y: SIMD4<Float>) -> SIMD4<Float> {
    return x * y
  }
  let (val1, df1) = valueWithDifferential(at: a, a2, in: foo1)
  expectEqual(a * a2, val1)
  expectEqual(a * g2 + g * a2, df1(g, g2))

  // SIMD * Scalar
  func foo2(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return x * y
  }
  let (val2, df2) = valueWithDifferential(at: a, 5, in: foo2)
  expectEqual(a * 5, val2)
  expectEqual(a * 2 + g * 5, df2(g, 2))

  // Scalar * SIMD
  func foo3(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return y * x
  }
  let (val3, df3) = valueWithDifferential(at: a, 5, in: foo3)
  expectEqual(a * 5, val3)
  expectEqual(a * 3 + g * 5, df3(g, 3))
}

ForwardModeTests.test("Division") {
  let a = SIMD4<Float>(1, 2, 3, 4)
  let g = SIMD4<Float>(1, 1, 1, 1)

  // SIMD / SIMD
  func foo1(x: SIMD4<Float>, y: SIMD4<Float>) -> SIMD4<Float> {
    return x / y
  }
  let (val1, df1) = valueWithDifferential(at: a, a, in: foo1)
  expectEqual(a / a, val1)
  expectEqual((g * a - a * g) / (a * a)/* == 0 */, df1(g, g))

  // SIMD / Scalar
  func foo2(x: SIMD4<Float>, y: Float) -> SIMD4<Float> {
    return x / y
  }
  let (val2, df2) = valueWithDifferential(at: a, 5, in: foo2)
  expectEqual(a / 5, val2)
  expectEqual((g * 5 - a * 2) / (5 * 5), df2(g, 2))

  // Scalar / SIMD
  func foo3(x: Float, y: SIMD4<Float>) -> SIMD4<Float> {
    return x / y
  }
  let (val3, df3) = valueWithDifferential(at: 5, a, in: foo3)
  expectEqual(5 / a, val3)
  expectEqual((3 * a - 5 * g) / (a * a), df3(3, g))
}

ForwardModeTests.test("Generics") {
  let a = SIMD3<Double>(1, 2, 3)
  let g = SIMD3<Double>(1, 1, 1)

  // FIXME(SR-13210): Fix forward-mode SIL verification error.
  /*
  func testInit<Scalar, SIMDType: SIMD>(x: Scalar) -> SIMDType
    where SIMDType.Scalar == Scalar,
          SIMDType : Differentiable,
          Scalar : BinaryFloatingPoint & Differentiable,
          SIMDType.TangentVector == SIMDType,
          Scalar.TangentVector == Scalar {
    return SIMDType.init(repeating: x)
  }
  func simd3Init(x: Double) -> SIMD3<Double> { testInit(x: x) }
  let (val1, df1) = valueWithDifferential(at: 10, in: simd3Init)
  expectEqual(SIMD3<Double>(10, 10, 10), val1)
  expectEqual(SIMD3<Double>(5, 5, 5), df1(5))
  */

  // SIMDType + SIMDType
  func testAddition<Scalar, SIMDType: SIMD>(lhs: SIMDType, rhs: SIMDType)
    -> SIMDType
    where SIMDType.Scalar == Scalar,
          SIMDType : Differentiable,
          SIMDType.TangentVector : SIMD,
          Scalar : BinaryFloatingPoint,
          SIMDType.TangentVector.Scalar : BinaryFloatingPoint {
    return lhs + rhs
  }
  func simd3Add(lhs: SIMD3<Double>, rhs: SIMD3<Double>) -> SIMD3<Double> {
    return testAddition(lhs: lhs, rhs: rhs)
  }
  let (val2, df2) = valueWithDifferential(at: a, a, in: simd3Add)
  expectEqual(SIMD3<Double>(2, 4, 6), val2)
  expectEqual(g + a, df2(g, a))

  // Scalar - SIMDType
  func testSubtraction<Scalar, SIMDType: SIMD>(lhs: Scalar, rhs: SIMDType)
    -> SIMDType
    where SIMDType.Scalar == Scalar,
          SIMDType : Differentiable,
          Scalar : BinaryFloatingPoint & Differentiable,
          SIMDType.TangentVector == SIMDType,
          Scalar.TangentVector == Scalar {
    return lhs - rhs
  }
  func simd3Subtract(lhs: Double, rhs: SIMD3<Double>) -> SIMD3<Double> {
    return testSubtraction(lhs: lhs, rhs: rhs)
  }
  let (val3, df3) = valueWithDifferential(at: 5, a, in: simd3Subtract)
  expectEqual(SIMD3<Double>(4, 3, 2), val3)
  expectEqual(2 - g, df3(2, g))

  // SIMDType * Scalar
  func testMultipication<Scalar, SIMDType: SIMD>(lhs: SIMDType, rhs: Scalar)
    -> SIMDType
    where SIMDType.Scalar == Scalar,
      SIMDType : Differentiable,
      Scalar : BinaryFloatingPoint & Differentiable,
      SIMDType.TangentVector == SIMDType,
      Scalar.TangentVector == Scalar {
    return lhs * rhs
  }
  func simd3Multiply(lhs: SIMD3<Double>, rhs: Double) -> SIMD3<Double> {
    return testMultipication(lhs: lhs, rhs: rhs)
  }
  let (val4, df4) = valueWithDifferential(at: a, 5, in: simd3Multiply)
  expectEqual(SIMD3<Double>(5, 10, 15), val4)
  expectEqual(a * 3 + g * 5 , df4(g, 3))
}

runAllTests()