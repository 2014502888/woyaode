#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// ============================================================
//  Joker tweak (照 Joker.dylib 反推)
//  hook TextMessageCellView / ImageMessageCellView 的 operationMenuItems,
//  往微信原生菜单里加一个"小丑"项。
// ============================================================

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
        for (NSString *k in @[@"messageWrap", @"wrap", @"msgWrap", @"m_messageWrap", @"data", @"messageData"]) {
            id v = [cell valueForKey:k];
            if (v) return v;
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

%hook TextMessageCellView
- (NSArray *)operationMenuItems {
    NSArray *orig = %orig;
    if (!JokerEnabled()) return orig;
    @try {
        id wrap = PJGetMsgWrap(self);
        if (!wrap) return orig;
        Class mmItem = NSClassFromString(@"MMMenuItem");
        if (!mmItem) return orig;
        id item = [[mmItem alloc] init];
        if ([item respondsToSelector:@selector(setTitle:)]) {
            [item performSelector:@selector(setTitle:) withObject:@"小丑"];
        }
        UIViewController *host = PJTopmostVC();
        void (^blk)(void) = ^{ JokerShowTextEditor(wrap, host); };
        if ([item respondsToSelector:@selector(setActionBlock:)]) {
            [item performSelector:@selector(setActionBlock:) withObject:blk];
        }
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
        Class mmItem = NSClassFromString(@"MMMenuItem");
        if (!mmItem) return orig;
        id item = [[mmItem alloc] init];
        if ([item respondsToSelector:@selector(setTitle:)]) {
            [item performSelector:@selector(setTitle:) withObject:@"小丑"];
        }
        UIViewController *host = PJTopmostVC();
        void (^blk)(void) = ^{
            UIImagePickerController *p = [UIImagePickerController new];
            [host presentViewController:p animated:YES completion:nil];
        };
        if ([item respondsToSelector:@selector(setActionBlock:)]) {
            [item performSelector:@selector(setActionBlock:) withObject:blk];
        }
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
    [btn addTarget:^{
        PJSettingsViewController *s = [PJSettingsViewController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
        [PJTopmostVC() presentViewController:nav animated:YES completion:nil];
    } forControlEvents:UIControlEventTouchUpInside];
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
