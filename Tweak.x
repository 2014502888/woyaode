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

static void JokerShowTextEditor(id msg, UIViewController *host) {
    if (!msg || !host) return;
    JokerEditViewController *e = [JokerEditViewController new];
    e.originalText = GetJokerText(msg) ?: @"";
    __block id weakMsg = msg;
    e.onFinish = ^(NSString *t) { SetJokerText(weakMsg, t); };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:e];
    [host presentViewController:nav animated:YES completion:nil];
}

static id PJMakeJokerMenuItem(id wrap) {
    Class mmItem = NSClassFromString(@"MMMenuItem");
    if (!mmItem) return nil;
    UIImage *icon = [UIImage systemImageNamed:@"theatermasks"];
    if (!icon) icon = [UIImage systemImageNamed:@"pencil"];
    // initWithTitle:icon:action:  (action is a block)
    SEL initSel = @selector(initWithTitle:icon:action:);
    id obj = [[mmItem alloc] init];
    NSMethodSignature *sig = [mmItem instanceMethodSignatureForSelector:initSel];
    if (!sig) return nil;
    __block id weakWrap = wrap;
    void (^block)(void) = ^{
        UIViewController *host = PJTopmostVC();
        JokerShowTextEditor(weakWrap, host);
    };
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:initSel];
    [inv setTarget:obj];
    NSString *title = @"小丑";
    [inv setArgument:&title atIndex:2];
    [inv setArgument:&icon atIndex:3];
    [inv setArgument:&block atIndex:4];
    [inv invoke];
    id result;
    [inv getReturnValue:&result];
    return result;
}

%hook TextMessageCellView
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if (!JokerEnabled()) return orig;
    @try {
        id wrap = PJGetMsgWrap(self);
        if (!wrap) return orig;
        id item = PJMakeJokerMenuItem(wrap);
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
        id item = PJMakeJokerMenuItem(wrap);
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
    c.textLabel.text = @"消息小丑(Joker)";
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
    UITableView *tv = PJFindTableView(vc.view);
    if (!tv) return;
    if ([tv.tableFooterView.accessibilityLabel isEqual:@"pj_entry"]) return;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, tv.bounds.size.width, 54);
    btn.backgroundColor = [UIColor whiteColor];
    btn.accessibilityLabel = @"pj_entry";
    [btn setTitle:@"增强设置(Joker)" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    PJButtonTarget *t = [PJButtonTarget new];
    objc_setAssociatedObject(btn, "pj_t", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:t action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    tv.tableFooterView = btn;
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