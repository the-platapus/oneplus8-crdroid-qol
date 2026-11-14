// Registers the OnePlus 8 vibrator HAL as android.hardware.vibrator.IVibrator/default.
#include "Vibrator.h"

#include <android/binder_manager.h>
#include <android/binder_process.h>
#include <android/log.h>

#include <cstdlib>
#include <string>

using aidl::android::hardware::vibrator::Vibrator;

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto vib = ndk::SharedRefBase::make<Vibrator>();
    const std::string instance = std::string(Vibrator::descriptor) + "/default";
    binder_status_t status = AServiceManager_addService(vib->asBinder().get(), instance.c_str());
    if (status != STATUS_OK) {
        __android_log_print(ANDROID_LOG_ERROR, "vibrator-op8", "addService failed: %d", status);
        return EXIT_FAILURE;
    }
    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;  // joinThreadPool never returns
}
