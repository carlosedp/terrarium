#include "Terrarium.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace terrarium {

Terrarium::Terrarium(Paths paths) : paths_(std::move(paths)) {}

Terrarium::~Terrarium() {
    std::lock_guard<std::mutex> lock(lua_);
    host_.reset();
}

// A part's module is its <layer>_kind option (the options are the modules' ids), and the
// module's macros are its control params <module>_<macro>, in the order they were added (each
// followed by its _cv param, which isn't one).
static const char* MACROS_LUA = R"LUA(
local LAYER = { "brain", "voice", "color", "air", "drone" }
function terrarium_macro(part, k)
  local ok, kind = pcall(function()
    local p = params:lookup_param(LAYER[part] .. "_kind")
    return p.options[p.value]
  end)
  if not ok or not kind then return "" end
  local n = 0
  for _, p in ipairs(params.params) do
    if p.kind == "control" and p.id and p.id:sub(1, #kind + 1) == kind .. "_" and not p.id:match("_cv$") then
      n = n + 1
      if n == k then return p.id end
    end
  end
  return ""
end
)LUA";

const char* Terrarium::partName(int i) {
    static const char* names[] = {"weather", "soil", "water", "air", "hum"};
    return i >= 1 && i <= PARTS ? names[i - 1] : "";
}

bool Terrarium::boot(std::string& err) {
    if (!engine_.load(paths_.miLibs, err)) return false;
    std::lock_guard<std::mutex> lock(lua_);
    host_ = std::make_unique<LuaHost>(LuaHost::Callbacks{
        [this](const Command& cmd) {
            Command c = cmd;
            engine_.prepareCommand(c);  // a module swap gets its synth here, not on the audio thread
            if (!queue_->push(c)) {
                engine_.discard(c);
                if (onLog) onLog("engine queue full, a command was dropped", true);
            }
        },
        [this](const std::string& s, bool error) {
            if (onLog) onLog(s, error);
        },
    });
    if (!host_->boot(paths_.nornsLua, paths_.script, paths_.name)) {
        err = "the script didn't start (see the log)";
        return false;
    }
    host_->doString(MACROS_LUA);
    return true;
}

// with the audio stopped: what Lua has sent so far is run, then every slot is rebuilt. The engine
// runs at 48 kHz whatever the host's rate (as a norns does); the edges convert.
void Terrarium::prepare(double sampleRate) {
    std::lock_guard<std::mutex> lock(lua_);
    sr_ = sampleRate;
    Command c;
    for (int i = 0; i < npending_; ++i) engine_.command(pending_[i]);
    npending_ = 0;
    while (queue_->pop(c)) engine_.command(c);
    engine_.prepare(ENGINE_SR);
    out_.configure(ENGINE_SR, sampleRate);
    in_.configure(sampleRate, ENGINE_SR);
    // the input is heard a block late: one block of silence first, so it never runs dry
    inRead_ = 0;
    inWrite_ = BLOCK;
    std::fill(inL_.begin(), inL_.end(), 0.0f);
    std::fill(inR_.begin(), inR_.end(), 0.0f);
}

// ---------- the audio thread ----------

void Terrarium::follow(const HostTime& host) {
    // stopped with the transport: Lua's clock routines wait while the host's transport is stopped
    running_.store(!(stopWithTransport_.load(std::memory_order_relaxed) && host.valid && !host.playing),
                   std::memory_order_relaxed);
    if (!host.valid) return;
    if (host.bpm > 0) tempo_.store(host.bpm, std::memory_order_relaxed);
    if (!host.playing || host.bpm <= 0) return;
    // where this host block starts, in Lua's time: what's rendered and not yet out comes first
    double now = t_ - (double)out_.pending() / ENGINE_SR;
    double beats = now * host.bpm / 60;
    double ahead = host.ppq - beats;
    ahead -= std::floor(ahead);  // how far the host's beat phase is ahead of Lua's, 0..1
    if (ahead > 0.002 && ahead < 0.998) t_ += ahead * 60 / host.bpm;
}

// one block of the engine, at 48 kHz, into the output's resampler
void Terrarium::renderBlock() {
    if (offline_ && t_ + LOOKAHEAD >= nextOfflineTick_) {
        std::lock_guard<std::mutex> lock(lua_);
        tickLocked(t_ + LOOKAHEAD);
        nextOfflineTick_ = t_ + LOOKAHEAD + TICK;
    }
    double end = t_ + BLOCK / ENGINE_SR;
    // run what's due by the end of this block, in time order (they come mostly sorted)
    Command c;
    while (npending_ < (int)pending_.size() && queue_->pop(c)) pending_[npending_++] = c;
    for (;;) {
        int first = -1;
        for (int i = 0; i < npending_; ++i)
            if (pending_[i].time < end && (first < 0 || pending_[i].time < pending_[first].time)) first = i;
        if (first < 0) break;
        if (onRun) onRun(pending_[first], t_);
        engine_.command(pending_[first]);
        pending_[first] = pending_[--npending_];
    }
    float inL[BLOCK], inR[BLOCK];
    size_t mask = inL_.size() - 1;
    for (int i = 0; i < BLOCK; ++i) {
        bool have = inRead_ != inWrite_;
        inL[i] = have ? inL_[inRead_ & mask] : 0.0f;
        inR[i] = have ? inR_[inRead_ & mask] : 0.0f;
        if (have) ++inRead_;
    }
    engine_.render(bufL_, bufR_, inL, inR);
    out_.push(bufL_, bufR_, BLOCK);
    t_ = end;
    audioTime_.store(t_, std::memory_order_release);
}

