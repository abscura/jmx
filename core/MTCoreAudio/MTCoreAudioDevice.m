//
//  MTCoreAudioDevice.m
//  MTCoreAudio.framework
//
//  Created by Michael Thornburgh on Sun Dec 16 2001.
//  Copyright (c) 2001 Michael Thornburgh. All rights reserved.
//

#import "MTCoreAudioStreamDescription.h"
#import "MTCoreAudioTypes.h"
#import "MTCoreAudioStream.h"
#import "MTCoreAudioDevice.h"
#import "MTCoreAudioDevicePrivateAdditions.h"
#import "MTCoreAudioIOProcMux.h"
#import "MTDecibelTransformer.h"

// define some methods that are deprecated, but we still need to be able to call
// for backwards compatibility
@interface NSObject(MTCoreAudioDeprecatedMethods)
- (void) audioDeviceSourceDidChange:(MTCoreAudioDevice *)theDevice forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection;
@end


static NSString * _MTCoreAudioDeviceNotification = @"_MTCoreAudioDeviceNotification";
static NSString * _MTCoreAudioDeviceIDKey = @"DeviceID";
static NSString * _MTCoreAudioChannelKey = @"Channel";
static NSString * _MTCoreAudioDirectionKey = @"Direction";
static NSString * _MTCoreAudioPropertyIDKey = @"PropertyID";

NSString * MTCoreAudioHardwareDeviceListDidChangeNotification = @"MTCoreAudioHardwareDeviceListDidChangeNotification";
NSString * MTCoreAudioHardwareDefaultInputDeviceDidChangeNotification = @"MTCoreAudioHardwareDefaultInputDeviceDidChangeNotification";
NSString * MTCoreAudioHardwareDefaultOutputDeviceDidChangeNotification = @"MTCoreAudioHardwareDefaultOutputDeviceDidChangeNotification";
NSString * MTCoreAudioHardwareDefaultSystemOutputDeviceDidChangeNotification = @"MTCoreAudioHardwareDefaultSystemOutputDeviceDidChangeNotification";

static id _MTCoreAudioHardwareDelegate;


static OSStatus _MTCoreAudioHardwarePropertyListener (
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[],
#else
	AudioHardwarePropertyID inPropertyID,
#endif
	void * inClientData
)
{
	NSAutoreleasePool * pool;
	SEL delegateSelector;
	NSString * notificationName = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    int i;
    
    for (i = 0; i < inNumberAddresses; i++) {
    switch(inAddresses[i].mSelector)
#else
	switch (inPropertyID)
#endif
	{
		case kAudioHardwarePropertyDevices:
			delegateSelector = @selector(audioHardwareDeviceListDidChange);
			notificationName = MTCoreAudioHardwareDeviceListDidChangeNotification;
			break;
		case kAudioHardwarePropertyDefaultInputDevice:
			delegateSelector = @selector(audioHardwareDefaultInputDeviceDidChange);
			notificationName = MTCoreAudioHardwareDefaultInputDeviceDidChangeNotification;
			break;
		case kAudioHardwarePropertyDefaultOutputDevice:
			delegateSelector = @selector(audioHardwareDefaultOutputDeviceDidChange);
			notificationName = MTCoreAudioHardwareDefaultOutputDeviceDidChangeNotification;
			break;
		case kAudioHardwarePropertyDefaultSystemOutputDevice:
			delegateSelector = @selector(audioHardwareDefaultSystemOutputDeviceDidChange);
			notificationName = MTCoreAudioHardwareDefaultSystemOutputDeviceDidChangeNotification;
			break;
		
		default:
			return 0; // unknown notification, do nothing
	}
	
	pool = [[NSAutoreleasePool alloc] init];
	
	if ( _MTCoreAudioHardwareDelegate )
	{
		if ([_MTCoreAudioHardwareDelegate respondsToSelector:delegateSelector])
			[_MTCoreAudioHardwareDelegate performSelector:delegateSelector];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:nil];

	[pool release];
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    }
#endif
	return 0;
}

static OSStatus _MTCoreAudioDevicePropertyListener (
                                                    
	AudioDeviceID inDevice,
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    //AudioObjectID inObjectID,
    UInt32 inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[],
#else
    UInt32 inChannel,
    Boolean isInput,
	AudioDevicePropertyID inPropertyID,
#endif
    void * inClientData
)
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    int i;
    for (i = 0; i < inNumberAddresses; i++) {
        NSMutableDictionary * notificationUserInfo = [NSMutableDictionary dictionaryWithCapacity:4];
        
        [notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inDevice] forKey:_MTCoreAudioDeviceIDKey];
        [notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inAddresses[i].mElement] forKey:_MTCoreAudioChannelKey]; // XXX
        [notificationUserInfo setObject:[NSNumber numberWithBool:inAddresses[i].mScope ==  kAudioDevicePropertyScopeInput ? YES : NO] forKey:_MTCoreAudioDirectionKey];
        [notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inAddresses[i].mSelector] forKey:_MTCoreAudioPropertyIDKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:_MTCoreAudioDeviceNotification object:nil userInfo:notificationUserInfo];
    }
#else
    NSMutableDictionary * notificationUserInfo = [NSMutableDictionary dictionaryWithCapacity:4];
    
	[notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inDevice] forKey:_MTCoreAudioDeviceIDKey];
    [notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inChannel] forKey:_MTCoreAudioChannelKey];
	[notificationUserInfo setObject:[NSNumber numberWithBool:isInput] forKey:_MTCoreAudioDirectionKey];
	[notificationUserInfo setObject:[NSNumber numberWithUnsignedLong:inPropertyID] forKey:_MTCoreAudioPropertyIDKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:_MTCoreAudioDeviceNotification object:nil userInfo:notificationUserInfo];
#endif
    	
	[pool release];
	
	return 0;
}

static NSString * _DataSourceNameForID ( AudioDeviceID theDeviceID, MTCoreAudioDirection theDirection, UInt32 theChannel, UInt32 theDataSourceID )
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioValueTranslation theTranslation;
	CFStringRef theCFString;
	NSString * rv;
	
	theTranslation.mInputData = &theDataSourceID;
	theTranslation.mInputDataSize = sizeof(UInt32);
	theTranslation.mOutputData = &theCFString;
	theTranslation.mOutputDataSize = sizeof ( CFStringRef );
	theSize = sizeof(AudioValueTranslation);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    struct AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDataSourceNameForIDCFString;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    theStatus = AudioObjectGetPropertyData(theDeviceID, &propertyAddress, 0, NULL, &theSize, &theTranslation);
#else
    theStatus = AudioDeviceGetProperty ( theDeviceID, theChannel, theDirection, kAudioDevicePropertyDataSourceNameForIDCFString, &theSize, &theTranslation );
