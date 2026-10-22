// terrarium-render: the plugin's core without the plugin. Boots the script, plays it
// offline as a host would, and writes a WAV and the last screen, so the Lua, the engine
// and the timing between them can be tested anywhere (no JUCE, no audio device).
//
//   terrarium-render [options]
//     --script DIR    terrarium's folder (default: .)
//     --norns FILE    norns-web's norns.lua (default: <script>/tools/norns-web/lib/norns.lua)
//     --mi DIR        the native mi-UGens (default: the build's)
//     --seconds N     how long (default 20)
//     --bpm N         the host's tempo (default 120)
//     --stopped       the host's transport stopped (Lua's clock runs free)
//     --start BEATS   the host's position when it starts (default 0)
//     --block N       the host's block size (default 512)
//     --sr N          sample rate (default 48000)
//     --lua CODE      run in the script after it starts, like maiden's REPL (repeatable)
//     --out FILE      the WAV (default terrarium.wav); the screen goes next to it as .pgm
//     --quiet         no log
//     --check-params  check PARAMS for the plugin's face and its automation slots: the list,
//                     and each kind of param through 0..1 and back
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "Terrarium.h"

#if defined(_WIN32)
#include <stdlib.h>
static std::string absolute(const std::string& p) {
    char buf[4096];
    return _fullpath(buf, p.c_str(), sizeof(buf)) ? buf : p;
}
#else
#include <climits>
#include <cstdlib>
static std::string absolute(const std::string& p) {
    char buf[PATH_MAX];
    return realpath(p.c_str(), buf) ? buf : p;
}
#endif

#ifndef TERRARIUM_MI_DIR
#define TERRARIUM_MI_DIR "."
#endif

using namespace terrarium;

static void wav(const std::string& path, const std::vector<float>& l, const std::vector<float>& r, int sr) {
    uint32_t n = (uint32_t)l.size(), bytes = n * 4;
    std::ofstream f(path, std::ios::binary);
    auto u32 = [&](uint32_t v) { f.write((const char*)&v, 4); };
    auto u16 = [&](uint16_t v) { f.write((const char*)&v, 2); };
    f.write("RIFF", 4); u32(36 + bytes); f.write("WAVEfmt ", 8);
    u32(16); u16(1); u16(2); u32((uint32_t)sr); u32((uint32_t)sr * 4); u16(4); u16(16);
    f.write("data", 4); u32(bytes);
    for (uint32_t i = 0; i < n; ++i)
        for (float v : {l[i], r[i]}) u16((uint16_t)(int16_t)std::lround(std::max(-1.0f, std::min(1.0f, v)) * 32767));
}

static void pgm(const std::string& path, const unsigned char* fb) {
    std::ofstream f(path, std::ios::binary);
    f << "P5\n128 64\n255\n";
    for (int i = 0; i < 128 * 64; ++i) f.put((char)(fb[i] * 17));
}

