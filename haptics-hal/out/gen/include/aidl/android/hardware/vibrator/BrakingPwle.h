/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/BrakingPwle.aidl
 *
 * DO NOT CHECK THIS FILE INTO A CODE TREE (e.g. git, etc..).
 * ALWAYS GENERATE THIS FILE FROM UPDATED AIDL COMPILER
 * AS A BUILD INTERMEDIATE ONLY. THIS IS NOT SOURCE CODE.
 */
#pragma once

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <android/binder_interface_utils.h>
#include <android/binder_parcelable_utils.h>
#include <android/binder_to_string.h>
#include <aidl/android/hardware/vibrator/Braking.h>
#ifdef BINDER_STABILITY_SUPPORT
#include <android/binder_stability.h>
#endif  // BINDER_STABILITY_SUPPORT

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
class BrakingPwle {
public:
  typedef std::false_type fixed_size;
  static const char* descriptor;

  ::aidl::android::hardware::vibrator::Braking braking = ::aidl::android::hardware::vibrator::Braking(0);
  int32_t duration = 0;

  binder_status_t readFromParcel(const AParcel* parcel);
  binder_status_t writeToParcel(AParcel* parcel) const;

  inline bool operator==(const BrakingPwle& _rhs) const {
    return std::tie(braking, duration) == std::tie(_rhs.braking, _rhs.duration);
  }
  inline bool operator<(const BrakingPwle& _rhs) const {
    return std::tie(braking, duration) < std::tie(_rhs.braking, _rhs.duration);
  }
  inline bool operator!=(const BrakingPwle& _rhs) const {
    return !(*this == _rhs);
  }
  inline bool operator>(const BrakingPwle& _rhs) const {
    return _rhs < *this;
  }
  inline bool operator>=(const BrakingPwle& _rhs) const {
    return !(*this < _rhs);
  }
  inline bool operator<=(const BrakingPwle& _rhs) const {
    return !(_rhs < *this);
  }

  static const ::ndk::parcelable_stability_t _aidl_stability = ::ndk::STABILITY_VINTF;
  inline std::string toString() const {
    std::ostringstream _aidl_os;
    _aidl_os << "BrakingPwle{";
    _aidl_os << "braking: " << ::android::internal::ToString(braking);
    _aidl_os << ", duration: " << ::android::internal::ToString(duration);
    _aidl_os << "}";
    return _aidl_os.str();
  }
};
}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