#endif
	if (( theStatus == 0 ) && theCFString )
	{
		rv = [NSString stringWithString:(NSString *)theCFString];
		CFRelease ( theCFString );
		return rv;
	}

	return nil;
}

static NSString * _ClockSourceNameForID ( AudioDeviceID theDeviceID, MTCoreAudioDirection theDirection, UInt32 theChannel, UInt32 theClockSourceID )
{
	OSStatus theStatus;
	NSString * rv;
    CFStringRef theCFString;
    UInt32 theSize;

    AudioValueTranslation theTranslation;
	theTranslation.mInputData = &theClockSourceID;
	theTranslation.mInputDataSize = sizeof(UInt32);
	theTranslation.mOutputData = &theCFString;
	theTranslation.mOutputDataSize = sizeof ( CFStringRef );
    theSize = sizeof(AudioValueTranslation);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    struct AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyClockSourceNameForIDCFString;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    theStatus = AudioObjectGetPropertyData( theDeviceID, &propertyAddress, 0, NULL, &theSize, &theTranslation );
#else
	theStatus = AudioDeviceGetProperty ( theDeviceID, theChannel, theDirection, kAudioDevicePropertyClockSourceNameForIDCFString, &theSize, &theTranslation );
#endif
	if (( theStatus == 0 ) && theCFString )
	{
		rv = [NSString stringWithString:(NSString *)theCFString];
		CFRelease ( theCFString );
		return rv;
	}

	return nil;
}



@implementation MTCoreAudioDevice

// startup stuff
+ (void) initialize
{
	static Boolean initted = NO;
	
	if(!initted)
	{
		initted = YES;
		_MTCoreAudioHardwareDelegate = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
        struct AudioObjectPropertyAddress propertyAddress;
        propertyAddress.mSelector = kAudioObjectPropertySelectorWildcard;
        propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
        propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
        OSStatus theStatus = AudioObjectAddPropertyListener(kAudioObjectSystemObject, 
                                                       &propertyAddress, 
                                                       _MTCoreAudioHardwarePropertyListener, 
                                                       NULL);
        if (theStatus != 0) {
            // TODO - error messages
        }
#else
		AudioHardwareAddPropertyListener ( kAudioPropertyWildcardPropertyID, _MTCoreAudioHardwarePropertyListener, NULL );
#endif
		[MTDecibelTransformer class]; // will send +initialize if needed
	}
}

- (void) _registerForNotifications
{
	if ( ! isRegisteredForNotifications )
	{
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
        struct AudioObjectPropertyAddress propertyAddress;
        propertyAddress.mSelector = kAudioObjectPropertySelectorWildcard;
        propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
        propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
        OSStatus theStatus = AudioObjectAddPropertyListener(myDevice, 
                                                            &propertyAddress, 
                                                            _MTCoreAudioDevicePropertyListener, 
                                                            NULL);
        if (theStatus != 0) {
            // TODO - error messages
        }   
#else
		AudioDeviceAddPropertyListener ( myDevice, kAudioPropertyWildcardChannel, kAudioPropertyWildcardSection, kAudioPropertyWildcardPropertyID, _MTCoreAudioDevicePropertyListener, NULL );
#endif
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_dispatchDeviceNotification:) name:_MTCoreAudioDeviceNotification object:nil];
		isRegisteredForNotifications = YES;
	}
}

+ (NSArray *) allDevices
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray * theArray;
	UInt32 theSize;
	OSStatus theStatus;
	int numDevices;
	int x;
	AudioDeviceID * deviceList;
	MTCoreAudioDevice * tmpDevice;
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwarePropertyDevices;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    theStatus = AudioObjectGetPropertyDataSize( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioHardwareGetPropertyInfo ( kAudioHardwarePropertyDevices, &theSize, NULL );
#endif
	if (theStatus != 0)
		return nil;
	numDevices = theSize / sizeof(AudioDeviceID);
	deviceList = (AudioDeviceID *) malloc ( theSize );
	if (deviceList == NULL) {
		NSLog(@"Can't obtain device list size");
        return nil;
    }
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize, deviceList );
#else
	theStatus = AudioHardwareGetProperty ( kAudioHardwarePropertyDevices, &theSize, deviceList );
#endif
	if (theStatus != 0)
	{
        NSLog(@"Can't obtain device list");
		free(deviceList);
		return nil;
	}
	
	theArray = [[NSMutableArray alloc] initWithCapacity:numDevices];
	for ( x = 0; x < numDevices; x++ )
	{
		tmpDevice = [[[self class] alloc] initWithDeviceID:deviceList[x]];
		[theArray addObject:tmpDevice];
		[tmpDevice release];
	}
	free(deviceList);
	
	[theArray sortUsingSelector:@selector(_compare:)];
	
	[pool release];

	[theArray autorelease];
	return theArray;
}

+ (NSArray *)		allDevicesByRelation
{
	NSMutableSet * coveredDeviceSet = [NSMutableSet set];
	NSEnumerator * deviceEnumerator = [[[self class] allDevices] objectEnumerator];
	MTCoreAudioDevice * whichDevice;
	NSArray * relatedDevices;
	NSMutableArray * rv = [NSMutableArray array];
	
	while ( whichDevice = [deviceEnumerator nextObject] )
	{
		if ( ! [coveredDeviceSet containsObject:whichDevice] )
		{
			relatedDevices = [whichDevice relatedDevices];
			[rv addObject:relatedDevices];
			[coveredDeviceSet addObjectsFromArray:relatedDevices];
		}
	}
	return rv;
}

+ (NSArray *) devicesWithName:(NSString *)theName havingStreamsForDirection:(MTCoreAudioDirection)theDirection
{
	NSEnumerator * deviceEnumerator = [[self allDevices] objectEnumerator];
	NSMutableArray * rv = [NSMutableArray array];
	MTCoreAudioDevice * aDevice;
	
	while ( aDevice = [deviceEnumerator nextObject] )
	{
		if ( [theName isEqual:[aDevice deviceName]] && ( [aDevice channelsForDirection:theDirection] > 0 ))
		{
			[rv addObject:aDevice];
		}
	}
	return rv;
}

+ (MTCoreAudioDevice *) deviceWithID:(AudioDeviceID)theID
{
	return [[[[self class] alloc] initWithDeviceID:theID] autorelease];
}

