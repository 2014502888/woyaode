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

static void JokerShowTextEditor(id msg, id cell, UIViewController *host) {
    if (!msg || !host) return;
    // === DUMP ===
    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"msg class: %@\n", NSStringFromClass([msg class])];
    @try {
        unsigned int mc; objc_property_t *mp = class_copyPropertyList([msg class], &mc);
        for (unsigned int i = 0; i < mc; i++) {
            NSString *k = [NSString stringWithUTF8String:property_getName(mp[i])];
            @try { [dump appendFormat:@"  %@ = %@\n", k, [msg valueForKey:k] ?: @"(nil)"]; } @catch(id e) {}
        }
        free(mp);
    } @catch(id e) {}
    NSString *dp = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]; [dump writeToFile:[dp stringByAppendingPathComponent:@"dump.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // dump all RichTextViews
    NSMutableString *rv = [NSMutableString stringWithString:@"=== RichTextViews ===\n"];
    NSMutableArray *q = [NSMutableArray arrayWithObject:[UIApplication sharedApplication].keyWindow];
    while (q.count > 0) {
        UIView *v = q.firstObject; [q removeObject:v];
        for (UIView *sub in v.subviews) [q addObject:sub];
        if ([NSStringFromClass([v class]) isEqualToString:@"RichTextView"]) {
            [rv appendFormat:@"frame=%.0f,%.0f %.0fx%.0f text=\"%@\"\n", v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, [v valueForKey:@"text"] ?: @"(nil)"];
        }
    }
    [rv writeToFile:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"rv.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                UIView *v = (UIView *)cell;
                while (v) {
                    if ([v isKindOfClass:[UITableView class]]) { [(UITableView *)v reloadData]; break; }
                    v = v.superview;
                }
            } @catch(id e) {}
        });
    }];
    [alert addAction:cancel];
    [alert addAction:done];
    [host presentViewController:alert animated:YES completion:nil];
}

@interface JokerTarget : NSObject
@property (nonatomic, weak) id currentWrap;
@property (nonatomic, weak) id currentCell;
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
    target.currentWrap = wrap; target.currentCell = cell;
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
        // 递归找RichTextView
        NSMutableArray *q = [NSMutableArray arrayWithObject:(UIView*)self];
        while (q.count > 0) {
            UIView *v = q.firstObject; [q removeObject:v];
            if ([NSStringFromClass([v class]) isEqualToString:@"RichTextView"]) {
                @try { [v setValue:replacement forKey:@"text"]; } @catch(id e) {}
            }
            for (UIView *sub in v.subviews) [q addObject:sub];
        }
    } @catch(id e) {}
}
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if (!JokerEnabled()) return orig;
    @try {
        id wrap = PJGetMsgWrap(self);
        NSMutableString *dv = [NSMutableString stringWithString:@"=== menu dump ===\n"];
        NSMutableArray *queue = [NSMutableArray arrayWithObject:@[(UIView*)self, @""]];
        while (queue.count > 0) {
            NSArray *pair = queue.firstObject; [queue removeObject:pair];
            UIView *v = pair[0]; NSString *ind = pair[1];
            [dv appendFormat:@"%@[%@]", ind, NSStringFromClass([v class])];
            if ([v respondsToSelector:@selector(text)]) { @try { id t = [v performSelector:@selector(text)]; if(t) [dv appendFormat:@" text=\"%@\"", t]; } @catch(id e) {} }
            if ([v respondsToSelector:@selector(attributedText)]) { @try { id t = [v performSelector:@selector(attributedText)]; if(t) [dv appendFormat:@" attr=\"%@\"", t]; } @catch(id e) {} }
            [dv appendString:@"\n"];
            for (UIView *sub in v.subviews) [queue addObject:@[sub, [ind stringByAppendingString:@"  "]]];
        }
        NSString *dp = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [dv writeToFile:[dp stringByAppendingPathComponent:@"views.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (!wrap) return orig;
        id item = makeJokerMenuItem(wrap, self);
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
        id item = makeJokerMenuItem(wrap, self);
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

%hook RichTextView
- (void)setText:(NSString *)text {
    %orig;
    if (text.length > 0) {
        NSMutableString *s = [NSMutableString stringWithFormat:@"RichTextView setText: %@\n", text];
        [s appendFormat:@"frame=%.0f,%.0f %.0fx%.0f\n", self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height];
        NSString *dp = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [s writeToFile:[dp stringByAppendingPathComponent:@"hook.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
%end