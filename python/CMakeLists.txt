# The extension module. Built only when WEAKLINK_PYTHON is on, which
# scikit-build-core sets; a plain CMake build of this repo never looks for
# Python or pybind11.
find_package(Python 3.9 REQUIRED COMPONENTS Interpreter Development.Module)
find_package(pybind11 CONFIG REQUIRED)

pybind11_add_module(weaklink_core src/binding.cpp)
set_target_properties(weaklink_core PROPERTIES OUTPUT_NAME _core)

# wl_api is the whole public surface; the facade carries the rest of the
# libraries with it.
target_link_libraries(weaklink_core PRIVATE weaklink::modem wl_warnings)

# The static libraries are already position independent (see the root
# CMakeLists), which is what makes linking them into this shared object work.
# Tagged with a component so the wheel can take this and nothing else.
# PortAudio registers its own install rules for headers, a static library and
# its documentation, and those would otherwise land at the top of
# site-packages, where they do not belong and could collide with another
# package's files.
install(TARGETS weaklink_core LIBRARY DESTINATION weaklink/modem COMPONENT python)
