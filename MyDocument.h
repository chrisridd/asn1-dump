//
//  MyDocument.h
//  ASN.1 Dump
//
//  Created by Chris on 03/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//


#import <Cocoa/Cocoa.h>

@class ASN1Node;
@interface MyDocument : NSDocument
{
	IBOutlet NSOutlineView *outline;
	ASN1Node *doc;
}
@end
