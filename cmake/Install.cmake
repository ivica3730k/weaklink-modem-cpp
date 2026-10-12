# Everything needed for `cmake --install` plus a find_package(weaklink-modem) config
# package. The per-library install(TARGETS) calls live in weaklink_library();
# this file only assembles what they registered into the export set.
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(WEAKLINK_INSTALL_CMAKEDIR "${CMAKE_INSTALL_LIBDIR}/cmake/weaklink-modem")

if(WEAKLINK_BUILD_APPS)
  install(TARGETS weaklink-modem weaklink-modem-benchmark
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
endif()

install(EXPORT weaklink-modem-targets
  FILE weaklink-modem-targets.cmake
  NAMESPACE weaklink::
  DESTINATION "${WEAKLINK_INSTALL_CMAKEDIR}")

configure_package_config_file(
  "${PROJECT_SOURCE_DIR}/cmake/weaklink-modem-config.cmake.in"
  "${PROJECT_BINARY_DIR}/weaklink-modem-config.cmake"
  INSTALL_DESTINATION "${WEAKLINK_INSTALL_CMAKEDIR}")

write_basic_package_version_file(
  "${PROJECT_BINARY_DIR}/weaklink-modem-config-version.cmake"
  VERSION "${PROJECT_VERSION}"
  COMPATIBILITY SameMajorVersion)

install(FILES
  "${PROJECT_BINARY_DIR}/weaklink-modem-config.cmake"
  "${PROJECT_BINARY_DIR}/weaklink-modem-config-version.cmake"
  DESTINATION "${WEAKLINK_INSTALL_CMAKEDIR}")
