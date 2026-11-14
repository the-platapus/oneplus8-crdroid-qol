/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/EffectStrength.aidl
 *
 * DO NOT CHECK THIS FILE INTO A CODE TREE (e.g. git, etc..).
 * ALWAYS GENERATE THIS FILE FROM UPDATED AIDL COMPILER
 * AS A BUILD INTERMEDIATE ONLY. THIS IS NOT SOURCE CODE.
 */
#pragma once

#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <android/binder_enums.h>
#ifdef BINDER_STABILITY_SUPPORT
#include <android/binder_stability.h>
#endif  // BINDER_STABILITY_SUPPORT

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
enum class EffectStrength : int8_t {
  LIGHT = 0,
  MEDIUM = 1,
  STRONG = 2,
};

}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
[[nodiscard]] static inline std::string toString(EffectStrength val) {
  switch(val) {
  case EffectStrength::LIGHT:
    return "LIGHT";
  case EffectStrength::MEDIUM:
    return "MEDIUM";
  case EffectStrength::STRONG:
    return "STRONG";
  default:
    return std::to_string(static_cast<int8_t>(val));
  }
}
}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
namespace ndk {
namespace internal {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++17-extensions"
template <>
constexpr inline std::array<aidl::android::hardware::vibrator::EffectStrength, 3> enum_values<aidl::android::hardware::vibrator::EffectStrength> = {
  aidl::android::hardware::vibrator::EffectStrength::LIGHT,
  aidl::android::hardware::vibrator::EffectStrength::MEDIUM,
  aidl::android::hardware::vibrator::EffectStrength::STRONG,
};
#pragma clang diagnostic pop
}  // namespace internal
}  // namespace ndk
