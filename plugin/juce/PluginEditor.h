// The plugin's face: norns-web's page, the same one the browser shows, in a WebView. The page
// sees it's hosted (window.__JUCE__) and runs no Lua or sound of its own: it calls the
// plugin instead.
//
//   page -> plugin   enc(n, d), key(n, z), params(), param_delta(i or id, d), repl(code),
//                    pset(action, slot), param_map(i), param_maps(), set_extra_width(px)
//   plugin -> page   "frame": the screen, 128x64 letters "A".."P"; "log": { text, kind }
//
// The page and its files are served from the bundle's Resources/web/ (stage.cmake puts
// them there, with a files.json carrying norns-web.json's text), so the plugin's face is
// whatever norns-web is.
#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_extra/juce_gui_extra.h>

#include "PluginProcessor.h"

class TerrariumEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
    explicit TerrariumEditor(TerrariumProcessor&);
    ~TerrariumEditor() override;

    void paint(juce::Graphics&) override;
    void resized() override;

private:
    TerrariumProcessor& proc_;
    juce::File web_;
    std::unique_ptr<juce::WebBrowserComponent> view_;
    unsigned char last_[128 * 64] = {};
    size_t logSeen_ = 0;
    int extra_ = 0;  // how much wider the open drawer made the window

    void timerCallback() override;
    std::optional<juce::WebBrowserComponent::Resource> resource(const juce::String& url);
    juce::WebBrowserComponent::Options options();
    void setExtraWidth(int px);
};
