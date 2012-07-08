/*
 * Dump a BER-encoded file to stdout
 *
 * Copyright Chris Ridd, 1993-2012
 *
 * If string folding occurs, the length printed is incorrect. The printed
 * length is the length of the outer type, which will be more than the actual
 * number of octets in the constructed string
 */
#import <Foundation/Foundation.h>
#import "NSData+Utils.h"
#import "ASN1Node.h"
#import "berd.h"

#include <stdarg.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * BER tag classes
 *
 */
enum classes {
	UNIVERSAL = 0x00,
	APPLICATION = 0x01,
	CONTEXT = 0x02,
	PRIVATE = 0x03
};


/*
 * Globals
 *
 */
int		fold = 0;			// 1 means fold constructed strings together
int		textoctets = 0;		// 1 means display OCTETs as text
int		lengths = 1;		// 0 means do not display length value
int		encapsulated = 1;	// 1 means look for encapsulated data

const char *univTags[] = {
	"BOOLEAN",
	"INTEGER",
	"BIT STRING",
	"OCTET STRING",
	"NULL",
	"OBJECT IDENTIFIER",
	"ObjectDescriptor",
	"EXTERNAL",
	"REAL",
	"ENUMERATED",
	NULL,				/* 11 (reserved by ISO) */
	"UTF8String",
	"RELATIVE-OID",
	NULL,				/* 14 */
	NULL,				/* 15 */     	
	"SEQUENCE",
	"SET",
	"NumericString",
	"PrintableString",
	"TeletexString",
	"VideotexString",
	"IA5String",
	"UTCTime",
	"GeneralizedTime",
	"GraphicString",
	"VisibleString",
	"GeneralString",
	"UniversalString",
	NULL,				/* 29 */
	"BMPString"
};
#define numTags ((int)(sizeof(univTags) / sizeof(univTags[0])))

enum tags {
	ASN1_BOOLEAN = 1,
	ASN1_INTEGER = 2,
	ASN1_BIT_STRING = 3,
	ASN1_OCTET_STRING = 4,
	ASN1_NULL = 5,
	ASN1_OBJECT_IDENTIFIER = 6,
	ASN1_ObjectDescriptor = 7,
	ASN1_EXTERNAL = 8,
	ASN1_REAL = 9,
	ASN1_ENUMERATED = 10,
	ASN1_EMBEDDED_PDV = 11,
	ASN1_UTF8String = 12,
	ASN1_RELATIVE_OID = 13,
	/* 14 */
	/* 15 */     	
	ASN1_SEQUENCE = 16,
	ASN1_SET = 17,
	ASN1_NumericString = 18,
	ASN1_PrintableString = 19,
	ASN1_TeletexString = 20,
	ASN1_VideotexString = 21,
	ASN1_IA5String = 22,
	ASN1_UTCTime = 23,
	ASN1_GeneralizedTime = 24,
	ASN1_GraphicString = 25,
	ASN1_VisibleString = 26,
	ASN1_GeneralString = 27,
	ASN1_UniversalString = 28,
	/* 29 */
	ASN1_BMPString = 30
};

typedef struct {
	int	t_class;
	int	t_encode;
	int	t_tagnum;
} Tag;

NSInteger dump(NSData *d, NSInteger pos, NSInteger checkpt, ASN1Node *parent, enum Display display);

/*
 * Print a tag name and length value
 *
 */
ASN1Node *printTL(Tag *tag, NSInteger pos, long len, enum Display subdisplay)
{
	const char *s;

	NSString *t = nil;
	switch (tag->t_class) {
	case UNIVERSAL:
		s = NULL;
		if (tag->t_tagnum > 0 && tag->t_tagnum < numTags)
			s = univTags[tag->t_tagnum - 1];
		if (s)
			t = [NSString stringWithFormat: @"%s", s];
		else
			t = [NSString stringWithFormat:@"[UNIVERSAL %d]", tag->t_tagnum];
		break;
	case APPLICATION:
		t = [NSString stringWithFormat:@"[APPLICATION %d]", tag->t_tagnum];
		break;
	case CONTEXT:
		t = [NSString stringWithFormat:@"[%d]", tag->t_tagnum];
		break;
	case PRIVATE:
		t = [NSString stringWithFormat:@"[PRIVATE %d]", tag->t_tagnum];
		break;
	}
	ASN1Node *n = [ASN1Node nodeWithTag:t offset:[NSNumber numberWithInteger:pos]];
	
	if (lengths)
		[n setLength:[NSString stringWithFormat:@"-- %ld octet%@ --", len, len == 1 ? @"" : @"s"]];

	/*
	 * If a folded string, print the string prefix (like a ")
	 * If any other constructed type, or no folding, print a brace
	 *
	 */
	NSString *v = nil;
	if (tag->t_encode) {
		if (tag->t_class == 0) {
			if (subdisplay == standard) {
				v = @"{";
			}
		} else {
			v = @"{";
		}
		[n setValue:v];
	}
		
	return n;
}

/*
 * Print a bit string
 *
 */
NSString *printBit(NSData *d, NSInteger pos, long len)
{
	int  unused;	// Unused bits at end of string
	int	 num;
	int  mask;
	long n;
	int  c;
	int  i;
	NSMutableString *value = [NSMutableString stringWithString:@"\'"];

	unused = [d byteAtOffset:pos++];
	for (n = 0; n < (len - 1); n++) {
		num = (n == len - 2) ? 8 - unused : 8;
		c = [d byteAtOffset:pos++];
		for (i = 1, mask = 0x80; i <= num; i++, mask >>= 1)
			[value appendString:(c & mask) ? @"1" : @"0"];
	}
	[value appendString:@"\'B"];
	return value;
}

/*
 * Print an octet string
 *
 */
NSString *printOctet(NSData *d, NSInteger pos, long len)
{
	long n;
	NSMutableString *value = [NSMutableString string];

	for (n = 0; n < len; n++)
		[value appendFormat:@"%02x", [d byteAtOffset:pos++]];
	return value;
}

/*
 * Print a text string
 * All escape characters are printed as per ANSI C (ie \n etc)
 * Unknown escape characters are printed in hex
 *
 */
NSString *printText(NSData *d, NSInteger pos, long len)
{
	long n;
	int  c;
	NSMutableString *value = [NSMutableString string];

	for (n = 0; n < len; n++) {
		c = [d byteAtOffset:pos++];
		switch (c) {
		case '\n':	[value appendString:@"\\n"];	break;
		case '\t':	[value appendString:@"\\t"];	break;
		case '\v':	[value appendString:@"\\v"];	break;
		case '\b':	[value appendString:@"\\b"];	break;
		case '\r':	[value appendString:@"\\r"];	break;
		case '\f':	[value appendString:@"\\f"];	break;
		case '\a':	[value appendString:@"\\a"];	break;
		case '\\':	[value appendString:@"\\\\"];	break;
		case '\?':	[value appendString:@"\\?"];	break;
		case '\'':	[value appendString:@"\\\'"];	break;
		case '\"':	[value appendString:@"\\\""];	break;
		default:	if (iscntrl(c) || c > 0x7f)
			[value appendFormat:@"\\x%02x", c];
					else
						[value appendFormat:@"%c", c];
					break;
		}
	}
	return value;
}

/*
 * Read Tag octet(s)
 * Returns new pos
 *
 */
NSInteger readT(NSData *d, NSInteger pos, Tag *t)
{
	Tag		tag;
	int		c;
	
	c = [d byteAtOffset:pos++];
	
	tag.t_class = (c >> 6) & 0x03;
	tag.t_encode = (c >> 5) & 0x01;
	tag.t_tagnum = c & 0x1f;

	if (tag.t_tagnum == 0x1f) {		// Read further octets
		tag.t_tagnum = 0;
		while ((c = [d byteAtOffset:pos++]) && c & 0x80)
			tag.t_tagnum = (tag.t_tagnum << 7) | c;
									// Potential overflow...
	}
	*t = tag;
	return pos;
}

/*
 * Check if there's encapsulated data
 * Sniff the initial tag and length to see if the data looks
 * decodable. Based on Peter Gutmann's dumpasn1 heuristics.
 *
 */
int isEncapsulated(NSData *d, NSInteger pos, long outerlen)
{
	Tag		tag;
	long	len;

	if (encapsulated == 0)
		return 0;

	// minimal size of a tag+length is 2 bytes
	if (outerlen < 2)
		return 0;

	@try {
		NSInteger newpos = readT(d, pos, &tag);

		// extended tags suggest it isn't BER
		if (tag.t_tagnum == 0x1f) {
			return 0;
		}
		
		// only allow UNIVERSAL or CONTEXT classes	
		if (tag.t_class != UNIVERSAL && tag.t_class != CONTEXT) {
			return 0;
		}
		
		int c = [d byteAtOffset: newpos++];
		
		if (c == 0x80) {				// indefinite length
			return 0;
		} else if (c & 0x80) {
			long nlen = c & 0x7f;
			len = 0;
			for (c = 0; c < nlen; c++) {
				len = (len << 8) | ([d byteAtOffset:newpos++] & 0xff);
					// Potential overflow...
			}
		} else {
			len = c & 0x7f;
		}
		outerlen -= (newpos - pos); // account for extra tag and len?
	}
	// if we get a range exception, it wasn't BER!
	@catch (NSException *e) {
		return 0;
	}
	
	// sanity check length matches len here
	if (outerlen == len)
		return 1;

	return 0;
}
	
/*
 * Print a value.
 * Never called for a constructed type (SET/SEQ or IMPLICIT SET/SEQ)
 *
 */
