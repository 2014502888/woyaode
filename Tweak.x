#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static BOOL JokerEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"JokerTextEnabled"] ||
           [[NSUserDefaults standardUserDefaults] boolForKey:@"pjMessageJokerEnable"];
}

static const char *kJokerText = "joker_text";
static void SetJokerText(id msg, NSString *t) {
    objc_setAssociatedObject(msg, kJokerText, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSString *GetJokerText(id msg) {
    return objc_getAssociatedObject(msg, kJokerText);
}

static UIViewController *PJTopmostVC(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

@interface JokerEditViewController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) NSString *originalText;
@property (nonatomic, copy) void (^onFinish)(NSString *newText);
@end
@implementation JokerEditViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"小丑改文字";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(onCancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(onFinish)];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont systemFontOfSize:18];
    self.textView.text = self.originalText ?: @"";
    [self.view addSubview:self.textView];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}
- (void)onCancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)onFinish {
    if (self.onFinish) self.onFinish(self.textView.text);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static id PJGetMsgWrap(id cell) {
    @try {
        if ([cell respondsToSelector:@selector(getCurrentMessageWrap)]) {
            id w = [cell performSelector:@selector(getCurrentMessageWrap)];
            if (w) return w;
        }
        id vm = nil;
        if ([cell respondsToSelector:@selector(viewModel)]) {
            vm = [cell performSelector:@selector(viewModel)];
        }
        if (!vm) vm = [cell valueForKey:@"m_viewModel"];
        if (vm) {
            id w = [vm valueForKey:@"m_messageWrap"];
            if (w) return w;
        }
    } @catch(id e){}
    return nil;
}

static UITableView *PJFindTableView(UIView *view);
static UITableView *PJFindTableFromView(UIView *v) {
    while (v) {
        if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
        v = v.superview;
    }
    return nil;
}
static void PJSetMatchingLabel(UIView *view, NSString *origText, NSString *newText) {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)view;
        if ([l.text isEqualToString:origText] || (GetJokerText(view) && [l.text isEqualToString:GetJokerText(view)])) {
            l.text = newText;
        }
        return;
    }
    for (UIView *sub in view.subviews) PJSetMatchingLabel(sub, origText, newText);
}
static void DumpView(UIView *view, NSString *indent, NSMutableString *out) {
    if (!view) return;
    [out appendFormat:@"%@[%@] %.0f,%.0f %.0fx%.0f", indent, NSStringFromClass([view class]), view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height];
    if ([view isKindOfClass:[UILabel class]]) { UILabel *l = (UILabel *)view; [out appendFormat:@" txt=\"%@\"", l.text]; }
    [out appendString:@"\n"];
    for (UIView *sub in view.subviews) DumpView(sub, [indent stringByAppendingString:@"  "], out);
}

static void JokerShowTextEditor(id msg, id cell, UIViewController *host) {
    if (!msg || !host) return;
    // === DUMP ===
    NSMutableString *dump = [NSMutableString stringWithFormat:@"cell class: %@\n", NSStringFromClass([cell class])];
    @try {
        unsigned int pc; objc_property_t *pp = class_copyPropertyList([cell class], &pc);
        for (unsigned int k = 0; k < pc; k++) { [dump appendFormat:@"  prop %s\n", property_getName(pp[k]); }
        free(pp);
    } @catch(id e) {}
    [dump appendString:@"--- subviews ---\n"];
    if ([cell isKindOfClass:[UIView class]]) DumpView((UIView*)cell, @"", dump);
    [dump appendFormat:@"--- msg: %@\n", NSStringFromClass([msg class])];
    @try {
        unsigned int mc; objc_property_t *mp = class_copyPropertyList([msg class], &mc);
        for (unsigned int k = 0; k < mc; k++) {
            NSString *key = [NSString stringWithUTF8String:property_getName(mp[k])];
            @try { [dump appendFormat:@"  %@ = %@\n", key, [msg valueForKey:key] ?: @"(nil)"]; } @catch(id e) {}
        }
        free(mp);
    } @catch(id e) {}
    [dump writeToFile:@"/var/mobile/Documents/dump.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *originalText = [msg valueForKey:@"m_nsContent"];
    if (!originalText) originalText = GetJokerText(msg) ?: @"";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"改xx" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = originalText;
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *done = [UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *t = alert.textFields.firstObject.text;
        SetJokerText(msg, t);
        [msg setValue:t forKey:@"m_nsContent"];
        @try { [msg setValue:t forKey:@"m_nsBeforeDisplayContent"]; } @catch(id e) {}
        @try { [msg setValue:t forKey:@"m_nsLastDisplayContent"]; } @catch(id e) {}
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableString *log = [NSMutableString stringWithString:@"\n=== DONE ===\n"];
            @try {
                [log appendFormat:@"new text: %@\n", t];
                [log appendFormat:@"m_nsContent after set: %@\n", [msg valueForKey:@"m_nsContent"]];
                id mgr = [msg valueForKey:@"m_tableViewMgr"];
                [log appendFormat:@"m_tableViewMgr: %@\n", mgr ?: @"(nil)"];
                if (mgr) {
                    @try { [mgr performSelector:NSSelectorFromString(@"clearDisplayCachesOfWrap:") withObject:msg]; [log appendString:@"clearDisplayCaches OK\n"]; } @catch(id e) { [log appendFormat:@"clearDisplayCaches ERR: %@\n", e]; }
                    @try { [mgr performSelector:NSSelectorFromString(@"refreshByRecreatingViewModel:wrap:") withObject:nil withObject:msg]; [log appendString:@"refreshByRecreating OK\n"]; } @catch(id e) { [log appendFormat:@"refreshByRecreating ERR: %@\n", e]; }
                }
                UITableView *tv = PJFindTableFromView((UIView *)cell);
                [log appendFormat:@"tableView: %@\n", tv ?: @"(nil)"];
                if (tv) {
                    NSIndexPath *ip = [tv indexPathForCell:(UITableViewCell *)cell];
                    [log appendFormat:@"indexPath: %@\n", ip];
                    if (ip) [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
                    else [tv reloadData];
                }
            } @catch(id e) { [log appendFormat:@"ERR: %@\n", e]; }
            [log appendString:@"=== END ===\n"];
            [log writeToFile:@"/var/mobile/Documents/done_log.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
    }];
    [alert addAction:cancel];
    [alert addAction:done];
    [host presentViewController:alert animated:YES completion:nil];
}

@interface JokerTarget : NSObject
@property (nonatomic, weak) id currentWrap;
+ (instancetype)shared;
@end
@implementation JokerTarget
+ (instancetype)shared {
    static JokerTarget *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [JokerTarget new]; });
    return s;
}
- (void)jokerEditAction {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *host = PJTopmostVC();
        if (!self.currentWrap || !host) return;
        JokerShowTextEditor(self.currentWrap, self.currentCell, host);
    });
}
@end

