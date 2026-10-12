# Every weaklink library has the same shape: public headers under
# include/weaklink, a weaklink:: alias, and membership in the single export set.
# Declaring that shape once keeps the eleven library CMakeLists.txt files down
# to their target and its dependencies.
include(GNUInstallDirs)

# Registers <target> as a public weaklink library. Strips the wl_ prefix for
# the exported name, so wl_codec is linked as weaklink::codec from both the
# build tree (ALIAS) and an installed tree (EXPORT_NAME).
function(weaklink_library target)
  string(REGEX REPLACE "^wl_" "" export_name "${target}")
  set_target_properties(${target} PROPERTIES EXPORT_NAME "${export_name}")
  add_library(weaklink::${export_name} ALIAS ${target})

  # The build tree reads headers where they sit; an installed tree reads them
  # from the prefix. Without the two interfaces the exported target would hand
  # consumers a path that only exists on the machine that built it.
  target_include_directories(${target} PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")

  if(WEAKLINK_INSTALL)
    install(TARGETS ${target} EXPORT weaklink-modem-targets
      ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
      LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
      RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/include/"
      DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
  endif()
endfunction()

# Support targets (warning flags, runtime flags, header-only third party) carry
# no headers of their own but still appear in the installed link interface,
# because CMake records even PRIVATE dependencies of a static library. They have
# to travel with the export set or the generated targets file won't configure.
function(weaklink_support_library target)
  if(WEAKLINK_INSTALL)
    install(TARGETS ${target} EXPORT weaklink-modem-targets)
  endif()
endfunction()
