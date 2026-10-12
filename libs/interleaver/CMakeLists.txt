add_library(wl_interleaver STATIC src/interleaver.cpp)

# wl_rng is PUBLIC on purpose: the permutation it generates is part of the
# wire format, so anything reasoning about that format needs the generator.
target_link_libraries(wl_interleaver PUBLIC wl_core wl_rng PRIVATE wl_warnings)

weaklink_library(wl_interleaver)
