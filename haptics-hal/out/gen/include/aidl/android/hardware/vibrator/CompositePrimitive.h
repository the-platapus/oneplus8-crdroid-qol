/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/CompositePrimitive.aidl
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
enum class CompositePrimitive : int32_t {
  NOOP = 0,
  CLICK = 1,
  THUD = 2,
  SPIN = 3,
  QUICK_RISE = 4,
  SLOW_RISE = 5,
  QUICK_FALL = 6,
  LIGHT_TICK = 7,
  LOW_TICK = 8,
};

}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
[[nodiscard]] static inline std::string toString(CompositePrimitive val) {
  switch(val) {
  case CompositePrimitive::NOOP:
    return "NOOP";
  case CompositePrimitive::CLICK:
    return "CLICK";
  case CompositePrimitive::THUD:
    return "THUD";
  case CompositePrimitive::SPIN:
    return "SPIN";
  case CompositePrimitive::QUICK_RISE:
    return "QUICK_RISE";
  case CompositePrimitive::SLOW_RISE:
    return "SLOW_RISE";
  case CompositePrimitive::QUICK_FALL:
    return "QUICK_FALL";
  case CompositePrimitive::LIGHT_TICK:
    return "LIGHT_TICK";
  case CompositePrimitive::LOW_TICK:
    return "LOW_TICK";
  default:
    return std::to_string(static_cast<int32_t>(val));
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
constexpr inline std::array<aidl::android::hardware::vibrator::CompositePrimitive, 9> enum_values<aidl::android::hardware::vibrator::CompositePrimitive> = {
  aidl::android::hardware::vibrator::CompositePrimitive::NOOP,
  aidl::android::hardware::vibrator::CompositePrimitive::CLICK,
  aidl::android::hardware::vibrator::CompositePrimitive::THUD,
  aidl::android::hardware::vibrator::CompositePrimitive::SPIN,
  aidl::android::hardware::vibrator::CompositePrimitive::QUICK_RISE,
  aidl::android::hardware::vibrator::CompositePrimitive::SLOW_RISE,
  aidl::android::hardware::vibrator::CompositePrimitive::QUICK_FALL,
  aidl::android::hardware::vibrator::CompositePrimitive::LIGHT_TICK,
  aidl::android::hardware::vibrator::CompositePrimitive::LOW_TICK,
};
#pragma clang diagnostic pop
}  // namespace internal
}  // namespace ndk
