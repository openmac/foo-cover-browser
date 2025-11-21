#import <Cocoa/Cocoa.h>
#include "foobar2000/SDK/foobar2000.h"
#import "CoverBrowserViewController.h"

DECLARE_COMPONENT_VERSION(
    "Cover Browser",
    "1.0.0",
    "Displays Foobar2000 albums and their cover art in a Mac-native grid window."
);

// {4E0CE0D4-EB22-4F60-A9A9-824BC020AA87}
static const GUID kCoverBrowserCmdGuid =
{ 0x4e0ce0d4, 0xeb22, 0x4f60, { 0xa9, 0xa9, 0x82, 0x4b, 0xc0, 0x20, 0xaa, 0x87 } };

static NSWindowController *s_coverWindowController = nil;

class cover_browser_mainmenu : public mainmenu_commands {
public:
    t_uint32 get_command_count() override { return 1; }
    GUID get_parent() override { return mainmenu_groups::view; }
    GUID get_command(t_uint32) override { return kCoverBrowserCmdGuid; }

    void get_name(t_uint32, pfc::string_base & out) override {
        out = "Cover Browser";
    }
    bool get_description(t_uint32, pfc::string_base & out) override {
        out = "Open a gallery with cover artwork and album titles.";
        return true;
    }

    void execute(t_uint32, service_ptr_t<service_base>) override {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (s_coverWindowController == nil) {
                NSRect frame = NSMakeRect(120, 120, 900, 620);
                // Added NSWindowStyleMaskMiniaturizable to enable minimize button
                NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                               styleMask:(NSWindowStyleMaskTitled |
                                                                          NSWindowStyleMaskClosable |
                                                                          NSWindowStyleMaskResizable |
                                                                          NSWindowStyleMaskMiniaturizable)
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];
                window.title = @"Cover Browser";

                CoverBrowserViewController *vc = [[CoverBrowserViewController alloc] init];
                window.contentViewController = vc;

                s_coverWindowController = [[NSWindowController alloc] initWithWindow:window];
            }

            [s_coverWindowController showWindow:nil];
            [s_coverWindowController.window makeKeyAndOrderFront:nil];
        });
    }
};

static service_factory_single_t<cover_browser_mainmenu> g_cover_browser_factory;
