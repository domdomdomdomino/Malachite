# Malachite

This program's function is to process data from the output file of particle
collision simulations. 

## Compilation

The first step is to install *Nim*.

You need to install `docopt` with `nimble install docopt`.

After installing *Nim*, you must go to the terminal and use the `cd`
command to get to the `Malachite` directory, then you must input the following
command to compile the program:

``` sh
nim c -d:danger --threads:on src/Malachite.nim
```

## Running Malachite

To run *Malachite*, you must cd into the `src` directroy and use the `./Malachite` command from the
terminal.
