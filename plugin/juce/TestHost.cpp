// terrarium_host_test: loads the built plugin the way a DAW does, plays it with the
// transport running, and checks it makes sound: the bundle found its Resources, booted
// the script, and its engine plays. (pluginval checks it behaves; this checks it plays.)
//
//   terrarium_host_test <terrarium.vst3 | terrarium.component> [seconds, default 20]
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_events/juce_events.h>

#include <cmath>
#include <cstdio>

// a host's transport, playing at 120 BPM from beat 0
struct PlayHead : juce::AudioPlayHead {
    double sr = 48000, bpm = 120;
    juce::int64 samples = 0;
    juce::Optional<PositionInfo> getPosition() const override {
        PositionInfo p;
        p.setIsPlaying(true);
        p.setBpm(bpm);
        p.setTimeInSamples(samples);
        p.setPpqPosition((double)samples / sr * bpm / 60);
        return p;
    }
};

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: terrarium_host_test <plugin bundle> [seconds]\n");
        return 2;
    }
    juce::ScopedJuceInitialiser_GUI juce;  // the plugin's timer needs a message loop
    double seconds = argc > 2 ? std::atof(argv[2]) : 20;
    const double sr = 48000;
    const int block = 512;

    juce::AudioPluginFormatManager formats;
    formats.addDefaultFormats();
    juce::OwnedArray<juce::PluginDescription> found;
    for (auto* f : formats.getFormats())
        if (f->fileMightContainThisPluginType(argv[1])) f->findAllTypesForFile(found, argv[1]);
    if (found.isEmpty()) {
        std::fprintf(stderr, "no plugin found in %s\n", argv[1]);
        return 1;
    }
    juce::String err;
    auto plugin = formats.createPluginInstance(*found[0], sr, block, err);
    if (!plugin) {
        std::fprintf(stderr, "can't open it: %s\n", err.toRawUTF8());
        return 1;
    }
    std::printf("%s (%s), %d outputs\n", plugin->getName().toRawUTF8(), found[0]->pluginFormatName.toRawUTF8(),
                plugin->getTotalNumOutputChannels());

    PlayHead head;
    head.sr = sr;
    plugin->setPlayHead(&head);
    plugin->setNonRealtime(false);
    plugin->prepareToPlay(sr, block);

    // realtime: process a block, then let the message loop run (the plugin's Lua ticks there)
    juce::AudioBuffer<float> buf(2, block);
    juce::MidiBuffer midi;
    double sum = 0, peak = 0, firstSound = -1;
    auto total = (juce::int64)(seconds * sr);
    auto start = juce::Time::getMillisecondCounterHiRes();
    for (head.samples = 0; head.samples < total; head.samples += block) {
        buf.clear();
        plugin->processBlock(buf, midi);
        for (int ch = 0; ch < 2; ++ch)
            for (int i = 0; i < block; ++i) {
                float v = buf.getSample(ch, i);
                sum += (double)v * v;
                peak = std::max(peak, (double)std::fabs(v));
                if (firstSound < 0 && std::fabs(v) > 1e-3) firstSound = (double)(head.samples + i) / sr;
            }
        // keep to real time, so the timer ticks Lua as it would in a DAW
        double due = start + (double)(head.samples + block) / sr * 1000;
        while (juce::Time::getMillisecondCounterHiRes() < due)
            juce::MessageManager::getInstance()->runDispatchLoopUntil(1);
    }
    plugin->releaseResources();

    // the state round trip a DAW does when it saves a project
    juce::MemoryBlock state;
    plugin->getStateInformation(state);
    plugin->setStateInformation(state.getData(), (int)state.getSize());

    double rms = std::sqrt(sum / (2.0 * (double)total));
    std::printf("%.0f s: rms %.4f, peak %.3f, first sound at %.2f s; state %zu bytes\n", seconds, rms, peak, firstSound,
                state.getSize());
    bool ok = rms > 1e-3 && peak < 1.0 && state.getSize() > 100;
    std::printf("%s\n", ok ? "ok: it plays" : "FAIL: silent, clipping or no state");
    plugin.reset();
    return ok ? 0 : 1;
}
