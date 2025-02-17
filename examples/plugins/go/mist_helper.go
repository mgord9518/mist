package main

import "C"
import "unsafe"

type Error uint8

const (
    Success      Error = 0
    UnknownError Error = 1
    UsageError   Error = 2

    // Filesystem
    FileNotFound Error = 16
    AccessDenied Error = 17
    CwdNotFound  Error = 18
    NameTooLong  Error = 19
    NotDir       Error = 20
    NotFile      Error = 21
    SymLinkLoop  Error = 22

    // IO
    ReadFailure  Error = 32
    WriteFailure Error = 33
    InputOutput  Error = 34
    BrokenPipe   Error = 35

    // Variables
    InvalidVariable    Error = 48
    InvalidEnvVariable Error = 49

    // System
    OutOfMemory     Error = 64
    NoSpaceLeft     Error = 65
    NotEqual        Error = 66
    SystemResources Error = 67

    // Encoding/ compression
    CorruptInput Error = 80

    // Misc
    False           Error = 96
    InvalidArgument Error = 97

    // Exec
    CommandCannotExecute Error = 126
    CommandNotFound      Error = 127
);

//export _MIST_PLUGIN_1_0_MAIN
func _MIST_PLUGIN_1_0_MAIN(argCount C.size_t, argPointers **C.char, argPointerSizes *C.size_t) Error {
    arguments := makeGoArguments(argCount, argPointers, argPointerSizes)

    return mistMain(arguments)
}

// Transform C-style arguments into a simple string slice
func makeGoArguments(argCount C.size_t, argPointers **C.char, argPointerSizes *C.size_t) []string {
    arguments := make([]string, uint(argCount))

    for i := 0; i < int(argCount); i++ {
        ptrIdx := uintptr(i * C.sizeof_size_t)

        strStart := unsafe.Add(unsafe.Pointer(argPointers), ptrIdx)
        strLen := unsafe.Add(unsafe.Pointer(argPointerSizes), ptrIdx)

        arguments[i] = C.GoStringN(
            *(**C.char)(strStart),
            *(*C.int)(strLen),
        )
    }

    return arguments
}

func main() {}
