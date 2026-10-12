add_library(wl_fec STATIC src/fec.cpp)

target_link_libraries(wl_fec PUBLIC wl_core PRIVATE wl_warnings)

weaklink_library(wl_fec)
