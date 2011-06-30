//
//  VentilatorAppDelegate.h
//  Ventilator
//
//  Copyright Matt Rajca 2011. All rights reserved.
//

@interface VentilatorAppDelegate : NSObject < NSApplicationDelegate >

@property (nonatomic, assign) int maxHDDRPM;
@property (nonatomic, assign) BOOL authorized;

@property (nonatomic, retain) IBOutlet NSWindow *window;
@property (nonatomic, retain) IBOutlet NSTextField *hddTempField;

- (IBAction)adjustMaxHDDRPM:(id)sender;

@end
