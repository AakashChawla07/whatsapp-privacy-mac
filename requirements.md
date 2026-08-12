# WhatsApp Privacy Blur for macOS

## 1. Project Overview

### 1.1 Product Name

**WhatsApp Privacy Blur**

A lightweight macOS menu-bar utility that protects the privacy of WhatsApp conversations by visually blurring message previews displayed in the WhatsApp desktop application's chat sidebar.

### 1.2 Problem

When WhatsApp is open on a Mac, the left chat sidebar displays recent message previews.

For example:

```text
┌──────────────────────────┐
│ Chats                    │
│                          │
│ 👤 Mom                   │
│    Are you coming home?  │
│                          │
│ 👤 Rahul                 │
│    Bro check this out    │
│                          │
│ 👥 College Group         │
│    Meeting tomorrow...   │
└──────────────────────────┘
```

These previews can expose private information to anyone looking at the user's screen.

The application should hide this information without modifying WhatsApp, intercepting messages, or replacing the WhatsApp client.

### 1.3 Solution

The application will run as a macOS menu-bar utility and place a transparent visual privacy overlay over the WhatsApp sidebar.

Default behavior:

```text
┌──────────────────────────┐
│ Chats                    │
│                          │
│ 👤 Mom                   │
│    █████████████████     │
│                          │
│ 👤 Rahul                 │
│    █████████████████     │
│                          │
│ 👥 College Group         │
│    █████████████████     │
└──────────────────────────┘
```

When the user hovers over a specific message preview, that preview temporarily becomes visible.

---

# 2. Goals

## 2.1 Primary Goals

The application MUST:

1. Run natively on macOS.
2. Work with the official WhatsApp desktop application.
3. Detect when WhatsApp is running.
4. Detect the WhatsApp window position and size.
5. Identify the chat sidebar.
6. Overlay privacy blur regions over message previews.
7. Blur message previews by default.
8. Allow the user to temporarily reveal a preview.
9. Support hover-to-reveal.
10. Automatically re-hide the preview when the cursor leaves it.
11. Track WhatsApp window movement.
12. Track WhatsApp window resizing.
13. Track sidebar scrolling.
14. Work with light and dark WhatsApp themes.
15. Run primarily as a menu-bar application.
16. Require no modification of WhatsApp application files.
17. Never send, modify, delete, or transmit WhatsApp messages.

---

# 3. Non-Goals

The first version MUST NOT attempt to:

- Read or store complete WhatsApp conversations.
- Send WhatsApp messages.
- Modify WhatsApp's database.
- Modify WhatsApp's application bundle.
- Inject code into WhatsApp.
- Intercept WhatsApp network traffic.
- Access WhatsApp authentication credentials.
- Bypass WhatsApp security.
- Replace the official WhatsApp client.
- Synchronize WhatsApp messages with another service.
- Upload WhatsApp content to a server.
- Implement a full WhatsApp client.
- Circumvent macOS security permissions.

---

# 4. Target Platform

## 4.1 Operating System

Primary target:

- macOS 14 Sonoma or newer

The implementation SHOULD remain compatible with newer macOS versions without requiring architectural changes.

## 4.2 Architecture

Primary architecture:

- Apple Silicon (`arm64`)

The application SHOULD eventually support:

- Apple Silicon
- Intel Macs

## 4.3 Target Hardware

The application MUST work efficiently on:

- MacBook Air
- MacBook Pro
- iMac
- Mac mini
- Mac Studio

Apple Silicon MUST be a first-class target.

---

# 5. Technology Stack

## 5.1 Language

**Swift**

Preferred Swift version:

- Swift 6+

## 5.2 UI Framework

Use:

- SwiftUI for settings/preferences UI
- AppKit for system-level functionality

The application SHOULD use AppKit where necessary for:

- `NSWindow`
- transparent overlay windows
- window levels
- event monitoring
- mouse tracking
- accessibility integration
- menu-bar behavior

## 5.3 macOS APIs

Expected APIs include:

### Accessibility

```swift
ApplicationServices
AXUIElement
AXObserver
AXValue
```

Used for:

- detecting WhatsApp window geometry
- identifying accessible UI elements
- tracking window movement
- tracking window resizing
- potentially identifying sidebar/chat rows

### Window management

Use:

```swift
AppKit
NSWindow
NSWorkspace
```

### Event monitoring

Use:

```swift
NSEvent
```

for:

- mouse movement
- mouse enter/exit behavior
- keyboard shortcuts where appropriate

