#include "LuaHost.h"

#include <cstring>

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
}

namespace terrarium {

static const char* SELF = "terrarium.host";

// What the plugin needs of PARAMS beyond norns-web's panel: a param as 0..1 and back, for host
// automation. norns.lua's kinds: control (a controlspec), number, option, binary, trigger.
static const char* HOST_LUA = R"LUA(
norns_web_host = {}
local function find(id)
  local ok, p = pcall(params.lookup_param, params, id)
  if ok then return p end
end
function norns_web_host.norm(id)
  local p = find(id)
  if not p then return nil end
  if p.kind == "control" then return p.spec:unmap(p.value)
  elseif p.kind == "number" then return (p.value - p.min) / math.max(1, p.max - p.min)
  elseif p.kind == "option" then return (p.value - 1) / math.max(1, #p.options - 1)
  elseif p.kind == "binary" or p.kind == "trigger" then return p.value end
end
function norns_web_host.set_norm(id, v)
  local p = find(id)
  if not p then return end
  v = math.max(0, math.min(1, v))
  if p.kind == "control" then params:set(p.id, p.spec:map(v))
  elseif p.kind == "number" then params:set(p.id, p.min + math.floor(v * (p.max - p.min) + 0.5))
  elseif p.kind == "option" then params:set(p.id, 1 + math.floor(v * (#p.options - 1) + 0.5))
  elseif p.kind == "binary" then params:set(p.id, v >= 0.5 and 1 or 0)
  elseif p.kind == "trigger" then if v >= 0.5 then params:set(p.id, 1) end end
end
function norns_web_host.id(i) local p = find(i); return p and p.id or "" end
function norns_web_host.index(id) return params.lookup[id] or 0 end
function norns_web_host.name(id) local p = find(id); return p and (p.name or p.id) or "" end
)LUA";

LuaHost::LuaHost(Callbacks cb) : cb_(std::move(cb)) {}

LuaHost::~LuaHost() {
    if (!L_) return;
    lua_getglobal(L_, "cleanup");  // the script's own, as norns calls it when a script stops
    if (lua_isfunction(L_, -1)) lua_pcall(L_, 0, 0, 0);
    else lua_pop(L_, 1);
    lua_close(L_);
}

LuaHost* LuaHost::self(lua_State* L) {
    lua_getfield(L, LUA_REGISTRYINDEX, SELF);
    auto* h = static_cast<LuaHost*>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return h;
}

// engine.<cmd>(...): stamped with util.time(), Lua's now (a clock routine's wake time)
int LuaHost::l_engine(lua_State* L) {
    Command c;
    std::strncpy(c.name, luaL_checkstring(L, 1), sizeof(c.name) - 1);
    int n = lua_gettop(L) - 1;
    c.argc = n < 4 ? n : 4;
    for (int i = 0; i < c.argc; ++i) {
        int idx = i + 2;
        if (lua_type(L, idx) == LUA_TNUMBER) c.args[i].num = lua_tonumber(L, idx);
        else {
            c.args[i].isString = true;
            const char* s = lua_tostring(L, idx);
            std::strncpy(c.args[i].str, s ? s : "", sizeof(c.args[i].str) - 1);
        }
    }
    lua_getglobal(L, "util");
    lua_getfield(L, -1, "time");
    if (lua_pcall(L, 0, 1, 0) == LUA_OK) c.time = lua_tonumber(L, -1);
    lua_pop(L, 2);
    auto* h = self(L);
    if (h->cb_.engine) h->cb_.engine(c);
    return 0;
}

int LuaHost::l_engine_name(lua_State*) { return 0; }

int LuaHost::l_log(lua_State* L) {
    auto* h = self(L);
    if (h->cb_.log) h->cb_.log(luaL_optstring(L, 1, ""), false);
    return 0;
}

int LuaHost::l_error(lua_State* L) {
    auto* h = self(L);
    if (h->cb_.log) h->cb_.log(luaL_optstring(L, 1, ""), true);
    return 0;
}

// util.os_capture: the installer looks for mi-UGens with find; they're inside the plugin
int LuaHost::l_os_capture(lua_State* L) {
    const char* cmd = luaL_optstring(L, 1, "");
    bool find_sc = std::strncmp(cmd, "find ", 5) == 0 && std::strstr(cmd, ".sc");
    lua_pushstring(L, find_sc ? "/terrarium-plugin/Mi.sc" : "");
    return 1;
}

int LuaHost::l_nb(lua_State*) { return 0; }  // no nb voices in the plugin

int LuaHost::l_storage_get(lua_State* L) {
    auto* h = self(L);
    auto it = h->storage.find(luaL_checkstring(L, 1));
    lua_pushstring(L, it == h->storage.end() ? "" : it->second.c_str());
    return 1;
}

int LuaHost::l_storage_set(lua_State* L) {
    self(L)->storage[luaL_checkstring(L, 1)] = luaL_checkstring(L, 2);
    return 0;
}

bool LuaHost::call(const char* fn, int nargs, int nresults) {
    // norns_web.<fn> with nargs already pushed
    lua_getglobal(L_, "norns_web");
    lua_getfield(L_, -1, fn);
    lua_remove(L_, -2);
    lua_insert(L_, -(nargs + 1));
    if (lua_pcall(L_, nargs, nresults, 0) != LUA_OK) {
        if (cb_.log) cb_.log(lua_tostring(L_, -1), true);
        lua_pop(L_, 1);
        return false;
    }
    return true;
}

bool LuaHost::boot(const std::string& nornsLua, const std::string& scriptDir, const std::string& name) {
    L_ = luaL_newstate();
    luaL_openlibs(L_);
    lua_pushlightuserdata(L_, this);
    lua_setfield(L_, LUA_REGISTRYINDEX, SELF);

    static const luaL_Reg bridge[] = {
        {"engine", l_engine},       {"engine_name", l_engine_name}, {"log", l_log},
        {"error", l_error},         {"os_capture", l_os_capture},   {"nb", l_nb},
        {"storage_get", l_storage_get}, {"storage_set", l_storage_set}, {nullptr, nullptr},
    };
    luaL_newlib(L_, bridge);
    lua_setglobal(L_, "js_bridge");

    if (luaL_dofile(L_, nornsLua.c_str()) != LUA_OK) {
        if (cb_.log) cb_.log(std::string("norns.lua: ") + lua_tostring(L_, -1), true);
        return false;
    }
    if (luaL_dostring(L_, HOST_LUA) != LUA_OK) {
        if (cb_.log) cb_.log(std::string("host helpers: ") + lua_tostring(L_, -1), true);
        return false;
    }
    // the script's own folder, whatever it's called (norns.lua would look in _path.code/<name>/)
    std::string dir = scriptDir;
    if (!dir.empty() && dir.back() != '/' && dir.back() != '\\') dir += '/';
    lua_pushstring(L_, name.c_str());
    lua_pushstring(L_, (name + ".lua").c_str());
    lua_pushstring(L_, dir.c_str());
    return call("boot", 3, 0);
}

bool LuaHost::tick(double t) {
    if (!L_) return false;
    lua_pushnumber(L_, t);
    if (!call("tick", 1, 1)) return false;
    bool drew = false;
    size_t len = 0;
    const char* s = lua_tolstring(L_, -1, &len);  // "A".."P" per pixel, when the screen changed
    if (s && len >= sizeof(frame_)) {
        for (size_t i = 0; i < sizeof(frame_); ++i) frame_[i] = (unsigned char)(s[i] - 'A') & 15;
        drew = true;
    }
    lua_pop(L_, 1);
    return drew;
}

void LuaHost::setTempo(double bpm) {
    if (!L_) return;
    lua_pushnumber(L_, bpm);
    call("set_tempo", 1, 0);
}

void LuaHost::setRunning(bool on) {
    if (!L_) return;
    lua_pushboolean(L_, on);
    call("set_running", 1, 0);
}

void LuaHost::enc(int n, int d) {
    if (!L_) return;
    lua_pushinteger(L_, n);
    lua_pushinteger(L_, d);
    call("enc", 2, 0);
}

void LuaHost::key(int n, int z) {
    if (!L_) return;
    lua_pushinteger(L_, n);
    lua_pushinteger(L_, z);
    call("key", 2, 0);
}

void LuaHost::repl(const std::string& code) {
    if (!L_) return;
    lua_pushstring(L_, code.c_str());
    call("repl", 1, 0);
}

void LuaHost::pset(const std::string& action, const std::string& slot) {
    if (!L_) return;
    lua_pushstring(L_, action.c_str());
    lua_pushstring(L_, slot.c_str());
    call("pset", 2, 0);
}

// ---------- PARAMS ----------

std::string LuaHost::paramsJson() {
    if (!L_) return "[]";
    if (!call("params_json", 0, 1)) return "[]";
    std::string s = lua_tostring(L_, -1) ? lua_tostring(L_, -1) : "[]";
    lua_pop(L_, 1);
    return s;
}

void LuaHost::paramDelta(int index, double d) {
    if (!L_) return;
    lua_pushinteger(L_, index);
    lua_pushnumber(L_, d);
    call("param_delta", 2, 0);
}

void LuaHost::paramDelta(const std::string& id, double d) {
    if (!L_) return;
    lua_pushstring(L_, id.c_str());
    lua_pushnumber(L_, d);
    call("param_delta", 2, 0);
}

// norns_web_host.<fn>(arg): leaves its one result on the stack, or returns false
static bool hostCall(lua_State* L, const char* fn, int nargs) {
    lua_getglobal(L, "norns_web_host");
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    lua_insert(L, -(nargs + 1));
    if (lua_pcall(L, nargs, 1, 0) != LUA_OK) {
        lua_pop(L, 1);
        return false;
    }
    return true;
}

bool LuaHost::getNorm(const std::string& id, double& out) {
    if (!L_) return false;
    lua_pushstring(L_, id.c_str());
    if (!hostCall(L_, "norm", 1)) return false;
    bool ok = lua_isnumber(L_, -1);
    if (ok) out = lua_tonumber(L_, -1);
    lua_pop(L_, 1);
    return ok;
}

void LuaHost::setNorm(const std::string& id, double v) {
    if (!L_) return;
    lua_pushstring(L_, id.c_str());
    lua_pushnumber(L_, v);
    if (hostCall(L_, "set_norm", 2)) lua_pop(L_, 1);
}

std::string LuaHost::paramId(int index) {
    if (!L_) return "";
    lua_pushinteger(L_, index);
    if (!hostCall(L_, "id", 1)) return "";
    std::string s = lua_tostring(L_, -1) ? lua_tostring(L_, -1) : "";
    lua_pop(L_, 1);
    return s;
}

int LuaHost::paramIndex(const std::string& id) {
    if (!L_) return 0;
    lua_pushstring(L_, id.c_str());
    if (!hostCall(L_, "index", 1)) return 0;
    int i = (int)lua_tointeger(L_, -1);
    lua_pop(L_, 1);
    return i;
}

std::string LuaHost::paramName(const std::string& id) {
    if (!L_) return "";
    lua_pushstring(L_, id.c_str());
    if (!hostCall(L_, "name", 1)) return "";
    std::string s = lua_tostring(L_, -1) ? lua_tostring(L_, -1) : "";
    lua_pop(L_, 1);
    return s;
}

}  // namespace terrarium
