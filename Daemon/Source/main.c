//
//  main.c
//  VentilatorDaemon
//
//  Copyright Matt Rajca 2011. All rights reserved.
//

#include <CoreServices/CoreServices.h>

#include "smc.h"
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>

#define APP_ID CFSTR("com.MattRajca.Ventilator")

void SettingsApplier (const void *key, const void *value, void *context);
void UpdateFans (void);
void Callback (CFNotificationCenterRef center, void *observer,
			   CFStringRef name, const void *object, CFDictionaryRef userInfo);
void SystemSleepCallBack (void *refcon, io_service_t service, uint32_t messageType,
						  void *messageArgument);

void SettingsApplier (const void *key, const void *value, void *context) {
	CFPreferencesSetValue(key, value, APP_ID, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
	CFPreferencesSynchronize(APP_ID, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
	
	UpdateFans();
}

void UpdateFans (void) {
	CFNumberRef value = (CFNumberRef) CFPreferencesCopyValue(CFSTR("MaxHDDRPM"), APP_ID,
															 kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
	
	if (value == NULL)
		return;
	
	int maxHDDRPM;
	CFNumberGetValue(value, kCFNumberIntType, &maxHDDRPM);
	CFRelease(value);
	
	SMCOpen();
	SMCSetFanRpm(SMC_KEY_HD_FAN_RPM_MAX, maxHDDRPM);
	SMCClose();
}

void Callback (CFNotificationCenterRef center, void *observer, CFStringRef name,
			   const void *object, CFDictionaryRef userInfo) {
	
	CFDictionaryApplyFunction(userInfo, SettingsApplier, NULL);
}

static IONotificationPortRef port;
static io_object_t notifier;
static io_connect_t root_port;

void SystemSleepCallBack (void *refcon, io_service_t service, uint32_t messageType,
						  void *messageArgument) {
	
    if (messageType == kIOMessageSystemHasPoweredOn) {
		UpdateFans();
	}
	else if (messageType == kIOMessageSystemWillSleep) {
		IOAllowPowerChange(root_port, (long) messageArgument);
	}
	else if (messageType == kIOMessageCanSystemSleep) {
		IOAllowPowerChange(root_port, (long) messageArgument);
	}
}

int main (int argc, const char *argv[]) {
	UpdateFans();
	
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterAddObserver(center, NULL, Callback,
									CFSTR("com.MattRajca.Ventilator.SettingsChanged"), NULL,
									CFNotificationSuspensionBehaviorCoalesce);
	
	root_port = IORegisterForSystemPower(NULL, &port, SystemSleepCallBack, &notifier);
	
	if (root_port != MACH_PORT_NULL) {
		CFRunLoopAddSource(CFRunLoopGetCurrent(),
						   IONotificationPortGetRunLoopSource(port),
						   kCFRunLoopCommonModes);
	}
	
	CFRunLoopRun();
	
	IONotificationPortDestroy(port);
	IOServiceClose(root_port);
	
    return 0;
}
