#pragma once

#include <aidl/android/hardware/vibrator/BnVibrator.h>

#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace aidl::android::hardware::vibrator {

class Vibrator : public BnVibrator {
  public:
    // One primitive: RAM waveform, boost level, gain range and curve. See Vibrator.cpp.
    struct Prim {
        int wf;
        int level;
        float gmin;
        float gmax;
        float gamma;
    };
    struct Params {
        // Defaults. TICK at scale 1.0 equals the stock EFFECT_TICK (waveform 1, level 1400).
        Prim click{1, 2500, 48.f, 128.f, 1.0f};
        Prim tick{1, 1400, 24.f, 100.f, 1.0f};
        Prim lowtick{2, 1400, 20.f, 42.f, 1.0f};  // flattened 2026-11-12: volume felt harder
        Prim thud{4, 2500, 48.f, 128.f, 1.0f};
        float ampGainMax = 117.f;  // 0x75, the driver's cap for on() (RTP) playback
        float ampGamma = 1.0f;
        int shortMs = 20;
        bool log = false;
        bool coalesce = true;   // play a run of identical zero-delay primitives once
        bool tailStop = false;  // stock trailing 'rtp 0' (driver busy-waits) for primitives
        int performMs = 20;     // reported length of prebaked effects (stock: 150)
    };

    Vibrator();

    ndk::ScopedAStatus getCapabilities(int32_t* _aidl_return) override;
    ndk::ScopedAStatus off() override;
    ndk::ScopedAStatus on(int32_t timeoutMs,
                          const std::shared_ptr<IVibratorCallback>& callback) override;
    ndk::ScopedAStatus perform(Effect effect, EffectStrength strength,
                               const std::shared_ptr<IVibratorCallback>& callback,
                               int32_t* _aidl_return) override;
    ndk::ScopedAStatus getSupportedEffects(std::vector<Effect>* _aidl_return) override;
    ndk::ScopedAStatus setAmplitude(float amplitude) override;
    ndk::ScopedAStatus setExternalControl(bool enabled) override;
    ndk::ScopedAStatus getCompositionDelayMax(int32_t* _aidl_return) override;
    ndk::ScopedAStatus getCompositionSizeMax(int32_t* _aidl_return) override;
    ndk::ScopedAStatus getSupportedPrimitives(
            std::vector<CompositePrimitive>* _aidl_return) override;
    ndk::ScopedAStatus getPrimitiveDuration(CompositePrimitive primitive,
                                            int32_t* _aidl_return) override;
    ndk::ScopedAStatus compose(const std::vector<CompositeEffect>& composite,
                               const std::shared_ptr<IVibratorCallback>& callback) override;
    ndk::ScopedAStatus getSupportedAlwaysOnEffects(std::vector<Effect>* _aidl_return) override;
    ndk::ScopedAStatus alwaysOnEnable(int32_t id, Effect effect,
                                      EffectStrength strength) override;
    ndk::ScopedAStatus alwaysOnDisable(int32_t id) override;
    ndk::ScopedAStatus getResonantFrequency(float* _aidl_return) override;
    ndk::ScopedAStatus getQFactor(float* _aidl_return) override;
    ndk::ScopedAStatus getFrequencyResolution(float* _aidl_return) override;
    ndk::ScopedAStatus getFrequencyMinimum(float* _aidl_return) override;
    ndk::ScopedAStatus getBandwidthAmplitudeMap(std::vector<float>* _aidl_return) override;
    ndk::ScopedAStatus getPwlePrimitiveDurationMax(int32_t* _aidl_return) override;
    ndk::ScopedAStatus getPwleCompositionSizeMax(int32_t* _aidl_return) override;
    ndk::ScopedAStatus getSupportedBraking(std::vector<Braking>* _aidl_return) override;
    ndk::ScopedAStatus composePwle(const std::vector<PrimitivePwle>& composite,
                                   const std::shared_ptr<IVibratorCallback>& callback) override;

  private:
    int write(const char* node, const std::string& value);
    int write(const char* node, int value);
    void playRam(int waveform, int level, float gain, bool tailStop);
    void playPrimitive(const CompositeEffect& e);
    void refreshParams();
    const Prim* primFor(CompositePrimitive p) const;
    float onGain(int32_t timeoutMs, float amplitude) const;

    std::mutex mLock;  // guards everything below and serializes sysfs writes
    Params mParams;
    bool mParamsLoaded = false;
    std::chrono::steady_clock::time_point mParamsTime;
    uint64_t mGeneration = 0;
    float mAmplitude = 1.0f;
    bool mOnActive = false;
    int32_t mOnTimeoutMs = 0;
};

}  // namespace aidl::android::hardware::vibrator
