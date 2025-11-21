#import "CoverBrowserCollectionItem.h"

@implementation CoverBrowserCollectionItem

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160, 210)];
    self.view.wantsLayer = YES;
    self.view.layer.cornerRadius = 8.0;

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(15, 55, 130, 130)];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.imageFrameStyle = NSImageFrameNone;
    imageView.wantsLayer = YES;
    imageView.layer.cornerRadius = 6.0;
    imageView.layer.masksToBounds = YES;
    self.imageView = imageView;
    [self.view addSubview:imageView];

    NSTextField *title = [NSTextField labelWithString:@""];
    title.frame = NSMakeRect(5, 30, 150, 20);
    title.alignment = NSTextAlignmentCenter;
    title.font = [NSFont boldSystemFontOfSize:13];
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    self.textField = title;
    [self.view addSubview:title];

    NSTextField *subtitle = [NSTextField labelWithString:@""];
    subtitle.tag = 101;
    subtitle.frame = NSMakeRect(5, 10, 150, 18);
    subtitle.alignment = NSTextAlignmentCenter;
    subtitle.font = [NSFont systemFontOfSize:11];
    subtitle.textColor = [NSColor secondaryLabelColor];
    subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:subtitle];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    NSTextField *subtitle = [self.view viewWithTag:101];
    subtitle.stringValue = [representedObject valueForKey:@"albumArtist"] ?: @"";
}

@end
