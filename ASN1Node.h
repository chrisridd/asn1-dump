//
//  ASN1Node.h
//  ASN.1 Dump
//
//  Created by Chris on 03/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ASN1Node : NSObject {
	NSString		*tag;
	NSString		*length;
	NSString		*value;
	NSNumber		*offset;
	NSMutableArray	*children;
}

+ (id)nodeWithTag:(NSString *)s offset:(NSNumber *)p;
+ (id)nodeWithTag:(NSString *)s;

- (id)initWithTag:(NSString *)s;
- (id)initWithTag:(NSString *)s offset:(NSNumber *)p;

- (void)setTag:(NSString *)s;
- (void)setLength:(NSString *)s;
- (void)setValue:(NSString *)s;
- (NSString *)string;
- (NSNumber *)offset;

- (void)addChild:(ASN1Node *)n;
- (ASN1Node *)child:(NSInteger)i;
- (NSInteger)numberOfChildren;
@end
