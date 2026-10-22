# Stages what the plugin needs at run time (cmake -P, from juce/CMakeLists.txt):
#   terrarium/          terrarium.lua and lib/**/*.lua: the script, as it is on a norns
#   norns-web/norns.lua the norns API it runs on
#   mi-UGens/           the native mi-UGens' libraries
file(REMOVE_RECURSE "${STAGE}")
file(MAKE_DIRECTORY "${STAGE}/terrarium" "${STAGE}/norns-web" "${STAGE}/mi-UGens")
file(COPY "${SCRIPT_DIR}/terrarium.lua" DESTINATION "${STAGE}/terrarium")
file(COPY "${SCRIPT_DIR}/lib" DESTINATION "${STAGE}/terrarium" FILES_MATCHING PATTERN "*.lua")
file(COPY "${SCRIPT_DIR}/tools/norns-web/lib/norns.lua" DESTINATION "${STAGE}/norns-web")
file(GLOB libs "${MI_UGENS_DIR}/lib/Mi*")
file(COPY ${libs} DESTINATION "${STAGE}/mi-UGens")
file(COPY "${MI_UGENS_DIR}/BUILDINFO" DESTINATION "${STAGE}/mi-UGens")