### Graphics

Use:

```swift
CoreGraphics
CoreImage
QuartzCore
```

where necessary for:

- blur effects
- rendering
- overlay drawing

---

# 6. Application Architecture

The application SHOULD use a modular architecture.

Recommended structure:

```text
WhatsAppPrivacyBlur/
│
├── App/
│   ├── WhatsAppPrivacyBlurApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
│
├── Accessibility/
│   ├── AccessibilityManager.swift
│   ├── WhatsAppWindowDetector.swift
│   ├── AccessibilityPermissionManager.swift
│   └── AccessibilityElement.swift
│
├── WhatsApp/
│   ├── WhatsAppDetector.swift
│   ├── WhatsAppWindow.swift
│   ├── SidebarDetector.swift
│   ├── ChatRowDetector.swift
│   └── WhatsAppLayout.swift
│
├── Overlay/
│   ├── OverlayWindow.swift
│   ├── OverlayManager.swift
│   ├── BlurView.swift
│   ├── BlurRegion.swift
│   └── HoverRevealManager.swift
│
├── Input/
│   ├── MouseTracker.swift
│   └── KeyboardShortcutManager.swift
│
├── Settings/
│   ├── SettingsModel.swift
│   ├── SettingsView.swift
│   └── PreferencesManager.swift
│
├── MenuBar/
│   ├── MenuBarManager.swift
│   └── MenuBarView.swift
│
├── Permissions/
│   └── PermissionManager.swift
│
├── Utilities/
│   ├── Logger.swift
│   ├── Geometry.swift
│   └── Debouncer.swift
│
└── Tests/
    ├── AccessibilityTests/
    ├── GeometryTests/
    ├── OverlayTests/
    └── SettingsTests/
```

---

# 7. Core Components

## 7.1 App Controller

The application controller manages the overall lifecycle.

Responsibilities:

- initialize managers
- monitor WhatsApp
- manage permissions
- create/destroy overlay
- respond to application activation
- respond to configuration changes

State machine:

```text
                         ┌─────────────┐
                         │ App Started │
                         └──────┬──────┘
                                │
                                ▼
                     ┌────────────────────┐
                     │ Check Permissions  │
                     └─────────┬──────────┘
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
              Granted                     Missing
                 │                           │
                 ▼                           ▼
       ┌─────────────────┐        ┌──────────────────┐
       │ Detect WhatsApp │        │ Request Access   │
       └────────┬────────┘        └──────────────────┘
                │
                ▼
       ┌─────────────────┐
       │ WhatsApp Found  │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Detect Sidebar  │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Create Overlay  │
       └────────┬────────┘
                │
                ▼
       ┌─────────────────┐
       │ Track Changes   │
       └─────────────────┘
```

---

# 8. WhatsApp Detection

## 8.1 Application Detection

The application MUST detect whether WhatsApp is running.

The preferred mechanism is:

```swift
NSWorkspace.shared.runningApplications
```

The implementation SHOULD identify WhatsApp using its bundle identifier rather than relying exclusively on the process name.

The application MUST NOT assume that the WhatsApp executable path is fixed.

## 8.2 Application Lifecycle

The utility SHOULD respond to:

- WhatsApp launched
- WhatsApp terminated
- WhatsApp activated
- WhatsApp deactivated
- WhatsApp window created
- WhatsApp window destroyed

When WhatsApp is not running:

```text
Overlay = hidden
```

When WhatsApp becomes active:

```text
Overlay = enabled
```

---

# 9. Accessibility Permissions

The application requires macOS Accessibility permission.

## 9.1 Permission Check

The app MUST check whether Accessibility access is granted.

If access is missing, the application MUST NOT attempt to bypass the permission.

The user SHOULD be shown a clear explanation:

> WhatsApp Privacy Blur needs Accessibility access to detect the position of WhatsApp's chat sidebar and place the privacy overlay correctly.

## 9.2 Permission UI

Provide:

```text
Accessibility Permission

WhatsApp Privacy Blur needs permission to
detect WhatsApp's window position.

[ Open System Settings ]

[ I've Granted Access ]
```

The application SHOULD deep-link to:

```text
System Settings
→ Privacy & Security
→ Accessibility
```

## 9.3 Permission Failure

If permission is denied:

- do not crash
- do not repeatedly prompt
- display the current permission status
- provide a button to open System Settings

---

# 10. WhatsApp Window Detection

The application MUST identify the currently relevant WhatsApp window.

