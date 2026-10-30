.PHONY: all clean

all: output.jsx
	mkdir -p ../11_jsx_to_xml
	cp output.jsx ../11_jsx_to_xml/output.jsx

input.jsx: ../09_babel_ast/output.jsx
	cp ../09_babel_ast/output.jsx input.jsx

output.jsx: input.jsx compile.mjs
	node compile.mjs input.jsx output.jsx

clean:
	rm -f input.jsx output.jsx Component.svelte Component.mjs
