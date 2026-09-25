#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// 微信 8.0.78 目标类前向声明(实际实现在微信包内, 这里仅为编译通过)
@interface CMessageWrap : NSObject
- (NSString *)displayContent;
@end
@interface BaseMsgContentViewController : UIViewController
@end
@interface MainFrameViewController : UIViewController
@end
@interface NewMainFrameViewController : UIViewController
@end
@interface MoreViewController : UIViewController
@end
@interface NewSettingViewController : UIViewController
@end
@interface MainFrameLogicController : NSObject
@end

// ============================================================
//  Misaka + Joker 反推实现 (来自 2.dylib 逆向)
//  Misaka  = 首页会话列表分组 (单聊 / 群聊 / 其他)
//  Joker   = 聊天消息长按恶搞 (改文字 / 换图 / 伪造金额 / 缩放 / 排序 / 保存)
// ============================================================

#pragma mark - 全局开关 (对应原 dylib: pjMessageJokerEnable / setGroupingEnable:)
static BOOL MisakaGroupingEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"misaka_grouping_enable"];
}
static BOOL JokerEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"pjMessageJokerEnable"];
}

#pragma mark - 伪造数据: 给任意 CMessageWrap 挂"恶搞覆盖值"
// 原 dylib 通过 jokerWithText:/jokerWithImage:/jokerWithMoney: 改写显示内容,
// 这里用关联对象在消息对象上挂 override, 再 swizzle 它的 display getter。
static const char *kJokerOverrideText = "joker_override_text";
static const char *kJokerOverrideImage = "joker_override_image";
static const char *kJokerOverrideMoney = "joker_override_money";

