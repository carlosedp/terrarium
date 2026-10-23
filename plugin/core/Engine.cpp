#include "Engine.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>

#include "Ugens.h"

namespace terrarium {

using mi::Rate;
using Params = Engine::Params;
namespace u = ugen;

namespace {

float get(const Params& p, const char* k, float dflt) {
    auto it = p.find(k);
    return it == p.end() ? dflt : it->second;
}

float clip01(float v) { return std::max(0.0f, std::min(1.0f, v)); }

// SC's Pan2: equal power
void pan2(float pan, float amp, float& gl, float& gr) {
    float a = (std::max(-1.0f, std::min(1.0f, pan)) + 1.0f) * 0.25f * (float)u::PI;
    gl = std::cos(a) * amp;
    gr = std::sin(a) * amp;
}

}  // namespace

// ---------- a slot synth ----------
// Every slot synth has vol (its level from PARAMS, lagged 0.1 s) and the engine's fade:
// Env.asr(0.05, 1, 0.3), in when it starts, out once released, then it's done.
class Engine::Synth {
public:
    explicit Synth(double sr) : sr_(sr), kr_(sr / BLOCK), fadeIn_(1.0f / (0.05f * (float)sr)), fadeOut_(1.0f / (0.3f * (float)sr)) {
        vol_.time(0.1, kr_);
    }
    virtual ~Synth() = default;

    void set(const std::string& k, float v) {
        if (k == "vol") volTarget_ = v;
        else setParam(k, v);
    }
    virtual void note(float /*pitch*/, float /*accent*/, float /*pan*/) {}
    void release() { releasing_ = true; }
    bool done() const { return releasing_ && fade_ <= 0; }

    enum Bus { VOICE, COLOR, AIR, DRONE };
    Bus bus = VOICE;  // its slot: which bus it hears and feeds, also while it fades out

    // adds one block of this synth into outL/outR; in: what it hears (its bus), or null
    void renderInto(const float* inL, const float* inR, float* outL, float* outR) {
        process(inL ? inL : zero_, inR ? inR : zero_, l_, r_);
        float vol = vol_(volTarget_);
        for (int i = 0; i < BLOCK; ++i) {
            fade_ = releasing_ ? std::max(0.0f, fade_ - fadeOut_) : std::min(1.0f, fade_ + fadeIn_);
            float g = vol * fade_;
            outL[i] += l_[i] * g;
            outR[i] += r_[i] * g;
        }
    }

protected:
    double sr_, kr_;  // samples and blocks a second
    virtual void setParam(const std::string& k, float v) = 0;
    virtual void process(const float* inL, const float* inR, float* l, float* r) = 0;

private:
    u::Lag vol_;
    float volTarget_ = 1, fade_ = 0, fadeIn_, fadeOut_;
    bool releasing_ = false;
    float l_[BLOCK], r_[BLOCK];
    static constexpr float zero_[BLOCK] = {};
};

namespace {

using Synth = Engine::Synth;

// ---------- voices ----------

// terrarium_voice_plaits, twice, round robin: Plaits struck by t_trig, its LPG shaping each
// note; Pan2.ar(sig[0], pan, amp)
class PlaitsVoice : public Synth {
public:
    PlaitsVoice(mi::Library& lib, double sr, const Params& p) : Synth(sr), amp_(get(p, "amp", 0.35f)) {
        for (auto& v : v_) {
            v.pan = get(p, "pan", 0);
            v.u = std::make_unique<mi::Unit>(lib, sr, std::vector<mi::Spec>{
                {"pitch", get(p, "pitch", 60), Rate::Control},
                {"engine", get(p, "engine", 12), Rate::Control},
                {"harm", get(p, "harm", 0.5f), Rate::Control, 0.05f},
                {"timbre", get(p, "timbre", 0.5f), Rate::Control, 0.05f},
                {"morph", get(p, "morph", 0.5f), Rate::Control, 0.05f},
                {"trigger", 0, Rate::Control},
                {"level", get(p, "level", 0.8f), Rate::Control},
                {"decay", get(p, "decay", 0.5f), Rate::Control},
                {"lpg_colour", get(p, "lpg", 0.5f), Rate::Control},
            });
        }
    }
    void note(float pitch, float accent, float pan) override {
        auto& v = v_[next_];
        next_ = (next_ + 1) % 2;
        v.u->set("pitch", pitch);
        v.u->set("level", 0.5f + 0.5f * accent);
        v.pan = pan;
        v.u->trig("trigger");
    }

protected:
    void setParam(const std::string& k, float v) override {
        for (auto& x : v_) {
            if (k == "t_trig") x.u->trig("trigger", v);
            else if (k == "pan") x.pan = v;
            else if (k == "lpg") x.u->set("lpg_colour", v);
            else x.u->set(k, v);  // pitch, engine, harm, timbre, morph, level, decay
        }
        if (k == "amp") amp_ = v;
    }
    void process(const float*, const float*, float* l, float* r) override {
        std::fill(l, l + BLOCK, 0.0f);
        std::fill(r, r + BLOCK, 0.0f);
        for (auto& v : v_) {
            float* outs[] = {o0_, o1_};
            v.u->process(nullptr, nullptr, outs);
            float gl, gr;
            pan2(v.pan, amp_, gl, gr);
            for (int i = 0; i < BLOCK; ++i) {
                l[i] += o0_[i] * gl;
                r[i] += o0_[i] * gr;
            }
        }
    }

private:
    struct V {
        std::unique_ptr<mi::Unit> u;
        float pan = 0;
    } v_[2];
    size_t next_ = 0;
    float amp_;
    float o0_[BLOCK], o1_[BLOCK];
};

// terrarium_voice_rings: the internal exciter strikes the resonator on each note; two voices
// of polyphony inside Rings, so notes ring over each other
class RingsVoice : public Synth {
public:
    RingsVoice(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), amp_(get(p, "amp", 0.5f)),
          u_(lib, sr,
             {
                 {"trig", 0, Rate::Control},
                 {"pit", get(p, "pitch", 60), Rate::Control},
                 {"struct", get(p, "struct", 0.4f), Rate::Control, 0.05f},
                 {"bright", get(p, "bright", 0.5f), Rate::Control, 0.05f},
                 {"damp", get(p, "damp", 0.6f), Rate::Control, 0.05f},
                 {"pos", get(p, "pos", 0.3f), Rate::Control},
                 {"model", get(p, "model", 0), Rate::Control},
                 {"poly", 2},
                 {"intern_exciter", 1},
             }) {}
    void note(float pitch, float, float) override {
        u_.set("pit", pitch);
        u_.trig("trig");
    }

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "t_trig") u_.trig("trig", v);
        else if (k == "pitch") u_.set("pit", v);
        else if (k == "amp") amp_ = v;
        else u_.set(k, v);  // struct, bright, damp, pos, model
    }
    void process(const float*, const float*, float* l, float* r) override {
        float* outs[] = {l, r};
        u_.process(nullptr, nullptr, outs);
        for (int i = 0; i < BLOCK; ++i) {
            l[i] *= amp_;
            r[i] *= amp_;
        }
    }

private:
    float amp_;
    mi::Unit u_;
};

