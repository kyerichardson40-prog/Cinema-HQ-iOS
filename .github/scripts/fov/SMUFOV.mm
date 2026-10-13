#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <atomic>
#include <cstring>
#include "SMUFOVPolicy.h"

@interface UIView (SMUGameGLSelectors)
- (void)prepare;
@end

static uintptr_t GameBase;
static void (*OriginalPrepare)(id,SEL);
static void (*OriginalLayout)(id,SEL);
static std::atomic<float> SelectedDegrees(60.0f);
static __weak UIView *GameView;
static uintptr_t LastCamera;
static SMUFOVState CameraState={};
static NSString *const PreferenceKey=@"SMUFieldOfViewDegrees";

static bool Matches(uintptr_t at,const unsigned char *bytes,size_t size) {
    return std::memcmp(reinterpret_cast<const void *>(at),bytes,size)==0;
}
static void *HUD(void) {
    void *manager=*reinterpret_cast<void **>(GameBase+0x1bbf6c0);
    if (!manager) return nullptr;
    // Native libc++ short-string layout, observed at the existing menu_HUD call:
    // inline bytes at 0, length at 23. This avoids linking a foreign string ABI.
    alignas(8) unsigned char key[24]={0};std::memcpy(key,"menu_HUD",8);key[23]=8;
    auto lookup=reinterpret_cast<void *(*)(void *,const void *)>(GameBase+0x148d18);
    return lookup(manager,key);
}
static bool VisibleHUD(void *hud) {
    if (!hud) return false;
    auto visible=reinterpret_cast<bool (*)(void *)>(GameBase+0xd07c80);
    return visible(reinterpret_cast<unsigned char *>(hud)+0x20);
}
static bool PauseVisible(void *hud) {
    if (!VisibleHUD(hud)) return false;
    auto visible=reinterpret_cast<bool (*)(void *)>(GameBase+0x3a0cb0);
    return visible(hud);
}
static uintptr_t GameplayCamera(void) {
    auto scene=*reinterpret_cast<uintptr_t *>(GameBase+0x1bbf1a0);
    if (!scene) return 0;
    auto camera=*reinterpret_cast<uintptr_t *>(scene+0x208);
    if (!camera) return 0;
    // Only the concrete gameplay camera constructed at 0x22cbf0 is eligible.
    // Collada and menu cameras have different tables/names and are never written.
    if (*reinterpret_cast<uintptr_t *>(camera)!=GameBase+0x18d6ce0) return 0;
    if (*reinterpret_cast<unsigned char *>(camera+0x37)!=13 ||
        std::memcmp(reinterpret_cast<const void *>(camera+0x20),"camera-object",14)!=0) return 0;
    return camera;
}
static void ApplyFOV(void) {
    if (!GameBase || !NSThread.isMainThread) return;
    try {
        uintptr_t camera=GameplayCamera();
        // Keep only numeric history while another camera is active. Never dereference
        // the inactive object; restore its native FOV if it later becomes active again.
        if (!camera) return;
        if (camera!=LastCamera) { LastCamera=camera;CameraState={}; }
        float current=*reinterpret_cast<float *>(camera+0x188),next=current;
        if (SMUFOVNext(&CameraState,current,SelectedDegrees.load(),VisibleHUD(HUD()),&next)) {
            // Native setter updates the projection dirty flag, retaining native culling.
            auto setFOV=reinterpret_cast<void (*)(void *,float)>(GameBase+0xfe31c0);
            setFOV(reinterpret_cast<void *>(camera),next);
        }
    } catch (...) { /* Keep normal rendering if the UI subsystem is transitioning. */ }
}