static void JokerSetOverrideText(id msg, NSString *t) {
    objc_setAssociatedObject(msg, kJokerOverrideText, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSString *JokerGetOverrideText(id msg) {
    return objc_getAssociatedObject(msg, kJokerOverrideText);
}
static void JokerSetOverrideImage(id msg, UIImage *img) {
    objc_setAssociatedObject(msg, kJokerOverrideImage, img, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static UIImage *JokerGetOverrideImage(id msg) {
    return objc_getAssociatedObject(msg, kJokerOverrideImage);
}
static void JokerSetOverrideMoney(id msg, NSString *m) {
    objc_setAssociatedObject(msg, kJokerOverrideMoney, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSString *JokerGetOverrideMoney(id msg) {
    return objc_getAssociatedObject(msg, kJokerOverrideMoney);
}

#pragma mark - Misaka: 会话分组管理器
// 原 dylib ivar: misakaChatArray(单聊) / misakaGroupArray(群聊) / misakaOtherArray(其他)
@interface MisakaManager : NSObject
@property (nonatomic, strong) NSMutableArray *chatArray;   // 单聊
@property (nonatomic, strong) NSMutableArray *groupArray;   // 群聊
@property (nonatomic, strong) NSMutableArray *otherArray;  // 公众号/服务号/文件助手等
+ (instancetype)shared;
- (void)rebuildFromSessions:(NSArray *)sessions;
@end

@implementation MisakaManager
+ (instancetype)shared {
    static MisakaManager *m; static dispatch_once_t t;
    dispatch_once(&t, ^{ m = [MisakaManager new]; });
    return m;
}
- (instancetype)init {
    self = [super init];
    _chatArray = [NSMutableArray new];
    _groupArray = [NSMutableArray new];
    _otherArray = [NSMutableArray new];
    return self;
}
// 按会话对象的"群标识/公众号标识"分桶。WeChat 会话对象常见字段:
//  groupId 非空 => 群聊; brandContact/公众号 => other; 其余 => 单聊。
- (void)rebuildFromSessions:(NSArray *)sessions {
    [_chatArray removeAllObjects];
    [_groupArray removeAllObjects];
    [_otherArray removeAllObjects];
    for (id s in sessions) {
        NSString *groupId = [s valueForKey:@"groupId"];
        NSNumber *brand = [s valueForKey:@"brandContact"];
        if (groupId.length > 0) {
            [_groupArray addObject:s];
        } else if (brand.boolValue) {
            [_otherArray addObject:s];
        } else {
            [_chatArray addObject:s];
        }
    }
}
@end

#pragma mark - Joker: 长按菜单动作
// 原 dylib: messageJokerTextAction / Image / Money / Scale / PaiXu / Save
// 在聊天页长按消息弹出"小丑"子菜单。
static void JokerPresentEditorForMessage(id msg, UIViewController *host) {
    if (!JokerEnabled() || !host) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"小丑(Joker)" message:@"伪造这条消息的显示内容" preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"改文字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"新文字" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text = JokerGetOverrideText(msg) ?: @""; }];
        [input addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            JokerSetOverrideText(msg, input.textFields.firstObject.text);
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [host presentViewController:input animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"伪造金额" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        UIAlertController *input = [UIAlertController alertControllerWithTitle:@"金额(如 ¥88.00)" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [input addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text = JokerGetOverrideMoney(msg) ?: @""; }];
        [input addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            JokerSetOverrideMoney(msg, input.textFields.firstObject.text);
        }]];
        [input addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [host presentViewController:input animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"换图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        UIImagePickerController *picker = [UIImagePickerController new];
        [host presentViewController:picker animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"清除伪造" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
        JokerSetOverrideText(msg, nil);
        JokerSetOverrideMoney(msg, nil);
        JokerSetOverrideImage(msg, nil);
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Hook: CMessageWrap (消息模型)
// swizzle 它的 displayContent / summary getter, 有 override 就返回伪造值。
%hook CMessageWrap
- (NSString *)displayContent {
    NSString *over = JokerGetOverrideText(self);
    if (over) return over;
    NSString *money = JokerGetOverrideMoney(self);
    if (money.length) return money;
    return %orig;
}
%end

#pragma mark - Hook: 聊天页 (BaseMsgContentViewController)
static UIScrollView *PJFindAnyScroll(UIView *v) {
    if ([v isKindOfClass:[UIScrollView class]]) return (UIScrollView *)v;
    for (UIView *s in v.subviews) { UIScrollView *r = PJFindAnyScroll(s); if (r) return r; }
    return nil;
}
%hook BaseMsgContentViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        UIScrollView *sv = PJFindAnyScroll(self.view);
        if (!sv) return;
        for (UIGestureRecognizer *g in sv.gestureRecognizers) {
            if ([g isKindOfClass:[UILongPressGestureRecognizer class]] && ((UILongPressGestureRecognizer *)g).minimumPressDuration == 0.9) return;
        }
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pjJokerLong:)];
        lp.minimumPressDuration = 0.9;
        [sv addGestureRecognizer:lp];
    } @catch(id e){}
}
- (void)pjJokerLong:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    @try {
        NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [[NSString stringWithFormat:@"LONGPRESS at %@", [NSDate date]] writeToFile:[doc stringByAppendingPathComponent:@"pj_longpress.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch(id e){}
}
%end
#pragma mark - Hook: 首页会话列表 (MainFrameViewController)
// 原 dylib: misakaChatArray / misakaGroupArray / misakaOtherArray 分桶,
// 这里在列表刷新后重建分桶, 并按开关决定是否插入分组头。
static NSString *PJDoc(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}
static void PJDumpObjProps(id obj, NSMutableString *s, NSString *label) {
    [s appendFormat:@"--- %@ class=%@ ---\n", label, [obj class]];
    unsigned int np = 0;
    objc_property_t *props = class_copyPropertyList([obj class], &np);
    for (unsigned int i = 0; i < np; i++) {
        const char *n = property_getName(props[i]);
        [s appendFormat:@"  prop %s\n", n];
    }
    free(props);
    unsigned int ni = 0;
    Ivar *ivars = class_copyIvarList([obj class], &ni);
    for (unsigned int i = 0; i < ni; i++) {
        const char *n = ivar_getName(ivars[i]);
        [s appendFormat:@"  ivar %s\n", n];
    }
    free(ivars);
}
%hook MainFrameViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NSMutableString *s = [NSMutableString string];
        PJDumpObjProps(self, s, @"HOME VC");
        NSArray *candidates = @[@"sessions", @"dataArray", @"dataArr", @"sessionArray", @"arrData", @"m_packMainFrameViewController", @"allSession"];
        NSArray *arr = nil;
        for (NSString *k in candidates) {
            @try {
                id v = [self valueForKey:k];
                if ([v isKindOfClass:[NSArray class]] && [(NSArray *)v count] > 0) {
                    arr = v;
                    [s appendFormat:@"FOUND ARRAY key=%@ count=%lu\n", k, (unsigned long)arr.count];
                    break;
                }
            } @catch(id e){}
        }
        if (arr.count > 0) {
            PJDumpObjProps(arr.firstObject, s, @"FIRST SESSION");
        }
        [s writeToFile:[PJDoc() stringByAppendingPathComponent:@"pj_home_dump.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch(id e){}
}
%end
static const char *kPJRowMap = "pj_row_map";
static NSArray *PJBuildRowMap(id logic) {
    @try {
        NSArray *front = [logic valueForKey:@"m_frontSessionArray"];
        if (![front isKindOfClass:[NSArray class]] || front.count < 2) return nil;
        NSMutableIndexSet *single = [NSMutableIndexSet new];
        NSMutableIndexSet *group = [NSMutableIndexSet new];
        NSMutableIndexSet *other = [NSMutableIndexSet new];
        for (NSUInteger i = 0; i < front.count; i++) {
            NSString *un = [front[i] valueForKey:@"_userName"];
            if ([un hasSuffix:@"@chatroom"]) [group addIndex:i];
            else if ([un hasPrefix:@"gh_"]) [other addIndex:i];
            else [single addIndex:i];
        }
        NSMutableArray *map = [NSMutableArray new];
        [single enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *_) { [map addObject:@(i)]; }];
        [group enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *_) { [map addObject:@(i)]; }];
        [other enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *_) { [map addObject:@(i)]; }];
        return map;
    } @catch(id e) { return nil; }
}
static NSIndexPath *PJRemap(id self, NSIndexPath *ip) {
    if (!MisakaGroupingEnabled()) return ip;
    @try {
        id logic = [self valueForKey:@"m_mainFrameLogicController"];
        NSArray *map = PJBuildRowMap(logic);
        if (map && ip.row < (NSInteger)map.count) {
            NSUInteger origRow = [map[ip.row] unsignedIntegerValue];
            return [NSIndexPath indexPathForRow:origRow inSection:ip.section];
        }
    } @catch(id e){}
    return ip;
}
static NSString * const kPJFolderMark = @"__PJ_FOLDER__";
// 返回: 每行要么是 NSNumber(原始行号), 要么是 kPJFolderMark
static NSArray *PJBuildDisplayList(id logic) {
    @try {
        NSArray *front = [logic valueForKey:@"m_frontSessionArray"];
        if (![front isKindOfClass:[NSArray class]]) return nil;
        NSMutableArray *singles = [NSMutableArray new];
        NSMutableArray *groups = [NSMutableArray new];
        NSMutableArray *others = [NSMutableArray new];
        for (NSUInteger i = 0; i < front.count; i++) {
            NSString *un = [front[i] valueForKey:@"_userName"];
            if ([un hasSuffix:@"@chatroom"]) [groups addObject:@(i)];
            else if ([un hasPrefix:@"gh_"]) [others addObject:@(i)];
            else [singles addObject:@(i)];
        }
        NSMutableArray *r = [NSMutableArray new];
        [r addObjectsFromArray:singles];
        if (groups.count > 0) [r addObject:kPJFolderMark];
        [r addObjectsFromArray:others];
        return r;
    } @catch(id e) { return nil; }
}
// 群列表 VC: 简单列出所有群名
@interface PJGroupFolderVC : UITableViewController
@property (nonatomic, strong) NSArray *groupUsernames;
@end
@implementation PJGroupFolderVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"群助手";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.groupUsernames.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"g"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"g"];
    c.textLabel.text = self.groupUsernames[ip.row];
    return c;
}
@end
%hook NewMainFrameViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        id logic = [self valueForKey:@"m_mainFrameLogicController"];
        id ti = [logic valueForKey:@"m_tableViewInfo"];
        if (!ti) ti = [self valueForKey:@"m_tableViewInfo"];
        NSString *s = [NSString stringWithFormat:@"logic=%@ ti=%@", [logic class], [ti class]];
        [s writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pj_ti.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch(id e){}
}
%end

#pragma mark - 简单设置页(对应 PJSettingViewController)
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
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 2; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"cell";
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:cid] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    UISwitch *sw = [UISwitch new];
    if (ip.row == 0) {
        c.textLabel.text = @"会话分组(Misaka)";
        sw.on = MisakaGroupingEnabled(); sw.tag = 100;
    } else {
        c.textLabel.text = @"消息小丑(Joker)";
        sw.on = JokerEnabled(); sw.tag = 101;
    }
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}
- (void)toggle:(UISwitch *)sw {
    if (sw.tag == 100) [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"misaka_grouping_enable"];
    if (sw.tag == 101) [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"pjMessageJokerEnable"];
}
- (void)pjDismiss { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

#pragma mark - 设置入口: 我页/设置页底部加按钮
static UITableView *PJFindTableView(UIView *view) {
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *sub in view.subviews) {
        UITableView *t = PJFindTableView(sub);
        if (t) return t;
    }
    return nil;
}
static UIViewController *PJTopmostVC(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
@interface PJButtonTarget : NSObject
@end
@implementation PJButtonTarget
- (void)pjOnTap {
    dispatch_async(dispatch_get_main_queue(), ^{
        PJSettingsViewController *s = [PJSettingsViewController new];
        s.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:s action:@selector(pjDismiss)];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:s];
        UIViewController *top = PJTopmostVC();
        if (top) [top presentViewController:nav animated:YES completion:nil];
    });
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
    [btn setTitle:@"增强设置(Misaka/Joker)" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16];
    PJButtonTarget *t = [PJButtonTarget new];
    objc_setAssociatedObject(btn, "pj_btn_target", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:t action:@selector(pjOnTap) forControlEvents:UIControlEventTouchUpInside];
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

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NSString *n = NSStringFromClass([self class]);
        if ([n hasPrefix:@"UI"] || [n hasPrefix:@"_UI"] || [n hasPrefix:@"PJ"] || [n hasPrefix:@"JXT"]) return;
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"pj_vc_list.txt"];
        NSString *exist = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
        if (![exist containsString:[n stringByAppendingString:@"\n"]]) {
            NSString *line = [exist stringByAppendingFormat:@"%@\n", n];
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch(id e){}
}
%end
%ctor {
    @autoreleasepool {
        // 加载即生效; 开关由设置页/外部写入 NSUserDefaults。
    }
}