// terrarium_voice_input (visitors): the audio input as a voice. Each note opens it for len
// seconds (Env.perc(0.01, len, 1, -2) * level); open lets some through between notes.
class InputVoice : public Synth {
public:
    InputVoice(double sr, const Params& p)
        : Synth(sr), level_(get(p, "level", 0.8f)), open_(get(p, "open", 0.04f)), len_(get(p, "len", 0.3f)),
          amp_(get(p, "amp", 1)) {
        openLag_.time(0.1, kr_);
    }
    void note(float, float accent, float) override {
        level_ = 0.5f + 0.5f * accent;
        trig_ = true;
    }

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "level") level_ = v;
        else if (k == "open") open_ = v;
        else if (k == "len") len_ = v;
        else if (k == "amp") amp_ = v;
        else if (k == "t_trig") trig_ = v > 0;
    }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        float env = perc_(trig_, 0.01, std::max(0.01f, len_), -2, 1 / kr_) * level_;
        trig_ = false;
        float g = std::max(openLag_(open_), env) * amp_;
        for (int i = 0; i < BLOCK; ++i) {
            l[i] = inL[i] * g;
            r[i] = inR[i] * g;
        }
    }

private:
    float level_, open_, len_, amp_;
    bool trig_ = false;
    u::Lag openLag_;
    u::Perc perc_;
};

// ---------- color ----------

// terrarium_pond: the voice excites Rings; more structure, more resonator in the mix
class Pond : public Synth {
public:
    Pond(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), struct_(get(p, "struct", 0.4f)), mix_(get(p, "mix", 0.8f)),
          u_(lib, sr,
             {
                 {"in", 0, Rate::Audio},
                 {"trig", 0, Rate::Control},
                 {"pit", get(p, "pitch", 60), Rate::Control},
                 {"struct", get(p, "struct", 0.4f), Rate::Control, 0.1f},
                 {"bright", get(p, "bright", 0.5f), Rate::Control, 0.1f},
                 {"damp", get(p, "damp", 0.6f), Rate::Control, 0.1f},
                 {"pos", get(p, "pos", 0.3f), Rate::Control},
                 {"model", get(p, "model", 0), Rate::Control},
                 {"poly", 2},
             }) {}
    void note(float pitch, float, float) override {
        u_.set("pit", pitch);
        u_.trig("trig");
    }

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "t_trig") u_.trig("trig", v);
        else if (k == "pitch") u_.set("pit", v);
        else if (k == "mix") mix_ = v;
        else {
            if (k == "struct") struct_ = v;
            u_.set(k, v);  // struct, bright, damp, pos, model
        }
    }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        for (int i = 0; i < BLOCK; ++i) mono_[i] = (inL[i] + inR[i]) * 0.5f;  // dry.sum * 0.5
        const float* ins[] = {mono_};
        float* outs[] = {wl_, wr_};
        u_.process(ins, nullptr, outs);
        float dry = 1 - 0.5f * struct_;
        for (int i = 0; i < BLOCK; ++i) {
            l[i] = inL[i] * dry + wl_[i] * mix_;
            r[i] = inR[i] * dry + wr_[i] * mix_;
        }
    }

