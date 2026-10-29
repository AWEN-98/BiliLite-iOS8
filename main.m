#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
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
       @"like":BLString(stat[@"like"]),@"favorite":BLString(stat[@"favorite"]),
       @"reason":BLString([d[@"rcmd_reason"] isKindOfClass:[NSDictionary class]]?d[@"rcmd_reason"][@"content"]:@"")} mutableCopy];
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
      (__bridge id)kSecAttrAccessGroup:@"com.finn.bililite",
      (__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne};
    CFTypeRef answer=NULL;
    OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&answer);
    if(status!=errSecSuccess || !answer)return nil;
    NSData *data=CFBridgingRelease(answer);
    id saved=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [saved isKindOfClass:[NSDictionary class]]?saved:nil;
}
static NSString *const BLKeychainGroup=@"com.finn.bililite";
static NSDictionary *BLKeychainMatch(NSString *account){
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService:BLAccountService,
      (__bridge id)kSecAttrAccount:account,
      (__bridge id)kSecAttrAccessGroup:BLKeychainGroup};
}
static OSStatus BLWriteKeychain(NSString *account,NSData *data){
    if(!data.length)return errSecParam;
    NSDictionary *match=BLKeychainMatch(account);
    // Update first. Avoid deleting a valid account secret until replacement
    // is successfully written.
    OSStatus update=SecItemUpdate((__bridge CFDictionaryRef)match,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if(update==errSecSuccess)return update;
    if(update!=errSecItemNotFound)return update;
    NSMutableDictionary *newItem=[match mutableCopy];
    newItem[(__bridge id)kSecValueData]=data;
    newItem[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)newItem,NULL);
}
static OSStatus BLKeychainCheck(void){
    // Probe only with nonsecret test data. Never persist session material
    // outside the keychain.
    NSString *probe=@"keychain-self-check";
    NSData *data=[@"ok" dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status=BLWriteKeychain(probe,data);
    if(status==errSecSuccess){
        NSMutableDictionary *query=[BLKeychainMatch(probe) mutableCopy];
        query[(__bridge id)kSecReturnData]=@YES;
        query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
        CFTypeRef returned=NULL;
        status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&returned);
        NSData *value=returned?CFBridgingRelease(returned):nil;
        if(status==errSecSuccess && ![value isEqualToData:data])status=errSecInternalComponent;
    }
    SecItemDelete((__bridge CFDictionaryRef)BLKeychainMatch(probe));
    return status;
}
static OSStatus BLSaveSession(NSDictionary *values){
    NSMutableDictionary *safe=[NSMutableDictionary dictionary];
    for(NSString *name in @[@"SESSDATA",@"DedeUserID",@"DedeUserID__ckMd5",@"bili_jct",@"sid"]){
        NSString *value=BLString(values[name]);
        if(value.length)safe[name]=value;
    }
    if(!BLString(safe[@"SESSDATA"]).length)return errSecParam;
    NSData *data=[NSJSONSerialization dataWithJSONObject:safe options:0 error:NULL];
    if(!data)return errSecParam;
    OSStatus status=BLWriteKeychain(BLAccountKey,data);
    if(status!=errSecSuccess)return status;
    NSDictionary *readback=BLSession();
    return [BLString(readback[@"SESSDATA"]) isEqualToString:BLString(safe[@"SESSDATA"])]?errSecSuccess:errSecDecode;
}
static NSString *BLKeychainError(OSStatus code){
    if(code==(OSStatus)-34018)return @"钥匙串签名权限缺失（-34018），安装包可能没有正确签名。";
    if(code==errSecInteractionNotAllowed)return @"钥匙串当前不可访问（-25308），请解锁手机后重试。";
    if(code==errSecNotAvailable)return @"系统钥匙串服务不可用（-25291），请尝试重新打开应用。";
    if(code==errSecParam)return @"登录 Cookie 不完整，缺少 SESSDATA。";
    return [NSString stringWithFormat:@"钥匙串保存/回读失败，错误代码 %ld。",(long)code];
}
static NSDictionary *BLSessionFromPoll(NSDictionary *responseCookies,NSString *redirect){
    NSMutableDictionary *values=[responseCookies mutableCopy]?:[NSMutableDictionary dictionary];
    NSURLComponents *components=redirect.length?[NSURLComponents componentsWithString:redirect]:nil;
    NSString *host=[components.host lowercaseString];
    // Do not navigate to the cross-domain URL; only read the query fields
    // returned by the official passport API. Never send session cookies to biligame.
    if([components.scheme isEqualToString:@"https"] &&
        ([host isEqualToString:@"passport.biligame.com"] ||
         [host isEqualToString:@"passport.bilibili.com"] ||
         [host isEqualToString:@"www.bilibili.com"])){
        for(NSURLQueryItem *item in components.queryItems){
            if([@[@"SESSDATA",@"bili_jct",@"DedeUserID",@"DedeUserID__ckMd5",@"sid"] containsObject:item.name] && item.value.length)
                values[item.name]=item.value;
        }
    }
    return values;
}
static void BLClearSession(void){
    SecItemDelete((__bridge CFDictionaryRef)BLKeychainMatch(BLAccountKey));
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
    [cookies addObjectsFromArray:[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:@"https://www.bilibili.com/"]]?:@[]];
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
    CIImage *input=filter.outputImage;
    if(!input)return nil;
    CIContext *context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];
    CGImageRef bitmap=[context createCGImage:input fromRect:input.extent];
    if(!bitmap)return nil;
    size_t modules=CGImageGetWidth(bitmap);
    if(modules==0){CGImageRelease(bitmap);return nil;}
    UIImage *matrix=[UIImage imageWithCGImage:bitmap];
    // QR edges need an intact white quiet zone. Integer pixel scaling keeps
    // every module square and avoids blurred or apparently cropped edges.
    const CGFloat canvas=216.0f;
    const CGFloat screenScale=2.0f; // iPhone 4S Retina
    const CGFloat quiet=16.0f;
    NSInteger pixelModule=(NSInteger)floorf((canvas-quiet*2)*screenScale/(CGFloat)modules);
    if(pixelModule<1)pixelModule=1;
    CGFloat drawn=((CGFloat)modules*(CGFloat)pixelModule)/screenScale;
    if(drawn>canvas-quiet*2){drawn=canvas-quiet*2;}
    CGFloat inset=floorf((canvas-drawn)/2.0f*screenScale)/screenScale;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(canvas,canvas),YES,screenScale);
    CGContextRef graphic=UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(graphic,kCGInterpolationNone);
    [[UIColor whiteColor] setFill];
    UIRectFill(CGRectMake(0,0,canvas,canvas));
    [matrix drawInRect:CGRectMake(inset,inset,drawn,drawn)];
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(bitmap);
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

