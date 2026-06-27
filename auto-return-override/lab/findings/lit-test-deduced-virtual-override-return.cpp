// RUN: %clang_cc1 -std=c++2c -fsyntax-only -verify %s
// RUN: %clang_cc1 -std=c++2c -fsyntax-only -verify -DMACRO %s

// Tests for "Deduced return type for overriding functions via `auto`": a virtual
// function declared with the bare `auto` placeholder and `override` adopts the
// overridden function's return type, fixed at the declaration.

#ifdef MACRO
#if __cpp_deduced_virtual_override_return != 202606L
#error feature-test macro has the wrong value
#endif
// expected-no-diagnostics
#else

// --- basic: return type is the overridden type (int) ---
struct A { virtual int test() { return 5; } };
struct B : A {
  auto test() override { return 6; }   // ok: int
};

// --- the return type is fixed even with no in-class body ---
struct Abase { virtual int f() = 0; };
struct Decl : Abase { auto f() override; };   // ok: int
int g_decl() { Decl *d = nullptr; return d->f(); }

// --- out-of-line: all four combinations of auto / written-out ---
struct OO1 : Abase { auto f() override; };
auto OO1::f() { return 3; }            // ok: auto definition deduces int

struct OO2 : Abase { auto f() override; };
int  OO2::f() { return 3; }            // ok: int matches the overridden type

struct OO3 : Abase { int  f() override; };
auto OO3::f() { return 3; }            // ok: auto denotes the overridden int

// --- dependent / verbose base return type, restated for free ---
template <class T> struct Holder {};
struct VBase { virtual Holder<int> snapshot() = 0; };
struct VDer : VBase {
  auto snapshot() override { return Holder<int>{}; }   // ok
};

// --- qualifiers are orthogonal ---
struct Q { virtual int f() const { return 1; } virtual int g() noexcept { return 2; } };
struct QD : Q {
  auto f() const override { return 10; }     // ok
  auto g() noexcept override { return 20; }  // ok
};

// --- return operand must already have the overridden type (no conversion) ---
struct Pbool { virtual bool f() = 0; };
struct Pder : Pbool {
  auto f() override { return "pumpkin"; }  // expected-error {{does not match}}
};

struct Plong { virtual long f() = 0; virtual long h() = 0; };
struct Plder : Plong {
  auto f() override { return 0; }          // expected-error {{does not match}}
  auto h() override { return 0L; }         // ok: 0L already has type long
};

// --- `override` is required (a virtual `auto` without it stays ill-formed) ---
struct NoKw : Abase {
  auto f() { return 3; }   // expected-error {{cannot be virtual}}
};

// --- multiple inheritance with disagreeing return types ---
struct MA { virtual int  f() { return 1; } };
struct MC { virtual long f() { return 2; } };
struct MD : MA, MC {
  auto f() override { return 0; }   // expected-error {{does not match a unique type}}
};

// --- out-of-line written-out definition that disagrees ---
struct N5 : Abase { auto f() override; };  // expected-note {{previous declaration is here}}
long N5::f() { return 3; }           // expected-error {{does not match}}

// --- decltype(auto) is out of scope ---
struct D6 : Abase {
  decltype(auto) f() override { return 3; }   // expected-error {{cannot be virtual}}
};

#endif
