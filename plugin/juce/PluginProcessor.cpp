#include "PluginProcessor.h"

#include <cmath>

#include "PluginEditor.h"

// A host automation slot: 0..1, named after the param it follows ("weather 1: rain rate",
// "map 3: key")
class TerrariumProcessor::Slot : public juce::AudioParameterFloat {
public:
    Slot(const juce::String& id, const juce::String& title)
        : AudioParameterFloat(juce::ParameterID(id, 1), title, juce::NormalisableRange<float>(0, 1), 0), base_(title) {}

    juce::String getName(int maximumStringLength) const override {
        std::lock_guard<std::mutex> lock(m_);
        auto s = base_ + (label_.isEmpty() ? "" : ": " + label_);
        return maximumStringLength > 0 ? s.substring(0, maximumStringLength) : s;
    }
    void setLabel(const juce::String& l) {
        std::lock_guard<std::mutex> lock(m_);
        label_ = l;
    }

private:
    juce::String base_;
    mutable std::mutex m_;
    juce::String label_;
};

// The buses: the stereo output; a main input nobody needs (off), so that the visitors' input is a
// side chain (an aux bus), which is how Logic, Reason and Live offer an instrument's input.
TerrariumProcessor::TerrariumProcessor()
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), false)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
                         .withInput("Visitors", juce::AudioChannelSet::stereo(), false)) {
    for (int k = 0; k < SLOTS; ++k) {
        juce::String id, name;
        if (k < MACROS) {
            juce::String part = terrarium::Terrarium::partName(k / 2 + 1), n(k % 2 + 1);
            id = "macro_" + part + "_" + n;
            name = part + " " + n;
        } else {
            id = "map" + juce::String(k - MACROS + 1);
            name = "map " + juce::String(k - MACROS + 1);
        }
        slots_[(size_t)k] = new Slot(id, name);
        addParameter(slots_[(size_t)k]);
    }
    // off: the weather goes on when the host's transport stops, as a norns' does
    stopWithTransport = new juce::AudioParameterBool(juce::ParameterID("stop_with_transport", 1),
                                                     "stop with the DAW's transport", false);
    addParameter(stopWithTransport);
    auto res = resources();
    core_ = std::make_unique<terrarium::Terrarium>(terrarium::Terrarium::Paths{
        res.getChildFile("norns-web/norns.lua").getFullPathName().toStdString(),
        res.getChildFile("terrarium").getFullPathName().toStdString(),
        res.getChildFile("mi-UGens").getFullPathName().toStdString(),
    });
    core_->onLog = [this](const std::string& s, bool error) {
        std::lock_guard<std::mutex> lock(logMutex_);
        log_.push_back({juce::String::fromUTF8(s.c_str()), error});
        if (log_.size() > 300) log_.erase(log_.begin());
        ++logCount_;
    };
    // visitors' MIDI ports, for Lua's midi.vports: the DAW's MIDI out, then the system's outputs
    std::vector<std::string> ports{"DAW (plugin MIDI out)"};
    midiDevices_ = juce::MidiOutput::getAvailableDevices();
    for (auto& d : midiDevices_)
        if (ports.size() < 16) ports.push_back(d.name.toStdString());
    core_->setMidiPorts(ports, 1);
    core_->onMidiDevice = [this](const terrarium::MidiEvent& e, double delay) { sendToDevice(e, delay); };
    std::string err;
    booted_ = res.isDirectory() && core_->boot(err);
    if (!booted_) bootError_ = res.isDirectory() ? juce::String(err) : "can't find the plugin's Resources folder";
    startTimerHz(60);
}

TerrariumProcessor::~TerrariumProcessor() { stopTimer(); }

// Resources/ next to the binary: Contents/Resources in a VST3, AU or .app bundle, or
// terrarium-resources/ beside a standalone on Linux and Windows
juce::File TerrariumProcessor::resources() {
    auto bin = juce::File::getSpecialLocation(juce::File::currentExecutableFile);
    for (auto dir : {bin.getParentDirectory().getSiblingFile("Resources"),
                     bin.getParentDirectory().getChildFile("terrarium-resources")})
        if (dir.getChildFile("terrarium/terrarium.lua").existsAsFile()) return dir;
    return {};
}

std::vector<TerrariumProcessor::LogLine> TerrariumProcessor::logSince(size_t& seen) {
    std::lock_guard<std::mutex> lock(logMutex_);
    size_t missed = logCount_ - seen, have = log_.size();
    size_t from = missed >= have ? 0 : have - missed;
    seen = logCount_;
    return {log_.begin() + (long)from, log_.end()};
}

