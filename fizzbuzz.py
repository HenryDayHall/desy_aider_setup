#!/usr/bin/env python3
"""
FizzBuzz implementation.

Prints numbers from 1 to 100, but for multiples of three prints "Fizz"
instead of the number, for multiples of five prints "Buzz", and for numbers
which are multiples of both three and five prints "FizzBuzz".
"""

def fizzbuzz(start: int = 1, end: int = 100) -> None:
    """Print the FizzBuzz sequence from start to end inclusive."""
    i = start
    while i <= end:
        output = ''
        if i % 3 == 0:
            output += 'Fizz'
        if i % 5 == 0:
            output += 'Buzz'
        print(output or i)
        i += 1


if __name__ == '__main__':
    fizzbuzz()
