#[allow(non_snake_case)]

// TODO: iterate arguments
#[no_mangle]
fn _MIST_PLUGIN_1_0_MAIN(
    arg_count: usize,
    arg_pointers: *const *const u8,
    arg_pointer_sizes: *const usize
) -> usize {
    _ = arg_count;
    _ = arg_pointers;
    _ = arg_pointer_sizes;

    println!("Hello from Rust!");

    return 0;
}
