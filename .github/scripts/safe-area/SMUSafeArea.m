#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SMUSafeRect.h"

static void (*OriginalSetFrame)(id,SEL,CGRect);
static void (*OriginalLayout)(id,SEL);
static void (*OriginalDidMove)(id,SEL);
static void (*OriginalSafeChange)(id,SEL);
static const char ApplyingKey;

static BOOL FittedFrame(UIView *view, CGRect proposed, CGRect *out) {
    UIWindow *window=view.window;
    UIView *parent=view.superview;
    if (!window || !parent || window.screen!=UIScreen.mainScreen) return NO;
    // Use the window's insets: the view's own insets become zero once it is fitted.
    UIEdgeInsets insets=window.safeAreaInsets;
    CGRect full=[window convertRect:window.bounds toView:parent];
    if (!SMUNearRect(full,parent.bounds)) return NO;
    return SMUAdjustFrame(proposed,full,insets.top,insets.left,insets.bottom,insets.right,out);
}

static void SafeSetFrame(UIView *view,SEL selector,CGRect frame) {
    CGRect fitted=frame;
    FittedFrame(view,frame,&fitted);
    OriginalSetFrame(view,selector,fitted);
}

static void ApplySafeFrame(UIView *view) {
    if (objc_getAssociatedObject(view,&ApplyingKey)) return;
    CGRect fitted=view.frame;
    if (!FittedFrame(view,view.frame,&fitted) || SMUNearRect(fitted,view.frame)) return;
    objc_setAssociatedObject(view,&ApplyingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    OriginalSetFrame(view,@selector(setFrame:),fitted);
    objc_setAssociatedObject(view,&ApplyingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SafeLayout(UIView *view,SEL selector) {
    ApplySafeFrame(view);
    // Keep the existing GenericGLView framebuffer resize and engine callbacks.
    OriginalLayout(view,selector);
}
static void SafeDidMove(UIView *view,SEL selector) {
    OriginalDidMove(view,selector);
    ApplySafeFrame(view);
    [view setNeedsLayout];
}
static void SafeInsetsChanged(UIView *view,SEL selector) {
    OriginalSafeChange(view,selector);
    ApplySafeFrame(view);
    [view setNeedsLayout];
}

static IMP Hook(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return NULL;
    IMP previous=method_getImplementation(method);
    if (!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
    return previous;
}

__attribute__((constructor)) static void InstallSMUSafeArea(void) {
    @autoreleasepool {
        Class cls=objc_getClass("MainGLView");
        if (!cls || ![cls isSubclassOfClass:UIView.class]) return;
        // Validate all inherited methods before installing any hooks.
        for (NSString *name in @[@"setFrame:",@"layoutSubviews",@"didMoveToWindow",@"safeAreaInsetsDidChange"])
            if (!class_getInstanceMethod(cls,NSSelectorFromString(name))) return;
        OriginalSetFrame=(void(*)(id,SEL,CGRect))Hook(cls,@selector(setFrame:),(IMP)SafeSetFrame);
        OriginalLayout=(void(*)(id,SEL))Hook(cls,@selector(layoutSubviews),(IMP)SafeLayout);
        OriginalDidMove=(void(*)(id,SEL))Hook(cls,@selector(didMoveToWindow),(IMP)SafeDidMove);
        OriginalSafeChange=(void(*)(id,SEL))Hook(cls,@selector(safeAreaInsetsDidChange),(IMP)SafeInsetsChanged);
    }
}