The detector SHOULD obtain:

- window bounds
- window position
- window size
- window visibility
- window title where available
- window activation state

Example:

```text
WhatsApp window:

x = 100
y = 80
width = 1400
height = 900
```

---

# 11. Sidebar Detection

## 11.1 Objective

The system must determine the approximate rectangle occupied by WhatsApp's left chat sidebar.

Example:

```text
WhatsApp Window
┌────────────────────────────────────────────┐
│                                            │
│ ┌────────────────┐                         │
│ │ Sidebar        │                         │
│ │                │                         │
│ │ Chats          │                         │
│ │                │                         │
│ │ Chat 1         │                         │
│ │ Chat 2         │                         │
│ │ Chat 3         │                         │
│ │                │                         │
│ └────────────────┘                         │
│                                            │
└────────────────────────────────────────────┘
```

## 11.2 Detection Strategy

Use the following strategies in priority order:

1. Accessibility element hierarchy.
2. Known WhatsApp layout characteristics.
3. Window geometry heuristics.
4. Visual fallback if required.

The implementation SHOULD avoid hardcoding a single sidebar width.

## 11.3 Dynamic Sidebar Width

The sidebar width may change.

The detector MUST recalculate its bounds when:

- WhatsApp window is resized
- sidebar is resized
- display scaling changes
- application UI changes

---

# 12. Chat Row Detection

The application SHOULD identify individual chat rows whenever possible.

A chat row can conceptually contain:

```text
ChatRow
├── Avatar
├── ContactName
├── MessagePreview
└── Timestamp
```

The application SHOULD determine the geometry of:

```text
MessagePreview
```

rather than blindly blurring the entire chat row.

Example:

```text
┌─────────────────────────────┐
│ 👤 Rahul                    │
│    Hey, are you free today? │
│                      5:42 PM│
└─────────────────────────────┘
```

Blur:

```text
Hey, are you free today?
```

Do not blur:

```text
Rahul
5:42 PM
avatar
```

unless the user enables those options.

---

# 13. Fallback Blur Mode

If individual message-preview elements cannot be reliably detected, the application MUST support a fallback mode.

Fallback:

```text
┌───────────────────────┐
│ Chats                 │
│                       │
│ 👤 Rahul              │
│ ████████████████████  │
│                       │
│ 👤 Mom                │
│ ████████████████████  │
│                       │
│ 👥 Group              │
│ ████████████████████  │
└───────────────────────┘
```

The fallback MUST prioritize privacy over precision.

---

# 14. Overlay Window

## 14.1 Requirements

The overlay MUST:

- be transparent
- have no visible window chrome
- remain positioned above WhatsApp
- not appear in the Dock
- not appear as a normal application window
- follow WhatsApp's position
- follow WhatsApp's size
- optionally ignore mouse events

The overlay SHOULD use an appropriate window level so that it remains above WhatsApp but does not unnecessarily cover unrelated applications.

## 14.2 Click-Through

When hover interaction is disabled, the overlay SHOULD be click-through.

The user must be able to interact with WhatsApp normally.

When hover detection requires mouse tracking, the implementation SHOULD use an architecture that does not prevent normal WhatsApp interaction.

---

# 15. Blur Rendering

## 15.1 Default

Every detected message-preview region MUST be blurred by default.

## 15.2 Blur Types

The application SHOULD support:

### Gaussian blur

```text
████████████████
```

### Material blur

Use a native macOS visual material where practical.

### Solid privacy mask

```text
████████████████
```

The default SHOULD be a visually subtle blur/material effect.

## 15.3 Blur Intensity

Settings:

```text
Blur intensity
○ Low
● Medium
○ High
```

Or a continuous slider:

```text
Low ───────●────── High
```

Default:

```text
Medium
```

---

# 16. Hover-to-Reveal

## 16.1 Default Behavior

When the user's cursor enters a blurred message-preview region:

```text
blurred → visible
```

When the cursor leaves:

```text
visible → blurred
```

## 16.2 Transition

Reveal/hide SHOULD have a short animation.

Target:

```text
100–200 ms
```

The animation MUST NOT feel distracting.

## 16.3 Hover Precision

Hovering over:

```text
Contact name
Avatar
Timestamp
Empty space
```

MUST NOT reveal the message preview unless configured otherwise.

Only the relevant preview region SHOULD be revealed.

---

# 17. Click-to-Reveal

The application SHOULD support an alternative mode:

```text
Reveal mode:
○ Hover
● Click
○ Hover + Click
```

