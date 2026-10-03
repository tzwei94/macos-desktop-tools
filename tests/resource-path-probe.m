#import <Cocoa/Cocoa.h>

// Exercise the production script's resource lookup in a real bundle without
// invoking its run handler, which would change the display arrangement.
int main(void) {
    @autoreleasepool {
        NSURL *url = [NSBundle.mainBundle URLForResource:@"main" withExtension:@"scpt" subdirectory:@"Scripts"];
        NSDictionary *error = nil;
        NSAppleScript *script = [[NSAppleScript alloc] initWithContentsOfURL:url error:&error];
        NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:'ascr'
            eventID:'psbr' targetDescriptor:nil returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
        [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"bundledHelperPath"] forKeyword:'snam'];
        NSAppleEventDescriptor *result = [script executeAppleEvent:event error:&error];
        if (!script || error || !result.stringValue) {
            fprintf(stderr, "%s\n", (error.description ?: @"Missing helper path").UTF8String);
            return 1;
        }
        printf("%s\n", result.stringValue.UTF8String);
        return 0;
    }
}
