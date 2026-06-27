// EXPECT-FAIL: does not match
// Out-of-line combination with a DISAGREEING written-out definition: declaration is
// `auto … override` (type fixed to int by the base), definition spells `long`.
struct A { virtual int f() = 0; };
struct B : A { auto f() override; };
long B::f() { return 3; }     // long != A::f's int -> ill-formed
