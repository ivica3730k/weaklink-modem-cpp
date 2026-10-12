add_library(wl_reedsolomon STATIC
  src/galois.cpp
  src/reedsolomon.cpp)

target_link_libraries(wl_reedsolomon PUBLIC wl_core PRIVATE wl_warnings)

weaklink_library(wl_reedsolomon)
