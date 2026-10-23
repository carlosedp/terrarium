# Stages what the plugin needs at run time (cmake -P, from juce/CMakeLists.txt):
#   terrarium/          terrarium.lua and lib/**/*.lua: the script, as it is on a norns
#   norns-web/norns.lua the norns API it runs on
#   mi-UGens/           the native mi-UGens' libraries
#   web/                norns-web's page, the plugin's face: index.html and norns-web.js, a
#                       files.json with norns-web.json's text (and no Lua: the plugin runs it),
#                       the icons it names, under script/, and its fonts (no Google Fonts: a
#                       DAW may well be offline)
file(REMOVE_RECURSE "${STAGE}")
file(MAKE_DIRECTORY "${STAGE}/terrarium" "${STAGE}/norns-web" "${STAGE}/mi-UGens")
file(COPY "${SCRIPT_DIR}/terrarium.lua" DESTINATION "${STAGE}/terrarium")
file(COPY "${SCRIPT_DIR}/lib" DESTINATION "${STAGE}/terrarium" FILES_MATCHING PATTERN "*.lua")
file(COPY "${SCRIPT_DIR}/tools/norns-web/lib/norns.lua" DESTINATION "${STAGE}/norns-web")
file(GLOB libs "${MI_UGENS_DIR}/lib/Mi*")
file(COPY ${libs} DESTINATION "${STAGE}/mi-UGens")
file(COPY "${MI_UGENS_DIR}/BUILDINFO" DESTINATION "${STAGE}/mi-UGens")

file(MAKE_DIRECTORY "${STAGE}/web")
file(READ "${SCRIPT_DIR}/tools/norns-web/index.html" page)
# no analytics inside a DAW: the page's Google tag (gtag.js) is for the website
string(REGEX REPLACE "<!-- Google tag \\(gtag\\.js\\) -->.*gtag\\('config'[^<]*</script>" "" page "${page}")
# the fonts from the bundle, not from Google
string(REGEX REPLACE "<link rel=\"preconnect\"[^>]*>" "" page "${page}")
string(REGEX REPLACE "<link rel=\"stylesheet\"[^>]*fonts\\.googleapis\\.com[^>]*>" "<link rel=\"stylesheet\" href=\"fonts/fonts.css\">" page "${page}")
file(COPY "${SCRIPT_DIR}/tools/norns-web/fonts" DESTINATION "${STAGE}/web")
file(WRITE "${STAGE}/web/index.html" "${page}")
file(COPY "${SCRIPT_DIR}/tools/norns-web/norns-web.js" DESTINATION "${STAGE}/web")
set(about "null")
if(EXISTS "${SCRIPT_DIR}/norns-web.json")
  file(READ "${SCRIPT_DIR}/norns-web.json" about)
  foreach(key icon touch_icon)
    string(JSON f ERROR_VARIABLE none GET "${about}" ${key})
    if(f AND EXISTS "${SCRIPT_DIR}/${f}")
      get_filename_component(d "${STAGE}/web/script/${f}" DIRECTORY)
      file(COPY "${SCRIPT_DIR}/${f}" DESTINATION "${d}")
    endif()
  endforeach()
endif()
file(WRITE "${STAGE}/web/files.json"
  "{\"name\": \"terrarium\", \"main\": \"terrarium.lua\", \"root\": \"script/\", \"files\": {}, \"about\": ${about}}\n")
