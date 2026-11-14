/*
 * Vibrator HAL for the OnePlus 8 (aw8697 haptics driver, /sys/class/leds/vibrator).
 *
 * Drop-in replacement for crDroid's vendor.qti.hardware.vibrator.service.oplus
 * (crdroidandroid/android_hardware_oplus, aidl/vibrator/qti, LED mode). Same service name,
 * same user/groups, same sysfs writes for the prebaked effects, plus:
 *
 *   - CAP_AMPLITUDE_CONTROL: setAmplitude() drives the chip gain through the vmax node
 *     (values <= 255 set gain = v * 0x80 / 255 in the driver). The stock HAL refused it, so
 *     Android played every "soft" waveform step at full power.
 *   - CAP_COMPOSE_EFFECTS with CLICK, LIGHT_TICK (= Java PRIMITIVE_TICK), LOW_TICK and THUD,
 *     each played from the chip's built-in RAM waveforms at a gain derived from the scale.
 *     This lets SystemUI (MSDL) use its designed primitives instead of the fallback waveforms.
 *
 * Every primitive and the amplitude curve can be tuned live from adb (no reflash):
 *   setprop debug.vib.<name> "wf,level,gmin,gmax,gamma"   name = click|tick|lowtick|thud
 *       wf     RAM waveform index (1..18)
 *       level  table level written first: 1400 = low boost, 2500 = high boost
 *       gmin   chip gain (0..128) at the smallest scale, gmax at scale 1.0
 *       gamma  curve: gain = gmin + (gmax - gmin) * scale^gamma
 *   setprop debug.vib.amp "gmax,gamma,short_ms"   amplitude curve for on()/setAmplitude()
 *   setprop debug.vib.coalesce 0|1   1 (default): a run of identical primitives with no delay
 *                                    (SystemUI's 5 x LOW_TICK slider grain) plays as one tick
 *   setprop debug.vib.perform_ms N   length reported for prebaked effects (default 20; stock 150)
 *   setprop debug.vib.tailstop 0|1   1: end each primitive with the stock 'rtp 0' write, which
 *                                    busy-waits in the driver until the waveform is done
 *   setprop debug.vib.log 1                        log every call to logcat (tag vibrator-op8)
 */

#include "Vibrator.h"

#include <android/log.h>
#include <fcntl.h>
#include <sys/system_properties.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

#define LOG_TAG "vibrator-op8"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGD(...) \
    do { if (mParams.log) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__); } while (0)

namespace aidl::android::hardware::vibrator {

static constexpr char kLed[] = "/sys/class/leds/vibrator/";
static constexpr int32_t kCompositionDelayMaxMs = 1000;
static constexpr int32_t kCompositionSizeMax = 16;
// The stock HAL reported every prebaked effect as 150 ms long. Android waits out the reported
// length before a superseding vibration starts, which capped fast typing at ~5 clicks/s.
// The real effects take ~14 ms of waveform plus the driver's stop wait (default: Params::performMs).
// Reported LOW_TICK duration. SystemUI rate-limits slider ticks to 5 x this, so 4 ms allows
// ~50 ticks/s, about what the chip can fire. The waveform itself is longer (waveformMs).
static constexpr int32_t kLowTickReportMs = 4;
static constexpr float kGainFull = 128.f;      // driver gain for vmax 255 (AW8697 RAM comp gain 0x80)

static ndk::ScopedAStatus unsupported() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}
static ndk::ScopedAStatus illegal() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);
}

// ---- sysfs ---------------------------------------------------------------------------------

int Vibrator::write(const char* node, const std::string& value) {
    std::string path = std::string(kLed) + node;
    int fd = TEMP_FAILURE_RETRY(open(path.c_str(), O_WRONLY | O_CLOEXEC));
    if (fd < 0) {
        ALOGE("open %s: %s", path.c_str(), strerror(errno));
        return -errno;
    }
    // The stock HAL writes the terminating NUL too; the driver's kstrtouint accepts either.
    ssize_t n = TEMP_FAILURE_RETRY(::write(fd, value.c_str(), value.size() + 1));
    int err = n < 0 ? -errno : 0;
    close(fd);
    if (err) ALOGE("write %s=%s: %s", node, value.c_str(), strerror(-err));
    return err;
}

int Vibrator::write(const char* node, int value) {
    return write(node, std::to_string(value));
}

// Chip gain (0..128) -> vmax node value (1..255).
static int gainToVmax(float gain) {
    int v = static_cast<int>(std::lround(gain * 255.f / kGainFull));
    return std::clamp(v, 1, 255);
}

