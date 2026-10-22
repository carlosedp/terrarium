#include "PluginEditor.h"

namespace {
const juce::Colour NIGHT(0xff121513);
constexpr int W = 700, H = 760;

juce::String mimeType(const juce::String& path) {
    static const std::pair<const char*, const char*> types[] = {
        {".html", "text/html"}, {".js", "text/javascript"}, {".css", "text/css"},
        {".json", "application/json"}, {".svg", "image/svg+xml"}, {".png", "image/png"},
        {".woff2", "font/woff2"}, {".lua", "text/plain"}};
    for (auto& [ext, type] : types)
        if (path.endsWithIgnoreCase(ext)) return type;
    return "application/octet-stream";
}

using Args = const juce::Array<juce::var>&;
using Done = juce::WebBrowserComponent::NativeFunctionCompletion;
int argInt(Args a, int i) { return a.size() > i ? (int)a[i] : 0; }
}  // namespace

TerrariumEditor::TerrariumEditor(TerrariumProcessor& p) : AudioProcessorEditor(&p), proc_(p) {
    auto bin = juce::File::getSpecialLocation(juce::File::currentExecutableFile).getParentDirectory();
    for (auto dir : {bin.getSiblingFile("Resources").getChildFile("web"), bin.getChildFile("terrarium-resources/web")})
        if (dir.getChildFile("index.html").existsAsFile()) web_ = dir;

    view_ = std::make_unique<juce::WebBrowserComponent>(options());
    addAndMakeVisible(*view_);
    setResizable(true, true);
    setResizeLimits(480, 520, 2400, 2400);
    setSize(W, H);
    view_->goToURL(juce::WebBrowserComponent::getResourceProviderRoot());
    startTimerHz(30);
}

TerrariumEditor::~TerrariumEditor() { stopTimer(); }

juce::WebBrowserComponent::Options TerrariumEditor::options() {
    using Options = juce::WebBrowserComponent::Options;
    auto core = [this] { return proc_.core(); };
    return Options{}
        .withBackend(Options::Backend::webview2)
        // WebView2 misbehaves when it can't write its default data folder, which is what
        // happens inside a host's process: name one (as AlloyFlux's plugin does)
        .withWinWebView2Options(Options::WinWebView2{}
                                    .withUserDataFolder(juce::File::getSpecialLocation(juce::File::tempDirectory)
                                                            .getChildFile("terrarium-webview"))
                                    .withBackgroundColour(NIGHT))
        .withResourceProvider([this](const juce::String& url) { return resource(url); })
        .withNativeIntegrationEnabled()
        .withNativeFunction("enc",
                            [core](Args a, Done done) {
                                if (auto* c = core()) c->enc(argInt(a, 0), argInt(a, 1));
                                done(true);
                            })
        .withNativeFunction("key",
                            [core](Args a, Done done) {
                                if (auto* c = core()) c->key(argInt(a, 0), argInt(a, 1));
                                done(true);
                            })
        .withNativeFunction("params",
                            [core](Args, Done done) {
                                auto* c = core();
                                done(juce::String(c ? c->paramsJson() : "[]"));
                            })
        .withNativeFunction("param_delta",
                            [core](Args a, Done done) {
                                if (auto* c = core(); c && a.size() >= 2) {
                                    if (a[0].isString()) c->paramDelta(a[0].toString().toStdString(), (double)a[1]);
                                    else c->paramDelta((int)a[0], (double)a[1]);
                                }
                                done(true);
                            })
        .withNativeFunction("repl",
                            [core](Args a, Done done) {
                                if (auto* c = core(); c && a.size() > 0) c->repl(a[0].toString().toStdString());
                                done(true);
                            })
        .withNativeFunction("pset",
                            [core](Args a, Done done) {
                                if (auto* c = core(); c && a.size() >= 2)
                                    c->pset(a[0].toString().toStdString(), a[1].toString().toStdString());
                                done(true);
                            })
        .withNativeFunction("param_map", [this](Args a, Done done) { done(proc_.toggleMap(argInt(a, 0))); })
        .withNativeFunction("param_maps", [this](Args, Done done) { done(proc_.maps()); })
        // the drawer opens below the device: the window grows by it, rather than covering it
        .withNativeFunction("set_extra_height", [this](Args a, Done done) {
            setExtraHeight(argInt(a, 0));
            done(true);
        });
}

// the page's files, from Resources/web/ (and nothing outside it)
std::optional<juce::WebBrowserComponent::Resource> TerrariumEditor::resource(const juce::String& url) {
    auto path = url.upToFirstOccurrenceOf("?", false, false).upToFirstOccurrenceOf("#", false, false);
    while (path.startsWithChar('/')) path = path.substring(1);
    if (path.isEmpty()) path = "index.html";
    if (path.contains("..") || !web_.isDirectory()) return std::nullopt;
    auto f = web_.getChildFile(path);
    juce::MemoryBlock data;
    if (!f.existsAsFile() || !f.loadFileAsData(data)) return std::nullopt;
    auto* bytes = static_cast<const std::byte*>(data.getData());
    return juce::WebBrowserComponent::Resource{std::vector<std::byte>(bytes, bytes + data.getSize()), mimeType(path)};
}

// the screen when it changes, and the log's new lines
void TerrariumEditor::timerCallback() {
    auto* core = proc_.core();
    if (!core || !view_) return;
    unsigned char fb[128 * 64];
    core->copyFrame(fb);
    if (std::memcmp(fb, last_, sizeof(fb)) != 0) {
        std::memcpy(last_, fb, sizeof(fb));
        std::string s(sizeof(fb), 'A');
        for (size_t i = 0; i < sizeof(fb); ++i) s[i] = (char)('A' + (fb[i] & 15));
        view_->emitEventIfBrowserIsVisible("frame", juce::String(s));
    }
    for (auto& line : proc_.logSince(logSeen_)) {
        auto* o = new juce::DynamicObject();
        o->setProperty("text", line.text);
        o->setProperty("kind", line.error ? "error" : "print");
        view_->emitEventIfBrowserIsVisible("log", juce::var(o));
    }
}

void TerrariumEditor::paint(juce::Graphics& g) {
    g.fillAll(NIGHT);
    if (!web_.isDirectory() || !proc_.core()) {
        g.setColour(juce::Colour(0xffe3e6e1));
        g.drawText(proc_.core() ? "can't find the plugin's web folder" : "terrarium didn't start: " + proc_.bootError(),
                   getLocalBounds(), juce::Justification::centred);
    }
}

void TerrariumEditor::resized() {
    if (view_) view_->setBounds(getLocalBounds());
    // with the drawer shut, a resize by hand is the new natural height
    if (extra_ == 0) baseHeight_ = getHeight();
}

void TerrariumEditor::setExtraHeight(int px) {
    px = juce::jmax(0, px);
    if (px == extra_) return;
    extra_ = px;
    setSize(getWidth(), baseHeight_ + extra_);
}
