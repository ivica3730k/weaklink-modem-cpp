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
    # Plain variables rather than cache entries: these choices are this
    # project's, and an enclosing build that fetches CLI11 for its own
    # purposes should keep its own. CMP0077 is what makes a subproject's
    # option() defer to them.
    set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
    set(CLI11_BUILD_TESTS OFF)
    set(CLI11_BUILD_EXAMPLES OFF)
    set(CLI11_BUILD_DOCS OFF)
    set(CLI11_INSTALL OFF)

    FetchContent_Declare(cli11
      GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
      GIT_TAG ${WEAKLINK_CLI11_TAG}
      GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(cli11)

    unset(CMAKE_POLICY_DEFAULT_CMP0077)
    weaklink_mark_system(CLI11)
  endif()

  add_library(wl_cli11 INTERFACE)
  target_link_libraries(wl_cli11 INTERFACE CLI11::CLI11)
endif()

if(WEAKLINK_BUILD_TESTS)
  find_package(Catch2 2 QUIET)
  if(NOT Catch2_FOUND)
    # Catch2 2.13 predates CMP0077, so without granting it the policy its
    # option() calls would overwrite the three settings below -- and building
    # Catch2's own self-tests is not this project's business.
    set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
    set(CATCH_BUILD_TESTING OFF)
    set(CATCH_INSTALL_DOCS OFF)
    set(CATCH_INSTALL_HELPERS OFF)

    # It also still declares cmake_minimum_required(VERSION 3.5), which newer
    # CMake refuses outright -- the same grant PortAudio needs below.
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

    FetchContent_Declare(catch2
      GIT_REPOSITORY https://github.com/catchorg/Catch2.git
      GIT_TAG ${WEAKLINK_CATCH2_TAG}
      GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(catch2)

    unset(CMAKE_POLICY_VERSION_MINIMUM)
    unset(CMAKE_POLICY_DEFAULT_CMP0077)
    weaklink_mark_system(Catch2)
  endif()

  add_library(wl_catch2 INTERFACE)
  target_link_libraries(wl_catch2 INTERFACE Catch2::Catch2)
endif()

if(WEAKLINK_LIVE_AUDIO)
  find_package(Threads REQUIRED)
  set(WEAKLINK_PORTAUDIO_TAG "v19.7.0" CACHE STRING "PortAudio git tag to bundle")

  # PortAudio 19.7 still declares cmake_minimum_required(VERSION 3.0), which
  # CMake 4 refuses outright. Granting it the 3.5 floor is the documented
  # escape hatch and affects only the fetched subproject.
  #
  # CMP0077 is granted for the same reason the floor is: the settings below
  # are plain variables, scoped to this directory, and a project that predates
  # the policy would have its own option() defaults overwrite them. Cache
  # entries would reach further than they should -- an enclosing build that
  # fetches PortAudio for its own purposes keeps its own choices this way.
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
  set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)

  set(PA_BUILD_SHARED OFF)
  set(PA_BUILD_STATIC ON)
  set(PA_BUILD_TESTS OFF)
  set(PA_BUILD_EXAMPLES OFF)
  set(BUILD_SHARED_LIBS OFF)

  # PortAudio is built for us, not for the machine: its headers, pkg-config
  # file, CMake package and documentation have no business in a prefix that
  # asked for weaklink. The option exists upstream for exactly this case.
  set(PA_DISABLE_INSTALL ON)

  # Load ALSA through dlopen rather than linking it. One Linux binary then
  # starts anywhere -- a container without libasound included -- and only needs
  # the library when live audio is actually opened. WAV and stdin/stdout modes
  # never touch it.
  set(PA_ALSA_DYNAMIC ON)

  FetchContent_Declare(portaudio
    GIT_REPOSITORY https://github.com/PortAudio/portaudio.git
    GIT_TAG ${WEAKLINK_PORTAUDIO_TAG}
    GIT_SHALLOW TRUE)
  FetchContent_MakeAvailable(portaudio)

  unset(CMAKE_POLICY_VERSION_MINIMUM)
  unset(CMAKE_POLICY_DEFAULT_CMP0077)

  # A shared PortAudio here would mean a binary that needs it at runtime,
  # which is the opposite of what every release promises. If the settings
  # above failed to take, this is where that shows up rather than in somebody
  # else's ldd output.
  if(NOT TARGET portaudio_static)
    message(FATAL_ERROR
      "PortAudio did not build its static library; weaklink's binaries would "
      "need a libportaudio at runtime. Check PA_BUILD_STATIC and PA_BUILD_SHARED.")
  endif()

  set(WEAKLINK_PORTAUDIO_TARGET portaudio_static)

  # Where the archives can be merged, PortAudio's objects go inside wl_audio
  # (see libs/audio) and nothing of PortAudio's is installed or exported: the
  # dependency is named for the build tree alone. Where they cannot, it is
  # linked and exported as before, which costs the consumer a libportaudio.a
  # in their prefix but keeps them able to link.
  weaklink_can_bundle_archives(WEAKLINK_BUNDLE_PORTAUDIO)

  add_library(wl_portaudio INTERFACE)
  target_link_libraries(wl_portaudio INTERFACE Threads::Threads)
  if(WEAKLINK_BUNDLE_PORTAUDIO)
    target_link_libraries(wl_portaudio INTERFACE "$<BUILD_INTERFACE:${WEAKLINK_PORTAUDIO_TARGET}>")

    # The objects travel inside wl_audio, but the system libraries they call
    # do not: CoreAudio and its neighbours on macOS, dl and rt elsewhere.
    # Those reach a consumer through PortAudio's own link interface, which is
    # build-tree only now, so they are repeated here.
    #
    # Frameworks arrive as absolute paths into whichever SDK built this. A
    # consumer may well have a different one, so they are passed on by name.
    get_target_property(portaudio_link_libraries ${WEAKLINK_PORTAUDIO_TARGET} INTERFACE_LINK_LIBRARIES)
    foreach(entry IN LISTS portaudio_link_libraries)
      if(TARGET "${entry}")
        continue()
      endif()
      if("${entry}" MATCHES "/([A-Za-z0-9_]+)\\.framework/?$")
        target_link_libraries(wl_portaudio INTERFACE "-framework ${CMAKE_MATCH_1}")
      else()
        target_link_libraries(wl_portaudio INTERFACE "${entry}")
      endif()
    endforeach()
  else()
    target_link_libraries(wl_portaudio INTERFACE ${WEAKLINK_PORTAUDIO_TARGET})
    # Otherwise an installed weaklink points at a target that only ever
    # existed in the build tree.
    weaklink_support_library(${WEAKLINK_PORTAUDIO_TARGET})
  endif()
  weaklink_support_library(wl_portaudio)
endif()
