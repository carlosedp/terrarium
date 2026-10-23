# The JUCE plugin: VST3, AU (macOS) and a standalone app, around terrarium_core.
#
# Each format's bundle gets a Resources/ folder (next to the binary, for the standalone
# on Linux and Windows): the script's Lua (terrarium.lua and lib/), norns-web's norns.lua,
# the native mi-UGens, and web/: norns-web's page, the plugin's face. The plugin finds them
# from its own binary.
#
# JUCE 8.0.6: its WebView bridge (native functions, events) is new; pinned, as AlloyFlux's
# plugin pins it.
FetchContent_Declare(juce
  URL https://github.com/juce-framework/JUCE/archive/refs/tags/8.0.6.tar.gz
  URL_HASH SHA256=95752f8e8b37d802b4c10182bc757de7d88f0c8899e879afa8798589be306a11)
FetchContent_MakeAvailable(juce)

# WebView2 (Windows): JUCE neither ships nor fetches its SDK, and its FindWebView2 looks
# under a folder named *Microsoft.Web.WebView2*, so the NuGet package (a zip) goes there.
# Under _deps/, so CI's cache of the downloads keeps it with FetchContent's own stamps.
# Linked statically: nothing to ship or find at run time. (As AlloyFlux's plugin does.)
if(WIN32)
  set(WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/_deps/webview2-pkg")
  FetchContent_Declare(webview2
    URL https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.1901.177
    URL_HASH SHA256=464360d5eedcae0e95b0a3fe13c74b496bc9b542980ff8ecebd9ff7ea37ca39e
    SOURCE_DIR "${WEBVIEW2_DIR}/Microsoft.Web.WebView2")
  FetchContent_MakeAvailable(webview2)
  set(JUCE_WEBVIEW2_PACKAGE_LOCATION "${WEBVIEW2_DIR}")
endif()

set(FORMATS VST3 Standalone)
if(APPLE)
  list(APPEND FORMATS AU)
endif()

juce_add_plugin(terrarium_plugin
  PRODUCT_NAME "terrarium"
  COMPANY_NAME "Voltage Foundry Modular"
  BUNDLE_ID com.vfmod.terrarium
  ICON_BIG "${SCRIPT_DIR}/doc/img/icon-touch.svg"  # the jar, on its night (the app's and the window's icon)
  ICON_SMALL "${SCRIPT_DIR}/doc/img/icon-touch.svg"
  PLUGIN_MANUFACTURER_CODE Vfmd
  PLUGIN_CODE Trrm
  IS_SYNTH TRUE
  NEEDS_MIDI_INPUT TRUE  # Live loads a VST3 instrument only with an event input (terrarium ignores it)
  NEEDS_MIDI_OUTPUT TRUE  # visitors' notes to the DAW
  EDITOR_WANTS_KEYBOARD_FOCUS TRUE
  NEEDS_WEB_BROWSER TRUE
  NEEDS_WEBVIEW2 TRUE
  VST3_CATEGORIES Instrument Generator
  AU_MAIN_TYPE kAudioUnitType_MusicDevice
  FORMATS ${FORMATS})

target_sources(terrarium_plugin PRIVATE PluginProcessor.cpp PluginEditor.cpp)
# JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING pairs with NEEDS_WEBVIEW2 (not JUCE_USE_WIN_WEBVIEW2,
# the DLL backend, which wants a loader DLL at run time)
target_compile_definitions(terrarium_plugin PUBLIC
  JUCE_WEB_BROWSER=1 JUCE_USE_WIN_WEBVIEW2_WITH_STATIC_LINKING=1
  JUCE_USE_CURL=0 JUCE_VST3_CAN_REPLACE_VST2=0 JUCE_DISPLAY_SPLASH_SCREEN=0
  # the MIDI input is there for Live (see NEEDS_MIDI_INPUT); without this, JUCE's VST3 adds 2048
  # "MIDI CC" parameters to the host's list
  JUCE_VST3_EMULATE_MIDI_CC_WITH_PARAMETERS=0)
if(MSVC)
  target_compile_options(terrarium_plugin PRIVATE /utf-8)  # the sources are UTF-8, not the system codepage
endif()
target_link_libraries(terrarium_plugin
  PRIVATE terrarium_core juce::juce_audio_utils juce::juce_audio_devices juce::juce_gui_extra
  PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_lto_flags juce::juce_recommended_warning_flags)

# ---------- the resources, staged once and copied into each bundle ----------
set(STAGE "${CMAKE_BINARY_DIR}/resources")
add_custom_target(terrarium_resources
  COMMAND ${CMAKE_COMMAND} -DSCRIPT_DIR=${SCRIPT_DIR} -DMI_UGENS_DIR=${MI_UGENS_DIR} -DSTAGE=${STAGE}
          -P ${CMAKE_CURRENT_SOURCE_DIR}/stage.cmake
  COMMENT "Staging terrarium's Lua and the mi-UGens")
add_dependencies(terrarium_plugin terrarium_resources)

foreach(fmt IN LISTS FORMATS)
  set(t terrarium_plugin_${fmt})
  if(TARGET ${t})
    if(fmt STREQUAL "Standalone" AND NOT APPLE)
      set(dest "$<TARGET_FILE_DIR:${t}>/terrarium-resources")
    else()
      get_target_property(artefact ${t} JUCE_PLUGIN_ARTEFACT_FILE)
      set(dest "${artefact}/Contents/Resources")
    endif()
    add_custom_command(TARGET ${t} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_directory "${STAGE}" "${dest}"
      COMMENT "Resources into terrarium ${fmt}")
  endif()
endforeach()

# ---------- a test host: loads the built plugin like a DAW and checks it plays ----------
juce_add_console_app(terrarium_host_test)
target_sources(terrarium_host_test PRIVATE TestHost.cpp)
target_compile_definitions(terrarium_host_test PRIVATE
  JUCE_PLUGINHOST_VST3=1 JUCE_PLUGINHOST_AU=1 JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0
  JUCE_MODAL_LOOPS_PERMITTED=1)  # it runs the message loop by hand, between blocks
target_link_libraries(terrarium_host_test PRIVATE juce::juce_audio_processors juce::juce_events
  PUBLIC juce::juce_recommended_config_flags)
if(APPLE)
  target_link_libraries(terrarium_host_test PRIVATE "-framework CoreAudioKit")  # hosting AUs (AUGenericView)
endif()
