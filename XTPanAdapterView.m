//
//  XTPanAdapterView.m
//  MacHPSDR
//
//  Copyright (c) 2010 - Jeremy C. McDermond (NH6Z)

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

// $Id$

#import "XTPanAdapterView.h"

#import <Accelerate/Accelerate.h>

@implementation XTPanAdapterView

@synthesize lowPanLevel;
@synthesize highPanLevel;
@synthesize zoomFactor;

-(id)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if(self) {		
		zoomFactor = 1.0;
		
		path = [[NSBezierPath alloc] init];
		[path setLineWidth:0.5];
										
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector: @selector(doNotification:) 
													 name: NSUserDefaultsDidChangeNotification 
												   object: nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(boundsHaveChanged) 
													 name:NSViewFrameDidChangeNotification 
												   object:nil];
				
		startedLeft = startedRight = dragging = NO;
		
		rootLayer = [CAScrollLayer layer];
		rootLayer.name = @"rootLayer";
		rootLayer.bounds = NSRectToCGRect(self.bounds);
		rootLayer.layoutManager = [CAConstraintLayoutManager layoutManager];
		rootLayer.scrollMode = kCAScrollHorizontally;
		
		tickLayer = [CALayer layer];
		tickLayer.name = @"tickLayer";
		
		//  Save for zoom work
		tickLayer.bounds = CGRectMake(0.0, 0.0, NSWidth(self.bounds), 0.0);
		
		frequencyLayer = [CALayer layer];
		frequencyLayer.name = @"frequencyLayer";
		
		waveLayer = [XTPanadapterLayer layer];
		waveLayer.name = @"waveLayer";
		
		CAConstraint *yCentered = 
		[CAConstraint constraintWithAttribute:kCAConstraintMidY 
								   relativeTo:@"superlayer" 
									attribute:kCAConstraintMidY];
		CAConstraint *xCentered =
		[CAConstraint constraintWithAttribute:kCAConstraintMidX 
								   relativeTo:@"superlayer" 
									attribute:kCAConstraintMidX];
		
		CAConstraint *ySameSize =
		[CAConstraint constraintWithAttribute:kCAConstraintHeight 
								   relativeTo:@"superlayer" 
									attribute:kCAConstraintHeight];
		
		CAConstraint *xWidthOfTicks =
		[CAConstraint constraintWithAttribute:kCAConstraintWidth 
								   relativeTo:@"tickLayer" 
									attribute:kCAConstraintWidth];
		
		/* CAConstraint *xSameSize =
		[CAConstraint constraintWithAttribute:kCAConstraintWidth 
								   relativeTo:@"superlayer" 
									attribute:kCAConstraintWidth]; */
		
		[tickLayer addConstraint:yCentered];
		[tickLayer addConstraint:xCentered];
		[tickLayer addConstraint:ySameSize];
		//[tickLayer addConstraint:xSameSize];
		[tickLayer setNeedsDisplayOnBoundsChange:YES];
		[tickLayer setDelegate: self];
		[rootLayer addSublayer:tickLayer];
		
		[frequencyLayer addConstraint:yCentered];
		[frequencyLayer addConstraint:xCentered];
		[frequencyLayer addConstraint:ySameSize];
		[frequencyLayer addConstraint:xWidthOfTicks];
		[frequencyLayer setNeedsDisplayOnBoundsChange:YES];
		[frequencyLayer setDelegate: self];
		[rootLayer addSublayer:frequencyLayer];
		
		[waveLayer addConstraint:yCentered];
		[waveLayer addConstraint:xCentered];
		[waveLayer addConstraint:ySameSize];
		[waveLayer addConstraint:xWidthOfTicks];
		[waveLayer setNeedsDisplayOnBoundsChange:YES];
		// [waveLayer setDelegate: self];
		[rootLayer addSublayer:waveLayer];
		
		[self setLayer: rootLayer];
		[rootLayer setDelegate: self];
		[self setWantsLayer:YES];
		
		updateThread = [[XTWorkerThread alloc] init];
		[updateThread start];
	}
	return self;
}