bool TerrariumProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const {
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo()) return false;
    for (auto& in : layouts.inputBuses)  // each input: off, mono or stereo
        if (!in.isDisabled() && in != juce::AudioChannelSet::mono() && in != juce::AudioChannelSet::stereo()) return false;
    return true;
}

void TerrariumProcessor::prepareToPlay(double sampleRate, int samplesPerBlock) {
    input_.setSize(2, juce::jmax(1, samplesPerBlock));
    if (booted_) core_->prepare(sampleRate);
}

// a message for one of the system's MIDI outputs, sent when it's due (Lua runs a little ahead)
void TerrariumProcessor::sendToDevice(const terrarium::MidiEvent& e, double delay) {
    int index = e.port - 2;  // port 2 is the first device
    if (index < 0 || index >= midiDevices_.size()) return;
    auto& out = openMidi_[e.port];
    if (!out) {
        out = juce::MidiOutput::openDevice(midiDevices_[index].identifier);
        if (!out) {
            if (core_->onLog)
                core_->onLog("can't open MIDI output " + midiDevices_[index].name.toStdString() +
                                 " (another program may have it)",
                             true);
            return;
        }
        out->startBackgroundThread();
    }
    juce::MidiBuffer b;
    b.addEvent(juce::MidiMessage(e.bytes, e.size), 0);
    out->sendBlockOfMessages(b, juce::Time::getMillisecondCounterHiRes() + (isNonRealtime() ? 0 : delay * 1000), 1000);
}

void TerrariumProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi) {
    juce::ScopedNoDenormals noDenormals;
    midi.clear();
    int n = buffer.getNumSamples();
    // the visitors' input (the side chain), if the host sends one, copied before the output is written
    const float* inL = nullptr;
    const float* inR = nullptr;
    if (getBusCount(true) > 1 && getBus(true, 1)->isEnabled() && n <= input_.getNumSamples()) {
        auto side = getBusBuffer(buffer, true, 1);
        if (side.getNumChannels() > 0) {
            input_.copyFrom(0, 0, side, 0, 0, n);
            input_.copyFrom(1, 0, side, juce::jmin(1, side.getNumChannels() - 1), 0, n);
            inL = input_.getReadPointer(0);
            inR = input_.getReadPointer(1);
        }
    }
    auto out = getBusBuffer(buffer, false, 0);
    if (!booted_ || out.getNumChannels() < 2) {
        buffer.clear();
        return;
    }
    core_->setStopWithTransport(stopWithTransport->get());
    terrarium::HostTime host;
    if (auto* ph = getPlayHead()) {
        if (auto pos = ph->getPosition()) {
            host.valid = true;
            host.playing = pos->getIsPlaying();
            if (auto bpm = pos->getBpm()) host.bpm = *bpm;
            if (auto ppq = pos->getPpqPosition()) host.ppq = *ppq;
            else host.playing = false;  // no position, nothing to follow
        }
    }
    core_->process(out.getWritePointer(0), out.getWritePointer(1), n, host, isNonRealtime(), inL, inR, &midiOut_);
    for (int i = 0; i < midiOut_.count; ++i) {
        auto& e = midiOut_.events[i];
        midi.addEvent(juce::MidiMessage(e.bytes, e.size), e.offset);
    }
    for (int ch = 2; ch < buffer.getNumChannels(); ++ch) buffer.clear(ch, 0, n);  // nothing on the inputs' channels
}

// Lua, ahead of the audio (when rendering offline, process() ticks it itself), then the slots
void TerrariumProcessor::timerCallback() {
    if (!booted_) return;
    if (!isNonRealtime()) core_->tick();
    syncSlots();
}

// ---------- automation slots ----------

// Each bound slot follows its param and the param follows it. The host moved the slot: the
// param takes the value. Otherwise, if the param changed in the plugin (the face, an encoder,
// the script), the slot takes it. Comparing each side with its own last value, not the two
// with each other, keeps a stepped param (an option) from fighting an automation lane.
void TerrariumProcessor::syncSlots() {
    // the macros follow whatever module lives in each part now
    for (int k = 0; k < MACROS; ++k) {
        auto id = core_->macroParam(k / 2 + 1, k % 2 + 1);
        if (id != bound_[(size_t)k]) bind(k, id);
    }
    for (size_t k = 0; k < SLOTS; ++k) {
        if (bound_[k].empty()) continue;
        float hv = slots_[k]->get();
        double lv = 0;
        if (!juce::exactlyEqual(hv, lastHost_[k])) {  // any move by the host, however small
            core_->setNorm(bound_[k], hv);
            lastHost_[k] = hv;
            if (core_->getNorm(bound_[k], lv)) lastLua_[k] = (float)lv;
        } else if (core_->getNorm(bound_[k], lv) && std::fabs((float)lv - lastLua_[k]) > 1e-5f) {
            lastLua_[k] = (float)lv;
            slots_[k]->beginChangeGesture();
            slots_[k]->setValueNotifyingHost((float)lv);
            slots_[k]->endChangeGesture();
            lastHost_[k] = slots_[k]->get();
        }
    }
}

