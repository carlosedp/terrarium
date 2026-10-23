#include "PluginProcessor.h"

#include <cmath>

#include "PluginEditor.h"

// A host automation slot: 0..1, named after the param it follows ("map 3: rain change")
class TerrariumProcessor::Slot : public juce::AudioParameterFloat {
public:
    explicit Slot(int n)
        : AudioParameterFloat(juce::ParameterID("map" + juce::String(n), 1), "map " + juce::String(n),
                              juce::NormalisableRange<float>(0, 1), 0),
          n_(n) {}

    juce::String getName(int maximumStringLength) const override {
        std::lock_guard<std::mutex> lock(m_);
        auto s = "map " + juce::String(n_) + (label_.isEmpty() ? "" : ": " + label_);
        return maximumStringLength > 0 ? s.substring(0, maximumStringLength) : s;
    }
    void setLabel(const juce::String& l) {
        std::lock_guard<std::mutex> lock(m_);
        label_ = l;
    }

private:
    int n_;
    mutable std::mutex m_;
    juce::String label_;
};

TerrariumProcessor::TerrariumProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    for (int k = 0; k < SLOTS; ++k) {
        slots_[(size_t)k] = new Slot(k + 1);
        addParameter(slots_[(size_t)k]);
    }
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
    return layouts.getMainOutputChannelSet() == juce::AudioChannelSet::stereo();
}

void TerrariumProcessor::prepareToPlay(double sampleRate, int) {
    if (booted_) core_->prepare(sampleRate);
}

void TerrariumProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) {
    juce::ScopedNoDenormals noDenormals;
    if (!booted_ || buffer.getNumChannels() < 2) {
        buffer.clear();
        return;
    }
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
    core_->process(buffer.getWritePointer(0), buffer.getWritePointer(1), buffer.getNumSamples(), host,
                   isNonRealtime());
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
    for (int k = 0; k < SLOTS; ++k)
        if (bound_[(size_t)k] == id) {
            bind(k, "");
            return 0;
        }
    for (int k = 0; k < SLOTS; ++k)
        if (bound_[(size_t)k].empty()) {
            bind(k, id);
            return k + 1;
        }
    return 0;
}

juce::var TerrariumProcessor::maps() {
    auto* o = new juce::DynamicObject();
    if (booted_)
        for (int k = 0; k < SLOTS; ++k)
            if (!bound_[(size_t)k].empty())
                o->setProperty(juce::String(core_->paramIndex(bound_[(size_t)k])), k + 1);
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
    for (int k = 0; k < SLOTS; ++k)
        if (!bound_[(size_t)k].empty()) {
            auto* e = xml.createNewChildElement("map");
            e->setAttribute("slot", k + 1);
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
    for (int k = 0; k < SLOTS; ++k) bind(k, "");
    for (auto* e : xml->getChildWithTagNameIterator("map")) {
        int k = e->getIntAttribute("slot") - 1;
        if (k >= 0 && k < SLOTS) bind(k, e->getStringAttribute("param").toStdString());
    }
}

juce::AudioProcessorEditor* TerrariumProcessor::createEditor() { return new TerrariumEditor(*this); }

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new TerrariumProcessor(); }
