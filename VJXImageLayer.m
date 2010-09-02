//
//  VJXImageLayer.m
//  VeeJay
//
//  Created by Igor Sutton on 8/25/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//

#import "VJXImageLayer.h"
#import <QTKit/QTKit.h>


@implementation VJXImageLayer

@synthesize imagePath, image;

- (id)init
{
    if (self = [super init]) {
        self.imagePath = @"/Users/igorsutton/Desktop/output.jpeg";
    }

    return self;
}

- (void)load
{
    NSData *imageData = [[NSData alloc] initWithContentsOfFile:self.imagePath];
    CIImage *image_ = [CIImage imageWithData:imageData];
    if (image_)
        self.image = image_;
}

- (CIImage *)frameImageForTime:(uint64_t)timeStamp
{
    @synchronized(self) {
        if (!self.image)
            [self load];
        // XXX - it's useless to render the image each time ... 
        //       it should be done only if image parameters have changed
        if (self.image) {
            CIFilter *colorFilter = [CIFilter filterWithName:@"CIColorControls"];
            [colorFilter setDefaults];
            [colorFilter setValue:self.saturation forKey:@"inputSaturation"];
            [colorFilter setValue:self.brightness forKey:@"inputBrightness"];
            [colorFilter setValue:self.contrast forKey:@"inputContrast"];
            [colorFilter setValue:self.image forKey:@"inputImage"];
            CIImage *transformedFrame = [colorFilter valueForKey:@"outputImage"];
            self.lastFrame = transformedFrame;
        }
    }
    return [super frameImageForTime:timeStamp];
}

@end
