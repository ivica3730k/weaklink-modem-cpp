add_library(wl_core STATIC
  src/bits.cpp
  src/constants.cpp
  src/log.cpp)

target_link_libraries(wl_core PRIVATE wl_warnings)

weaklink_library(wl_core)
