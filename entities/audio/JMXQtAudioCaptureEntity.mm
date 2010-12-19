//
//  JMXQtAudioCaptureLayer.m
//  JMX
//
//  Created by xant on 9/15/10.
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

#include <CoreAudio/CoreAudioTypes.h>
#import <QTKit/QTKit.h>
#define __JMXV8__
#import "JMXQtAudioCaptureEntity.h"
#include "JMXScript.h"

JMXV8_EXPORT_ENTITY_CLASS(JMXQtAudioCaptureEntity);

#pragma mark -
#pragma mark Converter Callback

typedef struct CallbackContext_t {
	AudioBufferList * theConversionBuffer;
	bool wait;
    UInt32 offset;
} CallbackContext;

static OSStatus _FillComplexBufferProc (
                                        AudioConverterRef aConveter,
                                        UInt32 * ioNumberDataPackets,
                                        AudioBufferList * ioData,
                                        AudioStreamPacketDescription ** outDataPacketDescription,
                                        void * inUserData
                                        )
{
	CallbackContext * ctx = (CallbackContext *)inUserData;
    AudioBufferList *bufferList = ctx->theConversionBuffer;
	int i;
    for (i = 0; i < bufferList->mNumberBuffers; i++) {
        //ioData->mBuffers[i].mData = bufferList->mBuffers[i].mData;
        //ioData->mBuffers[i].mDataByteSize = bufferList->mBuffers[i].mDataByteSize;
        memcpy(&ioData->mBuffers[i], &bufferList->mBuffers[i], sizeof(AudioBuffer));
    }
    return noErr;
}

#pragma mark -
#pragma mark JMXQtAudioGrabber
/*
 * QTKit Bridge
 */

@interface JMXQtAudioGrabber : QTCaptureDecompressedAudioOutput
{
    QTCaptureDeviceInput         *input;
    QTCaptureMovieFileOutput     *captureOutput;
    QTCaptureSession             *session;
    QTCaptureDevice              *device;
}

- (id)init;
- (void)startCapture:(JMXQtAudioCaptureEntity *)controller;
- (void)stopCapture;
@end

@implementation JMXQtAudioGrabber : QTCaptureDecompressedAudioOutput

- (id)init
{
    self = [super init];
    if( self ) {

    }
    return self;
}

- (void)dealloc
{
    [self stopCapture];
    
    [super dealloc];
}

- (void)startCapture:(JMXQtAudioCaptureEntity *)controller
{
    NSLog(@"QTCapture opened");
    bool ret = false;
    
    NSError *o_returnedError;
    @synchronized(self) {
        // XXX - supports only the default audio input for now
        device = controller.captureDevice;
        if( !device )
        {
            NSLog(@"Can't find any Video device");
            goto error;
        }
        [device retain];
        
        if( ![device open: &o_returnedError] )
        {
            NSLog(@"Unable to open the capture device (%i)", [o_returnedError code]);
            goto error;
        }
        
        if( [device isInUseByAnotherApplication] == YES )
        {
            NSLog(@"default capture device is exclusively in use by another application");
            goto error;
        }
        
        input = [[QTCaptureDeviceInput alloc] initWithDevice: device];
        if( !input )
        {
            NSLog(@"can't create a valid capture input facility");
            goto error;
        }
        
        
        session = [[QTCaptureSession alloc] init];
        
        ret = [session addInput:input error: &o_returnedError];
        if( !ret )
        {
            NSLog(@"default audio capture device could not be added to capture session (%i)", [o_returnedError code]);
            goto error;
        }
        
        ret = [session addOutput:self error: &o_returnedError];
        if( !ret )
        {
            NSLog(@"output could not be added to capture session (%i)", [o_returnedError code]);
            goto error;
        }
        
        [session startRunning]; // start the capture session
        NSLog(@"audio device ready!");
        
        [self setDelegate:controller];
        return;
    error:
        //[= exitQTKitOnThread];
        [input release];
    }
}

- (void)stopCapture
{
    @synchronized(self) {
        if (session) {
            [session stopRunning];
            if (input) {
                [session removeInput:input];
                [input release];
                input = NULL;
            }
            [session removeOutput:self];
            [session release];
            session = nil;
        }
        /*
         if (output) {
         [output release];
         output = NULL;
         }
         */
        if (device) {
            if ([device isOpen])
                [device close];
            [device release];
            device = NULL;
        }
    }
}

