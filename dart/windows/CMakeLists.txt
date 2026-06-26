# Prebuilt infer_core.dll from build hook or cargo build -p infer-core-ffi --release.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "local_infer_core")
project(${PROJECT_NAME} LANGUAGES C)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|ARM64")
  set(LOCAL_INFER_CORE_ARCH "arm64")
else()
  set(LOCAL_INFER_CORE_ARCH "x64")
endif()

set(_LIB_PATH
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/windows/${LOCAL_INFER_CORE_ARCH}/lib/infer_core.dll"
)

if(EXISTS "${_LIB_PATH}")
  set(local_infer_core_bundled_libraries "${_LIB_PATH}" PARENT_SCOPE)
else()
  set(local_infer_core_bundled_libraries "" PARENT_SCOPE)
endif()
