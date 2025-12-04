#import "CoverBrowserViewController.h"
#import "CoverBrowserCollectionItem.h"
#import "CoverBrowserCollectionView.h"
#import "CoverBrowserItem.h"
#import "CoverBrowserPreferences.h"
#include "foobar2000/SDK/album_art.h"
#include "foobar2000/SDK/autoplaylist.h"
#include "foobar2000/SDK/foobar2000.h"
#include "foobar2000/SDK/library_manager.h"
#include "foobar2000/SDK/playlist.h"
#include "foobar2000/SDK/threadsLite.h"
#include "foobar2000/SDK/titleformat.h"
#include "foobar2000/SDK/ui.h"
#include <map>
#include <string>

namespace {
pfc::string8 escape_for_query(const char *text) {
  pfc::string8 out;
  if (text == nullptr)
    return out;
  while (*text) {
    char c = *text++;
    if (c == '\\' || c == '"')
      out.add_char('\\');
    out.add_char(c);
  }
  return out;
}
} // namespace

static NSString *NormalizeQueryToken(NSString *input) {
  if (input == nil || input.length == 0) {
    return input;
  }
  static dispatch_once_t onceToken;
  static NSArray<NSDictionary<NSString *, NSString *> *> *replacementSets = nil;
  dispatch_once(&onceToken, ^{
    replacementSets = @[
      @{@"‘" : @"'"}, @{@"’" : @"'"}, @{@"‛" : @"'"}, @{@"＇" : @"'"},
      @{@"′" : @"'"}, @{@"“" : @"\""}, @{@"”" : @"\""}
    ];
  });

  NSMutableString *buffer = [input mutableCopy];
  for (NSDictionary<NSString *, NSString *> *map in replacementSets) {
    [map enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj,
                                             BOOL *stop) {
      [buffer replaceOccurrencesOfString:key
                              withString:obj
                                 options:0
                                   range:NSMakeRange(0, buffer.length)];
    }];
  }

  NSString *precomposed = [buffer precomposedStringWithCanonicalMapping];
  if (precomposed != nil) {
    return precomposed;
  }
  return [buffer copy];
}

typedef NS_ENUM(NSInteger, CoverBrowserSortOption) {
  CoverBrowserSortOptionAlbum = 0,
  CoverBrowserSortOptionAlbumArtist,
  CoverBrowserSortOptionArtist
};

@interface CoverBrowserViewController ()
- (void)refreshAlbums;
- (void)loadCoverArtAsync;
- (NSMenu *)collectionView:(CoverBrowserCollectionView *)collectionView
        menuForItemAtIndex:(NSInteger)index;
- (void)handleContextMenuSendToCurrentPlaylist:(NSMenuItem *)sender;
- (void)handleContextMenuAddToCurrentPlaylist:(NSMenuItem *)sender;
- (void)handleContextMenuSendToNewPlaylist:(NSMenuItem *)sender;
- (void)handleContextMenuPlay:(NSMenuItem *)sender;
- (void)sortAlbums;
- (void)handleSortSelection:(id)sender;
- (void)searchFieldDidChange:(id)sender;
- (void)performSearch;
@end

@implementation CoverBrowserViewController

