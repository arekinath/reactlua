Work in progress!

## What is it?

React.Lua will be (and already is in many respects) a simple, no-nonsense layer on top of straight UNIX system calls, for writing evented network servers and clients. There are no compulsory external libraries (other than perhaps an async DNS library of your choice if you want to do name lookups).

Everything is done by LuaJIT's FFI interface in a way compatible with most modern UNIX-like operating systems -- to ensure compatibility we provide a very basic "shim" library that exports the values of various compile-time constants back to Lua.

## Examples

See echo.lua and proxy.lua for some example code.