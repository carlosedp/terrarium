// terrarium, in-process: the script's Lua and the engine, and the time between them.
//
// The audio thread owns time. Lua runs on another thread (the plugin's message thread),
// a little ahead of the audio: each tick() runs Lua's clocks up to the audio's time plus
// LOOKAHEAD, and the engine commands that come out, stamped with the exact Lua time they
// were made at, wait in the audio thread until its time gets there. So notes land on
// their 64-sample block however late the message thread ticks, as long as it ticks
// within the lookahead.
//
// With the host playing, Lua's beat follows the host's: when they drift apart (the
// transport starts, loops, jumps, the tempo changes) Lua's time jumps forward to the
// host's beat phase. Only forward: a waiting clock routine would wait out a jump back.
//
// Threads: boot() and tick(), enc(), key()... on the message thread; prepare() before the
// audio starts; process() on the audio thread. With render offline (a bounce, the
// command-line renderer) process() ticks Lua itself, as nothing else would keep up.
#pragma once

#include <atomic>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "Commands.h"
#include "Engine.h"
#include "LuaHost.h"
#include "Resampler.h"

namespace terrarium {

struct HostTime {
    bool valid = false;    // the host says where it is
    bool playing = false;
    double bpm = 120;
    double ppq = 0;        // its position in beats, at the start of this block
};

class Terrarium {
public:
    static constexpr double LOOKAHEAD = 0.1;  // seconds Lua runs ahead of the audio
    static constexpr double TICK = 1.0 / 60;  // how often Lua ticks when rendering offline
    static constexpr double ENGINE_SR = 48000;  // the engine's rate, whatever the host's (a norns')

    struct Paths {
        std::string nornsLua;  // norns-web's norns.lua
        std::string script;    // the folder with terrarium.lua and lib/
        std::string miLibs;    // the native mi-UGens
        std::string name = "terrarium";  // the script: <script>/<name>.lua
    };

    explicit Terrarium(Paths paths);
    ~Terrarium();

    std::function<void(const std::string&, bool)> onLog;  // message thread (or the offline audio thread)
    // each engine command as the audio runs it, with the time of its block (for tests; audio thread)
    std::function<void(const Command&, double)> onRun;

    bool boot(std::string& err);
    void prepare(double sampleRate);

    // in: the plugin's input (visitors hear it), or null
    void process(float* left, float* right, int n, const HostTime& host, bool offline = false,
                 const float* inL = nullptr, const float* inR = nullptr);
    // on: while the host's transport is stopped, Lua's clocks wait (no weather); off, they run on
    void setStopWithTransport(bool on);

    // the message thread's part
    bool tick();  // true if the screen changed
    void enc(int n, int d);
    void key(int n, int z);
    void repl(const std::string& code);
    void copyFrame(unsigned char out[128 * 64]);

    // PARAMS (message thread): see LuaHost
    std::string paramsJson();
    void paramDelta(int index, double d);
    void paramDelta(const std::string& id, double d);
    void pset(const std::string& action, const std::string& slot);
    bool getNorm(const std::string& id, double& out);
    void setNorm(const std::string& id, double v);
    std::string paramId(int index);
    int paramIndex(const std::string& id);
    std::string paramName(const std::string& id);

    // the plugin's state: the params as a PSET, and what Lua stored
    std::map<std::string, std::string> saveState();
    void loadState(const std::map<std::string, std::string>& s);

private:
    Paths paths_;
    std::mutex lua_;  // never taken by the audio thread unless offline
    std::unique_ptr<LuaHost> host_;
    Engine engine_;
    // the queue and the pending list are big (about 1.2 MB): on the heap, so a Terrarium can
    // live anywhere (Windows gives a thread 1 MB of stack)
    std::unique_ptr<CommandQueue> queue_ = std::make_unique<CommandQueue>();

    // audio thread
    double sr_ = 48000;
    double t_ = 0;               // the time of the next block to render
    float bufL_[BLOCK], bufR_[BLOCK];
    Resampler out_, in_;         // 48 kHz to the host's rate, and the host's input to 48 kHz
    bool offline_ = false;
    std::vector<Command> pending_ = std::vector<Command>(1024);
    int npending_ = 0;
    double nextOfflineTick_ = 0;
    std::vector<float> inL_ = std::vector<float>(1 << 15), inR_ = std::vector<float>(1 << 15);  // the input, a ring
    size_t inRead_ = 0, inWrite_ = BLOCK;

    // shared
    std::atomic<double> audioTime_{0};
    std::atomic<double> tempo_{120};
    std::atomic<bool> stopWithTransport_{false}, running_{true};
    bool luaRunning_ = true;
    double luaTime_ = 0, luaTempo_ = 0;  // Lua's side

    void renderBlock();
    void follow(const HostTime& host);
    void tickLocked(double t);
};

}  // namespace terrarium
