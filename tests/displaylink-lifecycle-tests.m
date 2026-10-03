#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <notify.h>
#import "../apps/displaylink-toggle/src/DisplayLinkController.h"

static NSString *const FixtureID = @"io.github.tzwei94.DisplayLinkLifecycleFixture";

@interface FixtureDelegate : NSObject <NSApplicationDelegate>
@property BOOL userRequestedQuit;
@end
@implementation FixtureDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    // Require the vendor-specific user quit signal before allowing shutdown.
    return self.userRequestedQuit ? NSTerminateNow : NSTerminateCancel;
}
@end

static NSUInteger launchCount(NSString *path) {
    NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return log ? [log componentsSeparatedByString:@"launch\n"].count - 1 : 0;
}

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); }
}

static void toggle(NSString *identifier, BOOL expectError) {
    __block BOOL finished = NO;
    __block NSString *reportedError = nil;
    ToggleDisplayLinkManager(identifier, ^(NSString *errorMessage) {
        reportedError = errorMessage;
        finished = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    require(finished, @"Toggle did not complete");
    require((reportedError != nil) == expectError, reportedError ?: @"Expected an error");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:FixtureID]) {
            NSString *path = [NSBundle.mainBundle objectForInfoDictionaryKey:@"LifecycleLogPath"];
            NSMutableData *data = [[NSData dataWithContentsOfFile:path] mutableCopy] ?: [NSMutableData data];
            [data appendData:[@"launch\n" dataUsingEncoding:NSUTF8StringEncoding]];
            require([data writeToFile:path atomically:YES], @"Could not record fixture startup");
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
            FixtureDelegate *delegate = [[FixtureDelegate alloc] init];
            NSApp.delegate = delegate;
            int token = 0;
            require(notify_register_dispatch([FixtureID stringByAppendingString:@".userQuit"].UTF8String,
                &token, dispatch_get_main_queue(), ^(int notificationToken) {
                    (void)notificationToken;
                    delegate.userRequestedQuit = YES;
                    [NSApp terminate:nil];
                }) == NOTIFY_STATUS_OK, @"Fixture could not listen for a quit request");
            [NSApp run];
            return 0;
        }
        require(argc == 2, @"Provide an isolated fixture bundle path");
        NSURL *fixture = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        require(LSRegisterURL((__bridge CFURLRef)fixture, true) == noErr, @"Fixture registration failed");
        NSString *logPath = [[NSBundle bundleWithURL:fixture] objectForInfoDictionaryKey:@"LifecycleLogPath"];
        require([NSRunningApplication runningApplicationsWithBundleIdentifier:FixtureID].count == 0, @"Fixture must start off");
        toggle(@"io.github.tzwei94.MissingDisplayLinkFixture", YES);
        require(launchCount(logPath) == 0, @"Missing-app lookup launched a process");
        toggle(FixtureID, NO);
        require([NSRunningApplication runningApplicationsWithBundleIdentifier:FixtureID].count == 1, @"Off-to-on must launch the app");
        require(launchCount(logPath) == 1, @"Turning on should launch exactly once");
        toggle(FixtureID, NO);
        require([NSRunningApplication runningApplicationsWithBundleIdentifier:FixtureID].count == 0, @"On-to-off must stop the app");
        require(launchCount(logPath) == 1, @"Turning off must not relaunch the app");
        toggle(FixtureID, NO);
        require([NSRunningApplication runningApplicationsWithBundleIdentifier:FixtureID].count == 1, @"A later toggle must turn the app back on");
        toggle(FixtureID, NO);
        require([NSRunningApplication runningApplicationsWithBundleIdentifier:FixtureID].count == 0, @"Final toggle must leave the fixture off");
        require(launchCount(logPath) == 2, @"Repeated toggles unexpectedly restarted the app");
        puts("DisplayLink lifecycle tests passed (missing app, on, vendor user quit, no restart, repeated toggles).");
        return 0;
    }
}
