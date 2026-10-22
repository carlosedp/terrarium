# The JUCE plugin: VST3, AU (macOS) and a standalone app, around terrarium_core.
#
# Each format's bundle gets a Resources/ folder (next to the binary, for the standalone
# on Linux and Windows): the script's Lua (terrarium.lua and lib/), norns-web's norns.lua,
# and the native mi-UGens. The plugin finds them from its own binary.
FetchContent_Declare(juce
  URL https://github.com/juce-framework/JUCE/archive/refs/tags/8.0.4.tar.gz
  URL_HASH SHA256=0effe9823a6fd8a4f98e5c08be7d308350e417b2d15dcf34011e778fefbbf005)
FetchContent_MakeAvailable(juce)

set(FORMATS VST3 Standalone)
if(APPLE)
  list(APPEND FORMATS AU)
endif()

juce_add_plugin(terrarium_plugin
  PRODUCT_NAME "terrarium"
  COMPANY_NAME "Voltage Foundry Modular"
  BUNDLE_ID com.vfmod.terrarium
  PLUGIN_MANUFACTURER_CODE Vfmd
  PLUGIN_CODE Trrm
  IS_SYNTH TRUE
  NEEDS_MIDI_INPUT FALSE
  NEEDS_MIDI_OUTPUT FALSE
  EDITOR_WANTS_KEYBOARD_FOCUS TRUE
  VST3_CATEGORIES Instrument Generator
  AU_MAIN_TYPE kAudioUnitType_MusicDevice
  FORMATS ${FORMATS})

target_sources(terrarium_plugin PRIVATE PluginProcessor.cpp PluginEditor.cpp)
target_compile_definitions(terrarium_plugin PUBLIC
  JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_VST3_CAN_REPLACE_VST2=0 JUCE_DISPLAY_SPLASH_SCREEN=0)
target_link_libraries(terrarium_plugin
  PRIVATE terrarium_core juce::juce_audio_utils
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
