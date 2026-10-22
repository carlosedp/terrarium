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

bool Terrarium::boot(std::string& err) {
    if (!engine_.load(paths_.miLibs, err)) return false;
    std::lock_guard<std::mutex> lock(lua_);
    host_ = std::make_unique<LuaHost>(LuaHost::Callbacks{
        [this](const Command& c) {
            if (!queue_.push(c) && onLog) onLog("engine queue full, a command was dropped", true);
        },
        [this](const std::string& s, bool error) {
            if (onLog) onLog(s, error);
        },
    });
    if (!host_->boot(paths_.nornsLua, paths_.script, paths_.name)) {
        err = "the script didn't start (see the log)";
        return false;
    }
    return true;
}

void Terrarium::prepare(double sampleRate) {
    sr_ = sampleRate;
    engine_.prepare(sampleRate);
    bufPos_ = BLOCK;
}

// ---------- the audio thread ----------

void Terrarium::follow(const HostTime& host) {
    if (!host.valid) return;
    if (host.bpm > 0) tempo_.store(host.bpm, std::memory_order_relaxed);
    if (!host.playing || host.bpm <= 0) return;
    // where this host block starts, in Lua's time: the samples already rendered come first
    double now = t_ - (BLOCK - bufPos_) / sr_;
    double beats = now * host.bpm / 60;
    double ahead = host.ppq - beats;
    ahead -= std::floor(ahead);  // how far the host's beat phase is ahead of Lua's, 0..1
    if (ahead > 0.002 && ahead < 0.998) t_ += ahead * 60 / host.bpm;
}

void Terrarium::renderBlock() {
    double end = t_ + BLOCK / sr_;
    // run what's due by the end of this block, in time order (they come mostly sorted)
    Command c;
    while (npending_ < (int)(sizeof(pending_) / sizeof(pending_[0])) && queue_.pop(c)) pending_[npending_++] = c;
    for (;;) {
        int first = -1;
        for (int i = 0; i < npending_; ++i)
            if (pending_[i].time < end && (first < 0 || pending_[i].time < pending_[first].time)) first = i;
        if (first < 0) break;
        if (onRun) onRun(pending_[first], t_);
        engine_.command(pending_[first]);
        pending_[first] = pending_[--npending_];
    }
    engine_.render(bufL_, bufR_);
    t_ = end;
    audioTime_.store(t_, std::memory_order_release);
}

void Terrarium::process(float* left, float* right, int n, const HostTime& host, bool offline) {
    follow(host);
    for (int i = 0; i < n;) {
        if (bufPos_ == BLOCK) {
            if (offline && t_ + LOOKAHEAD >= nextOfflineTick_) {
                std::lock_guard<std::mutex> lock(lua_);
                tickLocked(t_ + LOOKAHEAD);
                nextOfflineTick_ = t_ + LOOKAHEAD + TICK;
            }
            renderBlock();
            bufPos_ = 0;
        }
        int k = std::min(n - i, BLOCK - bufPos_);
        std::memcpy(left + i, bufL_ + bufPos_, k * sizeof(float));
        std::memcpy(right + i, bufR_ + bufPos_, k * sizeof(float));
        bufPos_ += k;
        i += k;
    }
    // a loud moment from the voices shouldn't hit the host past full scale
    for (int i = 0; i < n; ++i) {
        left[i] = std::tanh(left[i] * 0.75f);
        right[i] = std::tanh(right[i] * 0.75f);
    }
}

// ---------- the message thread ----------

void Terrarium::tickLocked(double t) {
    if (!host_) return;
    double tempo = tempo_.load(std::memory_order_relaxed);
    if (tempo != luaTempo_) {
        luaTempo_ = tempo;
        host_->setTempo(tempo);
    }
    if (t < luaTime_) t = luaTime_;  // Lua's time never goes back
    luaTime_ = t;
    host_->tick(t);
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

}  // namespace terrarium
