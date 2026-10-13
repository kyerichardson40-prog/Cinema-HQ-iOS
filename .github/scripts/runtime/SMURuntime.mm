#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#include <atomic>
#include <algorithm>
#include <cstring>
#include "SMURuntimePolicy.h"
@interface UIView (SMUGameSelectors)
- (void)prepare;
@end
static uintptr_t GameBase;
static void (*OriginalPrepare)(id,SEL);
static void (*OriginalSetFOV)(void *,float);
static std::atomic<float> SelectedDegrees(60.0f);
static __weak UIView *GameView;
static uintptr_t LastCamera;
static float LastAuthoredRadians=1.0471975512f;
static NSString *const PreferenceKey=@"SMUFieldOfViewDegrees";
static NSTimer *UITimer;
static bool Matches(uintptr_t at,const unsigned char *bytes,size_t size) {
 return std::memcmp(reinterpret_cast<const void *>(at),bytes,size)==0;
}
static bool EligibleCamera(uintptr_t camera) {
 return camera && *reinterpret_cast<uintptr_t *>(camera)==GameBase+0x18d6ce0 &&
  *reinterpret_cast<unsigned char *>(camera+0x37)==13 && std::memcmp(reinterpret_cast<void *>(camera+0x20),"camera-object",14)==0;
}
static uintptr_t GameplayCamera(void) {
 auto scene=*reinterpret_cast<uintptr_t *>(GameBase+0x1bbf1a0);if(!scene) return 0;
 auto camera=*reinterpret_cast<uintptr_t *>(scene+0x208);return EligibleCamera(camera) ? camera : 0;
}
__attribute__((noinline)) static void GameplayFOVSetter(void *object,float nativeRadians) {
 uintptr_t caller=reinterpret_cast<uintptr_t>(__builtin_return_address(0));
 bool gameplay=caller==GameBase+0x22d464;
 bool eligible=gameplay && EligibleCamera(reinterpret_cast<uintptr_t>(object));
 if(eligible && isfinite(nativeRadians) && nativeRadians>0.1f && nativeRadians<3.0f) {
  LastCamera=reinterpret_cast<uintptr_t>(object);LastAuthoredRadians=nativeRadians;
 }
 OriginalSetFOV(object,SMUResolveFrameFOV(nativeRadians,SelectedDegrees.load(),gameplay,eligible));
}
static void ImmediateFOV(void) {
 uintptr_t camera=GameplayCamera();if(!camera || camera!=LastCamera) return;
 OriginalSetFOV(reinterpret_cast<void *>(camera),SMUResolveFrameFOV(LastAuthoredRadians,SelectedDegrees.load(),true,true));
}
static void *FindWidget(const char *name) {
 void *manager=*reinterpret_cast<void **>(GameBase+0x1bbf6c0);if(!manager) return nullptr;
 size_t length=std::strlen(name);if(length>22) return nullptr;
 alignas(8) unsigned char key[24]={0};std::memcpy(key,name,length);key[23]=(unsigned char)length;
 auto lookup=reinterpret_cast<void *(*)(void *,const void *)>(GameBase+0x148d18);return lookup(manager,key);
}
static SMUValue Invoke(void *widget,const char *name,const SMUValue *values,unsigned count) {
 if(!widget) return SMUValue{};
 alignas(8) unsigned char key[24]={0};size_t length=std::strlen(name);if(length>22) return SMUValue{};
 std::memcpy(key,name,length);key[23]=(unsigned char)length;
 // The 24-byte return uses AAPCS64 x8 sret, matching MovieClipHandle::Invoke.
 auto invoke=reinterpret_cast<SMUValue (*)(void *,const void *,const SMUValue *,unsigned)>(GameBase+0xd07320);
 return invoke(reinterpret_cast<unsigned char *>(widget)+0x20,key,values,count);
}
static void Dispose(SMUValue *value) {
 auto destroy=reinterpret_cast<void (*)(SMUValue *)>(GameBase+0xd97860);destroy(value);
}
static void TickUI(void) {
 if(!GameBase || !NSThread.isMainThread || !GameView.window) return;
 UIView *view=GameView;UIEdgeInsets insets=view.window.safeAreaInsets;
 double height=view.bounds.size.height;if(height<=0) return;
 double top=std::max(0.0,std::min(0.15,(double)insets.top/height));
 double bottom=std::max(0.0,std::min(0.15,(double)insets.bottom/height));
 try {
  void *hud=FindWidget("menu_HUD");
  if(hud) {
   SMUValue change=Invoke(hud,"SMU_DrainFOV",nullptr,0);
   if(change.tag==2) {
    double value=SMUDecodeNumber(change);
    if(isfinite(value) && value>=45 && value<=100) {
     float selected=SMUClampDegrees((float)value);SelectedDegrees.store(selected);
     if(selected==60) [NSUserDefaults.standardUserDefaults removeObjectForKey:PreferenceKey];
     else [NSUserDefaults.standardUserDefaults setFloat:selected forKey:PreferenceKey];
     ImmediateFOV();
    }
   }
   Dispose(&change);
   SMUValue args[]={SMUNumber(SelectedDegrees.load()),SMUNumber(top),SMUNumber(bottom),SMUNumber(GameplayCamera()!=0 ? 1 : 0)};
   SMUValue result=Invoke(hud,"SMU_Tick",args,4);Dispose(&result);
  }
  void *header=FindWidget("TopBar_Complete");
  if(header) {SMUValue arg=SMUNumber(top);SMUValue result=Invoke(header,"SMU_HeaderInset",&arg,1);Dispose(&result);}
 } catch(...) { /* Retain the game's UI during movie transitions. */ }
}
@interface SMURuntimeTimer : NSObject
- (void)tick:(NSTimer *)timer;
@end
@implementation SMURuntimeTimer
- (void)tick:(NSTimer *)timer {(void)timer;TickUI();}
@end
static SMURuntimeTimer *TimerTarget;
static void RuntimePrepare(UIView *view,SEL selector) {
 if(NSThread.isMainThread && view.window) {
  GameView=view;
  if(!UITimer) {
   TimerTarget=[[SMURuntimeTimer alloc] init];UITimer=[NSTimer timerWithTimeInterval:0.05 target:TimerTarget selector:@selector(tick:) userInfo:nil repeats:YES];
   [NSRunLoop.mainRunLoop addTimer:UITimer forMode:NSRunLoopCommonModes];TickUI();
  }
 }
 OriginalPrepare(view,selector);
}
static bool WritableSlot(uintptr_t slot) {
 mach_vm_address_t address=slot;mach_vm_size_t length=0;vm_region_basic_info_data_64_t info={};
 mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;mach_port_t object=MACH_PORT_NULL;
 kern_return_t result=mach_vm_region(mach_task_self(),&address,&length,VM_REGION_BASIC_INFO_64,reinterpret_cast<vm_region_info_t>(&info),&count,&object);
 if(object!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),object);
 return result==KERN_SUCCESS && address<=slot && slot+sizeof(uintptr_t)<=address+length && (info.protection&VM_PROT_WRITE);
}
__attribute__((constructor)) static void InstallSMURuntime(void) {
 @autoreleasepool {
  const unsigned char wanted[16]={0x13,0x5e,0x4f,0x28,0x1c,0xb4,0x3e,0xf3,0xb9,0x1d,0x53,0x5b,0xf2,0x91,0x40,0x9f};
  for(uint32_t i=0;i<_dyld_image_count();i++) {
   const auto *header=_dyld_get_image_header(i);if(!header || header->magic!=MH_MAGIC_64) continue;
   const auto *mh=reinterpret_cast<const mach_header_64 *>(header);const auto *cursor=reinterpret_cast<const unsigned char *>(mh)+sizeof(*mh);bool match=false;
   for(uint32_t j=0;j<mh->ncmds;j++) {auto *cmd=reinterpret_cast<const load_command *>(cursor);if(cmd->cmd==LC_UUID) match=std::memcmp(reinterpret_cast<const uuid_command *>(cmd)->uuid,wanted,16)==0;cursor+=cmd->cmdsize;}
   if(match) {GameBase=reinterpret_cast<uintptr_t>(header);break;}
  }
  if(!GameBase) return;
  const unsigned char setter[]={0x00,0x88,0x01,0xbd,0x08,0x40,0x47,0x79};
  const unsigned char lookup[]={0xf6,0x57,0xbd,0xa9,0xf4,0x4f,0x01,0xa9};
  const unsigned char update[]={0x00,0x01,0x3f,0xd6,0x60,0x02,0x40,0xf9};
  const unsigned char invoke[]={0xf6,0x57,0xbd,0xa9};
  if(!Matches(GameBase+0xfe31c0,setter,sizeof(setter)) || !Matches(GameBase+0x148d18,lookup,sizeof(lookup)) ||
   !Matches(GameBase+0x22d460,update,sizeof(update)) || !Matches(GameBase+0xd07320,invoke,sizeof(invoke))) {GameBase=0;return;}
  Class cls=objc_getClass("MainGLView");Method method=cls ? class_getInstanceMethod(cls,@selector(prepare)) : nullptr;
  if(!method || reinterpret_cast<uintptr_t>(method_getImplementation(method))!=GameBase+0xe56790) {GameBase=0;return;}
  auto slot=reinterpret_cast<uintptr_t *>(GameBase+0x18d6ce0+0x2c0);
  if(*slot!=GameBase+0xfe31c0 || !WritableSlot(reinterpret_cast<uintptr_t>(slot))) {GameBase=0;return;}
  id saved=[NSUserDefaults.standardUserDefaults objectForKey:PreferenceKey];
  if([saved respondsToSelector:@selector(floatValue)]) SelectedDegrees.store(SMUClampDegrees([saved floatValue]));
  OriginalSetFOV=reinterpret_cast<void (*)(void *,float)>(*slot);
  __atomic_store_n(slot,reinterpret_cast<uintptr_t>(GameplayFOVSetter),__ATOMIC_RELEASE);
  OriginalPrepare=reinterpret_cast<void (*)(id,SEL)>(method_getImplementation(method));
  if(!class_addMethod(cls,@selector(prepare),(IMP)RuntimePrepare,method_getTypeEncoding(method))) method_setImplementation(class_getInstanceMethod(cls,@selector(prepare)),(IMP)RuntimePrepare);
 }
}