+ (MTCoreAudioDevice *) deviceWithUID:(NSString *)theUID
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioValueTranslation theTranslation;
	CFStringRef theCFString;
	unichar * theCharacters;
	AudioDeviceID theID;
	MTCoreAudioDevice * rv = nil;
	
	theCharacters = (unichar *) malloc ( sizeof(unichar) * [theUID length] );
	[theUID getCharacters:theCharacters];
	
	theCFString = CFStringCreateWithCharactersNoCopy ( NULL, theCharacters, [theUID length], kCFAllocatorNull );
	
	theTranslation.mInputData = &theCFString;
	theTranslation.mInputDataSize = sizeof(CFStringRef);
	theTranslation.mOutputData = &theID;
	theTranslation.mOutputDataSize = sizeof(AudioDeviceID);
	theSize = sizeof(AudioValueTranslation);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwarePropertyDeviceForUID;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    theStatus = AudioObjectGetPropertyDataSize( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize );
    theStatus = AudioObjectGetPropertyData( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize, &theTranslation );
#else
	theStatus = AudioHardwareGetProperty ( kAudioHardwarePropertyDeviceForUID, &theSize, &theTranslation );
#endif
	CFRelease ( theCFString );
	free ( theCharacters );
	if (theStatus == 0)
		rv = [[self class] deviceWithID:theID];
	if ( [theUID isEqual:[rv deviceUID]] )
		return rv;
	return nil;
}

+ (MTCoreAudioDevice *) _defaultDevice:(int)whichDevice
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioDeviceID theID;
	
	theSize = sizeof(AudioDeviceID);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = whichDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = kAudioObjectPropertyElementMaster;
    theStatus = AudioObjectGetPropertyDataSize( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize );
    theStatus = AudioObjectGetPropertyData( kAudioObjectSystemObject, &propertyAddress, 0, NULL, &theSize, &theID );
#else
	theStatus = AudioHardwareGetProperty ( whichDevice, &theSize, &theID );
#endif
	if (theStatus == 0)
		return [[self class] deviceWithID:theID];
    NSLog(@"Can't init defaultDevice %d (%d)", whichDevice, theStatus);
	return nil;
}

+ (MTCoreAudioDevice *) defaultInputDevice
{
	return [[self class] _defaultDevice:kAudioHardwarePropertyDefaultInputDevice];
}

+ (MTCoreAudioDevice *) defaultOutputDevice
{
	return [[self class] _defaultDevice:kAudioHardwarePropertyDefaultOutputDevice];
}

+ (MTCoreAudioDevice *) defaultSystemOutputDevice
{
	return [[self class] _defaultDevice:kAudioHardwarePropertyDefaultSystemOutputDevice];
}

- init // head off -new and bad usage
{
	[self dealloc];
	return nil;
}

- (MTCoreAudioDevice *) initWithDeviceID:(AudioDeviceID)theID
{
	[super init];
	myStreams[0] = myStreams[1] = nil;
	streamsDirty[0] = streamsDirty[1] = true;
	myDevice = theID;
	myDelegate = nil;
	myIOProc = NULL;
	return self;
}

- (MTCoreAudioDevice *) clone
{
	return [[self class] deviceWithID:[self deviceID]];
}

- (NSArray *) relatedDevices
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 numDevices;
	AudioDeviceID * deviceList = NULL;
	MTCoreAudioDevice * tmpDevice;
	NSMutableArray * rv = [NSMutableArray arrayWithObject:self];
	UInt32 x;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioObjectPropertyOwnedObjects;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    AudioClassID deviceClass = kAudioDeviceClassID;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, sizeof(deviceClass), &deviceClass, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, 0, kAudioDevicePropertyRelatedDevices, &theSize, NULL );
#endif
    if (theStatus != 0)
		goto finish;
	deviceList = (AudioDeviceID *) malloc ( theSize );
	numDevices = theSize / sizeof(AudioDeviceID);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, sizeof(deviceClass), &deviceClass, &theSize, deviceList );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, 0, kAudioDevicePropertyRelatedDevices, &theSize, deviceList );
#endif
	if (theStatus != 0)
	{
		goto finish;
	}

	for ( x = 0; x < numDevices; x++ )
	{
		tmpDevice = [[self class] deviceWithID:deviceList[x]];
		if ( ! [self isEqual:tmpDevice] )
		{
			[rv addObject:tmpDevice];
		}
	}

	finish:
	
	if ( deviceList )
		free(deviceList);
	
	[rv sortUsingSelector:@selector(_compare:)];
	
	return rv;
}

- (AudioDeviceID) deviceID
{
	return myDevice;
}

- (NSString *) deviceName
{
	OSStatus theStatus;
	CFStringRef theCFString;
	NSString * rv;
	UInt32 theSize;
	
	theSize = sizeof ( CFStringRef );
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioObjectPropertyName;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theCFString);
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyDeviceNameCFString, &theSize, &theCFString );
#endif
	if ( theStatus != 0 || theCFString == NULL )
		return nil;
	rv = [NSString stringWithString:(NSString *)theCFString];
	CFRelease ( theCFString );
	return rv;
}

- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@: %p id %d> %@", [self className], self, [self deviceID], [self deviceName]];
}

- (NSString *) deviceUID
{
	OSStatus theStatus;
	CFStringRef theCFString;
	NSString * rv;
	UInt32 theSize;
	
	theSize = sizeof ( CFStringRef );
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDeviceUID;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, false, &theSize, &theCFString);
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyDeviceUID, &theSize, &theCFString );
#endif
	if ( theStatus != 0 || theCFString == NULL )
		return nil;
	rv = [NSString stringWithString:(NSString *)theCFString];
	CFRelease ( theCFString );
	return rv;
}

- (NSString *) deviceManufacturer
{
	OSStatus theStatus;
	CFStringRef theCFString;
	NSString * rv;
	UInt32 theSize;
	
	theSize = sizeof ( CFStringRef );
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioObjectPropertyManufacturer;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theCFString);
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyDeviceManufacturerCFString, &theSize, &theCFString );
#endif
	if ( theStatus != 0 || theCFString == NULL )
		return nil;
	rv = [NSString stringWithString:(NSString *)theCFString];
	CFRelease ( theCFString );
	return rv;
}

- (NSComparisonResult) _compare:(MTCoreAudioDevice *)other
{
	NSString * myName, *myUID;
	NSComparisonResult rv;
	
	myName = [self deviceName];
	if ( myName == nil )
		return NSOrderedDescending; // dead devices to the back of the bus!
	rv = [myName compare:[other deviceName]];
	if ( rv != NSOrderedSame )
		return rv;
	
	myUID = [self deviceUID];
	if ( myUID == nil )
		return NSOrderedDescending;
	return [myUID compare:[other deviceUID]];
}

- (BOOL) isEqual:(id)other
{
	if ( [other respondsToSelector:@selector(deviceID)] )
	{
		if ( [self deviceID] == [(MTCoreAudioDevice *)other deviceID] )
		{
			return YES;
		}
	}
	return NO;
}

/*
- (unsigned int)hash
{
	return (unsigned int)[self deviceID];
}
*/

