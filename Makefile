default:
	ml-build sources.cm Main.main

test:	default
	sml @SMLload=sources.x86-darwin

clean:
	rm -f *.x86-darwin
	rm -rf .cm/ src/.cm/ tests/.cm/
