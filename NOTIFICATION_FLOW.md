# Notification Flow Diagram

## Initialization Flow

```
main()
  ├─ Supabase.initialize()
  ├─ NotificationService.initialize()
  │   ├─ AndroidInitializationSettings
  │   ├─ DarwinInitializationSettings (iOS)
  │   └─ _createAndroidNotificationChannel()
  │       └─ Creates 'afx_channel' with HIGH importance
  └─ runApp(AFXApp())
```

## Message Notification Flow

```
Socket Service receives message
  ↓
_handleNewMessage() called
  ↓
NotificationService.showMessageNotification(senderName, content)
  ├─ _showPushNotification()
  │   └─ Shows system notification
  │       ├─ Android: High priority, vibration enabled
  │       └─ iOS: Alert, badge, sound enabled
  └─ showToast()
      └─ Shows in-app toast
          └─ Displayed at top of screen for 4 seconds
```

## Request Notification Flow

```
Socket Service receives request event
  ↓
NotificationService.showNewRequestNotification(userName)
  ├─ _showPushNotification() with emoji '📋'
  └─ showToast() with warning color
```

## Notification Display Layers

### Layer 1: System Push Notification (High Priority)

- Shown in Android notification center
- Shows notification sound and vibration
- User can tap to open app
- Remains visible until dismissed

### Layer 2: In-App Toast (Immediate Feedback)

- Shows at top of screen
- Auto-dismisses after 3-4 seconds
- Color-coded based on type:
  - 🟢 Green: Success
  - 🔴 Red: Error
  - 🟠 Orange: Warning
  - 🔵 Blue: Info

## Example: New Message Received

### What User Sees:

1. **Notification Sound + Vibration** (if enabled on device)
2. **System Notification** appears:
   ```
   AFX
   📨 New Message
   John: Hey, how are you?
   ```
3. **In-App Toast** appears:
   ```
   ┌──────────────────────────────────┐
   │ John: Hey, how are you?          │
   └──────────────────────────────────┘
   ```

## Configuration Details

### Android Channel (afx_channel)

- ID: `afx_channel`
- Name: `AFX Notifications`
- Importance: HIGH
- Sound: Enabled (uses default)
- Vibration: Enabled
- Alert Behavior: Default

### iOS Settings

- Alert Permission: Requested
- Badge Permission: Requested
- Sound Permission: Requested
- Foreground Presentation: Alert + Badge + Sound

### Toast Settings

- Position: Top of screen (ToastGravity.TOP)
- Duration: 3-4 seconds
- Font Size: 14px
- Colors: Dynamic based on type

## Notification Payload Structure

Each notification includes a payload for handling user interaction:

```dart
// Message notification
payload: 'message:$senderName'

// Request status notification
payload: 'request:$userName:$status'

// New request notification
payload: 'new_request:$userName'

// Message access notification
payload: 'access:$userName:$status'
```

## Debug Logging

All notification actions log with prefix `[NOTIFICATION]` and emojis:

- 🚀 Initialization
- ✅ Success
- ❌ Error
- 📤 Push notification shown
- 📱 Toast shown
- 🔔 Permission requested
- 📲 Notification tapped
- 🔐 Access changed
- 💬 Message received
- 📋 Request status
- 🆕 New request
- ⏳ Pending
- ⚠️ Warning

## Testing Checklist

- [ ] Permission is requested on first app launch
- [ ] Permission is granted
- [ ] Message received shows:
  - [ ] System notification in notification center
  - [ ] In-app toast appears
  - [ ] Sound plays (if device has sound on)
  - [ ] Device vibrates (if enabled)
- [ ] Request notification shows properly
- [ ] Toast auto-dismisses after 3-4 seconds
- [ ] Colors match notification type
- [ ] Tapping notification doesn't cause crashes
