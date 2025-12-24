# Current User Message Handling Flow

## 📤 SEND MESSAGE (Current User)

### Step 1: Optimistic Insert

```dart
final clientId = 'client_${timestamp}_${userId}'

optimisticMessage = {
  id: clientId,                    // Temporary ID
  senderId: widget.userId,
  senderName: widget.userName,
  content: text,
  role: widget.userRole,
  status: 'Sending',              // UI shows "Sending..."
  clientId: clientId,             // Track for replacement
}

_messages.insert(0, optimisticMessage)  // Show immediately
setState()  // Rebuild UI with temporary message
```

**Result in UI:** Message appears instantly with "Sending" status

---

### Step 2: Send to Server (Edge Function: send-message)

```
Flutter calls SupabaseService.sendMessage(senderId, content)
  ↓
Edge Function validates user
  ↓
INSERT message into database
  ↓
Database Trigger fires:
  - Calculates prev_sender_id (from previous message)
  - Calculates next_sender_id (from next message)
  - Updates previous message's next_sender_id
  ↓
Trigger returns message with:
  {
    id: 422,                    // Real server ID
    sender_id: 9,
    content: "...",
    role: "user",
    created_at: "...",
    prev_sender_id: 8,          // From trigger
    next_sender_id: null        // From trigger
  }
  ↓
Edge Function returns response
```

---

### Step 3: Replace Optimistic with Real Message

```dart
// Receive response from server
sentMessageData = {
  id: 422,
  sender_id: 9,
  prev_sender_id: 8,
  next_sender_id: null,
  ...
}

// Find optimistic message by clientId
optimisticIndex = _messages.indexWhere((msg) => msg['clientId'] == clientId)

// Replace at same index
_messages[optimisticIndex] = {
  ...sentMessageData,      // Real data with IDs from trigger
  'status': 'Sent',        // Update status
  'clientId': null,        // Clear temporary ID
  'sender_name': userName, // From current user
}

setState()  // Update UI with real message
```

**Result in UI:** Message updates with real ID and "Sent" status

---

### Step 4: Realtime INSERT Event (FROM DATABASE)

```
Database INSERT trigger completes
  ↓
Realtime broadcasts to all connected clients:
  {
    id: 422,
    sender_id: 9,
    content: "...",
    role: "user",
    created_at: "...",
    prev_sender_id: 8,
    next_sender_id: null
  }
  ↓
Current user receives event in subscribeToMessages()
  ↓
_handleNewMessage() called
  ↓
Check: if (incomingMessage['sender_id'] == widget.userId) return;  // ✅ SKIP!
  ↓
Message already in UI (from optimistic), so no duplicate
```

**Why no duplicate?**

- ✅ Realtime event is from sender_id 9 (current user)
- ✅ \_handleNewMessage() SKIPS current user messages
- ✅ Optimistic message already displayed

---

## 📥 RECEIVE MESSAGE (Other User)

### Step 1: Realtime INSERT Event

```
Other user sends message
  ↓
Database INSERT + Trigger
  ↓
Realtime broadcasts to current user:
  {
    id: 423,
    sender_id: 3,              // NOT current user (9)
    content: "Hello",
    role: "user",
    prev_sender_id: 9,         // From trigger
    next_sender_id: null
  }
  ↓
_handleNewMessage() called
  ↓
Check: if (incomingMessage['sender_id'] == widget.userId) return;  // ❌ Don't skip (sender_id=3, current=9)
  ↓
Add to UI
  ↓
Update previous message's next_sender_id if needed
```

**Result in UI:** New message from other user appears with full data

---

## 🔄 UPDATE MESSAGE (Current User - from Trigger)

### Scenario: Delete Other User's Message (Triggers Cascade Update)

```
Admin deletes message 422 (current user sent)
  ↓
Database DELETE fires trigger
  ↓
Trigger updates adjacent messages:
  - Message 421's next_sender_id changes
  ↓
Realtime UPDATE event:
  {
    id: 421,
    sender_id: 5,
    next_sender_id: 3          // Changed!
  }
  ↓
_updateMessageById(421, {...}) called
  ↓
Check: if (updatedData['sender_id'] == widget.userId) return;  // Skip (sender_id=5, current=9)
  ↓
Update message 421 in UI with new next_sender_id
```

**Why skip current user updates?**

- Current user doesn't DELETE their own messages via trigger
- Updates to current user's messages should come from their own actions
- Prevents race conditions with optimistic updates

---

## 🗑️ DELETE MESSAGE (Current User)

**Scenario: Current User Deletes Their Own Message**

### Client-Side (Not Yet Implemented - For Future)

```
User clicks delete on message ID=422
  ↓
Call API to delete (would need to add this function)
  ↓
Optimistically remove from UI
  ↓
Realtime DELETE event fires
  ↓
_deleteMessageById(422) removes it again (harmless, already gone)
```

---

## 📊 CURRENT STATE TABLE

| Action                                         | Trigger                | Handler                       | Result                                    |
| ---------------------------------------------- | ---------------------- | ----------------------------- | ----------------------------------------- |
| **Current user sends message**                 | Manual send            | sendMessage() + Realtime skip | Optimistic → Real ID                      |
| **Other user sends message**                   | Realtime INSERT        | \_handleNewMessage()          | Added to UI with full data                |
| **Trigger updates adjacent (delete scenario)** | Database trigger       | \_updateMessageById()         | Previous message's next_sender_id updated |
| **Message deleted**                            | Realtime DELETE        | \_deleteMessageById()         | Message removed from UI                   |
| **Current user deletes own**                   | ❌ Not yet implemented | N/A                           | N/A                                       |

---

## ⚠️ CURRENT LIMITATIONS

1. **Current user can't DELETE their own messages**

   - UI doesn't have delete button
   - No delete endpoint
   - Would require: Click button → API delete → Realtime event

2. **Current user can't EDIT their own messages**
   - UI doesn't have edit button
   - No update endpoint
   - Would require: Click button → API update → Realtime event

---

## ✅ WHAT WORKS NOW

| Feature                       | Status   | How                                     |
| ----------------------------- | -------- | --------------------------------------- |
| Send message                  | ✅ Works | Optimistic + server replace             |
| Receive message               | ✅ Works | Realtime INSERT                         |
| Message grouping              | ✅ Works | prev/next_sender_id from triggers       |
| Auto-update adjacent msgs     | ✅ Works | Realtime UPDATE + \_updateMessageById() |
| Skip current user in Realtime | ✅ Works | sender_id check in \_handleNewMessage() |

---

## 🔧 FUTURE: Add Delete/Edit for Current User

**Would need:**

1. Add delete button to UI (only for current user's messages)
2. Create Edge Function: `delete-message`
3. Create Edge Function: `update-message`
4. Handle Realtime events like other updates

**Architecture would stay the same:**

```
User action → Optimistic update → Server call → Realtime confirmation
```