-(void)awakeFromNib {	
	lowPanLevel = [[NSUserDefaults standardUserDefaults] floatForKey:@"lowPanLevel"];
	highPanLevel = [[NSUserDefaults standardUserDefaults] floatForKey:@"highPanLevel"];
		
	filterRect = NSMakeRect(NSMidX(self.bounds) + (transceiverController.filterLow / hzPerUnit), 0, (transceiverController.filterHigh / hzPerUnit) - (transceiverController.filterLow / hzPerUnit), NSHeight(self.bounds));	
	subFilterRect = NSMakeRect(subPosition + (transceiverController.subFilterLow / hzPerUnit), 0, (transceiverController.subFilterHigh / hzPerUnit) - (transceiverController.subFilterLow / hzPerUnit), NSHeight(self.bounds));

	[self.window invalidateCursorRectsForView:self];
	
	[transceiverController addObserver:self 
							forKeyPath:@"filterLow" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];	
	[transceiverController addObserver:self 
							forKeyPath:@"filterHigh" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];
	[transceiverController addObserver:self 
							forKeyPath:@"frequency" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];
	[transceiverController addObserver:self 
							forKeyPath:@"subFrequency" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];
	[transceiverController addObserver:self 
							forKeyPath:@"subFilterLow" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];	
	[transceiverController addObserver:self 
							forKeyPath:@"subFilterHigh" 
							   options:NSKeyValueObservingOptionNew 
							   context: NULL];
	[transceiverController addObserver:self 
							forKeyPath:@"subEnabled" 
							   options:NSKeyValueObservingOptionNew 
							   context:NULL];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(dataReady) 
												 name:@"XTPanAdapterDataReady" 
											   object: dataMux];
	
	[waveLayer setDataMUX:dataMux];
	
	[zoomControl bind:@"value" 
			 toObject:self 
		  withKeyPath:@"zoomFactor" 
			  options:nil];
	
	[waterView bind:@"zoomFactor"
		   toObject:self
		withKeyPath:@"zoomFactor"
			options:nil];
}

