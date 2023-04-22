# VESC RS485 via LispBM

LispBM scripts to operate RS485 UART interface using the lisp [dialect of LispBM](https://github.com/vedderb/bldc/tree/master/lispBM) in the [VESC project](vesc-project.com/)

This depends directly on the 410_LACEP board, available at [jordeam/vedderb_bldc_hardware](https://github.com/jordeam/vedderb_bldc_hardware).

# PC testing
To test on a PC, build the [original LispBM project](https://github.com/svenssonjoel/lispBM). Use the Makefile provided, that should be quicker.
Then comment out the `(run)` call on the end of the file. This is necessary as we are not mocking the `uart-read-until` procedure, so it won't run. 

```shell
$ make repl
```


A tip is to use the `rlwrap` program to test

```shell
$ rlwrap lispBM/repl/repl
> load mock_vesc.lisp
> load duty_rs485.lisp
> (cmd-duty 0.75 0.05)
```

The `mock_vesc.lisp` contains a mock versions of functions from the VESC Extensions
to the LispBM.

# Running on the VESC
Just open the `duty_rs485.lisp` on the "VESC Dev Tools" page, at the "Lisp" tab, then "Upload". (The "Open File" button is at the right-lower corner of the editor)

# TODO:
Main things I wish I could do better:
 - The toggling of the control flow pins is done via a delay. We don't have access to blocking UART calls
 - Add a default ramp rate (alpha)
