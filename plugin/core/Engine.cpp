#include "Engine.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace terrarium {

using mi::Rate;

// SC's Lag: reaches 60 dB of the way in t seconds; per-sample coefficient
static float lagCoef(double t, double sr) { return t > 0 ? (float)std::exp(std::log(0.001) / (t * sr)) : 0.0f; }

// ---------- a slot synth ----------
// Every synth has vol (its level, lagged 0.1 s), fades in over 0.05 s and, released, out over
// 0.3 s, as the engine's fade. Subclasses render one block into l/r.
class Engine::Synth {
public:
    explicit Synth(double sr) : sr_(sr), volCoef_(lagCoef(0.1, sr)), fadeIn_(1.0f / (0.05f * (float)sr)),
                                fadeOut_(1.0f / (0.3f * (float)sr)) {}
    virtual ~Synth() = default;

    void set(const std::string& k, float v) {
        if (k == "vol") volTarget_ = v;
        else setParam(k, v);
    }
    void release() { releasing_ = true; }
    bool done() const { return releasing_ && fade_ <= 0; }

    // adds this synth's block into outL/outR
    void renderInto(float* outL, float* outR) {
        process(l_, r_);
        for (int i = 0; i < BLOCK; ++i) {
            vol_ = volTarget_ + volCoef_ * (vol_ - volTarget_);
            fade_ = releasing_ ? std::max(0.0f, fade_ - fadeOut_) : std::min(1.0f, fade_ + fadeIn_);
            float g = vol_ * fade_;
            outL[i] += l_[i] * g;
            outR[i] += r_[i] * g;
        }
    }

protected:
    double sr_;
    virtual void setParam(const std::string& k, float v) = 0;
    virtual void process(float* l, float* r) = 0;

    // SC's Pan2: equal power
    static void pan2(float pan, float amp, float& gl, float& gr) {
        float a = (std::max(-1.0f, std::min(1.0f, pan)) + 1.0f) * 0.25f * 3.14159265f;
        gl = std::cos(a) * amp;
        gr = std::sin(a) * amp;
    }

private:
    float vol_ = 1, volTarget_ = 1, volCoef_, fade_ = 0, fadeIn_, fadeOut_;
    bool releasing_ = false;
    float l_[BLOCK], r_[BLOCK];
};

namespace {

using Params = std::map<std::string, float>;

float get(const Params& p, const char* k, float dflt) {
    auto it = p.find(k);
    return it == p.end() ? dflt : it->second;
}

// terrarium_voice_plaits: Plaits struck by t_trig, its LPG shaping each note;
// Pan2.ar(sig[0], pan, amp)
class PlaitsVoice : public Engine::Synth {
public:
    PlaitsVoice(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), pan_(get(p, "pan", 0)), amp_(get(p, "amp", 0.35f)),
          u_(lib, sr,
             {
                 {"pitch", get(p, "pitch", 60), Rate::Control},
                 {"engine", get(p, "engine", 12), Rate::Control},
                 {"harm", get(p, "harm", 0.5f), Rate::Control, 0.05f},
                 {"timbre", get(p, "timbre", 0.5f), Rate::Control, 0.05f},
                 {"morph", get(p, "morph", 0.5f), Rate::Control, 0.05f},
                 {"trigger", 0, Rate::Control},
                 {"level", get(p, "level", 0.8f), Rate::Control},
                 {"decay", get(p, "decay", 0.5f), Rate::Control},
                 {"lpg_colour", get(p, "lpg", 0.5f), Rate::Control},
             }) {}

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "t_trig") u_.trig("trigger", v);
        else if (k == "pan") pan_ = v;
        else if (k == "amp") amp_ = v;
        else if (k == "lpg") u_.set("lpg_colour", v);
        else u_.set(k, v);  // pitch, engine, harm, timbre, morph, level, decay: the same names
    }
    void process(float* l, float* r) override {
        float* outs[] = {o0_, o1_};
        u_.process(nullptr, nullptr, outs);
        float gl, gr;
        pan2(pan_, amp_, gl, gr);
        for (int i = 0; i < BLOCK; ++i) {
            l[i] = o0_[i] * gl;
            r[i] = o0_[i] * gr;
        }
    }

private:
    float pan_, amp_;
    mi::Unit u_;
    float o0_[BLOCK], o1_[BLOCK];
};

}  // namespace

