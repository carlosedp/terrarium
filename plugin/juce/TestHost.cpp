// terrarium_host_test: loads the built plugin the way a DAW does, plays it with the
// transport running, and checks it makes sound: the bundle found its Resources, booted
// the script, and its engine plays. (pluginval checks it behaves; this checks it plays.)
//
//   terrarium_host_test <terrarium.vst3 | terrarium.component> [seconds, default 20] [--visitors]
//
// --visitors: the soil set to visitors on MIDI port 1 (through the plugin's state, as a project
// would load it), a tone into its side chain, and checks the notes come out of its MIDI output.
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
    bool visitors = argc > 3 && juce::String(argv[3]) == "--visitors";
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
    std::printf("%s %s (%s), %d outputs, MIDI in: %s, MIDI out: %s\n", plugin->getName().toRawUTF8(),
                found[0]->version.toRawUTF8(), found[0]->pluginFormatName.toRawUTF8(), plugin->getTotalNumOutputChannels(),
                plugin->acceptsMidi() ? "yes" : "no", plugin->producesMidi() ? "yes" : "no");
    if (!plugin->acceptsMidi()) {
        std::fprintf(stderr, "FAIL: no MIDI input; Ableton Live won't load an instrument without one\n");
        return 1;
    }

    // visitors: the side chain on, and the soil switched in the saved params (a PSET, "id\tvalue")
    if (visitors) {
        auto layout = plugin->getBusesLayout();
        if (layout.inputBuses.size() < 2) {
            std::fprintf(stderr, "no side chain bus\n");
            return 1;
        }
        layout.inputBuses.getReference(1) = juce::AudioChannelSet::stereo();
        if (!plugin->setBusesLayout(layout)) {
            std::fprintf(stderr, "the host can't enable the side chain\n");
            return 1;
        }
        plugin->enableAllBuses();
        // A host sees a VST3's state as JUCE's wrapper keeps it: <VST3PluginState> with the
        // plugin's own blob (copyXmlToBinary of our <terrarium>) at the start of its base64
        // <IComponent>, JUCE's private data after it.
        juce::MemoryBlock st;
        plugin->getStateInformation(st);
        auto outer = juce::AudioProcessor::getXmlFromBinary(st.getData(), (int)st.getSize());
        auto* comp = outer ? outer->getChildByName("IComponent") : nullptr;
        juce::MemoryBlock data;
        if (!comp || !data.fromBase64Encoding(comp->getAllSubText())) {
            std::fprintf(stderr, "can't read the plugin's state\n");
            return 1;
        }
        auto ours = juce::AudioProcessor::getXmlFromBinary(data.getData(), (int)data.getSize());
        if (!ours) {
            std::fprintf(stderr, "no terrarium state in it\n");
            return 1;
        }
        size_t oursSize = 8 + (size_t)*reinterpret_cast<const juce::uint32*>(static_cast<const char*>(data.getData()) + 4);
        for (auto* e : ours->getChildWithTagNameIterator("store"))
            if (e->getStringAttribute("key") == "pset:daw") {
                juce::StringArray lines;
                lines.addLines(e->getAllSubText());
                for (auto& l : lines) {
                    if (l.startsWith("voice_kind\t")) l = "voice_kind\t4";
                    if (l.startsWith("visitors_midi\t")) l = "visitors_midi\t2";
                }
                e->deleteAllTextElements();
                e->addTextElement(lines.joinIntoString("\n"));
            }
        juce::MemoryBlock rebuilt;
        juce::AudioProcessor::copyXmlToBinary(*ours, rebuilt);
        if (oursSize < data.getSize())
            rebuilt.append(static_cast<const char*>(data.getData()) + oursSize, data.getSize() - oursSize);
        comp->deleteAllTextElements();
        comp->addTextElement(rebuilt.toBase64Encoding());
        juce::MemoryBlock changed;
        juce::AudioProcessor::copyXmlToBinary(*outer, changed);
        plugin->setStateInformation(changed.getData(), (int)changed.getSize());
        std::printf("visitors on MIDI port 1, a tone into the side chain (%d inputs)\n", plugin->getTotalNumInputChannels());
    }

    PlayHead head;
    head.sr = sr;
    plugin->setPlayHead(&head);
    plugin->setNonRealtime(false);
    plugin->prepareToPlay(sr, block);

    // realtime: process a block, then let the message loop run (the plugin's Lua ticks there)
    int channels = juce::jmax(2, plugin->getTotalNumInputChannels(), plugin->getTotalNumOutputChannels());
    juce::AudioBuffer<float> buf(channels, block);
    juce::MidiBuffer midi;
    int noteOns = 0;
    double sum = 0, peak = 0, firstSound = -1;
    auto total = (juce::int64)(seconds * sr);
    auto start = juce::Time::getMillisecondCounterHiRes();
    for (head.samples = 0; head.samples < total; head.samples += block) {
        buf.clear();
        midi.clear();
        if (visitors)  // the side chain: the input buses' last two channels
            for (int ch = channels - 2; ch < channels; ++ch)
                for (int i = 0; i < block; ++i)
                    buf.setSample(ch, i, 0.3f * (float)std::sin(2 * 3.14159265 * 220 * (double)(head.samples + i) / sr));
        plugin->processBlock(buf, midi);
        for (const auto m : midi)
            if (m.getMessage().isNoteOn()) ++noteOns;
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

    // the parameters, as a DAW lists them (the macros named after the modules playing)
    juce::StringArray names;
    for (auto* p : plugin->getParameters()) names.add(p->getName(64));
    std::printf("%d parameters: %s\n", names.size(), names.joinIntoString(" | ").toRawUTF8());
    if (names.size() > 40) {
        std::fprintf(stderr, "FAIL: %d parameters; the host's list should stay short\n", names.size());
        return 1;
    }

    // the state round trip a DAW does when it saves a project
    juce::MemoryBlock state;
    plugin->getStateInformation(state);
    plugin->setStateInformation(state.getData(), (int)state.getSize());

    double rms = std::sqrt(sum / (2.0 * (double)total));
    std::printf("%.0f s: rms %.4f, peak %.3f, first sound at %.2f s; state %zu bytes\n", seconds, rms, peak, firstSound,
                state.getSize());
    bool ok = rms > 1e-3 && peak < 1.0 && state.getSize() > 100;
    if (visitors) {
        std::printf("visitors: %d note-ons out of the plugin's MIDI output\n", noteOns);
        ok = ok && noteOns > 0;
    }
    std::printf("%s\n", ok ? "ok: it plays" : "FAIL: silent, clipping or no state");
    plugin.reset();
    return ok ? 0 : 1;
}
