* [Next: Control flow](control.md)
* [Prev: First program](first_program.md)
* [Main Page](index.md)

* * *

# Variables

Variable can store a value that can be used later.
A variable is defined by its type and must be declared before use.

`int a = 0;`
Here we created a variable **a** of type **int** initialized with the value **0**.

If we print the content of a with 'print(a)'. The prompt will display **0**.

A variable must be initialized before accessing its content, else it will raise an error !

## Basic Types
They're only a handful of basic type recognised by grimoire.
* Void type
* Integer declared with **int** ex: 2
* Floating number declared with **float** ex: 2.35f
* Boolean declared with **bool** ex: true, false
* String declared with **string** ex: "Hello"
* Array (see Array section)
* Function/Task (see Anonymous Functions section)
* Channel (see Channel section)
* Structure type
* Custom type (User defined type in D)
* Tuple (See Tuple section)

### Auto Type
**let** is a special keyword that let the compiler automatically infer the type of a declared variable.
Example:
```cpp
main {
  let a = 3.2; //'a' is inferred to be a float type.
  print(a);
}
```
let can only be used on variable declaration and cannot be part of a function signature because it's not a type !

## Scope
A variable can either be local or global.
* A global variable is declared outside of any function/task/etc and is accessible in everywhere in every file.
* A local variable is only accessible inside the function/task/etc where it was declared.

Example:
```cpp
int globalVar; //Declared outside of any scope, accessible everywhere.

main {
  int localVar; //Declared inside the main, only accessible within the main.
}
```

## Declaration List

You can also declare multiple variables at once separating each identifier with a comma. `int a, b;`

Initialization will be done in the same order:
`int a, b = 2, 3;` Here *a = 2* and *b = 3*.

If there is not enough values to assign, the other variable will be assigned the last value: `int a, b, c = 2, 3;` Here *a = 2*, *b = 3*, *c = 3*.

You can skip one or more values by leaving a blank comma, it'll then copy the last value:

`int a, b, c = 12,, 5;`
Both *a* and *b* are equal to *12* while *c* is equal to 5.

`int a, b, c, d = 12,,, 5;`
Both *a*, *b*, and *c* are equal to *12* while *c* is equal to 5.

The first value cannot be blank, you cannot do this: `int a, b, c = , 5, 2;`


Every variable on the same initialization list must be of the same type.
Ex: `int a, b = 2, "Hi"` will raise an error because *b* is expected to be **int** and you are passing a **string**.

But you can use **let** to initialize automatically different types :
`let a, b, c, d = 1, 2.3, "Hi!";`
Here:
* *a = 1* and is of type **int**,
* *b = 2.3* and is of type **float**,
* *c = "Hi!"* and is of type **string**,
* *d = "Hi!"* and is of type **string**.

### Type casting

You can explicitly cast a value to any type with the keyword `as`, it must be followed by the desired type like this: `float a = 5 as float;`.


* * *

* [Next: Control flow](control.md)
* [Prev: First program](first_program.md)
* [Main Page](index.md)