- (void)loadView {
  self.albums = [NSMutableArray array];
  self.filteredAlbums = [NSMutableArray array];
  self.sortOption = CoverBrowserSortOptionAlbumArtist;
  self.searchQuery = @"";

  NSView *baseView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 620)];
  self.view = baseView;

  NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
  header.translatesAutoresizingMaskIntoConstraints = NO;
  [baseView addSubview:header];

  NSView *sortContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  sortContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [header addSubview:sortContainer];

  NSTextField *sortLabel = [NSTextField labelWithString:@"Sort by:"];
  sortLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [sortContainer addSubview:sortLabel];

  self.sortPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                              pullsDown:NO];
  self.sortPopUp.translatesAutoresizingMaskIntoConstraints = NO;
  [self.sortPopUp addItemsWithTitles:@[ @"Album", @"Album Artist", @"Artist" ]];
  [self.sortPopUp selectItemAtIndex:self.sortOption];
  self.sortPopUp.target = self;
  self.sortPopUp.action = @selector(handleSortSelection:);
  [sortContainer addSubview:self.sortPopUp];

  NSButton *settingsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
  settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
  settingsButton.bezelStyle = NSBezelStyleRegularSquare;
  settingsButton.bordered = NO;

  NSImage *gearImage = [NSImage imageNamed:NSImageNameAdvanced];
  NSImage *resizedImage = [[NSImage alloc] initWithSize:NSMakeSize(24, 24)];
  [resizedImage lockFocus];
  [gearImage drawInRect:NSMakeRect(0, 0, 24, 24)
               fromRect:NSZeroRect
              operation:NSCompositingOperationCopy
               fraction:1.0];
  [resizedImage unlockFocus];
  settingsButton.image = resizedImage;
  settingsButton.toolTip = @"Settings";
  settingsButton.target = self;
  settingsButton.action = @selector(openSettings:);
  [header addSubview:settingsButton];

  self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.placeholderString = @"Search";
  self.searchField.target = self;
  self.searchField.action = @selector(searchFieldDidChange:);
  [header addSubview:self.searchField];

  NSCollectionViewFlowLayout *layout =
      [[NSCollectionViewFlowLayout alloc] init];
  layout.itemSize = NSMakeSize(160, 210);
  layout.sectionInset = NSEdgeInsetsMake(24, 24, 24, 24);
  layout.minimumLineSpacing = 18;
  layout.minimumInteritemSpacing = 16;

  self.collectionView =
      [[CoverBrowserCollectionView alloc] initWithFrame:baseView.bounds];
  self.collectionView.collectionViewLayout = layout;
  self.collectionView.dataSource = self;
  self.collectionView.delegate = self;
  self.collectionView.autoresizingMask =
      NSViewWidthSizable | NSViewHeightSizable;
  self.collectionView.interactionDelegate = self;
  [self.collectionView registerClass:[CoverBrowserCollectionItem class]
               forItemWithIdentifier:@"CoverBrowserItem"];

  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = self.collectionView;
  scrollView.hasVerticalScroller = YES;

  [baseView addSubview:scrollView];

  // Create spacing constraints with lower priority
  NSLayoutConstraint *sortToSearchSpacing = [sortContainer.trailingAnchor
      constraintLessThanOrEqualToAnchor:self.searchField.leadingAnchor
                               constant:-20.0];
  sortToSearchSpacing.priority = NSLayoutPriorityDefaultLow;

  NSLayoutConstraint *searchToSettingsSpacing = [self.searchField.trailingAnchor
      constraintLessThanOrEqualToAnchor:settingsButton.leadingAnchor
                               constant:-20.0];
  searchToSettingsSpacing.priority = NSLayoutPriorityDefaultLow;

  [NSLayoutConstraint activateConstraints:@[
    [header.topAnchor constraintEqualToAnchor:baseView.topAnchor constant:12.0],
    [header.leadingAnchor constraintEqualToAnchor:baseView.leadingAnchor
                                         constant:24.0],
    [header.trailingAnchor constraintEqualToAnchor:baseView.trailingAnchor
                                          constant:-24.0],
    [header.heightAnchor constraintEqualToConstant:28.0],

    [sortContainer.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [sortContainer.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [sortContainer.heightAnchor constraintEqualToAnchor:header.heightAnchor],

    [sortLabel.leadingAnchor
        constraintEqualToAnchor:sortContainer.leadingAnchor],
    [sortLabel.centerYAnchor
        constraintEqualToAnchor:sortContainer.centerYAnchor],

    [self.sortPopUp.leadingAnchor
        constraintEqualToAnchor:sortLabel.trailingAnchor
                       constant:8.0],
    [self.sortPopUp.trailingAnchor
        constraintEqualToAnchor:sortContainer.trailingAnchor],
    [self.sortPopUp.centerYAnchor
        constraintEqualToAnchor:sortContainer.centerYAnchor],
    [self.sortPopUp.widthAnchor constraintGreaterThanOrEqualToConstant:150.0],

    [settingsButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [settingsButton.trailingAnchor
        constraintEqualToAnchor:header.trailingAnchor],
    [settingsButton.widthAnchor constraintEqualToConstant:30.0],
    [settingsButton.heightAnchor constraintEqualToConstant:30.0],

    [self.searchField.centerXAnchor
        constraintEqualToAnchor:baseView.centerXAnchor],
    [self.searchField.centerYAnchor
        constraintEqualToAnchor:header.centerYAnchor],
    [self.searchField.widthAnchor constraintEqualToConstant:250.0],

    sortToSearchSpacing,
    searchToSettingsSpacing,

    [scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor
                                         constant:8.0],
    [scrollView.leadingAnchor constraintEqualToAnchor:baseView.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:baseView.trailingAnchor],
    [scrollView.bottomAnchor constraintEqualToAnchor:baseView.bottomAnchor]
  ]];

  [self refreshAlbums];
}

- (void)openSettings:(id)sender {
  static_api_ptr_t<ui_control>()->show_preferences(
      guid_cover_browser_preferences);
}

- (void)searchFieldDidChange:(id)sender {
  self.searchQuery = self.searchField.stringValue ?: @"";
  [self performSearch];
}

- (void)performSearch {
  [self.filteredAlbums removeAllObjects];

  if (self.searchQuery.length == 0) {
    [self.filteredAlbums addObjectsFromArray:self.albums];
  } else {
    NSString *lowercaseQuery = [self.searchQuery lowercaseString];

    for (CoverBrowserItem *item in self.albums) {
      BOOL matches = NO;

      // Search in album title
      if (item.albumTitle &&
          [[item.albumTitle lowercaseString] containsString:lowercaseQuery]) {
        matches = YES;
      }

      // Search in album artist
      if (!matches && item.albumArtist &&
          [[item.albumArtist lowercaseString] containsString:lowercaseQuery]) {
        matches = YES;
      }

      // Search in track artist
      if (!matches && item.trackArtist &&
          [[item.trackArtist lowercaseString] containsString:lowercaseQuery]) {
        matches = YES;
      }

      if (matches) {
        [self.filteredAlbums addObject:item];
      }
    }
  }

  [self.collectionView reloadData];
}

- (void)refreshAlbums {
  [self.albums removeAllObjects];

  pfc::list_t<metadb_handle_ptr> handles;
  library_manager::get()->get_all_items(handles);

  if (handles.get_count() == 0) {
    CoverBrowserItem *placeholder = [CoverBrowserItem new];
    placeholder.albumTitle = @"Your library is empty";
    placeholder.albumArtist = @"";
    placeholder.coverArt = [NSImage imageNamed:NSImageNameCaution];
    [self.albums addObject:placeholder];
    [self.collectionView reloadData];
    return;
  }

  titleformat_object::ptr tfAlbum;
  titleformat_object::ptr tfArtist;
  titleformat_object::ptr tfTrackArtist;
  titleformat_object::ptr tfAlbumMetaFlag;
  titleformat_object::ptr tfAlbumArtistMetaFlag;
  titleformat_object::ptr tfTrackArtistMetaFlag;
  titleformat_compiler::get()->compile(tfAlbum, "%album%");
  titleformat_compiler::get()->compile(tfArtist, "%album artist%");
  titleformat_compiler::get()->compile(tfTrackArtist, "%artist%");
  titleformat_compiler::get()->compile(tfAlbumMetaFlag, "$meta_test(album)");
  titleformat_compiler::get()->compile(tfAlbumArtistMetaFlag,
                                       "$meta_test(album artist)");
  titleformat_compiler::get()->compile(tfTrackArtistMetaFlag,
                                       "$meta_test(artist)");
  pfc::string8_fast bufAlbum, bufArtist, bufTrackArtist;
  pfc::string8_fast bufAlbumMetaFlag, bufArtistMetaFlag, bufTrackArtistMetaFlag;

  std::map<std::string, metadb_handle_ptr> byAlbum;

  for (size_t i = 0; i < handles.get_count(); ++i) {
    metadb_handle_ptr handle = handles[i];
    handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);
    std::string albumKey = bufAlbum.c_str();
    if (albumKey.empty())
      albumKey = "Unknown Album";
    if (byAlbum.find(albumKey) == byAlbum.end()) {
      byAlbum[albumKey] = handle;
    }
  }

  for (const auto &entry : byAlbum) {
    const std::string &albumKey = entry.first;
    metadb_handle_ptr handle = entry.second;

    bufAlbum.reset();
    handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);

    bufAlbumMetaFlag.reset();
    handle->format_title(nullptr, bufAlbumMetaFlag, tfAlbumMetaFlag, nullptr);
    const bool hasAlbumTag = bufAlbumMetaFlag.get_length() > 0 &&
                             bufAlbumMetaFlag.get_ptr()[0] != '0';

    NSString *albumDisplay = nil;
    if (!bufAlbum.is_empty()) {
      albumDisplay = [NSString stringWithUTF8String:bufAlbum.c_str()];
    } else {
      albumDisplay = [NSString stringWithUTF8String:albumKey.c_str()];
    }

    NSString *albumQuery = nil;
    NSData *albumQueryData = nil;
    if (hasAlbumTag && !bufAlbum.is_empty()) {
      albumQuery = [NSString stringWithUTF8String:bufAlbum.c_str()];
      albumQueryData = [NSData dataWithBytes:bufAlbum.c_str()
                                      length:bufAlbum.length()];
    }

    bufArtist.reset();
    handle->format_title(nullptr, bufArtist, tfArtist, nullptr);

    bufArtistMetaFlag.reset();
    handle->format_title(nullptr, bufArtistMetaFlag, tfAlbumArtistMetaFlag,
                         nullptr);
    const bool hasArtistTag = bufArtistMetaFlag.get_length() > 0 &&
                              bufArtistMetaFlag.get_ptr()[0] != '0';

    NSString *artistDisplay = nil;
    if (!bufArtist.is_empty()) {
      artistDisplay = [NSString stringWithUTF8String:bufArtist.c_str()];
    }
    if (artistDisplay == nil || artistDisplay.length == 0) {
      artistDisplay = @"Unknown Artist";
    }

    NSString *artistQuery = nil;
    NSData *artistQueryData = nil;
    if (hasArtistTag && !bufArtist.is_empty()) {
      artistQuery = [NSString stringWithUTF8String:bufArtist.c_str()];
      artistQueryData = [NSData dataWithBytes:bufArtist.c_str()
                                       length:bufArtist.length()];
    }

    bufTrackArtist.reset();
    handle->format_title(nullptr, bufTrackArtist, tfTrackArtist, nullptr);

    bufTrackArtistMetaFlag.reset();
    handle->format_title(nullptr, bufTrackArtistMetaFlag, tfTrackArtistMetaFlag,
                         nullptr);
    const bool hasTrackArtistTag = bufTrackArtistMetaFlag.get_length() > 0 &&
                                   bufTrackArtistMetaFlag.get_ptr()[0] != '0';

    NSString *trackArtistValue = nil;
    if (!bufTrackArtist.is_empty()) {
      trackArtistValue = [NSString stringWithUTF8String:bufTrackArtist.c_str()];
    }
    if (trackArtistValue == nil || trackArtistValue.length == 0) {
      trackArtistValue = artistDisplay;
    }

    CoverBrowserItem *item = [CoverBrowserItem new];
    item.albumTitle = albumDisplay;
    item.albumTitleQuery = albumQuery;
    item.albumTitleQueryData = albumQueryData;
    item.albumArtist = artistDisplay;
    item.albumArtistQuery = artistQuery;
    item.albumArtistQueryData = artistQueryData;
    item.trackArtist = trackArtistValue;
    item.hasAlbumTag = hasAlbumTag;
    item.hasAlbumArtistTag = hasArtistTag;
    item.hasTrackArtistTag = hasTrackArtistTag;
    item.coverArt = [NSImage imageNamed:NSImageNameFolder];
    [item setMetaDbHandle:&handle];

    [self.albums addObject:item];
  }

  [self sortAlbums];
  [self performSearch];
  [self loadCoverArtAsync];
}

