//
//  ACHLSCaptioningServer.m
//
//  Created by Alejandro Cotilla on 6/25/16.
//  Copyright © 2016 Alejandro Cotilla. All rights reserved.
//

#import "ACHLSCaptioningServer.h"

#import "GCDWebServer.h"

#define CAPTIONING_SERVER_BASE NSTemporaryDirectory()

#define SUBTITLED_HLS_STREAM_NAME @"subtitled_hls_stream.m3u8"
#define VTT_SUBTITLES_FILE_NAME @"subs.vtt"
#define HLS_SUBTITLES_FILE_NAME @"subs.m3u8"
#define HLS_VIDEO_REFERENCE_FILE_NAME @"direct_video_hls.m3u8"

@interface ACHLSCaptioningServer ()

@property (strong, nonatomic) GCDWebServer *webServer;

@end

@implementation ACHLSCaptioningServer

#pragma mark - Initialization -

static ACHLSCaptioningServer *_sharedInstance = nil;

+ (ACHLSCaptioningServer *)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[ACHLSCaptioningServer alloc] init];
    });
    
    return _sharedInstance;
}

+ (id)alloc
{
    NSAssert(_sharedInstance == nil, @"Attempted to allocate a second instance of a singleton.");
    return [super alloc];
}

- (id)init
{
    self = [super init];
    
    // create and start server
    _webServer = [[GCDWebServer alloc] init];
    [_webServer addGETHandlerForBasePath:@"/" directoryPath:CAPTIONING_SERVER_BASE indexFilename:nil cacheAge:1 allowRangeRequests:YES];
    [_webServer startWithPort:8080 bonjourName:nil]; // Start server on port 8080
    [GCDWebServer setLogLevel:3];
    
    return self;
}

#pragma mark - HLS Handling -

- (NSURL *)getCaptionedHLSStreamFromStream:(NSString *)origStreamPath vttFilePath:(NSString *)origVTTFilePath
{
    //
    // clear old server files
    //
    
    NSString *videoHLSReferencePath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:HLS_VIDEO_REFERENCE_FILE_NAME];
    NSString *subtitledHLSStreamPath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:SUBTITLED_HLS_STREAM_NAME];
    NSString *vttFilePath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:VTT_SUBTITLES_FILE_NAME];
    NSString *HLSSubtitlesPath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:HLS_SUBTITLES_FILE_NAME];
    
    [[NSFileManager defaultManager] removeItemAtPath:videoHLSReferencePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:subtitledHLSStreamPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:vttFilePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:HLSSubtitlesPath error:nil];
    
    // get hls contents
    NSString *hlsContents = [NSString stringWithContentsOfURL:[NSURL URLWithString:origStreamPath] encoding:NSUTF8StringEncoding error:nil];
    
    // make sure there's no empty lines
    hlsContents = [hlsContents stringByRemovingDoubleLinesJumps];
    
    // get all stream lines
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[hlsContents componentsSeparatedByString:@"\n"]];
    
    // add HLS version line
    if (![hlsContents containsString:@"#EXT-X-VERSION"])
    {
        [lines insertObject:@"#EXT-X-VERSION:4" atIndex:1];
    }
    
    // add subtitle line
    NSURL *onlineHLSSubsURL = [self buildAndSaveHLSSubsFromOrigVTTFilePath:origVTTFilePath];
    NSString *subtitleLine = [NSString stringWithFormat:@"#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,LANGUAGE=\"eng\",URI=\"%@\"", [onlineHLSSubsURL absoluteString]];
    [lines insertObject:subtitleLine atIndex:2];
    
    // iterate over HLS lines and customize its values
    NSURL *streamBaseURL = [[NSURL URLWithString:origStreamPath] URLByDeletingLastPathComponent];
    for (int i = 0; i < lines.count - 1; i++)
    {
        NSString *line = lines[i];
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        if (![line hasPrefix:@"#"] && ![line hasPrefix:@"http"])
        {
            // make sure streams urls are absolute
            NSString *absoluteURL = [[streamBaseURL URLByAppendingPathComponent:line] absoluteString];
            [lines replaceObjectAtIndex:i withObject:absoluteURL];
        }
        else if ([line hasPrefix:@"#EXT-X-STREAM-INF"])
        {
            // link subtitles to the stream info
            NSString *lineWithLinkedSubs = [line stringByAppendingString:@", SUBTITLES=\"subs\""];
            [lines replaceObjectAtIndex:i withObject:lineWithLinkedSubs];
        }
    }
    
    // save changes
    NSString *newHLSContents = [lines componentsJoinedByString:@"\n"];
    [newHLSContents writeToFile:subtitledHLSStreamPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSURL *onlineStreamURL = [_webServer.serverURL URLByAppendingPathComponent:SUBTITLED_HLS_STREAM_NAME];
    
    return onlineStreamURL;
}