private:
    float struct_, mix_;
    mi::Unit u_;
    float mono_[BLOCK], wl_[BLOCK], wr_[BLOCK];
};

// terrarium_fog: a Ripples per channel
class Fog : public Synth {
public:
    Fog(mi::Library& lib, double sr, const Params& p) : Synth(sr) {
        for (auto& x : u_)
            x = std::make_unique<mi::Unit>(lib, sr, std::vector<mi::Spec>{
                {"in", 0, Rate::Audio},
                {"cf", get(p, "cf", 0.5f), Rate::Control, 0.1f},
                {"reson", get(p, "reson", 0.2f), Rate::Control, 0.1f},
                {"drive", get(p, "drive", 1), Rate::Control, 0.1f},
            });
    }

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "cf" || k == "reson" || k == "drive")
            for (auto& x : u_) x->set(k, v);
    }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        const float* il[] = {inL};
        const float* ir[] = {inR};
        float* ol[] = {l};
        float* orr[] = {r};
        u_[0]->process(il, nullptr, ol);
        u_[1]->process(ir, nullptr, orr);
    }

private:
    std::unique_ptr<mi::Unit> u_[2];
};

// ---------- air ----------

// terrarium_clouds: grain position drifts on a 20 s triangle (LFTri.kr(0.05).range(0.3, 0.7))
// so the clouds move, and the pitch jitters by LFNoise1.kr(0.4) * pit_jitter
class Clouds : public Synth {
public:
    Clouds(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), jitter_(get(p, "pit_jitter", 0)), noise_(u::seedFrom(this, 1)), drift_(0.05, kr_),
          u_(lib, sr,
             {
                 {"pit", 0, Rate::Control, 0, 0},
                 {"pos", 0.5f, Rate::Control, 0, 1},
                 {"size", get(p, "size", 0.4f), Rate::Control, 0.1f},
                 {"dens", get(p, "dens", 0.5f), Rate::Control, 0.1f},
                 {"tex", get(p, "tex", 0.5f), Rate::Control, 0.1f},
                 {"drywet", get(p, "drywet", 0.45f), Rate::Control},
                 {"in_gain", 1},
                 {"spread", get(p, "spread", 0.7f), Rate::Control},
                 {"rvb", get(p, "rvb", 0.3f), Rate::Control},
                 {"fb", get(p, "fb", 0.2f), Rate::Control, 0.1f},
                 {"freeze", get(p, "freeze", 0), Rate::Control},
                 {"mode", get(p, "mode", 0), Rate::Control},
                 {"lofi", get(p, "lofi", 0), Rate::Control},
             }) {}

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "pit_jitter") jitter_ = v;
        else if (k != "pit" && k != "pos") u_.set(k, v);
    }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        m0_[0] = noise_(0.4, kr_) * jitter_;
        m1_[0] = drift_() * 0.2f;
        const float* mods[] = {m0_, m1_};
        const float* ins[] = {inL, inR};
        float* outs[] = {l, r};
        u_.process(ins, mods, outs);
    }

private:
    float jitter_;
    u::LFNoise1 noise_;
    u::LFTri drift_;
    mi::Unit u_;
    float m0_[BLOCK] = {}, m1_[BLOCK] = {};
};

// terrarium_fireflies: seed is never passed (any input there counts as patched and stops
// density from generating grains on its own)
class Fireflies : public Synth {
public:
    Fireflies(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), u_(lib, sr,
                        {
                            {"pitch", get(p, "pitch", 0), Rate::Control},
                            {"pitch_rnd", get(p, "pitch_rnd", 0.08f), Rate::Control},
                            {"time", get(p, "time", 0.5f), Rate::Control, 0.1f},
                            {"time_rnd", get(p, "time_rnd", 0.2f), Rate::Control},
                            {"size", get(p, "size", 0.5f), Rate::Control, 0.1f},
                            {"shape", get(p, "shape", 0.6f), Rate::Control},
                            {"density", get(p, "density", 0.7f), Rate::Control, 0.1f},
                            {"fb", get(p, "fb", 0.2f), Rate::Control, 0.1f},
                            {"drywet", get(p, "drywet", 0.5f), Rate::Control},
                            {"rvb", get(p, "rvb", 0.35f), Rate::Control},
                            {"freeze", get(p, "freeze", 0), Rate::Control},
                            {"seed_btn", 2},
                            {"quality", 0},
                            {"in_gain", 1},
                        }) {}

protected:
    void setParam(const std::string& k, float v) override {
        if (k != "seed" && k != "seed_btn" && k != "quality" && k != "in_gain") u_.set(k, v);
    }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        const float* ins[] = {inL, inR};
        float* outs[] = {l, r};
        u_.process(ins, nullptr, outs);
    }

