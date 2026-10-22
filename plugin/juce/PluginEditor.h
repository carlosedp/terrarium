// The plugin's face, for now: the screen and the norns' encoders and keys, drawn natively.
// (Phase 4 puts norns-web's page here, with the automation drawer.)
//
// Mouse: drag an encoder up and down or scroll on it; press and hold a key. Keyboard, as in
// norns-web: A S D are K1 K2 K3 (held while held), Y/H, U/J, I/K turn E1, E2, E3.
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include "PluginProcessor.h"

class TerrariumEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
    explicit TerrariumEditor(TerrariumProcessor&);
    ~TerrariumEditor() override;

    void paint(juce::Graphics&) override;
    void resized() override;
    void mouseDown(const juce::MouseEvent&) override;
    void mouseDrag(const juce::MouseEvent&) override;
    void mouseUp(const juce::MouseEvent&) override;
    void mouseWheelMove(const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
    bool keyPressed(const juce::KeyPress&) override;
    bool keyStateChanged(bool isKeyDown) override;

private:
    TerrariumProcessor& proc_;
    juce::Image screen_{juce::Image::RGB, 128, 64, true};
    juce::Rectangle<int> screenArea_;
    juce::Rectangle<float> encs_[3], keys_[3];
    float angle_[3] = {};
    int heldKey_ = 0, dragEnc_ = 0;
    float dragAcc_ = 0, wheelAcc_ = 0, lastDragY_ = 0;
    bool keyDown_[3] = {};  // A S D

    void timerCallback() override;
    void turn(int n, int d);
    void press(int n, int z);
};
