#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>
#import <CommonCrypto/CommonDigest.h>

static UIColor *BLPink(void){return [UIColor colorWithRed:.93 green:.27 blue:.47 alpha:1];}
static UIColor *BLBg(void){return [UIColor colorWithRed:.965 green:.972 blue:.985 alpha:1];}
static UIColor *BLInk(void){return [UIColor colorWithRed:.15 green:.19 blue:.28 alpha:1];}
static NSString *BLString(id value){
    if([value isKindOfClass:[NSString class]])return value;
    if([value respondsToSelector:@selector(stringValue)])return [value stringValue];
    return @"";
}
static NSString *BLTitle(NSString *text){
    NSString *t=text?:@"";
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:NULL];
    t=[re stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0,t.length) withTemplate:@""];
    return [[t stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"] stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
}
static NSString *BLBV(NSString *text){
    if(!text.length)return nil;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"BV[0-9A-Za-z]{10}" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    return m?[text substringWithRange:m.range]:nil;
}
static NSMutableDictionary *BLNormalize(NSDictionary *d){
    if(![d isKindOfClass:[NSDictionary class]])return nil;
    NSString *bvid=BLBV(BLString(d[@"bvid"]));
    if(!bvid.length)return nil;
    NSDictionary *owner=[d[@"owner"] isKindOfClass:[NSDictionary class]]?d[@"owner"]:@{};
    NSDictionary *stat=[d[@"stat"] isKindOfClass:[NSDictionary class]]?d[@"stat"]:@{};
    return [@{@"bvid":bvid,@"title":BLTitle(BLString(d[@"title"])),
       @"pic":[BLString(d[@"pic"]) hasPrefix:@"//"]?[@"https:" stringByAppendingString:BLString(d[@"pic"])]:BLString(d[@"pic"]),@"author":BLString(d[@"author"]).length?BLString(d[@"author"]):BLString(owner[@"name"]),
       @"desc":BLString(d[@"desc"]),@"cid":BLString(d[@"cid"]),
       @"duration":BLString(d[@"duration"]),@"view":BLString(d[@"play"]).length?BLString(d[@"play"]):BLString(stat[@"view"]),
       @"like":BLString(stat[@"like"]),@"favorite":BLString(stat[@"favorite"])} mutableCopy];
}
static NSArray *BLStored(NSString *key){
    id rows=[[NSUserDefaults standardUserDefaults] arrayForKey:key];
    return [rows isKindOfClass:[NSArray class]]?rows:@[];
}
static BOOL BLContains(NSString *key,NSString *bvid){
    for(NSDictionary *v in BLStored(key))if([v[@"bvid"] isEqualToString:bvid])return YES;
    return NO;
}
static void BLStore(NSString *key,NSDictionary *item,BOOL remove){
    NSMutableArray *list=[NSMutableArray array];
    for(NSDictionary *v in BLStored(key))if(![v[@"bvid"] isEqualToString:item[@"bvid"]])[list addObject:v];
    if(!remove && item[@"bvid"])[list insertObject:item atIndex:0];
    while(list.count>70)[list removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:key];
}
static void BLAlert(UIViewController *vc,NSString *title,NSString *message){
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

typedef void(^BLJSONCallback)(NSDictionary *,NSError *);
static void BLRequest(NSString *url,BLJSONCallback done){
    NSURL *endpoint=[NSURL URLWithString:url];
    if(!endpoint){if(done)done(nil,[NSError errorWithDomain:@"URL格式无效" code:1 userInfo:nil]);return;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:endpoint cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [req setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 8_4_1 like Mac OS X) AppleWebKit/600.1.4 Mobile/12H321" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSDictionary *obj=nil;
        if(!error && data.length && data.length<3*1024*1024){
            id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if([json isKindOfClass:[NSDictionary class]])obj=json;
        } else if(!error) {
            error=[NSError errorWithDomain:@"接口数据异常或过大" code:2 userInfo:nil];
        }
        dispatch_async(dispatch_get_main_queue(),^{if(done)done(obj,error);});
    }] resume];
}
static NSString *BLFailure(NSDictionary *json,NSError *error){
    if(error)return error.localizedDescription?:@"网络失败";
    NSString *message=BLString(json[@"message"]);
    return message.length?message:@"接口未返回可用数据，可能需要登录或请求验证";
}