private:
    mi::Unit u_;
};

// terrarium_mountains: MiVerb
class Mountains : public Synth {
public:
    Mountains(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), u_(lib, sr,
                        {
                            {"time", get(p, "time", 0.7f), Rate::Control, 0.1f},
                            {"drywet", get(p, "drywet", 0.4f), Rate::Control, 0.1f},
                            {"damp", get(p, "damp", 0.5f), Rate::Control, 0.1f},
                            {"hp", get(p, "hp", 0.05f), Rate::Control},
                            {"freeze", get(p, "freeze", 0), Rate::Control},
                            {"diff", get(p, "diff", 0.7f), Rate::Control},
                        }) {}

protected:
    void setParam(const std::string& k, float v) override { u_.set(k, v); }
    void process(const float* inL, const float* inR, float* l, float* r) override {
        const float* ins[] = {inL, inR};
        float* outs[] = {l, r};
        u_.process(ins, nullptr, outs);
    }

private:
    mi::Unit u_;
};

// ---------- drone ----------

// the drones' pitch lands on its first value, then glides (4 s) when the key turns:
// Lag.kr(pitch, EnvGen.kr(Env([0, 0, 4], [0.5, 0])))
struct Glide {
    u::Lag lag;
    double t = 0;
    float operator()(float pitch, double kr) {
        lag.time(t < 0.5 ? 0 : 4, kr);
        t += 1 / kr;
        return lag(pitch);
    }
};

// terrarium_aurora: a constant (scalar) trigger and level leave Plaits unpatched, so its LPG
// stays open and it sounds on. Root and fifth, each drifting on its own slow LFO; each voice
// swells on its own slow cycle; duck and lift come from the weather; hush glides it out.
class Aurora : public Synth {
public:
    Aurora(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), pitch_(get(p, "pitch", 48)), fifth_(get(p, "fifth", 7)), timbre_(get(p, "timbre", 0.4f)),
          morph_(get(p, "morph", 0.5f)), wobble_(get(p, "wobble", 0.1f)), amp_(get(p, "amp", 0.25f)),
          hush_(get(p, "hush", 1)), duck_(get(p, "duck", 0)), lift_(get(p, "lift", 0)), t0_(0.05, kr_), t1_(0.063, kr_),
          s0_(0.071, kr_, 0), s1_(0.053, kr_, 2), root_(plaits(lib, sr, p, pitch_)), top_(plaits(lib, sr, p, pitch_ + fifth_)) {
        liftLag_.time(0.3, kr_);
        duckLag_.time(0.4, kr_);
        hushLag_.time(3, kr_);
    }

protected:
    void setParam(const std::string& k, float v) override {
        if (k == "pitch") pitch_ = v;
        else if (k == "fifth") fifth_ = v;
        else if (k == "timbre") timbre_ = v;
        else if (k == "morph") morph_ = v;
        else if (k == "wobble") wobble_ = v;
        else if (k == "amp") amp_ = v;
        else if (k == "hush") hush_ = v;
        else if (k == "duck") duck_ = v;
        else if (k == "lift") lift_ = v;
        else if (k == "engine" || k == "harm") {
            root_->set(k, v);
            top_->set(k, v);
        }
    }
    void process(const float*, const float*, float* l, float* r) override {
        float lift = liftLag_(lift_) * 0.25f;
        float lfo0 = t0_() * wobble_ + lift, lfo1 = t1_() * wobble_ + lift;
        root_->set("pitch", rootGlide_(pitch_, kr_));
        top_->set("pitch", topGlide_(pitch_ + fifth_, kr_));
        root_->set("timbre", clip01(timbre_ + lfo0));
        root_->set("morph", clip01(morph_ + lfo1));
        top_->set("timbre", clip01(timbre_ + lfo1));
        top_->set("morph", clip01(morph_ - lfo0));
        float sw0 = 1 + s0_() * 0.15f, sw1 = 1 + s1_() * 0.15f;
        float g = amp_ * (1 - duckLag_(duck_) * 0.5f) * hushLag_(hush_);
        float* ro[] = {a0_, a1_};
        float* to[] = {b0_, b1_};
        root_->process(nullptr, nullptr, ro);
        top_->process(nullptr, nullptr, to);
        float rl, rr, tl, tr;
        pan2(-0.4f, 1, rl, rr);
        pan2(0.4f, 1, tl, tr);
        for (int i = 0; i < BLOCK; ++i) {
            float a = a0_[i] * sw0, b = b0_[i] * sw1 * 0.8f;
            l[i] = (a * rl + b * tl) * g;
            r[i] = (a * rr + b * tr) * g;
        }
    }

private:
    float pitch_, fifth_, timbre_, morph_, wobble_, amp_, hush_, duck_, lift_;
    u::LFTri t0_, t1_, s0_, s1_;
    u::Lag liftLag_, duckLag_, hushLag_;
    Glide rootGlide_, topGlide_;
    std::unique_ptr<mi::Unit> root_, top_;
    float a0_[BLOCK], a1_[BLOCK], b0_[BLOCK], b1_[BLOCK];

