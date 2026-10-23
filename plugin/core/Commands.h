// Engine commands, from Lua to the audio thread.
//
// Lua calls engine.note(60, 1) on the message thread; the command is stamped with the
// Lua time it was made at (util.time(): a clock routine's exact wake time) and goes
// through a lock-free queue to the audio thread, which runs it when its own time gets
// there. Fixed-size, so nothing allocates on the way.
#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstring>

namespace terrarium {

struct Arg {
    bool isString = false;
    double num = 0;
    char str[32] = {};
};

struct Command {
    double time = 0;  // seconds, in Lua's (and the engine's) time
    char name[24] = {};
    int argc = 0;
    Arg args[4];
    // a module swap's new synth, built on the message thread (Engine::prepareCommand), so the
    // audio thread never allocates one; the audio thread owns it once it runs the command
    void* synth = nullptr;

    bool is(const char* n) const { return std::strcmp(name, n) == 0; }
    double num(int i, double dflt = 0) const { return i < argc && !args[i].isString ? args[i].num : dflt; }
    const char* str(int i) const { return i < argc && args[i].isString ? args[i].str : ""; }
};

// One producer, one consumer, no locks: Lua's thread pushes, the audio thread pops.
template <typename T, size_t N>
class SpscQueue {
    static_assert((N & (N - 1)) == 0, "N must be a power of two");

public:
    bool push(const T& v) {
        size_t w = write_.load(std::memory_order_relaxed);
        if (w - read_.load(std::memory_order_acquire) >= N) return false;  // full
        buf_[w & (N - 1)] = v;
        write_.store(w + 1, std::memory_order_release);
        return true;
    }
    bool pop(T& v) {
        size_t r = read_.load(std::memory_order_relaxed);
        if (r == write_.load(std::memory_order_acquire)) return false;  // empty
        v = buf_[r & (N - 1)];
        read_.store(r + 1, std::memory_order_release);
        return true;
    }

private:
    std::array<T, N> buf_;
    std::atomic<size_t> write_{0}, read_{0};
};

using CommandQueue = SpscQueue<Command, 4096>;

}  // namespace terrarium
