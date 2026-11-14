/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/ActivePwle.aidl
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
#ifdef BINDER_STABILITY_SUPPORT
#include <android/binder_stability.h>
#endif  // BINDER_STABILITY_SUPPORT

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
class ActivePwle {
public:
  typedef std::false_type fixed_size;
  static const char* descriptor;

  float startAmplitude = 0.000000f;
  float startFrequency = 0.000000f;
  float endAmplitude = 0.000000f;
  float endFrequency = 0.000000f;
  int32_t duration = 0;

  binder_status_t readFromParcel(const AParcel* parcel);
  binder_status_t writeToParcel(AParcel* parcel) const;

  inline bool operator==(const ActivePwle& _rhs) const {
    return std::tie(startAmplitude, startFrequency, endAmplitude, endFrequency, duration) == std::tie(_rhs.startAmplitude, _rhs.startFrequency, _rhs.endAmplitude, _rhs.endFrequency, _rhs.duration);
  }
  inline bool operator<(const ActivePwle& _rhs) const {
    return std::tie(startAmplitude, startFrequency, endAmplitude, endFrequency, duration) < std::tie(_rhs.startAmplitude, _rhs.startFrequency, _rhs.endAmplitude, _rhs.endFrequency, _rhs.duration);
  }
  inline bool operator!=(const ActivePwle& _rhs) const {
    return !(*this == _rhs);
  }
  inline bool operator>(const ActivePwle& _rhs) const {
    return _rhs < *this;
  }
  inline bool operator>=(const ActivePwle& _rhs) const {
    return !(*this < _rhs);
  }
  inline bool operator<=(const ActivePwle& _rhs) const {
    return !(_rhs < *this);
  }

  static const ::ndk::parcelable_stability_t _aidl_stability = ::ndk::STABILITY_VINTF;
  inline std::string toString() const {
    std::ostringstream _aidl_os;
    _aidl_os << "ActivePwle{";
    _aidl_os << "startAmplitude: " << ::android::internal::ToString(startAmplitude);
    _aidl_os << ", startFrequency: " << ::android::internal::ToString(startFrequency);
    _aidl_os << ", endAmplitude: " << ::android::internal::ToString(endAmplitude);
    _aidl_os << ", endFrequency: " << ::android::internal::ToString(endFrequency);
    _aidl_os << ", duration: " << ::android::internal::ToString(duration);
    _aidl_os << "}";
    return _aidl_os.str();
  }
};
}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
