//
//  ASN1Node.m
//  ASN.1 Dump
//
//  Created by Chris on 03/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//

#import "ASN1Node.h"

@implementation ASN1Node

+ (id)nodeWithTag:(NSString *)s offset:(NSNumber *)p
{
	ASN1Node *n = [[ASN1Node alloc] initWithTag:s offset:p];
	return [n autorelease];
}

+ (id)nodeWithTag:(NSString *)s
{
	ASN1Node *n = [[ASN1Node alloc] initWithTag:s offset:nil];
	return [n autorelease];
}

- (id)initWithTag:(NSString *)s offset:(NSNumber *)p
{
	self = [super init];
	tag = [s copy];
	length = nil;
	value = nil;
	offset = [p copy];
	children = [[NSMutableArray array] retain];
	return self;
}

- (id)initWithTag:(NSString *)s
{
	return [self initWithTag:s offset:nil];
}

- (void)dealloc
{
	[children release], children = nil;
	[tag release], tag = nil;
	[length release], length = nil;
	[value release], value = nil;
	[offset release], offset = nil;
	[super dealloc];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"(%d) %@ %@ %@ children %@", offset, tag, length, value, children];
}

- (void)setTag:(NSString *)s
{
	[s retain];
	[tag release];
	tag = s;
}

- (void)setLength:(NSString *)s
{
	[s retain];
	[length release];
	length = s;
}

- (void)setValue:(NSString *)s
{
	[s retain];
	[value release];
	value = s;
}

- (NSString *)string
{
	if (tag != nil && length == nil && value == nil)
		return [NSString stringWithFormat:@"%@", tag];
	if (tag != nil && length != nil && value == nil)
		return [NSString stringWithFormat:@"%@ %@", tag, length];
	if (tag != nil && length != nil && value != nil)
		return [NSString stringWithFormat:@"%@ %@ %@", tag, length, value];
	if (tag != nil && length == nil && value != nil)
		return [NSString stringWithFormat:@"%@ %@", tag, value];
	return @"";
}

- (NSNumber *)offset
{
	return offset;
}

- (void)addChild:(ASN1Node *)n
{
	[children addObject:n];
}

- (ASN1Node *)child:(NSInteger)i
{
	return [children objectAtIndex:i];
}

- (NSInteger)numberOfChildren
{
	return [children count];
}

@end
