// Proposed: a virtual override written with the bare `auto` placeholder and the
// `override` specifier deduces its return type to be exactly the overridden
// function's return type.
//
// NOTE: This does NOT compile with current compilers. It illustrates the syntax
// this proposal would make well-formed.

#include <concepts>
#include <utility>

class A {
public:
    virtual int test() { return 5; }
};

static_assert(std::is_same_v<decltype(std::declval<A>().test()), int>);

class B : public A {
public:
    // Return type is taken from A::test -> int. No trailing-return-type needed.
    auto test() override {
        return 6;
    }
};

int main() {
    A* p = new B();
    return p->test() == 6 ? 0 : 1;
}
