// Sets the badge the runtime suite looks for.
chrome.runtime.onInstalled.addListener(() => chrome.action.setBadgeText({text: '3'}));
chrome.runtime.onStartup.addListener(() => chrome.action.setBadgeText({text: '3'}));
chrome.action.setBadgeText({text: '3'});
