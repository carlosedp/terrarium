// The engine: Engine_Terrarium.sc for the plugin, as Engine_Terrarium.js is for the browser.
// Each SynthDef becomes a Synth built from the native mi-UGens (norns-mi-UGens'
// native libraries, through mi_ugens.hpp) and a few plain blocks, running in 64-sample
// blocks as scsynth does.
//
//   voice (2x MiPlaits | MiRings | the input) -> voiceBus -> color -> colorBus -> air -> tape -> out
//   drone -> colorBus
//
// Phase 2: the commands are all taken and their state kept, but only voice_plaits plays;
// the rest of Engine_Terrarium.js comes next (doc/PLUGIN.md).
//
// load() and prepare() on the message thread, before the audio starts; command() and
// render() on the audio thread.
#pragma once

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "Commands.h"
#include "mi_ugens.hpp"

namespace terrarium {

constexpr int BLOCK = mi::BLOCK;

// a line for the log, from the audio thread (it can't log itself)
struct Note {
    char text[96] = {};
};

class Engine {
public:
    Engine();
    ~Engine();

    // the native mi-UGens in libDir (MiPlaits.so / .dylib / .dll ...); false, with err, if MiPlaits is missing
    bool load(const std::string& libDir, std::string& err);
    void prepare(double sampleRate);

    void command(const Command& c);
    void render(float* left, float* right);  // one BLOCK, overwriting

    SpscQueue<Note, 64> notes;  // for the message thread's log

    class Synth;

private:
    double sr_ = 48000;
    std::map<std::string, std::unique_ptr<mi::Library>> libs_;

    // what the engine keeps, as Engine_Terrarium.js does: each slot's kind and every parameter sent
    std::string voiceKind_, colorKind_, airKind_, droneKind_;
    std::map<std::string, std::map<std::string, float>> voiceParams_;
    std::map<std::string, float> colorParams_, airParams_, droneParams_, tape_;

    std::vector<std::unique_ptr<Synth>> voices_;    // the playing voice slot (2 Plaits round robin)
    std::vector<std::unique_ptr<Synth>> fading_;    // synths fading out after a swap
    size_t nextVoice_ = 0;

    float voiceL_[BLOCK], voiceR_[BLOCK];

    void setVoice(const std::string& kind);
    void say(const std::string& s);
    mi::Library* lib(const char* name);
};

}  // namespace terrarium
