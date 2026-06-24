#include <iostream>

void fizzbuzz(int start = 1, int end = 100) {
    for (int i = start; i <= end; ++i) {
        if (i % 15 == 0) {
            std::cout << "FizzBuzz\n";
        } else if (i % 3 == 0) {
            std::cout << "Fizz\n";
        } else if (i % 5 == 0) {
            std::cout << "Buzz\n";
        } else {
            std::cout << i << '\n';
        }
    }
}

int main() {
    fizzbuzz();
    return 0;
}