    static std::unique_ptr<mi::Unit> plaits(mi::Library& lib, double sr, const Params& p, float pitch) {
        return std::make_unique<mi::Unit>(lib, sr, std::vector<mi::Spec>{
            {"pitch", pitch, Rate::Control},
            {"engine", get(p, "engine", 22), Rate::Control},
            {"harm", get(p, "harm", 0.45f), Rate::Control, 0.2f},
            {"timbre", get(p, "timbre", 0.4f), Rate::Control},
            {"morph", get(p, "morph", 0.5f), Rate::Control},
            {"trigger", 0},
            {"level", 0},
        });
    }
};

// terrarium_roots: Elements with its gate held open, bowed and blown for as long as it runs
class Roots : public Synth {
public:
    Roots(mi::Library& lib, double sr, const Params& p)
        : Synth(sr), pitch_(get(p, "pitch", 48)), bright_(get(p, "bright", 0.4f)), lift_(get(p, "lift", 0)),
          amp_(get(p, "amp", 0.3f)), hush_(get(p, "hush", 1)), duck_(get(p, "duck", 0)),
          u_(lib, sr,
             {
                 {"gate", 1},
                 {"pit", pitch_, Rate::Control},
                 {"strength", get(p, "strength", 0.6f), Rate::Control},
                 {"contour", get(p, "contour", 0.8f), Rate::Control},
                 {"bow_level", get(p, "bow", 0.6f), Rate::Control, 0.2f},
                 {"blow_level", get(p, "blow", 0.2f), Rate::Control, 0.2f},
                 {"flow", get(p, "flow", 0.5f), Rate::Control, 0.2f},
                 {"geom", get(p, "geom", 0.3f), Rate::Control, 0.2f},
                 {"bright", clip01(bright_ + lift_ * 0.3f), Rate::Control},
                 {"damp", get(p, "damp", 0.7f), Rate::Control},
                 {"pos", 0.2f},
                 {"space", get(p, "space", 0.5f), Rate::Control, 0.2f},
                 {"model", get(p, "model", 1), Rate::Control},
             }) {
        brightLag_.time(0.3, kr_);
        duckLag_.time(0.4, kr_);
        hushLag_.time(3, kr_);
    }

protected:
    void setParam(const std::string& k, float v) override {
        static const std::map<std::string, const char*> keys = {
            {"strength", "strength"}, {"contour", "contour"}, {"bow", "bow_level"}, {"blow", "blow_level"},
            {"flow", "flow"},         {"geom", "geom"},       {"damp", "damp"},     {"space", "space"},
            {"model", "model"}};
        if (k == "pitch") pitch_ = v;
        else if (k == "bright") bright_ = v;
        else if (k == "lift") lift_ = v;
        else if (k == "amp") amp_ = v;
        else if (k == "hush") hush_ = v;
        else if (k == "duck") duck_ = v;
        else if (auto it = keys.find(k); it != keys.end()) u_.set(it->second, v);
    }
    void process(const float*, const float*, float* l, float* r) override {
        u_.set("pit", glide_(pitch_, kr_));
        u_.set("bright", clip01(brightLag_(bright_ + lift_ * 0.3f)));  // (bright + lift * 0.3).lag(0.3).clip(0, 1)
        float* outs[] = {l, r};
        u_.process(nullptr, nullptr, outs);
        float g = amp_ * (1 - duckLag_(duck_) * 0.5f) * hushLag_(hush_);
        for (int i = 0; i < BLOCK; ++i) {
            l[i] *= g;
            r[i] *= g;
        }
    }

private:
    float pitch_, bright_, lift_, amp_, hush_, duck_;
    mi::Unit u_;
    u::Lag brightLag_, duckLag_, hushLag_;
    Glide glide_;
};

}  // namespace

