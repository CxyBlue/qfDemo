//
//  ViewController.m
//  qf4
//
//  Created by 086 on 2018/9/6.
//  Copyright © 2018年 XK. All rights reserved.
//

#import "ViewController.h"
#import "qf4-Swift.h"
#import "AAPLEAGLLayer.h"
#import "H264HwDecoderImpl.h"
#import <iconv.h>

@import SocketIO;

@interface ViewController ()<H264HwDecoderImplDelegate>{
    
    H264HwDecoderImpl *h264Decoder;
    AAPLEAGLLayer *playLayer;
    int p1;
}

@property (strong, nonatomic) SocketManager* manager;
@property (strong, nonatomic) SocketIOClient *socket;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    h264Decoder = [[H264HwDecoderImpl alloc] init];
    h264Decoder.delegate = self;

    playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 80, self.view.frame.size.width, self.view.frame.size.height-160)];
    playLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    [self.view.layer addSublayer:playLayer];
    
    p1 = 0;
    
    [self qfTest];

}

-(void)qfTest{
    
    
    NSURL* url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"http://s7.xky.com:80"]];
    
    NSDictionary * dict = @{@"log": @NO, @"forceWebsockets": @YES,
                            @"forcePolling": @NO,
                            @"compress": @YES,
                            @"reconnectAttempts":@(-1),
                            @"forceNew": @YES,
                            @"reconnectAttempts":@5,
                            @"path":@"/xky", @"connectParams":@{@"sn":@"81756539",@"action":@"forward",@"session":@"dx2paxa284rppx38cdhmgea98wv6rwu3a1254vuh9n24aj21ahqpwk9t9h6pjmkp6th4ujkk9x0q0ha5d4np4vatf586ccb5e1qpgu379ta5cm3ed9ak2e1ban632j3cad1pcm3ma4yku",@"EIO":@"3"}};
    //使用给定的url初始化一个socketIOClient，后面的config是对这个socket的一些配置，比如log设置为YES，控制台会打印连接时的日志等
    self.manager = [[SocketManager alloc] initWithSocketURL:url config:dict];

    self.socket = self.manager.defaultSocket;

    
//    __weak typeof(self) weakSelf = self;
    //监听是否连接上服务器，正确连接走后面的回调
    [self.socket on:@"connect" callback:^(NSArray* data, SocketAckEmitter* ack) {
        
        NSLog(@"socket connected");
        //请求服务器430009这个股票代码的日k数据 kline_day服务端传递规定好的关键字
//        [self.socket emit:@"ping" with:@[@"sss"]];
        
    }];
    
    // 心跳包 具体情况看服务端发送和接收方式
    [self.socket on:@"ping" callback:^(NSArray * _Nonnull data, SocketAckEmitter * _Nonnull ack) {
        NSLog(@"socket - 心跳包,%@",data);
        // 查看socket 连接状态
        NSLog(@"connect manager status  : %ld",(long)self.manager.status);
    }];
    
    //监听h264，视频流
    [self.socket on:@"h264" callback:^(NSArray* data, SocketAckEmitter* ack) {
        
        NSLog(@"视频流h264:%lu",(unsigned long)[data[0]length]);
        NSLog(@"H264%@",data);
    
        if ([data[0]length] > 6) {
            
           //解码
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:data[0]];
            if (self->p1 == 0) {
                
                Byte *testByte = (Byte *)[h264Data bytes];
                //发送sps
                NSData *adata = [[NSData alloc] initWithBytes:testByte length:17];
                [self->h264Decoder decodeNalu:(uint8_t *)[adata bytes] withSize:(uint32_t)adata.length];
                NSLog(@"--%@",adata);
                //发送pps
                 Byte *b= (Byte*)malloc([h264Data length]-17);
                for(int i=17;i<[h264Data length];i++){
//                    printf("testByte = %d\n",testByte[i]);
                    b[i-17] = testByte[i];
                }
                NSData *bdata = [[NSData alloc] initWithBytes:b length:[h264Data length]-17];
                NSLog(@"--%@",bdata);
                 [self->h264Decoder decodeNalu:(uint8_t *)[bdata bytes] withSize:(uint32_t)bdata.length];
                 self->p1 = 1;
                
            }else{
                
                
                [self->h264Decoder decodeNalu:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
            }
            

        }
        
    }];
    
    //监听event，触摸事件
    [self.socket on:@"event" callback:^(NSArray* data, SocketAckEmitter* ack) {
        NSLog(@"触摸:%@",data);
        
    }];
    
    
    [self.socket on:@"error" callback:^(NSArray* data, SocketAckEmitter* ack)
     {
         NSLog(@"%@消息服务器连接错误",data);
         //         self.state = NO;
         
         [self.socket emit:@"Join" with:@[@"测试"]];
     }];
    

    [self.socket connect];
    
}


