//
//  JMXDrawEntity.h
//  JMX
//
//  Created by xant on 10/28/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "JMXDrawPath.h"
#import "JMXVideoEntity.h"

@interface JMXDrawEntity : JMXVideoEntity {
@private
    JMXDrawPath *drawPath;
}

@end

#ifdef __JMXV8__
JMXV8_DECLARE_ENTITY_CONSTRUCTOR(JMXDrawEntity);
#endif