@end

#pragma mark -
#pragma mark JMXQtAudioCaptureLayer

@implementation JMXQtAudioCaptureEntity : JMXEntity

@synthesize captureDevice;

+ (NSArray *)availableDevices
{
    NSMutableArray *devicesList = [[NSMutableArray alloc] init];
    NSArray *availableDevices = [QTCaptureDevice inputDevicesWithMediaType:QTMediaTypeSound];
    for (QTCaptureDevice *dev in availableDevices) 
        [devicesList addObject:[dev uniqueID]];
    return [availableDevices autorelease];
}

- (id)init
{
    self = [super init];
    if (self) {
        grabber = [[JMXQtAudioGrabber alloc] init];
        outputPin = [self registerOutputPin:@"audio" withType:kJMXAudioPin];
        // Set the client format to 32bit float data
        // Maintain the channel count and sample rate of the original source format
        outputFormat.mSampleRate = 44100;
        outputFormat.mChannelsPerFrame = 2  ;
        outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mBytesPerPacket = 4 * outputFormat.mChannelsPerFrame;
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = 4 * outputFormat.mChannelsPerFrame;
        outputFormat.mBitsPerChannel = 32;
        deviceSelect = [self registerInputPin:@"device" 
                                     withType:kJMXStringPin 
                                  andSelector:@"setDevice:"
                                allowedValues:[JMXQtAudioCaptureEntity availableDevices]
                                 initialValue:[[QTCaptureDevice defaultInputDeviceWithMediaType:QTMediaTypeSound] uniqueID]];
    } else {
        [self dealloc];
        return nil;
    }
    return self;
}

- (void)dealloc
{
	if (grabber) {
		[grabber release];
        grabber = nil;
    }
	[super dealloc];
}