In click mode:

1. User clicks a blurred preview.
2. Preview becomes visible.
3. Preview remains visible until:
   - clicked again
   - mouse leaves
   - timeout expires
   - user changes chat

The default MVP SHOULD use hover.

---

# 18. Reveal Timeout

Optional setting:

```text
Reveal timeout

○ Until mouse leaves
○ 2 seconds
○ 5 seconds
○ 10 seconds
```

Default:

```text
Until mouse leaves
```

---

# 19. Privacy Modes

## 19.1 Message Preview Blur

Default:

```text
ON
```

Blurs:

- latest message text
- media labels
- link previews represented in sidebar
- notification-style preview text

## 19.2 Contact Name Blur

Optional:

```text
OFF
```

## 19.3 Timestamp Blur

Optional:

```text
OFF
```

## 19.4 Avatar Blur

Optional:

```text
OFF
```

---

# 20. Global Privacy Toggle

The user MUST be able to enable/disable protection.

Menu-bar UI:

```text
WhatsApp Privacy Blur

Privacy Protection       ● ON

[ Disable ]
```

When disabled:

```text
Overlay = removed
```

When enabled:

```text
Overlay = active
```

---

# 21. Menu Bar Application

The application SHOULD run primarily as a menu-bar utility.

It SHOULD NOT require a traditional main window.

Menu bar:

```text
🔒
```

Click:

```text
┌───────────────────────────────┐
│ WhatsApp Privacy Blur         │
├───────────────────────────────┤
│ Privacy Protection      ✓     │
│                               │
│ Reveal on Hover         ✓     │
│                               │
│ Blur Intensity          Medium│
│                               │
├───────────────────────────────┤
│ Settings...                    │
│ Check for Updates...           │
│ Quit                           │
└───────────────────────────────┘
```

---

# 22. Settings

Settings SHOULD include:

## General

```text
☑ Enable privacy blur automatically
☑ Launch at login
☑ Enable when WhatsApp becomes active
```

## Blur

```text
☑ Message previews
☐ Contact names
☐ Timestamps
☐ Profile pictures

Blur intensity: Medium
```

## Reveal

```text
Reveal method:

● Hover
○ Click
○ Disabled

Reveal timeout:
● Until mouse leaves
○ 2 seconds
○ 5 seconds
○ 10 seconds
```

## Advanced

```text
☐ Use fallback sidebar blur
☐ Show debug overlay
☐ Enable diagnostic logging
```

---

# 23. Launch at Login

The application SHOULD support:

```text
Launch at login
```

Use Apple's supported login-item mechanism.

The app MUST NOT install unauthorized background services.

---

# 24. Multiple Displays

The application MUST support multiple monitors.

Requirements:

- WhatsApp can move between displays.
- Overlay follows WhatsApp.
- Different display scaling factors must be supported.
- Retina and non-Retina displays must work.

The system MUST correctly handle:

```text
NSScreen
backingScaleFactor
coordinate conversion
```

---

# 25. Display Scaling

The application MUST account for:

- Retina scaling
- non-Retina scaling
- different scaling on different monitors

Coordinate conversion MUST be centralized in a geometry utility.

Do not scatter coordinate transformations throughout the codebase.

---

# 26. Window Movement

If the user drags WhatsApp:

```text
Before:

WhatsApp
┌───────────────┐
│ █████████     │
└───────────────┘

After:

      WhatsApp
      ┌───────────────┐
      │ █████████     │
      └───────────────┘
```

The overlay MUST follow automatically.

Target:

- overlay position updated within approximately 100 ms of movement
- no visible separation between WhatsApp and overlay

---

# 27. Window Resizing

When WhatsApp is resized:

```text
Window resized
      ↓
Detect new bounds
      ↓
Recalculate sidebar
      ↓
Recalculate chat rows
      ↓
Update overlay
```

The system MUST debounce rapid geometry changes.

Recommended debounce:

```text
50–150 ms
```

---

# 28. Sidebar Scrolling

When the user scrolls the chat list:

```text
Before:

Chat A
Chat B
Chat C
Chat D

Scroll ↓

Chat B
Chat C
Chat D
Chat E
```

The overlay MUST update accordingly.

Old blur regions MUST NOT remain visible after the corresponding chat row leaves the visible area.

---

# 29. WhatsApp UI Changes

WhatsApp may change its UI in future releases.

The implementation MUST isolate WhatsApp-specific assumptions inside:

