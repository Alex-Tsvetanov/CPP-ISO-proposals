// EXPECT-FAIL: does not match
// The footgun the proposal closes: body yields const char*, override says bool.
// Must be rejected (NOT silently converted to true).
struct A { virtual bool f() = 0; };
struct B : A {
  auto f() override { return "pumpkin"; }   // const char* != bool  -> ill-formed
};
