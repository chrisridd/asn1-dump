//
//  NSData+Utils.h
//  ASN.1 Dump
//
//  Created by Chris on 03/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface NSData (Utils)

- (NSInteger)byteAtOffset:(NSInteger)p;

- (NSData *)dataFromPEMData;

- (id)initWithBase64Bytes:(const char *)base64Bytes
				   length:(unsigned long)lentext;

@end