- (void)loadCoverArtAsync {
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static_api_ptr_t<album_art_manager_v2> artMgr;
        abort_callback_dummy aborter;

        for (CoverBrowserItem *item in self.albums) {
          const metadb_handle_ptr *handlePtr =
              (const metadb_handle_ptr *)[item getMetaDbHandle];
          if (handlePtr == nullptr)
            continue;

          try {
            pfc::list_single_ref_t<metadb_handle_ptr> itemList(*handlePtr);
            pfc::list_single_ref_t<GUID> artIDs(album_art_ids::cover_front);

            album_art_extractor_instance_v2::ptr extractor =
                artMgr->open(itemList, artIDs, aborter);
            if (extractor.is_empty())
              continue;

            album_art_data::ptr data =
                extractor->query(album_art_ids::cover_front, aborter);
            if (data.is_empty())
              continue;

            NSData *nsData = [NSData dataWithBytes:data->get_ptr()
                                            length:data->get_size()];
            NSImage *art = [[NSImage alloc] initWithData:nsData];
            if (art == nil)
              continue;

            dispatch_async(dispatch_get_main_queue(), ^{
              item.coverArt = art;
              NSUInteger idx = [self.albums indexOfObjectIdenticalTo:item];
              if (idx != NSNotFound) {
                NSIndexPath *path = [NSIndexPath indexPathForItem:idx
                                                        inSection:0];
                [self.collectionView
                    reloadItemsAtIndexPaths:[NSSet setWithObject:path]];
              }
            });
          } catch (...) {
            // keep placeholder
          }
        }
      });
}

