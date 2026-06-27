// EXPECT-FAIL: does not match
// Multiple inheritance: the overridden functions disagree on return type, so there is no
// single type to adopt -> ill-formed.
struct A { virtual int  f() { return 1; } };
struct C { virtual long f() { return 2; } };
struct D : A, C {
  auto f() override { return 0; }   // A::f -> int, C::f -> long : ill-formed
};
