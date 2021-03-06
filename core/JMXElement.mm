//
//  JMXElement.mm
//  JMX
//
//  Created by xant on 1/1/11.
//  Copyright 2011 Dyne.org. All rights reserved.
//

#define __JMXV8__
#import "JMXElement.h"
#import "JMXAttribute.h"
#import "JMXContext.h"
#import "JMXGraph.h"

JMXV8_EXPORT_NODE_CLASS(JMXElement);

@implementation JMXElement

@synthesize uid, jsId;

- (void)addElementAttributes
{
    if (!idLock)
        idLock = [[NSLock alloc] init];
    if (!uid) {
        uid = [[NSString stringWithFormat:@"%8lx", [self hash]] retain];
        [self addAttribute:[JMXAttribute attributeWithName:@"uid"
                                               stringValue:uid]];
    }
    if (!jsId) {
        jsId = [[NSString stringWithFormat:@"%@", uid ] retain];
        [self addAttribute:[JMXAttribute attributeWithName:@"id"
                                               stringValue:jsId]];
    } else {
        // TODO - should never happen ... but handle the error condition if it does
    }
}

- (id)initWithName:(NSString *)name
{
    self = [super initWithName:name URI:@"http://jmxapp.org"];
    if (self)
        [self addElementAttributes];
    return self;
}

- (id)jmxInit
{
    v8::Unlocker unlocker;
    self = [super initWithKind:NSXMLElementKind];
    if (self) {
        //self = [super initWithName:self.name ? self.name : @"JMXElement" URI:@"http://jmxapp.org"];
        //[[[[JMXContext sharedContext] dom] rootElement] addChild:self];
        if (!self.name || [self.name isEqualToString:@""])
            self.name = @"JMXElement";
        if (!self.URI || [self.URI isEqualToString:@""])
            self.URI = @"http://jmxapp.org";
    }
    return self;
}

- (void)dealloc
{
    [self removeAttributeForName:@"uid"];
    [self removeAttributeForName:@"id"];
    [uid release];
    [jsId release];
    [idLock release];
    [super dealloc];
}

- (NSString *)jsId
{
    [idLock lock];
    NSString *theId = [jsId retain];
    [idLock unlock];
    return [theId autorelease];
}

- (void)setJsId:(NSString *)anId
{
    if (!anId)
        return;
    [idLock lock];
    [jsId release];
    jsId = [anId copy];
    // TODO - check if the ID already exists
    // we could use document.getElementByID() ... but that could affect performances 
    JMXAttribute *attr = (JMXAttribute *)[self attributeForName:@"id"];
    [attr setStringValue:jsId];
    [idLock unlock];
}

- (NSXMLNode *)childAtIndex:(NSUInteger)index
{
    if (self.childCount > index)
        return [self.children objectAtIndex:index];
    return nil;
}

#pragma mark V8

using namespace v8;

static v8::Handle<Value> GetId(Local<String> name, const AccessorInfo& info)
{   
    //v8::Locker lock;
    HandleScope handleScope;
    JMXElement *element = (JMXElement *)info.Holder()->GetPointerFromInternalField(0);
    if (element)
        return handleScope.Close(v8::String::New([element.jsId UTF8String]));
    return handleScope.Close(Undefined());
}

void SetId(Local<String> name, Local<Value> value, const AccessorInfo& info)
{   
    //v8::Locker lock;
    HandleScope handleScope;
    JMXElement *element = (JMXElement *)info.Holder()->GetPointerFromInternalField(0);
    if (!value->IsString()) {
        NSLog(@"Bad parameter (not string) passed to JMXCData.SetData()");
        return;
    }
    String::Utf8Value str(value->ToString());
    Local<Value> ret;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    element.jsId = [NSString stringWithUTF8String:*str];
    [pool drain];
}

static v8::Handle<Value> GetStyle(Local<String> name, const AccessorInfo& info)
{   
    //v8::Locker lock;
    HandleScope handleScope;
    Local<String> internalName = String::New("_style");
    v8::Handle<Value> ret;
    v8::Handle<Object> holder = info.Holder();
    if (holder->IsObject()) {
        if (!holder->Has(internalName)) {
            ret = Object::New();
            info.Holder()->Set(internalName, ret);
        } else {
            ret = info.Holder()->Get(internalName);
        }
    }
    return handleScope.Close(ret);
}

static void SetStyle(Local<String> name, Local<Value> value, const AccessorInfo& info)
{   
    //v8::Locker lock;
    HandleScope handleScope;
    info.Holder()->Set(name, value);
}

+ (v8::Persistent<v8::FunctionTemplate>)jsObjectTemplate
{
    //v8::Locker lock;
    if (!objectTemplate.IsEmpty())
        return objectTemplate;
    objectTemplate = v8::Persistent<FunctionTemplate>::New(FunctionTemplate::New());
    objectTemplate->Inherit([super jsObjectTemplate]);
    objectTemplate->SetClassName(String::New("Element"));
    v8::Handle<ObjectTemplate> classProto = objectTemplate->PrototypeTemplate();
    
    v8::Handle<ObjectTemplate> instanceTemplate = objectTemplate->InstanceTemplate();
    instanceTemplate->SetInternalFieldCount(1);
    
    // Add accessors for each of the fields of the entity.
    instanceTemplate->SetAccessor(String::NewSymbol("uid"), GetStringProperty, SetStringProperty);
    instanceTemplate->SetAccessor(String::NewSymbol("id"), GetId, SetId);
    instanceTemplate->SetAccessor(String::NewSymbol("style"), GetStyle, SetStyle);

    NSDebug(@"JMXElement objectTemplate created");
    return objectTemplate;
}

+ (void)jsRegisterClassMethods:(v8::Handle<v8::FunctionTemplate>)constructor
{
    return [super jsRegisterClassMethods:constructor];
}

- (void)appendToNode:(NSXMLElement *)parentNode
{
    [parentNode addChild:self];
}

- (id)copyWithZone:(NSZone *)zone
{
    // we don't want copies, but we want to use such objects as keys of a dictionary
    // so we still need to conform to the 'copying' protocol,
    // but since we are to be considered 'immutable' we can adopt what described at the end of :
    // http://developer.apple.com/mac/library/documentation/cocoa/conceptual/MemoryMgmt/Articles/mmImplementCopy.html
    return [self retain];
}

@end
