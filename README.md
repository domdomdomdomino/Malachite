# Malachite

This program's function is to process data from the output file of particle
collision simulations. 

## Compilation

The first step is to install *Nim* using the `sudo apt-get install nim` command on Ubuntu.

Then you must install a dependency called *Gintro*, which adds GTK bindings to
*Nim*. To install this dependency, you mus use the `nimble install gintro`
command. **MAKE SURE YOU HAVE GTK INSTALLED**.

After installing the dependencies, you must go to the terminal and use the `cd`
command to get to the `Malachite` directory, then you must input the following
command to compile the program:

``` sh
nim c -d:danger --threads:on -o:bin/Malachite src/Malachite.nim
```

## Running Malachite

To run *Malachite*, you must use the `./bin/Malachite` command from the
terminal.

The instructions on how to use the program itself can be found by hovering the
mouse over the `<?>` label.