// ---------- the tape ----------
// terrarium_tape: on the whole output, after the air. Wow (a slow wandering drift) and flutter
// (a fast fine wobble) modulate a short delay; sparse crackle and a soft hiss are mixed in; tone
// rolls off the top, drive warms it. It fades in over a second (Env.asr(1, 1, 1)) and, released,
// back to the dry output, then it's done.
class Engine::Tape {
public:
    Tape(double sr, const Params& p)
        : sr_(sr), kr_(sr / BLOCK), wowRate_(u::seedFrom(this, 2)), wow_(u::seedFrom(this, 3)),
          flutterRate_(u::seedFrom(this, 4)), dust_{u::Dust(u::seedFrom(this, 5)), u::Dust(u::seedFrom(this, 6))},
          decay_{u::Decay2(0.0003, 0.004, sr), u::Decay2(0.0003, 0.004, sr)}, popLp_{u::Butter(false), u::Butter(false)},
          hissHp_{u::Butter(true), u::Butter(true)}, toneLp_{u::Butter(false), u::Butter(false)},
          pink_{u::PinkNoise(u::seedFrom(this, 7)), u::PinkNoise(u::seedFrom(this, 8))}, white_(u::seedFrom(this, 9)),
          delay_{u::DelayC(0.03, sr), u::DelayC(0.03, sr)} {
        for (auto* k : {"wow", "flutter", "crackle", "hiss", "tone", "drive"}) {
            lags_[k].time(1, kr_);
            target_[k] = get(p, k, 0);
        }
        for (auto& f : popLp_) f.freq(7000, sr);
        for (auto& f : hissHp_) f.freq(2500, sr);
    }
    void set(const std::string& k, float v) {
        if (target_.count(k)) target_[k] = v;
    }
    void release() { releasing_ = true; }
    bool done() const { return releasing_ && env_ <= 0; }

    // in place, on the output
    void process(float* l, float* r) {
        auto lag = [&](const char* k) { return lags_[k](target_[k]); };
        float wow = lag("wow"), flutter = lag("flutter"), crackle = lag("crackle"), hiss = lag("hiss"),
              tone = lag("tone"), drive = lag("drive");
        // Env.asr(1, 1, 1): curve -4, a second each way
        pos_ = std::max(0.0, std::min(1.0, pos_ + (releasing_ ? -1 : 1) / kr_));
        env_ = releasing_ ? u::envCurve(0, 1, (float)pos_, 4) : u::envCurve(0, 1, (float)pos_, -4);
        float mod = wow_(0.5 + (wowRate_(0.1, kr_) + 1) * 0.2, kr_) * wow * 0.003f +
                    flutterOsc_(6.3 + flutterRate_(0.4, kr_), kr_) * flutter * 0.0003f;
        double delay = (0.01 + mod) * sr_;
        for (auto& f : toneLp_) f.freq(19000 - tone * 12000, sr_);
        float k = 1 + drive * 2;
        float* ch[] = {l, r};
        const float rates[] = {8, 10};
        for (int c = 0; c < 2; ++c) {
            float* x = ch[c];
            for (int i = 0; i < BLOCK; ++i) {
                float dry = x[i];
                float wet = delay_[c](dry, delay);
                float pop = decay_[c](dust_[c](crackle * rates[c], sr_)) * popLp_[c](white_.bi() * 0.6f);
                float noise = hissHp_[c](pink_[c]() * 0.012f * hiss);
                wet = toneLp_[c](wet);
                wet = std::tanh(wet * k) / k;  // unity for quiet signals
                x[i] = dry * (1 - env_) + (wet + pop * crackle * 0.5f + noise) * env_;
            }
        }
    }

private:
    double sr_, kr_, pos_ = 0;
    float env_ = 0;
    bool releasing_ = false;
    std::map<std::string, u::Lag> lags_;
    std::map<std::string, float> target_;
    u::LFNoise1 wowRate_;
    u::LFNoise2 wow_;
    u::LFNoise1 flutterRate_;
    u::SinOsc flutterOsc_;
    u::Dust dust_[2];
    u::Decay2 decay_[2];
    u::Butter popLp_[2], hissHp_[2], toneLp_[2];
    u::PinkNoise pink_[2];
    u::Rng white_;
    u::DelayC delay_[2];
};

// ---------- the engine ----------

Engine::Engine() {
    fading_.reserve(32);  // the audio thread never grows them
    fadingTapes_.reserve(8);
}

Engine::~Engine() {
    emptyTrash();
}

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

void Engine::say(const std::string& s) {
    Note n;
    std::strncpy(n.text, s.c_str(), sizeof(n.text) - 1);
    notes.push(n);
}

