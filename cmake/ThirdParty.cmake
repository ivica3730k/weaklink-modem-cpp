# Third-party dependencies, pinned and built as part of the project.
#
# A system package is preferred where one is installed, so a distribution can
# build this against the Catch2 and CLI11 it already ships; otherwise CMake
# fetches the pinned version. An offline build can point at a local checkout
# with -DFETCHCONTENT_SOURCE_DIR_CLI11=/path, and the same for catch2 and
# pocketfft.
include(FetchContent)

set(WEAKLINK_POCKETFFT_TAG "c90e55b3d529f8efa40ed01a20de22405f45fc65"
    CACHE STRING "pocketfft commit the DSP is built against")
set(WEAKLINK_CLI11_TAG "v2.4.2" CACHE STRING "CLI11 version the command line is built against")
set(WEAKLINK_CATCH2_TAG "v2.13.10" CACHE STRING "Catch2 version the test suite is built against")

# Marks a dependency's headers as system headers. Targets that come from
# add_subdirectory are not imported, so their include directories would
# otherwise be compiled with this project's warning flags, and a warning in
# somebody else's header is not something this build can fix.
function(weaklink_mark_system target)
  if(NOT TARGET ${target})
    return()
  endif()
  get_target_property(include_dirs ${target} INTERFACE_INCLUDE_DIRECTORIES)
  if(include_dirs)
    set_property(TARGET ${target} APPEND PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${include_dirs}")
  endif()
endfunction()

# pocketfft ships a header and a meson build, no CMake package, so this is a
# populate rather than a build: FetchContent_MakeAvailable adds nothing for a
# dependency with no CMakeLists.txt of its own.
FetchContent_Declare(pocketfft
  GIT_REPOSITORY https://github.com/mreineck/pocketfft.git
  GIT_TAG ${WEAKLINK_POCKETFFT_TAG})
FetchContent_MakeAvailable(pocketfft)

add_library(wl_pocketfft INTERFACE)
target_include_directories(wl_pocketfft SYSTEM INTERFACE
  "$<BUILD_INTERFACE:${pocketfft_SOURCE_DIR}>")
# Only wl_dsp compiles against pocketfft, but CMake records even a PRIVATE
# dependency of a static library in the exported link interface, so the target
# has to exist for consumers even though its headers never reach them.
weaklink_support_library(wl_pocketfft)

# The CLI and the benchmark are the only things that parse a command line.
if(WEAKLINK_BUILD_APPS)
  find_package(CLI11 2.4 QUIET)
  if(NOT CLI11_FOUND)
    set(CLI11_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(CLI11_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(CLI11_BUILD_DOCS OFF CACHE BOOL "" FORCE)
    set(CLI11_INSTALL OFF CACHE BOOL "" FORCE)

    FetchContent_Declare(cli11
      GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
      GIT_TAG ${WEAKLINK_CLI11_TAG}
      GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(cli11)
    weaklink_mark_system(CLI11)
  endif()

  add_library(wl_cli11 INTERFACE)
  target_link_libraries(wl_cli11 INTERFACE CLI11::CLI11)
endif()

if(WEAKLINK_BUILD_TESTS)
  find_package(Catch2 2 QUIET)
  if(NOT Catch2_FOUND)
    set(CATCH_BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(CATCH_INSTALL_DOCS OFF CACHE BOOL "" FORCE)
    set(CATCH_INSTALL_HELPERS OFF CACHE BOOL "" FORCE)

    # Catch2 2.13 still declares cmake_minimum_required(VERSION 3.5), which
    # newer CMake refuses outright -- the same grant PortAudio needs below.
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

    FetchContent_Declare(catch2
      GIT_REPOSITORY https://github.com/catchorg/Catch2.git
      GIT_TAG ${WEAKLINK_CATCH2_TAG}
      GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(catch2)

    unset(CMAKE_POLICY_VERSION_MINIMUM)
    weaklink_mark_system(Catch2)
  endif()

  add_library(wl_catch2 INTERFACE)
  target_link_libraries(wl_catch2 INTERFACE Catch2::Catch2)
endif()

if(WEAKLINK_LIVE_AUDIO)
  find_package(Threads REQUIRED)
  set(WEAKLINK_PORTAUDIO_TAG "v19.7.0" CACHE STRING "PortAudio git tag to bundle")

  set(PA_BUILD_SHARED OFF CACHE BOOL "" FORCE)
  set(PA_BUILD_STATIC ON  CACHE BOOL "" FORCE)
  set(PA_BUILD_TESTS  OFF CACHE BOOL "" FORCE)
  set(PA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(BUILD_SHARED_LIBS OFF)

  # Load ALSA through dlopen rather than linking it. One Linux binary then
  # starts anywhere -- a container without libasound included -- and only needs
  # the library when live audio is actually opened. WAV and stdin/stdout modes
  # never touch it.
  set(PA_ALSA_DYNAMIC ON CACHE BOOL "" FORCE)

  # PortAudio 19.7 still declares cmake_minimum_required(VERSION 3.0), which
  # CMake 4 refuses outright. Granting it the 3.5 floor is the documented
  # escape hatch and affects only the fetched subproject.
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

  FetchContent_Declare(portaudio
    GIT_REPOSITORY https://github.com/PortAudio/portaudio.git
    GIT_TAG ${WEAKLINK_PORTAUDIO_TAG}
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(portaudio)

  unset(CMAKE_POLICY_VERSION_MINIMUM)

  add_library(wl_portaudio INTERFACE)
  if(TARGET portaudio_static)
    set(WEAKLINK_PORTAUDIO_TARGET portaudio_static)
  else()
    set(WEAKLINK_PORTAUDIO_TARGET portaudio)
  endif()
  target_link_libraries(wl_portaudio INTERFACE ${WEAKLINK_PORTAUDIO_TARGET} Threads::Threads)

  # The fetched PortAudio has to join our export set as well; otherwise an
  # installed weaklink points at a target that only existed in the build tree.
  weaklink_support_library(wl_portaudio)
  weaklink_support_library(${WEAKLINK_PORTAUDIO_TARGET})
endif()