// Plays one RAM waveform. level: table level (sets boost voltage), gain: 0..128.
// Same write order as the stock HAL's perform(), plus the gain write. tailStop: the stock
// trailing 'rtp 0', which makes the driver busy-wait until the chip is back in standby.
void Vibrator::playRam(int waveform, int level, float gain, bool tailStop) {
    write("rtp", 0);
    write("vmax", level);
    if (gain > 0) write("vmax", gainToVmax(gain));
    write("waveform_index", waveform);
    write("brightness", 1);
    if (tailStop) write("rtp", 0);
}

// ---- tunables ------------------------------------------------------------------------------

static void parsePrim(const char* prop, Vibrator::Prim* p) {
    char buf[PROP_VALUE_MAX] = {};
    if (__system_property_get(prop, buf) <= 0) return;
    Vibrator::Prim q = *p;
    if (sscanf(buf, "%d,%d,%f,%f,%f", &q.wf, &q.level, &q.gmin, &q.gmax, &q.gamma) == 5 &&
        q.wf >= 1 && q.wf <= 18 && q.gmin >= 0 && q.gmax <= kGainFull && q.gamma > 0) {
        *p = q;
    }
}

void Vibrator::refreshParams() {
    // Re-read the debug.vib.* properties at most twice a second.
    auto now = std::chrono::steady_clock::now();
    if (mParamsLoaded && now - mParamsTime < std::chrono::milliseconds(500)) return;
    mParamsLoaded = true;
    mParamsTime = now;
    Params p;  // defaults
    parsePrim("debug.vib.click", &p.click);
    parsePrim("debug.vib.tick", &p.tick);
    parsePrim("debug.vib.lowtick", &p.lowtick);
    parsePrim("debug.vib.thud", &p.thud);
    char buf[PROP_VALUE_MAX] = {};
    if (__system_property_get("debug.vib.amp", buf) > 0) {
        float g, gm;
        int s;
        if (sscanf(buf, "%f,%f,%d", &g, &gm, &s) == 3 && g > 0 && g <= kGainFull && gm > 0) {
            p.ampGainMax = g;
            p.ampGamma = gm;
            p.shortMs = s;
        }
    }
    buf[0] = 0;
    p.log = __system_property_get("debug.vib.log", buf) > 0 && buf[0] == '1';
    buf[0] = 0;
    if (__system_property_get("debug.vib.coalesce", buf) > 0) p.coalesce = buf[0] == '1';
    buf[0] = 0;
    if (__system_property_get("debug.vib.tailstop", buf) > 0) p.tailStop = buf[0] == '1';
    buf[0] = 0;
    if (__system_property_get("debug.vib.perform_ms", buf) > 0) {
        int ms = atoi(buf);
        if (ms >= 1 && ms <= 1000) p.performMs = ms;
    }
    mParams = p;
}

const Vibrator::Prim* Vibrator::primFor(CompositePrimitive p) const {
    switch (p) {
        case CompositePrimitive::CLICK: return &mParams.click;
        case CompositePrimitive::LIGHT_TICK: return &mParams.tick;
        case CompositePrimitive::LOW_TICK: return &mParams.lowtick;
        case CompositePrimitive::THUD: return &mParams.thud;
        default: return nullptr;
    }
}

// Durations of the RAM waveforms in aw8697_haptic_172.bin (24 kHz), rounded up.
static int32_t waveformMs(int wf) {
    static const int32_t ms[19] = {0, 14, 12, 12, 14, 15, 14, 14, 1, 68, 6, 18, 18, 12, 1, 1, 14, 12, 15};
    return (wf >= 1 && wf <= 18) ? ms[wf] : 14;
}

// ---- IVibrator -----------------------------------------------------------------------------

Vibrator::Vibrator() {
    refreshParams();
    ALOGI("OnePlus 8 vibrator HAL up (amplitude control + primitives)");
}