void Terrarium::process(float* left, float* right, int n, const HostTime& host, bool offline, const float* inL,
                        const float* inR) {
    offline_ = offline;
    follow(host);
    // the input, converted to 48 kHz, waits in a ring for the engine's blocks
    static const float silence[512] = {};
    for (int i = 0; i < n; i += 512) {
        int k = std::min(512, n - i);
        in_.push(inL ? inL + i : silence, inR ? inR + i : (inL ? inL + i : silence), k);
        float l[1024], r[1024];
        size_t mask = inL_.size() - 1;
        for (int got; (got = in_.pull(l, r, 1024)) > 0;)
            for (int j = 0; j < got && inWrite_ - inRead_ < inL_.size(); ++j, ++inWrite_) {
                inL_[inWrite_ & mask] = l[j];
                inR_[inWrite_ & mask] = r[j];
            }
    }
    // the output: the engine's blocks, converted to the host's rate as the host asks for them
    for (int i = 0; i < n;) {
        i += out_.pull(left + i, right + i, n - i);
        if (i < n) renderBlock();
    }
    // a loud moment from the voices shouldn't hit the host past full scale
    for (int i = 0; i < n; ++i) {
        left[i] = std::tanh(left[i] * 0.75f);
        right[i] = std::tanh(right[i] * 0.75f);
    }
}

void Terrarium::setStopWithTransport(bool on) { stopWithTransport_.store(on, std::memory_order_relaxed); }

// ---------- the message thread ----------

void Terrarium::tickLocked(double t) {
    if (!host_) return;
    double tempo = tempo_.load(std::memory_order_relaxed);
    if (tempo != luaTempo_) {
        luaTempo_ = tempo;
        host_->setTempo(tempo);
    }
    bool running = running_.load(std::memory_order_relaxed);
    if (running != luaRunning_) {
        luaRunning_ = running;
        host_->setRunning(running);
    }
    if (t < luaTime_) t = luaTime_;  // Lua's time never goes back
    luaTime_ = t;
    host_->tick(t);
    engine_.emptyTrash();
    Note note;
    while (engine_.notes.pop(note))
        if (onLog) onLog(note.text, false);
}

bool Terrarium::tick() {
    std::lock_guard<std::mutex> lock(lua_);
    if (!host_) return false;
    std::vector<unsigned char> before(host_->frame(), host_->frame() + 128 * 64);
    tickLocked(audioTime_.load(std::memory_order_acquire) + LOOKAHEAD);
    return std::memcmp(before.data(), host_->frame(), 128 * 64) != 0;
}

void Terrarium::enc(int n, int d) {
    std::lock_guard<std::mutex> lock(lua_);
    if (host_) host_->enc(n, d);
}

void Terrarium::key(int n, int z) {
    std::lock_guard<std::mutex> lock(lua_);
    if (host_) host_->key(n, z);
}

void Terrarium::repl(const std::string& code) {
    std::lock_guard<std::mutex> lock(lua_);
    if (host_) host_->repl(code);
}

void Terrarium::copyFrame(unsigned char out[128 * 64]) {
    std::lock_guard<std::mutex> lock(lua_);
    if (host_) std::memcpy(out, host_->frame(), 128 * 64);
    else std::memset(out, 0, 128 * 64);
}

std::map<std::string, std::string> Terrarium::saveState() {
    std::lock_guard<std::mutex> lock(lua_);
    if (!host_) return {};
    host_->pset("save", "daw");  // every param, into storage as pset:daw
    return host_->storage;
}

void Terrarium::loadState(const std::map<std::string, std::string>& s) {
    std::lock_guard<std::mutex> lock(lua_);
    if (!host_) return;
    host_->storage = s;
    if (s.count("pset:daw")) host_->pset("load", "daw");
}

// ---------- PARAMS ----------

#define WITH_LUA(dflt) \
    std::lock_guard<std::mutex> lock(lua_); \
    if (!host_) return dflt

std::string Terrarium::paramsJson() { WITH_LUA("[]"); return host_->paramsJson(); }
void Terrarium::paramDelta(int index, double d) { WITH_LUA(void()); host_->paramDelta(index, d); }
void Terrarium::paramDelta(const std::string& id, double d) { WITH_LUA(void()); host_->paramDelta(id, d); }
void Terrarium::pset(const std::string& action, const std::string& slot) { WITH_LUA(void()); host_->pset(action, slot); }
bool Terrarium::getNorm(const std::string& id, double& out) { WITH_LUA(false); return host_->getNorm(id, out); }
void Terrarium::setNorm(const std::string& id, double v) { WITH_LUA(void()); host_->setNorm(id, v); }
std::string Terrarium::paramId(int index) { WITH_LUA(""); return host_->paramId(index); }
int Terrarium::paramIndex(const std::string& id) { WITH_LUA(0); return host_->paramIndex(id); }
std::string Terrarium::paramName(const std::string& id) { WITH_LUA(""); return host_->paramName(id); }
std::string Terrarium::macroParam(int part, int k) { WITH_LUA(""); return host_->callString("terrarium_macro", part, k); }

#undef WITH_LUA

}  // namespace terrarium
