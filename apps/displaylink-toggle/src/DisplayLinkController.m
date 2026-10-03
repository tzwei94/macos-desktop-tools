#import "DisplayLinkController.h"
#import <notify.h>

static void WaitForExit(NSString *identifier, NSDate *deadline, void (^completion)(NSString *)) {
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count == 0) {
        // Verify a settled off state without resolving an AppleScript application
        // object, which can launch the target while resolving it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            BOOL restarted = [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count != 0;
            completion(restarted ? @"DisplayLink Manager restarted after quitting. Another app or service may be reopening it." : nil);
        });
    } else if (deadline.timeIntervalSinceNow <= 0) {
        completion(@"DisplayLink Manager did not finish quitting. Try quitting it from its own menu.");
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{
            WaitForExit(identifier, deadline, completion);
        });
    }
}

void ToggleDisplayLinkManager(NSString *identifier, void (^completion)(NSString *)) {
    NSArray<NSRunningApplication *> *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier];
    if (running.count > 0) {
        // Manager's own user-quit handler stops its restart watchdog before
        // exiting. A generic quit alone is treated as a failure by Manager 17.
        // Fixture identifiers use an isolated name, never the real signal.
        NSString *notificationName = [identifier isEqualToString:@"com.displaylink.DisplayLinkUserAgent"]
            ? @"com.displaylink.DisplayLinkManager.userQuit" : [identifier stringByAppendingString:@".userQuit"];
        if (notify_post(notificationName.UTF8String) != NOTIFY_STATUS_OK) {
            completion(@"Could not send DisplayLink Manager its user quit request.");
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            // Older versions may not listen for the user-quit notification.
            // Only request a normal quit if the app has not already exited.
            for (NSRunningApplication *application in [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier]) {
                if (!application.terminated && ![application terminate] && !application.terminated) {
                    completion(@"Could not ask DisplayLink Manager to quit.");
                    return;
                }
            }
            WaitForExit(identifier, [NSDate dateWithTimeIntervalSinceNow:10], completion);
        });
        return;
    }
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
    if (!url) {
        completion(@"Install a compatible DisplayLink Manager from Synaptics, then open this toggle again. This utility does not include DisplayLink drivers.");
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error ? error.localizedDescription : (application ? nil : @"DisplayLink Manager could not be opened."));
            });
        }];
}