static NSString *BLQueryEscape(NSString *value){
    NSMutableCharacterSet *valid=[[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [valid removeCharactersInString:@"&=?+/#%!'()*"];
    NSString *clean=[[value?:@"" componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"!'()*"]] componentsJoinedByString:@""];
    return [clean stringByAddingPercentEncodingWithAllowedCharacters:valid]?:@"";
}
static NSString *BLWBIKey(NSDictionary *json){
    NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
    NSDictionary *wbi=[data[@"wbi_img"] isKindOfClass:[NSDictionary class]]?data[@"wbi_img"]:@{};
    NSString *image=[BLString(wbi[@"img_url"]) lastPathComponent];
    NSString *sub=[BLString(wbi[@"sub_url"]) lastPathComponent];
    NSString *raw=[[image stringByDeletingPathExtension] stringByAppendingString:[sub stringByDeletingPathExtension]];
    if(raw.length<64)return nil;
    static const unsigned char order[64]={
     46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,
     33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,
     61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,
     36,20,34,44,52};
    NSMutableString *result=[NSMutableString stringWithCapacity:32];
    for(int i=0;i<32;i++)[result appendFormat:@"%C",[raw characterAtIndex:order[i]]];
    return result;
}
static void BLSearch(NSString *term,NSInteger page,BLJSONCallback done){
    BLRequest(@"https://api.bilibili.com/x/web-interface/nav",^(NSDictionary *nav,NSError *navError){
        NSString *mixin=BLWBIKey(nav);
        if(mixin.length==32){
            long long now=(long long)[[NSDate date] timeIntervalSince1970];
            NSString *params=[NSString stringWithFormat:@"keyword=%@&page=%ld&search_type=video&wts=%lld",
              BLQueryEscape(term),(long)page,now];
            NSString *signBase=[params stringByAppendingString:mixin];
            const char *bytes=[signBase UTF8String];
            unsigned char hash[CC_MD5_DIGEST_LENGTH];
            CC_MD5(bytes,(CC_LONG)strlen(bytes),hash);
            NSMutableString *signature=[NSMutableString string];
            for(int i=0;i<CC_MD5_DIGEST_LENGTH;i++)[signature appendFormat:@"%02x",hash[i]];
            NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/wbi/search/type?%@&w_rid=%@",
              params,signature];
            BLRequest(url,^(NSDictionary *result,NSError *error){
                if(!error && [result[@"code"] integerValue]==0 && [result[@"data"] isKindOfClass:[NSDictionary class]])done(result,nil);
                else {
                    // Older mirror endpoints may still be available on some networks.
                    NSString *fallback=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=%ld",
                       BLQueryEscape(term),(long)page];
                    BLRequest(fallback,^(NSDictionary *old,NSError *legacyError){
                        done([old[@"code"] integerValue]==0?old:result,legacyError?:error);
                    });
                }
            });
        }else{
            NSString *fallback=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=%ld",
               BLQueryEscape(term),(long)page];
            BLRequest(fallback,done);
        }
    });
}
static void BLFetchImage(NSString *address,UIImageView *view,NSCache *cache){
    view.image=nil;
    if(![address hasPrefix:@"https://"] && ![address hasPrefix:@"http://"])return;
    view.accessibilityIdentifier=address;
    UIImage *cached=[cache objectForKey:address];
    if(cached){view.image=cached;return;}
    NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:address] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:12];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *res,NSError *err){
        if(err||data.length>550000||!data.length)return;
        UIImage *image=[UIImage imageWithData:data];
        if(!image)return;
        // Decode the full source only briefly, then cache a small thumbnail.
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(130,84),YES,1.0);
        [image drawInRect:CGRectMake(0,0,130,84)];
        UIImage *small=UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        if(!small)return;
        image=small;
        [cache setObject:image forKey:address];
        dispatch_async(dispatch_get_main_queue(),^{
            if([view.accessibilityIdentifier isEqualToString:address])view.image=image;
        });
    }] resume];
}

