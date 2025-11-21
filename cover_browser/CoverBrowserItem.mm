#import "CoverBrowserItem.h"
#include "foobar2000/SDK/foobar2000.h"

@interface CoverBrowserItem () {
    metadb_handle_ptr _handle;
}
@end

@implementation CoverBrowserItem

- (void)setMetaDbHandle:(const void *)handlePtr {
    if (handlePtr != nullptr) {
        const metadb_handle_ptr *typed = (const metadb_handle_ptr *)handlePtr;
        _handle = *typed;
    }
}

- (const void *)getMetaDbHandle {
    return &_handle;
}

@end