- (NSMenu *)collectionView:(CoverBrowserCollectionView *)collectionView
        menuForItemAtIndex:(NSInteger)index {
  if (index == NSNotFound || index >= (NSInteger)self.albums.count) {
    return nil;
  }

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"CoverBrowserMenu"];

  // Play at the top
  NSMenuItem *playItem =
      [[NSMenuItem alloc] initWithTitle:@"Play"
                                 action:@selector(handleContextMenuPlay:)
                          keyEquivalent:@""];
  playItem.target = self;
  playItem.representedObject = @(index);
  [menu addItem:playItem];

  // Separator line
  [menu addItem:[NSMenuItem separatorItem]];

  // Playlist operations
  NSMenuItem *sendToCurrentItem = [[NSMenuItem alloc]
      initWithTitle:@"Send to Current Playlist"
             action:@selector(handleContextMenuSendToCurrentPlaylist:)
      keyEquivalent:@""];
  sendToCurrentItem.target = self;
  sendToCurrentItem.representedObject = @(index);
  [menu addItem:sendToCurrentItem];

  NSMenuItem *addToCurrentItem = [[NSMenuItem alloc]
      initWithTitle:@"Add to Current Playlist"
             action:@selector(handleContextMenuAddToCurrentPlaylist:)
      keyEquivalent:@""];
  addToCurrentItem.target = self;
  addToCurrentItem.representedObject = @(index);
  [menu addItem:addToCurrentItem];

  NSMenuItem *sendToNewItem = [[NSMenuItem alloc]
      initWithTitle:@"Send to New Playlist"
             action:@selector(handleContextMenuSendToNewPlaylist:)
      keyEquivalent:@""];
  sendToNewItem.target = self;
  sendToNewItem.representedObject = @(index);
  [menu addItem:sendToNewItem];

  return menu;
}

- (void)handleContextMenuCreateAutoplaylist:(NSMenuItem *)sender {
  NSInteger index = [sender.representedObject integerValue];
  if (index == NSNotFound || index >= (NSInteger)self.albums.count) {
    return;
  }
  CoverBrowserItem *item = self.albums[index];
  [self createAutoplaylistForItem:item];
}

