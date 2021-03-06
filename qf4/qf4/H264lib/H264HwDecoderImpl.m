//
//  H264HwDecoderImpl.m
//  ShiPinHuiYi
//
//  Created by 徐杨 on 16/3/31.
//  Copyright (c) 2016年 feiyuxing. All rights reserved.
//



#import "H264HwDecoderImpl.h"
#import "config.h"
@interface H264HwDecoderImpl()
{
    uint8_t *_sps;
    NSInteger _spsSize;
    uint8_t *_pps;
    NSInteger _ppsSize;
    VTDecompressionSessionRef _deocderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
}
@end

@implementation H264HwDecoderImpl
//解码回调函数
static void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    H264HwDecoderImpl *decoder = (__bridge H264HwDecoderImpl *)decompressionOutputRefCon;
    if (decoder.delegate!=nil)
    {
        [decoder.delegate displayDecodedFrame:pixelBuffer];
    }
}


-(BOOL)initH264Decoder {
    if(_deocderSession) {
        return YES;
    }
    const uint8_t* const parameterSetPointers[2] = { _sps, _pps };
    const size_t parameterSetSizes[2] = { _spsSize, _ppsSize };
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2, //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4, //nal start code size
                                                                          &_decoderFormatDescription);
    
    if(status == noErr) {
        NSDictionary* destinationPixelBufferAttributes = @{
                                                           (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
                                                           //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
//                                                           或者是kCVPixelFormatType_420YpCbCr8Planar
                                                           //因为iOS是  nv12  其他是nv21
                                                           (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:h264outputHeight*2],
                                                           (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:h264outputWidth*2],
                                                           //这里款高和编码反的
                                                           (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]
                                                           };
        
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              (__bridge CFDictionaryRef)destinationPixelBufferAttributes,
                                              &callBackRecord,
                                              &_deocderSession);
        
        //设置实时编码输出(避免延迟)
        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        

        // 设置关键帧（GOPsize)间隔,gop太小的话有时候图像会糊
//        int frameInterval = 10;
//        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
//        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        
//        // 设置期望帧率,不是实际帧率
//        int fps = 10;
//        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
//        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
//
//        //设置码率，上限，单位是bps
//        int bitRate = h264outputHeight * h264outputWidth * 3 * 2 * 8 ;
//        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
//        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
//
//        // 设置码率，均值，单位是byte
//        int bitRateLimit = h264outputWidth * h264outputHeight * 3 * 2 ;
//        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
//        NSLog(@"码率%@",bitRateLimitRef);
//        VTSessionSetProperty(_deocderSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
//        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
//        VTSessionSetProperty(_deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
        
        
    } else {
        NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}

-(CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                          (void *)frame,
                                                          frameSize,
                                                          kCFAllocatorNull,
                                                          NULL,
                                                          0,
                                                          frameSize,
                                                          FALSE,
                                                          &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription ,
                                           1, 0, NULL, 1, sampleSizeArray,
                                           &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_deocderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);

            if(decodeStatus == kVTInvalidSessionErr) {
            
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
                 [self resetH264Decoder];//session失效时
                
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", (int)decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

- (void)resetH264Decoder
{//1
    if(_deocderSession) {
        VTDecompressionSessionInvalidate(_deocderSession);
        CFRelease(_deocderSession);
        _deocderSession = NULL;
    }
    CFDictionaryRef attrs = NULL;
    const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
    //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
    //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
    uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
    attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = didDecompress;
    callBackRecord.decompressionOutputRefCon = NULL;
    if(VTDecompressionSessionCanAcceptFormatDescription(_deocderSession, _decoderFormatDescription))
    {
        NSLog(@"yes");
    }
    
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorSystemDefault,
                                                   _decoderFormatDescription,
                                                   NULL, attrs,
                                                   &callBackRecord,
                                                   &_deocderSession);
    CFRelease(attrs);
}


-(void) decodeNalu:(uint8_t *)frame withSize:(uint32_t)frameSize
{
//    NSLog(@">>>>>>>>>>开始解码");
    int nalu_type = (frame[4] & 0x1F);
    CVPixelBufferRef pixelBuffer = NULL;
    uint32_t nalSize = (uint32_t)(frameSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
    //传输的时候。关键帧不能丢数据 否则绿屏   B/P可以丢  这样会卡顿
    switch (nalu_type)
    {
        case 0x05:
//           NSLog(@"nalu_type:%d Nal type is IDR frame",nalu_type);  //关键帧
            if([self initH264Decoder])
            {
                pixelBuffer = [self decode:frame withSize:frameSize];
            }
            break;
        case 0x07:
//           NSLog(@"nalu_type:%d Nal type is SPS",nalu_type);   //sps
            _spsSize = frameSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        case 0x08:
        {
//            NSLog(@"nalu_type:%d Nal type is PPS",nalu_type);   //pps
            _ppsSize = frameSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        }
        default:
        {
//            NSLog(@"Nal type is B/P frame");//其他帧
           if([self initH264Decoder])
            {
                pixelBuffer = [self decode:frame withSize:frameSize];
            }
            break;
        }
           
            
    }
}

@end
