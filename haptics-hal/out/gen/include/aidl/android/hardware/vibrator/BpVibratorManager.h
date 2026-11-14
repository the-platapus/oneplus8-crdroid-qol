/*
 * This file is auto-generated.  DO NOT MODIFY.
 * Using: /home/abdul/Android/Sdk/build-tools/36.0.0/aidl --lang=ndk --structured --stability=vintf --version=2 --hash=ea8742d6993e1a82917da38b9938e537aa7fcb54 --min_sdk_version=35 -I /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl -h /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/include -o /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/out/gen/src /home/abdul/Downloads/1+8/oneplus8-fixes/haptics-hal/third_party/aidl/android/hardware/vibrator/IVibratorManager.aidl
 *
 * DO NOT CHECK THIS FILE INTO A CODE TREE (e.g. git, etc..).
 * ALWAYS GENERATE THIS FILE FROM UPDATED AIDL COMPILER
 * AS A BUILD INTERMEDIATE ONLY. THIS IS NOT SOURCE CODE.
 */
#pragma once

#include "aidl/android/hardware/vibrator/IVibratorManager.h"

#include <android/binder_ibinder.h>

namespace aidl {
namespace android {
namespace hardware {
namespace vibrator {
class BpVibratorManager : public ::ndk::BpCInterface<IVibratorManager> {
public:
  explicit BpVibratorManager(const ::ndk::SpAIBinder& binder);
  virtual ~BpVibratorManager();

  ::ndk::ScopedAStatus getCapabilities(int32_t* _aidl_return) override;
  ::ndk::ScopedAStatus getVibratorIds(std::vector<int32_t>* _aidl_return) override;
  ::ndk::ScopedAStatus getVibrator(int32_t in_vibratorId, std::shared_ptr<::aidl::android::hardware::vibrator::IVibrator>* _aidl_return) override;
  ::ndk::ScopedAStatus prepareSynced(const std::vector<int32_t>& in_vibratorIds) override;
  ::ndk::ScopedAStatus triggerSynced(const std::shared_ptr<::aidl::android::hardware::vibrator::IVibratorCallback>& in_callback) override;
  ::ndk::ScopedAStatus cancelSynced() override;
  ::ndk::ScopedAStatus getInterfaceVersion(int32_t* _aidl_return) override;
  ::ndk::ScopedAStatus getInterfaceHash(std::string* _aidl_return) override;
  int32_t _aidl_cached_version = -1;
  std::string _aidl_cached_hash = "-1";
  std::mutex _aidl_cached_hash_mutex;
};
}  // namespace vibrator
}  // namespace hardware
}  // namespace android
}  // namespace aidl
