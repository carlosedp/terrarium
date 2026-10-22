#include "PluginEditor.h"

#include <cmath>

namespace {
// the night of the r/norns look, and the shield's aluminium
const juce::Colour NIGHT(0xff121513), ALU_EDGE(0xff7d817c), CAP(0xff262827), OLED(0xff030303);
constexpr int W = 600, H = 520, SCALE = 4, DRAG_PX = 14;
}  // namespace

TerrariumEditor::TerrariumEditor(TerrariumProcessor& p) : AudioProcessorEditor(&p), proc_(p) {
    setSize(W, H);
    setWantsKeyboardFocus(true);
    startTimerHz(30);
}

TerrariumEditor::~TerrariumEditor() { stopTimer(); }

void TerrariumEditor::resized() {
    // a shield: K1 top left, E1 top right, the screen, then K2 K3 E2 E3 along the bottom
    screenArea_ = {(W - 128 * SCALE) / 2, 120, 128 * SCALE, 64 * SCALE};
    float y1 = 62, y2 = 440, d = 56, k = 32;
    keys_[0] = {64 - k / 2, y1 - k / 2, k, k};
    encs_[0] = {W - 64 - d / 2, y1 - d / 2, d, d};
    float xs[4] = {84, 212, 388, 516};
    keys_[1] = {xs[0] - k / 2, y2 - k / 2, k, k};
    keys_[2] = {xs[1] - k / 2, y2 - k / 2, k, k};
    encs_[1] = {xs[2] - d / 2, y2 - d / 2, d, d};
    encs_[2] = {xs[3] - d / 2, y2 - d / 2, d, d};
}

// the screen, from the script's last frame: 16 levels of a warm white, as norns-web draws it
void TerrariumEditor::timerCallback() {
    auto* core = proc_.core();
    if (!core) return;
    unsigned char fb[128 * 64];
    core->copyFrame(fb);
    juce::Image::BitmapData px(screen_, juce::Image::BitmapData::writeOnly);
    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 128; ++x) {
            int l = fb[y * 128 + x];
            float v = l == 0 ? 0.0f : std::pow(l / 15.0f, 0.8f);
            px.setPixelColour(x, y, juce::Colour::fromFloatRGBA(v * 248 / 255, v * 245 / 255, v * 236 / 255, 1));
        }
    repaint();
}

void TerrariumEditor::paint(juce::Graphics& g) {
    g.fillAll(NIGHT);
    auto shell = getLocalBounds().toFloat().reduced(14);
    g.setGradientFill(juce::ColourGradient(juce::Colour(0xffd6d8d4), shell.getTopLeft(), juce::Colour(0xffa8aca7),
                                           shell.getBottomRight(), false));
    g.fillRoundedRectangle(shell, 12);
    g.setColour(ALU_EDGE);
    g.drawRoundedRectangle(shell, 12, 1);

    g.setColour(juce::Colour(0xff4f534f));
    g.setFont(juce::FontOptions(12.0f));
    g.drawText("terrarium", juce::Rectangle<int>(0, 50, W, 24), juce::Justification::centred);

    // the screen in its bezel; scaled up as pixels, not smoothed
    auto bezel = screenArea_.toFloat().expanded(10);
    g.setColour(ALU_EDGE);
    g.fillRoundedRectangle(bezel.expanded(4), 8);
    g.setColour(juce::Colour(0xff1a1b1a));
    g.fillRoundedRectangle(bezel.expanded(3), 7);
    g.setColour(OLED);
    g.fillRoundedRectangle(bezel, 6);
    g.setImageResamplingQuality(juce::Graphics::lowResamplingQuality);
    g.drawImage(screen_, screenArea_.toFloat(), juce::RectanglePlacement::stretchToFit);

    const char* klabels[] = {"K1", "K2", "K3"};
    const char* elabels[] = {"E1", "E2", "E3"};
    g.setFont(juce::FontOptions(10.0f));
    for (int i = 0; i < 3; ++i) {
        // a key cap, lit from the top left, sitting on its shadow; pressed, it sinks
        auto k = keys_[i];
        bool down = heldKey_ == i + 1 || keyDown_[i];
        g.setColour(juce::Colour(0x59000000));
        g.fillEllipse(k.translated(0, 3).expanded(1));
        g.setColour(juce::Colour(0xff111111));
        g.fillEllipse(k.translated(0, 2));  // the edge under the cap
        auto cap = k.translated(0, down ? 2.0f : 0.0f);
        g.setGradientFill(juce::ColourGradient(juce::Colour(0xff4a4d4b), cap.getX() + cap.getWidth() * 0.35f,
                                               cap.getY() + cap.getHeight() * 0.3f, CAP, cap.getRight(),
                                               cap.getBottom(), true));
        g.fillEllipse(cap);
        g.setColour(juce::Colour(0xff4a4e4a));
        g.drawText(klabels[i], k.withY(k.getBottom() + 4).withHeight(12).toNearestInt(), juce::Justification::centred);

        // an encoder: a knurled dark knob in a ring, its pointer turning
        auto e = encs_[i];
        g.setColour(juce::Colour(0x66000000));
        g.fillEllipse(e.translated(0, 4).expanded(2));
        g.setColour(juce::Colour(0xff3b3e3c));
        g.fillEllipse(e.expanded(3));
        g.setGradientFill(juce::ColourGradient(juce::Colour(0xff3a3d3b), e.getX(), e.getY(), juce::Colour(0xff1d1f1e),
                                               e.getRight(), e.getBottom(), false));
        g.fillEllipse(e);
        g.setColour(juce::Colour(0x18ffffff));
        for (int r = 0; r < 24; ++r) {  // the knurling
            float ra = r * juce::MathConstants<float>::twoPi / 24 + angle_[i], c0 = e.getWidth() * 0.44f;
            auto ctr = e.getCentre();
            g.drawLine(ctr.x + std::sin(ra) * c0 * 0.86f, ctr.y - std::cos(ra) * c0 * 0.86f, ctr.x + std::sin(ra) * c0,
                       ctr.y - std::cos(ra) * c0, 1);
        }
        auto c = e.getCentre();
        float a = angle_[i], r0 = e.getWidth() * 0.18f, r1 = e.getWidth() * 0.42f;
        g.setColour(juce::Colour(0xffcfd2ce));
        g.drawLine(c.x + std::sin(a) * r0, c.y - std::cos(a) * r0, c.x + std::sin(a) * r1, c.y - std::cos(a) * r1, 3);
        g.setColour(juce::Colour(0xff4a4e4a));
        g.drawText(elabels[i], e.withY(e.getBottom() + 4).withHeight(12).toNearestInt(), juce::Justification::centred);
    }

    // an error, if there is one (the log's other lines stay in the log)
    auto status = proc_.status();
    if (status.startsWith("error") || status.startsWith("terrarium didn't")) {
        g.setColour(juce::Colour(0xffb23b2a));
        g.setFont(juce::FontOptions(11.0f));
        g.drawText(status, juce::Rectangle<int>(24, H - 36, W - 48, 14), juce::Justification::centred, true);
    }
}

