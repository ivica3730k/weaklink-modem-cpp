# Deliberately a standalone project, not part of the parent build: it has to
# work the way a real consumer's build does, through find_package.
cmake_minimum_required(VERSION 3.16)
project(weaklink-embed-example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(weaklink-modem REQUIRED)

add_executable(weaklink-embed-example main.cpp)
target_link_libraries(weaklink-embed-example PRIVATE weaklink::modem)
