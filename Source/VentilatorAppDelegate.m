//
//  VentilatorAppDelegate.m
//  Ventilator
//
//  Copyright Matt Rajca 2011. All rights reserved.
//

#import "VentilatorAppDelegate.h"

#import "smc.h"
#import <sys/sysctl.h>
#import <SecurityInterface/SFAuthorizationView.h>
#import <ServiceManagement/ServiceManagement.h>

@interface VentilatorAppDelegate ()

- (SFAuthorizationView *)authView;

- (void)installDaemon;

@end


@implementation VentilatorAppDelegate {
	SFAuthorizationView *_authView;
	NSTimer *_tempTimer;
}

#define APP_ID CFSTR("com.MattRajca.Ventilator")
#define HAS_LAUNCHED_BEFORE_KEY @"HasLaunchedBefore"
#define MARGIN 14.0f

NSString *GetModelString(void);

@synthesize maxHDDRPM, authorized, window, hddTempField;

- (void)dealloc {
	[_authView release];
	[_tempTimer release];
	
	self.window = nil;
	self.hddTempField = nil;
	
	[super dealloc];
}

NSString *GetModelString(void) {
	// Adapted from http://www.cocoadev.com/index.pl?HowToGetHardwareAndNetworkInfo
	NSString *modelString = nil;
	
	int modelInfo[2] = { CTL_HW, HW_MODEL };
	size_t modelSize;
	
	if (sysctl(modelInfo, 2, NULL, &modelSize, NULL, 0) == 0) {
		void *modelData = malloc(modelSize);
		
		if (modelData) {
			if (sysctl(modelInfo, 2, modelData, &modelSize, NULL, 0) == 0) {
				modelString = [NSString stringWithUTF8String:modelData];
			}
			
			free(modelData);
		}
	}
	
	return modelString;
}

- (id)init {
	self = [super init];
	if (self) {
		self.maxHDDRPM = 1500;
	}
	return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	if (![GetModelString() rangeOfString:@"iMac"].length) {
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.5f * NSEC_PER_SEC);
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
			NSRunAlertPanel(@"Unsupported Configuration",
							@"Ventilator currently only runs on Intel-based iMacs.",
							@"Quit", nil, nil);
			
			[NSApp terminate:nil];
		});
		
		return;
	}
	
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	
	if (![defs boolForKey:HAS_LAUNCHED_BEFORE_KEY]) {
		NSInteger result;
		result = NSRunAlertPanel(@"Warning",
								 @"This software was written in my spare time to fill a personal "
								 @"need and was not tested on a wide range of hardware. "
								 @"I am not responsible for any damage Ventilator does to "
								 @"your computer.", @"Install Background Daemon", @"Quit", nil);
		
		if (result == NSAlertAlternateReturn) {
			[NSApp terminate:nil];
			return;
		}
		
		[defs setBool:YES forKey:HAS_LAUNCHED_BEFORE_KEY];
	}
	
	[self.window makeKeyAndOrderFront:nil];
	
	[self installDaemon];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

- (void)applicationDidResignActive:(NSNotification *)notification {
	[_tempTimer release];
	_tempTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	_tempTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0f
												   target:self
												 selector:@selector(tempTick:)
												 userInfo:nil
												  repeats:YES] retain];
}

- (void)awakeFromNib {
	NSView *contentView = [self.window contentView];
	[contentView addSubview:[self authView]];
	
	CFNumberRef boxedValue = (CFNumberRef) CFPreferencesCopyValue(CFSTR("MaxHDDRPM"), APP_ID,
																  kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
	
	if (boxedValue == NULL)
		return;
	
	int value;
	CFNumberGetValue(boxedValue, kCFNumberIntType, &value);
	CFRelease(boxedValue);
	
	self.maxHDDRPM = value;
}

- (SFAuthorizationView *)authView {
	if (!_authView) {
		CGFloat width = [[self.window contentView] frame].size.width;
		
		_authView = [[SFAuthorizationView alloc] initWithFrame:NSMakeRect(MARGIN, MARGIN, width - MARGIN * 2, 60.0f)];
		[_authView setString:kAuthorizationRightExecute];
		[_authView setDelegate:self];
		[_authView updateStatus:nil];
	}
	
	return _authView;
}

- (void)authorizationViewDidAuthorize:(SFAuthorizationView *)view {
	self.authorized = YES;
}

- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view {
	self.authorized = NO;
}

- (IBAction)adjustMaxHDDRPM:(id)sender {
	[[self class] cancelPreviousPerformRequestsWithTarget:self];
	[self performSelector:@selector(updateMaxHDDRPM) withObject:nil afterDelay:0.5f];
}

- (void)updateMaxHDDRPM {
	CFNumberRef boxedValue = CFNumberCreate(NULL, kCFNumberIntType, &maxHDDRPM);
	
	CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
	CFDictionarySetValue(dict, CFSTR("MaxHDDRPM"), boxedValue);
	CFRelease(boxedValue);
	
	CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
	CFNotificationCenterPostNotificationWithOptions(center, CFSTR("com.MattRajca.Ventilator.SettingsChanged"),
													NULL, dict, kCFNotificationPostToAllSessions);
	
	CFRelease(dict);
}

- (void)tempTick:(id)sender {
	if (![window isVisible])
		return;
	
	SMCOpen();
	double temp = SMCGetTemperature(SMC_KEY_HD_TEMP);
	SMCClose();
	
	if (temp == 0) {
		[self.hddTempField setStringValue:@"Unavailable"];
		return;
	}
	
	[self.hddTempField setIntValue:temp * 9 / 5 + 32.0f]; // convert to fahrenheit
}

- (void)installDaemon {
	CFStringRef jobLabel = CFSTR("com.MattRajca.VentilatorDaemon");
	NSDictionary *jobDict = (NSDictionary *) SMJobCopyDictionary(kSMDomainSystemLaunchd, jobLabel);
	
	if (jobDict) {
		[jobDict release];
		return;
	}
	
	AuthorizationRef auth;
	OSStatus result = AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, &auth);
	
	if (result != noErr) {
		NSLog(@"Error creating the auth object");
		return;
	}
	
	AuthorizationItem item;
	item.name = kSMRightBlessPrivilegedHelper;
	item.valueLength = item.flags = 0;
	item.value = NULL;
	
	AuthorizationRights requestedRights;
	requestedRights.count = 1;
	requestedRights.items = &item;
	
	result = AuthorizationCopyRights(auth, &requestedRights, kAuthorizationEmptyEnvironment,
									 kAuthorizationFlagDefaults | kAuthorizationFlagExtendRights | 
									 kAuthorizationFlagInteractionAllowed, NULL);
	
	if (result != noErr) {
		NSLog(@"Could not acquire the requisite rights");
		AuthorizationFree(auth, kAuthorizationFlagDefaults);
		[NSApp terminate:nil];
		return;
	}
	
	CFErrorRef error = NULL;
	BOOL blessed = SMJobBless(kSMDomainSystemLaunchd, jobLabel, auth, &error);
	AuthorizationFree(auth, kAuthorizationFlagDefaults);
	
	if (!blessed) {
		NSLog(@"Failed to bless the helper");
		[NSApp presentError: (NSError *) error];
		[NSApp terminate:nil];
		return;
	}
	
	[self adjustMaxHDDRPM:nil];
}

@end
