#import <Cocoa/Cocoa.h>
#import "CoverBrowserCollectionView.h"

@class CoverBrowserItem;
@class CoverBrowserCollectionView;

@interface CoverBrowserViewController : NSViewController <NSCollectionViewDataSource, NSCollectionViewDelegate, CoverBrowserCollectionViewDelegate>

@property (nonatomic, strong) CoverBrowserCollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<CoverBrowserItem *> *albums;
@property (nonatomic, strong) NSPopUpButton *sortPopUp;
@property (nonatomic, assign) NSInteger sortOption;

@end
