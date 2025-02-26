package main

import "C"
import (
    "fmt"
    "unsafe"
)

//export _MIST_PLUGIN_0_0_MAIN
func _MIST_PLUGIN_0_0_MAIN(
    argCount         C.size_t,
    argPointers    **C.char,
    argPointerSizes *C.size_t,
) uint8 {
    fmt.Println("Hello from Go!")

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

    fmt.Print("My arguments are: ")

    for _, arg := range arguments {
        fmt.Printf("%s, ", arg)
    }

    fmt.Println("")

    return 0
}

func main() {}
