#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>
#import <CommonCrypto/CommonDigest.h>
#include <string.h>
#include <time.h>
#import <Security/Security.h>
#import <CoreImage/CoreImage.h>

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
       @"desc":BLString(d[@"desc"]),@"cid":BLString(d[@"cid"]),@"aid":BLString(d[@"aid"]),
       @"duration":BLString(d[@"duration"]),@"view":BLString(d[@"play"]).length?BLString(d[@"play"]):BLString(stat[@"view"]),
       @"like":BLString(stat[@"like"]),@"favorite":BLString(stat[@"favorite"])} mutableCopy];
}
static NSArray *BLStored(NSString *key){
    id rows=[[NSUserDefaults standardUserDefaults] arrayForKey:key];
    return [rows isKindOfClass:[NSArray class]]?rows:@[];
}
static NSString *BLIdentityKey(NSString *key){
    return [key isEqualToString:@"bl_live_favorites_v1"]?@"roomid":@"bvid";
}
static BOOL BLContains(NSString *key,NSString *identifier){
    NSString *field=BLIdentityKey(key);
    if(!identifier.length)return NO;
    for(NSDictionary *v in BLStored(key))if([BLString(v[field]) isEqualToString:identifier])return YES;
    return NO;
}
static void BLStore(NSString *key,NSDictionary *item,BOOL remove){
    NSString *field=BLIdentityKey(key);
    NSString *identifier=BLString(item[field]);
    if(!identifier.length)return;
    NSMutableArray *list=[NSMutableArray array];
    for(NSDictionary *v in BLStored(key))if(![BLString(v[field]) isEqualToString:identifier])[list addObject:v];
    if(!remove)[list insertObject:item atIndex:0];
    while(list.count>70)[list removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:key];
}
static void BLAlert(UIViewController *vc,NSString *title,NSString *message){
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}


// All account secrets live in iOS Keychain (not NSUserDefaults, source, or logs).
static NSString *const BLAccountService=@"com.finn.bililite.account";
static NSString *const BLAccountKey=@"session";
static NSDictionary *BLSession(void){
    NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService:BLAccountService,(__bridge id)kSecAttrAccount:BLAccountKey,
      (__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne};
    CFTypeRef answer=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&answer);
    if(status!=errSecSuccess || !answer)return nil;
    NSData *data=CFBridgingRelease(answer);
    id saved=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [saved isKindOfClass:[NSDictionary class]]?saved:nil;
}
static BOOL BLSaveSession(NSDictionary *values){
    NSMutableDictionary *safe=[NSMutableDictionary dictionary];
    for(NSString *name in @[@"SESSDATA",@"DedeUserID",@"DedeUserID__ckMd5",@"bili_jct",@"sid"]){
        NSString *value=BLString(values[name]);if(value.length)safe[name]=value;
    }
    if(!BLString(safe[@"SESSDATA"]).length)return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:safe options:0 error:NULL];
    if(!data)return NO;
    NSDictionary *match=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:BLAccountService,(__bridge id)kSecAttrAccount:BLAccountKey};
    SecItemDelete((__bridge CFDictionaryRef)match);
    NSMutableDictionary *entry=[match mutableCopy];
    entry[(__bridge id)kSecValueData]=data;
    entry[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)entry,NULL)==errSecSuccess;
}
static void BLClearSession(void){
    NSDictionary *match=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
       (__bridge id)kSecAttrService:BLAccountService,(__bridge id)kSecAttrAccount:BLAccountKey};
    SecItemDelete((__bridge CFDictionaryRef)match);
    NSHTTPCookieStorage *storage=[NSHTTPCookieStorage sharedHTTPCookieStorage];
    for(NSHTTPCookie *cookie in storage.cookies){
        if([cookie.domain hasSuffix:@".bilibili.com"] || [cookie.domain isEqualToString:@"bilibili.com"])
            [storage deleteCookie:cookie];
    }
}
static NSString *BLAuthCookie(void){
    NSDictionary *session=BLSession();
    NSMutableArray *parts=[NSMutableArray array];
    for(NSString *name in @[@"SESSDATA",@"DedeUserID",@"DedeUserID__ckMd5",@"bili_jct",@"sid"]){
        NSString *value=BLString(session[name]);
        if(value.length)[parts addObject:[NSString stringWithFormat:@"%@=%@",name,value]];
    }
    return [parts componentsJoinedByString:@"; "];
}
static NSDictionary *BLCookiesFromResponse(NSHTTPURLResponse *response){
    NSMutableDictionary *session=[NSMutableDictionary dictionary];
    NSURL *url=response.URL?:[NSURL URLWithString:@"https://passport.bilibili.com"];
    NSMutableArray *cookies=[NSMutableArray array];
    [cookies addObjectsFromArray:[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:url]?:@[]];
    if(response.allHeaderFields.count){
        [cookies addObjectsFromArray:[NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:url]?:@[]];
    }
    for(NSHTTPCookie *cookie in cookies){
        if([@[@"SESSDATA",@"DedeUserID",@"DedeUserID__ckMd5",@"bili_jct",@"sid"] containsObject:cookie.name])
            session[cookie.name]=cookie.value?:@"";
    }
    return session;
}
typedef void(^BLAuthCallback)(NSDictionary *,NSDictionary *,NSError *);
static void BLPollLogin(NSString *qrKey,BLAuthCallback done){
    NSString *escaped=[qrKey stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *url=[NSURL URLWithString:[@"https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=" stringByAppendingString:escaped?:@""]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [request setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSDictionary *json=nil;
        if(!error && data.length){
            id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if([decoded isKindOfClass:[NSDictionary class]])json=decoded;
        }
        NSDictionary *cookies=([response isKindOfClass:[NSHTTPURLResponse class]])?BLCookiesFromResponse((NSHTTPURLResponse *)response):@{};
        dispatch_async(dispatch_get_main_queue(),^{if(done)done(json,cookies,error);});
    }] resume];
}
static UIImage *BLQRImage(NSString *text){
    NSData *utf8=[text dataUsingEncoding:NSUTF8StringEncoding];
    if(!utf8.length)return nil;
    CIFilter *filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:utf8 forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *input=[filter outputImage];
    if(!input)return nil;
    CIContext *context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];
    CGImageRef bitmap=[context createCGImage:input fromRect:input.extent];
    if(!bitmap)return nil;
    UIImage *qr=[UIImage imageWithCGImage:bitmap];
    CGImageRelease(bitmap);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(228,228),YES,1);
    CGContextRef graphic=UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(graphic,kCGInterpolationNone);
    [[UIColor whiteColor] setFill];UIRectFill(CGRectMake(0,0,228,228));
    [qr drawInRect:CGRectMake(12,12,204,204)];
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

