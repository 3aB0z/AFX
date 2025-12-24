// lib/pages/requests_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/socket_service.dart';
import '../services/supabase_service.dart';
import '../widgets/profile_avatar.dart';

// ============================================================================
// REQUEST MANAGEMENT UTILITIES
// ============================================================================

/// Updates a request status via socket and performs optimistic UI update
Future<void> _requestUpdateStatus(
  int requestId,
  String newStatus,
  List<Map<String, dynamic>> allRequests,
  List<Map<String, dynamic>> pendingRequests,
  List<Map<String, dynamic>> verifiedRequests,
  List<Map<String, dynamic>> rejectedRequests,
  Map<String, bool> hasLoaded,
  Function(void Function()) setState,
) async {
  try {
    // Emit socket event to update request status
    SocketService.emit('update_request_status', {
      'id': requestId,
      'status': newStatus,
    });

    // Remove from all applicable lists (optimistic update)
    for (var list in [
      allRequests,
      pendingRequests,
      verifiedRequests,
      rejectedRequests,
    ]) {
      final index = list.indexWhere((r) => r['id'] == requestId);
      if (index != -1) {
        setState(() {
          list.removeAt(index);
          // Clear the target filter's cache to refresh when selected
          if (newStatus == 'verified') {
            hasLoaded['verified'] = false;
          } else if (newStatus == 'rejected') {
            hasLoaded['rejected'] = false;
          } else if (newStatus == 'pending') {
            hasLoaded['pending'] = false;
          }
          // Also clear all cache if removing from all
          if (list == allRequests) {
            hasLoaded['all'] = false;
          }
        });
      }
    }

    // Socket event will automatically update counts
  } catch (e) {
    debugPrint('Error updating request: $e');
  }
}

/// Toggles message access for a user via socket and performs optimistic UI update
Future<void> _requestToggleMessageAccess(
  int userId,
  int currentAccess,
  List<Map<String, dynamic>> verifiedRequests,
  Function(void Function()) setState,
) async {
  try {
    // Emit socket event to toggle message access
    SocketService.emit('toggle_message_access', {
      'id': userId,
      'canSendMessages': currentAccess == 0,
    });

    // Optimistic update
    final index = verifiedRequests.indexWhere((r) => r['id'] == userId);
    if (index != -1) {
      setState(() {
        verifiedRequests[index]['can_send_messages'] =
            verifiedRequests[index]['can_send_messages'] == 0 ? 1 : 0;
      });
    }
  } catch (e) {
    debugPrint('Error toggling message access: $e');
  }
}