```text
WhatsApp/
```

The rest of the application MUST NOT depend directly on hardcoded WhatsApp accessibility paths.

Example:

```swift
protocol SidebarDetector {
    func detectSidebar() -> SidebarLayout?
}
```

This allows the detection strategy to be replaced independently.

---

# 30. Privacy Requirements

Privacy is a primary product requirement.

## 30.1 No Network Communication

The application MUST NOT communicate with a remote server for core functionality.

The application SHOULD operate completely offline.

## 30.2 No Message Storage

The application MUST NOT store:

- message contents
- contact names
- phone numbers
- chat history
- profile pictures

unless explicitly required for a future feature.

## 30.3 No Message Transmission

WhatsApp content MUST NEVER be transmitted externally.

## 30.4 No Clipboard Access

The application MUST NOT access the clipboard unless explicitly required.

## 30.5 No Screen Recording by Default

The application SHOULD avoid Screen Recording permission if the Accessibility-based overlay architecture can provide the required functionality.

If a future fallback requires Screen Recording:

- explain why
- make it optional
- never transmit captured data
- never persist screenshots

---

# 31. Security

The application MUST:

- follow macOS sandbox/security best practices where feasible
- use official Apple APIs
- avoid code injection
- avoid dynamic library injection
- avoid modifying WhatsApp
- avoid reading WhatsApp's private filesystem data
- avoid credential access

The application MUST NOT attempt to circumvent macOS permission systems.

---

# 32. Performance Requirements

The application should have minimal system impact.

Target:

- CPU usage: normally < 2% when idle
- memory: preferably < 100 MB
- no continuous high-frequency polling

The implementation SHOULD prefer:

```text
Accessibility observers
```

over:

```text
continuous polling
```

when possible.

Avoid:

```swift
Timer.scheduledTimer(withTimeInterval: 0.01, ...)
```

style loops.

---

# 33. Event-Driven Architecture

Prefer:

```text
WhatsApp launched
        ↓
observer

Window moved
        ↓
Accessibility notification

Window resized
        ↓
Accessibility notification

Sidebar changed
        ↓
Accessibility observer

Mouse moved
        ↓
event monitor
```

rather than repeatedly scanning the entire screen.

---

# 34. Error Handling

The application MUST gracefully handle:

- WhatsApp not installed
- WhatsApp not running
- Accessibility permission denied
- WhatsApp window unavailable
- sidebar detection failure
- unsupported WhatsApp UI
- unexpected accessibility tree structure
- display changes
- window disappearing
- application termination

The application MUST NOT crash because WhatsApp changes its UI.

---

# 35. Failsafe Privacy Behavior

If the application is uncertain whether a message preview is correctly identified, it SHOULD prefer hiding more content rather than exposing private content.

Example:

```text
Detection confidence: LOW

→ Use broader sidebar blur
```

This is preferable to:

```text
Detection confidence: LOW

→ Show potentially private text
```

---

# 36. Debug Mode

Development builds SHOULD support a debug overlay.

Example:

```text
┌─────────────────────────────┐
│ Chat row #1                 │
│ Preview bounds:             │
│ x: 120                      │
│ y: 240                      │
│ width: 260                  │
│ height: 22                  │
└─────────────────────────────┘
```

Debug mode may display:

- Accessibility hierarchy
- detected window bounds
- sidebar bounds
- chat row bounds
- preview bounds
- detection confidence
- overlay state

Debug mode MUST be disabled by default in production.

---

# 37. Logging

Use structured local logging.

Recommended:

```swift
OSLog
Logger
```

Logging levels:

```text
debug
info
warning
error
```

Logs MUST NOT contain:

- message contents
- contact names
- phone numbers
- message previews
- sensitive WhatsApp data

Example acceptable log:

```text
WhatsApp window detected.
Sidebar bounds updated.
Overlay regions: 12
```

Example unacceptable log:

```text
Message detected: "Meet me at 7 PM"
```

---

# 38. Accessibility Tree Abstraction

Do not tightly couple the application to raw `AXUIElement` calls.

Create an abstraction:

```swift
protocol AccessibilityProvider {
    func focusedApplication() -> AXUIElement?
    func windows(for application: AXUIElement) -> [AXUIElement]
    func frame(of element: AXUIElement) -> CGRect?
    func children(of element: AXUIElement) -> [AXUIElement]
}
```

This improves:

- testing
- maintainability
- mocking
- future compatibility

---

# 39. Geometry Model