+ (void) setDelegate:(id)theDelegate
{
	_MTCoreAudioHardwareDelegate = theDelegate;
}

+ (id) delegate
{
	return _MTCoreAudioHardwareDelegate;
}

+ (void) attachNotificationsToThisThread
{
	CFRunLoopRef theRunLoop = CFRunLoopGetCurrent();
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwarePropertyRunLoop;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    AudioObjectSetPropertyData(kAudioObjectSystemObject, 
                               &propertyAddress, 
                               0, 
                               NULL, 
                               sizeof(CFRunLoopRef), 
                               &theRunLoop);
#else
	AudioHardwareSetProperty ( kAudioHardwarePropertyRunLoop, sizeof(CFRunLoopRef), &theRunLoop );
#endif
}

- (void) _dispatchDeviceNotification:(NSNotification *)theNotification
{
	NSDictionary * theUserInfo = [theNotification userInfo];
	AudioDeviceID theDeviceID;
	MTCoreAudioDirection theDirection;
	UInt32 theChannel;
	AudioDevicePropertyID thePropertyID;
	BOOL hasVolumeInfoDidChangeMethod = false;
	
	theDeviceID = [[theUserInfo objectForKey:_MTCoreAudioDeviceIDKey] unsignedLongValue];

	// if (myDelegate && (theDeviceID == myDevice))
	if (theDeviceID == myDevice)
	{
		theDirection = ( [[theUserInfo objectForKey:_MTCoreAudioDirectionKey] boolValue] ) ? kMTCoreAudioDeviceRecordDirection : kMTCoreAudioDevicePlaybackDirection ;
		theChannel = [[theUserInfo objectForKey:_MTCoreAudioChannelKey] unsignedLongValue];
		thePropertyID = [[theUserInfo objectForKey:_MTCoreAudioPropertyIDKey] unsignedLongValue];
				
		switch (thePropertyID)
		{
			case kAudioDevicePropertyVolumeScalar:
			case kAudioDevicePropertyVolumeDecibels:
			case kAudioDevicePropertyMute:
			case kAudioDevicePropertyPlayThru:
				if ([myDelegate respondsToSelector:@selector(audioDeviceVolumeInfoDidChange:forChannel:forDirection:)])
					hasVolumeInfoDidChangeMethod = true;
				else
					hasVolumeInfoDidChangeMethod = false;
			break;
		}
		
		switch (thePropertyID)
		{
			case kAudioDevicePropertyDeviceIsAlive:
				if ([myDelegate respondsToSelector:@selector(audioDeviceDidDie:)])
					[myDelegate audioDeviceDidDie:self];
				break;
			case kAudioDeviceProcessorOverload:
				if ([myDelegate respondsToSelector:@selector(audioDeviceDidOverload:)])
					[myDelegate audioDeviceDidOverload:self];
				break;
			case kAudioDevicePropertyBufferFrameSize:
			case kAudioDevicePropertyUsesVariableBufferFrameSizes:
				if ([myDelegate respondsToSelector:@selector(audioDeviceBufferSizeInFramesDidChange:)])
					[myDelegate audioDeviceBufferSizeInFramesDidChange:self];
				break;
			case kAudioDevicePropertyStreams:
				if (theDirection == kMTCoreAudioDevicePlaybackDirection)
					streamsDirty[0] = true;
				else
					streamsDirty[1] = true;
				if ([myDelegate respondsToSelector:@selector(audioDeviceStreamsListDidChange:)])
					[myDelegate audioDeviceStreamsListDidChange:self];
				break;
			case kAudioDevicePropertyStreamConfiguration:
				if ([myDelegate respondsToSelector:@selector(audioDeviceChannelsByStreamDidChange:forDirection:)])
					[myDelegate audioDeviceChannelsByStreamDidChange:self forDirection:theDirection];
				break;
			case kAudioDevicePropertyStreamFormat:
				if ([myDelegate respondsToSelector:@selector(audioDeviceStreamDescriptionDidChange:forChannel:forDirection:)])
					[myDelegate audioDeviceStreamDescriptionDidChange:self forChannel:theChannel forDirection:theDirection];
				break;
			case kAudioDevicePropertyNominalSampleRate:
				if (0 == theChannel && [myDelegate respondsToSelector:@selector(audioDeviceNominalSampleRateDidChange:)])
					[myDelegate audioDeviceNominalSampleRateDidChange:self];
				break;
			case kAudioDevicePropertyAvailableNominalSampleRates:
				if (0 == theChannel && [myDelegate respondsToSelector:@selector(audioDeviceNominalSampleRatesDidChange:)])
					[myDelegate audioDeviceNominalSampleRatesDidChange:self];
				break;
			case kAudioDevicePropertyVolumeScalar:
			// case kAudioDevicePropertyVolumeDecibels:
				if ([myDelegate respondsToSelector:@selector(audioDeviceVolumeDidChange:forChannel:forDirection:)])
					[myDelegate audioDeviceVolumeDidChange:self forChannel:theChannel forDirection:theDirection];
				else if (hasVolumeInfoDidChangeMethod)
					[myDelegate audioDeviceVolumeInfoDidChange:self forChannel:theChannel forDirection:theDirection];
				break;
			case kAudioDevicePropertyMute:
				if ([myDelegate respondsToSelector:@selector(audioDeviceMuteDidChange:forChannel:forDirection:)])
					[myDelegate audioDeviceMuteDidChange:self forChannel:theChannel forDirection:theDirection];
				else if (hasVolumeInfoDidChangeMethod)
					[myDelegate audioDeviceVolumeInfoDidChange:self forChannel:theChannel forDirection:theDirection];
				break;
			case kAudioDevicePropertyPlayThru:
				if ([myDelegate respondsToSelector:@selector(audioDevicePlayThruDidChange:forChannel:forDirection:)])
					[myDelegate audioDevicePlayThruDidChange:self forChannel:theChannel forDirection:theDirection];
				else if (hasVolumeInfoDidChangeMethod)
					[myDelegate audioDeviceVolumeInfoDidChange:self forChannel:theChannel forDirection:theDirection];
				break;
			case kAudioDevicePropertyDataSource:
				if (theChannel != 0)
				{
					NSLog ( @"MTCoreAudioDevice kAudioDevicePropertyDataSource theChannel != 0" );
				}
				if ([myDelegate respondsToSelector:@selector(audioDeviceSourceDidChange:forDirection:)])
					[myDelegate audioDeviceSourceDidChange:self forDirection:theDirection];
				else if ([myDelegate respondsToSelector:@selector(audioDeviceSourceDidChange:forChannel:forDirection:)])
				{
					NSLog ( @"MTCoreAudio: delegate method -audioDeviceSourceDidChange:forChannel:forDirection: is deprecated, use audioDeviceSourceDidChange:forDirection:" );
					[myDelegate audioDeviceSourceDidChange:self forChannel:theChannel forDirection:theDirection];
				}
				break;
			case kAudioDevicePropertyClockSource:
				if ([myDelegate respondsToSelector:@selector(audioDeviceClockSourceDidChange:forChannel:forDirection:)])
					[myDelegate audioDeviceClockSourceDidChange:self forChannel:theChannel forDirection:theDirection];
				break;
			case kAudioDevicePropertyDeviceHasChanged:
				if ([myDelegate respondsToSelector:@selector(audioDeviceSomethingDidChange:)])
					[myDelegate audioDeviceSomethingDidChange:self];
				break;
				
		}
		
	}
}

