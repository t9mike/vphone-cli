#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

// Loaded only into an isolated vphoned script session. No injected hooks,
// preference changes or persistent daemons. Pose overrides last in SpringBoard
// until explicitly cleared or the guest reboots.
typedef struct { int64_t orientation; int32_t deviceOrientation, hingeState, tabletopPose; } VPPose;

@interface VPStandByProbe : NSObject
+ (NSDictionary *)probeMetadata;
+ (NSDictionary *)setOrientation:(int)orientation hinge:(int)hinge tabletop:(int)tabletop;
+ (NSString *)poseJSONOrientation:(int)orientation hinge:(int)hinge tabletop:(int)tabletop;
@end

@implementation VPStandByProbe
+ (void)loadServices {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW);
}
+ (NSDictionary *)probeMetadata {
    [self loadServices];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"SBSTestAutomationService", @"SBSDisplayToolService", @"CMMagicPoseManager", @"CMDeviceStateEvent"]) {
        Class cls = NSClassFromString(name);
        NSMutableArray *methods = [NSMutableArray array];
        for (int meta = 0; meta < 2; meta++) {
            unsigned count = 0;
            Method *list = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
            for (unsigned i = 0; i < count; i++) {
                NSString *selector = NSStringFromSelector(method_getName(list[i]));
                if ([selector rangeOfString:@"pose" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [selector rangeOfString:@"ambient" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [selector rangeOfString:@"standby" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [selector rangeOfString:@"tabletop" options:NSCaseInsensitiveSearch].location != NSNotFound)
                    [methods addObject:@{@"selector":selector, @"encoding":@(method_getTypeEncoding(list[i])), @"class":@(meta)}];
            }
            free(list);
        }
        result[name] = methods;
    }
    return result;
}
+ (NSDictionary *)setOrientation:(int)orientation hinge:(int)hinge tabletop:(int)tabletop {
    [self loadServices];
    if (orientation < 0 || orientation > 6 || hinge < 0 || hinge > 4 || tabletop < 0 || tabletop > 10)
        return @{@"error":@"out of range"};
    Class cls = NSClassFromString(@"SBSTestAutomationService");
    SEL set = NSSelectorFromString(@"setDevicePoseOverride:");
    SEL get = NSSelectorFromString(@"getDevicePose");
    Method setter = class_getInstanceMethod(cls, set), getter = class_getInstanceMethod(cls, get);
    if (!setter || !getter || strcmp(method_getTypeEncoding(setter), "v40@0:8{?=qiii}16") ||
        strcmp(method_getTypeEncoding(getter), "{?=qiii}16@0:8"))
        return @{@"error":@"unsupported ABI", @"setter": setter ? @(method_getTypeEncoding(setter)) : @"missing"};
    id client = [cls new];
    VPPose pose = {orientation, orientation, hinge, tabletop};
    ((void (*)(id, SEL, VPPose))objc_msgSend)(client, set, pose);
    // Readback proves acceptance of the pose, not that StandBy is visible.
    VPPose actual = {0};
    BOOL applied = NO;
    for (int attempt = 0; attempt < 20; attempt++) {
        actual = ((VPPose (*)(id, SEL))objc_msgSend)(client, get);
        applied = actual.deviceOrientation == orientation && actual.hingeState == hinge && actual.tabletopPose == tabletop;
        if (applied) break;
        [NSThread sleepForTimeInterval:0.1];
    }
    return @{@"orientation":@(actual.orientation), @"device_orientation":@(actual.deviceOrientation),
             @"hinge":@(actual.hingeState), @"tabletop":@(actual.tabletopPose), @"applied":@(applied)};
}
+ (NSString *)poseJSONOrientation:(int)orientation hinge:(int)hinge tabletop:(int)tabletop {
    NSDictionary *result = [self setOrientation:orientation hinge:hinge tabletop:tabletop];
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
@end