typedef void(^BLJSONCallback)(NSDictionary *,NSError *);
static void BLRequest(NSString *url,BLJSONCallback done){
    NSURL *endpoint=[NSURL URLWithString:url];
    if(!endpoint){if(done)done(nil,[NSError errorWithDomain:@"URL格式无效" code:1 userInfo:nil]);return;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:endpoint cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [req setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 8_4_1 like Mac OS X) AppleWebKit/600.1.4 Mobile/12H321" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    NSString *host=[[endpoint host] lowercaseString];
    // Never send login cookies to third-party image/CDN or arbitrary URLs.
    if([host isEqualToString:@"api.bilibili.com"] || [host isEqualToString:@"api.live.bilibili.com"]){
        NSString *cookie=BLAuthCookie();
        if(cookie.length)[req setValue:cookie forHTTPHeaderField:@"Cookie"];
    }
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
            long long now=(long long)time(NULL);
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
@property(nonatomic,strong) UILabel *liveBadge;
@property(nonatomic,strong) UILabel *playerHint;
@property(nonatomic,assign) BOOL liveStream;
@property(nonatomic,assign) BOOL speedControlVisible;
@property(nonatomic,assign) float preferredRate;
@property(nonatomic,copy) NSString *videoKey;
@property(nonatomic,assign) NSTimeInterval resumeAt;
@property(nonatomic,assign) BOOL didResume;
@property(nonatomic,assign) BOOL holdingSpeed;
@property(nonatomic,assign) BOOL completedPlayback;
@property(nonatomic,strong) NSTimer *saveTimer;
@end
@implementation BLPlayerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredRate=1.0f;
    self.moviePlayer.controlStyle=MPMovieControlStyleFullscreen;
    self.moviePlayer.shouldAutoplay=YES;
    [self.moviePlayer setFullscreen:YES animated:NO];
    if(self.liveStream){
        UILabel *badge=[[UILabel alloc] initWithFrame:CGRectMake(0,0,73,28)];
        badge.text=@"● 直播中";badge.textAlignment=NSTextAlignmentCenter;
        badge.textColor=[UIColor whiteColor];
        badge.font=[UIFont boldSystemFontOfSize:12];
        badge.layer.cornerRadius=7;badge.clipsToBounds=YES;
        badge.backgroundColor=[UIColor colorWithRed:.86 green:.20 blue:.30 alpha:.86];
        badge.userInteractionEnabled=NO;
        [self.moviePlayer.view addSubview:badge];self.liveBadge=badge;
    }else{
        UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdToSpeed:)];
        hold.minimumPressDuration=.42;hold.cancelsTouchesInView=NO;
        [self.moviePlayer.view addGestureRecognizer:hold];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
        tap.cancelsTouchesInView=NO;tap.delegate=nil;
        [self.moviePlayer.view addGestureRecognizer:tap];
        UIButton *speed=[UIButton buttonWithType:UIButtonTypeCustom];
        speed.frame=CGRectMake(0,0,88,34);
        speed.backgroundColor=[UIColor colorWithRed:.10 green:.12 blue:.17 alpha:.84];
        speed.layer.cornerRadius=17;
        speed.layer.borderWidth=.5;
        speed.layer.borderColor=[UIColor colorWithWhite:1 alpha:.25].CGColor;
        speed.titleLabel.font=[UIFont boldSystemFontOfSize:12];
        [speed setTitle:@"倍速 1.0×" forState:UIControlStateNormal];
        [speed addTarget:self action:@selector(changeSpeed) forControlEvents:UIControlEventTouchUpInside];
        [self.moviePlayer.view addSubview:speed];
        self.speedButton=speed;
        speed.alpha=0;speed.userInteractionEnabled=NO;
    }
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(0,0,224,29)];
    hint.backgroundColor=[UIColor colorWithWhite:0 alpha:.62];
    hint.text=self.liveStream?@"直播模式 · 仅支持兼容 HLS":@"轻点显示倍速 · 长按临时 2×";
    hint.textColor=[UIColor whiteColor];hint.textAlignment=NSTextAlignmentCenter;
    hint.font=[UIFont systemFontOfSize:11];hint.layer.cornerRadius=14;hint.clipsToBounds=YES;
    hint.userInteractionEnabled=NO;
    [self.moviePlayer.view addSubview:hint];self.playerHint=hint;
    [self positionPlayerOverlay];
    [self performSelector:@selector(hidePlayerHint) withObject:nil afterDelay:3.5];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackChanged:)
      name:MPMoviePlayerPlaybackStateDidChangeNotification object:self.moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieLoaded:)
      name:MPMoviePlayerLoadStateDidChangeNotification object:self.moviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieFinished:)
      name:MPMoviePlayerPlaybackDidFinishNotification object:self.moviePlayer];
    self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(savePosition)
       userInfo:nil repeats:YES];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self positionPlayerOverlay];
}
- (void)positionPlayerOverlay {
    CGRect b=self.moviePlayer.view.bounds;
    if(b.size.width<1 || b.size.height<1)return;
    if(self.liveBadge)self.liveBadge.frame=CGRectMake(MAX(8,b.size.width-87),12,73,28);
    if(self.playerHint)self.playerHint.frame=CGRectMake(MAX(0,(b.size.width-224)/2),MAX(42,b.size.height-161),224,29);
    if(self.speedButton)self.speedButton.frame=CGRectMake(MAX(8,b.size.width-104),MAX(42,b.size.height-116),88,34);
}
- (void)hidePlayerHint {
    [UIView animateWithDuration:.35 animations:^{self.playerHint.alpha=0;}];
}
- (void)playerTapped:(UITapGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateEnded || self.liveStream)return;
    [self revealSpeedControl];
}
- (void)revealSpeedControl {
    if(self.liveStream || !self.speedButton)return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSpeedControl) object:nil];
    self.speedControlVisible=YES;self.speedButton.userInteractionEnabled=YES;
    [UIView animateWithDuration:.18 animations:^{self.speedButton.alpha=1;}];
    [self performSelector:@selector(hideSpeedControl) withObject:nil afterDelay:3.2];
}
- (void)hideSpeedControl {
    if(self.holdingSpeed)return;
    self.speedControlVisible=NO;
    [UIView animateWithDuration:.22 animations:^{self.speedButton.alpha=0;} completion:^(BOOL finished){
        if(!self.speedControlVisible)self.speedButton.userInteractionEnabled=NO;
    }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSpeedControl) object:nil];
    if(!self.completedPlayback)[self savePosition];
    [super viewWillDisappear:animated];
}
- (void)dealloc {
    [self.saveTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)movieLoaded:(NSNotification *)notification {
    if(!self.didResume && self.resumeAt>5 && (self.moviePlayer.loadState&MPMovieLoadStatePlayable)){
        self.didResume=YES;
        self.moviePlayer.currentPlaybackTime=self.resumeAt;
    }
}
- (void)savePosition {
    if(!self.videoKey.length || self.completedPlayback)return;
    NSTimeInterval seconds=self.moviePlayer.currentPlaybackTime;
    if(seconds<0 || isnan(seconds) || isinf(seconds))return;
    NSMutableDictionary *saved=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"] mutableCopy]?:[NSMutableDictionary dictionary];
    if(saved.count>100){
        for(NSString *key in [[saved allKeys] subarrayWithRange:NSMakeRange(0,20)]) [saved removeObjectForKey:key];
    }
    NSTimeInterval duration=self.moviePlayer.duration;
    if(duration>0 && seconds>duration-12) [saved removeObjectForKey:self.videoKey];
    else saved[self.videoKey]=@(seconds);
    [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"bl_playback_positions"];
}
- (void)movieFinished:(NSNotification *)notification {
    NSInteger reason=[notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    if(reason==MPMovieFinishReasonPlaybackEnded){
        self.completedPlayback=YES;
        if(self.videoKey.length){
            NSMutableDictionary *saved=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"] mutableCopy]?:[NSMutableDictionary dictionary];
            [saved removeObjectForKey:self.videoKey];
            [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"bl_playback_positions"];
        }
    }else if(reason==MPMovieFinishReasonPlaybackError){
        BLAlert(self,@"视频播放失败",@"当前视频地址可能已过期、不支持该编码，或 B 站要求额外鉴权。可以尝试其他清晰度或分P。");
    }
}
- (void)playbackChanged:(NSNotification *)note {
    if(!self.liveStream && self.moviePlayer.playbackState==MPMoviePlaybackStatePlaying)
        self.moviePlayer.currentPlaybackRate=self.holdingSpeed?2.0f:self.preferredRate;
}
- (void)changeSpeed {
    if(self.liveStream)return;
    NSArray *speeds=@[@1.0,@1.25,@1.5,@2.0,@0.75];
    NSUInteger index=0;
    for(NSUInteger i=0;i<speeds.count;i++)if(fabsf([speeds[i] floatValue]-self.preferredRate)<.01){index=i;break;}
    self.preferredRate=[speeds[(index+1<speeds.count)?index+1:0] floatValue];
    self.moviePlayer.currentPlaybackRate=self.preferredRate;
    [self.speedButton setTitle:[NSString stringWithFormat:@"倍速 %.2g×",self.preferredRate] forState:UIControlStateNormal];
    [self revealSpeedControl];
}
- (void)holdToSpeed:(UILongPressGestureRecognizer *)gesture {
    if(self.liveStream)return;
    if(gesture.state==UIGestureRecognizerStateBegan) {
        [self revealSpeedControl];
        self.holdingSpeed=YES;
        self.moviePlayer.currentPlaybackRate=2.0f;
        [self.speedButton setTitle:@"按住 2×" forState:UIControlStateNormal];
    }else if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){
        self.holdingSpeed=NO;
        self.moviePlayer.currentPlaybackRate=self.preferredRate;
        [self.speedButton setTitle:[NSString stringWithFormat:@"倍速 %.2g×",self.preferredRate] forState:UIControlStateNormal];
        [self revealSpeedControl];
    }
}
@end


@interface BLCommentsController : UITableViewController
@property(nonatomic,copy) NSString *aid;
@property(nonatomic,strong) NSArray *comments;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) BOOL loading;
@end
@implementation BLCommentsController
- (instancetype)initWithAid:(NSString *)aid {
    if((self=[super initWithStyle:UITableViewStylePlain])){self.aid=aid;self.comments=@[];self.page=1;}
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"视频评论（只读）";
    self.tableView.backgroundColor=BLBg();
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=90;
    UIButton *more=[UIButton buttonWithType:UIButtonTypeSystem];more.frame=CGRectMake(12,4,self.view.bounds.size.width-24,42);
    [more setTitle:@"加载更多评论" forState:UIControlStateNormal];
    [more addTarget:self action:@selector(loadNext) forControlEvents:UIControlEventTouchUpInside];
    UIView *foot=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,55)];
    [foot addSubview:more];self.tableView.tableFooterView=foot;
    [self loadNext];
}
- (void)loadNext {
    if(self.loading||!self.aid.length)return;
    self.loading=YES;
    NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/v2/reply?type=1&oid=%@&pn=%ld&ps=15&sort=2",self.aid,(long)self.page];
    BLRequest(url,^(NSDictionary *json,NSError *err){
        self.loading=NO;
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        NSArray *rows=[data[@"replies"] isKindOfClass:[NSArray class]]?data[@"replies"]:@[];
        if(err || [json[@"code"] integerValue]!=0){
            BLAlert(self,@"评论暂不可用",[NSString stringWithFormat:@"%@\n有些评论需要登录或 B 站验证码。",BLFailure(json,err)]);return;
        }
        if(!rows.count){if(!self.comments.count)BLAlert(self,@"没有评论",@"该视频可能关闭了评论，或接口没有提供公开评论。");return;}
        NSMutableArray *items=[self.comments mutableCopy];
        for(NSDictionary *v in rows){
            NSDictionary *member=[v[@"member"] isKindOfClass:[NSDictionary class]]?v[@"member"]:@{};
            NSDictionary *content=[v[@"content"] isKindOfClass:[NSDictionary class]]?v[@"content"]:@{};
            NSString *name=BLString(member[@"uname"]),*comment=BLString(content[@"message"]);
            if(comment.length)[items addObject:@{@"name":name,@"text":comment}];
        }
        self.comments=items;self.page++;[self.tableView reloadData];
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.comments.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"comment"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"comment"];
    NSDictionary *item=self.comments[index.row];
    cell.backgroundColor=[UIColor whiteColor];
    cell.textLabel.text=item[@"name"];cell.textLabel.textColor=BLPink();
    cell.textLabel.font=[UIFont boldSystemFontOfSize:12];
    cell.detailTextLabel.text=item[@"text"];cell.detailTextLabel.numberOfLines=0;
    cell.detailTextLabel.font=[UIFont systemFontOfSize:13];
    return cell;
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
@property(nonatomic,strong) UIButton *partButton;
@property(nonatomic,strong) UIButton *qualityButton;
@property(nonatomic,strong) NSArray *parts;
@property(nonatomic,copy) NSString *selectedCID;
@property(nonatomic,assign) NSInteger quality;
@end
@implementation BLDetailController
- (instancetype)initWithVideo:(NSDictionary *)video {
    if((self=[super init])){self.video=video?:@{};self.related=@[];self.parts=@[];self.quality=16;self.selectedCID=BLString(video[@"cid"]);self.imageCache=[NSCache new];self.imageCache.countLimit=15;}
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
    [self.view addSubview:self.scroll];self.scroll.contentSize=CGSizeMake(w,765);
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
    self.partButton=[self button:@"选集 P1" x:12 y:420 w:90 action:@selector(choosePart)];
    self.qualityButton=[self button:@"清晰度 360P" x:107 y:420 w:107 action:@selector(chooseQuality)];
    [self button:@"评论" x:219 y:420 w:w-231 action:@selector(openComments)];
    UILabel *relatedLabel=[[UILabel alloc] initWithFrame:CGRectMake(12,468,w-24,30)];
    relatedLabel.text=@"相关推荐";relatedLabel.font=[UIFont boldSystemFontOfSize:17];
    relatedLabel.textColor=BLInk();[self.scroll addSubview:relatedLabel];
    self.relatedTable=[[UITableView alloc] initWithFrame:CGRectMake(10,505,w-20,233) style:UITableViewStylePlain];
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
    if(self.partButton){
        NSUInteger index=0;
        for(NSUInteger i=0;i<self.parts.count;i++)if([BLString(self.parts[i][@"cid"]) isEqualToString:self.selectedCID]){index=i;break;}
        [self.partButton setTitle:[NSString stringWithFormat:@"选集 P%lu",(unsigned long)(index+1)] forState:UIControlStateNormal];
    }
    BLFetchImage(BLString(self.video[@"pic"]),self.cover,self.imageCache);
}
- (void)loadDetails {
    NSString *bvid=BLString(self.video[@"bvid"]);if(!bvid.length)return;
    BLRequest([NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/view?bvid=%@",bvid],^(NSDictionary *json,NSError *error){
        NSDictionary *data=json[@"data"];
        if([data isKindOfClass:[NSDictionary class]] && [json[@"code"] integerValue]==0){
            NSMutableDictionary *full=BLNormalize(data);
            if(full){
                self.video=full;
                self.parts=[data[@"pages"] isKindOfClass:[NSArray class]]?data[@"pages"]:@[];
                // A saved CID may represent P2 or later; preserve it only when present.
                BOOL valid=NO;
                for(NSDictionary *part in self.parts)if([BLString(part[@"cid"]) isEqualToString:self.selectedCID]){valid=YES;break;}
                if(!valid)self.selectedCID=BLString(data[@"cid"]);
                [self render];
            }
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
- (void)choosePart {
    if(!self.parts.count){BLAlert(self,@"暂无分P信息",@"请检查视频详情是否加载成功。");return;}
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"选择分P" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    // Keep only 8 actions per sheet for the 3.5-inch iPhone 4S screen.
    NSUInteger currentIndex=0;
    for(NSUInteger i=0;i<self.parts.count;i++)if([BLString(self.parts[i][@"cid"]) isEqualToString:self.selectedCID]){currentIndex=i;break;}
    NSUInteger begin=(currentIndex/8)*8;
    [self fillPartMenu:menu start:begin];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)fillPartMenu:(UIAlertController *)menu start:(NSUInteger)begin {
    NSUInteger end=MIN(self.parts.count,begin+8);
    for(NSUInteger i=begin;i<end;i++){
        NSDictionary *part=self.parts[i];
        NSString *label=[NSString stringWithFormat:@"P%lu  %@",(unsigned long)(i+1),BLString(part[@"part"])];
        NSString *cid=BLString(part[@"cid"]);
        [menu addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            self.selectedCID=cid;[self render];
        }]];
    }
    if(end<self.parts.count)[menu addAction:[UIAlertAction actionWithTitle:@"更多分P…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        UIAlertController *next=[UIAlertController alertControllerWithTitle:@"选择分P" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [self fillPartMenu:next start:end];[self presentViewController:next animated:YES completion:nil];
    }]];
    if(begin>0)[menu addAction:[UIAlertAction actionWithTitle:@"上一组分P" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        UIAlertController *prev=[UIAlertController alertControllerWithTitle:@"选择分P" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [self fillPartMenu:prev start:begin-8];[self presentViewController:prev animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
}
- (void)chooseQuality {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"播放清晰度" message:@"会优先请求兼容 iPhone 4S 的单文件 MP4。高清选项可能需要登录。" preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSNumber *value in @[@16,@32,@64]){
        NSString *name=[value integerValue]==16?@"360P（最稳定）":[value integerValue]==32?@"480P":@"720P";
        [menu addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            self.quality=[value integerValue];
            [self.qualityButton setTitle:[NSString stringWithFormat:@"清晰度 %@",name] forState:UIControlStateNormal];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)openComments {
    NSString *aid=BLString(self.video[@"aid"]);
    if(!aid.length){BLAlert(self,@"评论暂不可用",@"需要先获取视频 AV 号，请稍后再试。");return;}
    [self.navigationController pushViewController:[[BLCommentsController alloc] initWithAid:aid] animated:YES];
}
- (void)playTapped {
    NSString *bvid=BLString(self.video[@"bvid"]),*cid=self.selectedCID.length?self.selectedCID:BLString(self.video[@"cid"]);
    if(!cid.length){BLAlert(self,@"暂不能播放",@"该视频没有返回 CID，或详情接口不可用。");return;}
    [self.playButton setTitle:@"获取播放地址…" forState:UIControlStateNormal];self.playButton.enabled=NO;
    NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/player/playurl?bvid=%@&cid=%@&qn=%ld&fnval=0&platform=html5",bvid,cid,(long)self.quality];
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
        self.player.videoKey=[NSString stringWithFormat:@"%@:%@",bvid,cid];
        self.player.resumeAt=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"][self.player.videoKey] doubleValue];
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


static NSDictionary *BLRoom(NSDictionary *data){
    if(![data isKindOfClass:[NSDictionary class]])return nil;
    NSString *rid=BLString(data[@"roomid"]);
    if(!rid.length)rid=BLString(data[@"room_id"]);
    if(!rid.length)return nil;
    NSString *cover=BLString(data[@"cover"]);
    if(!cover.length)cover=BLString(data[@"user_cover"]);
    if(!cover.length)cover=BLString(data[@"keyframe"]);
    if([cover hasPrefix:@"//"])cover=[@"https:" stringByAppendingString:cover];
    NSString *area=BLString(data[@"area_v2_name"]);
    if(!area.length)area=BLString(data[@"area_name"]);
    return @{@"roomid":rid,@"title":BLString(data[@"title"]),@"uname":BLString(data[@"uname"]),
      @"cover":cover,@"online":BLString(data[@"online"]),@"area":area,
      @"live_status":data[@"live_status"]?:@1};
}
static NSString *BLRoomInput(NSString *text){
    if(!text.length)return nil;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"live[.]bilibili[.]com/(?:blanc/)?([0-9]{1,12})" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m=[re firstMatchInString:text options:0 range:NSMakeRange(0,text.length)];
    NSString *value=m?[text substringWithRange:[m rangeAtIndex:1]]:text;
    value=[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!value.length || value.length>12)return nil;
    if([value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound)return nil;
    return value;
}
static NSString *BLHLS(NSDictionary *json){
    NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
    NSDictionary *urlInfo=[data[@"playurl_info"] isKindOfClass:[NSDictionary class]]?data[@"playurl_info"]:@{};
    NSDictionary *play=[urlInfo[@"playurl"] isKindOfClass:[NSDictionary class]]?urlInfo[@"playurl"]:@{};
    NSArray *streams=[play[@"stream"] isKindOfClass:[NSArray class]]?play[@"stream"]:@[];
    for(NSDictionary *stream in streams){
        if(![BLString(stream[@"protocol_name"]) isEqualToString:@"http_hls"])continue;
        NSArray *formats=[stream[@"format"] isKindOfClass:[NSArray class]]?stream[@"format"]:@[];
        for(NSDictionary *format in formats){
            if(![BLString(format[@"format_name"]) isEqualToString:@"ts"])continue;
            NSArray *codecs=[format[@"codec"] isKindOfClass:[NSArray class]]?format[@"codec"]:@[];
            for(NSDictionary *codec in codecs){
                if(![BLString(codec[@"codec_name"]) isEqualToString:@"avc"])continue;
                NSString *base=BLString(codec[@"base_url"]);
                NSArray *urls=[codec[@"url_info"] isKindOfClass:[NSArray class]]?codec[@"url_info"]:@[];
                for(NSDictionary *u in urls){
                    NSString *host=BLString(u[@"host"]);
                    NSString *extra=BLString(u[@"extra"]);
                    NSString *full=[NSString stringWithFormat:@"%@%@%@",host,base,extra];
                    if(([full hasPrefix:@"https://"]||[full hasPrefix:@"http://"]) && [full rangeOfString:@".m3u8"].location!=NSNotFound)return full;
                }
            }
        }
    }
    return nil;
}

@interface BLRoomDetailController : UIViewController
@property(nonatomic,strong) NSDictionary *room;
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *info;
@property(nonatomic,strong) UIButton *playButton;
@property(nonatomic,strong) UIButton *favoriteButton;
@property(nonatomic,strong) UIButton *qualityButton;
@property(nonatomic,strong) BLPlayerController *player;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,assign) NSInteger quality;
@end
@implementation BLRoomDetailController
- (instancetype)initWithRoom:(NSDictionary *)room {
    if((self=[super init])){self.room=room?:@{};self.quality=80;self.imageCache=[NSCache new];self.imageCache.countLimit=4;}
    return self;
}
- (UIButton *)button:(NSString *)title frame:(CGRect)rect action:(SEL)selector {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.frame=rect;
    b.layer.cornerRadius=10;b.backgroundColor=BLPink();
    [b setTitle:title forState:UIControlStateNormal];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];return b;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"直播间";
    self.view.backgroundColor=BLBg();
    CGFloat w=self.view.bounds.size.width;
    UIScrollView *scroller=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroller.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroller];
    UIView *holder=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,580)];
    [scroller addSubview:holder];scroller.contentSize=holder.bounds.size;
    self.cover=[[UIImageView alloc] initWithFrame:CGRectMake(12,12,w-24,164)];
    self.cover.contentMode=UIViewContentModeScaleAspectFit;
    self.cover.backgroundColor=[UIColor colorWithWhite:.88 alpha:1];
    [holder addSubview:self.cover];
    self.heading=[[UILabel alloc] initWithFrame:CGRectMake(13,188,w-26,60)];
    self.heading.numberOfLines=2;self.heading.font=[UIFont boldSystemFontOfSize:17];
    self.heading.textColor=BLInk();[holder addSubview:self.heading];
    self.info=[[UILabel alloc] initWithFrame:CGRectMake(13,258,w-26,76)];
    self.info.numberOfLines=4;self.info.textColor=[UIColor darkGrayColor];
    self.info.font=[UIFont systemFontOfSize:12];[holder addSubview:self.info];
    self.playButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.playButton.frame=CGRectMake(12,347,w-24,48);self.playButton.backgroundColor=BLPink();
    self.playButton.layer.cornerRadius=11;
    [self.playButton setTitle:@"▶ 进入直播 · 全屏观看" forState:UIControlStateNormal];
    [self.playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playButton.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [self.playButton addTarget:self action:@selector(playLive) forControlEvents:UIControlEventTouchUpInside];
    [holder addSubview:self.playButton];
    self.qualityButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.qualityButton.frame=CGRectMake(12,410,136,42);
    self.qualityButton.backgroundColor=[UIColor whiteColor];self.qualityButton.layer.cornerRadius=9;
    [self.qualityButton setTitle:@"画质：流畅（80）" forState:UIControlStateNormal];
    [self.qualityButton addTarget:self action:@selector(chooseQuality) forControlEvents:UIControlEventTouchUpInside];
    [holder addSubview:self.qualityButton];
    self.favoriteButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.favoriteButton.frame=CGRectMake(158,410,w-170,42);
    self.favoriteButton.backgroundColor=[UIColor whiteColor];self.favoriteButton.layer.cornerRadius=9;
    [self.favoriteButton addTarget:self action:@selector(toggleFavorite) forControlEvents:UIControlEventTouchUpInside];
    [holder addSubview:self.favoriteButton];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(13,472,w-26,87)];
    hint.numberOfLines=0;hint.font=[UIFont systemFontOfSize:12];hint.textColor=[UIColor grayColor];
    hint.text=@"老设备优先使用 HLS + AVC 直播源。部分直播间没有兼容地址，或要求额外鉴权；直播不支持倍速。";
    [holder addSubview:hint];
    // Buttons must belong to the scrollable content, not overlay the screen.
    [self render];[self loadInfo];
}
- (void)render {
    self.heading.text=BLString(self.room[@"title"]).length?self.room[@"title"]:@"直播间";
    NSString *status=[self.room[@"live_status"] integerValue]==1?@"● 正在直播":@"○ 未开播";
    self.info.text=[NSString stringWithFormat:@"%@\n主播：%@  ·  分区：%@\n房间号：%@",
      status,BLString(self.room[@"uname"]),BLString(self.room[@"area"]),BLString(self.room[@"roomid"])];
    BLFetchImage(BLString(self.room[@"cover"]),self.cover,self.imageCache);
    [self.favoriteButton setTitle:BLContains(@"bl_live_favorites_v1",BLString(self.room[@"roomid"]))?@"★ 已收藏":@"☆ 收藏直播间" forState:UIControlStateNormal];
}
- (void)loadInfo {
    NSString *roomid=BLString(self.room[@"roomid"]);if(!roomid.length)return;
    NSString *url=[NSString stringWithFormat:@"https://api.live.bilibili.com/room/v1/Room/get_info?room_id=%@",roomid];
    BLRequest(url,^(NSDictionary *json,NSError *error){
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:nil;
        if(!data || [json[@"code"] integerValue]!=0)return;
        NSMutableDictionary *updated=[self.room mutableCopy];
        NSString *real=BLString(data[@"room_id"]);
        if(real.length)updated[@"roomid"]=real;
        NSString *title=BLString(data[@"title"]);if(title.length)updated[@"title"]=title;
        NSString *cover=BLString(data[@"user_cover"]);if(cover.length)updated[@"cover"]=cover;
        NSString *area=BLString(data[@"area_name"]);if(area.length)updated[@"area"]=area;
        if(data[@"live_status"])updated[@"live_status"]=data[@"live_status"];
        self.room=updated;[self render];
    });
}
- (void)toggleFavorite {
    NSString *rid=BLString(self.room[@"roomid"]);if(!rid.length)return;
    BOOL existing=BLContains(@"bl_live_favorites_v1",rid);
    BLStore(@"bl_live_favorites_v1",self.room,existing);
    [self render];
}
- (void)chooseQuality {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"直播画质" message:@"建议优先使用流畅版，降低卡顿" preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSNumber *quality in @[@80,@150]){
        NSString *title=[quality integerValue]==80?@"流畅（80）":@"高清（150）";
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            self.quality=[quality integerValue];
            [self.qualityButton setTitle:[@"画质：" stringByAppendingString:title] forState:UIControlStateNormal];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)playLiveURL:(NSString *)url {
    if(![url hasPrefix:@"https://"] && ![url hasPrefix:@"http://"]){[self liveError:@"未获取到有效播放地址"];return;}
    [self.playButton setTitle:@"▶ 进入直播 · 全屏观看" forState:UIControlStateNormal];self.playButton.enabled=YES;
    self.player=[[BLPlayerController alloc] initWithContentURL:[NSURL URLWithString:url]];
    self.player.liveStream=YES;
    [self presentMoviePlayerViewControllerAnimated:self.player];
    [self.player.moviePlayer play];
}
- (void)liveError:(NSString *)message {
    self.playButton.enabled=YES;[self.playButton setTitle:@"重试直播" forState:UIControlStateNormal];
    BLAlert(self,@"直播暂时无法播放",[NSString stringWithFormat:@"%@\n\n请尝试切换到流畅画质；部分直播间只有 FLV/HEVC 流，iPhone 4S 无法解码。",message]);
}
- (void)playLive {
    if([self.room[@"live_status"] integerValue]==0){BLAlert(self,@"尚未开播",@"主播目前不在直播中，可以收藏并稍后再试。");return;}
    NSString *rid=BLString(self.room[@"roomid"]);if(!rid.length){[self liveError:@"缺少直播间号"];return;}
    [self.playButton setTitle:@"正在寻找兼容直播源…" forState:UIControlStateNormal];self.playButton.enabled=NO;
    NSString *url=[NSString stringWithFormat:@"https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=%@&protocol=1&format=1&codec=0&qn=%ld&platform=web",rid,(long)self.quality];
    BLRequest(url,^(NSDictionary *json,NSError *error){
        NSString *hls=BLHLS(json);
        if(hls.length){[self playLiveURL:hls];return;}
        // Some endpoints still expose older H5 HLS streams.
        NSString *old=[NSString stringWithFormat:@"https://api.live.bilibili.com/room/v1/Room/playUrl?cid=%@&platform=h5&qn=%ld",rid,(long)self.quality];
        BLRequest(old,^(NSDictionary *legacy,NSError *legacyError){
            NSDictionary *data=[legacy[@"data"] isKindOfClass:[NSDictionary class]]?legacy[@"data"]:@{};
            NSArray *durl=[data[@"durl"] isKindOfClass:[NSArray class]]?data[@"durl"]:@[];
            NSString *stream=durl.count && [durl[0] isKindOfClass:[NSDictionary class]]?BLString(durl[0][@"url"]):@"";
            if([stream rangeOfString:@".m3u8"].location!=NSNotFound && ([stream hasPrefix:@"https://"]||[stream hasPrefix:@"http://"]))
                [self playLiveURL:stream];
            else [self liveError:BLFailure(json,error)?:BLFailure(legacy,legacyError)];
        });
    });
}
@end

@interface BLLiveListController : UITableViewController
@property(nonatomic,strong) NSArray *rooms;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,assign) BOOL showFavorites;
@property(nonatomic,strong) UISegmentedControl *segments;
@end
@implementation BLLiveListController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"直播";
    self.tableView.backgroundColor=BLBg();
    self.tableView.rowHeight=87;self.rooms=@[];
    self.imageCache=[NSCache new];self.imageCache.countLimit=24;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"房间号"
      style:UIBarButtonItemStylePlain target:self action:@selector(openRoomNumber)];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,53)];
    self.segments=[[UISegmentedControl alloc] initWithItems:@[@"推荐直播",@"我的收藏"]];
    self.segments.frame=CGRectMake(10,7,self.view.bounds.size.width-20,37);
    [self.segments addTarget:self action:@selector(switchMode) forControlEvents:UIControlEventValueChanged];
    self.segments.selectedSegmentIndex=0;[header addSubview:self.segments];
    self.tableView.tableHeaderView=header;
    UIRefreshControl *refresh=[UIRefreshControl new];
    [refresh addTarget:self action:@selector(refreshRooms) forControlEvents:UIControlEventValueChanged];
    self.refreshControl=refresh;
    [self refreshRooms];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(self.showFavorites)[self loadFavorites];
}
- (void)switchMode {
    self.showFavorites=self.segments.selectedSegmentIndex==1;
    [self refreshRooms];
}
- (void)showEmpty:(NSString *)text {
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(18,0,self.view.bounds.size.width-36,140)];
    label.text=text;label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
    label.textColor=[UIColor grayColor];label.font=[UIFont systemFontOfSize:13];
    self.tableView.backgroundView=label;
}
- (void)loadFavorites {
    self.rooms=BLStored(@"bl_live_favorites_v1");
    [self.tableView reloadData];[self.refreshControl endRefreshing];
    [self showEmpty:self.rooms.count?@"":@"还没有收藏的直播间，可以在详情页点击收藏。"];
}
- (void)refreshRooms {
    if(self.showFavorites){[self loadFavorites];return;}
    [self showEmpty:@"正在加载推荐直播…"];
    BLRequest(@"https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList?platform=web",^(NSDictionary *json,NSError *error){
        [self.refreshControl endRefreshing];
        if(self.showFavorites)return;
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        id provided=data[@"recommend_room_list"];
        NSArray *rows=[provided isKindOfClass:[NSArray class]]?provided:@[];
        NSMutableArray *list=[NSMutableArray array];
        for(id raw in rows){
            if([raw isKindOfClass:[NSDictionary class]]){
                NSDictionary *item=BLRoom(raw);
                if(item)[list addObject:item];
                // Provider sometimes wraps multiple rooms under nested list keys.
                NSArray *nested=[raw[@"list"] isKindOfClass:[NSArray class]]?raw[@"list"]:@[];
                for(NSDictionary *n in nested){NSDictionary *v=BLRoom(n);if(v)[list addObject:v];}
            }
            if(list.count>=35)break;
        }
        self.rooms=list;[self.tableView reloadData];
        if(!list.count)[self showEmpty:[NSString stringWithFormat:@"当前无法获取直播推荐：%@\n仍可点右上角「房间号」直接打开直播间。",BLFailure(json,error)]];
        else self.tableView.backgroundView=nil;
    });
}
- (void)openRoomNumber {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"打开直播间" message:@"输入房间号或 live.bilibili.com 链接" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){t.keyboardType=UIKeyboardTypeNumbersAndPunctuation;t.placeholder=@"例如：3";}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"进入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *rid=BLRoomInput(a.textFields.firstObject.text);
        if(!rid){BLAlert(self,@"房间号无效",@"请输入数字房间号或直播间 URL。");return;}
        [self.navigationController pushViewController:[[BLRoomDetailController alloc] initWithRoom:@{@"roomid":rid,@"title":[@"房间 " stringByAppendingString:rid],@"live_status":@1}] animated:YES];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.rooms.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"live"];
    if(!cell){
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"live"];
        UIImageView *cover=[[UIImageView alloc] initWithFrame:CGRectMake(9,10,100,65)];
        cover.tag=931;cover.backgroundColor=[UIColor colorWithWhite:.87 alpha:1];
        cover.contentMode=UIViewContentModeScaleAspectFill;cover.clipsToBounds=YES;
        cover.layer.cornerRadius=5;[cell.contentView addSubview:cover];
        UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(117,10,177,44)];
        title.tag=932;title.font=[UIFont boldSystemFontOfSize:13];title.numberOfLines=2;
        title.textColor=BLInk();[cell.contentView addSubview:title];
        UILabel *meta=[[UILabel alloc] initWithFrame:CGRectMake(117,57,177,21)];
        meta.tag=933;meta.font=[UIFont systemFontOfSize:11];meta.textColor=[UIColor grayColor];
        [cell.contentView addSubview:meta];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    NSDictionary *room=self.rooms[index.row];
    ((UILabel *)[cell.contentView viewWithTag:932]).text=room[@"title"];
    ((UILabel *)[cell.contentView viewWithTag:933]).text=[NSString stringWithFormat:@"● %@ · %@",room[@"uname"]?:@"",room[@"area"]?:@""];
    BLFetchImage(BLString(room[@"cover"]),(UIImageView *)[cell.contentView viewWithTag:931],self.imageCache);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    [self.navigationController pushViewController:[[BLRoomDetailController alloc] initWithRoom:self.rooms[index.row]] animated:YES];
}
@end