- (void)handleContextMenuPlay:(NSMenuItem *)sender {
  NSInteger index = [sender.representedObject integerValue];
  if (index == NSNotFound || index >= (NSInteger)self.filteredAlbums.count) {
    return;
  }
  CoverBrowserItem *item = self.filteredAlbums[index];

  // Get tracks for the album
  NSString *albumQueryString = item.albumTitleQuery;
  NSString *artistQueryString = item.albumArtistQuery;
  NSData *albumQueryData = item.albumTitleQueryData;
  NSData *artistQueryData = item.albumArtistQueryData;

  std::string albumQueryUTF8;
  if (albumQueryData != nil && albumQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(albumQueryData.bytes);
    size_t length = (size_t)albumQueryData.length;
    albumQueryUTF8.assign(bytes, length);
  } else if (albumQueryString != nil) {
    const char *utf8 = [albumQueryString UTF8String];
    if (utf8 != nullptr) {
      albumQueryUTF8.assign(utf8);
    }
  }

  std::string artistQueryUTF8;
  if (artistQueryData != nil && artistQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(artistQueryData.bytes);
    size_t length = (size_t)artistQueryData.length;
    artistQueryUTF8.assign(bytes, length);
  } else if (artistQueryString != nil) {
    const char *utf8 = [artistQueryString UTF8String];
    if (utf8 != nullptr) {
      artistQueryUTF8.assign(utf8);
    }
  }

  BOOL hasAlbumTag = item.hasAlbumTag;
  BOOL hasArtistTag = item.hasAlbumArtistTag;

  // Get all library items and filter
  pfc::list_t<metadb_handle_ptr> allHandles;
  library_manager::get()->get_all_items(allHandles);

  pfc::list_t<metadb_handle_ptr> tracks;
  titleformat_object::ptr tfAlbum;
  titleformat_object::ptr tfArtist;
  titleformat_compiler::get()->compile(tfAlbum, "%album%");
  titleformat_compiler::get()->compile(tfArtist, "%album artist%");

  pfc::string8_fast bufAlbum, bufArtist;

  for (size_t i = 0; i < allHandles.get_count(); ++i) {
    metadb_handle_ptr handle = allHandles[i];
    bool matches = true;

    if (hasAlbumTag && !albumQueryUTF8.empty()) {
      bufAlbum.reset();
      handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);
      if (strcmp(bufAlbum.c_str(), albumQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches && hasArtistTag && !artistQueryUTF8.empty()) {
      bufArtist.reset();
      handle->format_title(nullptr, bufArtist, tfArtist, nullptr);
      if (strcmp(bufArtist.c_str(), artistQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches) {
      tracks.add_item(handle);
    }
  }

  if (tracks.get_count() == 0)
    return;

  // Clear playlist, add tracks, and play
  fb2k::inMainThread([tracks]() {
    static_api_ptr_t<playlist_manager> playlistAPI;
    t_size activePlaylist = playlistAPI->get_active_playlist();

    if (activePlaylist == pfc_infinite) {
      activePlaylist = playlistAPI->create_playlist("Default", 7, pfc_infinite);
      playlistAPI->set_active_playlist(activePlaylist);
    }

    playlistAPI->playlist_clear(activePlaylist);
    playlistAPI->playlist_add_items(activePlaylist, tracks, bit_array_false());

    // Set the focus and playing item to the first track, then start playback
    playlistAPI->set_playing_playlist(activePlaylist);
    playlistAPI->playlist_set_focus_item(activePlaylist, 0);
    playlistAPI->playlist_execute_default_action(activePlaylist, 0);
  });
}

- (void)handleContextMenuSendToCurrentPlaylist:(NSMenuItem *)sender {
  NSInteger index = [sender.representedObject integerValue];
  if (index == NSNotFound || index >= (NSInteger)self.filteredAlbums.count) {
    return;
  }
  CoverBrowserItem *item = self.filteredAlbums[index];

  // Get tracks for the album
  NSString *albumQueryString = item.albumTitleQuery;
  NSString *artistQueryString = item.albumArtistQuery;
  NSData *albumQueryData = item.albumTitleQueryData;
  NSData *artistQueryData = item.albumArtistQueryData;

  std::string albumQueryUTF8;
  if (albumQueryData != nil && albumQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(albumQueryData.bytes);
    size_t length = (size_t)albumQueryData.length;
    albumQueryUTF8.assign(bytes, length);
  } else if (albumQueryString != nil) {
    const char *utf8 = [albumQueryString UTF8String];
    if (utf8 != nullptr) {
      albumQueryUTF8.assign(utf8);
    }
  }

  std::string artistQueryUTF8;
  if (artistQueryData != nil && artistQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(artistQueryData.bytes);
    size_t length = (size_t)artistQueryData.length;
    artistQueryUTF8.assign(bytes, length);
  } else if (artistQueryString != nil) {
    const char *utf8 = [artistQueryString UTF8String];
    if (utf8 != nullptr) {
      artistQueryUTF8.assign(utf8);
    }
  }

  BOOL hasAlbumTag = item.hasAlbumTag;
  BOOL hasArtistTag = item.hasAlbumArtistTag;

  // Get all library items and filter
  pfc::list_t<metadb_handle_ptr> allHandles;
  library_manager::get()->get_all_items(allHandles);

  pfc::list_t<metadb_handle_ptr> tracks;
  titleformat_object::ptr tfAlbum;
  titleformat_object::ptr tfArtist;
  titleformat_compiler::get()->compile(tfAlbum, "%album%");
  titleformat_compiler::get()->compile(tfArtist, "%album artist%");

  pfc::string8_fast bufAlbum, bufArtist;

  for (size_t i = 0; i < allHandles.get_count(); ++i) {
    metadb_handle_ptr handle = allHandles[i];
    bool matches = true;

    if (hasAlbumTag && !albumQueryUTF8.empty()) {
      bufAlbum.reset();
      handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);
      if (strcmp(bufAlbum.c_str(), albumQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches && hasArtistTag && !artistQueryUTF8.empty()) {
      bufArtist.reset();
      handle->format_title(nullptr, bufArtist, tfArtist, nullptr);
      if (strcmp(bufArtist.c_str(), artistQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches) {
      tracks.add_item(handle);
    }
  }

  if (tracks.get_count() == 0)
    return;

  // Clear current playlist and add tracks
  fb2k::inMainThread([tracks]() {
    static_api_ptr_t<playlist_manager> playlistAPI;
    t_size activePlaylist = playlistAPI->get_active_playlist();

    if (activePlaylist == pfc_infinite) {
      activePlaylist = playlistAPI->create_playlist("Default", 7, pfc_infinite);
      playlistAPI->set_active_playlist(activePlaylist);
    }

    playlistAPI->playlist_clear(activePlaylist);
    playlistAPI->playlist_add_items(activePlaylist, tracks, bit_array_false());
  });
}

- (void)handleContextMenuAddToCurrentPlaylist:(NSMenuItem *)sender {
  NSInteger index = [sender.representedObject integerValue];
  if (index == NSNotFound || index >= (NSInteger)self.filteredAlbums.count) {
    return;
  }
  CoverBrowserItem *item = self.filteredAlbums[index];

  // Get tracks for the album
  NSString *albumQueryString = item.albumTitleQuery;
  NSString *artistQueryString = item.albumArtistQuery;
  NSData *albumQueryData = item.albumTitleQueryData;
  NSData *artistQueryData = item.albumArtistQueryData;

  std::string albumQueryUTF8;
  if (albumQueryData != nil && albumQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(albumQueryData.bytes);
    size_t length = (size_t)albumQueryData.length;
    albumQueryUTF8.assign(bytes, length);
  } else if (albumQueryString != nil) {
    const char *utf8 = [albumQueryString UTF8String];
    if (utf8 != nullptr) {
      albumQueryUTF8.assign(utf8);
    }
  }

  std::string artistQueryUTF8;
  if (artistQueryData != nil && artistQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(artistQueryData.bytes);
    size_t length = (size_t)artistQueryData.length;
    artistQueryUTF8.assign(bytes, length);
  } else if (artistQueryString != nil) {
    const char *utf8 = [artistQueryString UTF8String];
    if (utf8 != nullptr) {
      artistQueryUTF8.assign(utf8);
    }
  }

  BOOL hasAlbumTag = item.hasAlbumTag;
  BOOL hasArtistTag = item.hasAlbumArtistTag;

  // Get all library items and filter
  pfc::list_t<metadb_handle_ptr> allHandles;
  library_manager::get()->get_all_items(allHandles);

  pfc::list_t<metadb_handle_ptr> tracks;
  titleformat_object::ptr tfAlbum;
  titleformat_object::ptr tfArtist;
  titleformat_compiler::get()->compile(tfAlbum, "%album%");
  titleformat_compiler::get()->compile(tfArtist, "%album artist%");

  pfc::string8_fast bufAlbum, bufArtist;

  for (size_t i = 0; i < allHandles.get_count(); ++i) {
    metadb_handle_ptr handle = allHandles[i];
    bool matches = true;

    if (hasAlbumTag && !albumQueryUTF8.empty()) {
      bufAlbum.reset();
      handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);
      if (strcmp(bufAlbum.c_str(), albumQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches && hasArtistTag && !artistQueryUTF8.empty()) {
      bufArtist.reset();
      handle->format_title(nullptr, bufArtist, tfArtist, nullptr);
      if (strcmp(bufArtist.c_str(), artistQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches) {
      tracks.add_item(handle);
    }
  }

  if (tracks.get_count() == 0)
    return;

  // Add tracks to current playlist without clearing
  fb2k::inMainThread([tracks]() {
    static_api_ptr_t<playlist_manager> playlistAPI;
    t_size activePlaylist = playlistAPI->get_active_playlist();

    if (activePlaylist == pfc_infinite) {
      activePlaylist = playlistAPI->create_playlist("Default", 7, pfc_infinite);
      playlistAPI->set_active_playlist(activePlaylist);
    }

    playlistAPI->playlist_add_items(activePlaylist, tracks, bit_array_false());
  });
}

- (void)handleContextMenuSendToNewPlaylist:(NSMenuItem *)sender {
  NSInteger index = [sender.representedObject integerValue];
  if (index == NSNotFound || index >= (NSInteger)self.filteredAlbums.count) {
    return;
  }
  CoverBrowserItem *item = self.filteredAlbums[index];

  NSString *albumDisplay = item.albumTitle ?: @"Unknown Album";
  std::string albumDisplayUTF8 = albumDisplay.length > 0
                                     ? std::string([albumDisplay UTF8String])
                                     : std::string("Unknown Album");

  // Get tracks for the album
  NSString *albumQueryString = item.albumTitleQuery;
  NSString *artistQueryString = item.albumArtistQuery;
  NSData *albumQueryData = item.albumTitleQueryData;
  NSData *artistQueryData = item.albumArtistQueryData;

  std::string albumQueryUTF8;
  if (albumQueryData != nil && albumQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(albumQueryData.bytes);
    size_t length = (size_t)albumQueryData.length;
    albumQueryUTF8.assign(bytes, length);
  } else if (albumQueryString != nil) {
    const char *utf8 = [albumQueryString UTF8String];
    if (utf8 != nullptr) {
      albumQueryUTF8.assign(utf8);
    }
  }

  std::string artistQueryUTF8;
  if (artistQueryData != nil && artistQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(artistQueryData.bytes);
    size_t length = (size_t)artistQueryData.length;
    artistQueryUTF8.assign(bytes, length);
  } else if (artistQueryString != nil) {
    const char *utf8 = [artistQueryString UTF8String];
    if (utf8 != nullptr) {
      artistQueryUTF8.assign(utf8);
    }
  }

  BOOL hasAlbumTag = item.hasAlbumTag;
  BOOL hasArtistTag = item.hasAlbumArtistTag;

  // Get all library items and filter
  pfc::list_t<metadb_handle_ptr> allHandles;
  library_manager::get()->get_all_items(allHandles);

  pfc::list_t<metadb_handle_ptr> tracks;
  titleformat_object::ptr tfAlbum;
  titleformat_object::ptr tfArtist;
  titleformat_compiler::get()->compile(tfAlbum, "%album%");
  titleformat_compiler::get()->compile(tfArtist, "%album artist%");

  pfc::string8_fast bufAlbum, bufArtist;

  for (size_t i = 0; i < allHandles.get_count(); ++i) {
    metadb_handle_ptr handle = allHandles[i];
    bool matches = true;

    if (hasAlbumTag && !albumQueryUTF8.empty()) {
      bufAlbum.reset();
      handle->format_title(nullptr, bufAlbum, tfAlbum, nullptr);
      if (strcmp(bufAlbum.c_str(), albumQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches && hasArtistTag && !artistQueryUTF8.empty()) {
      bufArtist.reset();
      handle->format_title(nullptr, bufArtist, tfArtist, nullptr);
      if (strcmp(bufArtist.c_str(), artistQueryUTF8.c_str()) != 0) {
        matches = false;
      }
    }

    if (matches) {
      tracks.add_item(handle);
    }
  }

  if (tracks.get_count() == 0)
    return;

  // Create new playlist with album name and add tracks
  fb2k::inMainThread([tracks,
                      albumDisplayName = std::move(albumDisplayUTF8)]() {
    static_api_ptr_t<playlist_manager> playlistAPI;

    pfc::string8 playlistName;
    playlistName << albumDisplayName.c_str();

    t_size playlistIndex = playlistAPI->create_playlist(
        playlistName.c_str(), playlistName.length(), pfc_infinite);
    if (playlistIndex == pfc_infinite)
      return;

    playlistAPI->playlist_add_items(playlistIndex, tracks, bit_array_false());
    playlistAPI->set_active_playlist(playlistIndex);
  });
}

- (void)createAutoplaylistForItem:(CoverBrowserItem *)item {
  if (item == nil)
    return;
  NSString *albumDisplay = item.albumTitle ?: @"Unknown Album";
  NSString *albumQueryString = item.albumTitleQuery;
  NSString *artistQueryString = item.albumArtistQuery;
  NSString *trackArtist = item.trackArtist;
  NSData *albumQueryData = item.albumTitleQueryData;
  NSData *artistQueryData = item.albumArtistQueryData;

  std::string albumQueryUTF8;
  if (albumQueryData != nil && albumQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(albumQueryData.bytes);
    size_t length = (size_t)albumQueryData.length;
    albumQueryUTF8.assign(bytes, length);
  } else if (albumQueryString != nil) {
    const char *utf8 = [albumQueryString UTF8String];
    if (utf8 != nullptr) {
      albumQueryUTF8.assign(utf8);
    }
  }

  std::string artistQueryUTF8;
  if (artistQueryData != nil && artistQueryData.length > 0) {
    const char *bytes = static_cast<const char *>(artistQueryData.bytes);
    size_t length = (size_t)artistQueryData.length;
    artistQueryUTF8.assign(bytes, length);
  } else if (artistQueryString != nil) {
    const char *utf8 = [artistQueryString UTF8String];
    if (utf8 != nullptr) {
      artistQueryUTF8.assign(utf8);
    }
  }

  std::string albumDisplayUTF8 = albumDisplay.length > 0
                                     ? std::string([albumDisplay UTF8String])
                                     : std::string("Unknown Album");

  BOOL hasAlbumTag = item.hasAlbumTag;
  BOOL hasArtistTag = item.hasAlbumArtistTag;
  BOOL hasTrackArtistTag = item.hasTrackArtistTag;

  NSString *normalizedArtistQuery = NormalizeQueryToken(artistQueryString);
  NSString *normalizedTrackArtist = NormalizeQueryToken(trackArtist);

  BOOL includeAlbumArtist = hasArtistTag && normalizedArtistQuery != nil &&
                            normalizedArtistQuery.length > 0;
  if (includeAlbumArtist && hasTrackArtistTag && normalizedTrackArtist != nil &&
      normalizedTrackArtist.length > 0) {
    if ([normalizedArtistQuery caseInsensitiveCompare:normalizedTrackArtist] ==
        NSOrderedSame) {
      includeAlbumArtist = NO;
    }
  }

  bool includeAlbumArtistFlag = includeAlbumArtist ? true : false;

  fb2k::inMainThread([albumName = std::move(albumQueryUTF8),
                      artistName = std::move(artistQueryUTF8),
                      albumDisplayName = std::move(albumDisplayUTF8),
                      hasAlbumTag = hasAlbumTag,
                      includeAlbumArtistFlag = includeAlbumArtistFlag]() {
    static_api_ptr_t<playlist_manager> playlistAPI;
    static_api_ptr_t<autoplaylist_manager> autoplayAPI;

    pfc::string8 playlistName;
    playlistName << "Cover: "
                 << (albumDisplayName.empty() ? "Unknown Album"
                                              : albumDisplayName.c_str());

    t_size playlistIndex =
        playlistAPI->find_playlist(playlistName.c_str(), playlistName.length());
    if (playlistIndex == pfc_infinite) {
      playlistIndex = playlistAPI->create_playlist(
          playlistName.c_str(), playlistName.length(), pfc_infinite);
    }
    if (playlistIndex == pfc_infinite)
      return;

    try {
      if (autoplayAPI->is_client_present(playlistIndex)) {
        autoplayAPI->remove_client(playlistIndex);
      }
    } catch (...) {
      // not an autoplaylist yet, ignore
    }

    pfc::string_formatter queryFmt;
    if (hasAlbumTag && !albumName.empty()) {
      pfc::string8 albumEsc = escape_for_query(albumName.c_str());
      queryFmt << "album IS \"" << albumEsc << "\"";
    } else {
      queryFmt << "NOT %album% PRESENT";
    }

    if (includeAlbumArtistFlag && !artistName.empty()) {
      pfc::string8 artistEsc = escape_for_query(artistName.c_str());
      queryFmt << " AND album artist IS \"" << artistEsc << "\"";
    }

    const char *sortPattern = "%discnumber%|%tracknumber%";

    try {
      autoplayAPI->add_client_simple(queryFmt.get_ptr(), sortPattern,
                                     playlistIndex, autoplaylist_flag_sort);
    } catch (exception_autoplaylist_already_owned &) {
      // already configured; nothing else to do
    } catch (exception_autoplaylist &) {
      return;
    }

    playlistAPI->set_active_playlist(playlistIndex);
  });
}

- (void)sortAlbums {
  if (self.albums.count <= 1)
    return;

  CoverBrowserSortOption option = (CoverBrowserSortOption)self.sortOption;

  [self.albums sortUsingComparator:^NSComparisonResult(CoverBrowserItem *a,
                                                       CoverBrowserItem *b) {
    NSString *left = nil;
    NSString *right = nil;

    switch (option) {
    case CoverBrowserSortOptionAlbumArtist:
      left = a.albumArtist ?: @"";
      right = b.albumArtist ?: @"";
      break;
    case CoverBrowserSortOptionArtist:
      left = a.trackArtist ?: (a.albumArtist ?: @"");
      right = b.trackArtist ?: (b.albumArtist ?: @"");
      break;
    case CoverBrowserSortOptionAlbum:
    default:
      left = a.albumTitle ?: @"";
      right = b.albumTitle ?: @"";
      break;
    }

    NSComparisonResult comparison =
        [left localizedCaseInsensitiveCompare:right];
    if (comparison == NSOrderedSame) {
      NSString *secondaryLeft = a.albumTitle ?: @"";
      NSString *secondaryRight = b.albumTitle ?: @"";
      comparison =
          [secondaryLeft localizedCaseInsensitiveCompare:secondaryRight];
    }
    return comparison;
  }];
}

- (void)handleSortSelection:(id)sender {
  NSInteger selectedIndex = [self.sortPopUp indexOfSelectedItem];
  if (selectedIndex == NSNotFound) {
    return;
  }
  self.sortOption = selectedIndex;
  [self sortAlbums];
  [self performSearch];
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:
    (NSCollectionView *)collectionView {
  return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
  return self.filteredAlbums.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
  CoverBrowserCollectionItem *item =
      [collectionView makeItemWithIdentifier:@"CoverBrowserItem"
                                forIndexPath:indexPath];

  CoverBrowserItem *model = self.filteredAlbums[indexPath.item];
  item.textField.stringValue = model.albumTitle ?: @"";
  item.imageView.image =
      model.coverArt ?: [NSImage imageNamed:NSImageNameFolder];
  item.representedObject = model;

  return item;
}

@end
