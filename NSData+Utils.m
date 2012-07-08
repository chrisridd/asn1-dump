//
//  NSData+Utils.m
//  ASN.1 Dump
//
//  Created by Chris on 03/08/2008.
//  Copyright 2008-2012 Chris Ridd. All rights reserved.
//

#import "NSData+Utils.h"

@implementation NSData (Utils)

- (NSInteger)byteAtOffset:(NSInteger)p
{
	char c;

	[self getBytes: &c range:NSMakeRange(p,1)];
	return (NSInteger)c & 0xff;
}

// PEM files look like (according to OpenSSL crypto/pem/pem_lib.c, and a quick
// look at RFC 1421)
// -----BEGIN(stuff)-----\n
// key:value\n (optional, multiple)
// \n(blank line)
// base64-encoded data
// -----END(stuff)-----\n
- (NSData *)dataFromPEMData
{
	NSInteger length = [self length];
	const char *bytes = [self bytes];
	if (length > strlen("-----BEGIN") &&
		strncmp(bytes, "-----BEGIN", strlen("-----BEGIN")) != 0)
		return nil;

	NSInteger i;
	for (i = strlen("-----BEGIN"); i < length - 1; i++) {
		if (strncmp(bytes + i, "\n\n", strlen("\n\n")) == 0) {
			NSLog(@"Base64 data probably at %ld", i + 2);
			NSInteger j;
			for (j = length - 1 - strlen("\n-----END"); j > i + 2; j--) {
				if (strncmp(bytes + j, "\n-----END", strlen("\n-----END")) == 0) {
					NSLog(@"Base64 ends at %ld", j - 1);
					NSMutableData *d = [[NSMutableData alloc] initWithBase64Bytes:bytes + i + 2
                                                                           length: j - (i + 2)];
                    return [d autorelease];
				}
			}
			// not found the -----END
			return nil;
		}
	}
	return nil;
}

- (id)initWithBase64Bytes:(const char *)base64Bytes
				   length:(unsigned long)lentext
{
	unsigned long ixtext = 0;
	unsigned char ch = 0;
	unsigned char inbuf[4], outbuf[3];
	short i = 0, ixinbuf = 0;
	BOOL flignore = NO;
	BOOL flendtext = NO;
	
	NSMutableData *mutableData = [NSMutableData dataWithCapacity:lentext];
	
	while (YES) {
		if (ixtext >= lentext) break;
		ch = base64Bytes[ixtext++];
		flignore = NO;
		
		if ((ch >= 'A') && (ch <= 'Z')) ch = ch - 'A';
		else if ((ch >= 'a') && (ch <= 'z')) ch = ch - 'a' + 26;
		else if ((ch >= '0') && (ch <= '9')) ch = ch - '0' + 52;
		else if (ch == '+') ch = 62;
		else if (ch == '=') flendtext = YES;
		else if (ch == '/') ch = 63;
		else flignore = YES;
		
		if (!flignore) {
			short ctcharsinbuf = 3;
			BOOL flbreak = NO;
			
			if (flendtext) {
				if (!ixinbuf) break;
				if ((ixinbuf == 1) || (ixinbuf == 2)) ctcharsinbuf = 1;
				else ctcharsinbuf = 2;
				ixinbuf = 3;
				flbreak = YES;
			}
			
			inbuf[ixinbuf++] = ch;
			
			if (ixinbuf == 4) {
				ixinbuf = 0;
				outbuf[0] = (inbuf[0] << 2) | ((inbuf[1] & 0x30) >> 4);
				outbuf[1] = ((inbuf[1] & 0x0F) << 4) | ((inbuf[2] & 0x3C) >> 2);
				outbuf[2] = ((inbuf[2] & 0x03) << 6) | (inbuf[3] & 0x3F);
				
				for (i = 0; i < ctcharsinbuf; i++)
					[mutableData appendBytes:&outbuf[i] length:1];
			}
			
			if (flbreak)  break;
		}
	}
	
	self = [self initWithData:mutableData];
	return self;
}

@end
