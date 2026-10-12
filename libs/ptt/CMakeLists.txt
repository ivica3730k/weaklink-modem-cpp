add_library(wl_ptt STATIC src/ptt.cpp)

target_link_libraries(wl_ptt PUBLIC wl_core PRIVATE wl_warnings)

if(WIN32)
  target_link_libraries(wl_ptt PRIVATE ws2_32)
endif()

weaklink_library(wl_ptt)
