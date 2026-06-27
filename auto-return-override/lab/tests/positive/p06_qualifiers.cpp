// EXPECT-PASS
// Qualifiers are orthogonal to the return type: const / noexcept overrides still work.
struct A {
  virtual int f() const { return 1; }
  virtual int g() noexcept { return 2; }
};
struct B : A {
  auto f() const override { return 10; }
  auto g() noexcept override { return 20; }
};
