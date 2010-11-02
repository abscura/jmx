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
#import "VJXContext.h"
#import "VJXOutputPin.h"
#import "VJXInputPin.h"
#import <v8.h>

using namespace v8;

@implementation VJXPin

@synthesize type, name, multiple, continuous, connected,
            direction, allowedValues, owner, minValue, maxValue;

#pragma mark Constructors

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
       withSignal:(NSString *)pinSignal
         userData:(id)userData
    allowedValues:(NSArray *)pinValues
     initialValue:(id)value

{
    id pinClass = pinDirection == kVJXInputPin
                ? [VJXInputPin class]
                : [VJXOutputPin class];
    return [[[pinClass alloc]     initWithName:name
                                       andType:pinType
                                       ownedBy:pinOwner
                                    withSignal:pinSignal
                                      userData:userData
                                 allowedValues:pinValues
                                  initialValue:value]
            autorelease];
}

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
     withSignal:(NSString *)pinSignal
     userData:(id)userData
  allowedValues:(NSArray *)pinValues
{
    id pinClass = pinDirection == kVJXInputPin
                ? [VJXInputPin class]
                : [VJXOutputPin class];
    return  [pinClass pinWithName:name
                              andType:pinType
                         forDirection:pinDirection
                              ownedBy:pinOwner
                           withSignal:pinSignal
                             userData:userData
                        allowedValues:pinValues
                         initialValue:nil];
}

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
       withSignal:(NSString *)pinSignal
{
    id pinClass = pinDirection == kVJXInputPin
    ? [VJXInputPin class]
    : [VJXOutputPin class];
    return [pinClass pinWithName:name
                         andType:pinType
                    forDirection:pinDirection
                         ownedBy:pinOwner
                      withSignal:pinSignal
                        userData:nil
                   allowedValues:nil];
}

+ (id)pinWithName:(NSString *)name
          andType:(VJXPinType)pinType
     forDirection:(VJXPinDirection)pinDirection
          ownedBy:(id)pinOwner
       withSignal:(NSString *)pinSignal
         userData:(id)userData
{
    id pinClass = pinDirection == kVJXInputPin
                ? [VJXInputPin class]
                : [VJXOutputPin class];
    return [pinClass pinWithName:name
                         andType:pinType
                    forDirection:pinDirection
                         ownedBy:pinOwner
                      withSignal:pinSignal
                        userData:userData
                   allowedValues:nil];
}

#pragma mark Initializers

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
{
    return [self initWithName:name
                      andType:pinType
                      ownedBy:pinOwner
                   withSignal:pinSignal
                     userData:nil
                allowedValues:nil];
}

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
          userData:(id)userData
{
    return [self initWithName:name
                      andType:pinType
                      ownedBy:pinOwner
                   withSignal:pinSignal
                     userData:userData
                allowedValues:nil];
}

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
          userData:(id)userData
     allowedValues:(NSArray *)pinValues
{
    return [self initWithName:pinName
                      andType:pinType
                      ownedBy:pinOwner
                   withSignal:pinSignal
                     userData:userData
                allowedValues:pinValues
                 initialValue:nil];
}

- (id)initWithName:(NSString *)pinName
           andType:(VJXPinType)pinType
           ownedBy:(id)pinOwner
        withSignal:(NSString *)pinSignal
          userData:(id)userData
     allowedValues:(NSArray *)pinValues
      initialValue:(id)value
{
    self = [super init];
    if (self) {
        type = pinType;
        name = [pinName retain];
        multiple = NO;
        continuous = YES;
        connected = NO;
        currentSender = nil;
        owner = pinOwner;
        ownerSignal = pinSignal;
        ownerUserData = userData;
        if (pinValues)
            allowedValues = [[NSMutableArray arrayWithArray:pinValues] retain];
        rOffset = wOffset = 0;
        if (value && [self isCorrectDataType:value]) {
            currentSender = owner;
            dataBuffer[wOffset++] = [value retain];
        }
        writersLock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

- (id)init
{
    // bad usage
    [self dealloc];
    return nil;
}

#pragma mark Implementation

+ (NSString *)nameforType:(VJXPinType)type
{
    switch (type) {
        case kVJXStringPin:
            return @"String";
        case kVJXTextPin:
            return @"Text";
        case kVJXNumberPin:
            return @"Number";
        case kVJXImagePin:
            return @"Image";
        case kVJXSizePin:
            return @"Size";
        case kVJXPointPin:
            return @"Point";
        case kVJXAudioPin:
            return @"Audio";
        case kVJXColorPin:
            return @"Color";
    }
    return nil;
}

- (BOOL)isCorrectDataType:(id)data
{
    switch (type) {
        case kVJXStringPin:
        case kVJXTextPin:
            if (![data isKindOfClass:[NSString class]])
                return NO;
            break;
        case kVJXNumberPin:
            if ([[data className] isEqualToString:@"NSCFNumber"] || [data isKindOfClass:[NSNumber class]])
                return YES;
            return NO;
            break;
        case kVJXImagePin:
            if (![data isKindOfClass:[CIImage class]])
                return NO;
            break;
        case kVJXSizePin:
            if (![data isKindOfClass:[VJXSize class]])
                return NO;
            break;
        case kVJXPointPin:
            if (![data isKindOfClass:[VJXPoint class]])
                return NO;
            break;
        case kVJXAudioPin:
            if (![data isKindOfClass:[VJXAudioBuffer class]])
                return NO;
            break;
        case kVJXColorPin:
            if (![data isKindOfClass:[NSColor class]])
                return NO;
            break;
        default:
            NSLog(@"Unknown pin type!\n");
            return NO;
    }
    return YES;
}

- (void)allowMultipleConnections:(BOOL)choice
{
    multiple = choice;
}

- (void)dealloc
{
    [name release];
    if (allowedValues)
        [allowedValues release];
    [writersLock release];
    [super dealloc];
}

- (BOOL)connectToPin:(VJXPin *)destinationPin
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:destinationPin, @"outputPin", self, @"inputPin", nil];
    // send a connect notification for all involved pins
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VJXPinConnected"
                                                        object:self
                                                      userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VJXPinConnected"
                                                        object:destinationPin
                                                      userInfo:userInfo];
    return YES;
}

