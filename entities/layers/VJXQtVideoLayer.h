//
//  VJXQtVideoLayer.h
//  VeeJay
//
//  Created by Igor Sutton on 8/5/10.
//  Copyright (c) 2010 StrayDev.com. All rights reserved.
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

#import "VJXVideoEntity.h"
#import "VJXFileRead.h"

@class QTMovie;

@interface VJXQtVideoLayer : VJXVideoEntity <VJXFileRead> {
@private
    QTMovie *movie;
    NSString *moviePath;
    BOOL paused;
    BOOL repeat;
#ifndef __x86_64
    QTVisualContextRef    qtVisualContext;        // the context the movie is playing in
#endif
}

@property (copy) NSString *moviePath;
@property (assign) BOOL paused;
@property (assign) BOOL repeat;

@end

#ifdef __VJXV8__
VJXV8_DECLARE_ENTITY_CONSTRUCTOR(VJXQtVideoLayer);
#endif