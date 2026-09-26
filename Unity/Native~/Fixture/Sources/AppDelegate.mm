#import <UIKit/UIKit.h>
#import "UnityAppController.h"
#include <stdint.h>

extern "C" int32_t ICUnityInitialize(const uint8_t *, int32_t);
extern "C" void ICNativeCommand(const uint8_t *, int32_t);
extern "C" int32_t ICNativeBeginCapture(void);
extern "C" void ICNativeFinishCapture(const uint8_t *, int32_t);

static NSString *sessionID;
static NSDictionary *origin;

static void Send(NSDictionary *fields) {
    NSMutableDictionary *command = [fields mutableCopy];
    command[@"session"] = sessionID;
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
    ICNativeCommand((const uint8_t *)data.bytes, (int32_t)data.length);
}

@interface FixtureController : UIViewController
@end
@implementation FixtureController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemTealColor;
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    for (NSString *title in @[@"Capture Boardwalk fixture", @"Saved issues", @"Diagnostics", @"Late outcome after navigation"])
    {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.configuration = UIButtonConfiguration.filledButtonConfiguration;
        [button setTitle:title forState:UIControlStateNormal];
        [button addTarget:self action:@selector(activate:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (sessionID) return;
    ICFixtureSetWindow(self.view.window);
    sessionID = NSUUID.UUID.UUIDString;
    NSDictionary *command = @{@"operation": @"initialize", @"session": sessionID, @"projectID": @"unity-bridge-fixture"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
    int32_t installed = ICUnityInitialize((const uint8_t *)data.bytes, (int32_t)data.length);
    NSLog(@"IssueCapture fixture initialized: %d; legacy window: %d", installed, self.view.window.windowScene == nil);
    origin = @{@"id": NSUUID.UUID.UUIDString, @"parentID": @"", @"stableID": @"scene.boardwalk",
               @"name": @"Boardwalk", @"typeName": @"BoardwalkController", @"file": @"Assets/BoardwalkController.cs", @"line": @42};
    Send(@{@"operation": @"register", @"screen": origin, @"active": @YES});
    Send(@{@"operation": @"record", @"screen": origin, @"category": @"action", @"name": @"boardwalk.ready"});
}
- (void)activate:(UIButton *)button {
    NSString *title = button.currentTitle;
    if ([title isEqualToString:@"Saved issues"]) { Send(@{@"operation": @"inbox"}); return; }
    if ([title isEqualToString:@"Diagnostics"]) { Send(@{@"operation": @"diagnostics"}); return; }
    if ([title isEqualToString:@"Late outcome after navigation"]) {
        NSDictionary *savedOrigin = origin;
        Send(@{@"operation": @"dispose", @"screen": savedOrigin});
        NSMutableDictionary *clean = [origin mutableCopy];
        clean[@"id"] = NSUUID.UUID.UUIDString;
        clean[@"name"] = @"Clean";
        clean[@"stableID"] = @"scene.clean";
        Send(@{@"operation": @"register", @"screen": clean, @"active": @YES});
        origin = clean;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            Send(@{@"operation": @"record", @"screen": savedOrigin, @"category": @"outcome",
                   @"name": @"boardwalk.load_complete", @"result": @"success"});
        });
        return;
    }
    if (!ICNativeBeginCapture()) return;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.view.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:NO];
    }];
    NSData *png = UIImagePNGRepresentation(image);
    ICNativeFinishCapture((const uint8_t *)png.bytes, (int32_t)png.length);
}
@end

@interface FixtureAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation FixtureAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[FixtureController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FixtureAppDelegate.class)); }
}
