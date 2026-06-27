// EXPECT-PASS
// Out-of-line combination (2): auto declaration + written-out definition that matches.
struct A { virtual int f() = 0; };
struct B : A { auto f() override; };
int B::f() { return 3; }      // int matches A::f's return type