- (void)setDevice:(NSString *)uniqueID
{
    QTCaptureDevice *dev = [QTCaptureDevice deviceWithUniqueID:uniqueID];
    if (dev)
        captureDevice = dev;
    if (active) {
        [grabber stopCapture];
        [grabber startCapture:self];
    }
        
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput didOutputAudioSampleBuffer:(QTSampleBuffer *)sampleBuffer
                                                             fromConnection:(QTCaptureConnection *)connection
{
    //@synchronized(outputPin) {
        AudioStreamBasicDescription format;
       // AudioBufferList buffer;
        if (currentBuffer)
            [currentBuffer release];
        [[[sampleBuffer formatDescription] attributeForKey:QTFormatDescriptionAudioStreamBasicDescriptionAttribute] getValue:&format];
        AudioBufferList *buffer = [sampleBuffer audioBufferListWithOptions:(QTSampleBufferAudioBufferListOptions)QTSampleBufferAudioBufferListOptionAssure16ByteAlignment];
        
        // convert the sample to the internal format
        AudioStreamBasicDescription inputDescription = format;
        AudioStreamBasicDescription outputDescription = outputFormat;
        if (!converter) { // create on first use
            if ( noErr != AudioConverterNew ( &inputDescription, &outputDescription, &converter )) {
                converter = NULL; // just in case
                // TODO - Error Messages
                return;
            } else {
                
                UInt32 primeMethod = kConverterPrimeMethod_None;
                UInt32 srcQuality = kAudioConverterQuality_Max;
                (void) AudioConverterSetProperty ( converter, kAudioConverterPrimeMethod, sizeof(UInt32), &primeMethod );
                (void) AudioConverterSetProperty ( converter, kAudioConverterSampleRateConverterQuality, sizeof(UInt32), &srcQuality );
            }
        } else {
            // TODO - check if inputdescription or outputdescription have changed and, 
            //        if that's the case, reset the converter accordingly
        }
        OSStatus err = noErr;
        CallbackContext callbackContext;
        UInt32 framesRead = buffer->mBuffers[0].mDataByteSize / format.mBytesPerFrame / buffer->mBuffers[0].mNumberChannels;
        AudioBufferList *outputBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
        outputBufferList->mNumberBuffers = 1;
        outputBufferList->mBuffers[0].mDataByteSize = outputDescription.mBytesPerFrame * outputDescription.mChannelsPerFrame * framesRead;
        outputBufferList->mBuffers[0].mNumberChannels = outputDescription.mChannelsPerFrame;
        outputBufferList->mBuffers[0].mData = malloc(outputBufferList->mBuffers[0].mDataByteSize);
        callbackContext.theConversionBuffer = buffer;
        //callbackContext.wait = NO; // XXX (actually unused)
        if (inputDescription.mSampleRate == outputDescription.mSampleRate &&
            inputDescription.mBytesPerFrame == outputDescription.mBytesPerFrame) {
            err = AudioConverterConvertBuffer (
                                               converter,
                                               buffer->mBuffers[0].mDataByteSize,
                                               buffer->mBuffers[0].mData,
                                               &outputBufferList->mBuffers[0].mDataByteSize,
                                               outputBufferList->mBuffers[0].mData
                                               );
        } else {
            err = AudioConverterFillComplexBuffer ( converter, _FillComplexBufferProc, &callbackContext, &framesRead, outputBufferList, NULL );
        }
        if (err == noErr)
            currentBuffer = [[JMXAudioBuffer audioBufferWithCoreAudioBufferList:outputBufferList andFormat:&outputFormat copy:NO freeOnRelease:YES] retain];    

        if (currentBuffer)
            [outputPin deliverData:currentBuffer fromSender:self];
        [self outputDefaultSignals:CVGetCurrentHostTime()];
    //}
}

- (void)start
{
    // we don't want the extra thread (QTKit spawns already its own), 
    // so it's useless to call our super here
	//[super start];
	[grabber startCapture:self];
}

- (void)stop
{
	//[super stop];
	[grabber stopCapture];
}

#pragma mark -
#pragma mark NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder
{
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    return self;
}

- (void)tick:(uint64_t)timeStamp
{
    [self outputDefaultSignals:timeStamp];
}

#pragma mark V8
using namespace v8;

- (void)jsInit:(NSValue *)argsValue
{
    v8::Arguments *args = (v8::Arguments *)[argsValue pointerValue];
    if (args->Length()) {
        v8::Handle<Value> arg = (*args)[0];
        v8::String::Utf8Value value(arg);
        if (*value)
            [self setDevice:[NSString stringWithUTF8String:*value]];
    }
}

static v8::Handle<Value>start(const Arguments& args)
{
    HandleScope handleScope;
    JMXQtAudioCaptureEntity *entity = (JMXQtAudioCaptureEntity *)args.Holder()->GetPointerFromInternalField(0);
    [entity start];
    return v8::Undefined();
}

static v8::Handle<Value>stop(const Arguments& args)
{
    HandleScope handleScope;
    JMXQtAudioCaptureEntity *entity = (JMXQtAudioCaptureEntity *)args.Holder()->GetPointerFromInternalField(0);
    [entity stop];
    return v8::Undefined();
}

// class method to get a list with all available devices
static v8::Handle<Value>availableDevices(const Arguments& args)
{
    HandleScope handleScope;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *availableDevices = [JMXQtAudioCaptureEntity availableDevices];
    v8::Handle<Array> list = Array::New([availableDevices count]);
    for (int i = 0; i < [availableDevices count]; i++) {
        list->Set(i, String::New([[availableDevices objectAtIndex:i] UTF8String]));
    }
    [pool drain];
    return handleScope.Close(list);
}

+ (v8::Persistent<v8::FunctionTemplate>)jsClassTemplate
{
    HandleScope handleScope;
    v8::Persistent<v8::FunctionTemplate> classTemplate = v8::Persistent<FunctionTemplate>::New(FunctionTemplate::New());
    classTemplate->Inherit([super jsClassTemplate]);
    classTemplate->SetClassName(String::New("QtAudioCapture"));
    classTemplate->InstanceTemplate()->SetInternalFieldCount(1);
    v8::Handle<ObjectTemplate> classProto = classTemplate->PrototypeTemplate();
    classProto->Set("start", FunctionTemplate::New(start));
    classProto->Set("stop", FunctionTemplate::New(stop));
    classProto->Set("avaliableDevices", FunctionTemplate::New(availableDevices));
    return classTemplate;
}

@end

