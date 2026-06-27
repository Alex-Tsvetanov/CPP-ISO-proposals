// EXPECT-PASS
// The motivating case: a verbose/dependent base return type that the override would
// otherwise have to restate verbatim (or reconstruct with decltype).
#include <map>
#include <string>
#include <memory>
struct Base {
  virtual std::map<std::string, std::unique_ptr<int>> snapshot() = 0;
};
struct Derived : Base {
  auto snapshot() override {                  // == std::map<std::string,std::unique_ptr<int>>
    return std::map<std::string, std::unique_ptr<int>>{};
  }
};
