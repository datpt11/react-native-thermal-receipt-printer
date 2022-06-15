//
//  RNNetPrinter.m
//  RNThermalReceiptPrinter
//
//  Created by MTT on 06/11/19.
//  Copyright © 2019 Facebook. All rights reserved.
//


#import "RNNetPrinter.h"
#import "PrinterSDK.h"
#include <ifaddrs.h>
#include <arpa/inet.h>


int p0[] = { 0, 0x80 };
int p1[] = { 0, 0x40 };
int p2[] = { 0, 0x20 };
int p3[] = { 0, 0x10 };
int p4[] = { 0, 0x08 };
int p5[] = { 0, 0x04 };
int p6[] = { 0, 0x02 };

NSString *const EVENT_SCANNER_RESOLVED = @"scannerResolved";
NSString *const EVENT_SCANNER_RUNNING = @"scannerRunning";

@interface PrivateIP : NSObject

@end

@implementation PrivateIP

- (NSString *)getIPAddress {

    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];

                }

            }

            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;

}

@end

@implementation NSData (HexRepresentation)

- (NSString *)hexString {
    const unsigned char *bytes = (const unsigned char *)self.bytes;
    NSMutableString *hex = [NSMutableString new];
    for (NSInteger i = 0; i < self.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [hex copy];
}

@end

@implementation RNNetPrinter

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents
{
    return @[EVENT_SCANNER_RESOLVED, EVENT_SCANNER_RUNNING];
}

RCT_EXPORT_METHOD(init:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    connected_ip = nil;
    is_scanning = NO;
    _printerArray = [NSMutableArray new];
    successCallback(@[@"Init successful"]);
}

RCT_EXPORT_METHOD(getDeviceList:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePrinterConnectedNotification:) name:PrinterConnectedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBLEPrinterConnectedNotification:) name:@"BLEPrinterConnected" object:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self scan];
    });

    successCallback(@[_printerArray]);
}

- (void) scan {
    @try {
        PrivateIP *privateIP = [[PrivateIP alloc]init];
        NSString *localIP = [privateIP getIPAddress];
        is_scanning = YES;
        [self sendEventWithName:EVENT_SCANNER_RUNNING body:@YES];
        _printerArray = [NSMutableArray new];

        NSString *prefix = [localIP substringToIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)];
        NSInteger suffix = [[localIP substringFromIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)] intValue];

        for (NSInteger i = 1; i < 255; i++) {
            if (i == suffix) continue;
            NSString *testIP = [NSString stringWithFormat:@"%@.%ld", prefix, (long)i];
            current_scan_ip = testIP;
            [[PrinterSDK defaultPrinterSDK] connectIP:testIP];
            [NSThread sleepForTimeInterval:0.5];
        }

        NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:_printerArray];
        NSArray *arrayWithoutDuplicates = [orderedSet array];
        _printerArray = (NSMutableArray *)arrayWithoutDuplicates;

        [self sendEventWithName:EVENT_SCANNER_RESOLVED body:_printerArray];
    } @catch (NSException *exception) {
        NSLog(@"No connection");
    }
    [[PrinterSDK defaultPrinterSDK] disconnect];
    is_scanning = NO;
    [self sendEventWithName:EVENT_SCANNER_RUNNING body:@NO];
}

- (void)handlePrinterConnectedNotification:(NSNotification*)notification
{
    if (is_scanning) {
        [_printerArray addObject:@{@"host": current_scan_ip, @"port": @9100}];
    }
}

- (void)handleBLEPrinterConnectedNotification:(NSNotification*)notification
{
    connected_ip = nil;
}

