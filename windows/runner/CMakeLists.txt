cmake_minimum_required(VERSION 3.16)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "mpv/display_mode_manager.cpp"
  "mpv/mpv_player.cpp"
  "mpv/mpv_plugin.cpp"
  "youtube/youtube_web_plugin.cpp"
  "browser/browser_web_plugin.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_precompile_headers(${BINARY_NAME} PRIVATE "pch.h")

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

add_library(simdutf STATIC "${simdutf_SOURCE_DIR}/simdutf.cpp")
target_include_directories(simdutf PUBLIC "${simdutf_SOURCE_DIR}")
target_compile_features(simdutf PUBLIC cxx_std_17)
target_compile_options(simdutf PRIVATE /W0)

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "comctl32.lib" "dxgi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "${MPV_LIB_DIR}/libmpv.dll.a")
target_link_libraries(${BINARY_NAME} PRIVATE simdutf)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${MPV_INCLUDE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/../shared/cpp")

# WebView2 SDK for the native YouTube player and the in-app browser
# (youtube/, browser/). The webview_windows plugin keeps its own, older copy
# of the package; the runner uses a newer one for the browser's privacy and
# download APIs. Newer SDK headers still contain every older interface. The
# package is fetched once from NuGet into the build folder.
set(PLEZY_WEBVIEW2_VERSION "1.0.2903.40")
set(PLEZY_WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/packages/plezy-webview2-${PLEZY_WEBVIEW2_VERSION}")
if(NOT EXISTS "${PLEZY_WEBVIEW2_DIR}/build/native/include/WebView2.h")
  set(_plezy_wv2_pkg "${CMAKE_BINARY_DIR}/packages/plezy-webview2-${PLEZY_WEBVIEW2_VERSION}.zip")
  file(DOWNLOAD
    "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${PLEZY_WEBVIEW2_VERSION}"
    "${_plezy_wv2_pkg}"
    STATUS _plezy_wv2_status TLS_VERIFY ON)
  list(GET _plezy_wv2_status 0 _plezy_wv2_code)
  if(NOT _plezy_wv2_code EQUAL 0)
    message(FATAL_ERROR "Could not download the WebView2 SDK ${PLEZY_WEBVIEW2_VERSION}: ${_plezy_wv2_status}")
  endif()
  file(MAKE_DIRECTORY "${PLEZY_WEBVIEW2_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${_plezy_wv2_pkg}"
    WORKING_DIRECTORY "${PLEZY_WEBVIEW2_DIR}"
    RESULT_VARIABLE _plezy_wv2_extract)
  if(NOT _plezy_wv2_extract EQUAL 0)
    message(FATAL_ERROR "Could not unpack the WebView2 SDK ${PLEZY_WEBVIEW2_VERSION}")
  endif()
endif()
target_link_libraries(${BINARY_NAME} PRIVATE
  "${PLEZY_WEBVIEW2_DIR}/build/native/Microsoft.Web.WebView2.targets")
target_include_directories(${BINARY_NAME} PRIVATE
  "${PLEZY_WEBVIEW2_DIR}/build/native/include")
# Static loader: no WebView2Loader.dll next to the exe that could clash with
# the one of webview_windows' older package.
set_target_properties(${BINARY_NAME} PROPERTIES VS_GLOBAL_WebView2LoaderPreference "Static")
add_dependencies(${BINARY_NAME} webview_windows_DEPENDENCIES_DOWNLOAD)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

option(PLEZY_BUILD_MPV_PROPERTY_CONTRACT_TESTS
  "Build the focused Windows mpv property-result contract tests" OFF)
if(PLEZY_BUILD_MPV_PROPERTY_CONTRACT_TESTS)
  enable_testing()

  add_executable(mpv_property_result_contract_test
    "../../shared/mpv/mpv_player_common_test.cpp"
  )
  apply_standard_settings(mpv_property_result_contract_test)
  target_link_libraries(mpv_property_result_contract_test PRIVATE "${MPV_LIB_DIR}/libmpv.dll.a")
  target_include_directories(mpv_property_result_contract_test PRIVATE "${MPV_INCLUDE_DIR}")

  add_executable(mpv_player_property_contract_test
    "mpv/mpv_player.cpp"
    "mpv/mpv_player_property_contract_test.cpp"
  )
  apply_standard_settings(mpv_player_property_contract_test)
  target_compile_definitions(mpv_player_property_contract_test PRIVATE "NOMINMAX")
  target_link_libraries(
    mpv_player_property_contract_test
    PRIVATE flutter_wrapper_plugin "${MPV_LIB_DIR}/libmpv.dll.a" simdutf "comctl32.lib" "user32.lib" "dxgi.lib"
  )
  target_include_directories(
    mpv_player_property_contract_test
    PRIVATE
      "${CMAKE_SOURCE_DIR}"
      "${CMAKE_CURRENT_SOURCE_DIR}"
      "${MPV_INCLUDE_DIR}"
      "${CMAKE_SOURCE_DIR}/../shared/cpp"
  )

  foreach(test_target IN ITEMS mpv_property_result_contract_test mpv_player_property_contract_test)
    add_custom_command(
      TARGET ${test_target}
      POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${MPV_LIB_DIR}/libmpv-2.dll"
        "$<TARGET_FILE_DIR:${test_target}>"
    )
  endforeach()

  add_test(NAME mpv_property_result_contract_test COMMAND mpv_property_result_contract_test)
  add_test(NAME mpv_player_property_contract_test COMMAND mpv_player_property_contract_test)
endif()

option(PLEZY_BUILD_DISPLAY_RECOVERY_TESTS
  "Build the focused Windows display recovery transaction tests" OFF)
if(PLEZY_BUILD_DISPLAY_RECOVERY_TESTS)
  enable_testing()

  add_executable(display_mode_manager_test
    "mpv/display_mode_manager.cpp"
    "mpv/display_mode_manager_test.cpp"
  )
  apply_standard_settings(display_mode_manager_test)
  target_compile_definitions(
    display_mode_manager_test PRIVATE "NOMINMAX" "PLEZY_DISPLAY_MODE_MANAGER_TESTING"
  )
  target_link_libraries(display_mode_manager_test PRIVATE "advapi32.lib" "user32.lib")

  add_test(NAME display_mode_manager_test COMMAND display_mode_manager_test)
endif()
