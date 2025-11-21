#import "CoverBrowserCollectionView.h"

@implementation CoverBrowserCollectionView

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];

    if (event.type == NSEventTypeLeftMouseDown && event.clickCount >= 2) {
        id<CoverBrowserCollectionViewDelegate> delegate = self.interactionDelegate;
        if ([delegate respondsToSelector:@selector(collectionViewDidReceiveDoubleClick:)]) {
            [delegate collectionViewDidReceiveDoubleClick:self];
        }
    }
}

- (NSInteger)indexForPoint:(NSPoint)point {
    for (NSCollectionViewItem *item in self.visibleItems) {
        NSView *itemView = item.view;
        if (itemView == nil) continue;
        NSRect frameInSelf = [itemView.superview convertRect:itemView.frame toView:self];
        if (NSPointInRect(point, frameInSelf)) {
            NSIndexPath *indexPath = [self indexPathForItem:item];
            if (indexPath != nil) {
                return indexPath.item;
            }
        }
    }
    return NSNotFound;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexForPoint:point];
    if (index != NSNotFound) {
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:index];
        [self setSelectionIndexes:indexes];
    }

    id<CoverBrowserCollectionViewDelegate> delegate = self.interactionDelegate;
    if ([delegate respondsToSelector:@selector(collectionView:menuForItemAtIndex:)]) {
        NSMenu *menu = [delegate collectionView:self menuForItemAtIndex:index];
        if (menu != nil) {
            return menu;
        }
    }
    return [super menuForEvent:event];
}

@end
