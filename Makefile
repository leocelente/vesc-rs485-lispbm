lispBM/repl/Makefile: 
	git clone https://github.com/svenssonjoel/lispBM

repl: lispBM/repl/Makefile
	make -C lispBM/repl all64

doc:
	make -C documentation/
