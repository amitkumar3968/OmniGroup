// Copyright 2003-2008, 2010, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFTestCase.h"

@interface OATestCase : OFTestCase
// This just has some +initialize crud to make this (hopefully) run better
@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniAppKit/OAController.h>
#import <AppKit/NSApplication.h>
@interface OATestController : OAController <NSApplicationDelegate>
@end
#endif


// NSTextStorage does NOT reset the length of its editedRange in processEditing. Only the location gets reset to NSNotFound.
#define OAAssertNoPendingTextStorageEdits(ts) do { \
    XCTAssertEqual([ts editedMask], 0UL); \
    XCTAssertEqual([ts changeInLength], 0L); \
    NSRange editedRange = [ts editedRange]; \
    XCTAssertEqual(editedRange.location, (NSUInteger)NSNotFound); \
} while(0)