Use explicit geometry models.

Example:

```swift
struct BlurRegion: Identifiable {
    let id: UUID
    var frame: CGRect
    var isRevealed: Bool
}
```

Sidebar:

```swift
struct SidebarLayout {
    var frame: CGRect
    var rows: [ChatRowLayout]
}
```

Chat row:

```swift
struct ChatRowLayout {
    var frame: CGRect
    var previewFrame: CGRect?
}
```

---

# 40. Overlay Manager

The `OverlayManager` MUST be responsible for:

- creating overlay window
- destroying overlay window
- updating overlay frame
- updating blur regions
- revealing regions
- hiding regions
- synchronizing overlay state

It SHOULD NOT be responsible for discovering WhatsApp UI.

Separation:

```text
WhatsApp detector
        ↓
Sidebar layout
        ↓
Overlay manager
        ↓
Blur renderer
```

---

# 41. Hover Manager

The `HoverRevealManager` MUST:

1. receive cursor location
2. determine whether cursor intersects a blur region
3. identify the corresponding region
4. reveal it
5. hide previously revealed region
6. trigger animation

Example:

```swift
func updateHoverLocation(_ point: CGPoint) {
    let region = regions.first {
        $0.frame.contains(point)
    }

    reveal(region)
}
```

---

# 42. Mouse Tracking

Mouse tracking SHOULD be efficient.

The application MUST avoid unnecessarily processing every mouse event at full resolution if no interaction is required.

Potential strategy:

```text
Mouse event
   ↓
Is WhatsApp active?
   ↓
No → ignore
Yes
   ↓
Is point inside sidebar?
   ↓
No → ignore
Yes
   ↓
Find preview region
   ↓
Reveal
```

---

# 43. User Experience

The application SHOULD feel invisible.

The user should not need to:

1. manually start protection
2. select WhatsApp
3. configure sidebar coordinates
4. manually resize overlay
5. restart the app after moving WhatsApp

Ideal experience:

```text
Install
 ↓
Grant Accessibility permission
 ↓
Open WhatsApp
 ↓
Privacy blur automatically appears
```

---

# 44. First Launch

First launch screen:

```text
WhatsApp Privacy Blur

Protect your WhatsApp previews
from people looking at your screen.

The app works locally and does not
send WhatsApp messages anywhere.

Accessibility access is required.

[ Grant Accessibility Access ]
```

After permission:

```text
You're protected.

WhatsApp message previews will now
be blurred automatically.

[ Done ]
```

---

# 45. Notification Behavior

The app SHOULD avoid unnecessary notifications.

Acceptable:

```text
WhatsApp Privacy Blur is active.
```

Avoid:

```text
Privacy Blur enabled!
Privacy Blur disabled!
WhatsApp detected!
Overlay updated!
```

for every state change.

---

# 46. Visual Design

The application UI SHOULD follow Apple's design language.

Requirements:

- native macOS typography
- native controls
- system materials
- light/dark mode support
- compact settings interface
- minimal menu-bar presence

The privacy overlay itself SHOULD be visually neutral.

---

# 47. Accessibility

The utility's own UI MUST support macOS accessibility.

Requirements:

- VoiceOver labels
- keyboard navigation
- accessible settings controls
- meaningful button labels
- sufficient contrast

The privacy overlay itself SHOULD NOT interfere with VoiceOver navigation of WhatsApp.

---

# 48. Keyboard Shortcuts

Optional global shortcut:

```text
⌘ + Shift + B
```

Behavior:

```text
ON  → OFF
OFF → ON
```

The shortcut SHOULD be configurable in settings.

---

# 49. Automatic Activation

Default behavior:

```text
WhatsApp active
      ↓
Protection ON
```

When another application becomes active:

```text
Protection overlay hidden
```

When WhatsApp becomes active again:

```text
Protection overlay restored
```

The app SHOULD provide an option to keep protection active even when WhatsApp is not focused.

---

# 50. Fullscreen Support

The application SHOULD support WhatsApp fullscreen mode.

Requirements:

- overlay remains aligned
- no overlay artifacts
- no unexpected window activation

---

# 51. Multiple WhatsApp Windows

If WhatsApp supports multiple windows, the implementation SHOULD identify the active/main window.

For MVP:

- support the primary WhatsApp window
- ignore secondary windows

Future versions MAY support multiple windows.

---

# 52. Update Handling

The application SHOULD detect when WhatsApp changes its UI enough to make detection unreliable.

If detection fails repeatedly:

