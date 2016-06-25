//
//  ACHLSCaptioningServer.h
//
//  Created by Alejandro Cotilla on 6/25/16.
//  Copyright © 2016 Alejandro Cotilla. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ACHLSCaptioningServer : NSObject

+ (ACHLSCaptioningServer *)sharedInstance;

- (NSURL *)getCaptionedHLSStreamFromStream:(NSString *)origStreamPath vttFilePath:(NSString *)origVTTFilePath;

@end

@interface NSString (ACHLSCaptioningServer)

- (NSString *)stringByRemovingDoubleLinesJumps;
- (NSArray *)stringsBetweenText:(NSString *)txt1 andText:(NSString *)txt2 allowDuplicates:(BOOL)duplicates;

@end

@interface NSArray (ACHLSCaptioningServer)

- (BOOL)containsString:(NSString *)string insensitiveSearch:(BOOL)insensitive wholeWord:(BOOL)wholeWord;
- (int)indexOfString:(NSString *)string insensitiveSearch:(BOOL)insensitive wholeWord:(BOOL)wholeWord;

@end