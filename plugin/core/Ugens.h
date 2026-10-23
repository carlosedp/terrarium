// The plain SuperCollider UGens the engine's SynthDefs use beside the mi-UGens, small and
// close enough to scsynth's: control-rate ones advance once a 64-sample block (.kr), audio
// ones a sample at a time (.ar). Each matches its SC namesake's range and timing.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace terrarium::ugen {

constexpr double PI = 3.14159265358979323846;

// a small, fast random generator per UGen (no shared state between threads)
struct Rng {
    uint32_t s;
    explicit Rng(uint32_t seed = 0x9e3779b9u) : s(seed ? seed : 1) {}
    uint32_t next() {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    }
    float uni() { return (float)(next() >> 8) / 16777216.0f; }  // 0..1
    float bi() { return uni() * 2 - 1; }                         // -1..1
};

inline uint32_t seedFrom(const void* p, uint32_t salt) {
    auto v = (uint64_t)(uintptr_t)p ^ ((uint64_t)salt * 0x9e3779b97f4a7c15ull);
    return (uint32_t)(v ^ (v >> 29)) | 1;
}

// Lag: one pole, 60 dB of the way in t seconds, stepped at rate (samples or blocks a second)
struct Lag {
    float y = 0, coef = 0;
    bool primed = false;
    void time(double t, double rate) { coef = t > 0 ? (float)std::exp(std::log(0.001) / (t * rate)) : 0.0f; }
    float operator()(float x) {
        if (!primed) {
            y = x;
            primed = true;
        }
        return y = x + coef * (y - x);
    }
};

// LFTri: a triangle, -1..1, starting at iphase (0..4: 0 rising through 0, 2 half a cycle on)
struct LFTri {
    double phase, inc;
    LFTri(double freq, double rate, double iphase = 0) : phase(std::fmod(iphase + 1, 4.0)), inc(4 * freq / rate) {}
    float operator()() {
        double p = phase;
        phase = std::fmod(phase + inc, 4.0);
        return (float)(p < 2 ? p - 1 : 3 - p);
    }
};

// SinOsc at a (changing) frequency
struct SinOsc {
    double phase = 0;
    float operator()(double freq, double rate) {
        float y = (float)std::sin(phase);
        phase = std::fmod(phase + 2 * PI * freq / rate, 2 * PI);
        return y;
    }
};

// LFNoise1: ramps between random values (-1..1), freq new ones a second
struct LFNoise1 {
    Rng rng;
    float from = 0, to = 0;
    double pos = 1;
    explicit LFNoise1(uint32_t seed) : rng(seed) { to = rng.bi(); }
    float operator()(double freq, double rate) {
        pos += freq / rate;
        while (pos >= 1) {
            pos -= 1;
            from = to;
            to = rng.bi();
        }
        return from + (to - from) * (float)pos;
    }
};

// LFNoise2: the same, through a smooth (quadratic-like) curve between the values
struct LFNoise2 {
    LFNoise1 n;
    explicit LFNoise2(uint32_t seed) : n(seed) {}
    float operator()(double freq, double rate) {
        n(freq, rate);
        float t = (float)n.pos, s = t * t * (3 - 2 * t);
        return n.from + (n.to - n.from) * s;
    }
};

// Dust: random impulses (0..1), density a second on average
struct Dust {
    Rng rng;
    explicit Dust(uint32_t seed) : rng(seed) {}
    float operator()(double density, double rate) {
        float thresh = (float)(density / rate);
        float r = rng.uni();
        return r < thresh ? r / thresh : 0.0f;
    }
};

// Decay2: an impulse becomes a click with an attack and a decay (60 dB in each time)
struct Decay2 {
    double a = 0, b = 0, ca, cb;
    Decay2(double attack, double decay, double rate)
        : ca(std::exp(std::log(0.001) / (attack * rate))), cb(std::exp(std::log(0.001) / (decay * rate))) {}
    float operator()(float x) {
        a = x + ca * a;
        b = x + cb * b;
        return (float)(b - a);
    }
};