NSString *printV(NSData *d, NSInteger pos, Tag *tag, long len, NSInteger *decapsulatePos, long *decapsulateLen)
{
	int 	c;
	long	n;
	long	iv;
	static	NSMutableDictionary *oid = nil;
	NSMutableString *value = [NSMutableString string];

	if (oid == nil) {
		oid = [[NSMutableDictionary alloc] init];
		[oid setObject:@"Telesec" forKey:@"0.2.262.1.10"];
		[oid setObject:@"extension" forKey:@"0.2.262.1.10.0"];
		[oid setObject:@"mechanism" forKey:@"0.2.262.1.10.1"];
		[oid setObject:@"authentication" forKey:@"0.2.262.1.10.1.0"];
		[oid setObject:@"passwordAuthentication" forKey:@"0.2.262.1.10.1.0.1"];
		[oid setObject:@"protectedPasswordAuthentication" forKey:@"0.2.262.1.10.1.0.2"];
		[oid setObject:@"oneWayX509Authentication" forKey:@"0.2.262.1.10.1.0.3"];
		[oid setObject:@"twoWayX509Authentication" forKey:@"0.2.262.1.10.1.0.4"];
		[oid setObject:@"threeWayX509Authentication" forKey:@"0.2.262.1.10.1.0.5"];
		[oid setObject:@"oneWayISO9798Authentication" forKey:@"0.2.262.1.10.1.0.6"];
		[oid setObject:@"twoWayISO9798Authentication" forKey:@"0.2.262.1.10.1.0.7"];
		[oid setObject:@"telekomAuthentication" forKey:@"0.2.262.1.10.1.0.8"];
		[oid setObject:@"signature" forKey:@"0.2.262.1.10.1.1"];
		[oid setObject:@"md4WithRSAAndISO9697" forKey:@"0.2.262.1.10.1.1.1"];
		[oid setObject:@"md4WithRSAAndTelesecSignatureStandard" forKey:@"0.2.262.1.10.1.1.2"];
		[oid setObject:@"md5WithRSAAndISO9697" forKey:@"0.2.262.1.10.1.1.3"];
		[oid setObject:@"md5WithRSAAndTelesecSignatureStandard" forKey:@"0.2.262.1.10.1.1.4"];
		[oid setObject:@"ripemd160WithRSAAndTelekomSignatureStandard" forKey:@"0.2.262.1.10.1.1.5"];
		[oid setObject:@"hbciRsaSignature" forKey:@"0.2.262.1.10.1.1.9"];
		[oid setObject:@"encryption" forKey:@"0.2.262.1.10.1.2"];
		[oid setObject:@"none" forKey:@"0.2.262.1.10.1.2.0"];
		[oid setObject:@"rsaTelesec" forKey:@"0.2.262.1.10.1.2.1"];
		[oid setObject:@"des" forKey:@"0.2.262.1.10.1.2.2"];
		[oid setObject:@"desECB" forKey:@"0.2.262.1.10.1.2.2.1"];
		[oid setObject:@"desCBC" forKey:@"0.2.262.1.10.1.2.2.2"];
		[oid setObject:@"desOFB" forKey:@"0.2.262.1.10.1.2.2.3"];
		[oid setObject:@"desCFB8" forKey:@"0.2.262.1.10.1.2.2.4"];
		[oid setObject:@"desCFB64" forKey:@"0.2.262.1.10.1.2.2.5"];
		[oid setObject:@"des3" forKey:@"0.2.262.1.10.1.2.3"];
		[oid setObject:@"des3ECB" forKey:@"0.2.262.1.10.1.2.3.1"];
		[oid setObject:@"des3CBC" forKey:@"0.2.262.1.10.1.2.3.2"];
		[oid setObject:@"des3OFB" forKey:@"0.2.262.1.10.1.2.3.3"];
		[oid setObject:@"des3CFB8" forKey:@"0.2.262.1.10.1.2.3.4"];
		[oid setObject:@"des3CFB64" forKey:@"0.2.262.1.10.1.2.3.5"];
		[oid setObject:@"magenta" forKey:@"0.2.262.1.10.1.2.4"];
		[oid setObject:@"idea" forKey:@"0.2.262.1.10.1.2.5"];
		[oid setObject:@"ideaECB" forKey:@"0.2.262.1.10.1.2.5.1"];
		[oid setObject:@"ideaCBC" forKey:@"0.2.262.1.10.1.2.5.2"];
		[oid setObject:@"ideaOFB" forKey:@"0.2.262.1.10.1.2.5.3"];
		[oid setObject:@"ideaCFB8" forKey:@"0.2.262.1.10.1.2.5.4"];
		[oid setObject:@"ideaCFB64" forKey:@"0.2.262.1.10.1.2.5.5"];
		[oid setObject:@"oneWayFunction" forKey:@"0.2.262.1.10.1.3"];
		[oid setObject:@"md4" forKey:@"0.2.262.1.10.1.3.1"];
		[oid setObject:@"md5" forKey:@"0.2.262.1.10.1.3.2"];
		[oid setObject:@"sqModNX509" forKey:@"0.2.262.1.10.1.3.3"];
		[oid setObject:@"sqModNISO" forKey:@"0.2.262.1.10.1.3.4"];
		[oid setObject:@"ripemd128" forKey:@"0.2.262.1.10.1.3.5"];
		[oid setObject:@"hashUsingBlockCipher" forKey:@"0.2.262.1.10.1.3.6"];
		[oid setObject:@"mac" forKey:@"0.2.262.1.10.1.3.7"];
		[oid setObject:@"ripemd160" forKey:@"0.2.262.1.10.1.3.8"];
		[oid setObject:@"fecFunction" forKey:@"0.2.262.1.10.1.4"];
		[oid setObject:@"reedSolomon" forKey:@"0.2.262.1.10.1.4.1"];
		[oid setObject:@"module" forKey:@"0.2.262.1.10.2"];
		[oid setObject:@"algorithms" forKey:@"0.2.262.1.10.2.0"];
		[oid setObject:@"attributeTypes" forKey:@"0.2.262.1.10.2.1"];
		[oid setObject:@"certificateTypes" forKey:@"0.2.262.1.10.2.2"];
		[oid setObject:@"messageTypes" forKey:@"0.2.262.1.10.2.3"];
		[oid setObject:@"plProtocol" forKey:@"0.2.262.1.10.2.4"];
		[oid setObject:@"smeAndComponentsOfSme" forKey:@"0.2.262.1.10.2.5"];
		[oid setObject:@"fec" forKey:@"0.2.262.1.10.2.6"];
		[oid setObject:@"usefulDefinitions" forKey:@"0.2.262.1.10.2.7"];
		[oid setObject:@"stefiles" forKey:@"0.2.262.1.10.2.8"];
		[oid setObject:@"sadmib" forKey:@"0.2.262.1.10.2.9"];
		[oid setObject:@"electronicOrder" forKey:@"0.2.262.1.10.2.10"];
		[oid setObject:@"telesecTtpAsymmetricApplication" forKey:@"0.2.262.1.10.2.11"];
		[oid setObject:@"telesecTtpBasisApplication" forKey:@"0.2.262.1.10.2.12"];
		[oid setObject:@"telesecTtpMessages" forKey:@"0.2.262.1.10.2.13"];
		[oid setObject:@"telesecTtpTimeStampApplication" forKey:@"0.2.262.1.10.2.14"];
		[oid setObject:@"objectClass" forKey:@"0.2.262.1.10.3"];
		[oid setObject:@"telesecOtherName" forKey:@"0.2.262.1.10.3.0"];
		[oid setObject:@"directory" forKey:@"0.2.262.1.10.3.1"];
		[oid setObject:@"directoryType" forKey:@"0.2.262.1.10.3.2"];
		[oid setObject:@"directoryGroup" forKey:@"0.2.262.1.10.3.3"];
		[oid setObject:@"directoryUser" forKey:@"0.2.262.1.10.3.4"];
		[oid setObject:@"symmetricKeyEntry" forKey:@"0.2.262.1.10.3.5"];
		[oid setObject:@"package" forKey:@"0.2.262.1.10.4"];
		[oid setObject:@"parameter" forKey:@"0.2.262.1.10.5"];
		[oid setObject:@"nameBinding" forKey:@"0.2.262.1.10.6"];
		[oid setObject:@"attribute" forKey:@"0.2.262.1.10.7"];
		[oid setObject:@"applicationGroupIdentifier" forKey:@"0.2.262.1.10.7.0"];
		[oid setObject:@"certificateType" forKey:@"0.2.262.1.10.7.1"];
		[oid setObject:@"telesecCertificate" forKey:@"0.2.262.1.10.7.2"];
		[oid setObject:@"certificateNumber" forKey:@"0.2.262.1.10.7.3"];
		[oid setObject:@"certificateRevocationList" forKey:@"0.2.262.1.10.7.4"];
		[oid setObject:@"creationDate" forKey:@"0.2.262.1.10.7.5"];
		[oid setObject:@"issuer" forKey:@"0.2.262.1.10.7.6"];
		[oid setObject:@"namingAuthority" forKey:@"0.2.262.1.10.7.7"];
		[oid setObject:@"publicKeyDirectory" forKey:@"0.2.262.1.10.7.8"];
		[oid setObject:@"securityDomain" forKey:@"0.2.262.1.10.7.9"];
		[oid setObject:@"subject" forKey:@"0.2.262.1.10.7.10"];
		[oid setObject:@"timeOfRevocation" forKey:@"0.2.262.1.10.7.11"];
		[oid setObject:@"userGroupReference" forKey:@"0.2.262.1.10.7.12"];
		[oid setObject:@"validity" forKey:@"0.2.262.1.10.7.13"];
		[oid setObject:@"zert93" forKey:@"0.2.262.1.10.7.14"];
		[oid setObject:@"securityMessEnv" forKey:@"0.2.262.1.10.7.15"];
		[oid setObject:@"anonymizedPublicKeyDirectory" forKey:@"0.2.262.1.10.7.16"];
		[oid setObject:@"telesecGivenName" forKey:@"0.2.262.1.10.7.17"];
		[oid setObject:@"nameAdditions" forKey:@"0.2.262.1.10.7.18"];
		[oid setObject:@"telesecPostalCode" forKey:@"0.2.262.1.10.7.19"];
		[oid setObject:@"nameDistinguisher" forKey:@"0.2.262.1.10.7.20"];
		[oid setObject:@"telesecCertificateList" forKey:@"0.2.262.1.10.7.21"];
		[oid setObject:@"teletrustCertificateList" forKey:@"0.2.262.1.10.7.22"];
		[oid setObject:@"x509CertificateList" forKey:@"0.2.262.1.10.7.23"];
		[oid setObject:@"timeOfIssue" forKey:@"0.2.262.1.10.7.24"];
		[oid setObject:@"physicalCardNumber" forKey:@"0.2.262.1.10.7.25"];
		[oid setObject:@"fileType" forKey:@"0.2.262.1.10.7.26"];
		[oid setObject:@"ctlFileIsArchive" forKey:@"0.2.262.1.10.7.27"];
		[oid setObject:@"emailAddress" forKey:@"0.2.262.1.10.7.28"];
		[oid setObject:@"certificateTemplateList" forKey:@"0.2.262.1.10.7.29"];
		[oid setObject:@"directoryName" forKey:@"0.2.262.1.10.7.30"];
		[oid setObject:@"directoryTypeName" forKey:@"0.2.262.1.10.7.31"];
		[oid setObject:@"directoryGroupName" forKey:@"0.2.262.1.10.7.32"];
		[oid setObject:@"directoryUserName" forKey:@"0.2.262.1.10.7.33"];
		[oid setObject:@"revocationFlag" forKey:@"0.2.262.1.10.7.34"];
		[oid setObject:@"symmetricKeyEntryName" forKey:@"0.2.262.1.10.7.35"];
		[oid setObject:@"glNumber" forKey:@"0.2.262.1.10.7.36"];
		[oid setObject:@"goNumber" forKey:@"0.2.262.1.10.7.37"];
		[oid setObject:@"gKeyData" forKey:@"0.2.262.1.10.7.38"];
		[oid setObject:@"zKeyData" forKey:@"0.2.262.1.10.7.39"];
		[oid setObject:@"ktKeyData" forKey:@"0.2.262.1.10.7.40"];
		[oid setObject:@"ktKeyNumber" forKey:@"0.2.262.1.10.7.41"];
		[oid setObject:@"timeOfRevocationGen" forKey:@"0.2.262.1.10.7.51"];
		[oid setObject:@"liabilityText" forKey:@"0.2.262.1.10.7.52"];
		[oid setObject:@"attributeGroup" forKey:@"0.2.262.1.10.8"];
		[oid setObject:@"action" forKey:@"0.2.262.1.10.9"];
		[oid setObject:@"notification" forKey:@"0.2.262.1.10.10"];
		[oid setObject:@"snmp-mibs" forKey:@"0.2.262.1.10.11"];
		[oid setObject:@"securityApplication" forKey:@"0.2.262.1.10.11.1"];
		[oid setObject:@"certAndCrlExtensionDefinitions" forKey:@"0.2.262.1.10.12"];
		[oid setObject:@"certExtensionLiabilityLimitationExt" forKey:@"0.2.262.1.10.12.0"];
		[oid setObject:@"telesecCertIdExt" forKey:@"0.2.262.1.10.12.1"];
		[oid setObject:@"Telesec policyIdentifier" forKey:@"0.2.262.1.10.12.2"];
		[oid setObject:@"telesecPolicyQualifierID" forKey:@"0.2.262.1.10.12.3"];
		[oid setObject:@"telesecCRLFilteredExt" forKey:@"0.2.262.1.10.12.4"];
		[oid setObject:@"telesecCRLFilterExt" forKey:@"0.2.262.1.10.12.5"];
		[oid setObject:@"telesecNamingAuthorityExt" forKey:@"0.2.262.1.10.12.6"];
		[oid setObject:@"userID" forKey:@"0.9.2342.19200300.100.1.1"];
		[oid setObject:@"rfc822Mailbox" forKey:@"0.9.2342.19200300.100.1.3"];
		[oid setObject:@"domainComponent" forKey:@"0.9.2342.19200300.100.1.25"];
		[oid setObject:@"australianBusinessNumber" forKey:@"1.2.36.1.333.1"];
		[oid setObject:@"Certificates Australia policyIdentifier" forKey:@"1.2.36.75878867.1.100.1.1"];
		[oid setObject:@"Signet personal" forKey:@"1.2.36.68980861.1.1.2"];
		[oid setObject:@"Signet business" forKey:@"1.2.36.68980861.1.1.3"];
		[oid setObject:@"Signet legal" forKey:@"1.2.36.68980861.1.1.4"];
		[oid setObject:@"Signet pilot" forKey:@"1.2.36.68980861.1.1.10"];
		[oid setObject:@"Signet intraNet" forKey:@"1.2.36.68980861.1.1.11"];
		[oid setObject:@"Signet policyIdentifier" forKey:@"1.2.36.68980861.1.1.20"];
		[oid setObject:@"symmetric-encryption-algorithm" forKey:@"1.2.392.200011.61.1.1.1"];
		[oid setObject:@"misty1-cbc" forKey:@"1.2.392.200011.61.1.1.1.1"];
		[oid setObject:@"seis-cp" forKey:@"1.2.752.34.1"];
		[oid setObject:@"SEIS high-assurance policyIdentifier" forKey:@"1.2.752.34.1.1"];
		[oid setObject:@"SEIS GAK policyIdentifier" forKey:@"1.2.752.34.1.2"];
		[oid setObject:@"SEIS pe" forKey:@"1.2.752.34.2"];
		[oid setObject:@"SEIS at" forKey:@"1.2.752.34.3"];
		[oid setObject:@"SEIS at-personalIdentifier" forKey:@"1.2.752.34.3.1"];
		[oid setObject:@"module" forKey:@"1.2.840.10040.1"];
		[oid setObject:@"x9f1-cert-mgmt" forKey:@"1.2.840.10040.1.1"];
		[oid setObject:@"holdinstruction" forKey:@"1.2.840.10040.2"];
		[oid setObject:@"holdinstruction-none" forKey:@"1.2.840.10040.2.1"];
		[oid setObject:@"callissuer" forKey:@"1.2.840.10040.2.2"];
		[oid setObject:@"reject" forKey:@"1.2.840.10040.2.3"];
		[oid setObject:@"pickupToken" forKey:@"1.2.840.10040.2.4"];
		[oid setObject:@"attribute" forKey:@"1.2.840.10040.3"];
		[oid setObject:@"countersignature" forKey:@"1.2.840.10040.3.1"];
		[oid setObject:@"attribute-cert" forKey:@"1.2.840.10040.3.2"];
		[oid setObject:@"algorithm" forKey:@"1.2.840.10040.4"];
		[oid setObject:@"dsa" forKey:@"1.2.840.10040.4.1"];
		[oid setObject:@"dsa-match" forKey:@"1.2.840.10040.4.2"];
		[oid setObject:@"dsaWithSha1" forKey:@"1.2.840.10040.4.3"];
		[oid setObject:@"fieldType" forKey:@"1.2.840.10045.1"];
		[oid setObject:@"prime-field" forKey:@"1.2.840.10045.1.1"];
		[oid setObject:@"characteristic-two-field" forKey:@"1.2.840.10045.1.2"];
		[oid setObject:@"characteristic-two-basis" forKey:@"1.2.840.10045.1.2.3"];
		[oid setObject:@"onBasis" forKey:@"1.2.840.10045.1.2.3.1"];
		[oid setObject:@"tpBasis" forKey:@"1.2.840.10045.1.2.3.2"];
		[oid setObject:@"ppBasis" forKey:@"1.2.840.10045.1.2.3.3"];
		[oid setObject:@"publicKeyType" forKey:@"1.2.840.10045.2"];
		[oid setObject:@"ecPublicKey" forKey:@"1.2.840.10045.2.1"];
		[oid setObject:@"fieldType" forKey:@"1.2.840.10046.1"];
		[oid setObject:@"gf-prime" forKey:@"1.2.840.10046.1.1"];
		[oid setObject:@"numberType" forKey:@"1.2.840.10046.2"];
		[oid setObject:@"dhPublicKey" forKey:@"1.2.840.10046.2.1"];
		[oid setObject:@"scheme" forKey:@"1.2.840.10046.3"];
		[oid setObject:@"dhStatic" forKey:@"1.2.840.10046.3.1"];
		[oid setObject:@"dhEphem" forKey:@"1.2.840.10046.3.2"];
		[oid setObject:@"dhHybrid1" forKey:@"1.2.840.10046.3.3"];
		[oid setObject:@"dhHybrid2" forKey:@"1.2.840.10046.3.4"];
		[oid setObject:@"mqv2" forKey:@"1.2.840.10046.3.5"];
		[oid setObject:@"mqv1" forKey:@"1.2.840.10046.3.6"];
		[oid setObject:@"?" forKey:@"1.2.840.10065.2.2"];
		[oid setObject:@"healthcareLicense" forKey:@"1.2.840.10065.2.3"];
		[oid setObject:@"license?" forKey:@"1.2.840.10065.2.3.1.1"];
		[oid setObject:@"nsn" forKey:@"1.2.840.113533.7"];
		[oid setObject:@"nsn-ce" forKey:@"1.2.840.113533.7.65"];
		[oid setObject:@"entrustVersInfo" forKey:@"1.2.840.113533.7.65.0"];
		[oid setObject:@"nsn-alg" forKey:@"1.2.840.113533.7.66"];
		[oid setObject:@"cast3CBC" forKey:@"1.2.840.113533.7.66.3"];
		[oid setObject:@"cast5CBC" forKey:@"1.2.840.113533.7.66.10"];
		[oid setObject:@"cast5MAC" forKey:@"1.2.840.113533.7.66.11"];
		[oid setObject:@"pbeWithMD5AndCAST5-CBC" forKey:@"1.2.840.113533.7.66.12"];
		[oid setObject:@"passwordBasedMac" forKey:@"1.2.840.113533.7.66.13"];
		[oid setObject:@"nsn-oc" forKey:@"1.2.840.113533.7.67"];
		[oid setObject:@"entrustUser" forKey:@"1.2.840.113533.7.67.0"];
		[oid setObject:@"nsn-at" forKey:@"1.2.840.113533.7.68"];
		[oid setObject:@"entrustCAInfo" forKey:@"1.2.840.113533.7.68.0"];
		[oid setObject:@"attributeCertificate" forKey:@"1.2.840.113533.7.68.10"];
		[oid setObject:@"pkcs-1" forKey:@"1.2.840.113549.1.1"];
		[oid setObject:@"rsaEncryption" forKey:@"1.2.840.113549.1.1.1"];
		[oid setObject:@"md2withRSAEncryption" forKey:@"1.2.840.113549.1.1.2"];
		[oid setObject:@"md4withRSAEncryption" forKey:@"1.2.840.113549.1.1.3"];
		[oid setObject:@"md5withRSAEncryption" forKey:@"1.2.840.113549.1.1.4"];
		[oid setObject:@"sha1withRSAEncryption" forKey:@"1.2.840.113549.1.1.5"];
		[oid setObject:@"rsaOAEP" forKey:@"1.2.840.113549.1.1.7"];
		[oid setObject:@"rsaOAEP-MGF" forKey:@"1.2.840.113549.1.1.8"];
		[oid setObject:@"rsaOAEP-pSpecified" forKey:@"1.2.840.113549.1.1.9"];
		[oid setObject:@"rsaPSS" forKey:@"1.2.840.113549.1.1.10"];
		[oid setObject:@"sha256WithRSAEncryption" forKey:@"1.2.840.113549.1.1.11"];
		[oid setObject:@"sha384WithRSAEncryption" forKey:@"1.2.840.113549.1.1.12"];
		[oid setObject:@"sha512WithRSAEncryption" forKey:@"1.2.840.113549.1.1.13"];
		[oid setObject:@"rsaOAEPEncryptionSET" forKey:@"1.2.840.113549.1.1.6"];
		[oid setObject:@"bsafeRsaEncr" forKey:@"1.2.840.113549.1.2"];
		[oid setObject:@"dhKeyAgreement" forKey:@"1.2.840.113549.1.3.1"];
		[oid setObject:@"pbeWithMD2AndDES-CBC" forKey:@"1.2.840.113549.1.5.1"];
		[oid setObject:@"pbeWithMD5AndDES-CBC" forKey:@"1.2.840.113549.1.5.3"];
		[oid setObject:@"pbeWithMD2AndRC2-CBC" forKey:@"1.2.840.113549.1.5.4"];
		[oid setObject:@"pbeWithMD5AndRC2-CBC" forKey:@"1.2.840.113549.1.5.6"];
		[oid setObject:@"pbeWithMD5AndXOR" forKey:@"1.2.840.113549.1.5.9"];
		[oid setObject:@"pbeWithSHAAndDES-CBC" forKey:@"1.2.840.113549.1.5.10"];
		[oid setObject:@"pkcs5PBKDF2" forKey:@"1.2.840.113549.1.5.12"];
		[oid setObject:@"pkcs5PBES2" forKey:@"1.2.840.113549.1.5.13"];
		[oid setObject:@"pkcs5PBMAC1" forKey:@"1.2.840.113549.1.5.14"];
		[oid setObject:@"data" forKey:@"1.2.840.113549.1.7.1"];
		[oid setObject:@"signedData" forKey:@"1.2.840.113549.1.7.2"];
		[oid setObject:@"envelopedData" forKey:@"1.2.840.113549.1.7.3"];
		[oid setObject:@"signedAndEnvelopedData" forKey:@"1.2.840.113549.1.7.4"];
		[oid setObject:@"digestedData" forKey:@"1.2.840.113549.1.7.5"];
		[oid setObject:@"encryptedData" forKey:@"1.2.840.113549.1.7.6"];
		[oid setObject:@"dataWithAttributes" forKey:@"1.2.840.113549.1.7.7"];
		[oid setObject:@"encryptedPrivateKeyInfo" forKey:@"1.2.840.113549.1.7.8"];
		[oid setObject:@"pkcs-9" forKey:@"1.2.840.113549.1.9"];
		[oid setObject:@"emailAddress" forKey:@"1.2.840.113549.1.9.1"];
		[oid setObject:@"unstructuredName" forKey:@"1.2.840.113549.1.9.2"];
		[oid setObject:@"contentType" forKey:@"1.2.840.113549.1.9.3"];
		[oid setObject:@"messageDigest" forKey:@"1.2.840.113549.1.9.4"];
		[oid setObject:@"signingTime" forKey:@"1.2.840.113549.1.9.5"];
		[oid setObject:@"countersignature" forKey:@"1.2.840.113549.1.9.6"];
		[oid setObject:@"challengePassword" forKey:@"1.2.840.113549.1.9.7"];
		[oid setObject:@"unstructuredAddress" forKey:@"1.2.840.113549.1.9.8"];
		[oid setObject:@"extendedCertificateAttributes" forKey:@"1.2.840.113549.1.9.9"];
		[oid setObject:@"issuerAndSerialNumber" forKey:@"1.2.840.113549.1.9.10"];
		[oid setObject:@"passwordCheck" forKey:@"1.2.840.113549.1.9.11"];
		[oid setObject:@"publicKey" forKey:@"1.2.840.113549.1.9.12"];
		[oid setObject:@"signingDescription" forKey:@"1.2.840.113549.1.9.13"];
		[oid setObject:@"extensionRequest" forKey:@"1.2.840.113549.1.9.14"];
		[oid setObject:@"sMIMECapabilities" forKey:@"1.2.840.113549.1.9.15"];
		[oid setObject:@"preferSignedData" forKey:@"1.2.840.113549.1.9.15.1"];
		[oid setObject:@"canNotDecryptAny" forKey:@"1.2.840.113549.1.9.15.2"];
		[oid setObject:@"receiptRequest" forKey:@"1.2.840.113549.1.9.15.3"];
		[oid setObject:@"receipt" forKey:@"1.2.840.113549.1.9.15.4"];
		[oid setObject:@"contentHints" forKey:@"1.2.840.113549.1.9.15.5"];
		[oid setObject:@"mlExpansionHistory" forKey:@"1.2.840.113549.1.9.15.6"];
		[oid setObject:@"id-sMIME" forKey:@"1.2.840.113549.1.9.16"];
		[oid setObject:@"id-mod" forKey:@"1.2.840.113549.1.9.16.0"];
		[oid setObject:@"id-mod-cms" forKey:@"1.2.840.113549.1.9.16.0.1"];
		[oid setObject:@"id-mod-ess" forKey:@"1.2.840.113549.1.9.16.0.2"];
		[oid setObject:@"id-mod-oid" forKey:@"1.2.840.113549.1.9.16.0.3"];
		[oid setObject:@"id-mod-msg-v3" forKey:@"1.2.840.113549.1.9.16.0.4"];
		[oid setObject:@"id-mod-ets-eSignature-88" forKey:@"1.2.840.113549.1.9.16.0.5"];
		[oid setObject:@"id-mod-ets-eSignature-97" forKey:@"1.2.840.113549.1.9.16.0.6"];
		[oid setObject:@"id-mod-ets-eSigPolicy-88" forKey:@"1.2.840.113549.1.9.16.0.7"];
		[oid setObject:@"id-mod-ets-eSigPolicy-88" forKey:@"1.2.840.113549.1.9.16.0.8"];
		[oid setObject:@"contentType" forKey:@"1.2.840.113549.1.9.16.1"];
		[oid setObject:@"receipt" forKey:@"1.2.840.113549.1.9.16.1.1"];
		[oid setObject:@"authData" forKey:@"1.2.840.113549.1.9.16.1.2"];
		[oid setObject:@"publishCert" forKey:@"1.2.840.113549.1.9.16.1.3"];
		[oid setObject:@"tSTInfo" forKey:@"1.2.840.113549.1.9.16.1.4"];
		[oid setObject:@"tDTInfo" forKey:@"1.2.840.113549.1.9.16.1.5"];
		[oid setObject:@"contentInfo" forKey:@"1.2.840.113549.1.9.16.1.6"];
		[oid setObject:@"dVCSRequestData" forKey:@"1.2.840.113549.1.9.16.1.7"];
		[oid setObject:@"dVCSResponseData" forKey:@"1.2.840.113549.1.9.16.1.8"];
		[oid setObject:@"compressedData" forKey:@"1.2.840.113549.1.9.16.1.9"];
		[oid setObject:@"authenticatedAttributes" forKey:@"1.2.840.113549.1.9.16.2"];
		[oid setObject:@"receiptRequest" forKey:@"1.2.840.113549.1.9.16.2.1"];
		[oid setObject:@"securityLabel" forKey:@"1.2.840.113549.1.9.16.2.2"];
		[oid setObject:@"mlExpandHistory" forKey:@"1.2.840.113549.1.9.16.2.3"];
		[oid setObject:@"contentHint" forKey:@"1.2.840.113549.1.9.16.2.4"];
		[oid setObject:@"msgSigDigest" forKey:@"1.2.840.113549.1.9.16.2.5"];
		[oid setObject:@"encapContentType" forKey:@"1.2.840.113549.1.9.16.2.6"];
		[oid setObject:@"contentIdentifier" forKey:@"1.2.840.113549.1.9.16.2.7"];
		[oid setObject:@"macValue" forKey:@"1.2.840.113549.1.9.16.2.8"];
		[oid setObject:@"equivalentLabels" forKey:@"1.2.840.113549.1.9.16.2.9"];
		[oid setObject:@"contentReference" forKey:@"1.2.840.113549.1.9.16.2.10"];
		[oid setObject:@"encrypKeyPref" forKey:@"1.2.840.113549.1.9.16.2.11"];
		[oid setObject:@"signingCertificate" forKey:@"1.2.840.113549.1.9.16.2.12"];
		[oid setObject:@"smimeEncryptCerts" forKey:@"1.2.840.113549.1.9.16.2.13"];
		[oid setObject:@"timeStampToken" forKey:@"1.2.840.113549.1.9.16.2.14"];
		[oid setObject:@"ets-sigPolicyId" forKey:@"1.2.840.113549.1.9.16.2.15"];
		[oid setObject:@"ets-commitmentType" forKey:@"1.2.840.113549.1.9.16.2.16"];
		[oid setObject:@"ets-signerLocation" forKey:@"1.2.840.113549.1.9.16.2.17"];
		[oid setObject:@"ets-signerAttr" forKey:@"1.2.840.113549.1.9.16.2.18"];
		[oid setObject:@"ets-otherSigCert" forKey:@"1.2.840.113549.1.9.16.2.19"];
		[oid setObject:@"ets-contentTimestamp" forKey:@"1.2.840.113549.1.9.16.2.20"];
		[oid setObject:@"ets-CertificateRefs" forKey:@"1.2.840.113549.1.9.16.2.21"];
		[oid setObject:@"ets-RevocationRefs" forKey:@"1.2.840.113549.1.9.16.2.22"];
		[oid setObject:@"ets-certValues" forKey:@"1.2.840.113549.1.9.16.2.23"];
		[oid setObject:@"ets-revocationValues" forKey:@"1.2.840.113549.1.9.16.2.24"];
		[oid setObject:@"ets-escTimeStamp" forKey:@"1.2.840.113549.1.9.16.2.25"];
		[oid setObject:@"ets-certCRLTimestamp" forKey:@"1.2.840.113549.1.9.16.2.26"];
		[oid setObject:@"ets-archiveTimeStamp" forKey:@"1.2.840.113549.1.9.16.2.27"];
		[oid setObject:@"signatureType" forKey:@"1.2.840.113549.1.9.16.2.28"];
		[oid setObject:@"dvcs-dvc" forKey:@"1.2.840.113549.1.9.16.2.29"];
		[oid setObject:@"algESDHwith3DES" forKey:@"1.2.840.113549.1.9.16.3.1"];
		[oid setObject:@"algESDHwithRC2" forKey:@"1.2.840.113549.1.9.16.3.2"];
		[oid setObject:@"alg3DESwrap" forKey:@"1.2.840.113549.1.9.16.3.3"];
		[oid setObject:@"algRC2wrap" forKey:@"1.2.840.113549.1.9.16.3.4"];
		[oid setObject:@"esDH" forKey:@"1.2.840.113549.1.9.16.3.5"];
		[oid setObject:@"cms3DESwrap" forKey:@"1.2.840.113549.1.9.16.3.6"];
		[oid setObject:@"cmsRC2wrap" forKey:@"1.2.840.113549.1.9.16.3.7"];
		[oid setObject:@"zlib" forKey:@"1.2.840.113549.1.9.16.3.8"];
		[oid setObject:@"pwri-KEK" forKey:@"1.2.840.113549.1.9.16.3.9"];
		[oid setObject:@"certDist-ldap" forKey:@"1.2.840.113549.1.9.16.4.1"];
		[oid setObject:@"sigPolicyQualifier-ets-sqt-uri" forKey:@"1.2.840.113549.1.9.16.5.1"];
		[oid setObject:@"sigPolicyQualifier-ets-sqt-unotice" forKey:@"1.2.840.113549.1.9.16.5.2"];
		[oid setObject:@"id-cti-ets-proofOfOrigin" forKey:@"1.2.840.113549.1.9.16.6.1"];
		[oid setObject:@"id-cti-ets-proofOfReceipt" forKey:@"1.2.840.113549.1.9.16.6.2"];
		[oid setObject:@"id-cti-ets-proofOfDelivery" forKey:@"1.2.840.113549.1.9.16.6.3"];
		[oid setObject:@"id-cti-ets-proofOfSender" forKey:@"1.2.840.113549.1.9.16.6.4"];
		[oid setObject:@"id-cti-ets-proofOfApproval" forKey:@"1.2.840.113549.1.9.16.6.5"];
		[oid setObject:@"id-cti-ets-proofOfCreation" forKey:@"1.2.840.113549.1.9.16.6.6"];
		[oid setObject:@"sMIMECapabilities" forKey:@"1.2.840.113549.1.9.15"];
		[oid setObject:@"signatureTypeIdentifier" forKey:@"1.2.840.113549.1.9.16.9"];
		[oid setObject:@"originatorSig" forKey:@"1.2.840.113549.1.9.16.9.1"];
		[oid setObject:@"domainSig" forKey:@"1.2.840.113549.1.9.16.9.2"];
		[oid setObject:@"additionalAttributesSig" forKey:@"1.2.840.113549.1.9.16.9.3"];
		[oid setObject:@"reviewSig" forKey:@"1.2.840.113549.1.9.16.9.4"];
		[oid setObject:@"capabilities" forKey:@"1.2.840.113549.1.9.16.11"];
		[oid setObject:@"preferBinaryInside" forKey:@"1.2.840.113549.1.9.16.11.1"];
		[oid setObject:@"friendlyName (for PKCS #12)" forKey:@"1.2.840.113549.1.9.20"];
		[oid setObject:@"localKeyID (for PKCS #12)" forKey:@"1.2.840.113549.1.9.21"];
		[oid setObject:@"certTypes (for PKCS #12)" forKey:@"1.2.840.113549.1.9.22"];
		[oid setObject:@"x509Certificate (for PKCS #12)" forKey:@"1.2.840.113549.1.9.22.1"];
		[oid setObject:@"sdsiCertificate (for PKCS #12)" forKey:@"1.2.840.113549.1.9.22.2"];
		[oid setObject:@"crlTypes (for PKCS #12)" forKey:@"1.2.840.113549.1.9.23"];
		[oid setObject:@"x509Crl (for PKCS #12)" forKey:@"1.2.840.113549.1.9.23.1"];
		[oid setObject:@"pkcs9objectClass" forKey:@"1.2.840.113549.1.9.24"];
		[oid setObject:@"pkcs9attributes" forKey:@"1.2.840.113549.1.9.25"];
		[oid setObject:@"pkcs15Token" forKey:@"1.2.840.113549.1.9.25.1"];
		[oid setObject:@"encryptedPrivateKeyInfo" forKey:@"1.2.840.113549.1.9.25.2"];
		[oid setObject:@"randomNonce" forKey:@"1.2.840.113549.1.9.25.3"];
		[oid setObject:@"sequenceNumber" forKey:@"1.2.840.113549.1.9.25.4"];
		[oid setObject:@"pkcs7PDU" forKey:@"1.2.840.113549.1.9.25.5"];
		[oid setObject:@"pkcs9syntax" forKey:@"1.2.840.113549.1.9.1A"];
		[oid setObject:@"pkcs9matchingRules" forKey:@"1.2.840.113549.1.9.1B"];
		[oid setObject:@"pkcs-12" forKey:@"1.2.840.113549.1.12"];
		[oid setObject:@"pkcs-12-PbeIds" forKey:@"1.2.840.113549.1.12.1"];
		[oid setObject:@"pbeWithSHAAnd128BitRC4" forKey:@"1.2.840.113549.1.12.1.1"];
		[oid setObject:@"pbeWithSHAAnd40BitRC4" forKey:@"1.2.840.113549.1.12.1.2"];
		[oid setObject:@"pbeWithSHAAnd3-KeyTripleDES-CBC" forKey:@"1.2.840.113549.1.12.1.3"];
		[oid setObject:@"pbeWithSHAAnd2-KeyTripleDES-CBC" forKey:@"1.2.840.113549.1.12.1.4"];
		[oid setObject:@"pbeWithSHAAnd128BitRC2-CBC" forKey:@"1.2.840.113549.1.12.1.5"];
		[oid setObject:@"pbeWithSHAAnd40BitRC2-CBC" forKey:@"1.2.840.113549.1.12.1.6"];
		[oid setObject:@"pkcs-12-ESPVKID" forKey:@"1.2.840.113549.1.12.2"];
		[oid setObject:@"pkcs-12-PKCS8KeyShrouding" forKey:@"1.2.840.113549.1.12.2.1"];
		[oid setObject:@"pkcs-12-BagIds" forKey:@"1.2.840.113549.1.12.3"];
		[oid setObject:@"pkcs-12-keyBagId" forKey:@"1.2.840.113549.1.12.3.1"];
		[oid setObject:@"pkcs-12-certAndCRLBagId" forKey:@"1.2.840.113549.1.12.3.2"];
		[oid setObject:@"pkcs-12-secretBagId" forKey:@"1.2.840.113549.1.12.3.3"];
		[oid setObject:@"pkcs-12-safeContentsId" forKey:@"1.2.840.113549.1.12.3.4"];
		[oid setObject:@"pkcs-12-pkcs-8ShroudedKeyBagId" forKey:@"1.2.840.113549.1.12.3.5"];
		[oid setObject:@"pkcs-12-CertBagID" forKey:@"1.2.840.113549.1.12.4"];
		[oid setObject:@"pkcs-12-X509CertCRLBagID" forKey:@"1.2.840.113549.1.12.4.1"];
		[oid setObject:@"pkcs-12-SDSICertBagID" forKey:@"1.2.840.113549.1.12.4.2"];
		[oid setObject:@"pkcs-12-PBEID" forKey:@"1.2.840.113549.1.12.5.1"];
		[oid setObject:@"pkcs-12-PBEWithSha1And128BitRC4" forKey:@"1.2.840.113549.1.12.5.1.1"];
		[oid setObject:@"pkcs-12-PBEWithSha1And40BitRC4" forKey:@"1.2.840.113549.1.12.5.1.2"];
		[oid setObject:@"pkcs-12-PBEWithSha1AndTripleDESCBC" forKey:@"1.2.840.113549.1.12.5.1.3"];
		[oid setObject:@"pkcs-12-PBEWithSha1And128BitRC2CBC" forKey:@"1.2.840.113549.1.12.5.1.4"];
		[oid setObject:@"pkcs-12-PBEWithSha1And40BitRC2CBC" forKey:@"1.2.840.113549.1.12.5.1.5"];
		[oid setObject:@"pkcs-12-PBEWithSha1AndRC4" forKey:@"1.2.840.113549.1.12.5.1.6"];
		[oid setObject:@"pkcs-12-PBEWithSha1AndRC2CBC" forKey:@"1.2.840.113549.1.12.5.1.7"];
		[oid setObject:@"pkcs-12-RSAEncryptionWith128BitRC4" forKey:@"1.2.840.113549.1.12.5.2.1"];
		[oid setObject:@"pkcs-12-RSAEncryptionWith40BitRC4" forKey:@"1.2.840.113549.1.12.5.2.2"];
		[oid setObject:@"pkcs-12-RSAEncryptionWithTripleDES" forKey:@"1.2.840.113549.1.12.5.2.3"];
		[oid setObject:@"pkcs-12-RSASignatureWithSHA1Digest" forKey:@"1.2.840.113549.1.12.5.3.1"];
		[oid setObject:@"pkcs-12-keyBag" forKey:@"1.2.840.113549.1.12.10.1.1"];
		[oid setObject:@"pkcs-12-pkcs-8ShroudedKeyBag" forKey:@"1.2.840.113549.1.12.10.1.2"];
		[oid setObject:@"pkcs-12-certBag" forKey:@"1.2.840.113549.1.12.10.1.3"];
		[oid setObject:@"pkcs-12-crlBag" forKey:@"1.2.840.113549.1.12.10.1.4"];
		[oid setObject:@"pkcs-12-secretBag" forKey:@"1.2.840.113549.1.12.10.1.5"];
		[oid setObject:@"pkcs-12-safeContentsBag" forKey:@"1.2.840.113549.1.12.10.1.6"];
		[oid setObject:@"pkcs15modules" forKey:@"1.2.840.113549.1.15.1"];
		[oid setObject:@"pkcs15attributes" forKey:@"1.2.840.113549.1.15.2"];
		[oid setObject:@"pkcs15contentType" forKey:@"1.2.840.113549.1.15.3"];
		[oid setObject:@"pkcs15content" forKey:@"1.2.840.113549.1.15.3.1"];
		[oid setObject:@"md2" forKey:@"1.2.840.113549.2.2"];
		[oid setObject:@"md4" forKey:@"1.2.840.113549.2.4"];
		[oid setObject:@"md5" forKey:@"1.2.840.113549.2.5"];
		[oid setObject:@"hmacWithSHA1" forKey:@"1.2.840.113549.2.7"];
		[oid setObject:@"rc2CBC" forKey:@"1.2.840.113549.3.2"];
		[oid setObject:@"rc2ECB" forKey:@"1.2.840.113549.3.3"];
		[oid setObject:@"rc4" forKey:@"1.2.840.113549.3.4"];
		[oid setObject:@"rc4WithMAC" forKey:@"1.2.840.113549.3.5"];
		[oid setObject:@"desx-CBC" forKey:@"1.2.840.113549.3.6"];
		[oid setObject:@"des-EDE3-CBC" forKey:@"1.2.840.113549.3.7"];
		[oid setObject:@"rc5CBC" forKey:@"1.2.840.113549.3.8"];
		[oid setObject:@"rc5-CBCPad" forKey:@"1.2.840.113549.3.9"];
		[oid setObject:@"desCDMF" forKey:@"1.2.840.113549.3.10"];
		[oid setObject:@"Identrus unknown policyIdentifier" forKey:@"1.2.840.114021.1.6.1"];
		[oid setObject:@"identrusOCSP" forKey:@"1.2.840.114021.4.1"];
		[oid setObject:@"site-Addressing" forKey:@"1.2.840.113556.1.3.00"];
		[oid setObject:@"classSchema" forKey:@"1.2.840.113556.1.3.13"];
		[oid setObject:@"attributeSchema" forKey:@"1.2.840.113556.1.3.14"];
		[oid setObject:@"mailbox-Agent" forKey:@"1.2.840.113556.1.3.174"];
		[oid setObject:@"mailbox" forKey:@"1.2.840.113556.1.3.22"];
		[oid setObject:@"container" forKey:@"1.2.840.113556.1.3.23"];
		[oid setObject:@"mailRecipient" forKey:@"1.2.840.113556.1.3.46"];
		[oid setObject:@"deliveryMechanism" forKey:@"1.2.840.113556.1.2.241"];
		[oid setObject:@"microsoftExcel" forKey:@"1.2.840.113556.4.3"];
		[oid setObject:@"titledWithOID" forKey:@"1.2.840.113556.4.4"];
		[oid setObject:@"microsoftPowerPoint" forKey:@"1.2.840.113556.4.5"];
		[oid setObject:@"spcIndirectDataContext" forKey:@"1.3.6.1.4.1.311.2.1.4"];
		[oid setObject:@"spcAgencyInfo" forKey:@"1.3.6.1.4.1.311.2.1.10"];
		[oid setObject:@"spcStatementType" forKey:@"1.3.6.1.4.1.311.2.1.11"];
		[oid setObject:@"spcSpOpusInfo" forKey:@"1.3.6.1.4.1.311.2.1.12"];
		[oid setObject:@"certReqExtensions" forKey:@"1.3.6.1.4.1.311.2.1.14"];
		[oid setObject:@"spcPEImageData" forKey:@"1.3.6.1.4.1.311.2.1.15"];
		[oid setObject:@"spcRawFileData" forKey:@"1.3.6.1.4.1.311.2.1.18"];
		[oid setObject:@"spcStructuredStorageData" forKey:@"1.3.6.1.4.1.311.2.1.19"];
		[oid setObject:@"spcJavaClassData (type 1)" forKey:@"1.3.6.1.4.1.311.2.1.20"];
		[oid setObject:@"individualCodeSigning" forKey:@"1.3.6.1.4.1.311.2.1.21"];
		[oid setObject:@"commercialCodeSigning" forKey:@"1.3.6.1.4.1.311.2.1.22"];
		[oid setObject:@"spcLink (type 2)" forKey:@"1.3.6.1.4.1.311.2.1.25"];
		[oid setObject:@"spcMinimalCriteriaInfo" forKey:@"1.3.6.1.4.1.311.2.1.26"];
		[oid setObject:@"spcFinancialCriteriaInfo" forKey:@"1.3.6.1.4.1.311.2.1.27"];
		[oid setObject:@"spcLink (type 3)" forKey:@"1.3.6.1.4.1.311.2.1.28"];
		[oid setObject:@"timestampRequest" forKey:@"1.3.6.1.4.1.311.3.2.1"];
		[oid setObject:@"certTrustList" forKey:@"1.3.6.1.4.1.311.10.1"];
		[oid setObject:@"nextUpdateLocation" forKey:@"1.3.6.1.4.1.311.10.2"];
		[oid setObject:@"certTrustListSigning" forKey:@"1.3.6.1.4.1.311.10.3.1"];
		[oid setObject:@"timeStampSigning" forKey:@"1.3.6.1.4.1.311.10.3.2"];
		[oid setObject:@"serverGatedCrypto" forKey:@"1.3.6.1.4.1.311.10.3.3"];
		[oid setObject:@"encryptedFileSystem" forKey:@"1.3.6.1.4.1.311.10.3.4"];
		[oid setObject:@"yesnoTrustAttr" forKey:@"1.3.6.1.4.1.311.10.4.1"];
		[oid setObject:@"enrolmentCSP" forKey:@"1.3.6.1.4.1.311.13.2.2"];
		[oid setObject:@"osVersion" forKey:@"1.3.6.1.4.1.311.13.2.3"];
		[oid setObject:@"microsoftRecipientInfo" forKey:@"1.3.6.1.4.1.311.16.4"];
		[oid setObject:@"cAKeyCertIndexPair" forKey:@"1.3.6.1.4.1.311.21.1"];
		[oid setObject:@"originalFilename" forKey:@"1.3.6.1.4.1.311.88.2.1"];
		[oid setObject:@"ascom" forKey:@"1.3.6.1.4.1.188.7.1.1"];
		[oid setObject:@"ideaECB" forKey:@"1.3.6.1.4.1.188.7.1.1.1"];
		[oid setObject:@"ideaCBC" forKey:@"1.3.6.1.4.1.188.7.1.1.2"];
		[oid setObject:@"ideaCFB" forKey:@"1.3.6.1.4.1.188.7.1.1.3"];
		[oid setObject:@"ideaOFB" forKey:@"1.3.6.1.4.1.188.7.1.1.4"];
		[oid setObject:@"UNINETT policyIdentifier" forKey:@"1.3.6.1.4.1.2428.10.1.1"];
		[oid setObject:@"ICE-TEL policyIdentifier" forKey:@"1.3.6.1.4.1.2712.10"];
		[oid setObject:@"ICE-TEL Italian policyIdentifier" forKey:@"1.3.6.1.4.1.2786.1.1.1"];
		[oid setObject:@"blowfishECB" forKey:@"1.3.6.1.4.1.3029.1.1.1"];
		[oid setObject:@"blowfishCBC" forKey:@"1.3.6.1.4.1.3029.1.1.2"];
		[oid setObject:@"blowfishCFB" forKey:@"1.3.6.1.4.1.3029.1.1.3"];
		[oid setObject:@"blowfishOFB" forKey:@"1.3.6.1.4.1.3029.1.1.4"];
		[oid setObject:@"elgamal" forKey:@"1.3.6.1.4.1.3029.1.2.1"];
		[oid setObject:@"elgamalWithSHA-1" forKey:@"1.3.6.1.4.1.3029.1.2.1.1"];
		[oid setObject:@"elgamalWithRIPEMD-160" forKey:@"1.3.6.1.4.1.3029.1.2.1.2"];
		[oid setObject:@"cryptlibPresenceCheck" forKey:@"1.3.6.1.4.1.3029.3.1.1"];
		[oid setObject:@"ocspResponseRTCS" forKey:@"1.3.6.1.4.1.3029.3.1.2"];
		[oid setObject:@"ocspResponseRTCSExtended" forKey:@"1.3.6.1.4.1.3029.3.1.3"];
		[oid setObject:@"crlExtReason" forKey:@"1.3.6.1.4.1.3029.3.1.4"];
		[oid setObject:@"keyFeatures" forKey:@"1.3.6.1.4.1.3029.3.1.5"];
		[oid setObject:@"pkiBoot" forKey:@"1.3.6.1.4.1.3029.3.1.6"];
		[oid setObject:@"cryptlibContent" forKey:@"1.3.6.1.4.1.3029.4.1"];
		[oid setObject:@"cryptlibConfigData" forKey:@"1.3.6.1.4.1.3029.4.1.1"];
		[oid setObject:@"cryptlibUserIndex" forKey:@"1.3.6.1.4.1.3029.4.1.2"];
		[oid setObject:@"cryptlibUserInfo" forKey:@"1.3.6.1.4.1.3029.4.1.3"];
		[oid setObject:@"mpeg-1" forKey:@"1.3.6.1.4.1.3029.42.11172.1"];
		[oid setObject:@"xYZZY policyIdentifier" forKey:@"1.3.6.1.4.1.3029.88.89.90.90.89"];
		[oid setObject:@"eciaAscX12Edi" forKey:@"1.3.6.1.4.1.3576.7"];
		[oid setObject:@"plainEDImessage" forKey:@"1.3.6.1.4.1.3576.7.1"];
		[oid setObject:@"signedEDImessage" forKey:@"1.3.6.1.4.1.3576.7.2"];
		[oid setObject:@"integrityEDImessage" forKey:@"1.3.6.1.4.1.3576.7.5"];
		[oid setObject:@"iaReceiptMessage" forKey:@"1.3.6.1.4.1.3576.7.65"];
		[oid setObject:@"iaStatusMessage" forKey:@"1.3.6.1.4.1.3576.7.97"];
		[oid setObject:@"eciaEdifact" forKey:@"1.3.6.1.4.1.3576.8"];
		[oid setObject:@"eciaNonEdi" forKey:@"1.3.6.1.4.1.3576.9"];
		[oid setObject:@"timeproof" forKey:@"1.3.6.1.4.1.5472"];
		[oid setObject:@"tss" forKey:@"1.3.6.1.4.1.5472.1"];
		[oid setObject:@"tss80" forKey:@"1.3.6.1.4.1.5472.1.1"];
		[oid setObject:@"tss380" forKey:@"1.3.6.1.4.1.5472.1.2"];
		[oid setObject:@"tss400" forKey:@"1.3.6.1.4.1.5472.1.3"];
		[oid setObject:@"secondaryPractices" forKey:@"1.3.6.1.4.1.5770.0.3"];
		[oid setObject:@"physicianIdentifiers" forKey:@"1.3.6.1.4.1.5770.0.4"];
		[oid setObject:@"comodoPolicy" forKey:@"1.3.6.1.4.1.6449.1.2.1.3.1"];
		[oid setObject:@"rolUnicoNacional" forKey:@"1.3.6.1.4.1.8231.1"];
		[oid setObject:@"gnu" forKey:@"1.3.6.1.4.1.11591"];
		[oid setObject:@"gnu-radius" forKey:@"1.3.6.1.4.1.11591.1"];
		[oid setObject:@"gnu-radar" forKey:@"1.3.6.1.4.1.11591.3"];
		[oid setObject:@"gnuDigestAlgorithm" forKey:@"1.3.6.1.4.1.11591.12"];
		[oid setObject:@"tiger" forKey:@"1.3.6.1.4.1.11591.12.2"];
		[oid setObject:@"gnuEncryptionAlgorithm" forKey:@"1.3.6.1.4.1.11591.13"];
		[oid setObject:@"serpent" forKey:@"1.3.6.1.4.1.11591.13.2"];
		[oid setObject:@"serpent128-ECB" forKey:@"1.3.6.1.4.1.11591.13.2.1"];
		[oid setObject:@"serpent128-CBC" forKey:@"1.3.6.1.4.1.11591.13.2.2"];
		[oid setObject:@"serpent128-OFB" forKey:@"1.3.6.1.4.1.11591.13.2.3"];
		[oid setObject:@"serpent128-CFB" forKey:@"1.3.6.1.4.1.11591.13.2.4"];
		[oid setObject:@"serpent192-ECB" forKey:@"1.3.6.1.4.1.11591.13.2.21"];
		[oid setObject:@"serpent192-CBC" forKey:@"1.3.6.1.4.1.11591.13.2.22"];
		[oid setObject:@"serpent192-OFB" forKey:@"1.3.6.1.4.1.11591.13.2.23"];
		[oid setObject:@"serpent192-CFB" forKey:@"1.3.6.1.4.1.11591.13.2.24"];
		[oid setObject:@"serpent256-ECB" forKey:@"1.3.6.1.4.1.11591.13.2.41"];
		[oid setObject:@"serpent256-CBC" forKey:@"1.3.6.1.4.1.11591.13.2.42"];
		[oid setObject:@"serpent256-OFB" forKey:@"1.3.6.1.4.1.11591.13.2.43"];
		[oid setObject:@"serpent256-CFB" forKey:@"1.3.6.1.4.1.11591.13.2.44"];
		[oid setObject:@"pkix" forKey:@"1.3.6.1.5.5.7"];
		[oid setObject:@"attributeCert" forKey:@"1.3.6.1.5.5.7.0.12"];
		[oid setObject:@"privateExtension" forKey:@"1.3.6.1.5.5.7.1"];
		[oid setObject:@"authorityInfoAccess" forKey:@"1.3.6.1.5.5.7.1.1"];
		[oid setObject:@"biometricInfo" forKey:@"1.3.6.1.5.5.7.1.2"];
		[oid setObject:@"qcStatements" forKey:@"1.3.6.1.5.5.7.1.3"];
		[oid setObject:@"acAuditIdentity" forKey:@"1.3.6.1.5.5.7.1.4"];
		[oid setObject:@"acTargeting" forKey:@"1.3.6.1.5.5.7.1.5"];
		[oid setObject:@"acAaControls" forKey:@"1.3.6.1.5.5.7.1.6"];
		[oid setObject:@"sbgp-ipAddrBlock" forKey:@"1.3.6.1.5.5.7.1.7"];
		[oid setObject:@"sbgp-autonomousSysNum" forKey:@"1.3.6.1.5.5.7.1.8"];
		[oid setObject:@"sbgp-routerIdentifier" forKey:@"1.3.6.1.5.5.7.1.9"];
		[oid setObject:@"acProxying" forKey:@"1.3.6.1.5.5.7.1.10"];
		[oid setObject:@"subjectInfoAccess" forKey:@"1.3.6.1.5.5.7.1.11"];
		[oid setObject:@"policyQualifierIds" forKey:@"1.3.6.1.5.5.7.2"];
		[oid setObject:@"cps" forKey:@"1.3.6.1.5.5.7.2.1"];
		[oid setObject:@"unotice" forKey:@"1.3.6.1.5.5.7.2.2"];
		[oid setObject:@"textNotice" forKey:@"1.3.6.1.5.5.7.2.3"];
		[oid setObject:@"keyPurpose" forKey:@"1.3.6.1.5.5.7.3"];
		[oid setObject:@"serverAuth" forKey:@"1.3.6.1.5.5.7.3.1"];
		[oid setObject:@"clientAuth" forKey:@"1.3.6.1.5.5.7.3.2"];
		[oid setObject:@"codeSigning" forKey:@"1.3.6.1.5.5.7.3.3"];
		[oid setObject:@"emailProtection" forKey:@"1.3.6.1.5.5.7.3.4"];
		[oid setObject:@"ipsecEndSystem" forKey:@"1.3.6.1.5.5.7.3.5"];
		[oid setObject:@"ipsecTunnel" forKey:@"1.3.6.1.5.5.7.3.6"];
		[oid setObject:@"ipsecUser" forKey:@"1.3.6.1.5.5.7.3.7"];
		[oid setObject:@"timeStamping" forKey:@"1.3.6.1.5.5.7.3.8"];
		[oid setObject:@"ocspSigning" forKey:@"1.3.6.1.5.5.7.3.9"];
		[oid setObject:@"dvcs" forKey:@"1.3.6.1.5.5.7.3.10"];
		[oid setObject:@"sbgpCertAAServerAuth" forKey:@"1.3.6.1.5.5.7.3.11"];
		[oid setObject:@"eapOverPPP" forKey:@"1.3.6.1.5.5.7.3.13"];
		[oid setObject:@"wlanSSID" forKey:@"1.3.6.1.5.5.7.3.14"];
		[oid setObject:@"cmpInformationTypes" forKey:@"1.3.6.1.5.5.7.4"];
		[oid setObject:@"caProtEncCert" forKey:@"1.3.6.1.5.5.7.4.1"];
		[oid setObject:@"signKeyPairTypes" forKey:@"1.3.6.1.5.5.7.4.2"];
		[oid setObject:@"encKeyPairTypes" forKey:@"1.3.6.1.5.5.7.4.3"];
		[oid setObject:@"preferredSymmAlg" forKey:@"1.3.6.1.5.5.7.4.4"];
		[oid setObject:@"caKeyUpdateInfo" forKey:@"1.3.6.1.5.5.7.4.5"];
		[oid setObject:@"currentCRL" forKey:@"1.3.6.1.5.5.7.4.6"];
		[oid setObject:@"unsupportedOIDs" forKey:@"1.3.6.1.5.5.7.4.7"];
		[oid setObject:@"keyPairParamReq" forKey:@"1.3.6.1.5.5.7.4.10"];
		[oid setObject:@"keyPairParamRep" forKey:@"1.3.6.1.5.5.7.4.11"];
		[oid setObject:@"revPassphrase" forKey:@"1.3.6.1.5.5.7.4.12"];
		[oid setObject:@"implicitConfirm" forKey:@"1.3.6.1.5.5.7.4.13"];
		[oid setObject:@"confirmWaitTime" forKey:@"1.3.6.1.5.5.7.4.14"];
		[oid setObject:@"origPKIMessage" forKey:@"1.3.6.1.5.5.7.4.15"];
		[oid setObject:@"suppLangTags" forKey:@"1.3.6.1.5.5.7.4.16"];
		[oid setObject:@"crmfRegistration" forKey:@"1.3.6.1.5.5.7.5"];
		[oid setObject:@"regCtrl" forKey:@"1.3.6.1.5.5.7.5.1"];
		[oid setObject:@"regToken" forKey:@"1.3.6.1.5.5.7.5.1.1"];
		[oid setObject:@"authenticator" forKey:@"1.3.6.1.5.5.7.5.1.2"];
		[oid setObject:@"pkiPublicationInfo" forKey:@"1.3.6.1.5.5.7.5.1.3"];
		[oid setObject:@"pkiArchiveOptions" forKey:@"1.3.6.1.5.5.7.5.1.4"];
		[oid setObject:@"oldCertID" forKey:@"1.3.6.1.5.5.7.5.1.5"];
		[oid setObject:@"protocolEncrKey" forKey:@"1.3.6.1.5.5.7.5.1.6"];
		[oid setObject:@"altCertTemplate" forKey:@"1.3.6.1.5.5.7.5.1.7"];
		[oid setObject:@"wtlsTemplate" forKey:@"1.3.6.1.5.5.7.5.1.8"];
		[oid setObject:@"utf8Pairs" forKey:@"1.3.6.1.5.5.7.5.2.1"];
		[oid setObject:@"certReq" forKey:@"1.3.6.1.5.5.7.5.2.2"];
		[oid setObject:@"algorithms" forKey:@"1.3.6.1.5.5.7.6"];
		[oid setObject:@"des40" forKey:@"1.3.6.1.5.5.7.6.1"];
		[oid setObject:@"noSignature" forKey:@"1.3.6.1.5.5.7.6.2"];
		[oid setObject:@"dh-sig-hmac-sha1" forKey:@"1.3.6.1.5.5.7.6.3"];
		[oid setObject:@"dh-pop" forKey:@"1.3.6.1.5.5.7.6.4"];
		[oid setObject:@"cmcControls" forKey:@"1.3.6.1.5.5.7.7"];
		[oid setObject:@"otherNames" forKey:@"1.3.6.1.5.5.7.8"];
		[oid setObject:@"personalData" forKey:@"1.3.6.1.5.5.7.8.1"];
		[oid setObject:@"userGroup" forKey:@"1.3.6.1.5.5.7.8.2"];
		[oid setObject:@"personalData" forKey:@"1.3.6.1.5.5.7.9"];
		[oid setObject:@"dateOfBirth" forKey:@"1.3.6.1.5.5.7.9.1"];
		[oid setObject:@"placeOfBirth" forKey:@"1.3.6.1.5.5.7.9.2"];
		[oid setObject:@"gender" forKey:@"1.3.6.1.5.5.7.9.3"];
		[oid setObject:@"countryOfCitizenship" forKey:@"1.3.6.1.5.5.7.9.4"];
		[oid setObject:@"countryOfResidence" forKey:@"1.3.6.1.5.5.7.9.5"];
		[oid setObject:@"attributeCertificate" forKey:@"1.3.6.1.5.5.7.10"];
		[oid setObject:@"authenticationInfo" forKey:@"1.3.6.1.5.5.7.10.1"];
		[oid setObject:@"accessIdentity" forKey:@"1.3.6.1.5.5.7.10.2"];
		[oid setObject:@"chargingIdentity" forKey:@"1.3.6.1.5.5.7.10.3"];
		[oid setObject:@"group" forKey:@"1.3.6.1.5.5.7.10.4"];
		[oid setObject:@"role" forKey:@"1.3.6.1.5.5.7.10.5"];
		[oid setObject:@"encAttrs" forKey:@"1.3.6.1.5.5.7.10.6"];
		[oid setObject:@"personalData" forKey:@"1.3.6.1.5.5.7.11"];
		[oid setObject:@"pkixQCSyntax-v1" forKey:@"1.3.6.1.5.5.7.11.1"];
		[oid setObject:@"ocsp" forKey:@"1.3.6.1.5.5.7.48.1"];
		[oid setObject:@"ocspBasic" forKey:@"1.3.6.1.5.5.7.48.1.1"];
		[oid setObject:@"ocspNonce" forKey:@"1.3.6.1.5.5.7.48.1.2"];
		[oid setObject:@"ocspCRL" forKey:@"1.3.6.1.5.5.7.48.1.3"];
		[oid setObject:@"ocspResponse" forKey:@"1.3.6.1.5.5.7.48.1.4"];
		[oid setObject:@"ocspNoCheck" forKey:@"1.3.6.1.5.5.7.48.1.5"];
		[oid setObject:@"ocspArchiveCutoff" forKey:@"1.3.6.1.5.5.7.48.1.6"];
		[oid setObject:@"ocspServiceLocator" forKey:@"1.3.6.1.5.5.7.48.1.7"];
		[oid setObject:@"caIssuers" forKey:@"1.3.6.1.5.5.7.48.2"];
		[oid setObject:@"timeStamping" forKey:@"1.3.6.1.5.5.7.48.3"];
		[oid setObject:@"caRepository" forKey:@"1.3.6.1.5.5.7.48.5"];
		[oid setObject:@"hmacMD5" forKey:@"1.3.6.1.5.5.8.1.1"];
		[oid setObject:@"hmacSHA" forKey:@"1.3.6.1.5.5.8.1.2"];
		[oid setObject:@"hmacTiger" forKey:@"1.3.6.1.5.5.8.1.3"];
		[oid setObject:@"iKEIntermediate" forKey:@"1.3.6.1.5.5.8.2.2"];
		[oid setObject:@"decEncryptionAlgorithm" forKey:@"1.3.12.2.1011.7.1"];
		[oid setObject:@"decDEA" forKey:@"1.3.12.2.1011.7.1.2"];
		[oid setObject:@"decHashAlgorithm" forKey:@"1.3.12.2.1011.7.2"];
		[oid setObject:@"decMD2" forKey:@"1.3.12.2.1011.7.2.1"];
		[oid setObject:@"decMD4" forKey:@"1.3.12.2.1011.7.2.2"];
		[oid setObject:@"decSignatureAlgorithm" forKey:@"1.3.12.2.1011.7.3"];
		[oid setObject:@"decMD2withRSA" forKey:@"1.3.12.2.1011.7.3.1"];
		[oid setObject:@"decMD4withRSA" forKey:@"1.3.12.2.1011.7.3.2"];
		[oid setObject:@"decDEAMAC" forKey:@"1.3.12.2.1011.7.3.3"];
		[oid setObject:@"sha" forKey:@"1.3.14.2.26.5"];
		[oid setObject:@"rsa" forKey:@"1.3.14.3.2.1.1"];
		[oid setObject:@"md4WitRSA" forKey:@"1.3.14.3.2.2"];
		[oid setObject:@"md5WithRSA" forKey:@"1.3.14.3.2.3"];
		[oid setObject:@"md4WithRSAEncryption" forKey:@"1.3.14.3.2.4"];
		[oid setObject:@"sqmod-N" forKey:@"1.3.14.3.2.2.1"];
		[oid setObject:@"sqmod-NwithRSA" forKey:@"1.3.14.3.2.3.1"];
		[oid setObject:@"desECB" forKey:@"1.3.14.3.2.6"];
		[oid setObject:@"desCBC" forKey:@"1.3.14.3.2.7"];
		[oid setObject:@"desOFB" forKey:@"1.3.14.3.2.8"];
		[oid setObject:@"desCFB" forKey:@"1.3.14.3.2.9"];
		[oid setObject:@"desMAC" forKey:@"1.3.14.3.2.10"];
		[oid setObject:@"rsaSignature" forKey:@"1.3.14.3.2.11"];
		[oid setObject:@"dsa" forKey:@"1.3.14.3.2.12"];
		[oid setObject:@"dsaWithSHA" forKey:@"1.3.14.3.2.13"];
		[oid setObject:@"mdc2WithRSASignature" forKey:@"1.3.14.3.2.14"];
		[oid setObject:@"shaWithRSASignature" forKey:@"1.3.14.3.2.15"];
		[oid setObject:@"dhWithCommonModulus" forKey:@"1.3.14.3.2.16"];
		[oid setObject:@"desEDE" forKey:@"1.3.14.3.2.17"];
		[oid setObject:@"sha" forKey:@"1.3.14.3.2.18"];
		[oid setObject:@"mdc-2" forKey:@"1.3.14.3.2.19"];
		[oid setObject:@"dsaCommon" forKey:@"1.3.14.3.2.20"];
		[oid setObject:@"dsaCommonWithSHA" forKey:@"1.3.14.3.2.21"];
		[oid setObject:@"rsaKeyTransport" forKey:@"1.3.14.3.2.22"];
		[oid setObject:@"keyed-hash-seal" forKey:@"1.3.14.3.2.23"];
		[oid setObject:@"md2WithRSASignature" forKey:@"1.3.14.3.2.24"];
		[oid setObject:@"md5WithRSASignature" forKey:@"1.3.14.3.2.25"];
		[oid setObject:@"sha1" forKey:@"1.3.14.3.2.26"];
		[oid setObject:@"dsaWithSHA1" forKey:@"1.3.14.3.2.27"];
		[oid setObject:@"dsaWithCommonSHA1" forKey:@"1.3.14.3.2.28"];
		[oid setObject:@"sha-1WithRSAEncryption" forKey:@"1.3.14.3.2.29"];
		[oid setObject:@"simple-strong-auth-mechanism" forKey:@"1.3.14.3.3.1"];
		[oid setObject:@"ElGamal" forKey:@"1.3.14.7.2.1.1"];
		[oid setObject:@"md2WithRSA" forKey:@"1.3.14.7.2.3.1"];
		[oid setObject:@"md2WithElGamal" forKey:@"1.3.14.7.2.3.2"];
		[oid setObject:@"document" forKey:@"1.3.36.1"];
		[oid setObject:@"finalVersion" forKey:@"1.3.36.1.1"];
		[oid setObject:@"draft" forKey:@"1.3.36.1.2"];
		[oid setObject:@"sio" forKey:@"1.3.36.2"];
		[oid setObject:@"sedu" forKey:@"1.3.36.2.1"];
		[oid setObject:@"algorithm" forKey:@"1.3.36.3"];
		[oid setObject:@"encryptionAlgorithm" forKey:@"1.3.36.3.1"];
		[oid setObject:@"des" forKey:@"1.3.36.3.1.1"];
		[oid setObject:@"desECB_pad" forKey:@"1.3.36.3.1.1.1"];
		[oid setObject:@"desECB_ISOpad" forKey:@"1.3.36.3.1.1.1.1"];
		[oid setObject:@"desCBC_pad" forKey:@"1.3.36.3.1.1.2.1"];
		[oid setObject:@"desCBC_ISOpad" forKey:@"1.3.36.3.1.1.2.1.1"];
		[oid setObject:@"des_3" forKey:@"1.3.36.3.1.3"];
		[oid setObject:@"des_3ECB_pad" forKey:@"1.3.36.3.1.3.1.1"];
		[oid setObject:@"des_3ECB_ISOpad" forKey:@"1.3.36.3.1.3.1.1.1"];
		[oid setObject:@"des_3CBC_pad" forKey:@"1.3.36.3.1.3.2.1"];
		[oid setObject:@"des_3CBC_ISOpad" forKey:@"1.3.36.3.1.3.2.1.1"];
		[oid setObject:@"idea" forKey:@"1.3.36.3.1.2"];
		[oid setObject:@"ideaECB" forKey:@"1.3.36.3.1.2.1"];
		[oid setObject:@"ideaECB_pad" forKey:@"1.3.36.3.1.2.1.1"];
		[oid setObject:@"ideaECB_ISOpad" forKey:@"1.3.36.3.1.2.1.1.1"];
		[oid setObject:@"ideaCBC" forKey:@"1.3.36.3.1.2.2"];
		[oid setObject:@"ideaCBC_pad" forKey:@"1.3.36.3.1.2.2.1"];
		[oid setObject:@"ideaCBC_ISOpad" forKey:@"1.3.36.3.1.2.2.1.1"];
		[oid setObject:@"ideaOFB" forKey:@"1.3.36.3.1.2.3"];
		[oid setObject:@"ideaCFB" forKey:@"1.3.36.3.1.2.4"];
		[oid setObject:@"rsaEncryption" forKey:@"1.3.36.3.1.4"];
		[oid setObject:@"rsaEncryptionWithlmod512expe17" forKey:@"1.3.36.3.1.4.512.17"];
		[oid setObject:@"bsi-1" forKey:@"1.3.36.3.1.5"];
		[oid setObject:@"bsi_1ECB_pad" forKey:@"1.3.36.3.1.5.1"];
		[oid setObject:@"bsi_1CBC_pad" forKey:@"1.3.36.3.1.5.2"];
		[oid setObject:@"bsi_1CBC_PEMpad" forKey:@"1.3.36.3.1.5.2.1"];
		[oid setObject:@"hashAlgorithm" forKey:@"1.3.36.3.2"];
		[oid setObject:@"ripemd160" forKey:@"1.3.36.3.2.1"];
		[oid setObject:@"ripemd128" forKey:@"1.3.36.3.2.2"];
		[oid setObject:@"ripemd256" forKey:@"1.3.36.3.2.3"];
		[oid setObject:@"mdc2singleLength" forKey:@"1.3.36.3.2.4"];
		[oid setObject:@"mdc2doubleLength" forKey:@"1.3.36.3.2.5"];
		[oid setObject:@"signatureAlgorithm" forKey:@"1.3.36.3.3"];
		[oid setObject:@"rsaSignature" forKey:@"1.3.36.3.3.1"];
		[oid setObject:@"rsaSignatureWithsha1" forKey:@"1.3.36.3.3.1.1"];
		[oid setObject:@"rsaSignatureWithsha1_l512_l2" forKey:@"1.3.36.3.3.1.1.512.2"];
		[oid setObject:@"rsaSignatureWithsha1_l640_l2" forKey:@"1.3.36.3.3.1.1.640.2"];
		[oid setObject:@"rsaSignatureWithsha1_l768_l2" forKey:@"1.3.36.3.3.1.1.768.2"];
		[oid setObject:@"rsaSignatureWithsha1_l896_l2" forKey:@"1.3.36.3.3.1.1.892.2"];
		[oid setObject:@"rsaSignatureWithsha1_l1024_l2" forKey:@"1.3.36.3.3.1.1.1024.2"];
		[oid setObject:@"rsaSignatureWithsha1_l512_l3" forKey:@"1.3.36.3.3.1.1.512.3"];
		[oid setObject:@"rsaSignatureWithsha1_l640_l3" forKey:@"1.3.36.3.3.1.1.640.3"];
		[oid setObject:@"rsaSignatureWithsha1_l768_l3" forKey:@"1.3.36.3.3.1.1.768.3"];
		[oid setObject:@"rsaSignatureWithsha1_l896_l3" forKey:@"1.3.36.3.3.1.1.896.3"];
		[oid setObject:@"rsaSignatureWithsha1_l1024_l3" forKey:@"1.3.36.3.3.1.1.1024.3"];
		[oid setObject:@"rsaSignatureWithsha1_l512_l5" forKey:@"1.3.36.3.3.1.1.512.5"];
		[oid setObject:@"rsaSignatureWithsha1_l640_l5" forKey:@"1.3.36.3.3.1.1.640.5"];
		[oid setObject:@"rsaSignatureWithsha1_l768_l5" forKey:@"1.3.36.3.3.1.1.768.5"];
		[oid setObject:@"rsaSignatureWithsha1_l896_l5" forKey:@"1.3.36.3.3.1.1.896.5"];
		[oid setObject:@"rsaSignatureWithsha1_l1024_l5" forKey:@"1.3.36.3.3.1.1.1024.5"];
		[oid setObject:@"rsaSignatureWithsha1_l512_l9" forKey:@"1.3.36.3.3.1.1.512.9"];
		[oid setObject:@"rsaSignatureWithsha1_l640_l9" forKey:@"1.3.36.3.3.1.1.640.9"];
		[oid setObject:@"rsaSignatureWithsha1_l768_l9" forKey:@"1.3.36.3.3.1.1.768.9"];
		[oid setObject:@"rsaSignatureWithsha1_l896_l9" forKey:@"1.3.36.3.3.1.1.896.9"];
		[oid setObject:@"rsaSignatureWithsha1_l1024_l9" forKey:@"1.3.36.3.3.1.1.1024.9"];
		[oid setObject:@"rsaSignatureWithsha1_l512_l11" forKey:@"1.3.36.3.3.1.1.512.11"];
		[oid setObject:@"rsaSignatureWithsha1_l640_l11" forKey:@"1.3.36.3.3.1.1.640.11"];
		[oid setObject:@"rsaSignatureWithsha1_l768_l11" forKey:@"1.3.36.3.3.1.1.768.11"];
		[oid setObject:@"rsaSignatureWithsha1_l896_l11" forKey:@"1.3.36.3.3.1.1.896.11"];
		[oid setObject:@"rsaSignatureWithsha1_l1024_l11" forKey:@"1.3.36.3.3.1.1.1024.11"];
		[oid setObject:@"rsaSignatureWithripemd160" forKey:@"1.3.36.3.3.1.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l512_l2" forKey:@"1.3.36.3.3.1.2.512.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l640_l2" forKey:@"1.3.36.3.3.1.2.640.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l768_l2" forKey:@"1.3.36.3.3.1.2.768.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l896_l2" forKey:@"1.3.36.3.3.1.2.892.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l1024_l2" forKey:@"1.3.36.3.3.1.2.1024.2"];
		[oid setObject:@"rsaSignatureWithripemd160_l512_l3" forKey:@"1.3.36.3.3.1.2.512.3"];
		[oid setObject:@"rsaSignatureWithripemd160_l640_l3" forKey:@"1.3.36.3.3.1.2.640.3"];
		[oid setObject:@"rsaSignatureWithripemd160_l768_l3" forKey:@"1.3.36.3.3.1.2.768.3"];
		[oid setObject:@"rsaSignatureWithripemd160_l896_l3" forKey:@"1.3.36.3.3.1.2.896.3"];
		[oid setObject:@"rsaSignatureWithripemd160_l1024_l3" forKey:@"1.3.36.3.3.1.2.1024.3"];
		[oid setObject:@"rsaSignatureWithripemd160_l512_l5" forKey:@"1.3.36.3.3.1.2.512.5"];
		[oid setObject:@"rsaSignatureWithripemd160_l640_l5" forKey:@"1.3.36.3.3.1.2.640.5"];
		[oid setObject:@"rsaSignatureWithripemd160_l768_l5" forKey:@"1.3.36.3.3.1.2.768.5"];
		[oid setObject:@"rsaSignatureWithripemd160_l896_l5" forKey:@"1.3.36.3.3.1.2.896.5"];
		[oid setObject:@"rsaSignatureWithripemd160_l1024_l5" forKey:@"1.3.36.3.3.1.2.1024.5"];
		[oid setObject:@"rsaSignatureWithripemd160_l512_l9" forKey:@"1.3.36.3.3.1.2.512.9"];
		[oid setObject:@"rsaSignatureWithripemd160_l640_l9" forKey:@"1.3.36.3.3.1.2.640.9"];
		[oid setObject:@"rsaSignatureWithripemd160_l768_l9" forKey:@"1.3.36.3.3.1.2.768.9"];
		[oid setObject:@"rsaSignatureWithripemd160_l896_l9" forKey:@"1.3.36.3.3.1.2.896.9"];
		[oid setObject:@"rsaSignatureWithripemd160_l1024_l9" forKey:@"1.3.36.3.3.1.2.1024.9"];
		[oid setObject:@"rsaSignatureWithripemd160_l512_l11" forKey:@"1.3.36.3.3.1.2.512.11"];
		[oid setObject:@"rsaSignatureWithripemd160_l640_l11" forKey:@"1.3.36.3.3.1.2.640.11"];
		[oid setObject:@"rsaSignatureWithripemd160_l768_l11" forKey:@"1.3.36.3.3.1.2.768.11"];
		[oid setObject:@"rsaSignatureWithripemd160_l896_l11" forKey:@"1.3.36.3.3.1.2.896.11"];
		[oid setObject:@"rsaSignatureWithripemd160_l1024_l11" forKey:@"1.3.36.3.3.1.2.1024.11"];
		[oid setObject:@"rsaSignatureWithrimpemd128" forKey:@"1.3.36.3.3.1.3"];
		[oid setObject:@"rsaSignatureWithrimpemd256" forKey:@"1.3.36.3.3.1.4"];
		[oid setObject:@"ecsieSign" forKey:@"1.3.36.3.3.2"];
		[oid setObject:@"ecsieSignWithsha1" forKey:@"1.3.36.3.3.2.1"];
		[oid setObject:@"ecsieSignWithripemd160" forKey:@"1.3.36.3.3.2.2"];
		[oid setObject:@"ecsieSignWithmd2" forKey:@"1.3.36.3.3.2.3"];
		[oid setObject:@"ecsieSignWithmd5" forKey:@"1.3.36.3.3.2.4"];
		[oid setObject:@"signatureScheme" forKey:@"1.3.36.3.4"];
		[oid setObject:@"sigS_ISO9796-1" forKey:@"1.3.36.3.4.1"];
		[oid setObject:@"sigS_ISO9796-2" forKey:@"1.3.36.3.4.2"];
		[oid setObject:@"sigS_ISO9796-2Withred" forKey:@"1.3.36.3.4.2.1"];
		[oid setObject:@"sigS_ISO9796-2Withrsa" forKey:@"1.3.36.3.4.2.2"];
		[oid setObject:@"sigS_ISO9796-2Withrnd" forKey:@"1.3.36.3.4.2.3"];
		[oid setObject:@"attribute" forKey:@"1.3.36.4"];
		[oid setObject:@"policy" forKey:@"1.3.36.5"];
		[oid setObject:@"api" forKey:@"1.3.36.6"];
		[oid setObject:@"manufacturer-specific_api" forKey:@"1.3.36.6.1"];
		[oid setObject:@"utimaco-api" forKey:@"1.3.36.6.1.1"];
		[oid setObject:@"functionality-specific_api" forKey:@"1.3.36.6.2"];
		[oid setObject:@"keymgmnt" forKey:@"1.3.36.7"];
		[oid setObject:@"keyagree" forKey:@"1.3.36.7.1"];
		[oid setObject:@"bsiPKE" forKey:@"1.3.36.7.1.1"];
		[oid setObject:@"keytrans" forKey:@"1.3.36.7.2"];
		[oid setObject:@"encISO9796-2Withrsa" forKey:@"1.3.36.7.2.1"];
		[oid setObject:@"Teletrust SigiSigConform policyIdentifier" forKey:@"1.3.36.8.1.1"];
		[oid setObject:@"directoryService" forKey:@"1.3.36.8.2.1"];
		[oid setObject:@"dateOfCertGen" forKey:@"1.3.36.8.3.1"];
		[oid setObject:@"procuration" forKey:@"1.3.36.8.3.2"];
		[oid setObject:@"admission" forKey:@"1.3.36.8.3.3"];
		[oid setObject:@"monetaryLimit" forKey:@"1.3.36.8.3.4"];
		[oid setObject:@"declarationOfMajority" forKey:@"1.3.36.8.3.5"];
		[oid setObject:@"integratedCircuitCardSerialNumber" forKey:@"1.3.36.8.3.6"];
		[oid setObject:@"pKReference" forKey:@"1.3.36.8.3.7"];
		[oid setObject:@"restriction" forKey:@"1.3.36.8.3.8"];
		[oid setObject:@"retrieveIfAllowed" forKey:@"1.3.36.8.3.9"];
		[oid setObject:@"requestedCertificate" forKey:@"1.3.36.8.3.10"];
		[oid setObject:@"namingAuthorities" forKey:@"1.3.36.8.3.11"];
		[oid setObject:@"certInDirSince" forKey:@"1.3.36.8.3.12"];
		[oid setObject:@"certHash" forKey:@"1.3.36.8.3.13"];
		[oid setObject:@"personalData" forKey:@"1.3.36.8.4.1"];
		[oid setObject:@"restriction" forKey:@"1.3.36.8.4.8"];
		[oid setObject:@"rsaIndicateSHA1" forKey:@"1.3.36.8.5.1.1.1"];
		[oid setObject:@"rsaIndicateRIPEMD160" forKey:@"1.3.36.8.5.1.1.2"];
		[oid setObject:@"rsaWithSHA1" forKey:@"1.3.36.8.5.1.1.3"];
		[oid setObject:@"rsaWithRIPEMD160" forKey:@"1.3.36.8.5.1.1.4"];
		[oid setObject:@"dsaExtended" forKey:@"1.3.36.8.5.1.2.1"];
		[oid setObject:@"dsaWithRIPEMD160" forKey:@"1.3.36.8.5.1.2.2"];
		[oid setObject:@"cert" forKey:@"1.3.36.8.6.1"];
		[oid setObject:@"certRef" forKey:@"1.3.36.8.6.2"];
		[oid setObject:@"attrCert" forKey:@"1.3.36.8.6.3"];
		[oid setObject:@"attrRef" forKey:@"1.3.36.8.6.4"];
		[oid setObject:@"fileName" forKey:@"1.3.36.8.6.5"];
		[oid setObject:@"storageTime" forKey:@"1.3.36.8.6.6"];
		[oid setObject:@"fileSize" forKey:@"1.3.36.8.6.7"];
		[oid setObject:@"location" forKey:@"1.3.36.8.6.8"];
		[oid setObject:@"sigNumber" forKey:@"1.3.36.8.6.9"];
		[oid setObject:@"autoGen" forKey:@"1.3.36.8.6.10"];
		[oid setObject:@"ptAdobeILL" forKey:@"1.3.36.8.7.1.1"];
		[oid setObject:@"ptAmiPro" forKey:@"1.3.36.8.7.1.2"];
		[oid setObject:@"ptAutoCAD" forKey:@"1.3.36.8.7.1.3"];
		[oid setObject:@"ptBinary" forKey:@"1.3.36.8.7.1.4"];
		[oid setObject:@"ptBMP" forKey:@"1.3.36.8.7.1.5"];
		[oid setObject:@"ptCGM" forKey:@"1.3.36.8.7.1.6"];
		[oid setObject:@"ptCorelCRT" forKey:@"1.3.36.8.7.1.7"];
		[oid setObject:@"ptCorelDRW" forKey:@"1.3.36.8.7.1.8"];
		[oid setObject:@"ptCorelEXC" forKey:@"1.3.36.8.7.1.9"];
		[oid setObject:@"ptCorelPHT" forKey:@"1.3.36.8.7.1.10"];
		[oid setObject:@"ptDraw" forKey:@"1.3.36.8.7.1.11"];
		[oid setObject:@"ptDVI" forKey:@"1.3.36.8.7.1.12"];
		[oid setObject:@"ptEPS" forKey:@"1.3.36.8.7.1.13"];
		[oid setObject:@"ptExcel" forKey:@"1.3.36.8.7.1.14"];
		[oid setObject:@"ptGEM" forKey:@"1.3.36.8.7.1.15"];
		[oid setObject:@"ptGIF" forKey:@"1.3.36.8.7.1.16"];
		[oid setObject:@"ptHPGL" forKey:@"1.3.36.8.7.1.17"];
		[oid setObject:@"ptJPEG" forKey:@"1.3.36.8.7.1.18"];
		[oid setObject:@"ptKodak" forKey:@"1.3.36.8.7.1.19"];
		[oid setObject:@"ptLaTeX" forKey:@"1.3.36.8.7.1.20"];
		[oid setObject:@"ptLotus" forKey:@"1.3.36.8.7.1.21"];
		[oid setObject:@"ptLotusPIC" forKey:@"1.3.36.8.7.1.22"];
		[oid setObject:@"ptMacPICT" forKey:@"1.3.36.8.7.1.23"];
		[oid setObject:@"ptMacWord" forKey:@"1.3.36.8.7.1.24"];
		[oid setObject:@"ptMSWfD" forKey:@"1.3.36.8.7.1.25"];
		[oid setObject:@"ptMSWord" forKey:@"1.3.36.8.7.1.26"];
		[oid setObject:@"ptMSWord2" forKey:@"1.3.36.8.7.1.27"];
		[oid setObject:@"ptMSWord6" forKey:@"1.3.36.8.7.1.28"];
		[oid setObject:@"ptMSWord8" forKey:@"1.3.36.8.7.1.29"];
		[oid setObject:@"ptPDF" forKey:@"1.3.36.8.7.1.30"];
		[oid setObject:@"ptPIF" forKey:@"1.3.36.8.7.1.31"];
		[oid setObject:@"ptPostscript" forKey:@"1.3.36.8.7.1.32"];
		[oid setObject:@"ptRTF" forKey:@"1.3.36.8.7.1.33"];
		[oid setObject:@"ptSCITEX" forKey:@"1.3.36.8.7.1.34"];
		[oid setObject:@"ptTAR" forKey:@"1.3.36.8.7.1.35"];
		[oid setObject:@"ptTarga" forKey:@"1.3.36.8.7.1.36"];
		[oid setObject:@"ptTeX" forKey:@"1.3.36.8.7.1.37"];
		[oid setObject:@"ptText" forKey:@"1.3.36.8.7.1.38"];
		[oid setObject:@"ptTIFF" forKey:@"1.3.36.8.7.1.39"];
		[oid setObject:@"ptTIFF-FC" forKey:@"1.3.36.8.7.1.40"];
		[oid setObject:@"ptUID" forKey:@"1.3.36.8.7.1.41"];
		[oid setObject:@"ptUUEncode" forKey:@"1.3.36.8.7.1.42"];
		[oid setObject:@"ptWMF" forKey:@"1.3.36.8.7.1.43"];
		[oid setObject:@"ptWordPerfect" forKey:@"1.3.36.8.7.1.44"];
		[oid setObject:@"ptWPGrph" forKey:@"1.3.36.8.7.1.45"];
		[oid setObject:@"thawte-ce" forKey:@"1.3.101.1.4"];
		[oid setObject:@"strongExtranet" forKey:@"1.3.101.1.4.1"];
		[oid setObject:@"objectClass" forKey:@"2.5.4.0"];
		[oid setObject:@"aliasedEntryName" forKey:@"2.5.4.1"];
		[oid setObject:@"knowledgeInformation" forKey:@"2.5.4.2"];
		[oid setObject:@"commonName" forKey:@"2.5.4.3"];
		[oid setObject:@"surname" forKey:@"2.5.4.4"];
		[oid setObject:@"serialNumber" forKey:@"2.5.4.5"];
		[oid setObject:@"countryName" forKey:@"2.5.4.6"];
		[oid setObject:@"localityName" forKey:@"2.5.4.7"];
		[oid setObject:@"collectiveLocalityName" forKey:@"2.5.4.7.1"];
		[oid setObject:@"stateOrProvinceName" forKey:@"2.5.4.8"];
		[oid setObject:@"collectiveStateOrProvinceName" forKey:@"2.5.4.8.1"];
		[oid setObject:@"streetAddress" forKey:@"2.5.4.9"];
		[oid setObject:@"collectiveStreetAddress" forKey:@"2.5.4.9.1"];
		[oid setObject:@"organizationName" forKey:@"2.5.4.10"];
		[oid setObject:@"collectiveOrganizationName" forKey:@"2.5.4.10.1"];
		[oid setObject:@"organizationalUnitName" forKey:@"2.5.4.11"];
		[oid setObject:@"collectiveOrganizationalUnitName" forKey:@"2.5.4.11.1"];
		[oid setObject:@"title" forKey:@"2.5.4.12"];
		[oid setObject:@"description" forKey:@"2.5.4.13"];
		[oid setObject:@"searchGuide" forKey:@"2.5.4.14"];
		[oid setObject:@"businessCategory" forKey:@"2.5.4.15"];
		[oid setObject:@"postalAddress" forKey:@"2.5.4.16"];
		[oid setObject:@"collectivePostalAddress" forKey:@"2.5.4.16.1"];
		[oid setObject:@"postalCode" forKey:@"2.5.4.17"];
		[oid setObject:@"collectivePostalCode" forKey:@"2.5.4.17.1"];
		[oid setObject:@"postOfficeBox" forKey:@"2.5.4.18"];
		[oid setObject:@"collectivePostOfficeBox" forKey:@"2.5.4.18.1"];
		[oid setObject:@"physicalDeliveryOfficeName" forKey:@"2.5.4.19"];
		[oid setObject:@"collectivePhysicalDeliveryOfficeName" forKey:@"2.5.4.19.1"];
		[oid setObject:@"telephoneNumber" forKey:@"2.5.4.20"];
		[oid setObject:@"collectiveTelephoneNumber" forKey:@"2.5.4.20.1"];
		[oid setObject:@"telexNumber" forKey:@"2.5.4.21"];
		[oid setObject:@"collectiveTelexNumber" forKey:@"2.5.4.21.1"];
		[oid setObject:@"teletexTerminalIdentifier" forKey:@"2.5.4.22"];
		[oid setObject:@"collectiveTeletexTerminalIdentifier" forKey:@"2.5.4.22.1"];
		[oid setObject:@"facsimileTelephoneNumber" forKey:@"2.5.4.23"];
		[oid setObject:@"collectiveFacsimileTelephoneNumber" forKey:@"2.5.4.23.1"];
		[oid setObject:@"x121Address" forKey:@"2.5.4.24"];
		[oid setObject:@"internationalISDNNumber" forKey:@"2.5.4.25"];
		[oid setObject:@"collectiveInternationalISDNNumber" forKey:@"2.5.4.25.1"];
		[oid setObject:@"registeredAddress" forKey:@"2.5.4.26"];
		[oid setObject:@"destinationIndicator" forKey:@"2.5.4.27"];
		[oid setObject:@"preferredDeliveryMehtod" forKey:@"2.5.4.28"];
		[oid setObject:@"presentationAddress" forKey:@"2.5.4.29"];
		[oid setObject:@"supportedApplicationContext" forKey:@"2.5.4.30"];
		[oid setObject:@"member" forKey:@"2.5.4.31"];
		[oid setObject:@"owner" forKey:@"2.5.4.32"];
		[oid setObject:@"roleOccupant" forKey:@"2.5.4.33"];
		[oid setObject:@"seeAlso" forKey:@"2.5.4.34"];
		[oid setObject:@"userPassword" forKey:@"2.5.4.35"];
		[oid setObject:@"userCertificate" forKey:@"2.5.4.36"];
		[oid setObject:@"caCertificate" forKey:@"2.5.4.37"];
		[oid setObject:@"authorityRevocationList" forKey:@"2.5.4.38"];
		[oid setObject:@"certificateRevocationList" forKey:@"2.5.4.39"];
		[oid setObject:@"crossCertificatePair" forKey:@"2.5.4.40"];
		[oid setObject:@"name" forKey:@"2.5.4.41"];
		[oid setObject:@"givenName" forKey:@"2.5.4.42"];
		[oid setObject:@"initials" forKey:@"2.5.4.43"];
		[oid setObject:@"generationQualifier" forKey:@"2.5.4.44"];
		[oid setObject:@"uniqueIdentifier" forKey:@"2.5.4.45"];
		[oid setObject:@"dnQualifier" forKey:@"2.5.4.46"];
		[oid setObject:@"enhancedSearchGuide" forKey:@"2.5.4.47"];
		[oid setObject:@"protocolInformation" forKey:@"2.5.4.48"];
		[oid setObject:@"distinguishedName" forKey:@"2.5.4.49"];
		[oid setObject:@"uniqueMember" forKey:@"2.5.4.50"];
		[oid setObject:@"houseIdentifier" forKey:@"2.5.4.51"];
		[oid setObject:@"supportedAlgorithms" forKey:@"2.5.4.52"];
		[oid setObject:@"deltaRevocationList" forKey:@"2.5.4.53"];
		[oid setObject:@"dmdName" forKey:@"2.5.4.54"];
		[oid setObject:@"clearance" forKey:@"2.5.4.55"];
		[oid setObject:@"defaultDirQop" forKey:@"2.5.4.56"];
		[oid setObject:@"attributeIntegrityInfo" forKey:@"2.5.4.57"];
		[oid setObject:@"attributeCertificate" forKey:@"2.5.4.58"];
		[oid setObject:@"attributeCertificateRevocationList" forKey:@"2.5.4.59"];
		[oid setObject:@"confKeyInfo" forKey:@"2.5.4.60"];
		[oid setObject:@"aACertificate" forKey:@"2.5.4.61"];
		[oid setObject:@"attributeDescriptorCertificate" forKey:@"2.5.4.62"];
		[oid setObject:@"attributeAuthorityRevocationList" forKey:@"2.5.4.63"];
		[oid setObject:@"familyInformation" forKey:@"2.5.4.64"];
		[oid setObject:@"pseudonym" forKey:@"2.5.4.65"];
		[oid setObject:@"communicationsService" forKey:@"2.5.4.66"];
		[oid setObject:@"communicationsNetwork" forKey:@"2.5.4.67"];
		[oid setObject:@"certificationPracticeStmt" forKey:@"2.5.4.68"];
		[oid setObject:@"certificatePolicy" forKey:@"2.5.4.69"];
		[oid setObject:@"pkiPath" forKey:@"2.5.4.70"];
		[oid setObject:@"privPolicy" forKey:@"2.5.4.71"];
		[oid setObject:@"role" forKey:@"2.5.4.72"];
		[oid setObject:@"delegationPath" forKey:@"2.5.4.73"];
		[oid setObject:@"top" forKey:@"2.5.6.0"];
		[oid setObject:@"alias" forKey:@"2.5.6.1"];
		[oid setObject:@"country" forKey:@"2.5.6.2"];
		[oid setObject:@"locality" forKey:@"2.5.6.3"];
		[oid setObject:@"organization" forKey:@"2.5.6.4"];
		[oid setObject:@"organizationalUnit" forKey:@"2.5.6.5"];
		[oid setObject:@"person" forKey:@"2.5.6.6"];
		[oid setObject:@"organizationalPerson" forKey:@"2.5.6.7"];
		[oid setObject:@"organizationalRole" forKey:@"2.5.6.8"];
		[oid setObject:@"groupOfNames" forKey:@"2.5.6.9"];
		[oid setObject:@"residentialPerson" forKey:@"2.5.6.10"];
		[oid setObject:@"applicationProcess" forKey:@"2.5.6.11"];
		[oid setObject:@"applicationEntity" forKey:@"2.5.6.12"];
		[oid setObject:@"dSA" forKey:@"2.5.6.13"];
		[oid setObject:@"device" forKey:@"2.5.6.14"];
		[oid setObject:@"strongAuthenticationUser" forKey:@"2.5.6.15"];
		[oid setObject:@"certificateAuthority" forKey:@"2.5.6.16"];
		[oid setObject:@"groupOfUniqueNames" forKey:@"2.5.6.17"];
		[oid setObject:@"pkiUser" forKey:@"2.5.6.21"];
		[oid setObject:@"pkiCA" forKey:@"2.5.6.22"];
		[oid setObject:@"X.500-Algorithms" forKey:@"2.5.8"];
		[oid setObject:@"X.500-Alg-Encryption" forKey:@"2.5.8.1"];
		[oid setObject:@"rsa" forKey:@"2.5.8.1.1"];
		[oid setObject:@"accessControlScheme" forKey:@"2.5.24.1"];
		[oid setObject:@"prescriptiveACI" forKey:@"2.5.24.4"];
		[oid setObject:@"entryACI" forKey:@"2.5.24.5"];
		[oid setObject:@"subentryACI" forKey:@"2.5.24.6"];
		[oid setObject:@"createTimestamp" forKey:@"2.5.18.1"];
		[oid setObject:@"modifyTimestamp" forKey:@"2.5.18.2"];
		[oid setObject:@"creatorsName" forKey:@"2.5.18.3"];
		[oid setObject:@"modifiersName" forKey:@"2.5.18.4"];
		[oid setObject:@"administrativeRole" forKey:@"2.5.18.5"];
		[oid setObject:@"subtreeSpecification" forKey:@"2.5.18.6"];
		[oid setObject:@"collectiveExclusions" forKey:@"2.5.18.7"];
		[oid setObject:@"hasSubordinates" forKey:@"2.5.18.9"];
		[oid setObject:@"subschemaSubentry" forKey:@"2.5.18.10"];
		[oid setObject:@"authorityKeyIdentifier" forKey:@"2.5.29.1"];
		[oid setObject:@"keyAttributes" forKey:@"2.5.29.2"];
		[oid setObject:@"certificatePolicies" forKey:@"2.5.29.3"];
		[oid setObject:@"keyUsageRestriction" forKey:@"2.5.29.4"];
		[oid setObject:@"policyMapping" forKey:@"2.5.29.5"];
		[oid setObject:@"subtreesConstraint" forKey:@"2.5.29.6"];
		[oid setObject:@"subjectAltName" forKey:@"2.5.29.7"];
		[oid setObject:@"issuerAltName" forKey:@"2.5.29.8"];
		[oid setObject:@"subjectDirectoryAttributes" forKey:@"2.5.29.9"];
		[oid setObject:@"basicConstraints" forKey:@"2.5.29.10"];
		[oid setObject:@"nameConstraints" forKey:@"2.5.29.11"];
		[oid setObject:@"policyConstraints" forKey:@"2.5.29.12"];
		[oid setObject:@"basicConstraints" forKey:@"2.5.29.13"];
		[oid setObject:@"subjectKeyIdentifier" forKey:@"2.5.29.14"];
		[oid setObject:@"keyUsage" forKey:@"2.5.29.15"];
		[oid setObject:@"privateKeyUsagePeriod" forKey:@"2.5.29.16"];
		[oid setObject:@"subjectAltName" forKey:@"2.5.29.17"];
		[oid setObject:@"issuerAltName" forKey:@"2.5.29.18"];
		[oid setObject:@"basicConstraints" forKey:@"2.5.29.19"];
		[oid setObject:@"cRLNumber" forKey:@"2.5.29.20"];
		[oid setObject:@"cRLReason" forKey:@"2.5.29.21"];
		[oid setObject:@"expirationDate" forKey:@"2.5.29.22"];
		[oid setObject:@"instructionCode" forKey:@"2.5.29.23"];
		[oid setObject:@"invalidityDate" forKey:@"2.5.29.24"];
		[oid setObject:@"cRLDistributionPoints" forKey:@"2.5.29.25"];
		[oid setObject:@"issuingDistributionPoint" forKey:@"2.5.29.26"];
		[oid setObject:@"deltaCRLIndicator" forKey:@"2.5.29.27"];
		[oid setObject:@"issuingDistributionPoint" forKey:@"2.5.29.28"];
		[oid setObject:@"certificateIssuer" forKey:@"2.5.29.29"];
		[oid setObject:@"nameConstraints" forKey:@"2.5.29.30"];
		[oid setObject:@"cRLDistributionPoints" forKey:@"2.5.29.31"];
		[oid setObject:@"certificatePolicies" forKey:@"2.5.29.32"];
		[oid setObject:@"anyPolicy" forKey:@"2.5.29.32.0"];
		[oid setObject:@"policyMappings" forKey:@"2.5.29.33"];
		[oid setObject:@"policyConstraints" forKey:@"2.5.29.34"];
		[oid setObject:@"authorityKeyIdentifier" forKey:@"2.5.29.35"];
		[oid setObject:@"policyConstraints" forKey:@"2.5.29.36"];
		[oid setObject:@"extKeyUsage" forKey:@"2.5.29.37"];
		[oid setObject:@"freshestCRL" forKey:@"2.5.29.46"];
		[oid setObject:@"inhibitAnyPolicy" forKey:@"2.5.29.54"];
		[oid setObject:@"sdnsSignatureAlgorithm" forKey:@"2.16.840.1.101.2.1.1.1"];
		[oid setObject:@"fortezzaSignatureAlgorithm" forKey:@"2.16.840.1.101.2.1.1.2"];
		[oid setObject:@"sdnsConfidentialityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.3"];
		[oid setObject:@"fortezzaConfidentialityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.4"];
		[oid setObject:@"sdnsIntegrityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.5"];
		[oid setObject:@"fortezzaIntegrityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.6"];
		[oid setObject:@"sdnsTokenProtectionAlgorithm" forKey:@"2.16.840.1.101.2.1.1.7"];
		[oid setObject:@"fortezzaTokenProtectionAlgorithm" forKey:@"2.16.840.1.101.2.1.1.8"];
		[oid setObject:@"sdnsKeyManagementAlgorithm" forKey:@"2.16.840.1.101.2.1.1.9"];
		[oid setObject:@"fortezzaKeyManagementAlgorithm" forKey:@"2.16.840.1.101.2.1.1.10"];
		[oid setObject:@"sdnsKMandSigAlgorithm" forKey:@"2.16.840.1.101.2.1.1.11"];
		[oid setObject:@"fortezzaKMandSigAlgorithm" forKey:@"2.16.840.1.101.2.1.1.12"];
		[oid setObject:@"suiteASignatureAlgorithm" forKey:@"2.16.840.1.101.2.1.1.13"];
		[oid setObject:@"suiteAConfidentialityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.14"];
		[oid setObject:@"suiteAIntegrityAlgorithm" forKey:@"2.16.840.1.101.2.1.1.15"];
		[oid setObject:@"suiteATokenProtectionAlgorithm" forKey:@"2.16.840.1.101.2.1.1.16"];
		[oid setObject:@"suiteAKeyManagementAlgorithm" forKey:@"2.16.840.1.101.2.1.1.17"];
		[oid setObject:@"suiteAKMandSigAlgorithm" forKey:@"2.16.840.1.101.2.1.1.18"];
		[oid setObject:@"fortezzaUpdatedSigAlgorithm" forKey:@"2.16.840.1.101.2.1.1.19"];
		[oid setObject:@"fortezzaKMandUpdSigAlgorithms" forKey:@"2.16.840.1.101.2.1.1.20"];
		[oid setObject:@"fortezzaUpdatedIntegAlgorithm" forKey:@"2.16.840.1.101.2.1.1.21"];
		[oid setObject:@"keyExchangeAlgorithm" forKey:@"2.16.840.1.101.2.1.1.22"];
		[oid setObject:@"fortezzaWrap80Algorithm" forKey:@"2.16.840.1.101.2.1.1.23"];
		[oid setObject:@"kEAKeyEncryptionAlgorithm" forKey:@"2.16.840.1.101.2.1.1.24"];
		[oid setObject:@"rfc822MessageFormat" forKey:@"2.16.840.1.101.2.1.2.1"];
		[oid setObject:@"emptyContent" forKey:@"2.16.840.1.101.2.1.2.2"];
		[oid setObject:@"cspContentType" forKey:@"2.16.840.1.101.2.1.2.3"];
		[oid setObject:@"mspRev3ContentType" forKey:@"2.16.840.1.101.2.1.2.42"];
		[oid setObject:@"mspContentType" forKey:@"2.16.840.1.101.2.1.2.48"];
		[oid setObject:@"mspRekeyAgentProtocol" forKey:@"2.16.840.1.101.2.1.2.49"];
		[oid setObject:@"mspMMP" forKey:@"2.16.840.1.101.2.1.2.50"];
		[oid setObject:@"mspRev3-1ContentType" forKey:@"2.16.840.1.101.2.1.2.66"];
		[oid setObject:@"forwardedMSPMessageBodyPart" forKey:@"2.16.840.1.101.2.1.2.72"];
		[oid setObject:@"mspForwardedMessageParameters" forKey:@"2.16.840.1.101.2.1.2.73"];
		[oid setObject:@"forwardedCSPMsgBodyPart" forKey:@"2.16.840.1.101.2.1.2.74"];
		[oid setObject:@"cspForwardedMessageParameters" forKey:@"2.16.840.1.101.2.1.2.75"];
		[oid setObject:@"mspMMP2" forKey:@"2.16.840.1.101.2.1.2.76"];
		[oid setObject:@"sdnsSecurityPolicy" forKey:@"2.16.840.1.101.2.1.3.1"];
		[oid setObject:@"sdnsPRBAC" forKey:@"2.16.840.1.101.2.1.3.2"];
		[oid setObject:@"mosaicPRBAC" forKey:@"2.16.840.1.101.2.1.3.3"];
		[oid setObject:@"siSecurityPolicy" forKey:@"2.16.840.1.101.2.1.3.10"];
		[oid setObject:@"siNASP" forKey:@"2.16.840.1.101.2.1.3.10.0"];
		[oid setObject:@"siELCO" forKey:@"2.16.840.1.101.2.1.3.10.1"];
		[oid setObject:@"siTK" forKey:@"2.16.840.1.101.2.1.3.10.2"];
		[oid setObject:@"siDSAP" forKey:@"2.16.840.1.101.2.1.3.10.3"];
		[oid setObject:@"siSSSS" forKey:@"2.16.840.1.101.2.1.3.10.4"];
		[oid setObject:@"siDNASP" forKey:@"2.16.840.1.101.2.1.3.10.5"];
		[oid setObject:@"siBYEMAN" forKey:@"2.16.840.1.101.2.1.3.10.6"];
		[oid setObject:@"siREL-US" forKey:@"2.16.840.1.101.2.1.3.10.7"];
		[oid setObject:@"siREL-AUS" forKey:@"2.16.840.1.101.2.1.3.10.8"];
		[oid setObject:@"siREL-CAN" forKey:@"2.16.840.1.101.2.1.3.10.9"];
		[oid setObject:@"siREL_UK" forKey:@"2.16.840.1.101.2.1.3.10.10"];
		[oid setObject:@"siREL-NZ" forKey:@"2.16.840.1.101.2.1.3.10.11"];
		[oid setObject:@"siGeneric" forKey:@"2.16.840.1.101.2.1.3.10.12"];
		[oid setObject:@"genser" forKey:@"2.16.840.1.101.2.1.3.11"];
		[oid setObject:@"genserNations" forKey:@"2.16.840.1.101.2.1.3.11.0"];
		[oid setObject:@"genserComsec" forKey:@"2.16.840.1.101.2.1.3.11.1"];
		[oid setObject:@"genserAcquisition" forKey:@"2.16.840.1.101.2.1.3.11.2"];
		[oid setObject:@"genserSecurityCategories" forKey:@"2.16.840.1.101.2.1.3.11.3"];
		[oid setObject:@"genserTagSetName" forKey:@"2.16.840.1.101.2.1.3.11.3.0"];
		[oid setObject:@"defaultSecurityPolicy" forKey:@"2.16.840.1.101.2.1.3.12"];
		[oid setObject:@"capcoMarkings" forKey:@"2.16.840.1.101.2.1.3.13"];
		[oid setObject:@"capcoSecurityCategories" forKey:@"2.16.840.1.101.2.1.3.13.0"];
		[oid setObject:@"capcoTagSetName1" forKey:@"2.16.840.1.101.2.1.3.13.0.1"];
		[oid setObject:@"capcoTagSetName2" forKey:@"2.16.840.1.101.2.1.3.13.0.2"];
		[oid setObject:@"capcoTagSetName3" forKey:@"2.16.840.1.101.2.1.3.13.0.3"];
		[oid setObject:@"capcoTagSetName4" forKey:@"2.16.840.1.101.2.1.3.13.0.4"];
		[oid setObject:@"sdnsKeyManagementCertificate" forKey:@"2.16.840.1.101.2.1.5.1"];
		[oid setObject:@"sdnsUserSignatureCertificate" forKey:@"2.16.840.1.101.2.1.5.2"];
		[oid setObject:@"sdnsKMandSigCertificate" forKey:@"2.16.840.1.101.2.1.5.3"];
		[oid setObject:@"fortezzaKeyManagementCertificate" forKey:@"2.16.840.1.101.2.1.5.4"];
		[oid setObject:@"fortezzaKMandSigCertificate" forKey:@"2.16.840.1.101.2.1.5.5"];
		[oid setObject:@"fortezzaUserSignatureCertificate" forKey:@"2.16.840.1.101.2.1.5.6"];
		[oid setObject:@"fortezzaCASignatureCertificate" forKey:@"2.16.840.1.101.2.1.5.7"];
		[oid setObject:@"sdnsCASignatureCertificate" forKey:@"2.16.840.1.101.2.1.5.8"];
		[oid setObject:@"auxiliaryVector" forKey:@"2.16.840.1.101.2.1.5.10"];
		[oid setObject:@"mlReceiptPolicy" forKey:@"2.16.840.1.101.2.1.5.11"];
		[oid setObject:@"mlMembership" forKey:@"2.16.840.1.101.2.1.5.12"];
		[oid setObject:@"mlAdministrators" forKey:@"2.16.840.1.101.2.1.5.13"];
		[oid setObject:@"alid" forKey:@"2.16.840.1.101.2.1.5.14"];
		[oid setObject:@"janUKMs" forKey:@"2.16.840.1.101.2.1.5.20"];
		[oid setObject:@"febUKMs" forKey:@"2.16.840.1.101.2.1.5.21"];
		[oid setObject:@"marUKMs" forKey:@"2.16.840.1.101.2.1.5.22"];
		[oid setObject:@"aprUKMs" forKey:@"2.16.840.1.101.2.1.5.23"];
		[oid setObject:@"mayUKMs" forKey:@"2.16.840.1.101.2.1.5.24"];
		[oid setObject:@"junUKMs" forKey:@"2.16.840.1.101.2.1.5.25"];
		[oid setObject:@"julUKMs" forKey:@"2.16.840.1.101.2.1.5.26"];
		[oid setObject:@"augUKMs" forKey:@"2.16.840.1.101.2.1.5.27"];
		[oid setObject:@"sepUKMs" forKey:@"2.16.840.1.101.2.1.5.28"];
		[oid setObject:@"octUKMs" forKey:@"2.16.840.1.101.2.1.5.29"];
		[oid setObject:@"novUKMs" forKey:@"2.16.840.1.101.2.1.5.30"];
		[oid setObject:@"decUKMs" forKey:@"2.16.840.1.101.2.1.5.31"];
		[oid setObject:@"metaSDNSckl" forKey:@"2.16.840.1.101.2.1.5.40"];
		[oid setObject:@"sdnsCKL" forKey:@"2.16.840.1.101.2.1.5.41"];
		[oid setObject:@"metaSDNSsignatureCKL" forKey:@"2.16.840.1.101.2.1.5.42"];
		[oid setObject:@"sdnsSignatureCKL" forKey:@"2.16.840.1.101.2.1.5.43"];
		[oid setObject:@"sdnsCertificateRevocationList" forKey:@"2.16.840.1.101.2.1.5.44"];
		[oid setObject:@"fortezzaCertificateRevocationList" forKey:@"2.16.840.1.101.2.1.5.45"];
		[oid setObject:@"fortezzaCKL" forKey:@"2.16.840.1.101.2.1.5.46"];
		[oid setObject:@"alExemptedAddressProcessor" forKey:@"2.16.840.1.101.2.1.5.47"];
		[oid setObject:@"guard" forKey:@"2.16.840.1.101.2.1.5.48"];
		[oid setObject:@"algorithmsSupported" forKey:@"2.16.840.1.101.2.1.5.49"];
		[oid setObject:@"suiteAKeyManagementCertificate" forKey:@"2.16.840.1.101.2.1.5.50"];
		[oid setObject:@"suiteAKMandSigCertificate" forKey:@"2.16.840.1.101.2.1.5.51"];
		[oid setObject:@"suiteAUserSignatureCertificate" forKey:@"2.16.840.1.101.2.1.5.52"];
		[oid setObject:@"prbacInfo" forKey:@"2.16.840.1.101.2.1.5.53"];
		[oid setObject:@"prbacCAConstraints" forKey:@"2.16.840.1.101.2.1.5.54"];
		[oid setObject:@"sigOrKMPrivileges" forKey:@"2.16.840.1.101.2.1.5.55"];
		[oid setObject:@"commPrivileges" forKey:@"2.16.840.1.101.2.1.5.56"];
		[oid setObject:@"labeledAttribute" forKey:@"2.16.840.1.101.2.1.5.57"];
		[oid setObject:@"policyInformationFile" forKey:@"2.16.840.1.101.2.1.5.58"];
		[oid setObject:@"secPolicyInformationFile" forKey:@"2.16.840.1.101.2.1.5.59"];
		[oid setObject:@"cAClearanceConstraint" forKey:@"2.16.840.1.101.2.1.5.60"];
		[oid setObject:@"cspExtns" forKey:@"2.16.840.1.101.2.1.7.1"];
		[oid setObject:@"cspCsExtn" forKey:@"2.16.840.1.101.2.1.7.1.0"];
		[oid setObject:@"mISSISecurityCategories" forKey:@"2.16.840.1.101.2.1.8.1"];
		[oid setObject:@"standardSecurityLabelPrivileges" forKey:@"2.16.840.1.101.2.1.8.2"];
		[oid setObject:@"sigPrivileges" forKey:@"2.16.840.1.101.2.1.10.1"];
		[oid setObject:@"kmPrivileges" forKey:@"2.16.840.1.101.2.1.10.2"];
		[oid setObject:@"namedTagSetPrivilege" forKey:@"2.16.840.1.101.2.1.10.3"];
		[oid setObject:@"ukDemo" forKey:@"2.16.840.1.101.2.1.11.1"];
		[oid setObject:@"usDODClass2" forKey:@"2.16.840.1.101.2.1.11.2"];
		[oid setObject:@"usMediumPilot" forKey:@"2.16.840.1.101.2.1.11.3"];
		[oid setObject:@"usDODClass4" forKey:@"2.16.840.1.101.2.1.11.4"];
		[oid setObject:@"usDODClass3" forKey:@"2.16.840.1.101.2.1.11.5"];
		[oid setObject:@"usDODClass5" forKey:@"2.16.840.1.101.2.1.11.6"];
		[oid setObject:@"testSecurityPolicy" forKey:@"2.16.840.1.101.2.1.12.0"];
		[oid setObject:@"tsp1" forKey:@"2.16.840.1.101.2.1.12.0.1"];
		[oid setObject:@"tsp1SecurityCategories" forKey:@"2.16.840.1.101.2.1.12.0.1.0"];
		[oid setObject:@"tsp1TagSetZero" forKey:@"2.16.840.1.101.2.1.12.0.1.0.0"];
		[oid setObject:@"tsp1TagSetOne" forKey:@"2.16.840.1.101.2.1.12.0.1.0.1"];
		[oid setObject:@"tsp1TagSetTwo" forKey:@"2.16.840.1.101.2.1.12.0.1.0.2"];
		[oid setObject:@"tsp2" forKey:@"2.16.840.1.101.2.1.12.0.2"];
		[oid setObject:@"tsp2SecurityCategories" forKey:@"2.16.840.1.101.2.1.12.0.2.0"];
		[oid setObject:@"tsp2TagSetZero" forKey:@"2.16.840.1.101.2.1.12.0.2.0.0"];
		[oid setObject:@"tsp2TagSetOne" forKey:@"2.16.840.1.101.2.1.12.0.2.0.1"];
		[oid setObject:@"tsp2TagSetTwo" forKey:@"2.16.840.1.101.2.1.12.0.2.0.2"];
		[oid setObject:@"kafka" forKey:@"2.16.840.1.101.2.1.12.0.3"];
		[oid setObject:@"kafkaSecurityCategories" forKey:@"2.16.840.1.101.2.1.12.0.3.0"];
		[oid setObject:@"kafkaTagSetName1" forKey:@"2.16.840.1.101.2.1.12.0.3.0.1"];
		[oid setObject:@"kafkaTagSetName2" forKey:@"2.16.840.1.101.2.1.12.0.3.0.2"];
		[oid setObject:@"kafkaTagSetName3" forKey:@"2.16.840.1.101.2.1.12.0.3.0.3"];
		[oid setObject:@"tcp1" forKey:@"2.16.840.1.101.2.1.12.1.1"];
		[oid setObject:@"slabel" forKey:@"2.16.840.1.101.3.1"];
		[oid setObject:@"pki" forKey:@"2.16.840.1.101.3.2"];
		[oid setObject:@"GAK policyIdentifier" forKey:@"2.16.840.1.101.3.2.1"];
		[oid setObject:@"FBCA-Rudimentary policyIdentifier" forKey:@"2.16.840.1.101.3.2.1.3.1"];
		[oid setObject:@"FBCA-Basic policyIdentifier" forKey:@"2.16.840.1.101.3.2.1.3.2"];
		[oid setObject:@"FBCA-Medium policyIdentifier" forKey:@"2.16.840.1.101.3.2.1.3.3"];
		[oid setObject:@"FBCA-High policyIdentifier" forKey:@"2.16.840.1.101.3.2.1.3.4"];
		[oid setObject:@"GAK" forKey:@"2.16.840.1.101.3.2.2"];
		[oid setObject:@"kRAKey" forKey:@"2.16.840.1.101.3.2.2.1"];
		[oid setObject:@"extensions" forKey:@"2.16.840.1.101.3.2.3"];
		[oid setObject:@"kRTechnique" forKey:@"2.16.840.1.101.3.2.3.1"];
		[oid setObject:@"kRecoveryCapable" forKey:@"2.16.840.1.101.3.2.3.2"];
		[oid setObject:@"kR" forKey:@"2.16.840.1.101.3.2.3.3"];
		[oid setObject:@"keyrecoveryschemes" forKey:@"2.16.840.1.101.3.2.4"];
		[oid setObject:@"krapola" forKey:@"2.16.840.1.101.3.2.5"];
		[oid setObject:@"arpa" forKey:@"2.16.840.1.101.3.3"];
		[oid setObject:@"nistAlgorithm" forKey:@"2.16.840.1.101.3.4"];
		[oid setObject:@"aes" forKey:@"2.16.840.1.101.3.4.1"];
		[oid setObject:@"aes128-ECB" forKey:@"2.16.840.1.101.3.4.1.1"];
		[oid setObject:@"aes128-CBC" forKey:@"2.16.840.1.101.3.4.1.2"];
		[oid setObject:@"aes128-OFB" forKey:@"2.16.840.1.101.3.4.1.3"];
		[oid setObject:@"aes128-CFB" forKey:@"2.16.840.1.101.3.4.1.4"];
		[oid setObject:@"aes192-ECB" forKey:@"2.16.840.1.101.3.4.1.21"];
		[oid setObject:@"aes192-CBC" forKey:@"2.16.840.1.101.3.4.1.22"];
		[oid setObject:@"aes192-OFB" forKey:@"2.16.840.1.101.3.4.1.23"];
		[oid setObject:@"aes192-CFB" forKey:@"2.16.840.1.101.3.4.1.24"];
		[oid setObject:@"aes256-ECB" forKey:@"2.16.840.1.101.3.4.1.41"];
		[oid setObject:@"aes256-CBC" forKey:@"2.16.840.1.101.3.4.1.42"];
		[oid setObject:@"aes256-OFB" forKey:@"2.16.840.1.101.3.4.1.43"];
		[oid setObject:@"aes256-CFB" forKey:@"2.16.840.1.101.3.4.1.44"];
		[oid setObject:@"sha2-256" forKey:@"2.16.840.1.101.3.4.2.1"];
		[oid setObject:@"sha2-384" forKey:@"2.16.840.1.101.3.4.2.2"];
		[oid setObject:@"sha2-512" forKey:@"2.16.840.1.101.3.4.2.3"];
		[oid setObject:@"novellAlgorithm" forKey:@"2.16.840.1.113719.1.2.8"];
		[oid setObject:@"desCbcIV8" forKey:@"2.16.840.1.113719.1.2.8.22"];
		[oid setObject:@"desCbcPadIV8" forKey:@"2.16.840.1.113719.1.2.8.23"];
		[oid setObject:@"desEDE2CbcIV8" forKey:@"2.16.840.1.113719.1.2.8.24"];
		[oid setObject:@"desEDE2CbcPadIV8" forKey:@"2.16.840.1.113719.1.2.8.25"];
		[oid setObject:@"desEDE3CbcIV8" forKey:@"2.16.840.1.113719.1.2.8.26"];
		[oid setObject:@"desEDE3CbcPadIV8" forKey:@"2.16.840.1.113719.1.2.8.27"];
		[oid setObject:@"rc5CbcPad" forKey:@"2.16.840.1.113719.1.2.8.28"];
		[oid setObject:@"md2WithRSAEncryptionBSafe1" forKey:@"2.16.840.1.113719.1.2.8.29"];
		[oid setObject:@"md5WithRSAEncryptionBSafe1" forKey:@"2.16.840.1.113719.1.2.8.30"];
		[oid setObject:@"sha1WithRSAEncryptionBSafe1" forKey:@"2.16.840.1.113719.1.2.8.31"];
		[oid setObject:@"LMDigest" forKey:@"2.16.840.1.113719.1.2.8.32"];
		[oid setObject:@"MD2" forKey:@"2.16.840.1.113719.1.2.8.40"];
		[oid setObject:@"MD5" forKey:@"2.16.840.1.113719.1.2.8.50"];
		[oid setObject:@"IKEhmacWithSHA1-RSA" forKey:@"2.16.840.1.113719.1.2.8.51"];
		[oid setObject:@"IKEhmacWithMD5-RSA" forKey:@"2.16.840.1.113719.1.2.8.52"];
		[oid setObject:@"rc2CbcPad" forKey:@"2.16.840.1.113719.1.2.8.69"];
		[oid setObject:@"SHA-1" forKey:@"2.16.840.1.113719.1.2.8.82"];
		[oid setObject:@"rc2BSafe1Cbc" forKey:@"2.16.840.1.113719.1.2.8.92"];
		[oid setObject:@"MD4" forKey:@"2.16.840.1.113719.1.2.8.95"];
		[oid setObject:@"MD4Packet" forKey:@"2.16.840.1.113719.1.2.8.130"];
		[oid setObject:@"rsaEncryptionBsafe1" forKey:@"2.16.840.1.113719.1.2.8.131"];
		[oid setObject:@"NWPassword" forKey:@"2.16.840.1.113719.1.2.8.132"];
		[oid setObject:@"novellObfuscate-1" forKey:@"2.16.840.1.113719.1.2.8.133"];
		[oid setObject:@"pki" forKey:@"2.16.840.1.113719.1.9"];
		[oid setObject:@"pkiAttributeType" forKey:@"2.16.840.1.113719.1.9.4"];
		[oid setObject:@"securityAttributes" forKey:@"2.16.840.1.113719.1.9.4.1"];
		[oid setObject:@"relianceLimit" forKey:@"2.16.840.1.113719.1.9.4.2"];
		[oid setObject:@"cert-extension" forKey:@"2.16.840.1.113730.1"];
		[oid setObject:@"netscape-cert-type" forKey:@"2.16.840.1.113730.1.1"];
		[oid setObject:@"netscape-base-url" forKey:@"2.16.840.1.113730.1.2"];
		[oid setObject:@"netscape-revocation-url" forKey:@"2.16.840.1.113730.1.3"];
		[oid setObject:@"netscape-ca-revocation-url" forKey:@"2.16.840.1.113730.1.4"];
		[oid setObject:@"netscape-cert-renewal-url" forKey:@"2.16.840.1.113730.1.7"];
		[oid setObject:@"netscape-ca-policy-url" forKey:@"2.16.840.1.113730.1.8"];
		[oid setObject:@"HomePage-url" forKey:@"2.16.840.1.113730.1.9"];
		[oid setObject:@"EntityLogo" forKey:@"2.16.840.1.113730.1.10"];
		[oid setObject:@"UserPicture" forKey:@"2.16.840.1.113730.1.11"];
		[oid setObject:@"netscape-ssl-server-name" forKey:@"2.16.840.1.113730.1.12"];
		[oid setObject:@"netscape-comment" forKey:@"2.16.840.1.113730.1.13"];
		[oid setObject:@"data-type" forKey:@"2.16.840.1.113730.2"];
		[oid setObject:@"dataGIF" forKey:@"2.16.840.1.113730.2.1"];
		[oid setObject:@"dataJPEG" forKey:@"2.16.840.1.113730.2.2"];
		[oid setObject:@"dataURL" forKey:@"2.16.840.1.113730.2.3"];
		[oid setObject:@"dataHTML" forKey:@"2.16.840.1.113730.2.4"];
		[oid setObject:@"certSequence" forKey:@"2.16.840.1.113730.2.5"];
		[oid setObject:@"certURL" forKey:@"2.16.840.1.113730.2.6"];
		[oid setObject:@"directory" forKey:@"2.16.840.1.113730.3"];
		[oid setObject:@"ldapDefinitions" forKey:@"2.16.840.1.113730.3.1"];
		[oid setObject:@"carLicense" forKey:@"2.16.840.1.113730.3.1.1"];
		[oid setObject:@"departmentNumber" forKey:@"2.16.840.1.113730.3.1.2"];
		[oid setObject:@"employeeNumber" forKey:@"2.16.840.1.113730.3.1.3"];
		[oid setObject:@"employeeType" forKey:@"2.16.840.1.113730.3.1.4"];
		[oid setObject:@"inetOrgPerson" forKey:@"2.16.840.1.113730.3.2.2"];
		[oid setObject:@"serverGatedCrypto" forKey:@"2.16.840.1.113730.4.1"];
		[oid setObject:@"verisignCZAG" forKey:@"2.16.840.1.113733.1.6.3"];
		[oid setObject:@"verisignInBox" forKey:@"2.16.840.1.113733.1.6.6"];
		[oid setObject:@"Unknown Verisign VPN extension" forKey:@"2.16.840.1.113733.1.6.11"];
		[oid setObject:@"Unknown Verisign VPN extension" forKey:@"2.16.840.1.113733.1.6.13"];
		[oid setObject:@"Verisign serverID" forKey:@"2.16.840.1.113733.1.6.15"];
		[oid setObject:@"Verisign policyIdentifier" forKey:@"2.16.840.1.113733.1.7.1.1"];
		[oid setObject:@"verisignCPSv1notice" forKey:@"2.16.840.1.113733.1.7.1.1.1"];
		[oid setObject:@"verisignCPSv1nsi" forKey:@"2.16.840.1.113733.1.7.1.1.2"];
		[oid setObject:@"Verisign SGC CA?" forKey:@"2.16.840.1.113733.1.8.1"];
		[oid setObject:@"contentType" forKey:@"2.23.42.0"];
		[oid setObject:@"PANData" forKey:@"2.23.42.0.0"];
		[oid setObject:@"PANToken" forKey:@"2.23.42.0.1"];
		[oid setObject:@"PANOnly" forKey:@"2.23.42.0.2"];
		[oid setObject:@"msgExt" forKey:@"2.23.42.1"];
		[oid setObject:@"field" forKey:@"2.23.42.2"];
		[oid setObject:@"fullName" forKey:@"2.23.42.2.0"];
		[oid setObject:@"givenName" forKey:@"2.23.42.2.1"];
		[oid setObject:@"familyName" forKey:@"2.23.42.2.2"];
		[oid setObject:@"birthFamilyName" forKey:@"2.23.42.2.3"];
		[oid setObject:@"placeName" forKey:@"2.23.42.2.4"];
		[oid setObject:@"identificationNumber" forKey:@"2.23.42.2.5"];
		[oid setObject:@"month" forKey:@"2.23.42.2.6"];
		[oid setObject:@"date" forKey:@"2.23.42.2.7"];
		[oid setObject:@"address" forKey:@"2.23.42.2.8"];
		[oid setObject:@"telephone" forKey:@"2.23.42.2.9"];
		[oid setObject:@"amount" forKey:@"2.23.42.2.10"];
		[oid setObject:@"accountNumber" forKey:@"2.23.42.2.7.11"];
		[oid setObject:@"passPhrase" forKey:@"2.23.42.2.7.12"];
		[oid setObject:@"attribute" forKey:@"2.23.42.3"];
		[oid setObject:@"cert" forKey:@"2.23.42.3.0"];
		[oid setObject:@"rootKeyThumb" forKey:@"2.23.42.3.0.0"];
		[oid setObject:@"additionalPolicy" forKey:@"2.23.42.3.0.1"];
		[oid setObject:@"algorithm" forKey:@"2.23.42.4"];
		[oid setObject:@"policy" forKey:@"2.23.42.5"];
		[oid setObject:@"root" forKey:@"2.23.42.5.0"];
		[oid setObject:@"module" forKey:@"2.23.42.6"];
		[oid setObject:@"certExt" forKey:@"2.23.42.7"];
		[oid setObject:@"hashedRootKey" forKey:@"2.23.42.7.0"];
		[oid setObject:@"certificateType" forKey:@"2.23.42.7.1"];
		[oid setObject:@"merchantData" forKey:@"2.23.42.7.2"];
		[oid setObject:@"cardCertRequired" forKey:@"2.23.42.7.3"];
		[oid setObject:@"tunneling" forKey:@"2.23.42.7.4"];
		[oid setObject:@"setExtensions" forKey:@"2.23.42.7.5"];
		[oid setObject:@"setQualifier" forKey:@"2.23.42.7.6"];
		[oid setObject:@"brand" forKey:@"2.23.42.8"];
		[oid setObject:@"IATA-ATA" forKey:@"2.23.42.8.1"];
		[oid setObject:@"VISA" forKey:@"2.23.42.8.4"];
		[oid setObject:@"MasterCard" forKey:@"2.23.42.8.5"];
		[oid setObject:@"Diners" forKey:@"2.23.42.8.30"];
		[oid setObject:@"AmericanExpress" forKey:@"2.23.42.8.34"];
		[oid setObject:@"Novus" forKey:@"2.23.42.8.6011"];
		[oid setObject:@"vendor" forKey:@"2.23.42.9"];
		[oid setObject:@"GlobeSet" forKey:@"2.23.42.9.0"];
		[oid setObject:@"IBM" forKey:@"2.23.42.9.1"];
		[oid setObject:@"CyberCash" forKey:@"2.23.42.9.2"];
		[oid setObject:@"Terisa" forKey:@"2.23.42.9.3"];
		[oid setObject:@"RSADSI" forKey:@"2.23.42.9.4"];
		[oid setObject:@"VeriFone" forKey:@"2.23.42.9.5"];
		[oid setObject:@"TrinTech" forKey:@"2.23.42.9.6"];
		[oid setObject:@"BankGate" forKey:@"2.23.42.9.7"];
		[oid setObject:@"GTE" forKey:@"2.23.42.9.8"];
		[oid setObject:@"CompuSource" forKey:@"2.23.42.9.9"];
		[oid setObject:@"Griffin" forKey:@"2.23.42.9.10"];
		[oid setObject:@"Certicom" forKey:@"2.23.42.9.11"];
		[oid setObject:@"OSS" forKey:@"2.23.42.9.12"];
		[oid setObject:@"TenthMountain" forKey:@"2.23.42.9.13"];
		[oid setObject:@"Antares" forKey:@"2.23.42.9.14"];
		[oid setObject:@"ECC" forKey:@"2.23.42.9.15"];
		[oid setObject:@"Maithean" forKey:@"2.23.42.9.16"];
		[oid setObject:@"Netscape" forKey:@"2.23.42.9.17"];
		[oid setObject:@"Verisign" forKey:@"2.23.42.9.18"];
		[oid setObject:@"BlueMoney" forKey:@"2.23.42.9.19"];
		[oid setObject:@"Lacerte" forKey:@"2.23.42.9.20"];
		[oid setObject:@"Fujitsu" forKey:@"2.23.42.9.21"];
		[oid setObject:@"eLab" forKey:@"2.23.42.9.22"];
		[oid setObject:@"Entrust" forKey:@"2.23.42.9.23"];
		[oid setObject:@"VIAnet" forKey:@"2.23.42.9.24"];
		[oid setObject:@"III" forKey:@"2.23.42.9.25"];
		[oid setObject:@"OpenMarket" forKey:@"2.23.42.9.26"];
		[oid setObject:@"Lexem" forKey:@"2.23.42.9.27"];
		[oid setObject:@"Intertrader" forKey:@"2.23.42.9.28"];
		[oid setObject:@"Persimmon" forKey:@"2.23.42.9.29"];
		[oid setObject:@"NABLE" forKey:@"2.23.42.9.30"];
		[oid setObject:@"espace-net" forKey:@"2.23.42.9.31"];
		[oid setObject:@"Hitachi" forKey:@"2.23.42.9.32"];
		[oid setObject:@"Microsoft" forKey:@"2.23.42.9.33"];
		[oid setObject:@"NEC" forKey:@"2.23.42.9.34"];
		[oid setObject:@"Mitsubishi" forKey:@"2.23.42.9.35"];
		[oid setObject:@"NCR" forKey:@"2.23.42.9.36"];
		[oid setObject:@"e-COMM" forKey:@"2.23.42.9.37"];
		[oid setObject:@"Gemplus" forKey:@"2.23.42.9.38"];
		[oid setObject:@"national" forKey:@"2.23.42.10"];
		[oid setObject:@"Japan" forKey:@"2.23.42.10.392"];
		[oid setObject:@"hashedRootKey" forKey:@"2.54.1775.2"];
		[oid setObject:@"certificateType" forKey:@"2.54.1775.3"];
		[oid setObject:@"merchantData" forKey:@"2.54.1775.4"];
		[oid setObject:@"cardCertRequired" forKey:@"2.54.1775.5"];
		[oid setObject:@"tunneling" forKey:@"2.54.1775.6"];
		[oid setObject:@"setQualifier" forKey:@"2.54.1775.7"];
		[oid setObject:@"set-data" forKey:@"2.54.1775.99"];
	}
	*decapsulatePos = -1;
	*decapsulateLen = -1;
	switch (tag->t_class) {
	case UNIVERSAL:
		switch (tag->t_tagnum) {
		case ASN1_BOOLEAN:							// BOOLEAN
			c = [d byteAtOffset:pos++];
			if (c == 0xff)
				value = [NSString stringWithString: @"TRUE"];
			else if (c == 0x00)
				value = [NSString stringWithString: @"FALSE"];
			else	
				value = [NSString stringWithFormat: @"0x%02x", c];
			break;
		case ASN1_INTEGER:							// INTEGER
			c = [d byteAtOffset:pos++];
			if (c & 0x80)	// Negative
				iv = (signed char)c;
			else
				iv = (unsigned char)c;
			for (n = 1; n < len; n++)
				iv = (iv << 8) | [d byteAtOffset:pos++];
			value = [NSString stringWithFormat:@"%ld", iv];
			break;
		case ASN1_OBJECT_IDENTIFIER:				// OID
			iv = 0;
			NSMutableString *oidString = [NSMutableString string];
			for (n = 0; n < len; n++) {
				c = [d byteAtOffset:pos++];
				iv = (iv << 7) | (c & 0x7f);
				if (c & 0x80)
					continue;
				if (n == 0) {
					if (iv < 40)
						[oidString appendFormat:@"0.%ld", iv];
					else if (iv < 80)
						[oidString appendFormat:@"1.%ld", iv - 40];
					else
						[oidString appendFormat:@"2.%ld", iv - 80];
				} else {
					[oidString appendFormat:@".%ld", iv];
				}
				iv = 0;
			}
			value = [oid valueForKey:oidString];
			if (value == nil)
				value = oidString;
			break;
		case ASN1_BIT_STRING:						// BIT STRING
			// BIT STRINGs may encapsulate stuff after the
			// leading "unused-bits" octet, which is why
			// the +1 and -1 are needed
			if (isEncapsulated(d, pos + 1, len - 1)) {
				[value appendString:@" encapsulating {"];
				*decapsulatePos = pos + 1;
				*decapsulateLen = len - 1;
				// dump(d, pos, pos + len - 1, parent, standard);
			} else {
				[value appendString:printBit(d, pos, len)];
				pos += len;
			}
			break;
		case ASN1_OCTET_STRING:
			if (isEncapsulated(d, pos, len)) {
				[value appendString:@" encapsulating {"];
				*decapsulatePos = pos;
				*decapsulateLen = len;
				//pos = dump(d, pos, pos + len, parent, standard);
			} else {
				if (textoctets) {
					[value appendString:@"\""];
					[value appendString:printText(d, pos, len)];
					[value appendString:@"\""];
					pos += len;
				} else if (len > 0) {
					[value appendString:@"0x"];
					[value appendString:printOctet(d, pos, len)];
					pos += len;
				}
			}
			break;
		default:								// OCTET STRING, anything else
			if (textoctets) {
				[value appendString:@"\""];
				[value appendString:printText(d, pos, len)];
				[value appendString:@"\""];
				pos += len;
			} else if (len > 0) {
				[value appendString:@"0x"];
				[value appendString:printOctet(d, pos, len)];
				pos += len;
			}
			break;
		case ASN1_NULL:							// NULL
			break;
		case ASN1_ENUMERATED:					// ENUMERATED
			if (len > 0) {
				[value appendString:@"0x"];
				[value appendString:printOctet(d, pos, len)];
				pos += len;
			}
			break;
		case ASN1_ObjectDescriptor:
		case ASN1_NumericString:
		case ASN1_UTF8String:
		case ASN1_PrintableString:
		case ASN1_TeletexString:
		case ASN1_VideotexString:
		case ASN1_IA5String:
		case ASN1_UTCTime:
		case ASN1_GeneralizedTime:
		case ASN1_GraphicString:
		case ASN1_VisibleString:
		case ASN1_GeneralString:
			[value appendString:@"\""];
			[value appendString:printText(d, pos, len)];
			[value appendString:@"\""];
			pos += len;
			break;
		}
		break;
	case APPLICATION:
	case CONTEXT:
	case PRIVATE:						// Treat other stuff as an OCTET
		if (textoctets) {				// STRING.
			[value appendString:@"\""];
			[value appendString:printText(d, pos, len)];
			[value appendString:@"\""];
			pos += len;
		} else {
			[value appendString:@"0x"];
			[value appendString:printOctet(d, pos, len)];
			pos += len;
		}
		break;
	}
	return value;
}

