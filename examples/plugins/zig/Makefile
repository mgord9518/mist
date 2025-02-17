name=plugin_zig

$(name).so: build.zig main.zig
	zig build -p . --prefix-lib-dir .
	# TODO: how to do this in build.zig or CLI option? I know it's possible
	mv lib$(name).so $(name).so 
