// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_DOWNLOADS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_DOWNLOADS_H_

#import <Foundation/Foundation.h>

#include <memory>
#include <set>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#import "chrome/browser/clair/ClairHost.h"
#include "components/download/content/public/all_download_item_notifier.h"

class ClairBrowserWindow;

namespace download {
class DownloadItem;
}  // namespace download

// The sidebar's downloads (design D7): this session's downloads of the
// window's profile, as snapshots, and the list's actions on them.
class ClairDownloads : public download::AllDownloadItemNotifier::Observer {
 public:
  explicit ClairDownloads(ClairBrowserWindow* window);
  ClairDownloads(const ClairDownloads&) = delete;
  ClairDownloads& operator=(const ClairDownloads&) = delete;
  ~ClairDownloads() override;

  // Newest first.
  NSArray<id<ClairDownload>>* Snapshot();

  // The whole app's download progress, from the DownloadStatusUpdater that
  // drives the Dock icon.
  static ClairDownloadProgress Progress();

  void Open(const std::string& guid);
  void ShowInFinder(const std::string& guid);
  void Cancel(const std::string& guid);
  void Resume(const std::string& guid);
  void Keep(const std::string& guid);
  void Discard(const std::string& guid);
  void MarkSeen();

  // download::AllDownloadItemNotifier::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override;
  void OnDownloadOpened(content::DownloadManager* manager,
                        download::DownloadItem* item) override;
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override;

 private:
  download::DownloadItem* Find(const std::string& guid);
  bool IsFromThisSession(download::DownloadItem* item) const;
  void Changed();
  void Flush();

  // The progress is the whole app's, but each window hears only its own
  // profile's downloads: while any download runs, every window refreshes
  // at the Dock's rate, so a download in another profile, even one with no
  // window, moves every window's progress and clears it when it ends.
  static void Poll();

  const raw_ptr<ClairBrowserWindow> window_;
  std::unique_ptr<download::AllDownloadItemNotifier> notifier_;
  const base::Time session_start_;
  std::set<std::string> seen_;
  bool flush_posted_ = false;
  base::WeakPtrFactory<ClairDownloads> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_DOWNLOADS_H_
