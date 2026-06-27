// EXPECT-PASS
// Out-of-line combination (1): auto declaration + auto definition.
struct A { virtual int f() = 0; };
struct B : A { auto f() override; };
auto B::f() { return 3; }     // deduces the overridden type, int
