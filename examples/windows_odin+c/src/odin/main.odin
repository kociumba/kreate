package main

foreign import mylib "mylib.o"

foreign mylib {
    hello_from_c :: proc() ---
}

main :: proc() {
    hello_from_c()
}