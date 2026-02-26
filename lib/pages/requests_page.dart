import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import '../widgets/profile_avatar.dart';

// Request management logic is now integrated directly into RequestsPage methods

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  // Active Streams
  final Map<String, StreamSubscription?> _subscriptions = {};

  // Data Store (Isolated lists per requirement)
  final Map<String, List<Map<String, dynamic>>> _requestsData = {
    'all': [],
    'pending': [],
    'verified': [],
    'rejected': [],
  };

  // Loading State
  final Map<String, bool> _isLoading = {
    'all': false,
    'pending': false,
    'verified': false,
    'rejected': false,
  };

  // Pagination State (per tab)
  final Map<String, bool> _hasMore = {
    'all': true,
    'pending': true,
    'verified': true,
    'rejected': true,
  };

  final Map<String, int> _pages = {
    'all': 0,
    'pending': 0,
    'verified': 0,
    'rejected': 0,
  };

  // Status Counts
  int _pendingCount = 0;
  int _verifiedCount = 0;
  int _rejectedCount = 0;
  int _allCount = 0;
  StreamSubscription? _statusCountsSubscription;

  String _selectedFilter = 'all'; // 'all', 'pending', 'verified', 'rejected'
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Always listen to counts for the chips
    _listenToStatusCounts();

    // Lazy Load: Only load the initial selected filter ('all')
    _loadRequestsForFilter(_selectedFilter);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _statusCountsSubscription?.cancel();
    for (var sub in _subscriptions.values) {
      sub?.cancel();
    }
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreRequests(_selectedFilter);
    }
  }

  // ===========================================================================
  // DATA FETCHING & STREAMS
  // ===========================================================================

  void _listenToStatusCounts() {
    _statusCountsSubscription = FirebaseService.getAllStatusCountsStream()
        .listen(
          (counts) {
            if (mounted) {
              setState(() {
                _pendingCount = counts['pending'] ?? 0;
                _verifiedCount = counts['verified'] ?? 0;
                _rejectedCount = counts['rejected'] ?? 0;
                _allCount = counts['all'] ?? 0;
              });
            }
          },
          onError: (e) =>
              debugPrint('[REQUESTS_PAGE] ❌ Error in counts stream: $e'),
        );
  }

  // Handles switching filters and lazy loading
  void _onFilterChanged(String newFilter) {
    if (_selectedFilter == newFilter) return;

    setState(() {
      _selectedFilter = newFilter;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // Lazy Loading: Check if we have a subscription or data already?
    // Requirement says: "Fetch data only when a specific status is selected." "Disable auto-fetching on page load."
    // And "specific statuses must fetch fresh data from their own endpoints".
    // We will ensure a subscription is active for this filter.
    if (_subscriptions[newFilter] == null) {
      _loadRequestsForFilter(newFilter);
    }
  }

  Future<void> _loadRequestsForFilter(String filter) async {
    // If we already have an active subscription for this filter, do we need to do anything?
    // The requirements imply we should fetch/subscribe when selected.
    // If we want to be strictly lazy and save resources, we could cancel other subscriptions?
    // But usually keeping them alive for a bit is better UX.
    // We will start the stream if not started.

    if (_subscriptions[filter] != null) return; // Already listening

    setState(() {
      _isLoading[filter] = true;
      _pages[filter] =
          0; // Reset pagination logic if we were using it, but for Streams with pagination it's tricky.
      // Note: The previous code mixed Pagination (getRequestsByStatus) and Streams.
      // To satisfy "Lazy-Loading" + "Async State Fix" + "Real-time behavior",
      // we need a STABLE approach.
      // Pure Streams are best for real-time. Pagination with Streams requires 'limit' increasion.
      // We will use the stream with a limit that increases on scroll.
    });

    _subscribeToStream(filter, limit: 20);
  }

  void _subscribeToStream(String filter, {int limit = 20}) {
    _subscriptions[filter]?.cancel();

    debugPrint(
      '[REQUESTS_PAGE] 🔌 Subscribing to $filter stream (limit: $limit)',
    );

    _subscriptions[filter] =
        FirebaseService.getRequestsStream(filter, limit: limit).listen(
          (data) {
            if (mounted) {
              setState(() {
                _requestsData[filter] = data;
                _isLoading[filter] = false;
                // Crude hasMore check: if we got exactly the limit, maybe there's more.
                _hasMore[filter] = data.length >= limit;
              });
              debugPrint(
                '[REQUESTS_PAGE] 📥 Stream matched for $filter: ${data.length} items',
              );
            }
          },
          onError: (e) {
            debugPrint('[REQUESTS_PAGE] ❌ Error in $filter stream: $e');
            if (mounted) {
              setState(() {
                _isLoading[filter] = false;
              });
            }
          },
        );
  }

  void _loadMoreRequests(String filter) {
    if (_isLoading[filter] == true) return; // Debounce
    // With streams, "load more" means increasing the limit of the query

    final currentLength = _requestsData[filter]?.length ?? 0;
    // Arbitrary pagination step
    final int newLimit = currentLength + 20;

    debugPrint(
      '[REQUESTS_PAGE] 📜 Loading more for $filter (new limit: $newLimit)',
    );

    // We don't set _isLoading to true here to avoid blocking interaction/flickering,
    // or we can show a bottom loader.
    // For streams, re-subscribing might cause a full refresh flicker if not handled carefully by Firestore (usually it's fine).
    _subscribeToStream(filter, limit: newLimit);
  }

  Future<void> _refreshCurrentFilter() async {
    // For streams, refresh usually resets the limit or forces a reconnect?
    // Or just resets the limit to 20.
    _subscribeToStream(_selectedFilter, limit: 20);
    setState(() {
      _pages[_selectedFilter] = 0;
    });
  }

  // ===========================================================================
  // ACTIONS (No Manual State Mutation - Rely on Stream)
  // ===========================================================================

  Future<void> updateRequestStatus(String userId, String newStatus) async {
    try {
      // Optimistic update removed per REQUIREMENTS for Data Integrity.
      // "specific statuses must fetch fresh data from their own endpoints rather than filtering existing local lists."
      // We rely on the server update propagating back via the stream.

      final result = await FirebaseService.updateUserStatus(userId, newStatus);
      if (!mounted) return;

      if (result.success) {
        debugPrint(
          '[REQUESTS_PAGE] ✅ Status updated for $userId to $newStatus',
        );
      } else {
        debugPrint(
          '[REQUESTS_PAGE] ❌ Failed to update status: ${result.message}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${result.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[REQUESTS_PAGE] ❌ Error updating status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> toggleMessageAccess(String userId, dynamic currentAccess) async {
    try {
      final bool newAccess = currentAccess != true;
      final result = await FirebaseService.toggleMessageAccess(
        userId,
        newAccess,
      );
      if (!mounted) return;

      if (result.success) {
        debugPrint(
          '[REQUESTS_PAGE] ✅ Message access toggled for $userId to $newAccess',
        );
      } else {
        debugPrint(
          '[REQUESTS_PAGE] ❌ Failed to toggle access: ${result.message}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${result.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('[REQUESTS_PAGE] ❌ Error toggling access: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle access: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================

  Future<void> showEditDialog(Map<String, dynamic> request) async {
    final String userId = request['id'] ?? '';
    String currentStatus = (request['status'] ?? 'pending')
        .toString()
        .toLowerCase();

    if (!['pending', 'verified', 'rejected'].contains(currentStatus)) {
      currentStatus = 'pending';
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Config.getSurfaceColor(context),
            title: Text(
              'Manage User Request Status',
              style: TextStyle(color: Config.getTextColor(context)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Config.getDividerColor(context)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      dropdownColor: Config.getSurfaceColor(context),
                      borderRadius: BorderRadius.circular(8),
                      value: currentStatus,
                      isExpanded: true,
                      style: TextStyle(color: Config.getTextColor(context)),
                      items: ['pending', 'verified', 'rejected'].map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(
                            status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(
                              color: Config.getTextColor(context),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setDialogState(() => currentStatus = newValue);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Config.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  updateRequestStatus(userId, currentStatus);
                  Navigator.pop(context);
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, int count) {
    final isSelected = _selectedFilter == value;
    final isDarkMode = Config.isDarkMode(context);

    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Config.primaryColor.withAlpha(isDarkMode ? 40 : 25)
              : Config.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Config.primaryColor.withAlpha(isDarkMode ? 100 : 40)
                : Config.getDividerColor(context),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(2, 0, 0, 0),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Config.primaryColor
                      : Config.getTextColor(context, level: 2),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? Config.primaryColor.withAlpha(isDarkMode ? 180 : 255)
                    : Config.getDividerColor(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Config.getTextColor(context, level: 2),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRequests = _requestsData[_selectedFilter] ?? [];
    final isDarkMode = Config.isDarkMode(context);
    final isCurrentLoading = _isLoading[_selectedFilter] ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 56,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Config.getTextColor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Requests',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Config.getTextColor(context),
            fontSize: 20,
          ),
        ),
        elevation: 0,
        backgroundColor: Config.getSurfaceColor(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildFilterChip('all', 'All', _allCount),
                const SizedBox(width: 8),
                _buildFilterChip('pending', 'Pending', _pendingCount),
                const SizedBox(width: 8),
                _buildFilterChip('verified', 'Verified', _verifiedCount),
                const SizedBox(width: 8),
                _buildFilterChip('rejected', 'Rejected', _rejectedCount),
              ],
            ),
          ),

          // List
          Expanded(
            child: RefreshIndicator(
              color: Config.primaryColor,
              onRefresh: _refreshCurrentFilter,
              child: isCurrentLoading && currentRequests.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Config.primaryColor,
                      ),
                    )
                  : currentRequests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: Config.getTextColor(context, level: 3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No $_selectedFilter requests',
                            style: TextStyle(
                              fontSize: 18,
                              color: Config.getTextColor(context, level: 2),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: false,
                      thickness: 6,
                      radius: const Radius.circular(3),
                      thumbColor: Config.primaryColor.withAlpha(100),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        itemCount:
                            currentRequests.length + 1, // +1 for loader/spacer
                        itemBuilder: (context, index) {
                          if (index == currentRequests.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _hasMore[_selectedFilter] == true
                                    ? SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Config.primaryColor,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            );
                          }

                          final request = currentRequests[index];
                          final status = (request['status'] ?? '').toString();
                          final Color statusColor =
                              status.toLowerCase() == 'verified'
                              ? Colors.green
                              : status.toLowerCase() == 'rejected'
                              ? Colors.red[400]!
                              : Colors.blue;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Config.getSurfaceColor(context),
                            elevation: isDarkMode ? 0 : 2,
                            shadowColor: Config.getShadowColor(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isDarkMode
                                  ? BorderSide(
                                      color: Config.getDividerColor(context),
                                    )
                                  : BorderSide.none,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            ProfileAvatar(
                                              fullName:
                                                  request['name'] ?? 'User',
                                              size: 40,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        request['name'] ??
                                                            'User',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 16,
                                                          color:
                                                              Config.getTextColor(
                                                                context,
                                                              ),
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: statusColor
                                                              .withAlpha(26),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                          border: Border.all(
                                                            color: statusColor
                                                                .withAlpha(
                                                                  isDarkMode
                                                                      ? 100
                                                                      : 128,
                                                                ),
                                                            width: isDarkMode
                                                                ? 1
                                                                : 0.5,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          status.toUpperCase(),
                                                          style: TextStyle(
                                                            color: statusColor,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    request['email'] ?? '',
                                                    style: TextStyle(
                                                      color:
                                                          Config.getTextColor(
                                                            context,
                                                            level: 2,
                                                          ),
                                                      fontSize: 13,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (status.toLowerCase() ==
                                              'verified')
                                            Container(
                                              decoration: BoxDecoration(
                                                color:
                                                    Config.getBackgroundColor(
                                                      context,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Config.getDividerColor(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: () => toggleMessageAccess(
                                                  request['id'],
                                                  request['can_send_messages'],
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  child: Icon(
                                                    request['can_send_messages'] ==
                                                            true
                                                        ? Icons.chat_outlined
                                                        : Icons
                                                              .speaker_notes_off_outlined,
                                                    color:
                                                        request['can_send_messages'] ==
                                                            true
                                                        ? Colors.green
                                                        : (isDarkMode
                                                              ? Colors.red[300]
                                                              : Colors
                                                                    .red[400]),
                                                    size: 22,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 4),
                                          if (status.toLowerCase() != 'pending')
                                            Container(
                                              decoration: BoxDecoration(
                                                color:
                                                    Config.getBackgroundColor(
                                                      context,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Config.getDividerColor(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: () =>
                                                    showEditDialog(request),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  child: Icon(
                                                    Icons.edit,
                                                    color: isDarkMode
                                                        ? Colors.blue[300]
                                                        : Colors.blue,
                                                    size: 22,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (status.toLowerCase() == 'pending') ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                updateRequestStatus(
                                                  request['id'],
                                                  'verified',
                                                ),
                                            icon: const Icon(
                                              Icons.check_circle,
                                              size: 20,
                                            ),
                                            label: const Text('Approve'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                updateRequestStatus(
                                                  request['id'],
                                                  'rejected',
                                                ),
                                            icon: const Icon(Icons.close),
                                            label: const Text('Reject'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red[400]!,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
