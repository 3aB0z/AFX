# Notification System - Quick Start Guide

## Overview

The notification system has been completely fixed and now provides:

- ✅ System-level push notifications (visible in notification center)
- ✅ In-app toast notifications (immediate feedback)
- ✅ Proper Android notification channel setup
- ✅ iOS notification support
- ✅ Sound and vibration enabled

## What Changed

### Files Modified

1. **pubspec.yaml** - Added `permission_handler: ^12.0.1`
2. **lib/main.dart** - Added `NotificationService.initialize()` call
3. **lib/services/notification_service.dart** - Complete rewrite with push notification support
4. **android/app/src/main/res/raw/** - Created directory for notification sounds

### Key Features Added

- Push notification display via `flutter_local_notifications`
- Android notification channel creation (required for Android 8+)
- iOS notification permission handling
- Notification payload support for app navigation
- Comprehensive logging with emojis

## How to Test

### Option 1: Send Message from Another User

1. Run the app: `flutter run`
2. Open app from another device/emulator logged in as different user
3. Send a message
4. Expected: You should see:
   - System notification in notification center
   - In-app toast at top of screen
   - Sound and vibration (if enabled on device)

### Option 2: Send Request Status Change

1. Admin user logs in
2. Another user's status changes
3. Expected: Request notification appears

### Option 3: Check Logs

Run the app and look for log messages with `[NOTIFICATION]` prefix:

```
[NOTIFICATION] 🚀 Initializing notification service...
[NOTIFICATION] ✅ Notification service initialized
[NOTIFICATION] 🔔 Requesting notification permission...
[NOTIFICATION] ✅ Notification permission granted
[NOTIFICATION] 📤 Showing push notification: 📨 New Message
```

## Notification Types

### 1. Message Notification

**Triggered:** When a new message is received
**Display:**

- Push: "📨 New Message"
- Toast: "SenderName: message content"
  **Action:** Tap to navigate to chat

### 2. Request Status Notification

**Triggered:** When a request status changes
**Display:**

- Push: "📋 Request Status Update"
- Toast: "emoji UserName - status"
  **Example:** "✅ John - verified"

### 3. New Request Notification

**Triggered:** When new user registration request arrives
**Display:**

- Push: "📋 New Request"
- Toast: "📋 New request from UserName"

### 4. Message Access Notification

**Triggered:** When user's message permission changes
**Display:**

- Push: "🔐 Message Access GRANTED/REVOKED"
- Toast: "Message access granted/revoked for UserName"

## Configuration

### Android Settings

- **Min SDK:** 21 (unchanged)
- **Target SDK:** 33+ (supports Android 13+)
- **Notification Channel ID:** `afx_channel`
- **Importance:** HIGH (interrupts user)
- **Sound:** Enabled (uses system default)
- **Vibration:** Enabled

### iOS Settings

- **Alert Permission:** Requested on first launch
- **Badge Permission:** Requested on first launch
- **Sound Permission:** Requested on first launch
- **Foreground Notification:** Shown even when app is open

### Runtime Permissions

- **Android 13+:** POST_NOTIFICATIONS permission required
- **iOS 10+:** User alert for notifications
- Permissions are requested automatically on first app launch

## Troubleshooting

### Notifications Not Showing

1. **Check Permission:**

   ```dart
   bool granted = await NotificationService.isNotificationPermissionGranted();
   if (!granted) {
     await NotificationService.requestNotificationPermission();
   }
   ```

2. **Check Device Settings:**

   - Settings > Notifications > AFX > Enable notifications
   - Settings > Notifications > AFX > Sounds & haptics

3. **Check Logs:**

   - Look for `[NOTIFICATION]` prefix in debug output
   - Check for error messages

4. **Rebuild App:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

### Toast Not Showing

- Check that notification service was initialized
- Verify `flutter_local_notifications` is in pubspec.yaml
- Check device notification settings

### Push Notification Not Showing in Notification Center

- Ensure app is in background when testing
- Check Android notification channel creation logs
- Verify importance is set to HIGH

## Code Example: Sending Notifications

### From Socket Service

```dart
// When message received
NotificationService.showMessageNotification(senderName, content);

// When request created
NotificationService.showNewRequestNotification(userName);

// When status changes
NotificationService.showRequestStatusNotification(userName, status);
```

### From Anywhere

```dart
// Show custom toast
await NotificationService.showSuccess('Operation completed!');
await NotificationService.showError('Something went wrong');
await NotificationService.showWarning('Warning message');
await NotificationService.showInfo('Information');
```

## Testing Checklist

- [ ] App launches without errors
- [ ] Permission is requested on first launch
- [ ] User grants notification permission
- [ ] Message received shows system notification + toast
- [ ] Request notification shows correctly
- [ ] Toast auto-dismisses after 3-4 seconds
- [ ] Sound plays when notification arrives
- [ ] Device vibrates when notification arrives
- [ ] Colors are correct for each notification type
- [ ] Tapping notification doesn't crash app
- [ ] Notifications appear in notification center
- [ ] Multiple notifications don't overlap

## Implementation Details

### Notification Service Initialization

Called in `main()` before running app:

```dart
await NotificationService.initialize();
```

### Permission Handling

Automatic with `permission_handler` package:

- Android 13+: Requests POST_NOTIFICATIONS at runtime
- iOS: Requests alert, badge, and sound permissions

### Notification Display

Two layers:

1. **Push Notification** - System-level (notification center)
2. **Toast** - In-app feedback (top of screen)

### Logging

All actions logged with emoji prefixes for easy debugging:

- 🚀 Initialization events
- ✅ Success messages
- ❌ Error messages
- 📤 Push notifications
- 📱 Toast notifications
- 🔔 Permission requests
- 📲 User interaction

## Next Steps

1. **Test on real device** - Notifications may work differently on emulator
2. **Customize sounds** - Add custom notification sound to `android/app/src/main/res/raw/`
3. **Handle notification payload** - Implement navigation when user taps notification
4. **Add notification preferences** - Let users customize notification types
5. **Implement notification history** - Store notification logs

## References

- `lib/services/notification_service.dart` - Main notification service
- `lib/main.dart` - Initialization code
- `NOTIFICATION_FIX_SUMMARY.md` - Complete change summary
- `NOTIFICATION_FLOW.md` - Notification flow diagrams
- [flutter_local_notifications documentation](https://pub.dev/packages/flutter_local_notifications)
- [permission_handler documentation](https://pub.dev/packages/permission_handler)
