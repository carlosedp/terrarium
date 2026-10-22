# terrarium as a plugin (doc/PLUGIN.md): the core (Lua + engine, no JUCE), a command-line
# renderer that tests it, and the JUCE plugin around it.
#
#   cmake -S plugin -B build/plugin -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/plugin --config Release
#
# Options:
#   TERRARIUM_PLUGIN=OFF   only the core and terrarium-render (no JUCE: builds anywhere)
#   MI_UGENS_DIR=<dir>     a mi-UGens-native/ folder to use instead of downloading the release's
cmake_minimum_required(VERSION 3.22)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)  # downloads get the extraction time (CMake 3.24+)
endif()
if(APPLE AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "macOS architectures")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13 CACHE STRING "")
project(terrarium VERSION 0.1.0 LANGUAGES C CXX)

option(TERRARIUM_PLUGIN "build the JUCE plugin (VST3, AU, standalone)" ON)
set(MI_UGENS_DIR "" CACHE PATH "mi-UGens-native/ folder (default: download the release's)")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

include(FetchContent)
set(SCRIPT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")

# ---------- Lua 5.3, what norns runs ----------
FetchContent_Declare(lua
  URL https://www.lua.org/ftp/lua-5.3.6.tar.gz
  URL_HASH SHA256=fc5fd69bb8736323f026672b1b7235da613d7177e72558893a0bdcd320466d60)
FetchContent_MakeAvailable(lua)
file(GLOB LUA_SOURCES "${lua_SOURCE_DIR}/src/*.c")
list(FILTER LUA_SOURCES EXCLUDE REGEX "/(lua|luac)\\.c$")
add_library(lua53 STATIC ${LUA_SOURCES})
target_include_directories(lua53 PUBLIC "${lua_SOURCE_DIR}/src")
if(UNIX AND NOT APPLE)
  target_compile_definitions(lua53 PRIVATE LUA_USE_LINUX)
  target_link_libraries(lua53 PUBLIC m)
elseif(APPLE)
  target_compile_definitions(lua53 PRIVATE LUA_USE_MACOSX)
endif()

# ---------- the native mi-UGens, from norns-mi-UGens' release ----------
set(MI_RELEASE v1.2.0)
if(NOT MI_UGENS_DIR)
  if(WIN32)
    set(MI_PLAT windows-x86_64)
    set(MI_HASH 235535dbbfc5feed69cf29edaa00322510449fa59ff52a57249906ab863eb054)
  elseif(APPLE)
    set(MI_PLAT macos-universal)
    set(MI_HASH 55729e5af7f7f9b56b110eea9b5f15de473ae47c978902df24de4b4db1b48ede)
  else()
    set(MI_PLAT linux-x86_64)
    set(MI_HASH 2b466a2267b39b483a6bbd301127deb1a2dde28c167e5a0a34a31ca115d2dff5)
  endif()
  FetchContent_Declare(mi_ugens
    URL https://github.com/carlosedp/norns-mi-UGens/releases/download/${MI_RELEASE}/mi-UGens-native-${MI_PLAT}-${MI_RELEASE}.tar.gz
    URL_HASH SHA256=${MI_HASH})
  FetchContent_MakeAvailable(mi_ugens)
  set(MI_UGENS_DIR "${mi_ugens_SOURCE_DIR}")
endif()
message(STATUS "mi-UGens: ${MI_UGENS_DIR}")

# ---------- the core: Lua, the engine, the time between them ----------
add_library(terrarium_core STATIC
  core/LuaHost.cpp core/Engine.cpp core/Terrarium.cpp)
target_include_directories(terrarium_core PUBLIC core)
target_include_directories(terrarium_core SYSTEM PUBLIC "${MI_UGENS_DIR}")  # mi_ugens.hpp: not our warnings
target_link_libraries(terrarium_core PUBLIC lua53 ${CMAKE_DL_LIBS})
find_package(Threads REQUIRED)
target_link_libraries(terrarium_core PUBLIC Threads::Threads)

add_executable(terrarium-render render/main.cpp)
target_link_libraries(terrarium-render PRIVATE terrarium_core)
target_compile_definitions(terrarium-render PRIVATE TERRARIUM_MI_DIR="${MI_UGENS_DIR}/lib")

# ---------- the plugin ----------
if(TERRARIUM_PLUGIN)
  add_subdirectory(juce)
endif()
