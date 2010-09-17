//
//  VJXConnector.m
//  VeeJay
//
//  Created by xant on 9/2/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//
//  This file is part of VeeJay
//
//  VeeJay is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Foobar is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with VeeJay.  If not, see <http://www.gnu.org/licenses/>.
//

#import "VJXPin.h"

@interface VJXPinSignal : NSObject {
    id data;
    id sender;
}

@property (retain) id data;
@property (retain) id sender;

+ signalFrom:(id)sender withData:(id)data;
- (id)initWithSender:(id)theSender andData:(id)theData;

@end

@implementation VJXPinSignal

@synthesize sender, data;

+ (id)signalFrom:(id)sender withData:(id)data
{
    id signal = [VJXPinSignal alloc];
    if (signal) {
        return [[signal initWithSender:sender andData:data] autorelease];
    }
    return nil;
}

- (id)initWithSender:(id)theSender andData:(id)theData
{
    if (self = [super init]) {
        self.sender = theSender;
        self.data = theData;
    }
    return self;
}

- (void)dealloc
{
    self.sender = nil;
    self.data = nil;
    [super dealloc];
}

@end

@interface VJXPin (private)
- (BOOL)attachObject:(id)pinReceiver withSelector:(NSString *)pinSignal;
- (void)sendData:(id)data toReceiver:(id)receiver withSelector:(NSString *)selectorName fromSender:(id)sender;
@end

@implementation VJXPin

@synthesize type, name, multiple, continuous, direction, producers, allowedValues;

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
     withSignal:(NSString *)pinSignal
  allowedValues:(NSArray *)pinValues
{
    return [[[VJXPin alloc] initWithName:name
                                 andType:pinType
                            forDirection:pinDirection
                                 ownedBy:pinOwner withSignal:pinSignal
                           allowedValues:pinValues]
            autorelease];
}

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
       withSignal:(NSString *)pinSignal
{
    return [VJXPin pinWithName:name
                       andType:pinType
                  forDirection:pinDirection
                       ownedBy:pinOwner
                    withSignal:pinSignal
                 allowedValues:nil];
}

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
      forDirection:(VJXPinDirection)pinDirection
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
     allowedValues:(NSArray *)pinValues
{
    if (self = [super init]) {
        type = pinType;
        name = [pinName retain];
        receivers = [[NSMutableDictionary alloc] init];
        producers = [[NSMutableArray alloc] init];
        direction = pinDirection;
        multiple = NO;
        continuous = YES;
        currentData = nil;
        currentSender = nil;
        owner = pinOwner;
        ownerSignal = pinSignal;
        allowedValues = pinValues;
    }
    return self;
}

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
      forDirection:(VJXPinDirection)pinDirection
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
{
    return [self initWithName:name
                      andType:pinType
                 forDirection:pinDirection
                      ownedBy:pinOwner
                   withSignal:pinSignal];
}

- (void)sendData:(id)data toReceiver:(id)receiver withSelector:(NSString *)selectorName fromSender:(id)sender
{
    SEL selector = NSSelectorFromString(selectorName);
    int selectorArgsNum = [[selectorName componentsSeparatedByString:@":"] count]-1;
    // checks are now done when registering receivers
    // so we can avoid checking again now if receiver responds to selector and 
    // if the selector expects the correct amount of arguments.
    // this routine is expected to deliver the signals as soon as possible
    // all safety checks must be done before putting new objects in the receivers' table
    switch (selectorArgsNum) {
        case 0:
            // some listener could be uninterested to the data, 
            // but just want to get notified when something travels on a pin
            [receiver performSelector:selector withObject:nil];
            break;
        case 1:
            // some other listeners could be interested only in the data,
            // regardless of the sender
            [receiver performSelector:selector withObject:data];
            break;
        case 2:
            [receiver performSelector:selector withObject:data withObject:sender];
            break;
        default:
            NSLog(@"Unsupported selector : '%@' . It can take up to two arguments\n", selectorName);
    }
}

- (void)performSignal:(VJXPinSignal *)signal
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // send the signal to our owner 
    // (if we are an input pin and if our owner registered a selector)
    if (direction == kVJXInputPin && owner && ownerSignal)
        [self sendData:signal.data toReceiver:owner withSelector:ownerSignal fromSender:signal.sender];
    
    // and then propagate it to all receivers
    @synchronized (receivers) {
        for (id receiver in receivers)
            [self sendData:signal.data toReceiver:receiver withSelector:[receivers objectForKey:receiver] fromSender:signal.sender];
    }
    [pool drain];
}

- (BOOL)attachObject:(id)pinReceiver withSelector:(NSString *)pinSignal
{
    BOOL rv = NO;
    if ([pinReceiver respondsToSelector:NSSelectorFromString(pinSignal)]) {
        if ([[pinSignal componentsSeparatedByString:@":"] count]-1 <= 2) {
            @synchronized(receivers) {
                [receivers setObject:pinSignal forKey:pinReceiver];
            }
            rv = YES;
        } else {
            NSLog(@"Unsupported selector : '%@' . It can take up to two arguments\n", pinSignal);
        }
    } else {
        NSLog(@"Object %@ doesn't respond to %@\n", pinReceiver, pinSignal);
    }
    // deliver the signal to the just connected receiver
    if (rv == YES) {
        VJXPinSignal *signal;
        @synchronized(self) {
            signal = [VJXPinSignal signalFrom:currentSender withData:currentData];
        }
        [self performSelectorInBackground:@selector(performSignal:) withObject:signal];
    }
    return rv;
}