void TerrariumEditor::turn(int n, int d) {
    if (auto* core = proc_.core()) core->enc(n, d);
    angle_[n - 1] += d * 0.21f;
}

void TerrariumEditor::press(int n, int z) {
    if (auto* core = proc_.core()) core->key(n, z);
}

void TerrariumEditor::mouseDown(const juce::MouseEvent& e) {
    auto p = e.position;
    for (int i = 0; i < 3; ++i) {
        if (keys_[i].expanded(6).contains(p)) {
            heldKey_ = i + 1;
            press(heldKey_, 1);
            repaint();
            return;
        }
        if (encs_[i].expanded(4).contains(p)) {
            dragEnc_ = i + 1;
            dragAcc_ = 0;
            lastDragY_ = e.position.y;
            return;
        }
    }
}

void TerrariumEditor::mouseDrag(const juce::MouseEvent& e) {
    if (!dragEnc_) return;
    dragAcc_ += lastDragY_ - e.position.y;  // up turns up
    lastDragY_ = e.position.y;
    while (std::abs(dragAcc_) >= DRAG_PX) {
        int s = dragAcc_ > 0 ? 1 : -1;
        turn(dragEnc_, s);
        dragAcc_ -= s * DRAG_PX;
    }
}

void TerrariumEditor::mouseUp(const juce::MouseEvent&) {
    if (heldKey_) press(heldKey_, 0);
    heldKey_ = 0;
    dragEnc_ = 0;
    repaint();
}

void TerrariumEditor::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& w) {
    for (int i = 0; i < 3; ++i)
        if (encs_[i].expanded(8).contains(e.position)) {
            wheelAcc_ += w.deltaY;
            // a mouse notch is about 0.1 to 0.25; a trackpad's stream adds up the same way
            while (std::abs(wheelAcc_) >= 0.1f) {
                int s = wheelAcc_ > 0 ? 1 : -1;
                turn(i + 1, s);
                wheelAcc_ -= s * 0.1f;
            }
            return;
        }
}

bool TerrariumEditor::keyPressed(const juce::KeyPress& k) {
    static const struct { juce::juce_wchar c; int enc, dir; } ENCS[] = {
        {'y', 1, 1}, {'h', 1, -1}, {'u', 2, 1}, {'j', 2, -1}, {'i', 3, 1}, {'k', 3, -1}};
    auto c = juce::CharacterFunctions::toLowerCase(k.getTextCharacter());
    for (auto& m : ENCS)
        if (c == m.c) {
            turn(m.enc, m.dir);
            return true;
        }
    return c == 'a' || c == 's' || c == 'd';  // keyStateChanged presses them
}

// A S D held like the norns' keys: down while down
bool TerrariumEditor::keyStateChanged(bool) {
    const int codes[] = {'A', 'S', 'D'};
    bool any = false;
    for (int i = 0; i < 3; ++i) {
        bool down = juce::KeyPress::isKeyCurrentlyDown(codes[i]);
        if (down != keyDown_[i]) {
            keyDown_[i] = down;
            press(i + 1, down ? 1 : 0);
            any = true;
        }
    }
    if (any) repaint();
    return any;
}
