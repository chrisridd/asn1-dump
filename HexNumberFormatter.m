//
//  HexNumberFormatter.m
//  ASN.1 Dump
//
//  Created by Chris on 09/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//

#import "HexNumberFormatter.h"

@implementation HexNumberFormatter

- (NSString *)stringForObjectValue:(id)anObject
{
    if (![anObject isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%08lx", [anObject integerValue]];
}

@end
