# Windows/Android infer_core is bundled via hook/build.dart (CodeAsset), not prebuilt here.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "local_infer_core")
project(${PROJECT_NAME} LANGUAGES C)

set(local_infer_core_bundled_libraries "" PARENT_SCOPE)