void TerrariumProcessor::bind(int slot, const std::string& id) {
    auto k = (size_t)slot;
    bound_[k] = id;
    slots_[k]->setLabel(id.empty() ? "" : juce::String(core_->paramName(id)));
    if (!id.empty()) {
        double lv = 0;
        core_->getNorm(id, lv);
        lastLua_[k] = (float)lv;
        slots_[k]->setValueNotifyingHost((float)lv);  // the slot starts where the param is
        lastHost_[k] = slots_[k]->get();
    }
    updateHostDisplay(ChangeDetails().withParameterInfoChanged(true));
}

int TerrariumProcessor::toggleMap(int paramIndex) {
    if (!booted_) return 0;
    auto id = core_->paramId(paramIndex);
    if (id.empty()) return 0;
    for (int k = MACROS; k < SLOTS; ++k)
        if (bound_[(size_t)k] == id) {
            bind(k, "");
            return 0;
        }
    for (int k = MACROS; k < SLOTS; ++k)
        if (bound_[(size_t)k].empty()) {
            bind(k, id);
            return k - MACROS + 1;
        }
    return 0;
}

juce::var TerrariumProcessor::maps() {
    auto* o = new juce::DynamicObject();
    if (booted_)
        for (int k = MACROS; k < SLOTS; ++k)
            if (!bound_[(size_t)k].empty())
                o->setProperty(juce::String(core_->paramIndex(bound_[(size_t)k])), k - MACROS + 1);
    return juce::var(o);
}

// ---------- state ----------
// what the script stored (the params as a PSET, via params:write), and the slots' bindings

void TerrariumProcessor::getStateInformation(juce::MemoryBlock& dest) {
    if (!booted_) return;
    juce::XmlElement xml("terrarium");
    for (auto& [k, v] : core_->saveState()) {
        auto* e = xml.createNewChildElement("store");
        e->setAttribute("key", juce::String(k));
        e->addTextElement(juce::String(v));
    }
    for (auto& [k, v] : uiPrefs) {
        auto* e = xml.createNewChildElement("pref");
        e->setAttribute("key", juce::String(k));
        e->addTextElement(juce::String(v));
    }
    xml.setAttribute("stop_with_transport", stopWithTransport->get());
    for (int k = MACROS; k < SLOTS; ++k)
        if (!bound_[(size_t)k].empty()) {
            auto* e = xml.createNewChildElement("map");
            e->setAttribute("slot", k - MACROS + 1);
            e->setAttribute("param", juce::String(bound_[(size_t)k]));
        }
    copyXmlToBinary(xml, dest);
}

void TerrariumProcessor::setStateInformation(const void* data, int size) {
    if (!booted_) return;
    auto xml = getXmlFromBinary(data, size);
    if (!xml || !xml->hasTagName("terrarium")) return;
    std::map<std::string, std::string> s;
    for (auto* e : xml->getChildWithTagNameIterator("store"))
        s[e->getStringAttribute("key").toStdString()] = e->getAllSubText().toStdString();
    core_->loadState(s);
    uiPrefs.clear();
    for (auto* e : xml->getChildWithTagNameIterator("pref"))
        uiPrefs[e->getStringAttribute("key").toStdString()] = e->getAllSubText().toStdString();
    *stopWithTransport = xml->getBoolAttribute("stop_with_transport", stopWithTransport->get());
    for (int k = MACROS; k < SLOTS; ++k) bind(k, "");
    for (auto* e : xml->getChildWithTagNameIterator("map")) {
        int k = MACROS + e->getIntAttribute("slot") - 1;
        if (k >= MACROS && k < SLOTS) bind(k, e->getStringAttribute("param").toStdString());
    }
}

juce::AudioProcessorEditor* TerrariumProcessor::createEditor() { return new TerrariumEditor(*this); }

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new TerrariumProcessor(); }
