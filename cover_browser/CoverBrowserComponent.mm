#import "CoverBrowserPreferences.h"
#import "CoverBrowserViewController.h"
#include "foobar2000/SDK/commonObjects-Apple.h"
#include "foobar2000/SDK/foobar2000.h"
#include "foobar2000/SDK/preferences_page.h"
#import <Cocoa/Cocoa.h>

cfg_bool cfg_open_on_startup(guid_cfg_open_on_startup, false);

DECLARE_COMPONENT_VERSION("Cover Browser", "1.0.0",
                          "Displays Foobar2000 albums and their cover art in a "
                          "Mac-native grid window.");

// {4E0CE0D4-EB22-4F60-A9A9-824BC020AA87}
static const GUID kCoverBrowserCmdGuid = {
    0x4e0ce0d4,
    0xeb22,
    0x4f60,
    {0xa9, 0xa9, 0x82, 0x4b, 0xc0, 0x20, 0xaa, 0x87}};

static NSWindowController *s_coverWindowController = nil;

void ShowCoverBrowserWindow() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (s_coverWindowController == nil) {
      NSRect frame = NSMakeRect(120, 120, 900, 620);
      // Added NSWindowStyleMaskMiniaturizable to enable minimize button
      NSWindow *window = [[NSWindow alloc]
          initWithContentRect:frame
                    styleMask:(NSWindowStyleMaskTitled |
                               NSWindowStyleMaskClosable |
                               NSWindowStyleMaskResizable |
                               NSWindowStyleMaskMiniaturizable)
                      backing:NSBackingStoreBuffered
                        defer:NO];
      window.title = @"Cover Browser";

      CoverBrowserViewController *vc =
          [[CoverBrowserViewController alloc] init];
      window.contentViewController = vc;

      s_coverWindowController =
          [[NSWindowController alloc] initWithWindow:window];
    }

    [s_coverWindowController showWindow:nil];
    [s_coverWindowController.window makeKeyAndOrderFront:nil];
  });
}

class cover_browser_mainmenu : public mainmenu_commands {
public:
  t_uint32 get_command_count() override { return 1; }
  GUID get_parent() override { return mainmenu_groups::view; }
  GUID get_command(t_uint32) override { return kCoverBrowserCmdGuid; }

  void get_name(t_uint32, pfc::string_base &out) override {
    out = "Cover Browser";
  }
  bool get_description(t_uint32, pfc::string_base &out) override {
    out = "Open a gallery with cover artwork and album titles.";
    return true;
  }

  void execute(t_uint32, service_ptr_t<service_base>) override {
    ShowCoverBrowserWindow();
  }
};

static service_factory_single_t<cover_browser_mainmenu> g_cover_browser_factory;

class CoverBrowserInitQuit : public initquit {
public:
  void on_init() override {
    if (cfg_open_on_startup) {
      ShowCoverBrowserWindow();
    }
  }
  void on_quit() override {}
};
static initquit_factory_t<CoverBrowserInitQuit>
    g_cover_browser_initquit_factory;

@interface CoverBrowserPreferencesViewController : NSViewController
@property(nonatomic, strong) NSButton *startupCheckbox;
@end

@implementation CoverBrowserPreferencesViewController

- (void)loadView {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
  self.view = view;

  self.startupCheckbox =
      [NSButton checkboxWithTitle:@"Open Cover Browser on startup"
                           target:self
                           action:@selector(checkboxToggled:)];
  self.startupCheckbox.frame = NSMakeRect(20, 60, 260, 24);
  [view addSubview:self.startupCheckbox];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.startupCheckbox.state =
      cfg_open_on_startup ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)checkboxToggled:(NSButton *)sender {
  cfg_open_on_startup = (sender.state == NSControlStateValueOn);
}

@end

class CoverBrowserPreferences : public preferences_page_v3 {
public:
  const char *get_name() override { return "Cover Browser"; }
  GUID get_guid() override { return guid_cover_browser_preferences; }
  GUID get_parent_guid() override { return guid_tools; }

  service_ptr instantiate() override {
    CoverBrowserPreferencesViewController *vc =
        [[CoverBrowserPreferencesViewController alloc] init];
    return fb2k::wrapNSObject(vc);
  }
};

static preferences_page_factory_t<CoverBrowserPreferences>
    g_cover_browser_preferences_factory;
