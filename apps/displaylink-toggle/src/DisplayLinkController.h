#import <Cocoa/Cocoa.h>

// The identifier parameter lets lifecycle tests use an isolated app fixture.
void ToggleDisplayLinkManager(NSString *identifier, void (^completion)(NSString *errorMessage));
