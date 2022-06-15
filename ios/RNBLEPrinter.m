//
//  RNBLEPrinter.m
//
//  Created by MTT on 06/10/19.
//  Copyright © 2019 Facebook. All rights reserved.
//


#import <Foundation/Foundation.h>

#import "RNBLEPrinter.h"
#import "PrinterSDK.h"

extern int p0[];
extern int p1[];
extern int p2[];
extern int p3[];
extern int p4[];
extern int p5[];
extern int p6[];

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

@implementation RNBLEPrinter

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(init:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        _printerArray = [NSMutableArray new];
        m_printer = [[NSObject alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNetPrinterConnectedNotification:) name:@"NetPrinterConnected" object:nil];
        // API MISUSE: <CBCentralManager> can only accept this command while in the powered on state
        [[PrinterSDK defaultPrinterSDK] scanPrintersWithCompletion:^(Printer* printer){}];
        successCallback(@[@"Init successful"]);
    } @catch (NSException *exception) {
        errorCallback(@[@"No bluetooth adapter available"]);
    }
}

- (void)handleNetPrinterConnectedNotification:(NSNotification*)notification
{
    m_printer = nil;
}

RCT_EXPORT_METHOD(getDeviceList:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        !_printerArray ? [NSException raise:@"Null pointer exception" format:@"Must call init function first"] : nil;
        [[PrinterSDK defaultPrinterSDK] scanPrintersWithCompletion:^(Printer* printer){
            [_printerArray addObject:printer];
            NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:[_printerArray count]];
            [_printerArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSDictionary *dict = @{ @"device_name" : printer.name, @"inner_mac_address" : printer.UUIDString};
                [mapped addObject:dict];
            }];
            NSMutableArray *uniquearray = (NSMutableArray *)[[NSSet setWithArray:mapped] allObjects];;
            successCallback(@[uniquearray]);
        }];
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(connectPrinter:(NSString *)inner_mac_address
                  success:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        __block BOOL found = NO;
        __block Printer* selectedPrinter = nil;
        [_printerArray enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop){
            selectedPrinter = (Printer *)obj;
            if ([inner_mac_address isEqualToString:(selectedPrinter.UUIDString)]) {
                found = YES;
                *stop = YES;
            }
        }];

        if (found) {
            [[PrinterSDK defaultPrinterSDK] connectBT:selectedPrinter];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BLEPrinterConnected" object:nil];
            m_printer = selectedPrinter;
            successCallback(@[[NSString stringWithFormat:@"Connected to printer %@", selectedPrinter.name]]);
        } else {
            [NSException raise:@"Invalid connection" format:@"connectPrinter: Can't connect to printer %@", inner_mac_address];
        }
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printRawData:(NSString *)text
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        !m_printer ? [NSException raise:@"Invalid connection" format:@"printRawData: Can't connect to printer"] : nil;

        NSNumber* boldPtr = [options valueForKey:@"bold"];
        NSNumber* alignCenterPtr = [options valueForKey:@"center"];

        BOOL bold = (BOOL)[boldPtr intValue];
        BOOL alignCenter = (BOOL)[alignCenterPtr intValue];

        bold ? [[PrinterSDK defaultPrinterSDK] sendHex:@"1B2108"] : [[PrinterSDK defaultPrinterSDK] sendHex:@"1B2100"];
        alignCenter ? [[PrinterSDK defaultPrinterSDK] sendHex:@"1B6102"] : [[PrinterSDK defaultPrinterSDK] sendHex:@"1B6101"];
        [[PrinterSDK defaultPrinterSDK] printText:text];

        NSNumber* beepPtr = [options valueForKey:@"beep"];
        NSNumber* cutPtr = [options valueForKey:@"cut"];

        BOOL beep = (BOOL)[beepPtr intValue];
        BOOL cut = (BOOL)[cutPtr intValue];

        beep ? [[PrinterSDK defaultPrinterSDK] beep] : nil;
        cut ? [[PrinterSDK defaultPrinterSDK] cutPaper] : nil;

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printRawImage:(NSString *)base64Image withOptions:(NSDictionary *) options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {
        !m_printer ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
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
        !m_printer ? [NSException raise:@"Invalid connection" format:@"closeConn: Can't connect to printer"] : nil;
        [[PrinterSDK defaultPrinterSDK] disconnect];
        m_printer = nil;
    } @catch (NSException *exception) {
        NSLog(@"%@", exception.reason);
    }
}

@end
