cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# ---- WinSparkle wiring ----
# Cache variables WINSPARKLE_INCLUDE_DIR / WINSPARKLE_LIB / WINSPARKLE_DLL are
# set in the parent windows/CMakeLists.txt via FetchContent.
target_include_directories(${BINARY_NAME} PRIVATE "${WINSPARKLE_INCLUDE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE "${WINSPARKLE_LIB}")

# Copy WinSparkle.dll next to the built .exe so the app finds it at runtime.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${WINSPARKLE_DLL}"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/WinSparkle.dll"
  COMMENT "Copying WinSparkle.dll alongside ${BINARY_NAME}.exe"
)

# Also install WinSparkle.dll into the install location (matches how plugins
# are installed via the generated_plugins.cmake mechanism).
install(FILES "${WINSPARKLE_DLL}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