-(void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
	NSGraphicsContext *nsGraphicsContext;
	nsGraphicsContext = [NSGraphicsContext graphicsContextWithGraphicsPort:ctx 
																   flipped: NO];
	
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:nsGraphicsContext];
	
	if(layer.name == @"tickLayer") {
		//  Recalculate all the tick layer parameters here
		//  We can do it here because this only should be called when we need to
		//  Actually draw the layer
		NSBezierPath *tickMark;
		NSString *tickMarkLabel;
		float mark, position;
		float startFrequency, endFrequency;
		
		hzPerUnit = (float) transceiverController.sampleRate / CGRectGetWidth(layer.bounds);
		startFrequency = ((float) transceiverController.frequency) - (CGRectGetMidX(layer.bounds) * hzPerUnit);
		endFrequency = startFrequency + (CGRectGetWidth(layer.bounds) * hzPerUnit);
		
		
		NSDictionary *textAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor lightGrayColor], NSForegroundColorAttributeName, 
						  [NSFont fontWithName:@"Monaco" size:9.0], NSFontAttributeName,
						  nil];		
		
		// Clear the window
		NSBezierPath *background = [[NSBezierPath alloc] init];
		[background appendBezierPathWithRect:NSRectFromCGRect(layer.bounds)];
		[[NSColor whiteColor] set];
		[background fill];		
		
		[[NSColor lightGrayColor] set];
		for(mark = ceilf(startFrequency / 10000.0) * 10000.0; mark < endFrequency; mark += 10000.0) {
			position = (mark - startFrequency) / hzPerUnit;
			
			tickMark = [[NSBezierPath alloc] init];
			[tickMark setLineWidth: 0.5];
			[tickMark moveToPoint: NSMakePoint(position, 0)];
			[tickMark lineToPoint: NSMakePoint(position, CGRectGetHeight(layer.bounds))];
			[tickMark stroke];
			
			tickMarkLabel = [NSString stringWithFormat:@"%d", (int) (mark / 1000.0)];
			[tickMarkLabel drawAtPoint:NSMakePoint(position + 4, CGRectGetHeight(layer.bounds) - 15) 
						withAttributes:textAttributes];
		}
		
		float slope = CGRectGetHeight(layer.bounds) / (highPanLevel - lowPanLevel);
		
		for(mark = ceilf(lowPanLevel / 10.0) * 10.0; mark < highPanLevel; mark += 10.0) {
			position = (mark - lowPanLevel) * slope;
			
			tickMark = [[NSBezierPath alloc] init];
			[tickMark setLineWidth: 0.5];
			[tickMark moveToPoint: NSMakePoint(0, position)];
			[tickMark lineToPoint: NSMakePoint(CGRectGetWidth(layer.bounds), position)];
			[tickMark stroke];
			
			tickMarkLabel = [NSString stringWithFormat:@"%d dB", (int) mark];
			[tickMarkLabel drawAtPoint:NSMakePoint(4, position - 15) 
						withAttributes:textAttributes];
		}
		
		
	} else if(layer.name == @"frequencyLayer") {
		float startFrequency, endFrequency;
		
		hzPerUnit = (float) transceiverController.sampleRate / CGRectGetWidth(layer.bounds);
		startFrequency = ((float) transceiverController.frequency) - (CGRectGetMidX(layer.bounds) * hzPerUnit);
		endFrequency = startFrequency + (CGRectGetWidth(layer.bounds) * hzPerUnit);

		NSBezierPath *centerLine = [[NSBezierPath alloc] init];
		[centerLine setLineWidth:0.5];
		[centerLine moveToPoint:NSMakePoint(CGRectGetMidX(layer.bounds), 0)];
		[centerLine lineToPoint:NSMakePoint(CGRectGetMidX(layer.bounds), CGRectGetHeight(layer.bounds))];
		[[NSColor redColor] set];
		[centerLine stroke];

		if(transceiverController.subEnabled == TRUE) {
			subPosition = (transceiverController.subFrequency - startFrequency) / hzPerUnit;
			
			NSBezierPath *subLine = [[NSBezierPath alloc] init];
			[subLine setLineWidth:0.5];
			[subLine moveToPoint:NSMakePoint(subPosition, 0)];
			[subLine lineToPoint:NSMakePoint(subPosition, CGRectGetHeight(layer.bounds))];											 
			[[NSColor blueColor] set];
			[subLine stroke];
			
			subFilterRect = NSMakeRect(subPosition + (transceiverController.subFilterLow / hzPerUnit), 
									   0, 
									   (transceiverController.subFilterHigh / hzPerUnit) - (transceiverController.subFilterLow / hzPerUnit), 
									   CGRectGetHeight(layer.bounds));
			
			NSBezierPath *subFilter = [[NSBezierPath alloc] init];
			[subFilter appendBezierPathWithRect:subFilterRect];
			[[NSColor colorWithDeviceRed:0.0 green:0.0 blue:1.0 alpha:0.1] set];
			[subFilter fill];
			
		}
											 
		NSDictionary *bandPlan = [transceiverController bandPlan];
		NSRange panadapterRange = NSMakeRange(startFrequency, transceiverController.sampleRate);
		for(id band in bandPlan) {
			int start = [[[bandPlan objectForKey:band] objectForKey:@"start"] intValue];
			int length = [[[bandPlan objectForKey:band] objectForKey:@"end"] intValue] - start;
			NSRange bandRange = NSMakeRange(start, length);
			NSRange intersectionRange = NSIntersectionRange(bandRange, panadapterRange);
			if(intersectionRange.length != 0) {
				NSRect bandEdgeRect = NSMakeRect((intersectionRange.location - startFrequency) / hzPerUnit, 
										  0, 
										  intersectionRange.length / hzPerUnit, 
										  CGRectGetHeight(layer.bounds));
				
				NSBezierPath *bandEdges = [[NSBezierPath alloc] init];
				[bandEdges setLineWidth:0.5];
				[bandEdges appendBezierPathWithRect:bandEdgeRect];
				[[NSColor colorWithDeviceRed:0.0 green:1.0 blue:0.0 alpha:0.05] set];
				[bandEdges fill];
				[[NSColor greenColor] set];
				[bandEdges stroke];				
			}
		}		
		
		filterRect = NSMakeRect(CGRectGetMidX(layer.bounds) + (transceiverController.filterLow / hzPerUnit), 
								0, 
								(transceiverController.filterHigh / hzPerUnit) - (transceiverController.filterLow / hzPerUnit), 
								CGRectGetHeight(layer.bounds));
		NSBezierPath *filter = [[NSBezierPath alloc] init];
		[filter appendBezierPathWithRect:filterRect];
		[[NSColor colorWithDeviceRed:1.0 green:0.0 blue:0.0 alpha:0.1] set];
		[filter fill];
		
		[self.window invalidateCursorRectsForView:self];
		
	} else if(layer.name == @"waveLayer") {
		int i;
		
		float x = 0;
		float *y;
		float negativeLowPanLevel;
		
		float slope = CGRectGetHeight(layer.bounds) / (highPanLevel - lowPanLevel);
				
		[path removeAllPoints];
		
		// Get the buffer
		NSData *panData = [dataMux smoothBufferData];
		
		float scale = CGRectGetWidth(layer.bounds) / (float) ([panData length] / sizeof(float));
		
		const float *smoothBuffer = [panData bytes];
		y = malloc([panData length]);
		
		negativeLowPanLevel = -lowPanLevel;
		vDSP_vsadd((float *) smoothBuffer, 1, &negativeLowPanLevel, y, 1, [panData length] / sizeof(float));
		vDSP_vsmul(y, 1, &slope, y, 1, [panData length] / sizeof(float)); 
		
		for(i = 1; i < ([panData length] / sizeof(float)) - 1; ++i) {
			x = i * scale;
			
			if(i == 1) {
				[path moveToPoint:NSMakePoint(x, y[i])];
			} else {
				[path lineToPoint:NSMakePoint(x, y[i])];
			}
		}
		
		free(y);
		
		[[NSColor blackColor] set];
		[path stroke];
	}

	[NSGraphicsContext restoreGraphicsState];
}

