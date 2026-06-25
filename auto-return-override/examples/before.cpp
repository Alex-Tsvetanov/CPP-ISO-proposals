// Current state of the art: the override must restate the base return type,
// either literally or by reconstructing it with decltype/declval.
//
// Compile: g++ -std=c++20 before.cpp -o before

#include <concepts>
#include <utility>

class A {
public:
    virtual int test() { return 5; }
};

static_assert(std::is_same_v<decltype(std::declval<A>().test()), int>);

class B : public A {
public:
    // The trailing-return-type is pure boilerplate that names A and test again.
    auto test() -> decltype(std::declval<A>().test()) override {
        return 6;
    }
};

int main() {
    A* p = new B();
    return p->test() == 6 ? 0 : 1;
}