@interface BLPlayerController : MPMoviePlayerViewController
@property(nonatomic,strong) UIButton *speedButton;
@property(nonatomic,assign) float preferredRate;
@end
@implementation BLPlayerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredRate=1.0f;
    self.moviePlayer.controlStyle=MPMovieControlStyleFullscreen;
    self.moviePlayer.shouldAutoplay=YES;
    [self.moviePlayer setFullscreen:YES animated:NO];
    UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdToSpeed:)];
    hold.minimumPressDuration=.38;hold.cancelsTouchesInView=NO;
    [self.moviePlayer.view addGestureRecognizer:hold];
    UIButton *speed=[UIButton buttonWithType:UIButtonTypeCustom];
    speed.frame=CGRectMake(9,43,82,33);
    speed.autoresizingMask=UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
    speed.backgroundColor=[UIColor colorWithWhite:0 alpha:.60];
    speed.layer.cornerRadius=8;speed.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    [speed setTitle:@"倍速 1.0×" forState:UIControlStateNormal];
    [speed addTarget:self action:@selector(changeSpeed) forControlEvents:UIControlEventTouchUpInside];
    [self.moviePlayer.view addSubview:speed];
    self.speedButton=speed;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackChanged:)
      name:MPMoviePlayerPlaybackStateDidChangeNotification object:self.moviePlayer];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)playbackChanged:(NSNotification *)note {
    if(self.moviePlayer.playbackState==MPMoviePlaybackStatePlaying && self.preferredRate!=1.0f)
        self.moviePlayer.currentPlaybackRate=self.preferredRate;
}
- (void)changeSpeed {
    NSArray *speeds=@[@1.0,@1.25,@1.5,@2.0,@0.75];
    NSUInteger index=0;
    for(NSUInteger i=0;i<speeds.count;i++)if(fabsf([speeds[i] floatValue]-self.preferredRate)<.01){index=i;break;}
    self.preferredRate=[speeds[(index+1)%speeds.count] floatValue];
    self.moviePlayer.currentPlaybackRate=self.preferredRate;
    [self.speedButton setTitle:[NSString stringWithFormat:@"倍速 %.2g×",self.preferredRate] forState:UIControlStateNormal];
}
- (void)holdToSpeed:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan) {
        self.moviePlayer.currentPlaybackRate=2.0f;
        [self.speedButton setTitle:@"按住 2×" forState:UIControlStateNormal];
    }else if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){
        self.moviePlayer.currentPlaybackRate=self.preferredRate;
        [self.speedButton setTitle:[NSString stringWithFormat:@"倍速 %.2g×",self.preferredRate] forState:UIControlStateNormal];
    }
}
@end