std::string Engine::State::apply(const Command& c) {
    auto kind = [&](std::string& k, const char* slot) -> std::string {
        if (k == c.str(0)) return "";
        k = c.str(0);
        return slot;
    };
    if (c.is("voice_kind")) return kind(voiceKind, "voice");
    if (c.is("color_kind")) return kind(colorKind, "color");
    if (c.is("air_kind")) return kind(airKind, "air");
    if (c.is("drone_kind")) return kind(droneKind, "drone");
    if (c.is("voice_set")) {
        if (!voiceKind.empty() && voiceKind != "none") voiceParams[voiceKind][c.str(0)] = (float)c.num(1);
    } else if (c.is("color_set")) colorParams[c.str(0)] = (float)c.num(1);
    else if (c.is("air_set")) airParams[c.str(0)] = (float)c.num(1);
    else if (c.is("drone_set")) droneParams[c.str(0)] = (float)c.num(1);
    else if (c.is("tape_set")) {
        if (std::strcmp(c.str(0), "on") == 0) {
            bool on = c.num(1) > 0;
            if (on == tapeOn) return "";
            tapeOn = on;
            return "tape";
        }
        tape[c.str(0)] = (float)c.num(1);
    }
    return "";
}

// a slot's synth for the kind and parameters in s (null for none, or a kind it doesn't have)
std::unique_ptr<Engine::Synth> Engine::build(const std::string& slot, const State& s) {
    auto need = [&](const char* name) { return lib(name); };
    auto params = [](const std::map<std::string, Params>& m, const std::string& k) {
        auto it = m.find(k);
        return it == m.end() ? Params{} : it->second;
    };
    if (slot == "voice") {
        const auto& k = s.voiceKind;
        auto p = params(s.voiceParams, k);
        if (k == "plaits" && need("MiPlaits")) return std::make_unique<PlaitsVoice>(*lib("MiPlaits"), sr_, p);
        if (k == "rings" && need("MiRings")) return std::make_unique<RingsVoice>(*lib("MiRings"), sr_, p);
        if (k == "input") return std::make_unique<InputVoice>(sr_, p);
    } else if (slot == "color") {
        const auto& k = s.colorKind;
        if (k == "pond" && need("MiRings")) return std::make_unique<Pond>(*lib("MiRings"), sr_, s.colorParams);
        if (k == "fog" && need("MiRipples")) return std::make_unique<Fog>(*lib("MiRipples"), sr_, s.colorParams);
    } else if (slot == "air") {
        const auto& k = s.airKind;
        if (k == "clouds" && need("MiClouds")) return std::make_unique<Clouds>(*lib("MiClouds"), sr_, s.airParams);
        if (k == "fireflies" && need("MiBeads")) return std::make_unique<Fireflies>(*lib("MiBeads"), sr_, s.airParams);
        if (k == "mountains" && need("MiVerb")) return std::make_unique<Mountains>(*lib("MiVerb"), sr_, s.airParams);
    } else if (slot == "drone") {
        const auto& k = s.droneKind;
        if (k == "aurora" && need("MiPlaits")) return std::make_unique<Aurora>(*lib("MiPlaits"), sr_, s.droneParams);
        if (k == "roots" && need("MiElements")) return std::make_unique<Roots>(*lib("MiElements"), sr_, s.droneParams);
    }
    return nullptr;
}

void Engine::prepareCommand(Command& c) {
    std::string slot = mirror_.apply(c);
    if (slot.empty()) return;
    if (slot == "tape") {
        if (mirror_.tapeOn) c.synth = new Tape(sr_, mirror_.tape);
        return;
    }
    c.synth = build(slot, mirror_).release();
}

// with the audio stopped: every slot rebuilt at this rate, from what the audio side has been sent
void Engine::prepare(double sampleRate) {
    sr_ = sampleRate;
    fading_.clear();
    fadingTapes_.clear();
    emptyTrash();
    voice_.reset();
    color_.reset();
    air_.reset();
    drone_.reset();
    swap(voice_, build("voice", audio_).release(), Synth::VOICE);
    swap(color_, build("color", audio_).release(), Synth::COLOR);
    swap(air_, build("air", audio_).release(), Synth::AIR);
    swap(drone_, build("drone", audio_).release(), Synth::DRONE);
    tape_ = audio_.tapeOn ? std::make_unique<Tape>(sr_, audio_.tape) : nullptr;
}

void Engine::discard(Command& c) {
    if (!c.synth) return;
    if (c.is("tape_set")) delete static_cast<Tape*>(c.synth);
    else delete static_cast<Synth*>(c.synth);
    c.synth = nullptr;
}

void Engine::emptyTrash() {
    void* p;
    while (trash_.pop(p)) delete static_cast<Synth*>(p);
    while (trashTape_.pop(p)) delete static_cast<Tape*>(p);
}

void Engine::swap(std::unique_ptr<Synth>& slot, Synth* next, int bus) {
    if (slot) {
        slot->release();
        if (fading_.size() < fading_.capacity()) fading_.push_back(std::move(slot));
        else if (Synth* s = slot.release(); !trash_.push(s)) delete s;  // a pile-up of swaps: cut it short
    }
    slot.reset(next);
    if (next) next->bus = (Synth::Bus)bus;
}