/// Shows a dialog to edit request status
Future<void> _requestShowEditDialog(
  BuildContext context,
  Map<String, dynamic> request,
  Function(int, String) onStatusChanged,
) async {
  String selectedStatus = request['status'] ?? 'pending';

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Update Request Status'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: ['pending', 'verified', 'rejected']
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  selectedStatus = value;
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onStatusChanged(request['id'], selectedStatus);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Config.primaryColor),
          child: const Text('Update', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class RequestsPage extends StatefulWidget {
  final int userId;
  final String userName;
  final String userEmail;

  const RequestsPage({
    required this.userId,
    required this.userName,
    required this.userEmail,
    super.key,
  });

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final baseUrl = Config.baseUrl;

  // Separate lists for each status
  final List<Map<String, dynamic>> _allRequests = [];
  final List<Map<String, dynamic>> _pendingRequests = [];
  final List<Map<String, dynamic>> _verifiedRequests = [];
  final List<Map<String, dynamic>> _rejectedRequests = [];

  bool _isLoading = false;
  bool _initialLoadComplete = false;
  String _selectedFilter = 'all'; // 'all', 'pending', 'verified', 'rejected'

  // Counts for each filter - MUTABLE
  int _pendingCount = 0;
  int _verifiedCount = 0;
  int _rejectedCount = 0;
  int _allCount = 0;

  // Track which filters have been loaded
  final Map<String, bool> _hasLoaded = {
    'all': false,
    'pending': false,
    'verified': false,
    'rejected': false,
  };

  // Pagination tracking
  final Map<String, bool> _isLoadingMore = {
    'all': false,
    'pending': false,
    'verified': false,
    'rejected': false,
  };
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

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchStatusCounts(); // Fetch counts before loading data
    _startInitialLoad();

    // TODO: Migrate these Socket.io listeners to Supabase Realtime when needed
    // For now, requests page uses polling via _startInitialLoad() and manual refresh
    /*
    // Listen for real-time admin count updates
    SocketService.onAdminCountsUpdated((data) {
      if (mounted) {
        setState(() {
          _pendingCount = data['pending'] ?? 0;
          _verifiedCount = data['verified'] ?? 0;
          _rejectedCount = data['rejected'] ?? 0;
          _allCount = data['all'] ?? 0;
        });
      }
    });

    // Listen for individual request updates (from any source - UI, Postman, etc.)
    SocketService.onRequestUpdated((data) {
      if (mounted) {
        final requestId = data['id'];
        final updates = data['updates'] as Map<String, dynamic>? ?? {};

        // Update request in all relevant lists
        for (var list in [
          _allRequests,
          _pendingRequests,
          _verifiedRequests,
          _rejectedRequests,
        ]) {
          final index = list.indexWhere((r) => r['id'] == requestId);
          if (index != -1) {
            setState(() {
              // Update the request with new data
              if (updates['status'] != null) {
                list[index]['status'] = updates['status'];
              }
              if (updates['name'] != null) {
                list[index]['name'] = updates['name'];
              }
              if (updates['email'] != null) {
                list[index]['email'] = updates['email'];
              }
            });
          }
        }
      }
    });

    // Listen for message access changes to update UI
    SocketService.onMessageAccessChanged((data) {
      if (mounted) {
        final userId = data['userId'];

        // Update verified requests (only verified users can have message access toggled)
        for (var i = 0; i < _verifiedRequests.length; i++) {
          if (_verifiedRequests[i]['id'] == userId) {
            setState(() {
              _verifiedRequests[i]['can_send_messages'] =
                  data['canSendMessages'] ? 1 : 0;
            });
            break;
          }
        }
      }
    });

    // Listen for all requests data
    SocketService.onRequestsAllLoaded((data) {
      if (mounted) {
        final List<dynamic> requestsList = data['requests'] is List
            ? data['requests']
            : [];
        final page = data['page'] ?? 0;

        setState(() {
          if (page == 0) {
            // First page - clear and set
            _allRequests.clear();
            _allRequests.addAll(
              requestsList.map((r) => r as Map<String, dynamic>),
            );
            _hasLoaded['all'] = true;
            _pages['all'] = 1;
          } else {
            // More pages - append
            _allRequests.addAll(
              requestsList.map((r) => r as Map<String, dynamic>),
            );
            _pages['all'] = _pages['all']! + 1;
          }
          _hasMore['all'] = data['hasMore'] ?? false;
          _isLoading = false;
          _isLoadingMore['all'] = false;
        });
      }
    });

    // Listen for requests by status data
    SocketService.onRequestsByStatusLoaded((data) {
      if (mounted) {
        final String status = data['status'] ?? '';
        final List<dynamic> requestsList = data['requests'] is List
            ? data['requests']
            : [];
        final page = data['page'] ?? 0;

        setState(() {
          if (page == 0) {
            // First page - clear and set
            if (status == 'pending') {
              _pendingRequests.clear();
              _pendingRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            } else if (status == 'verified') {
              _verifiedRequests.clear();
              _verifiedRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            } else if (status == 'rejected') {
              _rejectedRequests.clear();
              _rejectedRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            }
            _hasLoaded[status] = true;
            _pages[status] = 1;
          } else {
            // More pages - append
            if (status == 'pending') {
              _pendingRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            } else if (status == 'verified') {
              _verifiedRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            } else if (status == 'rejected') {
              _rejectedRequests.addAll(
                requestsList.map((r) => r as Map<String, dynamic>),
              );
            }
            _pages[status] = _pages[status]! + 1;
          }
          _hasMore[status] = data['hasMore'] ?? false;
          _isLoading = false;
          _isLoadingMore[status] = false;
        });
      }
    });
    */
  }

  Future<void> _startInitialLoad() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      // Load the 'all' filter by default
      await _loadAllRequests();
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
        });
      }
    }
  }

  Future<void> _fetchStatusCounts() async {
    try {
      debugPrint('[REQUESTS_PAGE] 📊 Fetching status counts on page entry...');
      final counts = await SupabaseService.getAdminCounts();

      if (mounted) {
        setState(() {
          _pendingCount = counts['pending'] ?? 0;
          _verifiedCount = counts['verified'] ?? 0;
          _rejectedCount = counts['rejected'] ?? 0;
          _allCount = counts['all'] ?? 0;
          debugPrint(
            '[REQUESTS_PAGE] ✅ Counts loaded: pending=$_pendingCount, verified=$_verifiedCount, rejected=$_rejectedCount, all=$_allCount',
          );
        });
      }
    } catch (e) {
      debugPrint('[REQUESTS_PAGE] ❌ Error fetching status counts: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      if (_selectedFilter == 'all') {
        // Load more for 'all' filter
        if (!_isLoadingMore['all']! && _hasMore['all']!) {
          _loadMoreAllRequests();
        }
      } else if (!_isLoadingMore[_selectedFilter]! &&
          _hasMore[_selectedFilter]!) {
        // Load more for individual filters
        _loadMoreRequestsByStatus(_selectedFilter);
      }
    }
  }

  Future<void> _loadRequestsByStatus(String status) async {
    // Skip if already loaded
    if (_hasLoaded[status] == true) return;

    setState(() => _isLoading = true);
    _pages[status] = 0;

    try {
      debugPrint('[REQUESTS_PAGE] 📥 Loading $status requests via Supabase...');
      final result = await SupabaseService.getRequestsByStatus(status, 0);

      if (mounted) {
        setState(() {
          if (status == 'pending') {
            _pendingRequests.clear();
            _pendingRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
            _pendingCount = result['total'] ?? 0;
          } else if (status == 'verified') {
            _verifiedRequests.clear();
            _verifiedRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
            _verifiedCount = result['total'] ?? 0;
          } else if (status == 'rejected') {
            _rejectedRequests.clear();
            _rejectedRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
            _rejectedCount = result['total'] ?? 0;
          }
          _hasLoaded[status] = true;
          _pages[status] = 1;
          _hasMore[status] = result['hasMore'] ?? false;
          _isLoading = false;
          debugPrint(
            '[REQUESTS_PAGE] ✅ Loaded ${(result['requests'] as List).length} $status requests, total: ${result['total']}',
          );
        });
      }
    } catch (e) {
      debugPrint('[REQUESTS_PAGE] ❌ Error loading $status requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreRequestsByStatus(String status) async {
    if (_isLoadingMore[status]!) return;
    setState(() => _isLoadingMore[status] = true);

    try {
      debugPrint(
        '[REQUESTS_PAGE] 📥 Loading more $status requests (page ${_pages[status]})...',
      );
      final result = await SupabaseService.getRequestsByStatus(
        status,
        _pages[status]!,
      );

      if (mounted) {
        setState(() {
          if (status == 'pending') {
            _pendingRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
          } else if (status == 'verified') {
            _verifiedRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
          } else if (status == 'rejected') {
            _rejectedRequests.addAll(
              (result['requests'] as List).cast<Map<String, dynamic>>(),
            );
          }
          _pages[status] = _pages[status]! + 1;
          _hasMore[status] = result['hasMore'] ?? false;
          _isLoadingMore[status] = false;
          debugPrint(
            '[REQUESTS_PAGE] ✅ Loaded more ${(result['requests'] as List).length} $status requests',
          );
        });
      }
    } catch (e) {
      debugPrint('[REQUESTS_PAGE] ❌ Error loading more $status requests: $e');
      if (mounted) {
        setState(() => _isLoadingMore[status] = false);
      }
    }
  }

  Future<void> _loadAllRequests() async {
    if (_hasLoaded['all'] == true) return;

    setState(() => _isLoading = true);
    _pages['all'] = 0;

    try {
      debugPrint('[REQUESTS_PAGE] 📥 Loading all requests (page 0)...');
      final result = await SupabaseService.getAllRequestsByPagination(0);

      if (mounted) {
        setState(() {
          _allRequests.clear();
          _allRequests.addAll(
            (result['requests'] as List).cast<Map<String, dynamic>>(),
          );
          _allCount = result['total'] ?? 0;
          _hasLoaded['all'] = true;
          _pages['all'] = 1;
          _hasMore['all'] = result['hasMore'] ?? false;
          _isLoading = false;
          debugPrint(
            '[REQUESTS_PAGE] ✅ Loaded ${(result['requests'] as List).length} total requests, total: ${result['total']}',
          );
        });
      }
    } catch (e) {
      debugPrint('[REQUESTS_PAGE] ❌ Error loading all requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreAllRequests() async {
    if (_isLoadingMore['all']!) return;
    setState(() => _isLoadingMore['all'] = true);

    try {
      debugPrint(
        '[REQUESTS_PAGE] 📥 Loading more all requests (page ${_pages['all']})...',
      );
      final result = await SupabaseService.getAllRequestsByPagination(
        _pages['all']!,
      );

      if (mounted) {
        setState(() {
          _allRequests.addAll(
            (result['requests'] as List).cast<Map<String, dynamic>>(),
          );
          _pages['all'] = _pages['all']! + 1;
          _hasMore['all'] = result['hasMore'] ?? false;
          _isLoadingMore['all'] = false;
          debugPrint(
            '[REQUESTS_PAGE] ✅ Loaded more ${(result['requests'] as List).length} total requests',
          );
        });
      }
    } catch (e) {
      debugPrint('[REQUESTS_PAGE] ❌ Error loading more all requests: $e');
      if (mounted) {
        setState(() => _isLoadingMore['all'] = false);
      }
    }
  }

  Future<void> updateRequestStatus(int requestId, String newStatus) async {
    await _requestUpdateStatus(
      requestId,
      newStatus,
      _allRequests,
      _pendingRequests,
      _verifiedRequests,
      _rejectedRequests,
      _hasLoaded,
      setState,
    );
  }

  Future<void> toggleMessageAccess(int userId, int currentAccess) async {
    await _requestToggleMessageAccess(
      userId,
      currentAccess,
      _verifiedRequests,
      setState,
    );
  }

  Future<void> showEditDialog(Map<String, dynamic> request) async {
    await _requestShowEditDialog(context, request, updateRequestStatus);
  }

  @override
  Widget build(BuildContext context) {
    final currentRequests = _selectedFilter == 'all'
        ? _allRequests
        : _selectedFilter == 'pending'
        ? _pendingRequests
        : _selectedFilter == 'verified'
        ? _verifiedRequests
        : _rejectedRequests;

    return Scaffold(
      backgroundColor: Config.background,
      appBar: AppBar(
        toolbarHeight: 56,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Requests',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black,
            fontSize: 20,
          ),
        ),
        elevation: 2,
        shadowColor: Colors.grey.withAlpha(51),
        backgroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter chips (WhatsApp style)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
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
          // Requests list
          Expanded(
            child: RefreshIndicator(
              color: Config.primaryColor,
              onRefresh: () async {
                debugPrint(
                  '[REQUESTS_PAGE] 🔄 Pull-to-refresh triggered for $_selectedFilter',
                );
                if (_selectedFilter == 'all') {
                  _allRequests.clear();
                  _pages['all'] = 0;
                  _hasMore['all'] = true;
                  _hasLoaded['all'] = false;
                  await _loadAllRequests();
                } else {
                  if (_selectedFilter == 'pending') {
                    _pendingRequests.clear();
                  } else if (_selectedFilter == 'verified') {
                    _verifiedRequests.clear();
                  } else if (_selectedFilter == 'rejected') {
                    _rejectedRequests.clear();
                  }
                  _pages[_selectedFilter] = 0;
                  _hasMore[_selectedFilter] = true;
                  _hasLoaded[_selectedFilter] = false;
                  await _loadRequestsByStatus(_selectedFilter);
                }
              },
              child: _isLoading && currentRequests.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Config.primaryColor,
                      ),
                    )
                  : !_initialLoadComplete && currentRequests.isEmpty
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
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No $_selectedFilter requests',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
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
                      interactive: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        itemCount:
                            currentRequests.length +
                            (_selectedFilter != 'all' &&
                                    _hasMore[_selectedFilter]!
                                ? 1
                                : 0),
                        itemBuilder: (context, index) {
                          if (index == currentRequests.length) {
                            return Padding(
                              padding: const EdgeInsets.all(8),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Config.primaryColor,
                                  ),
                                ),
                              ),
                            );
                          }
                          final request = currentRequests[index];
                          final status = request['status'] ?? _selectedFilter;
                          final Color statusColor =
                              status.toLowerCase() == 'verified'
                              ? Colors.green
                              : status.toLowerCase() == 'rejected'
                              ? Colors.red[400]!
                              : Colors.orange;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Config.veryLightPurpleColor,
                            elevation: 2,
                            shadowColor: const Color.fromARGB(140, 0, 0, 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
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
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        request['name'],
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 16,
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
                                                                .withAlpha(128),
                                                            width: 0.5,
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
                                                    request['email'],
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
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
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          if (status.toLowerCase() ==
                                              'verified')
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                  width: 1,
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
                                                    (request['can_send_messages'] !=
                                                            0)
                                                        ? Icons.chat_outlined
                                                        : Icons
                                                              .speaker_notes_off_outlined,
                                                    color:
                                                        (request['can_send_messages'] !=
                                                            0)
                                                        ? Colors.green
                                                        : Colors.red[400],
                                                    size: 22,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 4),
                                          if (status.toLowerCase() != 'pending')
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                  width: 1,
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
                                                    color: Colors.blue,
                                                    size: 22,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (status.toLowerCase() == 'pending')
                                    const SizedBox(height: 12),
                                  if (status.toLowerCase() == 'pending')
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
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

  Widget _buildFilterChip(String value, String label, int count) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
        // Scroll to top safely if controller is attached
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        // Load filters when selected (lazy loading)
        if (value == 'all') {
          // Load all filters when 'all' is selected
          _loadAllRequests();
        } else {
          // Load individual filter if not already loaded
          if (!_hasLoaded[value]!) {
            _loadRequestsByStatus(value);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Config.primaryLightest : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Config.primaryLight : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(2, 0, 0, 0),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Config.primaryColor : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
                maxHeight: 18,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? Colors.green[400] : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 0 ? count.toString() : '',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
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
}
