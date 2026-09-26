#import <UIKit/UIKit.h>

// Standalone ABI fixture only: the real Unity export supplies this accessor.
UIWindow *UnityGetMainWindow(void);
extern "C" void ICFixtureSetWindow(UIWindow *window);
