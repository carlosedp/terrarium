// The script's Lua, in-process: Lua 5.3 (what norns runs) with norns-web's norns.lua as the
// norns API, so terrarium's own files run unchanged. norns.lua talks to its host through a
// js_bridge table; here those functions are C++.
//
// Not thread-safe: one thread (the plugin's message thread) makes every call.
#pragma once

#include <functional>
#include <map>
#include <string>
#include <vector>

#include "Commands.h"

struct lua_State;

namespace terrarium {

class LuaHost {
public:
    struct Callbacks {
        std::function<void(const Command&)> engine;            // an engine command, stamped
        std::function<void(const std::string&, bool)> log;      // a line of output; true: an error
        std::function<void(const MidiEvent&)> midi;             // a MIDI message, stamped
    };

    explicit LuaHost(Callbacks cb);
    ~LuaHost();
    LuaHost(const LuaHost&) = delete;
    LuaHost& operator=(const LuaHost&) = delete;

    // nornsLua: norns-web's norns.lua; scriptDir: the folder holding <name>.lua and its lib/
    // (named anything)
    bool boot(const std::string& nornsLua, const std::string& scriptDir, const std::string& name);

    // Lua's clocks and metros up to time t (seconds); true if the screen changed
    bool tick(double t);
    void setTempo(double bpm);
    void setRunning(bool on);  // false: the clock routines wait (a stopped transport)
    void enc(int n, int d);
    void key(int n, int z);
    void repl(const std::string& code);
    void pset(const std::string& action, const std::string& slot);  // "save" | "load"

    // PARAMS, for the plugin's face: the list as norns-web's panel wants it (JSON), and a step
    // of one param, by index or id
    std::string paramsJson();
    void paramDelta(int index, double d);
    void paramDelta(const std::string& id, double d);
    // a param as 0..1 (for host automation): nothing for kinds that have no such value
    bool getNorm(const std::string& id, double& out);
    void setNorm(const std::string& id, double v);
    std::string paramId(int index);   // "" if there's none
    int paramIndex(const std::string& id);  // 0 if there's none
    std::string paramName(const std::string& id);

    // Lua of the host's own, after boot: a chunk, and a global function of two integers that
    // returns a string ("" if it fails)
    bool doString(const char* code);
    std::string callString(const char* fn, int a, int b);

    // the screen: 128x64 levels 0..15, the last frame the script drew
    const unsigned char* frame() const { return frame_; }

    // what params:write() kept (PSETs), saved with the plugin's state
    std::map<std::string, std::string> storage;
    // the MIDI ports norns' midi.vports shows (up to 16), set before boot
    std::vector<std::string> midiPorts;

private:
    lua_State* L_ = nullptr;
    Callbacks cb_;
    unsigned char frame_[128 * 64] = {};

    bool call(const char* fn, int nargs, int nresults);
    static LuaHost* self(lua_State* L);
    static int l_engine(lua_State* L);
    static int l_engine_name(lua_State* L);
    static int l_log(lua_State* L);
    static int l_error(lua_State* L);
    static int l_os_capture(lua_State* L);
    static int l_nb(lua_State* L);
    static int l_storage_get(lua_State* L);
    static int l_storage_set(lua_State* L);
    static int l_midi_ports(lua_State* L);
    static int l_midi_send(lua_State* L);
};

}  // namespace terrarium