@interface BLDetailController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) NSDictionary *video;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *meta;
@property(nonatomic,strong) UITextView *descriptionBox;
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UITableView *relatedTable;
@property(nonatomic,strong) UIButton *favoriteButton;
@property(nonatomic,strong) UIButton *playButton;
@property(nonatomic,strong) NSArray *related;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,strong) BLPlayerController *player;
@property(nonatomic,strong) UIScrollView *scroll;
@end
@implementation BLDetailController
- (instancetype)initWithVideo:(NSDictionary *)video {
    if((self=[super init])){self.video=video?:@{};self.related=@[];self.imageCache=[NSCache new];self.imageCache.countLimit=15;}
    return self;
}
- (UIButton *)button:(NSString *)title x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.frame=CGRectMake(x,y,w,38);
    b.layer.cornerRadius=9;b.backgroundColor=BLPink();b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [b setTitle:title forState:UIControlStateNormal];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.scroll addSubview:b];return b;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"视频详情";self.view.backgroundColor=BLBg();
    CGFloat w=self.view.bounds.size.width;
    self.scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scroll];self.scroll.contentSize=CGSizeMake(w,700);
    self.cover=[[UIImageView alloc] initWithFrame:CGRectMake(12,10,w-24,153)];
    self.cover.backgroundColor=[UIColor colorWithWhite:.88 alpha:1];
    self.cover.contentMode=UIViewContentModeScaleAspectFit;[self.scroll addSubview:self.cover];
    self.titleLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,173,w-24,56)];
    self.titleLabel.textColor=BLInk();self.titleLabel.numberOfLines=2;
    self.titleLabel.font=[UIFont boldSystemFontOfSize:16];[self.scroll addSubview:self.titleLabel];
    self.meta=[[UILabel alloc] initWithFrame:CGRectMake(12,228,w-24,45)];
    self.meta.font=[UIFont systemFontOfSize:12];self.meta.numberOfLines=2;
    self.meta.textColor=[UIColor grayColor];[self.scroll addSubview:self.meta];
    self.playButton=[self button:@"全屏播放" x:12 y:279 w:104 action:@selector(playTapped)];
    self.favoriteButton=[self button:@"☆ 收藏" x:124 y:279 w:84 action:@selector(toggleFavorite)];
    [self button:@"复制链接" x:216 y:279 w:w-228 action:@selector(copyLink)];
    self.descriptionBox=[[UITextView alloc] initWithFrame:CGRectMake(12,329,w-24,80)];
    self.descriptionBox.editable=NO;self.descriptionBox.font=[UIFont systemFontOfSize:12];
    self.descriptionBox.textColor=BLInk();self.descriptionBox.backgroundColor=[UIColor whiteColor];
    self.descriptionBox.layer.cornerRadius=8;[self.scroll addSubview:self.descriptionBox];
    UILabel *relatedLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,425,w-24,30)];
    relatedLabel.text=@"相关推荐";relatedLabel.font=[UIFont boldSystemFontOfSize:17];
    relatedLabel.textColor=BLInk();[self.scroll addSubview:relatedLabel];
    self.relatedTable=[[UITableView alloc] initWithFrame:CGRectMake(10,462,w-20,233) style:UITableViewStylePlain];
    self.relatedTable.dataSource=self;self.relatedTable.delegate=self;
    self.relatedTable.rowHeight=57;self.relatedTable.scrollEnabled=NO;
    self.relatedTable.layer.cornerRadius=8;[self.scroll addSubview:self.relatedTable];
    [self render];[self loadDetails];
}
- (void)render {
    NSString *bvid=self.video[@"bvid"]?:@"";
    self.titleLabel.text=self.video[@"title"]?:bvid;
    self.meta.text=[NSString stringWithFormat:@"UP：%@   播放：%@\nBV：%@",self.video[@"author"]?:@"",self.video[@"view"]?:@"",bvid];
    self.descriptionBox.text=BLString(self.video[@"desc"]).length?self.video[@"desc"]:@"视频简介正在加载…";
    [self.favoriteButton setTitle:BLContains(@"bl_favorites_v1",bvid)?@"★ 已收藏":@"☆ 收藏" forState:UIControlStateNormal];
    BLFetchImage(BLString(self.video[@"pic"]),self.cover,self.imageCache);
}
- (void)loadDetails {
    NSString *bvid=BLString(self.video[@"bvid"]);if(!bvid.length)return;
    BLRequest([NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/view?bvid=%@",bvid],^(NSDictionary *json,NSError *error){
        NSDictionary *data=json[@"data"];
        if([data isKindOfClass:[NSDictionary class]] && [json[@"code"] integerValue]==0){
            NSMutableDictionary *full=BLNormalize(data);
            if(full){self.video=full;[self render];}
        }else self.descriptionBox.text=[NSString stringWithFormat:@"简介不可用：%@",BLFailure(json,error)];
    });
    BLRequest([NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/archive/related?bvid=%@",bvid],^(NSDictionary *json,NSError *err){
        NSArray *rows=[json[@"data"] isKindOfClass:[NSArray class]]?json[@"data"]:@[];
        NSMutableArray *related=[NSMutableArray array];
        for(NSDictionary *d in rows){NSDictionary *v=BLNormalize(d);if(v)[related addObject:v];if(related.count>=4)break;}
        self.related=related;
        [self.relatedTable reloadData];
    });
}
- (void)toggleFavorite {
    BOOL found=BLContains(@"bl_favorites_v1",BLString(self.video[@"bvid"]));
    BLStore(@"bl_favorites_v1",self.video,found);[self render];
}
- (void)copyLink {
    [UIPasteboard generalPasteboard].string=[@"https://www.bilibili.com/video/" stringByAppendingString:BLString(self.video[@"bvid"])];
    BLAlert(self,@"已复制",@"可以把视频链接粘贴到其他软件。");
}
- (void)playTapped {
    NSString *bvid=BLString(self.video[@"bvid"]),*cid=BLString(self.video[@"cid"]);
    if(!cid.length){BLAlert(self,@"暂不能播放",@"该视频没有返回 CID，或详情接口不可用。");return;}
    [self.playButton setTitle:@"获取播放地址…" forState:UIControlStateNormal];self.playButton.enabled=NO;
    NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/player/playurl?bvid=%@&cid=%@&qn=16&fnval=0&platform=html5",bvid,cid];
    BLRequest(url,^(NSDictionary *json,NSError *err){
        [self.playButton setTitle:@"全屏播放" forState:UIControlStateNormal];self.playButton.enabled=YES;
        NSDictionary *data=json[@"data"];
        NSArray *d=[data isKindOfClass:[NSDictionary class]]&&[data[@"durl"] isKindOfClass:[NSArray class]]?data[@"durl"]:@[];
        NSString *stream=d.count&&[d[0] isKindOfClass:[NSDictionary class]]?BLString(d[0][@"url"]):@"";
        if(![stream hasPrefix:@"https://"] && ![stream hasPrefix:@"http://"]){
            BLAlert(self,@"暂无法播放",[NSString stringWithFormat:@"B站未返回 iOS 8 可播放的 MP4 地址。\n%@\n\n会员、DRM、DASH 与新编码视频目前不支持。",BLFailure(json,err)]);
            return;
        }
        BLStore(@"bl_history_v1",self.video,NO);
        self.player=[[BLPlayerController alloc] initWithContentURL:[NSURL URLWithString:stream]];
        [self presentMoviePlayerViewControllerAnimated:self.player];
        [self.player.moviePlayer play];
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.related.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"related"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"related"];
    NSDictionary *v=self.related[index.row];
    cell.textLabel.text=v[@"title"];cell.textLabel.font=[UIFont systemFontOfSize:13];
    cell.detailTextLabel.text=v[@"author"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    [self.navigationController pushViewController:[[BLDetailController alloc] initWithVideo:self.related[index.row]] animated:YES];
}
@end

@interface BLListController : UITableViewController <UISearchBarDelegate,UITextFieldDelegate>
@property(nonatomic,strong) UISearchBar *search;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,copy) NSString *query;
@property(nonatomic,assign) NSInteger mode;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) BOOL loading;
@end
@implementation BLListController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"BiliLite 2";
    self.navigationController.navigationBar.barTintColor=[UIColor whiteColor];
    self.navigationController.navigationBar.tintColor=BLPink();
    self.navigationController.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:BLInk()};
    self.tableView.backgroundColor=BLBg();self.tableView.rowHeight=82;
    self.imageCache=[NSCache new];self.imageCache.countLimit=25;
    self.items=@[];self.mode=0;self.page=1;
    CGFloat w=self.view.bounds.size.width;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,98)];
    header.backgroundColor=BLBg();
    self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,w,51)];
    self.search.placeholder=@"搜视频、粘贴 BV 号或完整链接";
    self.search.delegate=self;self.search.tintColor=BLPink();
    [header addSubview:self.search];
    self.segments=[[UISegmentedControl alloc] initWithItems:@[@"热门",@"搜索",@"收藏",@"历史"]];
    self.segments.frame=CGRectMake(9,54,w-18,36);
    self.segments.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.segments.selectedSegmentIndex=0;
    [self.segments addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.segments];
    self.tableView.tableHeaderView=header;
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,52)];
    UIButton *more=[UIButton buttonWithType:UIButtonTypeSystem];more.frame=CGRectMake(12,5,w-24,42);
    [more setTitle:@"加载更多" forState:UIControlStateNormal];
    [more setTitleColor:BLPink() forState:UIControlStateNormal];
    [more addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:more];self.tableView.tableFooterView=footer;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"BV号"
      style:UIBarButtonItemStylePlain target:self action:@selector(openByBV)];
    UIRefreshControl *refresh=[UIRefreshControl new];[refresh addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventValueChanged];
    self.refreshControl=refresh;
    [self fetch];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(self.mode>=2)[self loadLocal];
}
- (void)changed:(UISegmentedControl *)control {
    self.mode=control.selectedSegmentIndex;self.page=1;self.items=@[];
    [self.tableView reloadData];
    if(self.mode>=2)[self loadLocal];else if(self.mode==0)[self fetch];
    else if(self.query.length)[self fetch];else[self showMessage:@"在上方输入关键词，点击键盘上的搜索"];
    [self.search resignFirstResponder];
}
- (void)showMessage:(NSString *)message {
    self.tableView.backgroundView=nil;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(18,0,self.view.bounds.size.width-36,120)];
    label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;label.textColor=[UIColor grayColor];
    label.font=[UIFont systemFontOfSize:13];label.text=message;
    self.tableView.backgroundView=label;
}
- (void)loadLocal {
    NSString *key=self.mode==2?@"bl_favorites_v1":@"bl_history_v1";
    self.items=BLStored(key);
    [self.tableView reloadData];
    [self showMessage:self.items.count?@"":@"这里暂时没有视频。打开视频详情后可以收藏或产生观看历史。"];
}
- (void)refreshTapped {[self refresh];}
- (void)refresh {
    self.page=1;self.items=@[];
    [self.tableView reloadData];
    if(self.mode>=2){[self loadLocal];[self.refreshControl endRefreshing];}
    else [self fetch];
}
- (void)loadMore {
    if(self.mode>=2 || self.loading)return;
    if(self.mode==1&&!self.query.length)return;
    self.page++;[self fetch];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    NSString *text=[bar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [bar resignFirstResponder];if(!text.length)return;
    NSString *bvid=BLBV(text);
    if(bvid){[self openVideo:@{@"bvid":bvid,@"title":bvid}];return;}
    self.query=text;self.mode=1;self.segments.selectedSegmentIndex=1;[self refresh];
}
- (void)fetch {
    if(self.loading)return;
    if(self.mode>=2){[self loadLocal];return;}
    self.loading=YES;[UIApplication sharedApplication].networkActivityIndicatorVisible=YES;
    NSString *url=nil;
    if(self.mode==0)url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/popular?ps=20&pn=%ld",(long)self.page];
    else {
        NSString *encoded=[self.query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=%ld",encoded,(long)self.page];
    }
    NSInteger requestedMode=self.mode,requestedPage=self.page;
    BLJSONCallback completion=^(NSDictionary *json,NSError *error){
        if(self.mode!=requestedMode || self.page!=requestedPage)return;
        self.loading=NO;[UIApplication sharedApplication].networkActivityIndicatorVisible=NO;
        [self.refreshControl endRefreshing];
        id data=json[@"data"];NSArray *rows=nil;
        if([data isKindOfClass:[NSDictionary class]])rows=self.mode==0?data[@"list"]:data[@"result"];
        if(![rows isKindOfClass:[NSArray class]] || [json[@"code"] integerValue]!=0){
            [self showMessage:[NSString stringWithFormat:@"获取视频列表失败：%@\n可以试试 BV号 入口，或稍后重试。",BLFailure(json,error)]];
            if(self.page>1)self.page--;
            return;
        }
        NSMutableArray *list=[self.items mutableCopy]?:[NSMutableArray array];
        for(NSDictionary *raw in rows) {
            NSDictionary *video=BLNormalize(raw);
            if(!video)continue;
            BOOL duplicate=NO;
            for(NSDictionary *item in list)if([item[@"bvid"] isEqualToString:video[@"bvid"]]){duplicate=YES;break;}
            if(!duplicate)[list addObject:video];
        }
        self.items=list;[self.tableView reloadData];
        [self showMessage:list.count?@"":@"当前没有符合条件的视频"];
    };
    if(self.mode==1)BLSearch(self.query,self.page,completion);
    else BLRequest(url,completion);
}
- (void)openByBV {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"打开视频" message:@"输入 BV 号或完整视频链接" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){
        field.placeholder=@"BV1xxxxxxxxxx";
        field.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"bl_last_bv"];
        field.autocorrectionType=UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *bvid=BLBV(alert.textFields.firstObject.text);
        if(!bvid){BLAlert(self,@"格式错误",@"请输入正确的 BV 号");return;}
        [self openVideo:@{@"bvid":bvid,@"title":bvid}];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openVideo:(NSDictionary *)video {
    if(!BLString(video[@"bvid"]).length)return;
    [[NSUserDefaults standardUserDefaults] setObject:video[@"bvid"] forKey:@"bl_last_bv"];
    [self.navigationController pushViewController:[[BLDetailController alloc] initWithVideo:video] animated:YES];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"video"];
    if(!cell){
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"video"];
        UIImageView *cover=[[UIImageView alloc] initWithFrame:CGRectMake(10,10,95,61)];
        cover.tag=911;cover.contentMode=UIViewContentModeScaleAspectFill;cover.clipsToBounds=YES;cover.layer.cornerRadius=5;
        cover.backgroundColor=[UIColor colorWithWhite:.91 alpha:1];[cell.contentView addSubview:cover];
        UILabel *name=[[UILabel alloc] initWithFrame:CGRectMake(114,9,190,46)];
        name.tag=912;name.font=[UIFont boldSystemFontOfSize:13];name.numberOfLines=2;name.textColor=BLInk();
        name.autoresizingMask=UIViewAutoresizingFlexibleWidth;[cell.contentView addSubview:name];
        UILabel *info=[[UILabel alloc] initWithFrame:CGRectMake(114,55,190,19)];
        info.tag=913;info.font=[UIFont systemFontOfSize:11];info.textColor=[UIColor grayColor];
        info.autoresizingMask=UIViewAutoresizingFlexibleWidth;[cell.contentView addSubview:info];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary *video=self.items[index.row];
    ((UILabel *)[cell.contentView viewWithTag:912]).text=video[@"title"];
    ((UILabel *)[cell.contentView viewWithTag:913]).text=[NSString stringWithFormat:@"%@ · %@",video[@"author"]?:@"",video[@"view"]?:@""];
    UIImageView *cover=[cell.contentView viewWithTag:911];
    cover.accessibilityIdentifier=video[@"pic"];BLFetchImage(video[@"pic"],cover,self.imageCache);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    [self openVideo:self.items[index.row]];
}
@end
@interface BLApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation BLApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[[BLListController alloc] initWithStyle:UITableViewStylePlain]];
    self.window.rootViewController=navigation;[self.window makeKeyAndVisible];
    return YES;
}
- (UIInterfaceOrientationMask)application:(UIApplication *)app supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([BLApp class]));}}
