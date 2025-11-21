#import <Cocoa/Cocoa.h>

@class CoverBrowserCollectionView;

@protocol CoverBrowserCollectionViewDelegate <NSObject>
- (void)collectionViewDidReceiveDoubleClick:(CoverBrowserCollectionView *)collectionView;
@optional
- (NSMenu *)collectionView:(CoverBrowserCollectionView *)collectionView menuForItemAtIndex:(NSInteger)index;
@end

@interface CoverBrowserCollectionView : NSCollectionView

@property (nonatomic, weak) id<CoverBrowserCollectionViewDelegate> interactionDelegate;

@end
