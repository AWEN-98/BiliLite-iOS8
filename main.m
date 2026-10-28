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
 self.field=[[UITextField alloc]initWithFrame:CGRectMake(18,60,284,42)];self.field.backgroundColor=[UIColor whiteColor];self.field.textColor=[UIColor blackColor];self.field.placeholder=@"输入 BV 号或视频链接";self.field.autocapitalizationType=UITextAutocapitalizationTypeNone;self.field.autocorrectionType=UITextAutocorrectionTypeNo;self.field.delegate=self;self.field.text=[[NSUserDefaults standardUserDefaults]stringForKey:@"lastBV"];[pane addSubview:self.field];
 UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(18,12,284,42)];title.text=@"Bili Lite · iOS 8";title.textColor=[UIColor whiteColor];title.font=[UIFont boldSystemFontOfSize:23];[pane addSubview:title];
 UIButton *fetch=[UIButton buttonWithType:UIButtonTypeSystem];fetch.frame=CGRectMake(18,116,284,42);fetch.backgroundColor=[UIColor colorWithRed:0.9 green:0.28 blue:0.48 alpha:1];[fetch setTitle:@"获取视频" forState:UIControlStateNormal];[fetch setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[fetch addTarget:self action:@selector(fetchVideo) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:fetch];
 self.status=[[UILabel alloc]initWithFrame:CGRectMake(18,171,284,65)];self.status.text=@"准备就绪。先测试离线播放器";self.status.textColor=[UIColor lightGrayColor];self.status.numberOfLines=0;self.status.font=[UIFont systemFontOfSize:13];[pane addSubview:self.status];
 self.details=[[UILabel alloc]initWithFrame:CGRectMake(18,246,284,100)];self.details.numberOfLines=0;self.details.textColor=[UIColor whiteColor];[pane addSubview:self.details];
 self.play=[UIButton buttonWithType:UIButtonTypeSystem];self.play.frame=CGRectMake(18,362,284,44);[self.play setTitle:@"播放公开视频" forState:UIControlStateNormal];[self.play setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];self.play.backgroundColor=[UIColor darkGrayColor];self.play.enabled=NO;[self.play addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];[pane addSubview:self.play];
 UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(18,422,284,90)];hint.numberOfLines=0;hint.textColor=[UIColor lightGrayColor];hint.font=[UIFont systemFontOfSize:12];hint.text=@"实验版：仅处理公开、兼容的 MP4 视频。播放地址可能因 B 站接口、鉴权或编码变化而不可用。";[pane addSubview:hint];
 self.window.rootViewController=self.root;[self.window makeKeyAndVisible];return YES;
}
- (BOOL)textFieldShouldReturn:(UITextField *)f {[f resignFirstResponder];[self fetchVideo];return YES;}
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