- (void) setDelegate:(id)theDelegate
{
	myDelegate = theDelegate;
	if ( myDelegate )
		[self _registerForNotifications];
}

- (id) delegate
{
	return myDelegate;
}

- (Class) streamFactory
{
	return [MTCoreAudioStream class];
}

// NSArray of MTCoreAudioStreams
- (NSArray *) streamsForDirection:(MTCoreAudioDirection)theDirection
{
	AudioStreamID * theStreamIDs;
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 numStreams;
	MTCoreAudioStream * theStream;
	NSMutableArray * tmpArray;
	UInt32 x;
	int streamIndex;
	
	streamIndex = (theDirection == kMTCoreAudioDevicePlaybackDirection) ? 0 : 1 ;
	
	if ( ! streamsDirty[streamIndex] )
		return myStreams[streamIndex];
		
	if ( myStreams[streamIndex] )
		[myStreams[streamIndex] release];
	myStreams[streamIndex] = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreams;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection) ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, theDirection, kAudioDevicePropertyStreams, &theSize, NULL );
#endif
	if (theStatus != 0)
		return nil;
	theStreamIDs = (UInt32 *) malloc ( theSize );
	numStreams = theSize / sizeof(AudioStreamID);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theStreamIDs );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyStreams, &theSize, theStreamIDs );
#endif
	if (theStatus != 0)
	{
		free(theStreamIDs);
		return myStreams[streamIndex];
	}
	
	tmpArray = [[NSMutableArray alloc] initWithCapacity:numStreams];

	for ( x = 0; x < numStreams; x++ )
	{
		theStream = [[[self streamFactory] alloc] initWithStreamID:theStreamIDs[x] withOwningDevice:self];
		[tmpArray addObject:theStream];
		[theStream release]; // retained by _streams
	}
	free(theStreamIDs);
	myStreams[streamIndex] = tmpArray;
	streamsDirty[streamIndex] = false;
	return myStreams[streamIndex];

}

// backwards compatibility nastiness
- (NSString *) dataSourceForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	NSLog ( @"-[MTCoreAudioDevice dataSourceForChannel:forDirection:] is deprecated, use -dataSourceForDirection:]" );
	return [self dataSourceForDirection:theDirection];
}

- (NSArray *) dataSourcesForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	NSLog ( @"-[MTCoreAudioDevice dataSourcesForChannel:forDirection:] is deprecated, use -dataSourcesForDirection:]" );
	return [self dataSourcesForDirection:theDirection];
}

- (void) setDataSource:(NSString *)theSource forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	NSLog ( @"-[MTCoreAudioDevice setDataSource:forChannel:forDirection:] is deprecated, use -setDataSource:forDirection:]" );
	[self setDataSource:theSource forDirection:theDirection];
}

// real methods
- (NSString *) dataSourceForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 theSourceID;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDataSource;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theSourceID );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyDataSource, &theSize, &theSourceID );
#endif
	if (theStatus == 0)
		return _DataSourceNameForID ( myDevice, theDirection, 0, theSourceID );
	return nil;
}

- (NSArray *) dataSourcesForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 * theSourceIDs;
	UInt32 numSources;
	UInt32 x;
	NSMutableArray * rv = [NSMutableArray array];
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDataSources;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, theDirection, kAudioDevicePropertyDataSources, &theSize, NULL );
#endif
	if (theStatus != 0)
		return rv;
	theSourceIDs = (UInt32 *) malloc ( theSize );
	numSources = theSize / sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theSourceIDs );
#else
    theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyDataSources, &theSize, theSourceIDs );
#endif
	if (theStatus != 0)
	{
		free(theSourceIDs);
		return rv;
	}
	for ( x = 0; x < numSources; x++ )
		[rv addObject:_DataSourceNameForID ( myDevice, theDirection, 0, theSourceIDs[x] )];
	free(theSourceIDs);
	return rv;
}

- (Boolean) canSetDataSourceForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize = 0; // XXX
	Boolean rv = NO;

#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDataSource;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
    if (theSize)
        rv = YES;
#else
	theSize = sizeof(UInt32);
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, theDirection, kAudioDevicePropertyDataSource, &theSize, &rv );
#endif
	if ( 0 == theStatus )
		return rv;
	else
	{
		return NO;
	}
}

- (void) setDataSource:(NSString *)theSource forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 * theSourceIDs;
	UInt32 numSources;
	UInt32 x;
	
	if ( theSource == nil )
		return;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyDataSources;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, theDirection, kAudioDevicePropertyDataSources, &theSize, NULL );
#endif
	if (theStatus != 0)
		return;
	theSourceIDs = (UInt32 *) malloc ( theSize );
	numSources = theSize / sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theSourceIDs );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyDataSources, &theSize, theSourceIDs );
#endif
	if (theStatus != 0)
	{
		free(theSourceIDs);
		return;
	}
	
	theSize = sizeof(UInt32);
	for ( x = 0; x < numSources; x++ )
	{
		if ( [theSource compare:_DataSourceNameForID ( myDevice, theDirection, 0, theSourceIDs[x] )] == NSOrderedSame )
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
            AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theSourceIDs[x] );
#else
			AudioDeviceSetProperty ( myDevice, NULL, 0, theDirection, kAudioDevicePropertyDataSource, theSize, &theSourceIDs[x] );
#endif
	}
	free(theSourceIDs);
}

- (NSString *) clockSourceForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 theSourceID;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyClockSource;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theSourceID );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyClockSource, &theSize, &theSourceID );
#endif
	if (theStatus == 0)
		return _ClockSourceNameForID ( myDevice, theDirection, theChannel, theSourceID );
	return nil;
}

- (NSArray *)  clockSourcesForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 * theSourceIDs;
	UInt32 numSources;
	UInt32 x;
	NSMutableArray * rv;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyClockSources;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyClockSources, &theSize, NULL );
#endif
	if (theStatus != 0)
		return nil;
	theSourceIDs = (UInt32 *) malloc ( theSize );
	numSources = theSize / sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theSourceIDs );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyClockSources, &theSize, theSourceIDs );
