#import <Foundation/Foundation.h>

enum Display {none = 0, standard, foldtext, foldoctet, foldbit};

@class ASN1Node;

extern NSInteger dump(NSData *, NSInteger, NSInteger, ASN1Node *, enum Display);