#import <Cocoa/Cocoa.h>

@interface CoverBrowserItem : NSObject

@property (nonatomic, strong) NSString *albumTitle;
@property (nonatomic, strong) NSString *albumArtist;
@property (nonatomic, strong) NSImage  *coverArt;
@property (nonatomic, copy, nullable) NSString *albumTitleQuery;
@property (nonatomic, strong, nullable) NSData *albumTitleQueryData;
@property (nonatomic, copy, nullable) NSString *albumArtistQuery;
@property (nonatomic, strong, nullable) NSData *albumArtistQueryData;
@property (nonatomic, copy, nullable) NSString *trackArtist;
@property (nonatomic, assign) BOOL hasAlbumTag;
@property (nonatomic, assign) BOOL hasAlbumArtistTag;
@property (nonatomic, assign) BOOL hasTrackArtistTag;

- (void)setMetaDbHandle:(const void *)handlePtr;
- (const void *)getMetaDbHandle;

@end