@interface BLQRLoginController : UIViewController
@property(nonatomic,strong) UIImageView *qrView;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *instructions;
@property(nonatomic,strong) UIButton *reloadButton;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *qrKey;
@property(nonatomic,assign) NSTimeInterval expiresAt;
@property(nonatomic,assign) BOOL requestActive;
@end
@implementation BLQRLoginController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"扫码登录 B 站";
    self.view.backgroundColor=BLBg();
    CGFloat w=self.view.bounds.size.width;
    self.qrView=[[UIImageView alloc] initWithFrame:CGRectMake(MAX(0,(w-228)/2),14,228,228)];
    self.qrView.backgroundColor=[UIColor whiteColor];
    self.qrView.contentMode=UIViewContentModeScaleAspectFit;
    self.qrView.layer.cornerRadius=12;self.qrView.clipsToBounds=YES;
    [self.view addSubview:self.qrView];
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(14,249,w-28,53)];
    self.status.textColor=BLInk();self.status.textAlignment=NSTextAlignmentCenter;
    self.status.numberOfLines=3;self.status.font=[UIFont boldSystemFontOfSize:13];
    [self.view addSubview:self.status];
    self.reloadButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.reloadButton.frame=CGRectMake(14,307,w-28,42);
    [self.reloadButton setTitle:@"生成登录二维码" forState:UIControlStateNormal];
    self.reloadButton.backgroundColor=BLPink();
    self.reloadButton.layer.cornerRadius=9;
    [self.reloadButton addTarget:self action:@selector(generateQR) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.reloadButton];
    self.instructions=[[UILabel alloc] initWithFrame:CGRectMake(15,355,w-30,76)];
    self.instructions.text=@"用另一台已登录 B 站的手机 App 扫描上方二维码，再在那台手机确认授权。\n二维码有效期约 3 分钟。";
    self.instructions.font=[UIFont systemFontOfSize:12];
    self.instructions.numberOfLines=4;
    self.instructions.textColor=[UIColor grayColor];
    [self.view addSubview:self.instructions];
    [self generateQR];
}
- (void)stopPolling {
    [self.timer invalidate];self.timer=nil;self.qrKey=nil;self.expiresAt=0;
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPolling];
}
- (void)dealloc {[self stopPolling];}
- (void)generateQR {
    [self stopPolling];
    [self.reloadButton setTitle:@"二维码获取中…" forState:UIControlStateNormal];
    self.reloadButton.enabled=NO;self.status.text=@"正在连接 B 站登录服务";
    self.qrView.image=nil;
    BLRequest(@"https://passport.bilibili.com/x/passport-login/web/qrcode/generate",^(NSDictionary *json,NSError *error){
        if(!self.view.window)return;
        self.reloadButton.enabled=YES;
        [self.reloadButton setTitle:@"刷新二维码" forState:UIControlStateNormal];
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        NSString *address=BLString(data[@"url"]),*qrKey=BLString(data[@"qrcode_key"]);
        if(error || [json[@"code"] integerValue]!=0 || !address.length || !qrKey.length){
            self.status.text=[NSString stringWithFormat:@"获取失败：%@",BLFailure(json,error)];return;
        }
        UIImage *image=BLQRImage(address);
        if(!image){self.status.text=@"无法在此 iOS 版本绘制二维码";return;}
        self.qrView.image=image;self.qrKey=qrKey;
        self.expiresAt=[[NSDate date] timeIntervalSince1970]+180;
        self.status.text=@"等待扫码…";
        self.timer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(pollOnce) userInfo:nil repeats:YES];
        [self pollOnce];
    });
}
- (void)pollOnce {
    if(!self.view.window || !self.qrKey.length || self.requestActive)return;
    if([[NSDate date] timeIntervalSince1970]>=self.expiresAt){
        [self stopPolling];self.status.text=@"二维码已过期，请点击刷新";return;
    }
    self.requestActive=YES;
    NSString *current=[self.qrKey copy];
    BLPollLogin(current,^(NSDictionary *json,NSDictionary *cookies,NSError *error){
        self.requestActive=NO;
        if(![self.qrKey isEqualToString:current] || !self.view.window)return;
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        NSInteger resultCode=[data[@"code"] integerValue];
        if(error || !json){
            self.status.text=@"检查失败，请检查网络连接";return;
        }
        if([json[@"code"] integerValue]!=0){
            self.status.text=[NSString stringWithFormat:@"扫码检查失败：%@",BLFailure(json,error)];return;
        }
        if(resultCode==86101){self.status.text=@"等待扫描二维码…";return;}
        if(resultCode==86090){self.status.text=@"已扫描，请在另一台手机上确认登录";return;}
        if(resultCode==86038){
            [self stopPolling];self.status.text=@"二维码已失效，请刷新";return;
        }
        if(resultCode==0){
            NSMutableDictionary *session=[cookies mutableCopy]?:[NSMutableDictionary dictionary];
            // Some Bilibili deployments include login cookies in the returned SSO URL.
            NSString *redirect=BLString(data[@"url"]);
            NSURLComponents *components=redirect.length?[NSURLComponents componentsWithString:redirect]:nil;
            for(NSURLQueryItem *item in components.queryItems){
                if([@[@"SESSDATA",@"bili_jct",@"DedeUserID",@"DedeUserID__ckMd5",@"sid"] containsObject:item.name] && item.value.length)
                    session[item.name]=item.value;
            }
            if(!BLSaveSession(session)){
                [self stopPolling];
                self.status.text=@"扫码已确认，但未取得有效登录 Cookie，或钥匙串写入失败。请重新扫描。";
                return;
            }
            [self stopPolling];
            self.status.text=@"授权成功，正在验证登录状态…";
            BLRequest(@"https://api.bilibili.com/x/web-interface/nav",^(NSDictionary *user,NSError *verifyError){
                NSDictionary *profile=[user[@"data"] isKindOfClass:[NSDictionary class]]?user[@"data"]:@{};
                if(!verifyError && [user[@"code"] integerValue]==0 && [profile[@"isLogin"] boolValue]){
                    self.status.text=@"登录成功";
                    [self.navigationController popViewControllerAnimated:YES];
                }else{
                    BLClearSession();
                    self.status.text=@"登录凭证验证失败，请刷新二维码重试。";
                }
            });
            return;
        }
        self.status.text=BLString(data[@"message"]).length?BLString(data[@"message"]):@"登录状态暂不可用";
    });
}
@end

