// The engine: Engine_Terrarium.sc for the plugin, as Engine_Terrarium.js is for the browser.
// Each SynthDef is a Synth here, built from the native mi-UGens (norns-mi-UGens' native
// libraries, through mi_ugens.hpp) and the plain UGens in Ugens.h, running in 64-sample
// blocks as scsynth does. The .sc is the reference: same graphs, same lags, same routing.
//
//   voice (2x MiPlaits | MiRings | the input) -> voiceBus -> color (MiRings | MiRipples) -> colorBus
//     -> air (MiClouds | MiBeads | MiVerb) -> out
//   drone (2x MiPlaits | MiElements) -> colorBus: under the weather, into the air
//   tape: last, on the whole output, when on
//
// A module swap builds its synth on the message thread: prepareCommand() sees every command
// before it's queued, keeps a mirror of the slots' parameters, and attaches the new synth to
// the command; the audio thread swaps it in and fades the old one out, then hands it back
// (trash) to be freed on the message thread. The audio thread allocates nothing.
//
// Threads: load(), prepare() and prepareCommand(), emptyTrash() on the message thread (prepare
// with the audio stopped); command() and render() on the audio thread.
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
    using Params = std::map<std::string, float>;
    class Synth;
    class Tape;

    Engine();
    ~Engine();

    // the native mi-UGens in libDir (MiPlaits.so / .dylib / .dll ...); false, with err, if MiPlaits is missing
    bool load(const std::string& libDir, std::string& err);
    void prepare(double sampleRate);

    // message thread: before a command is queued (attaches a new synth to a module swap)
    void prepareCommand(Command& c);
    // message thread: frees what the audio thread is done with
    void emptyTrash();
    // message thread: a prepared command that won't be queued after all
    void discard(Command& c);

    // audio thread
    void command(const Command& c);
    void render(float* left, float* right, const float* inL = nullptr, const float* inR = nullptr);  // one BLOCK

    SpscQueue<Note, 64> notes;  // for the message thread's log

private:
    double sr_ = 48000;
    std::map<std::string, std::unique_ptr<mi::Library>> libs_;

    // what a slot is and every parameter it was sent, as the .sc keeps them: one copy for the
    // audio thread, one (the mirror) for the message thread, both moved by the same commands
    struct State {
        std::string voiceKind, colorKind, airKind, droneKind;
        std::map<std::string, Params> voiceParams;  // per voice kind
        Params colorParams, airParams, droneParams, tape;
        bool tapeOn = false;
        // applies c; returns the slot whose kind changed ("voice", "color", ... or "tape"), or ""
        std::string apply(const Command& c);
    };
    State audio_, mirror_;

    // the playing synths (audio thread)
    std::unique_ptr<Synth> voice_, color_, air_, drone_;
    std::unique_ptr<Tape> tape_;
    std::vector<std::unique_ptr<Synth>> fading_;
    std::vector<std::unique_ptr<Tape>> fadingTapes_;
    SpscQueue<void*, 64> trash_;      // finished synths, for the message thread to free
    SpscQueue<void*, 64> trashTape_;  // finished tapes

    float voiceL_[BLOCK], voiceR_[BLOCK], colorL_[BLOCK], colorR_[BLOCK];

    std::unique_ptr<Synth> build(const std::string& slot, const State& s);
    void swap(std::unique_ptr<Synth>& slot, Synth* next, int bus);
    void say(const std::string& s);
    mi::Library* lib(const char* name);
};

}  // namespace terrarium
