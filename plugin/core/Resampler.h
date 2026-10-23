// Stereo sample-rate conversion, for the engine running at 48 kHz (as a norns does) inside a
// host at another rate: the engine's output to the host's rate, and the host's input to 48 kHz.
// Some mi-UGens (Plaits, Rings) change their envelopes and damping with the sample rate, so
// the engine keeps to the rate they sound right at, and only the edges convert.
//
// A windowed-sinc interpolator: 64 taps (a Blackman-Harris window), the kernel tabulated at 512
// phases a tap and interpolated; its cutoff follows the lower of the two rates, so going down
// (48 to 44.1 kHz) it filters out what the new rate can't hold. Latency: 32 input samples.
// At equal rates it's skipped (samples pass through as they are).
//
// push() input, then pull() output while there's enough input for it. Not thread-safe; nothing
// allocates after configure().
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace terrarium {

class Resampler {
public:
    static constexpr int HALF = 32;        // taps each side
    static constexpr int PHASES = 512;     // kernel table resolution, per tap
    static constexpr size_t RING = 1 << 14;

    void configure(double inRate, double outRate) {
        step_ = inRate / outRate;
        bypass_ = std::fabs(step_ - 1) < 1e-9;
        for (auto& c : ring_) c.assign(RING, 0.0f);
        // HALF samples of silence first, so the first output has its history
        write_ = 2 * HALF;
        base_ = HALF;
        frac_ = 0;
        if (bypass_) {
            write_ = base_ = 0;
            return;
        }
        double fc = std::min(1.0, 1 / step_) * 0.93;  // cutoff, of the input's Nyquist
        table_.assign((size_t)(2 * HALF * PHASES + 1), 0.0f);
        for (size_t i = 0; i < table_.size(); ++i) {
            double d = (double)i / PHASES - HALF;  // distance from the output, in input samples
            double x = PI * fc * d;
            double sinc = std::fabs(d) < 1e-9 ? 1.0 : std::sin(x) / x;
            double w = (d + HALF) / (2 * HALF);  // 0..1 across the window
            double bh = 0.35875 - 0.48829 * std::cos(2 * PI * w) + 0.14128 * std::cos(4 * PI * w) -
                        0.01168 * std::cos(6 * PI * w);
            table_[i] = (float)(fc * sinc * bh);
        }
    }

    bool bypass() const { return bypass_; }

    // input waiting, in input samples, past what the next output needs
    size_t pending() const { return write_ - base_; }

    void push(const float* l, const float* r, int n) {
        for (int i = 0; i < n; ++i, ++write_) {
            ring_[0][write_ & (RING - 1)] = l[i];
            ring_[1][write_ & (RING - 1)] = r ? r[i] : l[i];
        }
    }

    // up to n outputs; returns how many there was input for
    int pull(float* l, float* r, int n) {
        int i = 0;
        if (bypass_) {
            for (; i < n && base_ < write_; ++i, ++base_) {
                l[i] = ring_[0][base_ & (RING - 1)];
                r[i] = ring_[1][base_ & (RING - 1)];
            }
            return i;
        }
        for (; i < n && base_ + HALF < write_; ++i) {
            // the taps: input samples base-HALF+1 .. base+HALF, at distance k - (HALF-1) - frac
            double pos = (1 - frac_) * PHASES;  // table position of the first tap (distance -HALF+1-frac)
            float sl = 0, sr = 0;
            for (int k = 0; k < 2 * HALF; ++k, pos += PHASES) {
                size_t ti = (size_t)pos;
                float f = (float)(pos - (double)ti);
                float h = ti + 1 < table_.size() ? table_[ti] + (table_[ti + 1] - table_[ti]) * f : 0.0f;
                size_t idx = (base_ - HALF + 1 + (size_t)k) & (RING - 1);
                sl += ring_[0][idx] * h;
                sr += ring_[1][idx] * h;
            }
            l[i] = sl;
            r[i] = sr;
            frac_ += step_;
            double whole = std::floor(frac_);
            base_ += (uint64_t)whole;
            frac_ -= whole;
        }
        return i;
    }

private:
    static constexpr double PI = 3.14159265358979323846;
    double step_ = 1, frac_ = 0;
    bool bypass_ = true;
    std::vector<float> ring_[2], table_;
    uint64_t write_ = 0, base_ = 0;
};

}  // namespace terrarium
