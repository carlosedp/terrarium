// terrarium as a plugin: a thin JUCE layer over terrarium_core (core/Terrarium.h).
// The audio thread renders; a 60 Hz timer on the message thread ticks the script's Lua
// ahead of it; the host's tempo and position steer Lua's clock.
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include <mutex>

#include "Terrarium.h"

class TerrariumProcessor : public juce::AudioProcessor, private juce::Timer {
public:
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
    terrarium::Terrarium* core() { return core_.get(); }
    juce::String status();  // the boot error, or the last log line

private:
    std::unique_ptr<terrarium::Terrarium> core_;
    bool booted_ = false;
    std::mutex logMutex_;
    juce::String lastLog_, bootError_;

    void timerCallback() override;
    static juce::File resources();

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TerrariumProcessor)
};
