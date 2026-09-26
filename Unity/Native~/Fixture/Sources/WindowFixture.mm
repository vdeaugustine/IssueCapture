#import "UnityAppController.h"

static __weak UIWindow *fixtureWindow;
UIWindow *UnityGetMainWindow(void) { return fixtureWindow; }
extern "C" void ICFixtureSetWindow(UIWindow *window) { fixtureWindow = window; }
