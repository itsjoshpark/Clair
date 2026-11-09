# Spec Delta

## MODIFIED Requirements

### Requirement: Chromium bubbles placed in the native window
Chromium bubbles that remain, including permission prompts and page info, SHALL open attached to their control in the sidebar while the sidebar is shown, or to the card's top-leading corner while it is hidden or the window is in full screen. They SHALL work as they do in Chromium. Extension popups, and the install and remove confirmations, are not bubbles: `extensions` defines them.

#### Scenario: Permission prompt with the sidebar shown
- **WHEN** a page asks for the user's location while the sidebar is shown
- **THEN** Chromium's permission prompt opens attached to the site controls in the sidebar, and choosing Allow grants the permission to the page

#### Scenario: Permission prompt with the sidebar hidden
- **WHEN** a page asks for the user's location while the sidebar is hidden
- **THEN** the prompt opens at the card's top-leading corner, fully on screen, and choosing Block denies the permission

#### Scenario: Extension popup with the sidebar hidden
- **WHEN** an extension opens its popup while the sidebar is hidden
- **THEN** the popup window opens at the card's top-leading corner, fully on screen