void Engine::command(const Command& c) {
    std::string slot = audio_.apply(c);
    if (c.is("note")) {
        float pitch = (float)c.num(0, 60), accent = (float)c.num(1, 0), pan = (float)c.num(2, 0);
        if (voice_) voice_->note(pitch, accent, pan);
        if (color_ && audio_.colorKind == "pond") color_->note(pitch, 0, 0);
        return;
    }
    if (slot == "voice") return swap(voice_, static_cast<Synth*>(c.synth), Synth::VOICE);
    if (slot == "color") return swap(color_, static_cast<Synth*>(c.synth), Synth::COLOR);
    if (slot == "air") return swap(air_, static_cast<Synth*>(c.synth), Synth::AIR);
    if (slot == "drone") return swap(drone_, static_cast<Synth*>(c.synth), Synth::DRONE);
    if (slot == "tape") {
        if (tape_) {
            tape_->release();
            if (fadingTapes_.size() < fadingTapes_.capacity()) fadingTapes_.push_back(std::move(tape_));
            else if (Tape* t = tape_.release(); !trashTape_.push(t)) delete t;
        }
        tape_.reset(static_cast<Tape*>(c.synth));
        return;
    }
    if (c.synth) {  // can't happen (both sides see the same commands), but never leak one
        if (!trash_.push(c.synth)) delete static_cast<Synth*>(c.synth);
    }
    if (c.is("voice_set") && voice_) voice_->set(c.str(0), (float)c.num(1));
    else if (c.is("color_set") && color_) color_->set(c.str(0), (float)c.num(1));
    else if (c.is("air_set") && air_) air_->set(c.str(0), (float)c.num(1));
    else if (c.is("drone_set") && drone_) drone_->set(c.str(0), (float)c.num(1));
    else if (c.is("tape_set") && tape_) tape_->set(c.str(0), (float)c.num(1));
    else if (!c.is("voice_set") && !c.is("color_set") && !c.is("air_set") && !c.is("drone_set") && !c.is("tape_set") &&
             !c.is("voice_kind") && !c.is("color_kind") && !c.is("air_kind") && !c.is("drone_kind"))
        say(std::string("unknown engine command: ") + c.name);
}

void Engine::render(float* left, float* right, const float* inL, const float* inR) {
    std::memset(voiceL_, 0, sizeof(voiceL_));
    std::memset(voiceR_, 0, sizeof(voiceR_));
    std::memset(colorL_, 0, sizeof(colorL_));
    std::memset(colorR_, 0, sizeof(colorR_));
    std::memset(left, 0, BLOCK * sizeof(float));
    std::memset(right, 0, BLOCK * sizeof(float));

    // a fading synth keeps playing where it was, on its slot's buses
    // voice -> voiceBus (the input voice hears the plugin's input)
    if (voice_) voice_->renderInto(inL, inR, voiceL_, voiceR_);
    for (auto& f : fading_)
        if (f->bus == Synth::VOICE) f->renderInto(inL, inR, voiceL_, voiceR_);
    // color: voiceBus -> colorBus; drone -> colorBus
    if (color_) color_->renderInto(voiceL_, voiceR_, colorL_, colorR_);
    if (drone_) drone_->renderInto(nullptr, nullptr, colorL_, colorR_);
    for (auto& f : fading_) {
        if (f->bus == Synth::COLOR) f->renderInto(voiceL_, voiceR_, colorL_, colorR_);
        if (f->bus == Synth::DRONE) f->renderInto(nullptr, nullptr, colorL_, colorR_);
    }
    // air: colorBus -> out (no air, no sound: as the .sc, where the air synth writes the output)
    if (air_) air_->renderInto(colorL_, colorR_, left, right);
    for (auto& f : fading_)
        if (f->bus == Synth::AIR) f->renderInto(colorL_, colorR_, left, right);
    // tape, in place on the output
    if (tape_) tape_->process(left, right);
    for (auto& t : fadingTapes_) t->process(left, right);

    // what's done fading goes back to the message thread to be freed
    for (size_t i = 0; i < fading_.size();) {
        if (fading_[i]->done()) {
            Synth* s = fading_[i].release();
            if (!trash_.push(s)) delete s;
            fading_.erase(fading_.begin() + (long)i);
        } else ++i;
    }
    for (size_t i = 0; i < fadingTapes_.size();) {
        if (fadingTapes_[i]->done()) {
            Tape* t = fadingTapes_[i].release();
            if (!trashTape_.push(t)) delete t;
            fadingTapes_.erase(fadingTapes_.begin() + (long)i);
        } else ++i;
    }
}

}  // namespace terrarium
