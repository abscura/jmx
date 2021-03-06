//
//  JMXWindowController.h
//  JMX
//
//  Created by Igor Sutton on 11/14/10.
//  Copyright 2010 Dyne.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "JMXEntityInspectorPanel.h"

@interface JMXWindowController : NSWindowController {
	NSView *libraryView;	
	NSSplitView *documentSplitView;
	NSViewController *boardViewController;
    IBOutlet NSPanel *inspectorPanel;
    IBOutlet NSTextView *outputPanel;
    IBOutlet NSPanel *domBrowser;
    int stdout_pipe[2];
    int stderr_pipe[2];
    int output_filedes[2];
}

@property (nonatomic, assign) IBOutlet NSSplitView *documentSplitView;
@property (nonatomic, assign) IBOutlet NSViewController *boardViewController;
@property (nonatomic, assign) IBOutlet NSView *libraryView;

#pragma mark -
#pragma mark Interface Builder actions

- (IBAction)toggleInspector:(id)sender;
- (IBAction)toggleDOMBrowser:(id)sender;
- (IBAction)toggleLibrary:(id)sender;
- (IBAction)showJavascriptExamples:(id)sender;

@end
