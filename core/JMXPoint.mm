//
//  JMXPoint.m
//  JMX
//
//  Created by xant on 9/5/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//
//  This file is part of JMX
//
//  JMX is free software: you can redistribute it and/or modify
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
//  along with JMX.  If not, see <http://www.gnu.org/licenses/>.
//

#define __JMXV8__ 1
#import "JMXPoint.h"
#import "JMXScript.h"

using namespace v8;

@implementation JMXPoint

@synthesize nsPoint;

+ (id)pointWithX:(CGFloat)x Y:(CGFloat)y
{
    return [self pointWithNSPoint:NSMakePoint(x, y)];
}

+ (id)pointWithNSPoint:(NSPoint)point
{
    id obj = [JMXPoint alloc];
    return [[obj initWithNSPoint:point] autorelease];
}

- (id)initWithNSPoint:(NSPoint)point
{
    self = [super init];
    if (self) {
        self.nsPoint = point;
    }
    return self;
}

- (id)init
{
    self = [super init];
    if (self)
        return [self initWithNSPoint:NSZeroPoint];
    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (void)setX:(CGFloat)x
{
    nsPoint.x = x;
}

- (void)setY:(CGFloat)y
{
    nsPoint.y = y;
}

- (CGFloat)x
{
    return nsPoint.x;
}

- (CGFloat)y
{
    return nsPoint.y;
}

- (BOOL)isEqual:(JMXPoint *)object
{
    if ([object isKindOfClass:[JMXPoint class]] &&
        nsPoint.y == object.y && nsPoint.x == object.x)
    {
        return YES;
    }
    return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
    // we don't want copies, but we want to use such objects as keys of a dictionary
    // so we still need to conform to the 'copying' protocol,
    // but since we are to be considered 'immutable' we can adopt what described at the end of :
    // http://developer.apple.com/mac/library/documentation/cocoa/conceptual/MemoryMgmt/Articles/mmImplementCopy.html
    return [[JMXPoint alloc] initWithNSPoint:nsPoint];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Point: { X: %.2f, Y: %.2f }", nsPoint.x, nsPoint.y];
}
#pragma mark V8

static v8::Persistent<FunctionTemplate> objectTemplate;

+ (v8::Persistent<FunctionTemplate>)jsObjectTemplate
{
    v8::Locker lock;
    HandleScope handleScope;
    
    if (!objectTemplate.IsEmpty())
        return objectTemplate;
    
    objectTemplate = Persistent<FunctionTemplate>::New(FunctionTemplate::New());
      
    objectTemplate->SetClassName(String::New("Point"));
    v8::Handle<ObjectTemplate> classProto = objectTemplate->PrototypeTemplate();
    // set instance methods
    v8::Handle<ObjectTemplate> instanceTemplate = objectTemplate->InstanceTemplate();
    instanceTemplate->SetInternalFieldCount(1);
    // Add accessors for each of the fields of the entity.
    instanceTemplate->SetAccessor(String::NewSymbol("x"), GetDoubleProperty, SetDoubleProperty);
    instanceTemplate->SetAccessor(String::NewSymbol("y"), GetDoubleProperty, SetDoubleProperty);
    return objectTemplate;
}

static void JMXPointJSDestructor(Persistent<Value> object, void *parameter)
{
    HandleScope handle_scope;
    v8::Locker lock;
    JMXPoint *obj = static_cast<JMXPoint *>(parameter);
    //NSLog(@"V8 WeakCallback (Point) called %@", obj);
    [obj release];
    if (!object.IsEmpty()) {
        object.ClearWeak();
        object.Dispose();
        object.Clear();
    }
}

- (v8::Handle<v8::Object>)jsObj
{
    //v8::Locker lock;
    HandleScope handle_scope;
    v8::Handle<FunctionTemplate> objectTemplate = [JMXPoint jsObjectTemplate];
    v8::Persistent<Object> jsInstance = v8::Persistent<Object>::New(objectTemplate->InstanceTemplate()->NewInstance());
    jsInstance.MakeWeak([self retain], JMXPointJSDestructor);
    jsInstance->SetPointerInInternalField(0, self);
    return handle_scope.Close(jsInstance);
}

+ (void)jsRegisterClassMethods:(v8::Handle<v8::FunctionTemplate>)constructor
{
}

@end

v8::Handle<v8::Value> JMXPointJSConstructor(const v8::Arguments& args)
{
    HandleScope handleScope;
    //v8::Locker locker;
    v8::Persistent<FunctionTemplate> objectTemplate = [JMXPoint jsObjectTemplate];
    int64_t x = 0;
    int64_t y = 0;
    if (args.Length() >= 2) {
        x = args[0]->IntegerValue();
        y = args[1]->IntegerValue();
    }
    Persistent<Object>jsInstance = Persistent<Object>::New(objectTemplate->InstanceTemplate()->NewInstance());
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    JMXPoint *point = [[JMXPoint pointWithNSPoint:NSMakePoint(x, y)] retain];
    jsInstance.MakeWeak(point, JMXPointJSDestructor);
    jsInstance->SetPointerInInternalField(0, point);
    [pool drain];    
    return handleScope.Close(jsInstance);
}
