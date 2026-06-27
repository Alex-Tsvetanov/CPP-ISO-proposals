// EXPECT-PASS
// Basic case: auto override of a simple virtual; return type is the base's (int).
struct A { virtual int test() { return 5; } };
struct B : A {
  auto test() override { return 6; }   // return type: int
};
int main() { B b; return b.test() == 6 ? 0 : 1; }
