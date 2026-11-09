// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_downloads.h"

#include <algorithm>
#include <map>
#include <vector>

#include "base/no_destructor.h"
#include "base/process/process.h"
#include "base/scoped_multi_source_observation.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/download/download_status_updater.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_manager_observer.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"

@interface ClairChromiumDownload : NSObject <ClairDownload>
@property(nonatomic, copy) NSString* downloadID;
@property(nonatomic, copy) NSString* fileName;
@property(nonatomic) ClairDownloadState state;
@property(nonatomic) int64_t receivedBytes;
@property(nonatomic) int64_t totalBytes;
@property(nonatomic) BOOL needsDecision;
@property(nonatomic, copy, nullable) NSString* warningText;
@property(nonatomic) BOOL canResume;
@property(nonatomic) BOOL isSeen;
@end

@implementation ClairChromiumDownload
@end

namespace {

ClairDownloadState StateOf(download::DownloadItem* item) {
  switch (item->GetState()) {
    case download::DownloadItem::IN_PROGRESS:
      return item->IsPaused() ? ClairDownloadStatePaused
                              : ClairDownloadStateInProgress;
    case download::DownloadItem::COMPLETE:
      return ClairDownloadStateComplete;
    case download::DownloadItem::CANCELLED:
      return ClairDownloadStateCancelled;
    case download::DownloadItem::INTERRUPTED:
      return ClairDownloadStateInterrupted;
    default:
      return ClairDownloadStateInProgress;
  }
}

}  // namespace

namespace {

// When this session's downloads start: the process's start, or failing that
// when the first native window opened.
base::Time SessionStart() {
  static const base::Time start = [] {
    base::Time created = base::Process::Current().CreationTime();
    return created.is_null() ? base::Time::Now() : created;
  }();
  return start;
}

}  // namespace

namespace {

// Every window's downloads, which hear about the app-wide progress.
std::set<ClairDownloads*>& Instances() {
  static base::NoDestructor<std::set<ClairDownloads*>> instances;
  return *instances;
}

bool SameProgress(const ClairDownloadProgress& a,
                  const ClairDownloadProgress& b) {
  return a.count == b.count && a.isIndeterminate == b.isIndeterminate &&
         a.fraction == b.fraction;
}

// Watches the downloads of every loaded profile, off-the-record ones
// included, as the DownloadStatusUpdater behind the Dock does, and tells
// every window when the app-wide progress changes. A download in a profile
// with no window counts too, and nothing runs while no download changes,
// such as while one is paused.
class ProgressWatcher : public ProfileManagerObserver,
                        public ProfileObserver,
                        public download::AllDownloadItemNotifier::Observer {
 public:
  static ProgressWatcher& Get() {
    static base::NoDestructor<ProgressWatcher> watcher;
    return *watcher;
  }

  ProgressWatcher() {
    if (ProfileManager* profile_manager =
            g_browser_process->profile_manager()) {
      profile_manager_observation_.Observe(profile_manager);
      for (Profile* profile : profile_manager->GetLoadedProfiles()) {
        Watch(profile);
      }
    }
  }

  // Guest and incognito profiles don't reach OnProfileAdded, so each window
  // also adds its own.
  void Watch(Profile* profile) {
    if (!profile_observations_.IsObservingSource(profile)) {
      profile_observations_.AddObservation(profile);
    }
    if (!notifiers_.contains(profile)) {
      if (content::DownloadManager* manager = profile->GetDownloadManager()) {
        notifiers_[profile] =
            std::make_unique<download::AllDownloadItemNotifier>(manager,
                                                                 this);
      }
    }
    for (Profile* off_the_record : profile->GetAllOffTheRecordProfiles()) {
      Watch(off_the_record);
    }
  }

  // ProfileManagerObserver:
  void OnProfileAdded(Profile* profile) override { Watch(profile); }
  void OnProfileManagerDestroying() override {
    profile_manager_observation_.Reset();
  }

  // ProfileObserver:
  void OnOffTheRecordProfileCreated(Profile* off_the_record) override {
    Watch(off_the_record);
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    notifiers_.erase(profile);
    profile_observations_.RemoveObservation(profile);
    Changed();
  }

  // download::AllDownloadItemNotifier::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    Changed();
  }
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    Changed();
  }
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    Changed();
  }

 private:
  // A running download updates many times a second; windows hear at most
  // once per run-loop turn, and only when the progress changed.
  void Changed() {
    if (flush_posted_) {
      return;
    }
    flush_posted_ = true;
    dispatch_async(dispatch_get_main_queue(), ^{
      ProgressWatcher::Get().Flush();
    });
  }

  void Flush() {
    flush_posted_ = false;
    ClairDownloadProgress progress = ClairDownloads::Progress();
    if (has_sent_ && SameProgress(progress, sent_)) {
      return;
    }
    has_sent_ = true;
    sent_ = progress;
    for (ClairDownloads* downloads : Instances()) {
      downloads->ProgressChanged(progress);
    }
  }

  std::map<Profile*, std::unique_ptr<download::AllDownloadItemNotifier>>
      notifiers_;
  base::ScopedObservation<ProfileManager, ProfileManagerObserver>
      profile_manager_observation_{this};
  base::ScopedMultiSourceObservation<Profile, ProfileObserver>
      profile_observations_{this};
  bool flush_posted_ = false;
  bool has_sent_ = false;
  ClairDownloadProgress sent_ = {0, false, 0};
};

}  // namespace

