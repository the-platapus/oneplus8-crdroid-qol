/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/IVibratorCallback.aidl
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
#ifdef BINDER_STABILITY_SUPPORT
#include <android/binder_stability.h>
#endif  // BINDER_STABILITY_SUPPORT

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
class IVibratorCallbackDelegator;

class IVibratorCallback : public ::ndk::ICInterface {
public:
  typedef IVibratorCallbackDelegator DefaultDelegator;
  static const char* descriptor;
  IVibratorCallback();
  virtual ~IVibratorCallback();

  static inline const int32_t version = 2;
  static inline const std::string hash = "ea8742d6993e1a82917da38b9938e537aa7fcb54";
  static constexpr uint32_t TRANSACTION_onComplete = FIRST_CALL_TRANSACTION + 0;

  static std::shared_ptr<IVibratorCallback> fromBinder(const ::ndk::SpAIBinder& binder);
  static binder_status_t writeToParcel(AParcel* parcel, const std::shared_ptr<IVibratorCallback>& instance);
  static binder_status_t readFromParcel(const AParcel* parcel, std::shared_ptr<IVibratorCallback>* instance);
  static bool setDefaultImpl(const std::shared_ptr<IVibratorCallback>& impl);
  static const std::shared_ptr<IVibratorCallback>& getDefaultImpl();
  virtual ::ndk::ScopedAStatus onComplete() = 0;
  virtual ::ndk::ScopedAStatus getInterfaceVersion(int32_t* _aidl_return) = 0;
  virtual ::ndk::ScopedAStatus getInterfaceHash(std::string* _aidl_return) = 0;
private:
  static std::shared_ptr<IVibratorCallback> default_impl;
};
class IVibratorCallbackDefault : public IVibratorCallback {
public:
  ::ndk::ScopedAStatus onComplete() override;
  ::ndk::ScopedAStatus getInterfaceVersion(int32_t* _aidl_return) override;
  ::ndk::ScopedAStatus getInterfaceHash(std::string* _aidl_return) override;
  ::ndk::SpAIBinder asBinder() override;
  bool isRemote() override;
};
}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
