//
//  VJXBoardDelegate.m
//  VeeJay
//
//  Created by Igor Sutton on 8/27/10.
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

#import "VJXBoardDelegate.h"
#import "VJXBoardEntity.h"
#import "VJXQtVideoLayer.h"
#import "VJXOpenGLScreen.h"
#import "VJXImageLayer.h"
#import "VJXMixer.h"
#import "VJXBoard.h"
#import <QTKit/QTMovie.h>

@implementation VJXBoardDelegate

@synthesize board;

- (void)awakeFromNib
{
    [VJXBoard setSharedBoard:board];
}

- (void)openFilePanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo
{
    VJXEntity *entity = (VJXEntity *)contextInfo;
    
    if(returnCode == NSOKButton){
        NSLog(@"openFilePanel: OK\n");    
    } else if(returnCode == NSCancelButton) {
        NSLog(@"openFilePanel: Cancel\n");
        return;
    } else {
        NSLog(@"openFilePanel: Error %3d\n",returnCode);
        return;
    } // end if     
    NSString * directory = [panel directory];
    NSLog(@"openFile directory = %@\n",directory);
    
    NSString * fileName = [panel filename];
    NSLog(@"openFile filename = %@\n",fileName);
    
    if (fileName) {
        if ([entity respondsToSelector:@selector(open:)]) {
            [entity performSelector:@selector(open:) withObject:fileName];
        } else {
            NSLog(@"Entity %@ doesn't respond to 'open:'\n");
            return;
        }
        VJXBoardEntity *entityView = [[VJXBoardEntity alloc] initWithEntity:entity];
        [board addSubview:entityView];
        [entity release];
        if ([entity respondsToSelector:@selector(start)])
            [entity performSelector:@selector(start)];
        else
             NSLog(@"Entity %@ doesn't respond to 'start'. Not a VJXThreadedEntity ?\n");
        [entityView release];
    }
}

- (void)openFile:(NSArray *)types forEntity:(VJXEntity *)entity
{    
    NSOpenPanel *fileSelectionPanel    = [NSOpenPanel openPanel];
    
    
    [fileSelectionPanel 
     beginSheetForDirectory:nil 
     file:nil
     types:types 
     modalForWindow:[board window]
     modalDelegate:self 
     didEndSelector:@selector(openFilePanelDidEnd: returnCode: contextInfo:) 
     contextInfo:entity];    
    [fileSelectionPanel setCanChooseFiles:YES];
} // end openFile

- (IBAction)addMovieLayer:(id)sender
{
    NSArray *types = [QTMovie movieTypesWithOptions:QTIncludeCommonTypes];
    VJXQtVideoLayer *movieLayer = [[VJXQtVideoLayer alloc] init];
    [self openFile:types forEntity:movieLayer];
}


- (IBAction)addImageLayer:(id)sender
{
    NSArray *types = [NSImage imageTypes];

    VJXImageLayer *imageLayer = [[VJXImageLayer alloc] init];
    [self openFile:types forEntity:imageLayer];
}

- (IBAction)addMixerLayer:(id)sender
{
    VJXMixer *mixer = [[VJXMixer alloc] init];
    VJXBoardEntity *entity = [[VJXBoardEntity alloc] initWithEntity:mixer];
    [board addToBoard:entity];
    [mixer start];
    [mixer release];
    [entity release];
}

- (IBAction)addOutputScreen:(id)sender
{
    VJXOpenGLScreen *screen = [[VJXOpenGLScreen alloc] init];
    VJXBoardEntity *entity = [[VJXBoardEntity alloc] initWithEntity:screen];
    [board addToBoard:entity];
    [entity release];
    [screen release];
}

- (IBAction)removeSelectedEntities:(id)sender
{
    [board removeSelectedEntities];
}

@end
