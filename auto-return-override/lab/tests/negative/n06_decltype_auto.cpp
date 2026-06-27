// EXPECT-FAIL: cannot be virtual
// Out of scope: only the bare `auto` placeholder is permitted. `decltype(auto)` on a
// virtual override remains ill-formed.
struct A { virtual int f() = 0; };
struct B : A {
  decltype(auto) f() override { return 3; }   // not bare auto -> still prohibited
};
