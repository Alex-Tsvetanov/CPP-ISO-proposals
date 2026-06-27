// EXPECT-FAIL: cannot be virtual
// The feature is gated on `override`. A virtual auto WITHOUT override stays ill-formed,
// exactly as today.
struct A { virtual int f() = 0; };
struct B : A {
  auto f() { return 3; }   // no `override` -> still prohibited
};
