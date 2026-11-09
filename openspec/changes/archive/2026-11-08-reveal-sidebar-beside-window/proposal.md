# Proposal

## Why

With the sidebar hidden, Clair revealed it only while the pointer was inside the window's thin leading inset, and cancelled the reveal as soon as the pointer left it. Overshooting the inset, the usual fast flick to the left, revealed nothing, while Arc reveals its sidebar from beside the window too. Clair also revealed on entry, so a pointer passing through flashed the sidebar, and kept a revealed sidebar for 300 ms after the pointer left. Recorded after the fact: the work shipped in PR #111.

## What Changes

- **Reveal on rest, not on entry:** the sidebar reveals once the pointer has stopped in the leading inset for about 80 ms; a pointer passing through doesn't reveal it.
- **Hide sooner:** about 100 ms after the pointer leaves the revealed sidebar, instead of 300 ms.
- **The area beside the window counts:** to the left of the key window, as tall as it, 50 pt wide, or 250 pt while the pointer was last in the window or is already there. So overshooting the inset still reveals the sidebar and keeps it shown. Only pointer moves count, not drags.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sidebar`: "Revealing the hidden sidebar" reveals on rest and hides after about 100 ms; adds "Overshooting the window's edge".

## Impact

- **Native layer:** `BrowserRootView.swift`: the reveal strip's tracking area reports moves; a local mouse monitor follows the pointer outside the window while the sidebar is hidden and the window is key. No contract or engine change.
- **Tests:** a unit test for the reveal strip's mouse moves (a crash found by hand); the reveal itself is measured with the probe, against Arc.
- **Users:** a Changie fragment.