```text
WhatsApp Privacy Blur

We couldn't reliably detect WhatsApp's
chat sidebar.

Privacy protection has switched to
safe fallback mode.

[ Open Settings ]
```

Fallback mode SHOULD prefer privacy.

---

# 53. Testing Requirements

## 53.1 Unit Tests

Test:

- geometry calculations
- coordinate conversion
- blur region intersection
- hover detection
- settings persistence
- state transitions
- debounce behavior

## 53.2 Integration Tests

Test:

- WhatsApp launch detection
- WhatsApp termination detection
- accessibility permission state
- overlay creation
- overlay positioning
- window movement
- window resizing

## 53.3 Manual Tests

Test on:

- light mode
- dark mode
- small window
- maximized window
- fullscreen
- Retina display
- non-Retina display
- multiple monitors
- different display scaling
- long chat lists
- empty chat previews
- media previews
- group chats
- muted chats
- unread chats
- pinned chats

---

# 54. Privacy Test Cases

The application MUST verify:

### Test 1

Message preview visible in WhatsApp.

Expected:

```text
Preview is blurred.
```

### Test 2

Mouse enters preview.

Expected:

```text
Preview becomes visible.
```

### Test 3

Mouse leaves preview.

Expected:

```text
Preview becomes blurred.
```

### Test 4

WhatsApp moves.

Expected:

```text
Overlay follows WhatsApp.
```

### Test 5

WhatsApp resizes.

Expected:

```text
Blur regions resize/reposition.
```

### Test 6

WhatsApp scrolls.

Expected:

```text
Visible chat previews remain protected.
```

### Test 7

WhatsApp closes.

Expected:

```text
Overlay disappears.
```

### Test 8

Another app becomes active.

Expected:

```text
Overlay does not remain unnecessarily visible.
```

---

# 55. MVP Definition

The MVP is complete when all of the following work:

- [ ] macOS application launches
- [ ] menu-bar icon exists
- [ ] Accessibility permission flow works
- [ ] WhatsApp process is detected
- [ ] WhatsApp window is detected
- [ ] WhatsApp sidebar is detected
- [ ] sidebar message previews are blurred
- [ ] hover reveals preview
- [ ] leaving preview re-blurs it
- [ ] WhatsApp window movement is tracked
- [ ] WhatsApp window resizing is tracked
- [ ] sidebar scrolling is handled
- [ ] overlay does not block WhatsApp interaction
- [ ] light mode works
- [ ] dark mode works
- [ ] app can be toggled ON/OFF
- [ ] app does not store message content
- [ ] app does not send data externally
- [ ] app does not modify WhatsApp

---

# 56. MVP Simplification

If individual chat-row detection proves unreliable during initial development, the MVP MAY use:

```text
Entire message-preview column → blur
```

instead of:

```text
Individual preview → blur
```

The MVP priority should be:

1. Privacy correctness
2. Stability
3. Overlay positioning
4. Hover reveal
5. Precise region detection

Do not delay the MVP indefinitely attempting perfect Accessibility-tree parsing.

---

# 57. Future Features

Potential future features:

### Privacy presets

```text
Work Mode
Maximum Privacy
Normal
```

### More applications

Extend beyond WhatsApp:

- Telegram
- Slack
- Discord
- Messages
- Microsoft Teams

### Smart privacy

Automatically enable protection when:

- external monitor connected
- screen sharing detected
- presentation mode detected

### Screen-sharing mode

Detect active screen sharing and automatically enable maximum privacy.

### Per-application profiles

```text
WhatsApp:
  Blur previews: ON
  Reveal: Hover

Telegram:
  Blur previews: ON
  Reveal: Click
```

---

# 58. Architecture Principles

The project MUST follow these principles:

### Privacy first

Never sacrifice privacy for detection precision.

### Local first

No backend should be required.

### Event-driven

Prefer observers over polling.

### Modular

WhatsApp-specific logic must be isolated.

### Fail-safe

Detection failure should hide more content rather than expose it.

### Minimal permissions

Request only permissions that are genuinely necessary.

### Native macOS

Prefer Apple APIs and native Swift/AppKit implementations.

### No WhatsApp modification

The WhatsApp application itself must remain untouched.

---

# 59. Definition of Done

A production-ready release requires:

## Functionality

- [ ] Privacy blur reliably works
- [ ] Hover reveal works
- [ ] Overlay follows WhatsApp
- [ ] Scrolling works
- [ ] Resizing works
- [ ] Multiple display support works
- [ ] Light/dark mode works
- [ ] Settings work
- [ ] Launch at login works