// Personalized home-feed data. Uses the signed web feed (same session as
// login), not the public popularity chart. Only return ordinary videos.
static NSArray *BLRecommendationVideos(NSDictionary *json){
    NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
    NSArray *rows=[data[@"item"] isKindOfClass:[NSArray class]]?data[@"item"]:@[];
    NSMutableArray *videos=[NSMutableArray array];
    for(id item in rows){
        if(![item isKindOfClass:[NSDictionary class]])continue;
        NSString *type=BLString(item[@"goto"]);
        // Exclude sponsored banners, live rooms and non-video cards.
        if(![type isEqualToString:@"av"] && ![type isEqualToString:@"video"])continue;
        if(!BLBV(BLString(item[@"bvid"])).length)continue;
        [videos addObject:item];
        if(videos.count>=20)break;
    }
    return videos;
}
static void BLRecommend(NSInteger freshIndex,BLJSONCallback done){
    // The login cookie is automatically attached to api.bilibili.com
    // by BLRequest; recommendation ranking then uses the logged-in account.
    BLRequest(@"https://api.bilibili.com/x/web-interface/nav",^(NSDictionary *nav,NSError *navError){
        NSString *key=BLWBIKey(nav);
        if(key.length!=32){
            // Legacy API sometimes remains available to old devices.
            NSString *fallback=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/index/top/rcmd?version=1&fresh_type=4&ps=12&fresh_idx=%ld",(long)freshIndex];
            BLRequest(fallback,done);
            return;
        }
        long long now=(long long)time(NULL);
        // Sort keys lexicographically for WBI MD5 signing.
        NSString *params=[NSString stringWithFormat:@"brush=%ld&feed_version=V8&fresh_idx=%ld&fresh_idx_1h=%ld&fresh_type=4&homepage_ver=1&ps=12&web_location=1430650&wts=%lld",
            (long)freshIndex,(long)freshIndex,(long)freshIndex,now];
        NSString *message=[params stringByAppendingString:key];
        unsigned char digest[CC_MD5_DIGEST_LENGTH];
        const char *utf8=[message UTF8String];
        CC_MD5(utf8,(CC_LONG)strlen(utf8),digest);
        NSMutableString *signature=[NSMutableString stringWithCapacity:32];
        for(NSUInteger i=0;i<CC_MD5_DIGEST_LENGTH;i++)[signature appendFormat:@"%02x",digest[i]];
        NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?%@&w_rid=%@",params,signature];
        BLRequest(url,^(NSDictionary *json,NSError *error){
            if(!error && [json[@"code"] integerValue]==0 && BLRecommendationVideos(json).count){
                done(json,nil);return;
            }
            NSString *fallback=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/index/top/rcmd?version=1&fresh_type=4&ps=12&fresh_idx=%ld",(long)freshIndex];
            BLRequest(fallback,^(NSDictionary *other,NSError *otherError){
                if(!otherError && [other[@"code"] integerValue]==0 && BLRecommendationVideos(other).count)done(other,nil);
                else done(json?:other,error?:otherError);
            });
        });
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

static void *BLPlayerItemStatusContext = &BLPlayerItemStatusContext;

@interface BLPlayerSurface : UIView
@end
@implementation BLPlayerSurface
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface BLPlayerController : UIViewController
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *playerItem;
@property(nonatomic,strong) BLPlayerSurface *videoSurface;
@property(nonatomic,strong) UIView *topBar;
@property(nonatomic,strong) UIView *bottomBar;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIButton *playControlButton;
@property(nonatomic,strong) UIButton *centerButton;
@property(nonatomic,strong) UIButton *rewindButton;
@property(nonatomic,strong) UIButton *forwardButton;
@property(nonatomic,strong) UIButton *speedButton;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *liveBadge;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *currentTimeLabel;
@property(nonatomic,strong) UILabel *durationLabel;
@property(nonatomic,strong) UISlider *progressSlider;
@property(nonatomic,strong) NSURL *contentURL;
@property(nonatomic,copy) NSString *videoKey;
@property(nonatomic,copy) NSString *videoTitle;
@property(nonatomic,copy) NSString *qualityLabel;
@property(nonatomic,assign) BOOL liveStream;
@property(nonatomic,assign) BOOL controlsVisible;
@property(nonatomic,assign) BOOL seeking;
@property(nonatomic,assign) BOOL holdingSpeed;
@property(nonatomic,assign) BOOL wasPlayingBeforeHold;
@property(nonatomic,assign) BOOL didStartPlayback;
@property(nonatomic,assign) BOOL completedPlayback;
@property(nonatomic,assign) BOOL observingStatus;
@property(nonatomic,assign) float preferredRate;
@property(nonatomic,assign) NSTimeInterval resumeAt;
@property(nonatomic,strong) NSTimer *saveTimer;
@property(nonatomic,strong) id timeObserver;
@end

@implementation BLPlayerController
- (instancetype)initWithContentURL:(NSURL *)url {
    if((self=[super init])){
        self.contentURL=url;
        self.preferredRate=1.0f;
        self.modalPresentationStyle=UIModalPresentationFullScreen;
    }
    return self;
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor=[UIColor colorWithWhite:1 alpha:.12];
    button.layer.cornerRadius=7;
    button.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (UILabel *)makeLabel:(CGFloat)size color:(UIColor *)color {
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectZero];
    label.font=[UIFont systemFontOfSize:size];
    label.textColor=color;
    label.backgroundColor=[UIColor clearColor];
    return label;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor blackColor];
    self.preferredRate=MAX(.5f,self.preferredRate);
    if(!self.contentURL){self.statusLabel.text=@"没有可播放的视频地址";return;}

    self.playerItem=[AVPlayerItem playerItemWithURL:self.contentURL];
    self.player=[AVPlayer playerWithPlayerItem:self.playerItem];

    self.videoSurface=[[BLPlayerSurface alloc] initWithFrame:self.view.bounds];
    self.videoSurface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.videoSurface.backgroundColor=[UIColor blackColor];
    ((AVPlayerLayer *)self.videoSurface.layer).player=self.player;
    ((AVPlayerLayer *)self.videoSurface.layer).videoGravity=AVLayerVideoGravityResizeAspect;
    [self.view addSubview:self.videoSurface];

    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
    tap.cancelsTouchesInView=NO;
    [self.videoSurface addGestureRecognizer:tap];
    if(!self.liveStream){
        UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(holdToSpeed:)];
        hold.minimumPressDuration=.42;
        hold.cancelsTouchesInView=NO;
        [self.videoSurface addGestureRecognizer:hold];
    }

    self.controlsVisible=YES;
    self.topBar=[[UIView alloc] initWithFrame:CGRectZero];
    self.topBar.backgroundColor=[UIColor colorWithWhite:0 alpha:.68];
    [self.view addSubview:self.topBar];
    self.closeButton=[self makeButton:@"‹ 返回" action:@selector(closePlayer)];
    [self.topBar addSubview:self.closeButton];
    self.titleLabel=[self makeLabel:13 color:[UIColor whiteColor]];
    self.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    NSString *displayTitle=self.videoTitle.length?self.videoTitle:@"BiliLite 播放器";
    if(self.qualityLabel.length && !self.liveStream)displayTitle=[displayTitle stringByAppendingFormat:@" · %@",self.qualityLabel];
    self.titleLabel.text=displayTitle;
    [self.topBar addSubview:self.titleLabel];

    if(self.liveStream){
        self.liveBadge=[self makeLabel:12 color:[UIColor whiteColor]];
        self.liveBadge.text=@"● 直播中";
        self.liveBadge.textAlignment=NSTextAlignmentCenter;
        self.liveBadge.backgroundColor=[UIColor colorWithRed:.82 green:.12 blue:.24 alpha:.94];
        self.liveBadge.layer.cornerRadius=7;
        self.liveBadge.clipsToBounds=YES;
        [self.topBar addSubview:self.liveBadge];
    }

    self.bottomBar=[[UIView alloc] initWithFrame:CGRectZero];
    self.bottomBar.backgroundColor=[UIColor colorWithWhite:0 alpha:.72];
    [self.view addSubview:self.bottomBar];
    self.progressSlider=[[UISlider alloc] initWithFrame:CGRectZero];
    self.progressSlider.minimumValue=0;
    self.progressSlider.maximumValue=1;
    self.progressSlider.minimumTrackTintColor=BLPink();
    self.progressSlider.maximumTrackTintColor=[UIColor colorWithWhite:1 alpha:.32];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [self.bottomBar addSubview:self.progressSlider];
    self.currentTimeLabel=[self makeLabel:10 color:[UIColor colorWithWhite:1 alpha:.88]];
    self.currentTimeLabel.text=@"00:00";
    [self.bottomBar addSubview:self.currentTimeLabel];
    self.durationLabel=[self makeLabel:10 color:[UIColor colorWithWhite:1 alpha:.88]];
    self.durationLabel.text=@"00:00";
    self.durationLabel.textAlignment=NSTextAlignmentRight;
    [self.bottomBar addSubview:self.durationLabel];

    self.playControlButton=[self makeButton:@"▶" action:@selector(togglePlayback)];
    [self.bottomBar addSubview:self.playControlButton];
    self.rewindButton=[self makeButton:@"−15s" action:@selector(seekBackward)];
    [self.bottomBar addSubview:self.rewindButton];
    self.forwardButton=[self makeButton:@"+15s" action:@selector(seekForward)];
    [self.bottomBar addSubview:self.forwardButton];
    self.speedButton=[self makeButton:@"1.0×" action:@selector(changeSpeed)];
    [self.bottomBar addSubview:self.speedButton];

    self.centerButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.centerButton.backgroundColor=[UIColor colorWithWhite:0 alpha:.58];
    self.centerButton.layer.cornerRadius=34;
    self.centerButton.layer.borderWidth=1;
    self.centerButton.layer.borderColor=[UIColor colorWithWhite:1 alpha:.35].CGColor;
    self.centerButton.titleLabel.font=[UIFont systemFontOfSize:30];
    [self.centerButton setTitle:@"▶" forState:UIControlStateNormal];
    [self.centerButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.centerButton addTarget:self action:@selector(togglePlayback) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.centerButton];

    self.statusLabel=[self makeLabel:12 color:[UIColor whiteColor]];
    self.statusLabel.textAlignment=NSTextAlignmentCenter;
    self.statusLabel.numberOfLines=2;
    self.statusLabel.backgroundColor=[UIColor colorWithWhite:0 alpha:.48];
    self.statusLabel.layer.cornerRadius=6;
    self.statusLabel.clipsToBounds=YES;
    self.statusLabel.text=@"正在加载视频…";
    [self.view addSubview:self.statusLabel];

    if(self.liveStream){
        self.progressSlider.hidden=YES;
        self.currentTimeLabel.hidden=YES;
        self.durationLabel.hidden=YES;
        self.rewindButton.hidden=YES;
        self.forwardButton.hidden=YES;
        self.speedButton.hidden=YES;
        self.currentTimeLabel.text=@"直播中";
    }

    [self positionControls];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemFailed:)
        name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew context:BLPlayerItemStatusContext];
    self.observingStatus=YES;

    __weak BLPlayerController *weakSelf=self;
    self.timeObserver=[self.player addPeriodicTimeObserverForInterval:CMTimeMake(1,2) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){
        [weakSelf updateTimeline];
        [weakSelf updatePlaybackUI];
    }];
    self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(savePosition) userInfo:nil repeats:YES];
    [self setNeedsStatusBarAppearanceUpdate];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self positionControls];
}
- (void)positionControls {
    CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
    if(w<1 || h<1)return;
    self.topBar.frame=CGRectMake(0,0,w,46);
    self.closeButton.frame=CGRectMake(8,4,62,38);
    self.titleLabel.frame=CGRectMake(76,5,MAX(80,w-184),36);
    self.liveBadge.frame=CGRectMake(MAX(8,w-91),9,82,28);
    CGFloat bottomHeight=94;
    self.bottomBar.frame=CGRectMake(0,MAX(0,h-bottomHeight),w,bottomHeight);
    self.progressSlider.frame=CGRectMake(12,2,MAX(40,w-24),25);
    self.currentTimeLabel.frame=CGRectMake(13,25,70,18);
    self.durationLabel.frame=CGRectMake(MAX(75,w-83),25,70,18);
    self.playControlButton.frame=CGRectMake(12,48,42,38);
    self.rewindButton.frame=CGRectMake(61,48,48,38);
    self.forwardButton.frame=CGRectMake(116,48,48,38);
    self.speedButton.frame=CGRectMake(MAX(172,w-86),48,74,38);
    self.centerButton.frame=CGRectMake((w-68)/2,(h-68)/2,68,68);
    self.statusLabel.frame=CGRectMake(MAX(12,(w-270)/2),CGRectGetMaxY(self.centerButton.frame)+8,MIN(270,w-24),38);
}
- (void)closePlayer {
    [self savePosition];
    [self.player pause];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)isActuallyPlaying { return self.player && self.player.rate>.01f; }