- (void)disconnectFromPin:(VJXPin *)destinationPin
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:destinationPin, @"outputPin", self, @"inputPin", nil];
    // send a disconnect notification for all the involved pins
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VJXPinDisconnected"
                                                        object:self
                                                      userInfo:userInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VJXPinDisconnected"
                                                        object:destinationPin
                                                      userInfo:userInfo];
}

- (void)disconnectAllPins
{

}

- (id)copyWithZone:(NSZone *)zone
{
    // we don't want copies, but we want to use such objects as keys of a dictionary
    // so we still need to conform to the 'copying' protocol,
    // but since we are to be considered 'immutable' we can adopt what described at the end of :
    // http://developer.apple.com/mac/library/documentation/cocoa/conceptual/MemoryMgmt/Articles/mmImplementCopy.html
    return [self retain];
}

- (NSString *)typeName
{
    NSString *aName = [VJXPin nameforType:type];
    if (aName)
        return aName;
    return @"Unknown";
}

- (NSString *)description
{
    NSString *ownerName;
    if ([owner respondsToSelector:@selector(name)])
        ownerName = [owner performSelector:@selector(name)];
    return [NSString stringWithFormat:@"%@:%@", ownerName, name];
}

- (void)addAllowedValue:(id)value
{
    if ([self isCorrectDataType:value]) {
        if (!allowedValues)
            allowedValues = [[NSMutableArray alloc] init];
        [allowedValues addObject:value];
    }
}

- (void)addAllowedValues:(NSArray *)values
{
    for (id value in values)
        [self addAllowedValue:value];
}

- (void)removeAllowedValue:(id)value
{
    if ([self isCorrectDataType:value] && allowedValues) {
        [allowedValues removeObject:value];
        if ([allowedValues count] == 0) {
            [allowedValues release];
            allowedValues = nil;
        }
    }
}

- (void)removeAllowedValues:(NSArray *)values
{
    for (id value in values)
        [self removeAllowedValue:value];
}

- (void)addMinLimit:(id)value
{
    if ([self isCorrectDataType:value])
        minValue = [value retain];
}

- (void)addMaxLimit:(id)value
{
    if ([self isCorrectDataType:value])
        maxValue = [value retain];
}

- (id)readData
{
    id data = [dataBuffer[rOffset&0x1] retain];
    return [data autorelease];
}

- (void)deliverData:(id)data
{
    [self deliverData:data fromSender:self];
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
            [receiver performSelector:selector withObject:data withObject:ownerUserData];
            break;
        default:
            NSLog(@"Unsupported selector : '%@' . It can take up to two arguments\n", selectorName);
    }
}

- (void)deliverData:(id)data fromSender:(id)sender
{

    // check if NULL data has been signaled
    // and if it's the case, clear currentData and return
    if (!data) {
        return;
    }
    // if instead new data arrived, check if it's of the correct type
    // and propagate the signal if that's the case
    if ([self isCorrectDataType:data]) {
        // check if we restrict possible values
        if (allowedValues && ![allowedValues containsObject:data]) {
            // TODO - Error Message (a not allowed value has been signaled
            return;
        }
        // this lock protects us from multiple senders delivering a signal at the exact same time
        // wOffset and rOffset must both be incremented in an atomic operation.
        // concurrency here can happen only in 2 scenarios :
        // - an input pin which allows multiple producers (like mixers)
        // - when the user connect a new producer a signal is sent, and the signal from
        //   current producer could still being executed.
        // TODO - try to get rid of this lock
        [writersLock lock]; // in single-producer mode, this lock will always be free to lock
        dataBuffer[wOffset&0x1] = [data retain];
        if (wOffset > rOffset) {
            UInt32 off = rOffset++;
            [dataBuffer[off&0x1] release];
        }
        wOffset++;
        [writersLock unlock];

        // XXX - sender is not protected by a lock
        if (sender)
            currentSender = sender;
        else
            currentSender = self;
        VJXPinSignal *signal = [VJXPinSignal signalFromSender:sender receiver:owner data:data];

#if USE_NSOPERATIONS
        NSBlockOperation *signalDelivery = [NSBlockOperation blockOperationWithBlock:^{
            [self performSignal:signal];
        }];
        [signalDelivery setQueuePriority:NSOperationQueuePriorityVeryHigh];
        [signalDelivery setThreadPriority:1.0];
        [[VJXContext operationQueue] addOperation:signalDelivery];
#else
        [self performSelector:@selector(performSignal:) onThread:[VJXContext signalThread] withObject:signal waitUntilDone:NO];
#endif
    }
}