#endif
	if (theStatus != 0)
	{
		free(theSourceIDs);
		return nil;
	}
	rv = [NSMutableArray arrayWithCapacity:numSources];
	for ( x = 0; x < numSources; x++ )
		[rv addObject:_ClockSourceNameForID ( myDevice, theDirection, theChannel, theSourceIDs[x] )];
	free(theSourceIDs);
	return rv;
}

- (void)setClockSource:(NSString *)theSource forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 * theSourceIDs;
	UInt32 numSources;
	UInt32 x;
	
	if ( theSource == nil )
		return;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyClockSources;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyClockSources, &theSize, NULL );
#endif
	if (theStatus != 0)
		return;
	theSourceIDs = (UInt32 *) malloc ( theSize );
	numSources = theSize / sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theSourceIDs );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyClockSources, &theSize, theSourceIDs );
#endif
	if (theStatus != 0)
	{
		free(theSourceIDs);
		return;
	}
	
	theSize = sizeof(UInt32);
	for ( x = 0; x < numSources; x++ )
	{
		if ( [theSource compare:_ClockSourceNameForID ( myDevice, theDirection, theChannel, theSourceIDs[x] )] == NSOrderedSame )
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
            AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theSourceIDs[x] );
#else
			AudioDeviceSetProperty ( myDevice, NULL, theChannel, theDirection, kAudioDevicePropertyClockSource, theSize, &theSourceIDs[x] );
#endif
	}
	free(theSourceIDs);
}

- (UInt32) deviceBufferSizeInFrames
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 frameSize;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &frameSize );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyBufferFrameSize, &theSize, &frameSize );
#endif
	return frameSize;
}

- (UInt32) deviceMaxVariableBufferSizeInFrames
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 frameSize;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyUsesVariableBufferFrameSizes;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &frameSize );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyUsesVariableBufferFrameSizes, &theSize, &frameSize );
#endif
	if ( noErr == theStatus )
		return frameSize;
	else
		return [self deviceBufferSizeInFrames];
}

- (UInt32) deviceMinBufferSizeInFrames
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioValueRange theRange;
	
	theSize = sizeof(AudioValueRange);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSizeRange;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theRange );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyBufferFrameSizeRange, &theSize, &theRange );
#endif
	return (UInt32) theRange.mMinimum;
}

- (UInt32) deviceMaxBufferSizeInFrames
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioValueRange theRange;
	
	theSize = sizeof(AudioValueRange);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSizeRange;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theRange );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, false, kAudioDevicePropertyBufferFrameSizeRange, &theSize, &theRange );
#endif
	return (UInt32) theRange.mMaximum;
}

- (void) setDeviceBufferSizeInFrames:(UInt32)numFrames
{
	OSStatus theStatus;
	UInt32 theSize;

	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyBufferFrameSize;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &numFrames );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, 0, false, kAudioDevicePropertyBufferFrameSize, theSize, &numFrames );
#endif
}

- (UInt32) deviceLatencyFramesForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 latencyFrames;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyLatency;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &latencyFrames );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyLatency, &theSize, &latencyFrames );
#endif
    return latencyFrames;
}

- (UInt32) deviceSafetyOffsetFramesForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 safetyFrames;
	
	theSize = sizeof(UInt32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertySafetyOffset;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &safetyFrames );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertySafetyOffset, &theSize, &safetyFrames );
#endif
	return safetyFrames;
}

- (NSArray *) channelsByStreamForDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioBufferList * theList;
	NSMutableArray * rv;
	UInt32 x;
	
	rv = [NSMutableArray arrayWithCapacity:1];
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, theDirection, kAudioDevicePropertyStreamConfiguration, &theSize, NULL );
#endif
	if (theStatus != 0)
		return rv;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
	theList = (AudioBufferList *) malloc ( theSize );
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, theList );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, theDirection, kAudioDevicePropertyStreamConfiguration, &theSize, theList );
#endif
	if (theStatus != 0)
	{
		free(theList);
		return rv;
	}
	
	for ( x = 0; x < theList->mNumberBuffers; x++ )
	{
		[rv addObject:[NSNumber numberWithUnsignedLong:theList->mBuffers[x].mNumberChannels]];
	}
	free(theList);
	return rv;
}

- (UInt32) channelsForDirection:(MTCoreAudioDirection)theDirection
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	NSNumber * theNumberOfChannelsInThisStream;
	NSEnumerator * channelEnumerator;
	UInt32 rv;
	
	rv = 0;
	
	channelEnumerator = [[self channelsByStreamForDirection:theDirection] objectEnumerator];
	while ( theNumberOfChannelsInThisStream = [channelEnumerator nextObject] )
		rv += [theNumberOfChannelsInThisStream unsignedLongValue];
	[pool release];
	return rv;
}

- (MTCoreAudioVolumeInfo) volumeInfoForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	MTCoreAudioVolumeInfo rv;
	UInt32 theSize;
	UInt32 tmpBool32;
	
	rv.hasVolume = false;
	rv.canMute = false;
	rv.canPlayThru = false;
	rv.theVolume = 0.0;
	rv.isMuted = false;
	rv.playThruIsSet = false;
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
    // TODO - check theStatus
    theStatus = AudioObjectIsPropertySettable( myDevice, &propertyAddress, &rv.canSetVolume );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeScalar, &rv.canSetVolume );
#endif
	if (noErr == theStatus)
	{
		rv.hasVolume = true;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
        theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &rv.theVolume );
#else
		theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeScalar, &theSize, &rv.theVolume );
#endif
		if (noErr != theStatus)
			rv.theVolume = 0.0;
	}
    
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    propertyAddress.mSelector = kAudioDevicePropertyMute;
    theStatus = AudioObjectIsPropertySettable( myDevice, &propertyAddress, &rv.canMute );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyMute, &theSize, &rv.canMute );
#endif
	if (theStatus == 0)
	{
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
        theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &tmpBool32 );
#else
		theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyMute, &theSize, &tmpBool32 );
#endif
		if (noErr == theStatus)
			rv.isMuted = tmpBool32;
	}
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    propertyAddress.mSelector = kAudioDevicePropertyPlayThru;
    theStatus = AudioObjectIsPropertySettable( myDevice, &propertyAddress, &rv.canPlayThru );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyPlayThru, &theSize, &rv.canPlayThru );
#endif
	if (noErr == theStatus)
	{
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
        theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &tmpBool32 );
#else
		theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyPlayThru, &theSize, &tmpBool32 );
#endif
		if (noErr == theStatus)
			rv.playThruIsSet = tmpBool32;
	}
	
	return rv;
}

