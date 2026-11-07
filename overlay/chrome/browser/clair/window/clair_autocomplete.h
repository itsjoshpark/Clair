// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_AUTOCOMPLETE_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_AUTOCOMPLETE_H_

#import <Foundation/Foundation.h>

#import "chrome/browser/clair/ClairHost.h"

class ClairBrowserWindow;

// One command bar session (design D11): Chromium's AutocompleteController for
// the window's profile, with the omnibox's providers apart from bookmarks.
@interface ClairChromiumAutocomplete : NSObject <ClairAutocomplete>

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow
                                 mode:(ClairCommandBarMode)mode
                             delegate:(id<ClairAutocompleteDelegate>)delegate;

@end

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_AUTOCOMPLETE_H_
