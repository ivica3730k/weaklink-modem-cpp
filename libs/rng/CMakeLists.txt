add_library(wl_rng STATIC src/rng.cpp)

target_link_libraries(wl_rng PRIVATE wl_warnings)

weaklink_library(wl_rng)
