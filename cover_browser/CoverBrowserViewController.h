#import "CoverBrowserCollectionView.h"
#import <Cocoa/Cocoa.h>

@class CoverBrowserItem;
@class CoverBrowserCollectionView;

@interface CoverBrowserViewController
    : NSViewController <NSCollectionViewDataSource, NSCollectionViewDelegate,
                        CoverBrowserCollectionViewDelegate>

@property(nonatomic, strong) CoverBrowserCollectionView *collectionView;
@property(nonatomic, strong) NSMutableArray<CoverBrowserItem *> *albums;
@property(nonatomic, strong) NSMutableArray<CoverBrowserItem *> *filteredAlbums;
@property(nonatomic, strong) NSPopUpButton *sortPopUp;
@property(nonatomic, strong) NSSearchField *searchField;
@property(nonatomic, copy) NSString *searchQuery;
@property(nonatomic, assign) NSInteger sortOption;

@end
