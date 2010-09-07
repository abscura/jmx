//
//  VJXConnector.h
//  VeeJay
//
//  Created by xant on 9/2/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "VJXSize.h"
#import "VJXPoint.h"

typedef enum {
    kVJXVoidPin,
    kVJXStringPin,
    kVJXNumberPin,
    kVJXImagePin,
    kVJXAudioPin,
    kVJXPointPin,
    kVJXSizePin,
} VJXPinType;

typedef enum {
    kVJXInputPin,
    kVJXOutputPin,
    kVJXAnyPin
} VJXPinDirection;

@interface VJXPin : NSObject <NSCopying> {
@private
    VJXPinType          type;
    NSString            *name;
    NSMutableDictionary *receivers;
    NSMutableArray      *connections;
    BOOL                multiple;
    id                  currentData;
    VJXPinDirection     direction;
}

@property (readonly) VJXPinType type;
@property (readonly) NSString *name;
@property (readonly) BOOL multiple;
@property (readonly) VJXPinDirection direction;

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
    forDirection:(VJXPinDirection)pinDirection;
+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection 
    boundToObject:(id)pinReceiver 
     withSelector:(NSString *)pinSignal;

- (id)initWithName:(NSString *)name andType:(VJXPinType)pinType forDirection:(VJXPinDirection)pinDirection;
- (BOOL)attachObject:(id)pinReceiver withSelector:(NSString *)pinSignal;
- (BOOL)connectToPin:(VJXPin *)destinationPin;
- (void)disconnectFromPin:(VJXPin *)destinationPin;
- (void)disconnectAllPins;
- (void)deliverSignal:(id)data fromSender:(id)sender;
- (void)deliverSignal:(id)data;
- (void)allowMultipleConnections:(BOOL)choice;

- (id)readPinValue;

@end