// ---------- the engine ----------

Engine::Engine() = default;
Engine::~Engine() = default;

bool Engine::load(const std::string& libDir, std::string& err) {
    for (const char* name : {"MiPlaits", "MiRings", "MiRipples", "MiClouds", "MiBeads", "MiVerb", "MiElements"}) {
        auto l = std::make_unique<mi::Library>();
        std::string path = libDir + "/" + mi::libraryFile(name);
        if (l->open(path, name)) libs_[name] = std::move(l);
        else if (std::strcmp(name, "MiPlaits") == 0) {
            err = l->error;
            return false;
        }
    }
    return true;
}

mi::Library* Engine::lib(const char* name) {
    auto it = libs_.find(name);
    return it == libs_.end() ? nullptr : it->second.get();
}

void Engine::prepare(double sampleRate) {
    sr_ = sampleRate;
    voices_.clear();
    fading_.clear();
    setVoice(voiceKind_);
}

void Engine::say(const std::string& s) {
    Note n;
    std::strncpy(n.text, s.c_str(), sizeof(n.text) - 1);
    notes.push(n);
}

// two Plaits round robin; the old voices fade out
void Engine::setVoice(const std::string& kind) {
    for (auto& v : voices_) {
        v->release();
        fading_.push_back(std::move(v));
    }
    voices_.clear();
    nextVoice_ = 0;
    if (kind == "plaits") {
        if (auto* l = lib("MiPlaits")) {
            auto& p = voiceParams_[kind];
            for (int i = 0; i < 2; ++i) voices_.push_back(std::make_unique<PlaitsVoice>(*l, sr_, p));
        }
    } else if (!kind.empty() && kind != "none") {
        say("not in the plugin yet: voice " + kind);
    }
}

void Engine::command(const Command& c) {
    if (c.is("note")) {
        if (voices_.empty()) return;
        auto& v = voices_[nextVoice_];
        nextVoice_ = (nextVoice_ + 1) % voices_.size();
        v->set("pitch", (float)c.num(0, 60));
        v->set("level", 0.5f + 0.5f * (float)c.num(1, 0));
        v->set("pan", (float)c.num(2, 0));
        v->set("t_trig", 1);
    } else if (c.is("voice_kind")) {
        if (voiceKind_ == c.str(0)) return;
        voiceKind_ = c.str(0);
        setVoice(voiceKind_);
    } else if (c.is("voice_set")) {
        if (voiceKind_.empty() || voiceKind_ == "none") return;
        voiceParams_[voiceKind_][c.str(0)] = (float)c.num(1);
        for (auto& v : voices_) v->set(c.str(0), (float)c.num(1));
    } else if (c.is("color_kind") || c.is("air_kind") || c.is("drone_kind")) {
        std::string& kind = c.is("color_kind") ? colorKind_ : c.is("air_kind") ? airKind_ : droneKind_;
        if (kind == c.str(0)) return;
        kind = c.str(0);
        if (!kind.empty() && kind != "none") say(std::string("not in the plugin yet: ") + c.name + " " + kind);
    } else if (c.is("color_set")) {
        colorParams_[c.str(0)] = (float)c.num(1);
    } else if (c.is("air_set")) {
        airParams_[c.str(0)] = (float)c.num(1);
    } else if (c.is("drone_set")) {
        droneParams_[c.str(0)] = (float)c.num(1);
    } else if (c.is("tape_set")) {
        tape_[c.str(0)] = (float)c.num(1);
    } else {
        say(std::string("unknown engine command: ") + c.name);
    }
}

void Engine::render(float* left, float* right) {
    std::memset(voiceL_, 0, sizeof(voiceL_));
    std::memset(voiceR_, 0, sizeof(voiceR_));
    for (auto& v : voices_) v->renderInto(voiceL_, voiceR_);
    for (auto& v : fading_) v->renderInto(voiceL_, voiceR_);
    for (size_t i = 0; i < fading_.size();) {
        if (fading_[i]->done()) fading_.erase(fading_.begin() + (long)i);
        else ++i;
    }
    // no color, air or tape yet: the voice bus straight out
    for (int i = 0; i < BLOCK; ++i) {
        left[i] = voiceL_[i];
        right[i] = voiceR_[i];
    }
}

}  // namespace terrarium