ClairDownloads::ClairDownloads(ClairBrowserWindow* window)
    : window_(window), session_start_(SessionStart()) {
  Profile* profile = window_->browser()->GetProfile();
  if (content::DownloadManager* manager = profile->GetDownloadManager()) {
    notifier_ =
        std::make_unique<download::AllDownloadItemNotifier>(manager, this);
  }
  Instances().insert(this);
  ProgressWatcher::Get().Watch(profile);
}

ClairDownloads::~ClairDownloads() {
  Instances().erase(this);
}

// static
ClairDownloadProgress ClairDownloads::Progress() {
  ClairDownloadProgress progress = {0, false, 0};
  if (DownloadStatusUpdater* updater =
          g_browser_process->download_status_updater()) {
    float fraction = 0;
    int count = 0;
    bool certain = updater->GetProgress(&fraction, &count);
    progress.count = count;
    progress.isIndeterminate = !certain;
    progress.fraction = fraction;
  }
  return progress;
}

void ClairDownloads::ProgressChanged(const ClairDownloadProgress& progress) {
  if (id<ClairWindow> window = window_->clair_window()) {
    [window downloadProgressDidChange:progress];
  }
}

bool ClairDownloads::IsFromThisSession(download::DownloadItem* item) const {
  return !item->IsTransient() &&
         (session_start_.is_null() || item->GetStartTime() >= session_start_);
}

NSArray<id<ClairDownload>>* ClairDownloads::Snapshot() {
  content::DownloadManager* manager = notifier_ ? notifier_->GetManager() : nullptr;
  if (!manager) {
    return @[];
  }
  content::DownloadManager::DownloadVector items;
  manager->GetAllDownloads(&items);
  std::vector<download::DownloadItem*> session;
  for (download::DownloadItem* item : items) {
    if (IsFromThisSession(item)) {
      session.push_back(item);
    }
  }
  std::ranges::sort(session, [](download::DownloadItem* a,
                                download::DownloadItem* b) {
    return a->GetStartTime() > b->GetStartTime();
  });
  NSMutableArray<id<ClairDownload>>* snapshot = [NSMutableArray array];
  for (download::DownloadItem* item : session) {
    ClairChromiumDownload* download = [[ClairChromiumDownload alloc] init];
    download.downloadID = base::SysUTF8ToNSString(item->GetGuid());
    download.fileName = base::SysUTF8ToNSString(
        item->GetFileNameToReportUser().BaseName().AsUTF8Unsafe());
    download.state = StateOf(item);
    download.receivedBytes = item->GetReceivedBytes();
    download.totalBytes = std::max<int64_t>(item->GetTotalBytes(), 0);
    download.needsDecision = item->IsDangerous() || item->IsInsecure();
    download.canResume = item->CanResume();
    download.isSeen = item->GetOpened() || seen_.contains(item->GetGuid());
    [snapshot addObject:download];
  }
  return snapshot;
}

download::DownloadItem* ClairDownloads::Find(const std::string& guid) {
  content::DownloadManager* manager = notifier_ ? notifier_->GetManager() : nullptr;
  return manager ? manager->GetDownloadByGuid(guid) : nullptr;
}

void ClairDownloads::Open(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid);
      item && item->GetState() == download::DownloadItem::COMPLETE) {
    seen_.insert(guid);
    item->OpenDownload();
    Changed();
  }
}

void ClairDownloads::ShowInFinder(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid)) {
    item->ShowDownloadInShell();
  }
}

void ClairDownloads::Cancel(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid)) {
    item->Cancel(/*user_cancel=*/true);
  }
}

void ClairDownloads::Resume(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid); item && item->CanResume()) {
    item->Resume(/*user_resume=*/true);
  }
}

void ClairDownloads::Keep(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid)) {
    item->ValidateDangerousDownload();
  }
}

void ClairDownloads::Discard(const std::string& guid) {
  if (download::DownloadItem* item = Find(guid)) {
    item->Remove();
  }
}

void ClairDownloads::MarkSeen() {
  content::DownloadManager* manager = notifier_ ? notifier_->GetManager() : nullptr;
  if (!manager) {
    return;
  }
  content::DownloadManager::DownloadVector items;
  manager->GetAllDownloads(&items);
  for (download::DownloadItem* item : items) {
    if (IsFromThisSession(item) &&
        item->GetState() == download::DownloadItem::COMPLETE) {
      seen_.insert(item->GetGuid());
    }
  }
  Changed();
}

void ClairDownloads::OnDownloadCreated(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  if (IsFromThisSession(item)) {
    Changed();
  }
}

void ClairDownloads::OnDownloadUpdated(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  if (IsFromThisSession(item)) {
    Changed();
  }
}

void ClairDownloads::OnDownloadOpened(content::DownloadManager* manager,
                                      download::DownloadItem* item) {
  seen_.insert(item->GetGuid());
  Changed();
}

void ClairDownloads::OnDownloadRemoved(content::DownloadManager* manager,
                                       download::DownloadItem* item) {
  seen_.erase(item->GetGuid());
  Changed();
}

// A running download updates many times a second; the sidebar hears at most
// once per run-loop turn.
void ClairDownloads::Changed() {
  if (flush_posted_) {
    return;
  }
  flush_posted_ = true;
  base::WeakPtr<ClairDownloads> weak = weak_factory_.GetWeakPtr();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (weak) {
      weak->Flush();
    }
  });
}

void ClairDownloads::Flush() {
  flush_posted_ = false;
  if (id<ClairWindow> window = window_->clair_window()) {
    [window downloadsDidChange:Snapshot() progress:Progress()];
  }
}