/*
 * Dump BER-encoded data from the file, until a checkpoint is reached
 * (which is the calculated sequence end). Indent automatically.
 * Handles indefinite length encoding by decoding the constructed values
 * (this is a recursive definition) until finding a 0x0000 tag/length.
 * It then rewinds *back*, and the length is then calculated using ftell()
 *
 */
NSInteger dump(NSData *d, NSInteger pos, NSInteger checkpt, ASN1Node *parent, enum Display display)
{
	Tag		tag;
	enum	Display subdisplay;
	int		c;
	long	len;

	for (;;) {
		NSInteger startpos = pos;
		if (pos != 0 && pos == checkpt)	{ // 0 is the special starting case
			return pos;						// Reached a sequence end
		}

		pos = readT(d, pos, &tag);

/*
 * Get length, which is either indefinite (so we decode the sub-structs,
 * and then seek back); or long (a number of octets, preceded by the count);
 * or short (in the single octet)
 *
 */
		c = [d byteAtOffset:pos++];

/*
 * If we are have a 0x00 0x00 then we are at the end of an indefinite
 * constructed type, and we should return now.
 *
 */
		if (tag.t_class == 0 &&
			tag.t_encode == 0 &&
			tag.t_tagnum == 0 &&
			c == 0) {
			return pos;
		}
/*
 * We now have something worth printing
 *
 */
		if (c == 0x80) {
			NSInteger newpos = dump(d, pos, 0, parent, none);		// Dummy checkpoint value
			len = newpos - pos;
		} else if (c & 0x80) {
			long nlen;
			len = 0;
			nlen = c & 0x7f;
			for (c = 0; c < nlen; c++) {
				len = (len << 8) | ([d byteAtOffset:pos++] & 0xff);
										// Potential overflow...
			}
		} else {
			len = c & 0x7f;
		}
/*
 * Got tag and length
 * Display if required
 * First see if we are going to want to fold together a constructed type
 * We need to know this now, so we can change the printTL() behaviour.
 *
 */
		subdisplay = display;
		if (tag.t_encode == 1 && tag.t_class == 0 &&
			fold == 1 && display != none)
			switch (tag.t_tagnum) {
			case ASN1_BIT_STRING:
				subdisplay = foldbit;
				break;
			case ASN1_OCTET_STRING:
				subdisplay = foldoctet;
				break;
			case ASN1_ObjectDescriptor:
			case ASN1_NumericString:
			case ASN1_PrintableString:
			case ASN1_TeletexString:
			case ASN1_VideotexString:
			case ASN1_IA5String:
			case ASN1_UTCTime:
			case ASN1_GeneralizedTime:
			case ASN1_GraphicString:
			case ASN1_VisibleString:
			case ASN1_GeneralString:
				subdisplay = foldtext;
				break;
			}

		ASN1Node *cons = parent;
		if (display == standard) {
			cons = printTL(&tag, startpos, len, subdisplay);
			[parent addChild: cons];
		}

		if (tag.t_encode == 1) {		// We have TL and no value
			dump(d, pos, pos + len, cons, subdisplay);
			pos += len;
			if (display != none && subdisplay == standard) {
				[parent addChild:[ASN1Node nodeWithTag:@"}"]];
			}
		} else {						// We have TLV, so skip value
			NSInteger decapsulatePos;
			long decapsulateLen;
			switch (display) {
			case none:
				pos += len;
				break;
			case standard:
				[cons setValue:printV(d, pos, &tag, len, &decapsulatePos, &decapsulateLen)];
				if (decapsulatePos != -1) {
					dump(d, decapsulatePos, decapsulatePos + decapsulateLen, cons, subdisplay);
					[parent addChild:[ASN1Node nodeWithTag:@"}"]];
				}
				pos += len;
				break;
			case foldtext:
				[cons setValue:printText(d, pos, len)];
				pos += len;
				break;
			case foldoctet:
				[cons setValue:textoctets ? printText(d, pos, len) : printOctet(d, pos, len)];
				pos += len;
				break;
			case foldbit:
				[cons setValue:printBit(d, pos, len)];
				pos += len;
				break;
			}
		}

	}
}

/* End of berd.m */