- (void)updatePlaybackUI {
    BOOL playing=[self isActuallyPlaying];
    [self.playControlButton setTitle:playing?@"Ⅱ":@"▶" forState:UIControlStateNormal];
    self.centerButton.hidden=playing;
    if(self.liveStream)self.currentTimeLabel.text=@"直播中";
    
}
- (void)togglePlayback {
    if([self isActuallyPlaying]){
        [self.player pause];
        [self showControls];
    }else{
        if(self.player.currentItem.status==AVPlayerItemStatusFailed){
            self.statusLabel.text=@"播放失败，请返回后重试或切换清晰度";
            return;
        }
        [self.player play];
        self.player.rate=self.preferredRate;
        self.statusLabel.text=@"";
        [self showControls];
    }
    [self updatePlaybackUI];
}
- (void)playerTapped:(UITapGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateEnded)return;
    if(self.controlsVisible)[self hideControls];
    else [self showControls];
}
- (void)showControls {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideControls) object:nil];
    self.controlsVisible=YES;
    self.topBar.userInteractionEnabled=YES;
    self.bottomBar.userInteractionEnabled=YES;
    [UIView animateWithDuration:.18 animations:^{self.topBar.alpha=1;self.bottomBar.alpha=1;}];
    if([self isActuallyPlaying])[self performSelector:@selector(hideControls) withObject:nil afterDelay:4.0];
}
- (void)hideControls {
    if(self.seeking || ![self isActuallyPlaying])return;
    self.controlsVisible=NO;
    [UIView animateWithDuration:.22 animations:^{self.topBar.alpha=0;self.bottomBar.alpha=0;} completion:^(BOOL finished){
        if(!self.controlsVisible){self.topBar.userInteractionEnabled=NO;self.bottomBar.userInteractionEnabled=NO;}
    }];
}
- (void)seekBackward { [self seekBySeconds:-15]; }
- (void)seekForward { [self seekBySeconds:15]; }
- (void)seekBySeconds:(NSTimeInterval)delta {
    if(self.liveStream || !self.playerItem)return;
    NSTimeInterval duration=CMTimeGetSeconds(self.playerItem.duration);
    NSTimeInterval current=CMTimeGetSeconds(self.player.currentTime);
    if(!isfinite(duration)||duration<=0||!isfinite(current))return;
    NSTimeInterval target=MAX(0,MIN(duration,current+delta));
    [self.player seekToTime:CMTimeMakeWithSeconds(target,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self showControls];
    [self updateTimeline];
}
- (NSTimeInterval)durationSeconds {
    NSTimeInterval duration=CMTimeGetSeconds(self.playerItem.duration);
    return isfinite(duration)&&duration>0?duration:0;
}
- (NSString *)timeString:(NSTimeInterval)seconds {
    if(!isfinite(seconds)||seconds<0)seconds=0;
    NSInteger whole=(NSInteger)seconds;
    NSInteger hours=whole/3600,minutes=(whole%3600)/60,secs=whole%60;
    return hours>0?[NSString stringWithFormat:@"%ld:%02ld:%02ld",(long)hours,(long)minutes,(long)secs]:
        [NSString stringWithFormat:@"%02ld:%02ld",(long)minutes,(long)secs];
}
- (void)updateTimeline {
    if(!self.playerItem)return;
    NSTimeInterval current=CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval duration=[self durationSeconds];
    if(!isfinite(current)||current<0)current=0;
    if(!self.liveStream){
        self.currentTimeLabel.text=[self timeString:current];
        self.durationLabel.text=[self timeString:duration];
        if(duration>0 && !self.seeking)self.progressSlider.value=(float)MIN(1.0,MAX(0.0,current/duration));
    }
}
- (void)sliderTouchDown:(UISlider *)slider {
    self.seeking=YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideControls) object:nil];
}
- (void)sliderChanged:(UISlider *)slider {
    NSTimeInterval duration=[self durationSeconds];
    self.currentTimeLabel.text=[self timeString:duration*slider.value];
}
- (void)sliderReleased:(UISlider *)slider {
    NSTimeInterval duration=[self durationSeconds];
    if(duration>0){
        NSTimeInterval target=duration*slider.value;
        [self.player seekToTime:CMTimeMakeWithSeconds(target,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
    self.seeking=NO;
    [self updateTimeline];
    [self showControls];
}
- (void)changeSpeed {
    if(self.liveStream)return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"播放倍速" message:@"选择播放速度" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *speeds=@[@0.5,@0.75,@1.0,@1.25,@1.5,@2.0];
    for(NSNumber *number in speeds){
        float rate=[number floatValue];
        NSString *title=[NSString stringWithFormat:@"%.2g×%@",rate,(fabsf(rate-self.preferredRate)<.01f?@"  ✓":@"")];
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            BOOL wasPlaying=[self isActuallyPlaying];
            self.preferredRate=rate;
            [self.speedButton setTitle:[NSString stringWithFormat:@"%.2g×",rate] forState:UIControlStateNormal];
            if(wasPlaying)self.player.rate=rate;
            [self showControls];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)holdToSpeed:(UILongPressGestureRecognizer *)gesture {
    if(self.liveStream)return;
    if(gesture.state==UIGestureRecognizerStateBegan){
        self.wasPlayingBeforeHold=[self isActuallyPlaying];
        self.holdingSpeed=YES;
        [self showControls];
        if(self.wasPlayingBeforeHold)self.player.rate=2.0f;
        [self.speedButton setTitle:@"按住 2×" forState:UIControlStateNormal];
    }else if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){
        self.holdingSpeed=NO;
        if(self.wasPlayingBeforeHold)self.player.rate=self.preferredRate;
        [self.speedButton setTitle:[NSString stringWithFormat:@"%.2g×",self.preferredRate] forState:UIControlStateNormal];
        [self showControls];
    }
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context!=BLPlayerItemStatusContext){[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;}
    AVPlayerItem *item=(AVPlayerItem *)object;
    if(item!=self.playerItem)return;
    AVPlayerItemStatus status=item.status;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(item!=self.playerItem)return;
        if(status==AVPlayerItemStatusReadyToPlay){
            self.statusLabel.text=@"";
            if(!self.didStartPlayback){
                self.didStartPlayback=YES;
                NSTimeInterval resume=self.resumeAt;
                if(!self.liveStream && resume>5){
                    NSTimeInterval duration=[self durationSeconds];
                    if(duration>0 && resume<duration-8){
                        [self.player seekToTime:CMTimeMakeWithSeconds(resume,600) completionHandler:^(BOOL finished){
                            [self.player play];self.player.rate=self.preferredRate;[self updatePlaybackUI];[self updateTimeline];
                        }];
                    }else{
                        [self.player play];self.player.rate=self.preferredRate;
                    }
                }else{
                    [self.player play];self.player.rate=self.preferredRate;
                }
                [self updatePlaybackUI];
                [self showControls];
            }
        }else if(status==AVPlayerItemStatusFailed){
            NSString *reason=item.error.localizedDescription.length?item.error.localizedDescription:@"视频编码不受支持或播放地址已失效";
            self.statusLabel.text=[NSString stringWithFormat:@"无法播放\n%@",reason];
            [self updatePlaybackUI];
        }else{
            self.statusLabel.text=@"正在连接视频源…";
        }
    });
}
- (void)itemEnded:(NSNotification *)notification {
    self.completedPlayback=YES;
    self.statusLabel.text=@"播放结束";
    if(self.videoKey.length){
        NSMutableDictionary *saved=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"] mutableCopy]?:[NSMutableDictionary dictionary];
        [saved removeObjectForKey:self.videoKey];
        [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"bl_playback_positions"];
    }
    [self updatePlaybackUI];
}
- (void)itemFailed:(NSNotification *)notification {
    self.statusLabel.text=@"播放中断，视频地址可能已过期或编码不兼容";
    [self.player pause];
    [self updatePlaybackUI];
}
- (void)savePosition {
    if(!self.videoKey.length || self.completedPlayback || self.liveStream)return;
    NSTimeInterval seconds=CMTimeGetSeconds(self.player.currentTime);
    if(!isfinite(seconds)||seconds<0)return;
    NSMutableDictionary *saved=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"] mutableCopy]?:[NSMutableDictionary dictionary];
    if(saved.count>100){
        NSArray *keys=[saved allKeys];
        NSUInteger removeCount=MIN((NSUInteger)20,keys.count);
        for(NSString *key in [keys subarrayWithRange:NSMakeRange(0,removeCount)]) [saved removeObjectForKey:key];
    }
    NSTimeInterval duration=[self durationSeconds];
    if(duration>0 && seconds>duration-12)[saved removeObjectForKey:self.videoKey];
    else saved[self.videoKey]=@(seconds);
    [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"bl_playback_positions"];
}
- (void)viewWillDisappear:(BOOL)animated {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideControls) object:nil];
    if(!self.completedPlayback)[self savePosition];
    [self.player pause];
    [super viewWillDisappear:animated];
}
- (void)dealloc {
    [self.saveTimer invalidate];
    if(self.timeObserver && self.player)[self.player removeTimeObserver:self.timeObserver];
    if(self.observingStatus && self.playerItem)
        [self.playerItem removeObserver:self forKeyPath:@"status" context:BLPlayerItemStatusContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
- (void)requestPlayURLForBVID:(NSString *)bvid cid:(NSString *)cid quality:(NSInteger)quality allowFallback:(BOOL)allowFallback completion:(void (^)(NSString *, NSDictionary *, NSError *))completion {
    NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/player/playurl?bvid=%@&cid=%@&qn=%ld&fnval=0&platform=html5",bvid,cid,(long)quality];
    BLRequest(url,^(NSDictionary *json,NSError *err){
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        NSArray *rows=[data[@"durl"] isKindOfClass:[NSArray class]]?data[@"durl"]:@[];
        NSString *stream=@"";
        for(NSDictionary *part in rows){
            if(![part isKindOfClass:[NSDictionary class]])continue;
            NSString *candidate=BLString(part[@"url"]);
            if(![candidate hasPrefix:@"https://"] && ![candidate hasPrefix:@"http://"]){
                NSArray *backup=[part[@"backup_url"] isKindOfClass:[NSArray class]]?part[@"backup_url"]:@[];
                candidate=backup.count?BLString(backup[0]):@"";
            }
            if([candidate hasPrefix:@"https://"] || [candidate hasPrefix:@"http://"]){stream=candidate;break;}
        }
        if(!stream.length && allowFallback && quality!=16){
            [self requestPlayURLForBVID:bvid cid:cid quality:16 allowFallback:NO completion:completion];
            return;
        }
        completion(stream,json,err);
    });
}
- (void)playTapped {
    NSString *bvid=BLString(self.video[@"bvid"]),*cid=self.selectedCID.length?self.selectedCID:BLString(self.video[@"cid"]);
    if(!cid.length){BLAlert(self,@"暂不能播放",@"该视频没有返回 CID，或详情接口不可用。");return;}
    [self.playButton setTitle:@"获取播放地址…" forState:UIControlStateNormal];self.playButton.enabled=NO;
    [self requestPlayURLForBVID:bvid cid:cid quality:self.quality allowFallback:YES completion:^(NSString *stream, NSDictionary *json, NSError *err){
        [self.playButton setTitle:@"全屏播放" forState:UIControlStateNormal];self.playButton.enabled=YES;
        if(![stream hasPrefix:@"https://"] && ![stream hasPrefix:@"http://"]){
            BLAlert(self,@"暂无法播放",[NSString stringWithFormat:@"B站没有返回可用的兼容视频源。已自动尝试当前清晰度和 360P。\n%@\n\n部分 DASH、DRM、HEVC 或受限视频仍无法在 iPhone 4S 上播放。",BLFailure(json,err)]);
            return;
        }
        BLStore(@"bl_history_v1",self.video,NO);
        self.player=[[BLPlayerController alloc] initWithContentURL:[NSURL URLWithString:stream]];
        self.player.videoTitle=BLString(self.video[@"title"]);
        NSInteger actualQuality=[json[@"data"][@"quality"] integerValue];
        self.player.qualityLabel=actualQuality>=80?@"1080P":(actualQuality>=64?@"720P":(actualQuality>=32?@"480P":@"360P"));
        self.player.videoKey=[NSString stringWithFormat:@"%@:%@",bvid,cid];
        self.player.resumeAt=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"bl_playback_positions"][self.player.videoKey] doubleValue];
        [self presentViewController:self.player animated:YES completion:nil];
    }];
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
    self.player.videoTitle=BLString(self.room[@"title"]);
    [self presentViewController:self.player animated:YES completion:nil];
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
@property(nonatomic,strong) UIScrollView *scroller;
@property(nonatomic,strong) UIView *zoomOverlay;
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
    [super viewDidLoad];
    self.title=@"扫码登录 B 站";
    // iOS 8 UINavigationController extends content behind its translucent
    // 44pt navigation bar unless we opt out. That clipped the QR's top edge.
    self.edgesForExtendedLayout=UIRectEdgeNone;
    self.automaticallyAdjustsScrollViewInsets=NO;
    self.view.backgroundColor=BLBg();
    CGFloat w=self.view.bounds.size.width;
    CGFloat h=self.view.bounds.size.height;
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor=BLBg();
    scroll.alwaysBounceVertical=YES;
    self.scroller=scroll;
    [self.view addSubview:scroll];
    CGFloat side=MIN(216.0f,MAX(178.0f,h-204.0f));
    CGFloat qrY=10;
    self.qrView=[[UIImageView alloc] initWithFrame:CGRectMake(floorf((w-side)/2),qrY,side,side)];
    self.qrView.backgroundColor=[UIColor whiteColor];
    self.qrView.contentMode=UIViewContentModeScaleAspectFit;
    self.qrView.layer.cornerRadius=4;
    self.qrView.clipsToBounds=NO; // Never crop any corner/white quiet zone.
    self.qrView.userInteractionEnabled=YES;
    [self.qrView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showLargeQR)]];
    [scroll addSubview:self.qrView];
    CGFloat y=qrY+side+6;
    self.status=[[UILabel alloc] initWithFrame:CGRectMake(12,y,w-24,64)];
    self.status.textColor=BLInk();
    self.status.textAlignment=NSTextAlignmentCenter;
    self.status.numberOfLines=0;
    self.status.font=[UIFont boldSystemFontOfSize:12];
    [scroll addSubview:self.status];
    y+=70;
    self.reloadButton=[UIButton buttonWithType:UIButtonTypeCustom];
    self.reloadButton.frame=CGRectMake(16,y,w-32,40);
    [self.reloadButton setTitle:@"生成登录二维码" forState:UIControlStateNormal];
    self.reloadButton.backgroundColor=BLPink();
    self.reloadButton.layer.cornerRadius=9;
    [self.reloadButton addTarget:self action:@selector(generateQR) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:self.reloadButton];
    y+=46;
    self.instructions=[[UILabel alloc] initWithFrame:CGRectMake(17,y,w-34,70)];
    self.instructions.text=@"使用另一台已登录 B 站的手机 App 扫描二维码并确认。\n轻点二维码可放大 · 约 3 分钟有效";
    self.instructions.textAlignment=NSTextAlignmentCenter;
    self.instructions.font=[UIFont systemFontOfSize:12];
    self.instructions.numberOfLines=4;
    self.instructions.textColor=[UIColor grayColor];
    [scroll addSubview:self.instructions];
    scroll.contentSize=CGSizeMake(w,MAX(y+82,h+8));
    // Request QR after this controller appears in the navigation hierarchy.
}
- (void)showLargeQR {
    if(!self.qrView.image || self.zoomOverlay)return;
    // Keep QR polling running: presenting a full-screen controller would
    // trigger viewWillDisappear, cancelling this live login session.
    UIView *host=self.navigationController.view?:self.view;
    UIView *overlay=[[UIView alloc] initWithFrame:host.bounds];
    overlay.backgroundColor=[UIColor colorWithRed:.10 green:.11 blue:.15 alpha:1];
    overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    CGFloat w=overlay.bounds.size.width,h=overlay.bounds.size.height;
    CGFloat side=MIN(304.0f,MAX(180,MIN(w-16,h-100)));
    UIImageView *image=[[UIImageView alloc] initWithFrame:CGRectMake(floorf((w-side)/2),floorf((h-side)/2)-8,side,side)];
    image.image=self.qrView.image;
    image.backgroundColor=[UIColor whiteColor];
    image.contentMode=UIViewContentModeScaleAspectFit;
    image.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [overlay addSubview:image];
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(0,h-60,w,42)];
    hint.text=@"轻点屏幕缩小二维码";
    hint.textAlignment=NSTextAlignmentCenter;
    hint.textColor=[UIColor whiteColor];
    hint.font=[UIFont systemFontOfSize:13];
    hint.autoresizingMask=UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth;
    [overlay addSubview:hint];
    UIButton *dismiss=[UIButton buttonWithType:UIButtonTypeCustom];
    dismiss.frame=overlay.bounds;
    dismiss.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [dismiss addTarget:self action:@selector(closeLargeQR) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:dismiss];
    [host addSubview:overlay];
    self.zoomOverlay=overlay;
}
- (void)closeLargeQR {
    [self.zoomOverlay removeFromSuperview];
    self.zoomOverlay=nil;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(!self.qrKey.length && !self.qrView.image && self.reloadButton.enabled) [self generateQR];
}