- (Float32) volumeForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	Float32 theVolumeScalar;
	
	theSize = sizeof(Float32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theVolumeScalar );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeScalar, &theSize, &theVolumeScalar );
#endif
	if (theStatus == 0)
		return theVolumeScalar;
	else
		return 0.0;
}

- (Float32) volumeInDecibelsForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	Float32 theVolumeDecibels;
	
	theSize = sizeof(Float32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeDecibels;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theVolumeDecibels );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeDecibels, &theSize, &theVolumeDecibels );
#endif
	if (theStatus == 0)
		return theVolumeDecibels;
	else
		return 0.0;
}

- (void) setVolume:(Float32)theVolume forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	
	theSize = sizeof(Float32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theVolume );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, theChannel, theDirection, kAudioDevicePropertyVolumeScalar, theSize, &theVolume );
#endif
}

- (void) setVolumeDecibels:(Float32)theVolumeDecibels forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	
	theSize = sizeof(Float32);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeDecibels;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theVolumeDecibels );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, theChannel, theDirection, kAudioDevicePropertyVolumeDecibels, theSize, &theVolumeDecibels );
#endif
}

- (Float32) volumeInDecibelsForVolume:(Float32)theVolume forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	Float32 theVolumeDecibels;
	
	theSize = sizeof(Float32);
	theVolumeDecibels = theVolume;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalarToDecibels;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theVolumeDecibels );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeScalarToDecibels, &theSize, &theVolumeDecibels );
#endif
	if (theStatus == 0)
		return theVolumeDecibels;
	else
		return 0.0;
}

- (Float32) volumeForVolumeInDecibels:(Float32)theVolumeDecibels forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	Float32 theVolume;
	
	theSize = sizeof(Float32);
	theVolume = theVolumeDecibels;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyVolumeDecibelsToScalar;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theVolume );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyVolumeDecibelsToScalar, &theSize, &theVolume );
#endif
	if (theStatus == 0)
		return theVolume;
	else
		return 0.0;
}

- (void) setMute:(BOOL)isMuted forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 theMuteVal;
	
	theSize = sizeof(UInt32);
	if (isMuted) theMuteVal = 1; else theMuteVal = 0;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyMute;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theMuteVal );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, theChannel, theDirection, kAudioDevicePropertyMute, theSize, &theMuteVal );
#endif
}

- (void) setPlayThru:(BOOL)isPlayingThru forChannel:(UInt32)theChannel
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 thePlayThruVal;
	
	theSize = sizeof(UInt32);
	if (isPlayingThru) thePlayThruVal = 1; else thePlayThruVal = 0;
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyPlayThru;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &thePlayThruVal );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, theChannel, kMTCoreAudioDevicePlaybackDirection, kAudioDevicePropertyPlayThru, theSize, &thePlayThruVal );
#endif
}

- (void) setPlayThru:(BOOL)isPlayingThru forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	printf ( "-[MTCoreAudioDevice setPlayThru:forChannel:forDirection:] is deprecated, please use -[MTCoreAudioDevice setPlayThru:forChannel:] instead.\n" );
	[self setPlayThru:isPlayingThru forChannel:theChannel];
}

- (Class) streamDescriptionFactory
{
	return [MTCoreAudioStreamDescription class];
}

- (MTCoreAudioStreamDescription *) streamDescriptionForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioStreamBasicDescription theDescription;
	
	theSize = sizeof(AudioStreamBasicDescription);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreamFormat;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theDescription );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyStreamFormat, &theSize, &theDescription );
#endif
	if (theStatus == 0)
	{
		return [[self streamDescriptionFactory] streamDescriptionWithAudioStreamBasicDescription:theDescription];
	}
	return nil;
}

// NSArray of MTCoreAudioStreamDescriptions
- (NSArray *) streamDescriptionsForChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 numItems;
	UInt32 x;
	AudioStreamBasicDescription * descriptionArray;
	NSMutableArray * rv;
	
	rv = [NSMutableArray arrayWithCapacity:1];
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreamFormats;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, theChannel, theDirection, kAudioDevicePropertyStreamFormats, &theSize, NULL );
#endif
	if (theStatus != 0)
		return rv;
	
	descriptionArray = (AudioStreamBasicDescription *) malloc ( theSize );
	numItems = theSize / sizeof(AudioStreamBasicDescription);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, descriptionArray );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyStreamFormats, &theSize, descriptionArray );
#endif
	if (theStatus != 0)
	{
		free(descriptionArray);
		return rv;
	}
	
	for ( x = 0; x < numItems; x++ )
		[rv addObject:[[self streamDescriptionFactory] streamDescriptionWithAudioStreamBasicDescription:descriptionArray[x]]];

	free(descriptionArray);
	return rv;
}

- (Boolean) setStreamDescription:(MTCoreAudioStreamDescription *)theDescription forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioStreamBasicDescription theASBasicDescription;
	
	theASBasicDescription = [theDescription audioStreamBasicDescription];
	theSize = sizeof(AudioStreamBasicDescription);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreamFormat;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theASBasicDescription );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, theChannel, theDirection, kAudioDevicePropertyStreamFormat, theSize, &theASBasicDescription );
#endif
	return (theStatus == 0);
}

- (MTCoreAudioStreamDescription *) matchStreamDescription:(MTCoreAudioStreamDescription *)theDescription forChannel:(UInt32)theChannel forDirection:(MTCoreAudioDirection)theDirection
{
	OSStatus theStatus;
	UInt32 theSize;
	AudioStreamBasicDescription theASBasicDescription;
	
	theASBasicDescription = [theDescription audioStreamBasicDescription];
	theSize = sizeof(AudioStreamBasicDescription);
	
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyStreamFormatMatch;
    propertyAddress.mScope = (theDirection == kMTCoreAudioDevicePlaybackDirection)  ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput;
    propertyAddress.mElement = theChannel;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theASBasicDescription );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, theChannel, theDirection, kAudioDevicePropertyStreamFormatMatch, &theSize, &theASBasicDescription );
#endif
	if ( theStatus == 0 )
	{
		return [[self streamDescriptionFactory] streamDescriptionWithAudioStreamBasicDescription:theASBasicDescription];
	}

	return nil;
}

- (Float64)    nominalSampleRate
{
	OSStatus theStatus;
	UInt32 theSize;
	Float64 theSampleRate;
	
	theSize = sizeof(Float64);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theSampleRate );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, 0, kAudioDevicePropertyNominalSampleRate, &theSize, &theSampleRate );
#endif
    
	if ( noErr == theStatus )
		return theSampleRate;
	else
		return 0.0;
}

