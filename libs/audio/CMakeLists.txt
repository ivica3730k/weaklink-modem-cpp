add_library(wl_audio STATIC
  src/devices.cpp
  src/live_input.cpp
  src/playback.cpp
  src/process.cpp
  src/wav.cpp)

target_link_libraries(wl_audio PUBLIC wl_core PRIVATE wl_warnings)

if(WEAKLINK_LIVE_AUDIO)
  target_compile_definitions(wl_audio PUBLIC WEAKLINK_HAVE_PORTAUDIO=1)
  target_link_libraries(wl_audio PRIVATE wl_portaudio)
else()
  target_compile_definitions(wl_audio PUBLIC WEAKLINK_HAVE_PORTAUDIO=0)
endif()

weaklink_library(wl_audio)

# PortAudio's objects are merged into this archive, so an installed weaklink
# carries no PortAudio of its own. See cmake/BundleStatic.cmake.
if(WEAKLINK_LIVE_AUDIO AND WEAKLINK_BUNDLE_PORTAUDIO)
  weaklink_bundle_archive(wl_audio ${WEAKLINK_PORTAUDIO_TARGET})
endif()