- (void)performSignal:(VJXPinSignal *)signal
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // send the signal to our owner
    // (if we are an input pin and if our owner registered a selector)
    if (direction == kVJXInputPin && ownerSignal)
        [self sendData:signal.data toReceiver:signal.receiver withSelector:ownerSignal fromSender:signal.sender];
    [pool drain];
}

- (BOOL)canConnectToPin:(VJXPin *)pin
{
    return (type == pin.type && direction != pin.direction) ? YES : NO;
}

#pragma mark V8
static v8::Handle<Value>name(Local<String> name, const AccessorInfo& info)
{
    HandleScope handle_scope;
    v8::Handle<External> field = v8::Handle<External>::Cast(info.Holder()->GetInternalField(0));
    VJXPin *pin = (VJXPin *)field->Value();
    return handle_scope.Close(String::New([pin.name UTF8String], [pin.name length]));
}

static v8::Handle<Value>type(Local<String> name, const AccessorInfo& info)
{
    HandleScope handle_scope;
    v8::Handle<External> field = v8::Handle<External>::Cast(info.Holder()->GetInternalField(0));
    VJXPin *pin = (VJXPin *)field->Value();
    NSString *typeName = [pin typeName];
    return handle_scope.Close(String::New([typeName UTF8String], [typeName length]));
}

v8::Handle<Value> connect(const Arguments& args)
{
    HandleScope handleScope;
    Local<Object> self = args.Holder();
    Local<External> wrap = Local<External>::Cast(self->GetInternalField(0));
    VJXPin *pin = (VJXPin *)wrap->Value();
    v8::Handle<Value> arg = args[0];
    if (arg->IsObject()) {
        v8::Handle<Object> obj = v8::Handle<Object>::Cast(arg);
        v8::Handle<External> field = v8::Handle<External>::Cast(obj->GetInternalField(0));
        VJXPin *dest = (VJXPin *)field->Value();
        if (dest) {
            BOOL connected = [pin connectToPin:dest];
            return v8::Boolean::New(connected);
        }
    }
    return v8::Undefined();
}

+ (v8::Handle<FunctionTemplate>)jsClassTemplate
{
    HandleScope handleScope;
    v8::Handle<FunctionTemplate> classTemplate = FunctionTemplate::New();
    classTemplate->SetClassName(String::New("Pin"));
    v8::Handle<ObjectTemplate> classProto = classTemplate->PrototypeTemplate();
    classProto->Set("connect", FunctionTemplate::New(connect));
    // set instance methods
    v8::Handle<ObjectTemplate> instanceTemplate = classTemplate->InstanceTemplate();
    instanceTemplate->SetInternalFieldCount(1);
    // Add accessors for each of the fields of the entity.
    instanceTemplate->SetAccessor(String::NewSymbol("name"), name);
    instanceTemplate->SetAccessor(String::NewSymbol("type"), type);
    /*
    instanceTemplate->SetAccessor(String::NewSymbol("multiple"), multiple);
    instanceTemplate->SetAccessor(String::NewSymbol("direction"), direction);
    instanceTemplate->SetAccessor(String::NewSymbol("allowedValues"), allowedValues);
    instanceTemplate->SetAccessor(String::NewSymbol("continuous"), continuous);
    instanceTemplate->SetAccessor(String::NewSymbol("owner"), owner);
    instanceTemplate->SetAccessor(String::NewSymbol("minValue"), minValue);
    instanceTemplate->SetAccessor(String::NewSymbol("maxValue"), maxValue);
    instanceTemplate->SetAccessor(String::NewSymbol("connected"), connected);
     */
    return handleScope.Close(classTemplate);
}

- (v8::Handle<v8::Object>)jsObj
{
    HandleScope handle_scope;
    v8::Handle<FunctionTemplate> classTemplate = [VJXPin jsClassTemplate];
    v8::Handle<Object> jsInstance = classTemplate->InstanceTemplate()->NewInstance();
    v8::Handle<External> external_ptr = External::New(self);
    jsInstance->SetInternalField(0, external_ptr);
    return handle_scope.Close(jsInstance);
}

@end

