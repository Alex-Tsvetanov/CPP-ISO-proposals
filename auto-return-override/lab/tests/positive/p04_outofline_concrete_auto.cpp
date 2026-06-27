// EXPECT-PASS
// Out-of-line combination (3): written-out declaration + auto definition.
struct A { virtual int f() = 0; };
struct B : A { int f() override; };
auto B::f() { return 3; }     // auto denotes the overridden type, int
