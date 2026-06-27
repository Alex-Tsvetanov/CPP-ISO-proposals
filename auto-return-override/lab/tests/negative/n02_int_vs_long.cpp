// EXPECT-FAIL: does not match
// No silent widening: base returns long, return operand is int.
struct A { virtual long f() = 0; };
struct B : A {
  auto f() override { return 0; }   // 0 is int, not long -> ill-formed (write 0L or a cast)
};