- (NSArray *) nominalSampleRates
{
	OSStatus theStatus;
	UInt32 theSize;
	UInt32 numItems;
	UInt32 x;
	AudioValueRange * rangeArray;
	NSMutableArray * rv = [NSMutableArray array];
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyAvailableNominalSampleRates;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyDataSize( myDevice, &propertyAddress, 0, NULL, &theSize );
#else
	theStatus = AudioDeviceGetPropertyInfo ( myDevice, 0, 0, kAudioDevicePropertyAvailableNominalSampleRates, &theSize, NULL );
#endif
	if ( noErr != theStatus )
		return rv;
	
	rangeArray = (AudioValueRange *) malloc ( theSize );
	numItems = theSize / sizeof(AudioValueRange);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, rangeArray );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, 0, kAudioDevicePropertyAvailableNominalSampleRates, &theSize, rangeArray );
#endif
    if ( noErr != theStatus )
	{
		free(rangeArray);
		return rv;
	}
	
	for ( x = 0; x < numItems; x++ )
		[rv addObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:rangeArray[x].mMinimum], [NSNumber numberWithDouble:rangeArray[x].mMaximum], nil]];

	free(rangeArray);
	return rv;
}

- (Boolean)   supportsNominalSampleRate:(Float64)theRate
{
	NSEnumerator * sampleRateRangeEnumerator = [[self nominalSampleRates] objectEnumerator];
	NSArray * aRange;
	
	while ( aRange = [sampleRateRangeEnumerator nextObject] )
	{
		if (( [[aRange objectAtIndex:0] doubleValue] <= theRate ) && ( [[aRange objectAtIndex:1] doubleValue] >= theRate ))
		{
			return YES;
		}
	}
	return NO;
}

- (Boolean)   setNominalSampleRate:(Float64)theRate
{
	OSStatus theStatus;
	UInt32 theSize;
	
	theSize = sizeof(Float64);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectSetPropertyData( myDevice, &propertyAddress, 0, NULL, theSize, &theRate );
#else
	theStatus = AudioDeviceSetProperty ( myDevice, NULL, 0, 0, kAudioDevicePropertyNominalSampleRate, theSize, &theRate );
#endif
	return ( noErr == theStatus );
}

- (double)    actualSampleRate
{
	OSStatus theStatus;
	UInt32 theSize;
	Float64 theSampleRate;
	
	theSize = sizeof(Float64);
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioDevicePropertyActualSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeWildcard;
    propertyAddress.mElement = kAudioObjectPropertyElementWildcard;
    theStatus = AudioObjectGetPropertyData( myDevice, &propertyAddress, 0, NULL, &theSize, &theSampleRate );
#else
	theStatus = AudioDeviceGetProperty ( myDevice, 0, 0, kAudioDevicePropertyActualSampleRate, &theSize, &theSampleRate );
#endif
    
	if ( noErr == theStatus )
		return theSampleRate;
	else
		return 0.0;
}

- (void) setIOProc:(AudioDeviceIOProc)theIOProc withClientData:(void *)theClientData
{
	[self removeIOProc];
	myIOProc = theIOProc;
	myIOProcClientData = theClientData;
}

- (void) setIOTarget:(id)theTarget withSelector:(SEL)theSelector withClientData:(void *)theClientData
{
	[self removeIOProc];
	myIOInvocation = [[NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(ioCycleForDevice:timeStamp:inputData:inputTime:outputData:outputTime:clientData:)]] retain];
	[myIOInvocation setTarget:theTarget];
	[myIOInvocation setSelector:theSelector];
	[myIOInvocation setArgument:&self atIndex:2];
	[myIOInvocation setArgument:&theClientData atIndex:8];

	myIOProcClientData = theClientData;
}

- (void) removeIOProc
{
	if (myIOProc || myIOInvocation)
	{
		[self deviceStop];
		myIOProc = NULL;
		[myIOInvocation release];
		myIOInvocation = nil;
		myIOProcClientData = NULL;
	}
}

- (void) removeIOTarget
{
	[self removeIOProc];
}

- (Boolean) deviceStart
{
	if (myIOProc || myIOInvocation)
	{
		deviceIOStarted = [MTCoreAudioIOProcMux registerDevice:self];
	}
	return deviceIOStarted;
}

- (void) deviceStop
{
	if (deviceIOStarted)
	{
		[MTCoreAudioIOProcMux unRegisterDevice:self];
		deviceIOStarted = false;
	}
}

- (void) setDevicePaused:(Boolean)shouldPause
{
	if ( shouldPause )
	{
		[MTCoreAudioIOProcMux setPause:shouldPause forDevice:self];
	}
	else
	{
		isPaused = FALSE;
	}
}


- (void) dealloc
{
	if ( isRegisteredForNotifications )
		[[NSNotificationCenter defaultCenter] removeObserver:self name:_MTCoreAudioDeviceNotification object:nil];
	[self setDelegate:nil];
	[self removeIOProc];
	if (myStreams[0]) [myStreams[0] release];
	if (myStreams[1]) [myStreams[1] release];
	[super dealloc];
}

- (OSStatus) ioCycleForDevice:(MTCoreAudioDevice *)theDevice timeStamp:(const AudioTimeStamp *)inNow inputData:(const AudioBufferList *)inInputData inputTime:(const AudioTimeStamp *)inInputTime outputData:(AudioBufferList *)outOutputData outputTime:(const AudioTimeStamp *)inOutputTime clientData:(void *)inClientData
{
	return noErr;
}

@end

@implementation MTCoreAudioDevice(MTCoreAudioDevicePrivateAdditions)

- (void) dispatchIOProcWithTimeStamp:(const AudioTimeStamp *)inNow inputData:(const AudioBufferList *)inInputData inputTime:(const AudioTimeStamp *)inInputTime outputData:(AudioBufferList *)outOutputData outputTime:(const AudioTimeStamp *)inOutputTime
{
	if ( isPaused )
		return;
	
	if (myIOProc)
	{
		(void)(*myIOProc)( myDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, myIOProcClientData );
	}
	else if (myIOInvocation)
	{
		[myIOInvocation setArgument:&inNow atIndex:3];
		[myIOInvocation setArgument:&inInputData atIndex:4];
		[myIOInvocation setArgument:&inInputTime atIndex:5];
		[myIOInvocation setArgument:&outOutputData atIndex:6];
		[myIOInvocation setArgument:&inOutputTime atIndex:7];
		[myIOInvocation invoke];
	}
}

- (void) dispatchIOStartDidFailForReason:(OSStatus)theReason
{
	if ( myDelegate && [myDelegate respondsToSelector:@selector(audioDeviceStartDidFail:forReason:)] )
	{
		[myDelegate audioDeviceStartDidFail:self forReason:theReason];
	}
}

- (void) doSetPause:(Boolean)shouldPause
{
	isPaused = shouldPause;
}

@end