- (void)detachObject:(id)pinReceiver
{
    @synchronized(receivers) {
        [receivers removeObjectForKey:pinReceiver];
    }
}

- (void)deliverSignal:(id)data
{
    [self deliverSignal:data fromSender:self];
}

- (void)deliverSignal:(id)data fromSender:(id)sender
{
    id signalData = [NSNull null];
    switch (type) {
        case kVJXStringPin:
            if ([data isKindOfClass:[NSString class]])
                signalData = data;
            break;
        case kVJXNumberPin:
            if ([data isKindOfClass:[NSNumber class]])
                signalData = data;
            break;
        case kVJXImagePin:
            if ([data isKindOfClass:[CIImage class]])
                signalData = data;
            break;
        case kVJXSizePin:
            if ([data isKindOfClass:[VJXSize class]])
                signalData = data;
            break;
        case kVJXPointPin:
            if ([data isKindOfClass:[VJXPoint class]])
                signalData = data;
            break;
        default:
            NSLog(@"Unkown pin type!\n");
    }
    
    @synchronized(self) {
        if (data) {
            if (currentData)
                [currentData release];
            currentData = [data retain];
        }
        if (sender)
            currentSender = sender;
        else
            currentSender = self;
    }
    
    // if we are an output pin and not receivers have been hooked, 
    // it's useless to perform the signal
    @synchronized(receivers) {
        if (direction == kVJXOutputPin && ![receivers count])
            return;
    }
    VJXPinSignal *signal = [VJXPinSignal signalFrom:sender withData:data];
    // Since we need to honor our frequency, we can't wait until the signal 
    // is propagated to all receiver, otherwise our entity will slowdown its runloop
    // because of a deep chain of receivers. To avoid affecting the entity we will
    // perform the selector asynchronously in the background 
    [self performSelectorInBackground:@selector(performSignal:) withObject:signal];
}

- (void)allowMultipleConnections:(BOOL)choice
{
    multiple = choice;
}

- (void)dealloc
{
    if (currentData)
        [currentData release];
    [name release];
    [receivers release];
    [producers release];
    [super dealloc];
}

- (BOOL)connectToPin:(VJXPin *)destinationPin
{
    @synchronized(self) {
        if (destinationPin.type == type) {
            if (direction == kVJXInputPin) {
                if (destinationPin.direction != kVJXInputPin) {
                    if ([producers count] && !multiple)
                        [self disconnectAllPins];
                    if ([destinationPin attachObject:self withSelector:@"deliverSignal:fromSender:"]) {
                        [producers addObject:destinationPin];
                        return YES;
                    }
                }
            } else if (destinationPin.direction == kVJXInputPin) {
                if (direction != kVJXInputPin) 
                    return [destinationPin connectToPin:self];
            } else if (direction == kVJXAnyPin) {
                if ([producers count] && multiple)
                    [self disconnectAllPins];
                if ([destinationPin attachObject:self withSelector:@"deliverSignal:fromSender:"]) {
                    [producers addObject:self];
                    return YES;
                }
            } else if (destinationPin.direction == kVJXAnyPin) {
                return [destinationPin connectToPin:self];
            }
            
        }
    }
    return NO;
}

- (void)disconnectFromPin:(VJXPin *)destinationPin
{
    @synchronized(self) {
        if (direction == kVJXInputPin) {
            [destinationPin detachObject:self];
            [producers removeObjectIdenticalTo:destinationPin];
        } else {
            [destinationPin disconnectFromPin:self];
        }
    }
}

- (void)disconnectAllPins
{
    NSArray *receiverObjects;
    @synchronized (self) { 
        while ([producers count])
            [self disconnectFromPin:[producers objectAtIndex:0]];
        @synchronized(receivers) {
             receiverObjects = [receivers allKeys];
        }
        for (VJXPin *receiver in receiverObjects)
            [receiver disconnectFromPin:self];
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    // we don't want copies, but we want to use such objects as keys of a dictionary
    // so we still need to conform to the 'copying' protocol,
    // but since we are to be considered 'immutable' we can adopt what described at the end of :
    // http://developer.apple.com/mac/library/documentation/cocoa/conceptual/MemoryMgmt/Articles/mmImplementCopy.html
    return [self retain];
}

- (id)readPinValue
{
    id data;
    @synchronized(self) {
        data = [currentData retain];
    }
    return [data autorelease];
}

- (NSArray *)readProducers
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    @synchronized(self) {
        for (VJXPin *producer in producers) {
            id value = [producer readPinValue];
            if (value)
                [array addObject:value];
        }
    }
    return [array autorelease];
}

- (NSString *)typeName
{
    switch (type) {
        case kVJXStringPin:
            return @"String";
            break;
        case kVJXNumberPin:
            return @"Number";
            break;
        case kVJXImagePin:
            return @"Image";
            break;
        case kVJXSizePin:
            return @"Size";
            break;
        case kVJXPointPin:
            return @"Point";
            break;
    }
    return @"Unknown";
}

- (BOOL)moveProducerFromIndex:(NSUInteger)src toIndex:(NSUInteger)dst
{
    @synchronized(self) {
        if ([producers count] > dst) {
            VJXPin *obj = [[producers objectAtIndex:src] retain];
            [producers removeObjectAtIndex:src];
            [producers insertObject:obj atIndex:dst];
            return YES;
        }
    }
    return NO;
}

- (NSString *)description
{
    NSString *ownerName;
    if ([owner respondsToSelector:@selector(name)])
        ownerName = [owner performSelector:@selector(name)];
    return [NSString stringWithFormat:@"%@:%@", ownerName, name];
}

@end