- (void)stopPolling {
    [self.timer invalidate];self.timer=nil;self.qrKey=nil;self.expiresAt=0;
}
- (void)viewWillDisappear:(BOOL)animated {
    [self closeLargeQR];
    [self stopPolling];
    [super viewWillDisappear:animated];
}
- (void)dealloc {[self stopPolling];}
- (void)generateQR {
    [self stopPolling];
    OSStatus check=BLKeychainCheck();
    if(check!=errSecSuccess){
        self.qrView.image=nil;
        self.status.text=[NSString stringWithFormat:@"登录准备失败\n%@",BLKeychainError(check)];
        [self.reloadButton setTitle:@"重新检测钥匙串" forState:UIControlStateNormal];
        self.reloadButton.enabled=YES;
        return;
    }
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
            NSDictionary *session=BLSessionFromPoll(cookies,BLString(data[@"url"]));
            if(!BLString(session[@"SESSDATA"]).length){
                [self stopPolling];
                self.status.text=@"扫码已确认（阶段 1/3）\n但响应未包含 SESSDATA。请刷新二维码后再试。";
                return;
            }
            OSStatus saved=BLSaveSession(session);
            if(saved!=errSecSuccess){
                [self stopPolling];
                self.status.text=[NSString stringWithFormat:@"扫码已确认（阶段 2/3）\n%@",BLKeychainError(saved)];
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
@property(nonatomic,strong) UILabel *feedNotice;
@property(nonatomic,strong) UIButton *moreButton;
@property(nonatomic,strong) NSCache *imageCache;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,copy) NSString *query;
@property(nonatomic,assign) NSInteger mode; // 0 personalized, 1 popular, 2 search, 3 favorite, 4 history
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,assign) NSInteger freshIndex;
@property(nonatomic,assign) NSUInteger requestToken;
@property(nonatomic,assign) BOOL loading;
@property(nonatomic,assign) BOOL feedLoggedIn;
@end
@implementation BLListController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"BiliLite 2";
    self.navigationController.navigationBar.barTintColor=[UIColor whiteColor];
    self.navigationController.navigationBar.tintColor=BLPink();
    self.navigationController.navigationBar.titleTextAttributes=@{NSForegroundColorAttributeName:BLInk()};
    self.tableView.backgroundColor=BLBg();
    self.tableView.rowHeight=82;
    self.imageCache=[NSCache new];self.imageCache.countLimit=24;
    self.items=@[];self.mode=0;self.page=1;self.freshIndex=1;
    self.feedLoggedIn=BLAuthCookie().length>0;
    CGFloat w=self.view.bounds.size.width;
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,121)];
    header.backgroundColor=BLBg();
    self.search=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,w,51)];
    self.search.placeholder=@"搜索视频 / 粘贴 BV 号";
    self.search.delegate=self;self.search.tintColor=BLPink();
    [header addSubview:self.search];
    self.segments=[[UISegmentedControl alloc] initWithItems:@[@"推荐",@"热门",@"搜索",@"收藏",@"历史"]];
    self.segments.frame=CGRectMake(7,54,w-14,36);
    self.segments.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.segments.selectedSegmentIndex=0;
    [self.segments addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.segments];
    self.feedNotice=[[UILabel alloc] initWithFrame:CGRectMake(12,93,w-24,23)];
    self.feedNotice.font=[UIFont systemFontOfSize:11];
    self.feedNotice.textColor=[UIColor grayColor];
    self.feedNotice.textAlignment=NSTextAlignmentCenter;
    self.feedNotice.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.feedNotice];
    self.tableView.tableHeaderView=header;
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(0,0,w,52)];
    UIButton *more=[UIButton buttonWithType:UIButtonTypeSystem];
    more.frame=CGRectMake(12,5,w-24,42);
    more.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    [more setTitle:@"换一批推荐" forState:UIControlStateNormal];
    [more setTitleColor:BLPink() forState:UIControlStateNormal];
    [more addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:more];self.moreButton=more;
    self.tableView.tableFooterView=footer;
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"我的" style:UIBarButtonItemStylePlain target:self action:@selector(openAccount)],
        [[UIBarButtonItem alloc] initWithTitle:@"直播" style:UIBarButtonItemStylePlain target:self action:@selector(openLive)]
    ];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"BV号"
      style:UIBarButtonItemStylePlain target:self action:@selector(openByBV)];
    UIRefreshControl *refresh=[UIRefreshControl new];
    [refresh addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventValueChanged];
    self.refreshControl=refresh;
    [self updateFeedChrome];
    [self fetch];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(self.mode>=3)[self loadLocal];
    else if(self.mode==0){
        BOOL hasAccount=BLAuthCookie().length>0;
        if(hasAccount!=self.feedLoggedIn){
            self.feedLoggedIn=hasAccount;
            [self refresh];
        }
    }
}
- (void)updateFeedChrome {
    self.moreButton.hidden=self.mode>=3 || (self.mode==2 && !self.query.length);
    [self.moreButton setTitle:self.mode==0?@"换一批推荐":@"加载更多" forState:UIControlStateNormal];
    if(self.mode==0) {
        BOOL hasAccount=BLAuthCookie().length>0;
        self.feedNotice.text=hasAccount?@"为你推荐 · 根据已登录账号的兴趣更新":@"游客推荐 · 登录后会更贴合兴趣";
    }else if(self.mode==1)self.feedNotice.text=@"热门榜 · 不根据账号个性化排序";
    else if(self.mode==2)self.feedNotice.text=@"关键词搜索 · 点击结果即可进入详情";
    else self.feedNotice.text=@"本地收藏和本地历史（云端内容请进入「我的」）";
}
- (void)changed:(UISegmentedControl *)control {
    self.mode=control.selectedSegmentIndex;
    self.page=1;self.items=@[];self.loading=NO;
    self.requestToken++;
    [self.tableView reloadData];
    [self updateFeedChrome];
    if(self.mode>=3)[self loadLocal];
    else if(self.mode==2&&!self.query.length)[self showMessage:@"在上方输入关键词，点击键盘上的搜索"];
    else [self fetch];
    [self.search resignFirstResponder];
}
- (void)showMessage:(NSString *)message {
    self.tableView.backgroundView=nil;
    if(!message.length)return;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(18,0,self.view.bounds.size.width-36,120)];
    label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
    label.textColor=[UIColor grayColor];
    label.font=[UIFont systemFontOfSize:13];label.text=message;
    self.tableView.backgroundView=label;
}
- (void)loadLocal {
    NSString *key=self.mode==3?@"bl_favorites_v1":@"bl_history_v1";
    self.items=BLStored(key);
    [self.tableView reloadData];
    [self showMessage:self.items.count?@"":@"这里暂时没有视频。打开视频详情后可以收藏或产生观看历史。"];
}
- (void)refreshTapped {[self refresh];}
- (void)refresh {
    self.requestToken++;self.loading=NO;
    self.page=1;self.items=@[];
    if(self.mode==0)self.freshIndex++;
    [self.tableView reloadData];
    [self updateFeedChrome];
    if(self.mode>=3){
        [self loadLocal];
        [self.refreshControl endRefreshing];
    }else if(self.mode==2&&!self.query.length){
        [self.refreshControl endRefreshing];
        [self showMessage:@"先输入搜索关键词"];
    }else [self fetch];
}
- (void)loadMore {
    if(self.loading || self.mode>=3)return;
    if(self.mode==0){[self refresh];return;}
    if(self.mode==2&&!self.query.length)return;
    self.page++;[self fetch];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    NSString *text=[bar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [bar resignFirstResponder];
    if(!text.length)return;
    NSString *bvid=BLBV(text);
    if(bvid){[self openVideo:@{@"bvid":bvid,@"title":bvid}];return;}
    self.query=text;self.mode=2;self.segments.selectedSegmentIndex=2;
    [self refresh];
}
- (void)fetch {
    if(self.loading)return;
    if(self.mode>=3){[self loadLocal];return;}
    if(self.mode==2 && !self.query.length)return;
    self.loading=YES;[UIApplication sharedApplication].networkActivityIndicatorVisible=YES;
    NSUInteger token=++self.requestToken;
    NSInteger requestedMode=self.mode,requestedPage=self.page;
    NSInteger requestedFresh=self.freshIndex;
    [self showMessage:requestedMode==0?@"正在加载为你推荐…":@"正在加载视频列表…"];
    BLJSONCallback complete=^(NSDictionary *json,NSError *error){
        if(token!=self.requestToken || self.mode!=requestedMode || self.page!=requestedPage)return;
        if(self.mode==0 && self.freshIndex!=requestedFresh)return;
        self.loading=NO;
        [UIApplication sharedApplication].networkActivityIndicatorVisible=NO;
        [self.refreshControl endRefreshing];
        NSDictionary *data=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"]:@{};
        NSArray *rows=nil;
        if(requestedMode==0){
            rows=BLRecommendationVideos(json);
            // When the signed feed is unavailable, show actual popular results
            // with a clear fallback indicator rather than claiming personalization.
            if(!rows.count && [data[@"list"] isKindOfClass:[NSArray class]]){
                rows=data[@"list"];
                self.feedNotice.text=@"推荐暂不可用 · 当前显示热门榜";
            }
        }else if(requestedMode==1)rows=[data[@"list"] isKindOfClass:[NSArray class]]?data[@"list"]:nil;
        else rows=[data[@"result"] isKindOfClass:[NSArray class]]?data[@"result"]:nil;
        if(![rows isKindOfClass:[NSArray class]] || [json[@"code"] integerValue]!=0){
            [self showMessage:[NSString stringWithFormat:@"列表获取失败：%@\n可切换「热门」或下拉重试。",BLFailure(json,error)]];
            if(self.page>1)self.page--;
            return;
        }
        NSMutableArray *list=[self.items mutableCopy]?:[NSMutableArray array];
        for(id raw in rows){
            NSDictionary *video=BLNormalize(raw);
            if(!video)continue;
            BOOL duplicate=NO;
            for(NSDictionary *other in list)if([other[@"bvid"] isEqualToString:video[@"bvid"]]){duplicate=YES;break;}
            if(!duplicate)[list addObject:video];
            if(list.count>=100)break;
        }
        self.items=list;[self.tableView reloadData];
        [self showMessage:list.count?@"":@"当前没有可播放的视频结果，可以换一批或改看热门。"];
    };
    if(requestedMode==0){
        BLRecommend(requestedFresh,^(NSDictionary *json,NSError *error){
            if(token!=self.requestToken || self.mode!=0 || self.freshIndex!=requestedFresh)return;
            if(!error && [json[@"code"] integerValue]==0 && BLRecommendationVideos(json).count){
                complete(json,nil);return;
            }
            // Public chart fallback remains usable when personalized feed
            // is rejected due to Bilibili risk control or account limits.
            BLRequest(@"https://api.bilibili.com/x/web-interface/popular?ps=20&pn=1",^(NSDictionary *hot,NSError *hotError){
                if(!hotError && [hot[@"code"] integerValue]==0 && [hot[@"data"] isKindOfClass:[NSDictionary class]]){
                    complete(hot,nil);
                }else{
                    complete(json?:hot,error?:hotError);
                }
            });
        });
    }else if(requestedMode==1){
        NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/popular?ps=20&pn=%ld",(long)requestedPage];
        BLRequest(url,complete);
    }else BLSearch(self.query,requestedPage,complete);
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
    NSString *reason=BLString(video[@"reason"]);
    ((UILabel *)[cell.contentView viewWithTag:913]).text=reason.length && self.mode==0?
        [NSString stringWithFormat:@"%@ · %@",reason,BLString(video[@"author"])]:
        [NSString stringWithFormat:@"%@ · %@",video[@"author"]?:@"",video[@"view"]?:@""];
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