#pragma mark -  H264解码回调  H264HwDecoderImplDelegate delegare
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer
{
    if(imageBuffer)
    {
        playLayer.pixelBuffer = imageBuffer;
        CVPixelBufferRelease(imageBuffer);
    }
}



-(void)test{//官方
    
    NSURL *url = [NSURL URLWithString:@"ws://f2.api.xky.com:8888/"];
    
    //使用给定的url初始化一个socketIOClient，后面的config是对这个socket的一些配置，比如log设置为YES，控制台会打印连接时的日志等
    SocketManager* manager = [[SocketManager alloc] initWithSocketURL:url config:@{@"log": @NO, @"compress": @YES}];
    SocketIOClient* socket = manager.defaultSocket;
    
    //监听是否连接上服务器，正确连接走后面的回调
    [socket on:@"connect" callback:^(NSArray* data, SocketAckEmitter* ack) {
        NSLog(@"socket connected");
//        [socket emit:@"Join" with:@[@"测试"]];
    }];
    //监听new message，这是socketIO官网提供的一个测试用例，大家都可以试试。如果成功连接，会收到data内容。
    [socket on:@"new message" callback:^(NSArray* data, SocketAckEmitter* ack) {
        NSLog(@"服务器连接成功加入房间:%@",data);
    }];
    [socket connect];
}


-(void)test2{
    
    NSURL* url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"https://socket-io-chat.now.sh/"]];
    self.manager = [[SocketManager alloc] initWithSocketURL:url config:@{@"log": @NO, @"compress": @YES}];
    self.socket = self.manager.defaultSocket;
    [self clientEvents];
    [self.socket connect];
    
}

-(void)clientEvents
{
    //成功连接
    [self.socket on:@"connect" callback:^(NSArray* data, SocketAckEmitter* ack)
     {
         NSLog(@"%@",@"connect-消息服务器连接成功");
//         self.state = YES;
//         if (self.connetedBlock) {
//             self.connetedBlock(@"connected",nil);
//         }
     }];
    
    //监听new message，这是socketIO官网提供的一个测试用例，大家都可以试试。如果成功连接，会收到data内容。
    [self.socket on:@"new message" callback:^(NSArray* data, SocketAckEmitter* ack) {
        NSLog(@"response is %@",data);
    }];
    
    //断开连接
    [self.socket on:@"disconnect" callback:^(NSArray* data, SocketAckEmitter* ack)
     {
         NSLog(@"%@",@"disconnect-断开与服务器的连接");
//         self.state = NO;
         
     }];
    
    //开始重新连接
    [self.socket on:@"reconnect" callback:^(NSArray* data, SocketAckEmitter* ack)
     {
         NSLog(@"%@",@"reconnect-重新连接消息服务器");
     }];
    
    //error
    [self.socket on:@"error" callback:^(NSArray* data, SocketAckEmitter* ack)
     {
        NSLog(@"%@",@"error-消息服务器连接错误");
//         self.state = NO;
         
     }];
    
    //   //监听new message，这是socketIO官网提供的一个测试用例，大家都可以试试。如果成功连接，会收到data内容。
    //    [self.socket on:@"Join" callback:^(NSArray* data, SocketAckEmitter* ack) {
    //
    //        double cur = [[data objectAtIndex:0] floatValue];
    //
    //        [[self.socket emitWithAck:@"canUpdate" with:@[@(cur)]] timingOutAfter:0 callback:^(NSArray* data) {
    //            //需要给服务端传递规定好的关键字
    //            [self.socket emit:@"update" with:@[@{@"amount": @(cur + 2.50)}]];
    //        }];
    //
    //        [ack with:@[@"Got your currentAmount, ", @"dude"]];
    //    }];
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
