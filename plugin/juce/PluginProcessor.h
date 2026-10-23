// terrarium as a plugin: a thin JUCE layer over terrarium_core (core/Terrarium.h).
// The audio thread renders; a 60 Hz timer on the message thread ticks the script's Lua
// ahead of it; the host's tempo and position steer Lua's clock.
//
// Host automation, kept small so a DAW's list stays readable:
//   10 macros, "weather 1" .. "hum 2": the two macros of whatever module lives in each part,
//      renamed as it changes ("weather 1: rain rate");
//   8 "map" slots: the face's drawer binds any of terrarium's PARAMS to one ("map 3: key");
//   "stop with the DAW's transport".
// A slot and its param follow each other: the host moves the slot, the param follows; the
// param changes in the plugin, the slot follows. The map bindings are saved with the project.
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include <array>
#include <map>
#include <mutex>
#include <vector>

#include "Terrarium.h"

class TerrariumProcessor : public juce::AudioProcessor, private juce::Timer {
public:
    static constexpr int MACROS = 10, MAPS = 8, SLOTS = MACROS + MAPS;  // macros first, then maps

    TerrariumProcessor();
    ~TerrariumProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    using AudioProcessor::processBlock;  // the double version: JUCE converts

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "terrarium"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}

    void getStateInformation(juce::MemoryBlock& dest) override;
    void setStateInformation(const void* data, int size) override;

    // for the editor (message thread)
    terrarium::Terrarium* core() { return booted_ ? core_.get() : nullptr; }
    juce::String bootError() const { return bootError_; }

    // the log, kept for whenever the face is open: lines after `seen`, and the new count
    struct LogLine {
        juce::String text;
        bool error;
    };
    std::vector<LogLine> logSince(size_t& seen);

    // the face's own settings (its look, the drawer), kept with the project
    std::map<std::string, std::string> uiPrefs;
    // "stop with the DAW's transport": no weather while the host's transport is stopped
    juce::AudioParameterBool* stopWithTransport = nullptr;

    // automation slots: bind a param (by index) to a free slot, or free it; 0 if none was free
    int toggleMap(int paramIndex);
    juce::var maps();  // { paramIndex: slot } for the face

private:
    class Slot;
    std::unique_ptr<terrarium::Terrarium> core_;
    bool booted_ = false;
    juce::String bootError_;

    std::mutex logMutex_;
    std::vector<LogLine> log_;  // the last 300 lines
    size_t logCount_ = 0;       // lines ever

    std::array<Slot*, SLOTS> slots_{};
    std::array<std::string, SLOTS> bound_;          // the param id each slot follows ("" for none)
    std::array<float, SLOTS> lastHost_{}, lastLua_{};  // the last values seen on each side

    void timerCallback() override;
    void syncSlots();
    void bind(int slot, const std::string& id);
    static juce::File resources();

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TerrariumProcessor)
};
