//
//  JMXScriptInputPin.mm
//  JMX
//
//  Created by Andrea Guzzo on 2/13/12.
//  Copyright (c) 2012 Dyne.org. All rights reserved.
//

#import "JMXScriptInputPin.h"
#import "JMXScript.h"
#import "JMXScriptEntity.h"

using namespace v8;

@implementation JMXScriptInputPin

@synthesize function;

static v8::Persistent<FunctionTemplate> objectTemplate;

+ (v8::Persistent<FunctionTemplate>)jsObjectTemplate
{
    //v8::Locker lock;
    if (!objectTemplate.IsEmpty())
        return objectTemplate;
    objectTemplate = Persistent<FunctionTemplate>::New(FunctionTemplate::New());
    objectTemplate->Inherit([super jsObjectTemplate]);
    objectTemplate->SetClassName(String::New("InputPin"));
    v8::Handle<ObjectTemplate> classProto = objectTemplate->PrototypeTemplate();
    //classProto->Set("connect", FunctionTemplate::New(connect));
    // set instance methods
    v8::Handle<ObjectTemplate> instanceTemplate = objectTemplate->InstanceTemplate();
    instanceTemplate->SetInternalFieldCount(1);
    // Add accessors for each of the fields of the entity.
    NSDebug(@"JMXInputPin objectTemplate created");
    return objectTemplate;
}

void JMXInputPinJSDestructor(v8::Persistent<Value> object, void *parameter)
{
    v8::HandleScope handle_scope;
    v8::Locker lock;
    JMXScriptInputPin *obj = static_cast<JMXScriptInputPin *>(parameter);
    //NSLog(@"V8 WeakCallback (JMXInputPin) called %@", obj);
    [obj release];
    if (!object.IsEmpty()) {
        object.ClearWeak();
        object.Dispose();
        object.Clear();
    }
}

v8::Handle<v8::Value> JMXInputPinJSConstructor(const v8::Arguments& args)
{
    HandleScope handleScope;
    //v8::Locker locker;
    v8::Persistent<FunctionTemplate> objectTemplate = [JMXScriptInputPin jsObjectTemplate];
    NSString *label = @"inputPin";
    NSString *typeName = @"void";
    int argsCount = args.Length();
    if (argsCount >= 1) {
        String::Utf8Value str(args[0]->ToString());
        label = [NSString stringWithUTF8String:*str];
    }
    if (argsCount >= 2) {
        String::Utf8Value str(args[1]->ToString());
        typeName = [[NSString stringWithUTF8String:*str] lowercaseString];
    }
    Persistent<Object>jsInstance = Persistent<Object>::New(objectTemplate->InstanceTemplate()->NewInstance());
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    JMXPinType type = kJMXVoidPin;
    if ([typeName isEqualToString:@"string"]) {
        type = kJMXStringPin;
    } else if ([typeName isEqualToString:@"text"]) {
        type = kJMXTextPin;
    } else if ([typeName isEqualToString:@"code"]) {
        type = kJMXCodePin;
    } else if ([typeName isEqualToString:@"number"]) {
        type = kJMXNumberPin;
    } else if ([typeName isEqualToString:@"point"]) {
        type = kJMXPointPin;
    } else if ([typeName isEqualToString:@"size"]) {
        type = kJMXSizePin;
    } else if ([typeName isEqualToString:@"color"]) {
        type = kJMXColorPin;
    } else if ([typeName isEqualToString:@"image"]) {
        type = kJMXImagePin;
    } else if ([typeName isEqualToString:@"boolean"]) {
        type = kJMXBooleanPin;
    } else if ([typeName isEqualToString:@"void"]) {
        type = kJMXVoidPin;
    } else {
        NSLog(@"Invalid pin type %@", typeName);
        [pool drain];
        return Undefined();
    }
    v8::Local<Context> globalContext = v8::Context::GetCalling();
    JMXScript *ctx = [JMXScript getContext:globalContext];
    if (ctx && ctx.scriptEntity) {
        JMXInputPin *pin = [ctx.scriptEntity registerJSInputPinWithLabel:label
                                                                    type:type
                                                                function:Persistent<Function>::New(Handle<Function>::Cast(args[2]))];

        jsInstance.MakeWeak(pin, JMXInputPinJSDestructor);
        jsInstance->SetPointerInInternalField(0, pin);
    }
    [pool drain];    
    return handleScope.Close(jsInstance);
}

+ (void)jsRegisterClassMethods:(v8::Handle<v8::FunctionTemplate>)constructor
{
}

@end