-(void)dataReady {
	[waveLayer performSelector:@selector(setNeedsDisplay)
					  onThread:updateThread
					withObject:nil
				 waitUntilDone:NO];
}

-(void)doNotification: (NSNotification *) notification {
	NSString *notificationName = [notification name];
	
	if(notification == nil || notificationName == NSUserDefaultsDidChangeNotification ) {
		lowPanLevel = [[NSUserDefaults standardUserDefaults] floatForKey:@"lowPanLevel"];
		highPanLevel = [[NSUserDefaults standardUserDefaults] floatForKey:@"highPanLevel"];
		
		[tickLayer setNeedsDisplay];
	}

}

-(void)mouseDown:(NSEvent *)theEvent {
	NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView: nil];
	if(NSPointInRect(clickPoint, leftFilterBoundaryRect)) {
		startedLeft = YES;
	} else if(NSPointInRect(clickPoint, rightFilterBoundaryRect)) {
		startedRight = YES;
	} else if(transceiverController.subEnabled == YES) {
		if(NSPointInRect(clickPoint, leftSubFilterBoundaryRect)) {
			startedSubLeft = YES;
		} else if(NSPointInRect(clickPoint, rightSubFilterBoundaryRect)) {
			startedSubRight = YES;
		} else if(NSPointInRect(clickPoint, subFilterHotRect)) {
			startedSub = YES;
		}
	}
}

-(void)mouseDragged: (NSEvent *)theEvent {
	if([theEvent modifierFlags] & NSAlternateKeyMask) return;
	
	if(startedLeft == YES) {
		transceiverController.filterHigh += [theEvent deltaX] * hzPerUnit;
	} else if(startedRight == YES) {
		transceiverController.filterLow += [theEvent deltaX] * hzPerUnit;
	} else if(startedSubLeft == YES) {
		transceiverController.subFilterHigh += [theEvent deltaX] * hzPerUnit;
	} else if(startedSubRight == YES) {
		transceiverController.subFilterLow += [theEvent deltaX] * hzPerUnit;
	} else if(startedSub == YES) {
		if([[NSCursor currentCursor] isNotEqualTo:[NSCursor closedHandCursor]]) {
			[[NSCursor closedHandCursor] push];
		}		
		transceiverController.subFrequency += [theEvent deltaX] * hzPerUnit;
	} else {
		dragging = YES;
		if([[NSCursor currentCursor] isNotEqualTo:[NSCursor closedHandCursor]]) {
			[[NSCursor closedHandCursor] push];
		}
		transceiverController.frequency -= [theEvent deltaX] * hzPerUnit;
	} 
}

-(void)mouseUp: (NSEvent *)theEvent {
	if([theEvent clickCount] == 0) {
		// Dragging
		if(startedLeft == YES) {
			transceiverController.filterHigh += [theEvent deltaX] * hzPerUnit;
		} else if (startedRight == YES) {
			transceiverController.filterLow += [theEvent deltaX] * hzPerUnit;
		} else if(startedSubLeft == YES) {
			transceiverController.subFilterHigh += [theEvent deltaX] * hzPerUnit;
		} else if(startedSubRight == YES) {
			transceiverController.subFilterLow += [theEvent deltaX] * hzPerUnit;
		} else if(startedSub == YES) {
			transceiverController.subFrequency += [theEvent deltaX] * hzPerUnit;
			[NSCursor pop];			
		} else {
			transceiverController.frequency -= [theEvent deltaX] * hzPerUnit;
			[NSCursor pop];
		}
	} else {
		// Click or Double-Click
		NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView: nil];
		if([theEvent modifierFlags] & NSAlternateKeyMask) {
			if(transceiverController.subEnabled == TRUE) {
				transceiverController.subFrequency += (clickPoint.x - subPosition) * hzPerUnit;
			}
		} else {
			transceiverController.frequency += (clickPoint.x - NSMidX(self.bounds)) * hzPerUnit;
		}
	}
	startedLeft = startedRight = startedSubLeft = startedSubRight = startedSub = dragging = NO;
}

