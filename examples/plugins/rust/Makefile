name=plugin_rust

$(name).so: main.rs
	rustc main.rs --crate-type=dylib -o $(name).so