## Reliability

- [ ] No crashes during normal usage
- [ ] WhatsApp restart handled
- [ ] Mac sleep/wake handled
- [ ] Display connection/disconnection handled
- [ ] Permission changes handled

## Privacy

- [ ] No message contents logged
- [ ] No message contents stored
- [ ] No unnecessary network access
- [ ] No screenshots stored
- [ ] No WhatsApp files modified

## Performance

- [ ] Low idle CPU
- [ ] Low memory usage
- [ ] No excessive polling
- [ ] Smooth overlay updates

## UX

- [ ] Clear onboarding
- [ ] Clear permission explanation
- [ ] Menu-bar controls
- [ ] Native macOS appearance
- [ ] Accessible settings

---

# 60. Recommended Development Phases

## Phase 1 — macOS Foundation

Build:

- Swift project
- menu-bar application
- settings
- app lifecycle
- logging

Deliverable:

```text
Working menu-bar application
```

---

## Phase 2 — Accessibility

Implement:

- permission detection
- Accessibility permission flow
- WhatsApp detection
- WhatsApp window detection
- window geometry

Deliverable:

```text
App can identify and track WhatsApp's window.
```

---

## Phase 3 — Overlay

Implement:

- transparent NSWindow
- overlay positioning
- window tracking
- basic blur

Deliverable:

```text
A blur rectangle follows WhatsApp.
```

---

## Phase 4 — Sidebar

Implement:

- sidebar detection
- sidebar geometry
- scrolling detection
- dynamic resizing

Deliverable:

```text
WhatsApp sidebar is protected.
```

---

## Phase 5 — Chat Rows

Implement:

- chat-row detection
- preview detection
- individual blur regions

Deliverable:

```text
Only message previews are blurred.
```

---

## Phase 6 — Hover Reveal

Implement:

- mouse tracking
- region hit testing
- reveal animation
- automatic re-blur

Deliverable:

```text
Hover over preview → reveal.
Move away → blur.
```

---

## Phase 7 — Settings

Implement:

- blur intensity
- privacy targets
- reveal method
- timeout
- launch at login
- keyboard shortcut

Deliverable:

```text
Configurable privacy utility.
```

---

## Phase 8 — Hardening

Test:

- multiple displays
- scaling
- fullscreen
- dark/light mode
- sleep/wake
- WhatsApp updates
- permission changes

Deliverable:

```text
Production-ready application.
```

---

# 61. Important Implementation Constraint

The implementation MUST NOT assume that WhatsApp's Accessibility hierarchy will remain stable forever.

WhatsApp-specific selectors, roles, titles, identifiers, and layout assumptions MUST be isolated behind interfaces so that they can be updated without rewriting the overlay system.

Recommended abstraction:

```text
                 ┌──────────────────────────┐
                 │ WhatsApp UI Adapter       │
                 │                          │
                 │ Accessibility detection  │
                 │ Sidebar detection        │
                 │ Chat row detection       │
                 └────────────┬─────────────┘
                              │
                              ▼
                 ┌──────────────────────────┐
                 │ Layout Model             │
                 │                          │
                 │ Sidebar                  │
                 │ Chat rows                │
                 │ Preview regions          │
                 └────────────┬─────────────┘
                              │
                              ▼
                 ┌──────────────────────────┐
                 │ Overlay Engine           │
                 │                          │
                 │ Blur                     │
                 │ Hover                    │
                 │ Reveal                   │
                 └──────────────────────────┘
```

This separation is critical for long-term maintainability.

---

# 62. Final Product Experience

The final application should feel like this:

```text
1. User starts Mac
          ↓
2. WhatsApp Privacy Blur starts
          ↓
3. User opens WhatsApp
          ↓
4. Sidebar previews automatically blur
          ↓
5. User moves mouse over a preview
          ↓
6. Preview becomes readable
          ↓
7. User moves mouse away
          ↓
8. Preview immediately blurs again
```

The user should never have to manually position or manage the overlay.

The application should effectively disappear into the background while providing continuous visual privacy.

---

# 63. Success Criteria

The project is successful if a user can open WhatsApp on their Mac in a public environment and another person sitting nearby **cannot read message previews from the chat sidebar**, while the WhatsApp user can still naturally interact with the application and reveal previews when needed.

The ideal experience is:

> **Private by default. Readable on demand. Invisible when not needed.**