-(void)rightMouseUp:(NSEvent *)theEvent {
	if(transceiverController.subEnabled == TRUE && [theEvent clickCount] > 0) {
		NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView: nil];
		transceiverController.subFrequency += (clickPoint.x - subPosition) * hzPerUnit;
	}
}

-(void)scrollWheel:(NSEvent *)theEvent {
	if([theEvent modifierFlags] & NSAlternateKeyMask) {
		if(transceiverController.subEnabled == TRUE) {
			transceiverController.subFrequency += [theEvent deltaY] * hzPerUnit;
		}
	} else {
		transceiverController.frequency += [theEvent deltaY] * hzPerUnit;
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{	
	[frequencyLayer setNeedsDisplay];
	[tickLayer setNeedsDisplay];
}

-(void)resetCursorRects {
	rightFilterBoundaryRect = NSMakeRect(NSMinX(filterRect) - 3, 
										 0, 
										 6, 
										 NSHeight(self.bounds));
	rightFilterBoundaryRect = NSRectFromCGRect([tickLayer convertRect:NSRectToCGRect(rightFilterBoundaryRect)
											 toLayer:rootLayer]);
	
	leftFilterBoundaryRect = NSMakeRect(NSMaxX(filterRect) - 3,
										0,
										6, 
										NSHeight(self.bounds));
	leftFilterBoundaryRect = NSRectFromCGRect([tickLayer convertRect:NSRectToCGRect(leftFilterBoundaryRect)
											toLayer:rootLayer]);
	
	rightSubFilterBoundaryRect = NSMakeRect(NSMinX(subFilterRect) - 3,
											0,
											6,
											NSHeight(self.bounds));
	rightSubFilterBoundaryRect = NSRectFromCGRect([tickLayer convertRect:NSRectToCGRect(rightSubFilterBoundaryRect)
												toLayer:rootLayer]);
	
	leftSubFilterBoundaryRect = NSMakeRect(NSMaxX(subFilterRect) - 3,
										   0,
										   6,
										   NSHeight(self.bounds));
	leftSubFilterBoundaryRect = NSRectFromCGRect([tickLayer convertRect:NSRectToCGRect(leftSubFilterBoundaryRect)
											   toLayer:rootLayer]);
	
	if(dragging == YES || startedSub == YES) {
		[self addCursorRect:self.bounds cursor:[NSCursor currentCursor]];
	} else {
		[self addCursorRect:rightFilterBoundaryRect 
					 cursor:[NSCursor resizeLeftRightCursor]];
		[self addCursorRect:leftFilterBoundaryRect 
					 cursor:[NSCursor resizeLeftRightCursor]];
		if(transceiverController.subEnabled == YES) {
			subFilterHotRect = NSMakeRect(NSMinX(subFilterRect) + 3, 
												 NSMinY(subFilterRect),
												 NSWidth(subFilterRect) - 6, 
												 NSHeight(subFilterRect));
			subFilterHotRect = NSRectFromCGRect([tickLayer convertRect:NSRectToCGRect(subFilterHotRect)
											  toLayer:rootLayer]);
			
			[self addCursorRect:subFilterHotRect 
						 cursor:[NSCursor openHandCursor]];
			[self addCursorRect:rightSubFilterBoundaryRect
						 cursor:[NSCursor resizeLeftRightCursor]];
			[self addCursorRect:leftSubFilterBoundaryRect 
						 cursor:[NSCursor resizeLeftRightCursor]];
		}
	} 
}

-(id)actionForLayer:(CALayer *)theLayer forKey:(NSString *) aKey {	
	return [NSNull null];
}

-(void)boundsHaveChanged {
	tickLayer.bounds = CGRectMake(0.0, 0.0, NSWidth(self.bounds) * zoomFactor, 0.0);
}

-(void)setZoomFactor:(float)newZoomFactor {
	if(newZoomFactor < 1.0) return;
	zoomFactor = newZoomFactor;
	
	tickLayer.bounds = CGRectMake(0.0, 0.0, NSWidth(self.bounds) * zoomFactor, 0.0);
	[rootLayer scrollToRect:CGRectMake(CGRectGetWidth(rootLayer.bounds) / 4.0, 0, CGRectGetWidth(rootLayer.bounds) / 2.0, CGRectGetHeight(rootLayer.bounds))];
}

-(IBAction)zoomIn: (id) sender {
	self.zoomFactor *= 2.0;
}

-(IBAction)zoomOut: (id) sender {
	self.zoomFactor /= 2.0;
}

-(BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
    return [NSApp isActive];
}

@end