// LPF / HPF: SC's second-order Butterworth filters
struct Butter {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0, last = -1;
    bool high;
    explicit Butter(bool hp) : high(hp) {}
    void freq(double f, double rate) {
        if (f == last) return;
        last = f;
        f = std::min(std::max(f, 10.0), rate * 0.45);
        double c = high ? std::tan(PI * f / rate) : 1.0 / std::tan(PI * f / rate);
        double c2 = c * c, s2c = std::sqrt(2.0) * c, a0 = 1 + s2c + c2;
        if (high) {
            b0 = 1 / a0;
            b1 = -2 * b0;
            b2 = b0;
            a1 = 2 * (c2 - 1) / a0;
            a2 = (1 - s2c + c2) / a0;
        } else {
            b0 = 1 / a0;
            b1 = 2 * b0;
            b2 = b0;
            a1 = 2 * (1 - c2) / a0;
            a2 = (1 - s2c + c2) / a0;
        }
    }
    float operator()(float x) {
        double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = x;
        y2 = y1;
        y1 = y;
        return (float)y;
    }
};

// PinkNoise: -1..1, falling 3 dB an octave (Paul Kellet's filter on white noise)
struct PinkNoise {
    Rng rng;
    double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
    explicit PinkNoise(uint32_t seed) : rng(seed) {}
    float operator()() {
        double w = rng.bi();
        b0 = 0.99886 * b0 + w * 0.0555179;
        b1 = 0.99332 * b1 + w * 0.0750759;
        b2 = 0.96900 * b2 + w * 0.1538520;
        b3 = 0.86650 * b3 + w * 0.3104856;
        b4 = 0.55000 * b4 + w * 0.5329522;
        b5 = -0.7616 * b5 - w * 0.0168980;
        double y = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
        b6 = w * 0.115926;
        return (float)(y * 0.11);
    }
};

// DelayC: a delay line read with cubic interpolation, up to maxSeconds
struct DelayC {
    std::vector<float> buf;
    size_t w = 0;
    DelayC(double maxSeconds, double rate) : buf((size_t)(maxSeconds * rate) + 4, 0.0f) {}
    float operator()(float x, double delaySamples) {
        size_t n = buf.size();
        buf[w] = x;
        double d = std::min(std::max(delaySamples, 1.0), (double)n - 3);
        double rp = (double)w - d;
        while (rp < 0) rp += (double)n;
        size_t i1 = (size_t)rp;
        float f = (float)(rp - (double)i1);
        float y0 = buf[(i1 + n - 1) % n], y1 = buf[i1 % n], y2 = buf[(i1 + 1) % n], y3 = buf[(i1 + 2) % n];
        w = (w + 1) % n;
        // cubic (Hermite) interpolation, as SC's cubicinterp
        float c0 = y1, c1 = 0.5f * (y2 - y0), c2 = y0 - 2.5f * y1 + 2 * y2 - 0.5f * y3,
              c3 = 0.5f * (y3 - y0) + 1.5f * (y1 - y2);
        return ((c3 * f + c2) * f + c1) * f + c0;
    }
};

// SC's envelope curve between two levels: shape c (0 = linear), position t 0..1
inline float envCurve(float from, float to, float t, float c) {
    if (std::fabs(c) < 0.001f) return from + (to - from) * t;
    return from + (to - from) * (1 - std::exp(c * t)) / (1 - std::exp(c));
}

// Env.perc(attack, release, 1, curve) retriggered by t_trig, at control rate
struct Perc {
    double t = -1;  // seconds since the trigger, -1 idle
    float operator()(bool trig, double attack, double release, float curve, double blockSec) {
        if (trig) t = 0;
        if (t < 0) return 0;
        float y;
        if (t < attack) y = envCurve(0, 1, (float)(t / attack), curve);
        else if (t < attack + release) y = envCurve(1, 0, (float)((t - attack) / release), curve);
        else {
            t = -1;
            return 0;
        }
        t += blockSec;
        return y;
    }
};

}  // namespace terrarium::ugen