@interface SMUFOVController : NSObject
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UIButton *reset;
@property(nonatomic,strong) NSTimer *timer;
- (void)tick:(NSTimer *)timer;
- (void)attach:(UIView *)view;
@end
static SMUFOVController *Controller;
@implementation SMUFOVController
- (instancetype)init {
    self=[super init];if (!self) return nil;
    _panel=[[UIView alloc] initWithFrame:CGRectZero];_panel.hidden=YES;
    _panel.backgroundColor=[UIColor colorWithWhite:0.06 alpha:0.96];
    _panel.layer.borderWidth=2;_panel.layer.borderColor=UIColor.whiteColor.CGColor;
    _panel.layer.cornerRadius=10;
    _label=[[UILabel alloc] initWithFrame:CGRectZero];_label.textColor=UIColor.whiteColor;
    _label.font=[UIFont boldSystemFontOfSize:16];[_panel addSubview:_label];
    _slider=[[UISlider alloc] initWithFrame:CGRectZero];_slider.minimumValue=45;_slider.maximumValue=100;
    _slider.value=SelectedDegrees.load();_slider.minimumTrackTintColor=UIColor.systemRedColor;
    _slider.exclusiveTouch=YES;
    [_slider addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_panel addSubview:_slider];
    _reset=[UIButton buttonWithType:UIButtonTypeSystem];[_reset setTitle:@"RESET" forState:UIControlStateNormal];
    [_reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];_reset.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    _reset.backgroundColor=UIColor.systemRedColor;_reset.layer.cornerRadius=6;_reset.exclusiveTouch=YES;
    [_reset addTarget:self action:@selector(resetFOV:) forControlEvents:UIControlEventTouchUpInside];[_panel addSubview:_reset];
    _timer=[NSTimer timerWithTimeInterval:0.15 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    return self;
}
- (void)attach:(UIView *)view {
    if (_panel.superview!=view) { [_panel removeFromSuperview];[view addSubview:_panel]; }
    const CGFloat width=MIN(390.0,MAX(0.0,view.bounds.size.width-32.0));
    _panel.frame=CGRectMake((view.bounds.size.width-width)/2.0,MAX(0.0,view.bounds.size.height-122.0),width,106.0);
    _label.frame=CGRectMake(14,10,MAX(0.0,width-98),24);
    _reset.frame=CGRectMake(MAX(14.0,width-82),10,68,28);
    _slider.frame=CGRectMake(14,48,MAX(0.0,width-28),42);
}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIView *view=GameView;
    if (!GameBase || !view.window) { _panel.hidden=YES;return; }
    bool paused=false,available=false;
    try { paused=PauseVisible(HUD());available=GameplayCamera()!=0; } catch (...) { paused=false; }
    _panel.hidden=!paused;
    if (paused) {
        [self attach:view];[view bringSubviewToFront:_panel];_slider.enabled=available;
        const int value=(int)SMUClampDegrees(SelectedDegrees.load());
        _label.text=available ? [NSString stringWithFormat:@"FOV (VERTICAL)  %d°",value] : @"FOV CAMERA UNAVAILABLE";
        if (!_slider.tracking) _slider.value=(float)value;
    }
}
- (void)change:(UISlider *)slider {
    const float value=SMUClampDegrees(slider.value);SelectedDegrees.store(value);
    _label.text=[NSString stringWithFormat:@"FOV (VERTICAL)  %d°",(int)value];
    ApplyFOV();
}
- (void)save:(UISlider *)slider {
    (void)slider;[NSUserDefaults.standardUserDefaults setFloat:SelectedDegrees.load() forKey:PreferenceKey];
}
- (void)resetFOV:(UIButton *)button {
    (void)button;SelectedDegrees.store(60.0f);_slider.value=60.0f;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:PreferenceKey];
    ApplyFOV();[self tick:nil];
}
@end

static void Attach(UIView *view) {
    if (!NSThread.isMainThread || !view.window) return;
    GameView=view;
    if (!Controller) Controller=[[SMUFOVController alloc] init];
    [Controller attach:view];
}
static void FOVPrepare(UIView *view,SEL selector) {
    Attach(view);ApplyFOV();OriginalPrepare(view,selector);
}
static void FOVLayout(UIView *view,SEL selector) {
    OriginalLayout(view,selector);Attach(view);
}
static IMP Hook(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector);if (!method) return nullptr;
    IMP original=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
    return original;
}
__attribute__((constructor)) static void InstallSMUFOV(void) {
    @autoreleasepool {
        for (uint32_t i=0;i<_dyld_image_count();i++) {
            const auto *header=_dyld_get_image_header(i);
            if (!header || header->magic!=MH_MAGIC_64) continue;
            const auto *mh=reinterpret_cast<const mach_header_64 *>(header);
            const unsigned char *cursor=reinterpret_cast<const unsigned char *>(mh)+sizeof(*mh);
            bool uuidMatch=false;
            const unsigned char wanted[16]={0x13,0x5e,0x4f,0x28,0x1c,0xb4,0x3e,0xf3,0xb9,0x1d,0x53,0x5b,0xf2,0x91,0x40,0x9f};
            for (uint32_t j=0;j<mh->ncmds;j++) {
                auto *cmd=reinterpret_cast<const load_command *>(cursor);
                if (cmd->cmd==LC_UUID) uuidMatch=std::memcmp(reinterpret_cast<const uuid_command *>(cmd)->uuid,wanted,16)==0;
                cursor+=cmd->cmdsize;
            }
            if (uuidMatch) { GameBase=reinterpret_cast<uintptr_t>(header);break; }
        }
        if (!GameBase) return;
        const unsigned char setter[]={0x00,0x88,0x01,0xbd,0x08,0x40,0x47,0x79};
        const unsigned char pause[]={0xff,0x83,0x03,0xd1,0xf4,0x4f,0x0c,0xa9};
        const unsigned char lookup[]={0xf6,0x57,0xbd,0xa9,0xf4,0x4f,0x01,0xa9};
        if (!Matches(GameBase+0xfe31c0,setter,sizeof(setter)) || !Matches(GameBase+0x3a0cb0,pause,sizeof(pause)) ||
            !Matches(GameBase+0x148d18,lookup,sizeof(lookup))) { GameBase=0;return; }
        Class cls=objc_getClass("MainGLView");if (!cls) { GameBase=0;return; }
        Method prepare=class_getInstanceMethod(cls,@selector(prepare));
        Method layout=class_getInstanceMethod(cls,@selector(layoutSubviews));
        if (!prepare || !layout || reinterpret_cast<uintptr_t>(method_getImplementation(prepare))!=GameBase+0xe56790) { GameBase=0;return; }
        id stored=[NSUserDefaults.standardUserDefaults objectForKey:PreferenceKey];
        if ([stored respondsToSelector:@selector(floatValue)]) SelectedDegrees.store(SMUClampDegrees([stored floatValue]));
        OriginalPrepare=(void(*)(id,SEL))Hook(cls,@selector(prepare),(IMP)FOVPrepare);
        OriginalLayout=(void(*)(id,SEL))Hook(cls,@selector(layoutSubviews),(IMP)FOVLayout);
    }
}