ndk::ScopedAStatus Vibrator::getCapabilities(int32_t* _aidl_return) {
    *_aidl_return = static_cast<int32_t>(IVibrator::CAP_ON_CALLBACK) |
                    static_cast<int32_t>(IVibrator::CAP_PERFORM_CALLBACK) |
                    static_cast<int32_t>(IVibrator::CAP_AMPLITUDE_CONTROL) |
                    static_cast<int32_t>(IVibrator::CAP_COMPOSE_EFFECTS);
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::off() {
    std::lock_guard<std::mutex> lock(mLock);
    mGeneration++;  // aborts a running composition
    mOnActive = false;
    ALOGD("off");
    write("activate", "0");
    return ndk::ScopedAStatus::ok();
}

float Vibrator::onGain(int32_t timeoutMs, float amplitude) const {
    // Stock behaviour at full amplitude: pulses <= 20 ms use vmax = ms * 10, longer ones full.
    float full = timeoutMs <= mParams.shortMs ? timeoutMs * 10.f * kGainFull / 255.f
                                              : mParams.ampGainMax;
    full = std::min(full, mParams.ampGainMax);
    return std::max(1.f, full * std::pow(std::clamp(amplitude, 0.f, 1.f), mParams.ampGamma));
}

ndk::ScopedAStatus Vibrator::on(int32_t timeoutMs,
                                const std::shared_ptr<IVibratorCallback>& callback) {
    if (timeoutMs <= 0) return illegal();
    {
        std::lock_guard<std::mutex> lock(mLock);
        refreshParams();
        mGeneration++;
        float gain = onGain(timeoutMs, mAmplitude);
        ALOGD("on %d ms amp %.3f -> gain %.1f", timeoutMs, mAmplitude, gain);
        write("vmax", 1600);  // known boost level, then the gain
        write("vmax", gainToVmax(gain));
        write("waveform_index", 7);
        write("duration", timeoutMs);
        write("state", "1");
        write("activate", "1");
        write("activate", "0");  // stock sequence: the driver plays the RTP buffer to its end
        mOnActive = true;
        mOnTimeoutMs = timeoutMs;
    }
    if (callback) {
        std::thread([callback, timeoutMs] {
            std::this_thread::sleep_for(std::chrono::milliseconds(timeoutMs));
            callback->onComplete();
        }).detach();
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::setAmplitude(float amplitude) {
    if (amplitude <= 0.f || amplitude > 1.f) return illegal();
    std::lock_guard<std::mutex> lock(mLock);
    mAmplitude = amplitude;
    if (mOnActive) {  // change the gain of the running vibration
        float gain = onGain(mOnTimeoutMs, amplitude);
        ALOGD("amp %.3f -> gain %.1f (live)", amplitude, gain);
        write("vmax", gainToVmax(gain));
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::perform(Effect effect, EffectStrength /*strength*/,
                                     const std::shared_ptr<IVibratorCallback>& callback,
                                     int32_t* _aidl_return) {
    auto t0 = std::chrono::steady_clock::now();
    int32_t lengthMs;
    {
        std::lock_guard<std::mutex> lock(mLock);
        refreshParams();
        lengthMs = mParams.performMs;
        mGeneration++;
        mOnActive = false;
        ALOGD("perform %d", static_cast<int>(effect));
        // Identical to the stock HAL so these keep their current feel.
        switch (effect) {
            case Effect::CLICK: playRam(1, 2500, 0, true); break;
            case Effect::DOUBLE_CLICK:
                playRam(1, 2500, 0, true);
                usleep(100 * 1000);
                playRam(1, 2500, 0, true);
                break;
            case Effect::TICK: playRam(1, 1400, 0, true); break;
            case Effect::HEAVY_CLICK: playRam(4, 2500, 0, true); break;
            case Effect::TEXTURE_TICK: playRam(2, 60, 0, true); break;
            default: return unsupported();
        }
    }
    // The writes above already waited for the waveform (stock tail stop); report the rest.
    auto elapsed = std::chrono::steady_clock::now() - t0;
    auto remaining = std::chrono::milliseconds(lengthMs) - elapsed;
    if (callback) {
        std::thread([callback, remaining] {
            if (remaining.count() > 0) std::this_thread::sleep_for(remaining);
            callback->onComplete();
        }).detach();
    }
    *_aidl_return = lengthMs;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::getSupportedEffects(std::vector<Effect>* _aidl_return) {
    *_aidl_return = {Effect::CLICK, Effect::DOUBLE_CLICK, Effect::TICK, Effect::HEAVY_CLICK,
                     Effect::TEXTURE_TICK};
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::setExternalControl(bool /*enabled*/) {
    return unsupported();
}

ndk::ScopedAStatus Vibrator::getCompositionDelayMax(int32_t* _aidl_return) {
    *_aidl_return = kCompositionDelayMaxMs;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::getCompositionSizeMax(int32_t* _aidl_return) {
    *_aidl_return = kCompositionSizeMax;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::getSupportedPrimitives(std::vector<CompositePrimitive>* _aidl_return) {
    *_aidl_return = {CompositePrimitive::NOOP, CompositePrimitive::CLICK, CompositePrimitive::THUD,
                     CompositePrimitive::LIGHT_TICK, CompositePrimitive::LOW_TICK};
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::getPrimitiveDuration(CompositePrimitive primitive,
                                                  int32_t* _aidl_return) {
    std::lock_guard<std::mutex> lock(mLock);
    if (primitive == CompositePrimitive::NOOP) {
        *_aidl_return = 0;
        return ndk::ScopedAStatus::ok();
    }
    const Prim* p = primFor(primitive);
    if (!p) return unsupported();
    *_aidl_return = primitive == CompositePrimitive::LOW_TICK ? kLowTickReportMs : waveformMs(p->wf);
    return ndk::ScopedAStatus::ok();
}

void Vibrator::playPrimitive(const CompositeEffect& e) {
    const Prim* p = primFor(e.primitive);
    if (!p || e.scale <= 0.f) return;
    float s = std::clamp(e.scale, 0.f, 1.f);
    float gain = p->gmin + (p->gmax - p->gmin) * std::pow(s, p->gamma);
    ALOGD("primitive %d scale %.3f -> wf %d level %d gain %.1f", static_cast<int>(e.primitive),
          e.scale, p->wf, p->level, gain);
    playRam(p->wf, p->level, gain, mParams.tailStop);
}

ndk::ScopedAStatus Vibrator::compose(const std::vector<CompositeEffect>& composite,
                                     const std::shared_ptr<IVibratorCallback>& callback) {
    if (composite.empty() || composite.size() > kCompositionSizeMax) return illegal();
    for (const auto& e : composite) {
        if (e.delayMs < 0 || e.delayMs > kCompositionDelayMaxMs) return illegal();
        if (e.scale < 0.f || e.scale > 1.f) return illegal();
        if (e.primitive != CompositePrimitive::NOOP && !primFor(e.primitive)) return unsupported();
    }
    uint64_t gen;
    {
        std::lock_guard<std::mutex> lock(mLock);
        refreshParams();
        gen = ++mGeneration;
        mOnActive = false;
    }
    std::thread([this, composite, callback, gen] {
        const CompositeEffect* prev = nullptr;
        for (const auto& e : composite) {
            if (e.delayMs > 0) std::this_thread::sleep_for(std::chrono::milliseconds(e.delayMs));
            int32_t len = 0;
            {
                std::lock_guard<std::mutex> lock(mLock);
                if (gen != mGeneration) break;  // off() or a newer vibration took over
                bool repeat = prev && e.delayMs == 0 && e.primitive == prev->primitive &&
                              std::fabs(e.scale - prev->scale) < 0.01f;
                prev = &e;
                if (repeat && mParams.coalesce) continue;  // one tick per slider step
                auto t0 = std::chrono::steady_clock::now();
                playPrimitive(e);
                const Prim* p = primFor(e.primitive);
                // With the tail stop the driver already waited for the waveform to finish.
                len = (p && !mParams.tailStop) ? waveformMs(p->wf) : 0;
                if (mParams.log) {
                    auto us = std::chrono::duration_cast<std::chrono::microseconds>(
                            std::chrono::steady_clock::now() - t0).count();
                    ALOGD("  writes took %lld us", static_cast<long long>(us));
                }
            }
            if (len > 0) std::this_thread::sleep_for(std::chrono::milliseconds(len));
        }
        if (callback) callback->onComplete();
    }).detach();
    return ndk::ScopedAStatus::ok();
}

// ---- not supported (same as stock) ---------------------------------------------------------

ndk::ScopedAStatus Vibrator::getSupportedAlwaysOnEffects(std::vector<Effect>* /*_aidl_return*/) {
    return unsupported();
}
ndk::ScopedAStatus Vibrator::alwaysOnEnable(int32_t, Effect, EffectStrength) { return unsupported(); }
ndk::ScopedAStatus Vibrator::alwaysOnDisable(int32_t) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getResonantFrequency(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getQFactor(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getFrequencyResolution(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getFrequencyMinimum(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getBandwidthAmplitudeMap(std::vector<float>*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getPwlePrimitiveDurationMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getPwleCompositionSizeMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getSupportedBraking(std::vector<Braking>*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::composePwle(const std::vector<PrimitivePwle>&,
                                         const std::shared_ptr<IVibratorCallback>&) {
    return unsupported();
}

}  // namespace aidl::android::hardware::vibrator
