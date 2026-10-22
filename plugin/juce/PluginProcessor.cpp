#include "PluginProcessor.h"

#include "PluginEditor.h"

TerrariumProcessor::TerrariumProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    auto res = resources();
    core_ = std::make_unique<terrarium::Terrarium>(terrarium::Terrarium::Paths{
        res.getChildFile("norns-web/norns.lua").getFullPathName().toStdString(),
        res.getChildFile("terrarium").getFullPathName().toStdString(),
        res.getChildFile("mi-UGens").getFullPathName().toStdString(),
    });
    core_->onLog = [this](const std::string& s, bool error) {
        std::lock_guard<std::mutex> lock(logMutex_);
        lastLog_ = (error ? "error: " : "") + juce::String(s);
        DBG(lastLog_);
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

juce::String TerrariumProcessor::status() {
    if (!booted_) return "terrarium didn't start: " + bootError_;
    std::lock_guard<std::mutex> lock(logMutex_);
    return lastLog_;
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

// Lua, ahead of the audio (when rendering offline, process() ticks it itself)
void TerrariumProcessor::timerCallback() {
    if (booted_ && !isNonRealtime()) core_->tick();
}

// the state: what the script stored (the params as a PSET, via params:write) as XML
void TerrariumProcessor::getStateInformation(juce::MemoryBlock& dest) {
    if (!booted_) return;
    juce::XmlElement xml("terrarium");
    for (auto& [k, v] : core_->saveState()) {
        auto* e = xml.createNewChildElement("store");
        e->setAttribute("key", juce::String(k));
        e->addTextElement(juce::String(v));
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
}

juce::AudioProcessorEditor* TerrariumProcessor::createEditor() { return new TerrariumEditor(*this); }

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() { return new TerrariumProcessor(); }