static id makeJokerMenuItem(id wrap, id cell) {
    Class mmItem = NSClassFromString(@"MMMenuItem");
    if (!mmItem) return nil;
    UIImage *icon = [UIImage systemImageNamed:@"theatermasks"];
    if (!icon) icon = [UIImage systemImageNamed:@"pencil"];
    JokerTarget *target = [JokerTarget shared];
    target.currentWrap = wrap;
    target.currentCell = cell;
    SEL sel = @selector(initWithTitle:icon:target:action:);
    id (*msgSend)(id, SEL, NSString*, UIImage*, id, SEL) = (id (*)(id, SEL, NSString*, UIImage*, id, SEL))objc_msgSend;
    id item = msgSend([[mmItem alloc] init], sel, @"改xx", icon, target, @selector(jokerEditAction));
    return item;
}

%hook TextMessageCellView
- (void)layoutContentView {
    %orig;
    if (!JokerEnabled()) return;
    @try {
        id wrap = PJGetMsgWrap(self);
        if (!wrap) return;
        NSString *replacement = GetJokerText(wrap);
        if (!replacement) return;
        UIView *selfView = (UIView *)self;
        NSArray *subs = [selfView subviews];
        for (NSInteger i = 0; i < [subs count]; i++) {
            UIView *sub = [subs objectAtIndex:i];
            if ([sub isKindOfClass:[UILabel class]]) {
                UILabel *textLabel = (UILabel *)sub;
                textLabel.text = replacement;
                break;
            }
        }
    } @catch(id e) {}
}
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if (!JokerEnabled()) return orig;
    @try {
        id wrap = PJGetMsgWrap(self);
        if (!wrap) return orig;
        id item = makeJokerMenuItem(wrap);
        if (!item) return orig;
        NSMutableArray *m = [orig mutableCopy] ?: [NSMutableArray array];
        [m addObject:item];
        return m;
    } @catch(id e) { return orig; }
}
%end

%hook ImageMessageCellView
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if (!JokerEnabled()) return orig;
    @try {
        id wrap = PJGetMsgWrap(self);
        if (!wrap) return orig;
        id item = makeJokerMenuItem(wrap);
        if (!item) return orig;
        NSMutableArray *m = [orig mutableCopy] ?: [NSMutableArray array];
        [m addObject:item];
        return m;
    } @catch(id e) { return orig; }
}
%end

@interface PJSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end
@implementation PJSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"增强设置";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self; tv.delegate = self;
    [self.view addSubview:tv];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    UISwitch *sw = [UISwitch new];
    c.textLabel.text = @"改xx(消息文字修改)";
    sw.on = JokerEnabled();
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}
- (void)toggle:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"JokerTextEnabled"];
}
@end

static UITableView *PJFindTableView(UIView *view) {
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *t = PJFindTableView(sub);
        if (t) return t;
    }
    return nil;
}

@interface PJButtonTarget : NSObject
@end
@implementation PJButtonTarget
- (void)onTap {
    PJSettingsViewController *s = [PJSettingsViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
    [PJTopmostVC() presentViewController:nav animated:YES completion:nil];
}
@end

static void PJAddSettingsEntry(UIViewController *vc) {
    // 加到导航栏右边,不跟其他dylib冲突
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"改xx设置" style:UIBarButtonItemStylePlain target:nil action:@selector(onTap)];
    PJButtonTarget *t = [PJButtonTarget new];
    objc_setAssociatedObject(item, "pj_t", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item setAction:@selector(onTap)];
    [item setTarget:t];
    NSMutableArray *rightItems = [vc.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [rightItems addObject:item];
    vc.navigationItem.rightBarButtonItems = rightItems;
}

%hook MoreViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PJAddSettingsEntry(self);
}
%end

%hook NewSettingViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PJAddSettingsEntry(self);
}
%end

%ctor {
    @autoreleasepool { }
}
