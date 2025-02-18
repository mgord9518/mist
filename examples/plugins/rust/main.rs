#[allow(non_snake_case)]

use std::{slice, str};
use std::io::{self, Write};

// Please have mercy, this is the first Rust code I've ever written
#[no_mangle]
pub extern "C" fn _MIST_PLUGIN_1_0_MAIN(
    arg_count: usize,
    arg_pointers: *const *const u8,
    arg_pointer_sizes: *const usize
) -> u8 {
    println!("Hello from Rust!");

    let mut arg_vec: Vec<&str> = Vec::with_capacity(arg_count);

    let mut i = 0;
    while i < arg_count {
        let s = unsafe {
            str::from_utf8_unchecked(slice::from_raw_parts(
                *arg_pointers.wrapping_add(i),
                *arg_pointer_sizes.wrapping_add(i),
            ))
        };

        arg_vec.push(s);

        i += 1;
    }

    print!("My arguments are: ");

    let arg_vec_iter = arg_vec.iter();
    for string in arg_vec_iter {
        print!("{}, ", string);
    }

    io::stdout().flush().unwrap();

    println!("");

    return 0;
}