@interface BLRemoteListController : UITableViewController
@property(nonatomic,assign) NSInteger mode;  // 0 folders, 1 folder videos, 2 following, 3 history
@property(nonatomic,copy) NSString *mid;
@property(nonatomic,copy) NSString *mediaID;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) BOOL loading;
@property(nonatomic,strong) NSDictionary *historyCursor;
@property(nonatomic,strong) UILabel *messageLabel;
@end
@implementation BLRemoteListController
- (instancetype)initWithMode:(NSInteger)mode mid:(NSString *)mid mediaID:(NSString *)media {
    if((self=[super initWithStyle:UITableViewStylePlain])){
        self.mode=mode;self.mid=mid;self.mediaID=media;self.page=1;self.items=@[];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@[@"账号收藏夹",@"收藏夹视频",@"关注的 UP 主",@"云端观看历史"][self.mode];
    self.tableView.backgroundColor=BLBg();self.tableView.rowHeight=67;
    UIView *foot=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,54)];
    UIButton *more=[UIButton buttonWithType:UIButtonTypeSystem];
    more.frame=CGRectMake(12,6,self.view.bounds.size.width-24,40);
    [more setTitle:@"加载更多" forState:UIControlStateNormal];
    [more setTitleColor:BLPink() forState:UIControlStateNormal];
    [more addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside];
    [foot addSubview:more];self.tableView.tableFooterView=foot;
    UIRefreshControl *refresh=[UIRefreshControl new];
    [refresh addTarget:self action:@selector(refreshList) forControlEvents:UIControlEventValueChanged];
    self.refreshControl=refresh;
    [self refreshList];
}
- (void)showMessage:(NSString *)message {
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(17,0,self.view.bounds.size.width-34,130)];
    label.textAlignment=NSTextAlignmentCenter;label.numberOfLines=0;
    label.textColor=[UIColor grayColor];label.font=[UIFont systemFontOfSize:13];
    label.text=message;self.tableView.backgroundView=message.length?label:nil;
}
- (void)refreshList {
    self.page=1;self.historyCursor=nil;self.items=@[];
    [self.tableView reloadData];[self loadPage];
}
- (void)loadMore {
    if(self.loading || self.mode==0)return;
    if(self.mode==3 && !self.historyCursor)return;
    self.page++;[self loadPage];
}
- (void)loadPage {
    if(self.loading)return;
    if(!BLAuthCookie().length){[self showMessage:@"需要先登录账号"];[self.refreshControl endRefreshing];return;}
    NSString *url=nil;
    if(self.mode==0)url=[NSString stringWithFormat:@"https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=%@",self.mid];
    else if(self.mode==1)url=[NSString stringWithFormat:@"https://api.bilibili.com/x/v3/fav/resource/list?media_id=%@&pn=%ld&ps=20&platform=web",self.mediaID,(long)self.page];
    else if(self.mode==2)url=[NSString stringWithFormat:@"https://api.bilibili.com/x/relation/followings?vmid=%@&pn=%ld&ps=20",self.mid,(long)self.page];
    else {
        NSMutableString *q=[NSMutableString stringWithString:@"https://api.bilibili.com/x/web-interface/history/cursor?type=archive&ps=20"];
        NSDictionary *c=self.historyCursor;
        if(c.count)[q appendFormat:@"&max=%@&view_at=%@&business=%@",BLString(c[@"max"]),BLString(c[@"view_at"]),BLQueryEscape(BLString(c[@"business"]))];
        url=q;
    }
    self.loading=YES;[self showMessage:@"正在同步账号资料…"];
    BLRequest(url,^(NSDictionary *json,NSError *error){
        self.loading=NO;[self.refreshControl endRefreshing];
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        if(error || [json[@"code"] integerValue]!=0){
            [self showMessage:[NSString stringWithFormat:@"读取失败：%@\n可能是账号过期或 B 站接口限制。",BLFailure(json,error)]];
            if(self.page>1)self.page--;return;
        }
        NSArray *records=[data[@"list"] isKindOfClass:[NSArray class]]?data[@"list"]:@[];
        if(self.mode==1)records=[data[@"medias"] isKindOfClass:[NSArray class]]?data[@"medias"]:@[];
        if(self.mode==3)self.historyCursor=[data[@"cursor"] isKindOfClass:[NSDictionary class]]?data[@"cursor"]:nil;
        NSMutableArray *all=[self.items mutableCopy];
        for(NSDictionary *raw in records){
            if(![raw isKindOfClass:[NSDictionary class]])continue;
            NSMutableDictionary *item=[NSMutableDictionary dictionaryWithDictionary:raw];
            if(self.mode==0){
                item[@"bl_name"]=BLString(raw[@"title"]);
                item[@"bl_subtitle"]=[NSString stringWithFormat:@"%@ 条视频",BLString(raw[@"media_count"])];
            }else if(self.mode==2){
                item[@"bl_name"]=BLString(raw[@"uname"]);
                item[@"bl_subtitle"]=[NSString stringWithFormat:@"UID %@ · %@",BLString(raw[@"mid"]),BLString(raw[@"sign"])];
            }else{
                NSDictionary *nested=[raw[@"history"] isKindOfClass:[NSDictionary class]]?raw[@"history"]:@{};
                NSString *bvid=BLString(raw[@"bvid"]);
                if(!bvid.length)bvid=BLString(nested[@"bvid"]);
                NSDictionary *owner=[raw[@"upper"] isKindOfClass:[NSDictionary class]]?raw[@"upper"]:@{};
                NSString *title=BLString(raw[@"title"]);
                if(!bvid.length)continue;
                item[@"bl_name"]=title;item[@"bl_bvid"]=bvid;
                item[@"bl_subtitle"]=BLString(owner[@"name"]).length?BLString(owner[@"name"]):BLString(raw[@"author"]);
                NSString *picture=BLString(raw[@"cover"]);if(!picture.length)picture=BLString(raw[@"pic"]);
                item[@"bl_cover"]=picture;
            }
            [all addObject:item];
            if(all.count>=120)break;
        }
        self.items=all;
        [self.tableView reloadData];
        [self showMessage:all.count?@"":@"暂无内容，或接口当前没有返回可访问的数据。"];
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"remote"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"remote"];
    NSDictionary *item=self.items[index.row];
    cell.textLabel.text=BLString(item[@"bl_name"]);
    cell.textLabel.font=[UIFont boldSystemFontOfSize:13];
    cell.textLabel.textColor=BLInk();cell.detailTextLabel.text=BLString(item[@"bl_subtitle"]);
    cell.detailTextLabel.font=[UIFont systemFontOfSize:11];
    cell.detailTextLabel.textColor=[UIColor grayColor];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    NSDictionary *item=self.items[index.row];
    if(self.mode==0){
        NSString *media=BLString(item[@"id"]);
        if(media.length)[self.navigationController pushViewController:[[BLRemoteListController alloc] initWithMode:1 mid:self.mid mediaID:media] animated:YES];
    }else if(self.mode==2){
        NSString *uid=BLString(item[@"mid"]);
        NSString *name=BLString(item[@"uname"]);
        UIAlertController *menu=[UIAlertController alertControllerWithTitle:name
            message:[NSString stringWithFormat:@"UID %@",uid] preferredStyle:UIAlertControllerStyleAlert];
        [menu addAction:[UIAlertAction actionWithTitle:@"复制个人空间链接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [UIPasteboard generalPasteboard].string=[@"https://space.bilibili.com/" stringByAppendingString:uid];
        }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:menu animated:YES completion:nil];
    }else{
        NSString *bvid=BLString(item[@"bl_bvid"]);if(!bvid.length)return;
        NSDictionary *video=@{@"bvid":bvid,@"title":BLString(item[@"bl_name"]),
          @"pic":BLString(item[@"bl_cover"]),@"author":BLString(item[@"bl_subtitle"])};
        [self.navigationController pushViewController:[[BLDetailController alloc] initWithVideo:video] animated:YES];
    }
}
@end

@interface BLAccountController : UITableViewController
@property(nonatomic,strong) NSDictionary *profile;
@property(nonatomic,strong) UIImageView *portrait;
@property(nonatomic,strong) UILabel *userLabel;
@property(nonatomic,strong) UILabel *details;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,assign) BOOL checking;
@end
@implementation BLAccountController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"我的 B 站";self.tableView.backgroundColor=BLBg();
    self.tableView.rowHeight=58;
    self.imageCache=[NSCache new];self.imageCache.countLimit=2;
    CGFloat w=self.view.bounds.size.width;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,140)];
    header.backgroundColor=[UIColor whiteColor];
    self.portrait=[[UIImageView alloc] initWithFrame:CGRectMake(15,19,70,70)];
    self.portrait.layer.cornerRadius=35;self.portrait.clipsToBounds=YES;
    self.portrait.backgroundColor=BLBg();
    [header addSubview:self.portrait];
    self.userLabel=[[UILabel alloc] initWithFrame:CGRectMake(99,20,w-111,35)];
    self.userLabel.font=[UIFont boldSystemFontOfSize:18];self.userLabel.textColor=BLInk();
    [header addSubview:self.userLabel];
    self.details=[[UILabel alloc] initWithFrame:CGRectMake(99,58,w-110,74)];
    self.details.textColor=[UIColor grayColor];self.details.numberOfLines=3;
    self.details.font=[UIFont systemFontOfSize:12];[header addSubview:self.details];
    self.tableView.tableHeaderView=header;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self action:@selector(checkAccount)];
    [self render];[self checkAccount];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self render];
    if(BLAuthCookie().length)[self checkAccount];
}
- (void)render {
    BOOL logged=BLAuthCookie().length>0;
    self.userLabel.text=logged?(BLString(self.profile[@"uname"]).length?BLString(self.profile[@"uname"]):@"正在检查登录状态"):@"未登录";
    NSString *mid=BLString(self.profile[@"mid"]);
    NSDictionary *level=[self.profile[@"level_info"] isKindOfClass:[NSDictionary class]]?self.profile[@"level_info"]:@{};
    self.details.text=logged?[NSString stringWithFormat:@"UID：%@\n等级：LV%@ · 登录凭证已保存在钥匙串",
      mid,BLString(level[@"current_level"])]:@"点击下方「扫码登录」\n使用另一台手机的 B 站 App 授权";
    if(logged && BLString(self.profile[@"face"]).length)
        BLFetchImage(BLString(self.profile[@"face"]),self.portrait,self.imageCache);
    else self.portrait.image=nil;
    [self.tableView reloadData];
}
- (void)checkAccount {
    if(self.checking||!BLAuthCookie().length){[self render];return;}
    self.checking=YES;
    BLRequest(@"https://api.bilibili.com/x/web-interface/nav",^(NSDictionary *json,NSError *error){
        self.checking=NO;
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        if(!error && [json[@"code"] integerValue]==0 && [data[@"isLogin"] boolValue]){
            self.profile=data;
        }else{
            self.profile=nil;
            self.details.text=[NSString stringWithFormat:@"账号验证失败：%@",BLFailure(json,error)];
        }
        [self render];
        if(error||[json[@"code"] integerValue]!=0)self.details.text=@"登录状态无法验证；可重试或重新扫码";
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table{return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section==0?1:(BLAuthCookie().length?4:0);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section==0?@"账号":@"账号内容（只读）";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"account"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"account"];
    BOOL logged=BLAuthCookie().length>0;
    if(index.section==0)cell.textLabel.text=logged?@"退出登录（仅删除本机凭证）":@"扫码登录";
    else cell.textLabel.text=@[@"我的收藏夹",@"关注列表",@"云端观看历史",@"重新验证账号"][index.row];
    cell.textLabel.font=[UIFont systemFontOfSize:15];
    cell.textLabel.textColor=index.section==0&&logged?[UIColor redColor]:BLInk();
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    BOOL logged=BLAuthCookie().length>0;
    if(index.section==0){
        if(!logged){
            [self.navigationController pushViewController:[BLQRLoginController new] animated:YES];
        }else{
            UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"退出 B 站账号？"
                 message:@"只清除这台 iPhone 上的登录凭证，不影响其他设备的登录。" preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
                BLClearSession();self.profile=nil;[self render];
            }]];
            [self presentViewController:confirm animated:YES completion:nil];
        }
        return;
    }
    if(!logged)return;
    if(index.row==3){[self checkAccount];return;}
    NSString *uid=BLString(self.profile[@"mid"]);
    if(!uid.length){BLAlert(self,@"账号资料尚未就绪",@"请先点右上角刷新，确认 UID 已加载。");return;}
    NSInteger mode=index.row==0?0:index.row==1?2:3;
    [self.navigationController pushViewController:[[BLRemoteListController alloc] initWithMode:mode mid:uid mediaID:nil] animated:YES];
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
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"我的" style:UIBarButtonItemStylePlain target:self action:@selector(openAccount)],
        [[UIBarButtonItem alloc] initWithTitle:@"直播" style:UIBarButtonItemStylePlain target:self action:@selector(openLive)]
    ];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"BV号"
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
    self.mode=control.selectedSegmentIndex;self.page=1;self.items=@[];self.loading=NO;
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
- (void)openAccount {
    [self.search resignFirstResponder];
    [self.navigationController pushViewController:[[BLAccountController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
}
- (void)openLive {
    [self.search resignFirstResponder];
    [self.navigationController pushViewController:[[BLLiveListController alloc] initWithStyle:UITableViewStylePlain] animated:YES];
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