RCT_EXPORT_METHOD(connectPrinter:(NSString *)host
                  withPort:(nonnull NSNumber *)port
                  success:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        BOOL isConnectSuccess = [[PrinterSDK defaultPrinterSDK] connectIP:host];
        !isConnectSuccess ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer %@", host] : nil;

        connected_ip = host;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetPrinterConnected" object:nil];
        successCallback(@[[NSString stringWithFormat:@"Connecting to printer %@", host]]);

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printRawData:(NSString *)text
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        NSNumber* beepPtr = [options valueForKey:@"beep"];
        NSNumber* cutPtr = [options valueForKey:@"cut"];

        BOOL beep = (BOOL)[beepPtr intValue];
        BOOL cut = (BOOL)[cutPtr intValue];

        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;

        // [[PrinterSDK defaultPrinterSDK] printTestPaper];
        [[PrinterSDK defaultPrinterSDK] printText:text];
        beep ? [[PrinterSDK defaultPrinterSDK] beep] : nil;
        cut ? [[PrinterSDK defaultPrinterSDK] cutPaper] : nil;
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printHex:(NSString *)text
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        NSNumber* beepPtr = [options valueForKey:@"beep"];
        NSNumber* cutPtr = [options valueForKey:@"cut"];

        BOOL beep = (BOOL)[beepPtr intValue];
        BOOL cut = (BOOL)[cutPtr intValue];
         NSLog(@"text in PrintHex is - %@", text);
        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;

        // [[PrinterSDK defaultPrinterSDK] printTestPaper];
        // [[PrinterSDK defaultPrinterSDK] sendHex:text];
        // beep ? [[PrinterSDK defaultPrinterSDK] beep] : nil;
        // cut ? [[PrinterSDK defaultPrinterSDK] cutPaper] : nil;
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printRawImage:(NSString *)base64Image withOptions:(NSDictionary *) options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
        NSInteger nWidth = [[options valueForKey:@"width"] integerValue];
        NSData *data = [[NSData alloc]initWithBase64EncodedString:base64Image options:NSDataBase64DecodingIgnoreUnknownCharacters];
        UIImage *srcImage = [UIImage imageWithData:data scale:1];
        NSLog(@"The DeCoded String is - %@", data);
        NSData *jpgData = UIImageJPEGRepresentation(srcImage, 1);
        UIImage *jpgImage = [[UIImage alloc] initWithData:jpgData];
        NSInteger imgHeight = jpgImage.size.height;
        NSInteger imgWidth = jpgImage.size.width;
        NSLog(@"Width  is - %i", imgWidth);
        NSLog(@"Height is - %i", imgHeight);
        NSInteger width = nWidth;//((int)(((nWidth*0.86)+7)/8))*8-7;
        CGSize size = CGSizeMake(width, imgHeight*width/imgWidth);
        UIImage *scaled = [self imageWithImage:jpgImage scaledToFillSize:size];
        NSInteger imgHeightUpdate = scaled.size.height;
        NSInteger imgWidthUpdate = scaled.size.width;
        NSLog(@"Width  after scale is - %i", imgWidthUpdate);
        NSLog(@"Height is - %i", imgHeightUpdate);
        NSLog(@"Width  after scale 2 is  - %i", size.width);
        NSLog(@"Height 2  is - %i", size.height);

        unsigned char * graImage = [self imageToGreyImage:scaled];
        unsigned char * formatedData = [self format_K_threshold:graImage width: imgWidthUpdate height: imgHeightUpdate];
        NSData *dataToPrint = [self eachLinePixToCmd:formatedData nWidth: imgWidthUpdate nHeight: imgHeightUpdate nMode:0];
        NSLog(@"dataToPrint Image is - %@", dataToPrint);
//      NSString *hexToPrint = [self serializeDeviceToken: dataToPrint];
        NSString *hexToPrint = [dataToPrint hexString];
        NSLog(@"hexToPrint Image is - %@", hexToPrint);
           [[PrinterSDK defaultPrinterSDK] sendHex:hexToPrint];
           [[PrinterSDK defaultPrinterSDK] cutPaper] ;

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

- (NSString*) serializeDeviceToken:(NSData*) deviceToken
{
    NSMutableString *str = [NSMutableString stringWithCapacity:64];
    int length = [deviceToken length];
    char *bytes = malloc(sizeof(char) * length);

    [deviceToken getBytes:bytes length:length];

    for (int i = 0; i < length; i++)
    {
        [str appendFormat:@"%02.2hhx", bytes[i]];
    }
    free(bytes);

    return str;
}

- (UIImage *)imageWithImage:(UIImage *)image scaledToFillSize:(CGSize)size
{
    CGFloat scale = MAX(size.width/image.size.width, size.height/image.size.height);
    CGFloat width = image.size.width * scale;
    CGFloat height = image.size.height * scale;
    CGRect imageRect = CGRectMake((size.width - width)/2.0f,
                                  (size.height - height)/2.0f,
                                  width,
                                  height);

    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [image drawInRect:imageRect];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

- (uint8_t *)imageToGreyImage:(UIImage *)image {
    // Create image rectangle with current image width/height
    int kRed = 1;
    int kGreen = 2;
    int kBlue = 4;

    int colors = kGreen | kBlue | kRed;

    CGFloat actualWidth = image.size.width;
    CGFloat actualHeight = image.size.height;
    NSLog(@"actual size: %f,%f",actualWidth,actualHeight);
    uint32_t *rgbImage = (uint32_t *) malloc(actualWidth * actualHeight * sizeof(uint32_t));
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgbImage, actualWidth, actualHeight, 8, actualWidth*4, colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipLast);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextSetShouldAntialias(context, NO);
    CGContextDrawImage(context, CGRectMake(0, 0, actualWidth, actualHeight), [image CGImage]);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

//    CGRect imageRect = CGRectMake(0, 0, actualWidth, actualHeight);
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
//
//    CGContextRef context = CGBitmapContextCreate(rgbImage, actualWidth, actualHeight, 8, actualWidth*4, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipLast);
//    CGContextDrawImage(context, imageRect, [image CGImage]);
//
//    //CGImageRef grayImage = CGBitmapContextCreateImage(context);
//    CGColorSpaceRelease(colorSpace);
//    CGContextRelease(context);

//    context = CGBitmapContextCreate(nil, actualWidth, actualHeight, 8, 0, nil, kCGImageAlphaOnly);
//    CGContextDrawImage(context, imageRect, [image CGImage]);
//    CGImageRef mask = CGBitmapContextCreateImage(context);
//    CGContextRelease(context);

//    UIImage *grayScaleImage = [UIImage imageWithCGImage:CGImageCreateWithMask(grayImage, mask) scale:image.scale orientation:image.imageOrientation];
//    CGImageRelease(grayImage);
 //   CGImageRelease(mask);

    // Return the new grayscale image

     //now convert to grayscale
    uint8_t *m_imageData = (uint8_t *) malloc(actualWidth * actualHeight);
   // NSMutableString *toLog = [[NSMutableString alloc] init];
    for(int y = 0; y < actualHeight; y++) {
        for(int x = 0; x < actualWidth; x++) {
            uint32_t rgbPixel=rgbImage[(int)(y*actualWidth+x)];
            uint32_t sum=0,count=0;
            if (colors & kRed) {sum += (rgbPixel>>24)&255; count++;}
            if (colors & kGreen) {sum += (rgbPixel>>16)&255; count++;}
            if (colors & kBlue) {sum += (rgbPixel>>8)&255; count++;}
           // [toLog appendFormat:@"pixel:%d,sum:%d,count:%d,val:%d;",rgbPixel,sum,count,(int)(sum/count)];
            m_imageData[(int)(y*actualWidth+x)]=sum/count;

        }
    }
    //NSLog(@"m_imageData:%@",toLog);
    return m_imageData;
//    // Create image rectangle with current image width/height
//    CGRect imageRect = CGRectMake(0, 0, image.size.width, image.size.height);
//
//    // Grayscale color space
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
//
//    // Create bitmap content with current image size and grayscale colorspace
//    CGContextRef context = CGBitmapContextCreate(nil, image.size.width, image.size.height, 8, 0, colorSpace, kCGImageAlphaNone);
//
//    // Draw image into current context, with specified rectangle
//    // using previously defined context (with grayscale colorspace)
//    CGContextDrawImage(context, imageRect, [image CGImage]);
//
//    // Create bitmap image info from pixel data in current context
//    CGImageRef imageRef = CGBitmapContextCreateImage(context);
//
//    // Create a new UIImage object
//    UIImage *newImage = [UIImage imageWithCGImage:imageRef];
//
//    // Release colorspace, context and bitmap information
//    CGColorSpaceRelease(colorSpace);
//    CGContextRelease(context);
//    CFRelease(imageRef);
//
//    // Return the new grayscale image
//    return newImage;

}

- (NSData *)eachLinePixToCmd:(unsigned char *)src nWidth:(NSInteger) nWidth nHeight:(NSInteger) nHeight nMode:(NSInteger) nMode
{
    NSLog(@"SIZE OF SRC: %lu",sizeof(&src));
    NSInteger nBytesPerLine = (int)nWidth/8;
    unsigned char * data = malloc(nHeight*(8+nBytesPerLine));
   // const char* srcData = (const char*)[src bytes];
    NSInteger k = 0;
   // NSMutableString *toLog = [[NSMutableString alloc] init];
    for(int i=0;i<nHeight;i++){
        NSInteger var10 = i*(8+nBytesPerLine);
         //GS v 0 m xL xH yL yH d1....dk 打印光栅位图
                data[var10 + 0] = 29;//GS
                data[var10 + 1] = 118;//v
                data[var10 + 2] = 48;//0
                data[var10 + 3] =  (unsigned char)(nMode & 1);
                data[var10 + 4] =  (unsigned char)(nBytesPerLine % 256);//xL
                data[var10 + 5] =  (unsigned char)(nBytesPerLine / 256);//xH
                data[var10 + 6] = 1;//yL
                data[var10 + 7] = 0;//yH
//        for(int l=0;l<8;l++){
//            NSInteger d =data[var10 + l];
//            [toLog appendFormat:@"%ld,",(long)d];
//        }

        for (int j = 0; j < nBytesPerLine; ++j) {
            data[var10 + 8 + j] = (int) (p0[src[k]] + p1[src[k + 1]] + p2[src[k + 2]] + p3[src[k + 3]] + p4[src[k + 4]] + p5[src[k + 5]] + p6[src[k + 6]] + src[k + 7]);
            k =k+8;
             //  [toLog appendFormat:@"%ld,",(long)data[var10+8+j]];
        }
       // [toLog appendString:@"\n\r"];
    }
   // NSLog(@"line datas: %@",toLog);
    return [NSData dataWithBytes:data length:nHeight*(8+nBytesPerLine)];
}

- (unsigned char *)format_K_threshold:(unsigned char *) orgpixels
                        width:(NSInteger) xsize height:(NSInteger) ysize
{
    unsigned char * despixels = malloc(xsize*ysize);
    int graytotal = 0;
    int k = 0;

    int i;
    int j;
    int gray;
    for(i = 0; i < ysize; ++i) {
        for(j = 0; j < xsize; ++j) {
            gray = orgpixels[k] & 255;
            graytotal += gray;
            ++k;
        }
    }

    int grayave = graytotal / ysize / xsize;
    k = 0;
   // NSMutableString *logStr = [[NSMutableString alloc]init];
   // int oneCount = 0;
    for(i = 0; i < ysize; ++i) {
        for(j = 0; j < xsize; ++j) {
            gray = orgpixels[k] & 255;
            if(gray > grayave) {
                despixels[k] = 0;
            } else {
                despixels[k] = 1;
               // oneCount++;
            }

            ++k;
           // [logStr appendFormat:@"%d,",despixels[k]];
        }
    }
   // NSLog(@"despixels [with 1 count:%d]: %@",oneCount,logStr);
    return despixels;
}

RCT_EXPORT_METHOD(closeConn) {
    @try {
        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
        [[PrinterSDK defaultPrinterSDK] disconnect];
        connected_ip = nil;
    } @catch (NSException *exception) {
        NSLog(@"%@", exception.reason);
    }
}

@end
