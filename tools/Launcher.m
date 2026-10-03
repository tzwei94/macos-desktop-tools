#import <Cocoa/Cocoa.h>
#import "../apps/displaylink-toggle/src/DisplayLinkController.h"

@interface ToolDelegate : NSObject <NSApplicationDelegate>
@end

@implementation ToolDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Desktop Tool";
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:name];
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name] action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [menu addItem:appItem];
    NSApp.mainMenu = menu;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"io.github.tzwei94.DisplayLinkToggle"]) {
            ToggleDisplayLinkManager(@"com.displaylink.DisplayLinkUserAgent", ^(NSString *errorMessage) {
                if (errorMessage) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Could not toggle DisplayLink";
                    alert.informativeText = errorMessage;
                    [alert runModal];
                }
                [NSApp terminate:nil];
            });
            return;
        }
        NSURL *url = [NSBundle.mainBundle URLForResource:@"main" withExtension:@"scpt" subdirectory:@"Scripts"];
        NSDictionary *error = nil;
        NSAppleScript *script = url ? [[NSAppleScript alloc] initWithContentsOfURL:url error:&error] : nil;
        if (script) { [script executeAndReturnError:&error]; }
        if (!script || error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [@"Could not open " stringByAppendingString:name];
            alert.informativeText = error[NSAppleScriptErrorMessage] ?: @"The app is missing its bundled script. Download the complete app again.";
            [alert runModal];
        }
        [NSApp terminate:nil];
    });
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        static ToolDelegate *delegate;
        delegate = [[ToolDelegate alloc] init];
        NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
