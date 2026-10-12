# Consuming weaklink-modem straight from GitHub. Nothing is installed and
# nothing is vendored: CMake clones the tag at configure time and builds it as
# part of this project.
cmake_minimum_required(VERSION 3.16)
project(weaklink-fetch-example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# Pin a tag rather than a branch. GIT_SHALLOW keeps the clone to one commit.
FetchContent_Declare(weaklink-modem
  GIT_REPOSITORY https://github.com/ivica3730k/weaklink-modem-cpp.git
  GIT_TAG 0.1.0
  GIT_SHALLOW TRUE)

# Live audio pulls in a second clone of PortAudio. This example only touches
# WAV files, so turning it off makes the configure step considerably cheaper.
# Drop these two lines if the consuming program opens a sound device.
set(WEAKLINK_LIVE_AUDIO OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(weaklink-modem)

add_executable(weaklink-fetch-example main.cpp)
target_link_libraries(weaklink-fetch-example PRIVATE weaklink::modem)
