#import <UIKit/UIKit.h>
#import "UnityAppController.h"
#include <stdint.h>

extern "C" int32_t ICNativeInitialize(const void *window, const uint8_t *bytes, int32_t length);

// Only installed by the development-build postprocessor. Uses Unity's explicit
// window accessor, never a search for a key window or a guessed view hierarchy.
extern "C" int32_t ICUnityInitialize(const uint8_t *bytes, int32_t length)
{
    if (![NSThread isMainThread]) return 0;
    UIWindow *window = UnityGetMainWindow();
    if (!window) return 0;
    return ICNativeInitialize((__bridge const void *)window, bytes, length);
}