- (NSURL *)buildAndSaveHLSSubsFromOrigVTTFilePath:(NSString *)origVTTFilePath
{
    NSMutableString *subsContents = [NSMutableString stringWithString:[NSString stringWithContentsOfURL:[NSURL URLWithString:origVTTFilePath] encoding:NSUTF8StringEncoding error:nil]];
    
    //
    // get captions duration
    //
    
    NSArray *endTimes = [subsContents stringsBetweenText:@"--> " andText:@"\n" allowDuplicates:YES];
    NSString *topDurationStr = [endTimes lastObject];
    
    NSArray *timeComponents = [topDurationStr componentsSeparatedByString:@":"];
    NSString *hour = timeComponents[0];
    NSString *minute = timeComponents[1];
    NSString *second = timeComponents[2];
    NSString *milisecond = @"0";
    if ([second containsString:@"."])
    {
        NSArray *secondComponents = [second componentsSeparatedByString:@"."];
        second = secondComponents[0];
        milisecond = secondComponents[1];
    }
    
    int totalSeconds = ceilf([hour intValue] * 60.0 * 60.0 + [minute intValue] * 60.0 + [second intValue] + [milisecond intValue] / 1000.0);
    
    // postioning subtitles (adding line:80% will make the subtitles appear above the scrubber bar)
    NSInteger rangeLocation = 0;
    for (NSString *endTime in endTimes)
    {
        NSString *lineEnding = [NSString stringWithFormat:@"--> %@", endTime];
        lineEnding = [lineEnding stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        NSString *lineEndingWithPosition = [lineEnding stringByAppendingString:@" line:80%"];
        
        NSRange lineEndingRange = [subsContents rangeOfString:lineEnding options:kNilOptions range:NSMakeRange(rangeLocation, subsContents.length - rangeLocation)];
        rangeLocation = lineEndingRange.location + lineEndingWithPosition.length;
        
        [subsContents replaceCharactersInRange:lineEndingRange withString:lineEndingWithPosition];
    }
    
    // save vtt file to our server
    NSString *vttFileLocalPath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:VTT_SUBTITLES_FILE_NAME];
    [subsContents writeToFile:vttFileLocalPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    //
    // create and save hls subs
    //
    
    NSString *hlsSubsContents = [NSString stringWithFormat:@"#EXTM3U\n#EXT-X-VERSION:4\n#EXT-X-TARGETDURATION:%d\n#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:%d,\n%@\n#EXT-X-ENDLIST", totalSeconds, totalSeconds, VTT_SUBTITLES_FILE_NAME];
    
    NSString *localHLSPath = [CAPTIONING_SERVER_BASE stringByAppendingPathComponent:HLS_SUBTITLES_FILE_NAME];
    [hlsSubsContents writeToFile:localHLSPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSURL *onlineHLSSubsURL = [_webServer.serverURL URLByAppendingPathComponent:HLS_SUBTITLES_FILE_NAME];
    
    return onlineHLSSubsURL;
}

@end

#pragma mark - Helpers -

@implementation NSString (ACHLSCaptioningServer)

- (NSString *)stringByRemovingDoubleLinesJumps
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\n+" options:0 error:nil];
    NSString *formatted = [regex stringByReplacingMatchesInString:self options:0 range:NSMakeRange(0, self.length) withTemplate:@"\n"];
    return formatted;
}

- (NSArray *)stringsBetweenText:(NSString *)txt1 andText:(NSString *)txt2 allowDuplicates:(BOOL)duplicates
{
    NSMutableArray *strings = [NSMutableArray array];
    
    NSRange beforeRange = [self rangeOfString:txt1];
    while (beforeRange.location != NSNotFound)
    {
        NSRange afterRange = [self rangeOfString:txt2 options:0 range:NSMakeRange(beforeRange.location + beforeRange.length, self.length - (beforeRange.location + beforeRange.length))];
        if (afterRange.location != NSNotFound)
        {
            NSRange betweenRange = NSMakeRange(beforeRange.location + beforeRange.length, afterRange.location - (beforeRange.location + beforeRange.length));
            NSString *string = [self substringWithRange:betweenRange];
            if (duplicates || (!duplicates && ![strings containsString:string insensitiveSearch:NO wholeWord:YES]))
            {
                [strings addObject:string];
            }
        }
        else
        {
            return strings;
        }
        
        beforeRange = [self rangeOfString:txt1 options:0 range:NSMakeRange(afterRange.location + afterRange.length, self.length - (afterRange.location + afterRange.length))];
    }
    
    return strings;
}

@end

@implementation NSArray (ACHLSCaptioningServer)

- (BOOL)containsString:(NSString *)string insensitiveSearch:(BOOL)insensitive wholeWord:(BOOL)wholeWord
{
    if ([self indexOfString:string insensitiveSearch:insensitive wholeWord:wholeWord] >= 0)
    {
        return YES;
    }
    
    return NO;
}

- (int)indexOfString:(NSString *)string insensitiveSearch:(BOOL)insensitive wholeWord:(BOOL)wholeWord
{
    if (insensitive)
    {
        string = [string lowercaseString];
    }
    
    int index = 0;
    for (NSString *str in self)
    {
        NSString *formattedStr = str;
        if (insensitive)
        {
            formattedStr = [formattedStr lowercaseString];
        }
        
        if (wholeWord)
        {
            if ([formattedStr isEqualToString:string])
            {
                return index;
            }
        }
        else
        {
            if (insensitive)
            {
                if ([formattedStr rangeOfString:string options:NSCaseInsensitiveSearch].location != NSNotFound)
                {
                    return index;
                }
            }
            else
            {
                if ([formattedStr rangeOfString:string].location != NSNotFound)
                {
                    return index;
                }
            }
        }
        
        index++;
    }
    
    return -1;
}

@end
