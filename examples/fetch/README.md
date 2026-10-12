# Fetching weaklink-modem from GitHub

The same program as `examples/embed`, but with no prior install and nothing
vendored. `FetchContent` clones the pinned tag during `cmake -S`, builds it
alongside this project, and `weaklink::modem` becomes available.

```bash
cmake -S examples/fetch -B build/fetch -DCMAKE_BUILD_TYPE=Release
cmake --build build/fetch
./build/fetch/weaklink-fetch-example "hello"
```

The first configure clones the repository, so it is slower than the ones after
it; the clone is cached under the build directory.

Two things worth copying into a real project:

- **Pin a tag, not a branch.** `GIT_TAG 0.1.0` with `GIT_SHALLOW TRUE` fetches
  one commit and keeps the build reproducible. A branch name re-resolves and
  makes builds depend on when they ran.
- **Turn off what you do not use.** `WEAKLINK_LIVE_AUDIO OFF` skips a second
  clone of PortAudio, which is most of the configure time. Leave it on only if
  the program opens a sound device.

Embedded this way the CLI, the benchmark and the test suite stay off, so the
consuming build gets the libraries and nothing else.
