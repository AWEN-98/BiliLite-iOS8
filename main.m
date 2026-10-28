#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
@interface BLApp : UIResponder <UIApplicationDelegate,UITextFieldDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *root;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *details;
@property(nonatomic,strong) UIButton *play;
@property(nonatomic,strong) NSString *stream;
@property(nonatomic,strong) UITextField *searchField;
@property(nonatomic,strong) UITextView *searchResults;
@property(nonatomic,strong) NSArray *resultVideos;
@property(nonatomic,strong) UIButton *pasteButton;
@property(nonatomic,strong) MPMoviePlayerViewController *player;
@end
@implementation BLApp
- (UILabel *)label:(NSString *)text y:(CGFloat)y size:(CGFloat)s {
 UILabel *v=[[UILabel alloc]initWithFrame:CGRectMake(18,y,284,70)];
 v.numberOfLines=0;v.text=text;v.textColor=[UIColor whiteColor];v.font=[UIFont systemFontOfSize:s];
 [self.root.view addSubview:v];return v;
}
- (UIButton *)button:(NSString *)title y:(CGFloat)y action:(SEL)action {
 UIButton *v=[UIButton buttonWithType:UIButtonTypeSystem];v.frame=CGRectMake(18,y,284,42);
 [v setTitle:title forState:UIControlStateNormal];[v setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
 v.backgroundColor=[UIColor colorWithRed:0.86 green:0.22 blue:0.44 alpha:1];
 [v addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.root.view addSubview:v];return v;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
 self.window=[[UIWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];
 self.root=[UIViewController new];self.root.view.backgroundColor=[UIColor colorWithRed:0.09 green:0.10 blue:0.15 alpha:1];
 UIScrollView *scroll=[[UIScrollView alloc]initWithFrame:self.root.view.bounds];scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 [self.root.view addSubview:scroll];
 UIView *pane=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,570)];[scroll addSubview:pane];scroll.contentSize=pane.bounds.size;
 self.field=[[UITextField alloc]initWithFrame:CGRectMake(18,60,204,42)];self.field.backgroundColor=[UIColor whiteColor];self.field.textColor=[UIColor blackColor];self.field.placeholder=@"输入 BV 号或视频链接";self.field.autocapitalizationType=UITextAutocapitalizationTypeNone;self.field.autocorrectionType=UITextAutocorrectionTypeNo;self.field.delegate=self;self.field.leftView=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,10)];self.field.leftViewMode=UITextFieldViewModeAlways;self.field.text=[[NSUserDefaults standardUserDefaults]stringForKey:@"lastBV"];[pane addSubview:self.field];
 self.pasteButton=[UIButton buttonWithType:UIButtonTypeSystem];self.pasteButton.frame=CGRectMake(231,60,71,42);[self.pasteButton setTitle:@"粘贴" forState:UIControlStateNormal];self.pasteButton.backgroundColor=[UIColor colorWithRed:.25 green:.35 blue:.5 alpha:1];[self.pasteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[self.pasteButton addTarget:self action:@selector(pasteBV) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:self.pasteButton];
 UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(18,12,284,42)];title.text=@"Bili Lite · iOS 8";title.textColor=[UIColor whiteColor];title.font=[UIFont boldSystemFontOfSize:23];[pane addSubview:title];
 UIButton *fetch=[UIButton buttonWithType:UIButtonTypeSystem];fetch.frame=CGRectMake(18,116,284,42);fetch.backgroundColor=[UIColor colorWithRed:0.9 green:0.28 blue:0.48 alpha:1];[fetch setTitle:@"获取视频" forState:UIControlStateNormal];[fetch setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[fetch addTarget:self action:@selector(fetchVideo) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:fetch];
 self.status=[[UILabel alloc]initWithFrame:CGRectMake(18,171,284,65)];self.status.text=@"准备就绪。先测试离线播放器";self.status.textColor=[UIColor lightGrayColor];self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:13];[pane addSubview:self.status];
 self.details=[[UILabel alloc]initWithFrame:CGRectMake(18,246,284,100)];self.details.numberOfLines=0;self.details.textColor=[UIColor whiteColor];[pane addSubview:self.details];
 self.play=[UIButton buttonWithType:UIButtonTypeSystem];self.play.frame=CGRectMake(18,362,284,44);[self.play setTitle:@"播放公开视频" forState:UIControlStateNormal];[self.play setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];self.play.backgroundColor=[UIColor darkGrayColor];self.play.enabled=NO;[self.play addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:self.play];
 UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(18,422,284,90)];hint.numberOfLines=0;hint.textColor=[UIColor lightGrayColor];hint.font=[UIFont systemFontOfSize:12];hint.text=@"实验版：仅处理公开、兼容的 MP4 视频。播放地址可能因 B 站接口、鉴权或编码变化而不可用。";[pane addSubview:hint];
 UILabel *searchLabel=[[UILabel alloc]initWithFrame:CGRectMake(18,510,284,30)];searchLabel.text=@"视频搜索";searchLabel.textColor=[UIColor whiteColor];searchLabel.font=[UIFont boldSystemFontOfSize:18];[pane addSubview:searchLabel];
 self.searchField=[[UITextField alloc]initWithFrame:CGRectMake(18,546,205,40)];self.searchField.backgroundColor=[UIColor whiteColor];self.searchField.placeholder=@"关键词";self.searchField.autocorrectionType=UITextAutocorrectionTypeNo;self.searchField.returnKeyType=UIReturnKeySearch;self.searchField.delegate=self;[pane addSubview:self.searchField];
 UIButton *search=[UIButton buttonWithType:UIButtonTypeSystem];search.frame=CGRectMake(232,546,70,40);[search setTitle:@"搜索" forState:UIControlStateNormal];[search setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];search.backgroundColor=[UIColor colorWithRed:.9 green:.28 blue:.48 alpha:1];[search addTarget:self action:@selector(searchVideos) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:search];
 self.searchResults=[[UITextView alloc]initWithFrame:CGRectMake(18,598,284,226)];self.searchResults.editable=NO;self.searchResults.font=[UIFont systemFontOfSize:13];self.searchResults.backgroundColor=[UIColor colorWithRed:.14 green:.17 blue:.23 alpha:1];self.searchResults.textColor=[UIColor whiteColor];self.searchResults.text=@"搜索公开的视频，结果中可复制 BV 号到上方打开。";[pane addSubview:self.searchResults];
 UIButton *copyResult=[UIButton buttonWithType:UIButtonTypeSystem];copyResult.frame=CGRectMake(18,829,284,38);[copyResult setTitle:@"选择搜索结果中的 BV 号并复制到输入框" forState:UIControlStateNormal];[copyResult setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[copyResult addTarget:self action:@selector(pasteBV) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:copyResult];
 self.window.rootViewController=self.root;[self.window makeKeyAndVisible];return YES;
}
- (BOOL)textFieldShouldReturn:(UITextField *)f {[f resignFirstResponder];if(f==self.searchField)[self searchVideos];else[self fetchVideo];return YES;}
- (void)pasteBV {NSString *clip=[UIPasteboard generalPasteboard].string;if(clip.length){self.field.text=clip;self.status.text=@"已粘贴，可以获取视频";}}
- (void)searchVideos {
 [self.searchField resignFirstResponder];
 NSString *key=[self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
 if(!key.length){self.searchResults.text=@"请输入关键词";return;}
 self.searchResults.text=@"正在搜索公开的视频…";
 NSString *q=[key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
 NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=1",q];
 [self request:url done:^(NSDictionary *json,NSError *error){
  NSArray *rows=[json[@"data"] isKindOfClass:[NSDictionary class]]?json[@"data"][@"result"]:nil;
  if(error || ![rows isKindOfClass:[NSArray class]] || [json[@"code"] integerValue]!=0){
   self.searchResults.text=[NSString stringWithFormat:@"搜索接口不可用：%@\n可直接使用上方 BV 号播放。",error.localizedDescription?:json[@"message"]?:@"接口要求额外验证"];
   return;
  }
  NSMutableString *result=[NSMutableString string];
  NSUInteger count=0;
  for(NSDictionary *video in rows){
   if(![video isKindOfClass:[NSDictionary class]])continue;
   NSString *bvid=video[@"bvid"];NSString *title=video[@"title"];
   if(![bvid isKindOfClass:[NSString class]]||!bvid.length)continue;
   if(![title isKindOfClass:[NSString class]])title=@"未命名";
   title=[title stringByReplacingOccurrencesOfString:@"<em class=\"keyword\">" withString:@""];
   title=[title stringByReplacingOccurrencesOfString:@"</em>" withString:@""];
   [result appendFormat:@"%lu. %@\n%@\n\n",(unsigned long)(++count),title,bvid];
   if(count>=15)break;
  }
  self.searchResults.text=result.length?result:@"当前没有搜索结果";
 }];
}

- (void)request:(NSString *)address done:(void(^)(NSDictionary*,NSError*))done {
 NSURL *u=[NSURL URLWithString:address];if(!u){done(nil,[NSError errorWithDomain:@"URL" code:1 userInfo:nil]);return;}
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
 [r setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
 [[[NSURLSession sharedSession]dataTaskWithRequest:r completionHandler:^(NSData *data,NSURLResponse *res,NSError *err){
  NSDictionary *obj=nil;if(!err&&data){id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&err];if([json isKindOfClass:[NSDictionary class]])obj=json;}
  dispatch_async(dispatch_get_main_queue(),^{done(obj,err);});
 }]resume];
}
- (void)fetchVideo {
 [self.field resignFirstResponder];self.play.enabled=NO;self.stream=nil;
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"BV[0-9A-Za-z]{10}" options:NSRegularExpressionCaseInsensitive error:NULL];
 NSString *s=self.field.text?:@"";NSTextCheckingResult *m=[re firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
 if(!m){self.status.text=@"BV 号不正确";return;}
 NSString *bvid=[s substringWithRange:m.range];[[NSUserDefaults standardUserDefaults]setObject:bvid forKey:@"lastBV"];
 self.status.text=@"正在获取视频信息…";self.details.text=@"";
 NSString *url=[NSString stringWithFormat:@"https://api.bilibili.com/x/web-interface/view?bvid=%@",bvid];
 [self request:url done:^(NSDictionary *json,NSError *err){
  NSDictionary *data=json[@"data"];
  if(err||![data isKindOfClass:[NSDictionary class]]||[json[@"code"] integerValue]!=0){self.status.text=[NSString stringWithFormat:@"详情获取失败：%@",err.localizedDescription?:json[@"message"]?:@"接口无响应"];return;}
  NSString *title=[data[@"title"] isKindOfClass:[NSString class]]?data[@"title"]:@"未命名";
  NSDictionary *owner=data[@"owner"];self.details.text=[NSString stringWithFormat:@"%@\nUP主：%@",title,[owner isKindOfClass:[NSDictionary class]]?owner[@"name"]?:@"":@""];
  NSString *cid=[data[@"cid"] description];NSString *p=[NSString stringWithFormat:@"https://api.bilibili.com/x/player/playurl?bvid=%@&cid=%@&qn=16&fnval=0&platform=html5",bvid,cid];
  [self request:p done:^(NSDictionary *play,NSError *e){
   NSArray *d=play[@"data"][@"durl"];NSString *stream=[d isKindOfClass:[NSArray class]]&&d.count>0?[d[0] objectForKey:@"url"]:nil;
   if([stream isKindOfClass:[NSString class]]&&[stream hasPrefix:@"http"]){self.stream=stream;self.play.enabled=YES;self.play.backgroundColor=[UIColor colorWithRed:.9 green:.28 blue:.48 alpha:1];self.status.text=@"获取成功，点击播放";}else{self.status.text=@"已取得视频资料，但没有兼容的 MP4 地址"; }
  }];
 }];
}
- (void)playVideo {
 if(!self.stream.length)return;
 self.player=[[MPMoviePlayerViewController alloc]initWithContentURL:[NSURL URLWithString:self.stream]];
 self.player.moviePlayer.shouldAutoplay=YES;
 [self.root presentMoviePlayerViewControllerAnimated:self.player];
 [self.player.moviePlayer play];
}
@end
int main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([BLApp class]));}}