int main(int argc, char** argv) {
    std::string script = ".", norns, mi = TERRARIUM_MI_DIR, out = "terrarium.wav";
    double seconds = 20, bpm = 120, start = 0;
    int block = 512, sr = 48000;
    bool playing = true, quiet = false, checkParams = false;
    std::vector<std::string> lua;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "--script") script = next();
        else if (a == "--norns") norns = next();
        else if (a == "--mi") mi = next();
        else if (a == "--seconds") seconds = std::stod(next());
        else if (a == "--bpm") bpm = std::stod(next());
        else if (a == "--stopped") playing = false;
        else if (a == "--start") start = std::stod(next());
        else if (a == "--block") block = std::stoi(next());
        else if (a == "--sr") sr = std::stoi(next());
        else if (a == "--lua") lua.push_back(next());
        else if (a == "--out") out = next();
        else if (a == "--quiet") quiet = true;
        else if (a == "--check-params") checkParams = true;
        else {
            std::fprintf(stderr, "unknown option %s (see the top of render/main.cpp)\n", a.c_str());
            return 2;
        }
    }
    script = absolute(script);
    if (norns.empty()) norns = script + "/tools/norns-web/lib/norns.lua";

    Terrarium t({norns, script, mi});
    int errors = 0;
    t.onLog = [&](const std::string& s, bool err) {
        if (err) ++errors;
        if (!quiet || err) std::fprintf(err ? stderr : stdout, "%s%s\n", err ? "error: " : "", s.c_str());
    };
    // every note: its time, and where it falls on the host's beat
    std::vector<double> notes;
    t.onRun = [&](const Command& c, double time) {
        if (c.is("note")) notes.push_back(time);
    };

    std::string err;
    if (!t.boot(err)) {
        std::fprintf(stderr, "terrarium-render: %s\n", err.c_str());
        return 1;
    }
    t.prepare(sr);
    for (auto& code : lua) t.repl(code);

    if (checkParams) {
        std::string json = t.paramsJson();
        int n = 0;
        for (size_t p = json.find("\"i\":"); p != std::string::npos; p = json.find("\"i\":", p + 1)) ++n;
        std::printf("params: %d in the list (%zu bytes of JSON)\n", n, json.size());
        int bad = n > 50 ? 0 : 1;
        // a control, an option and a number: set through 0..1, read back, by index and by id
        for (const char* id : {"rain_change", "voice_kind", "t_length"}) {
            int index = t.paramIndex(id);
            if (!index || t.paramId(index) != id) {
                std::printf("FAIL %s: index %d doesn't lead back to it\n", id, index);
                bad = 1;
                continue;
            }
            for (double v : {0.0, 1.0, 0.5}) {
                t.setNorm(id, v);
                double back = -1;
                t.getNorm(id, back);
                bool ok = std::fabs(back - v) < 0.26;  // options and numbers land on their steps
                if (!ok) bad = 1;
                std::printf("%s %-14s (%s, #%d) set %.2f -> %.3f\n", ok ? "ok  " : "FAIL", id, t.paramName(id).c_str(),
                            index, v, back);
            }
        }
        return bad;
    }

    size_t total = (size_t)(seconds * sr);
    std::vector<float> L(total), R(total);
    HostTime host;
    host.valid = true;
    host.bpm = bpm;
    host.playing = playing;
    for (size_t pos = 0; pos < total; pos += block) {
        int n = (int)std::min<size_t>(block, total - pos);
        host.ppq = start + (double)pos / sr * bpm / 60;
        t.process(L.data() + pos, R.data() + pos, n, host, true);
    }

    wav(out, L, R, sr);
    unsigned char fb[128 * 64];
    t.copyFrame(fb);
    std::string screen = out.substr(0, out.find_last_of('.')) + ".pgm";
    pgm(screen, fb);

    double peak = 0, sum = 0;
    for (size_t i = 0; i < total; ++i) {
        peak = std::max(peak, (double)std::max(std::fabs(L[i]), std::fabs(R[i])));
        sum += (double)L[i] * L[i] + (double)R[i] * R[i];
    }
    // how far each note is from the host's nearest 16th: Lua's beat phase follows the host's,
    // so a note's Lua time in beats has the host's fraction
    double worst = 0, beatSec = 60 / bpm;
    for (double n : notes) {
        double sixteenths = n / beatSec * 4;
        worst = std::max(worst, std::fabs(sixteenths - std::round(sixteenths)) * beatSec / 4);
    }
    std::printf("%s: %.1f s, %zu notes, rms %.4f, peak %.3f; screen %s\n", out.c_str(), seconds, notes.size(),
                std::sqrt(sum / (2.0 * total)), peak, screen.c_str());
    if (playing && notes.size() > 1)
        std::printf("on the host's grid: every note within %.2f ms of a 16th (%.2f ms = one block)\n",
                    worst * 1000, 1000.0 * BLOCK / sr);
    return errors ? 1 : 0;
}
