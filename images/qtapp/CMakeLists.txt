cmake_minimum_required(VERSION 3.16)
project(k3rdp_qtapp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt5 REQUIRED COMPONENTS Widgets)

add_executable(qtapp src/main.cpp)
target_link_libraries(qtapp PRIVATE Qt5::Widgets)

install(TARGETS qtapp RUNTIME DESTINATION bin)
