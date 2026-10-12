# Embedding weaklink-modem

A standalone project that links the modem as a library and round-trips a string
through a WAV file. No audio device is opened, so it runs anywhere.

## Against an installed copy

```bash
cmake -S . -B build/install -DCMAKE_BUILD_TYPE=Release
cmake --build build/install
cmake --install build/install --prefix /usr/local

cmake -S examples/embed -B build/example -DCMAKE_PREFIX_PATH=/usr/local
cmake --build build/example
./build/example/weaklink-embed-example "hello"
```

## Against a source checkout

Replace the `find_package` line with an `add_subdirectory`; the target name is
the same either way.

```cmake
add_subdirectory(third_party/weaklink-modem)
target_link_libraries(my-app PRIVATE weaklink::modem)
```

Embedding turns the CLI, the benchmark, the test suite and the install rules off
by default. `-DWEAKLINK_BUILD_APPS=ON` brings the binaries back.

## Straight from GitHub

See `examples/fetch`, which clones a pinned tag at configure time instead of
needing either an install or a checkout.
