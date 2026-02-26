// lib/pages/request_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  bool loading = false;
  bool _initialLoading = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _requestStatus;

  DateTime? _deviceRejectionTime;
  Duration _timeLeft = Duration.zero;
  Timer? _cooldownTimer;
  StreamSubscription? _rejectedUserSubscription;

  bool get _hasExistingRequest => _requestStatus == 'pending';
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _initializeFlow();
  }

  Future<void> _initializeFlow() async {
    setState(() => _initialLoading = true);
    await Future.wait([
      _checkDeviceRejection(),
      _checkExistingRequest(),
      _checkLoginStatus(),
    ]);
    if (mounted) {
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _checkDeviceRejection() async {
    final rejectionTime = await FirebaseService.getDeviceRejectionTime();
    final rejectedUserId = await FirebaseService.getDeviceRejectionUserId();

    if (rejectionTime != null) {
      if (mounted) {
        setState(() {
          _deviceRejectionTime = rejectionTime;
          _calculateTimeLeft();
        });
      }
      _startCooldownTimer();

      // If we have a rejectedUserId, listen for verification while logged out
      if (rejectedUserId != null && !_isLoggedIn) {
        _listenForRejectionClearing(rejectedUserId);
      }
    }
  }

  void _listenForRejectionClearing(String uid) {
    _rejectedUserSubscription?.cancel();
    _rejectedUserSubscription = FirebaseService.getUserDataStream(uid).listen(
      (userDataSnapshot) {
        if (!mounted) return;
        final userData = userDataSnapshot.data();
        if (userData == null) return;

        final status = (userData['status'] ?? '').toString().toLowerCase();

        if (status == 'verified' || status == 'pending') {
          // Rejection was lifted or changed! Clear local penalty.
          FirebaseService.clearDeviceRejection();
          if (mounted) {
            setState(() {
              _timeLeft = Duration.zero;
              _requestStatus = status;
              _deviceRejectionTime = null;
            });
            _cooldownTimer?.cancel();
            _rejectedUserSubscription?.cancel();
          }
        }
      },
      onError: (e) {
        debugPrint('[REQUEST_PAGE] ⚠️ Error syncing status: $e');
        // Likely permission error since we aren't using Anon Auth, but we try anyway
      },
    );
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateTimeLeft();
    });
  }

  void _calculateTimeLeft() {
    if (_deviceRejectionTime == null) return;

    final now = DateTime.now();
    final unlockTime = _deviceRejectionTime!.add(const Duration(hours: 24));
    final difference = unlockTime.difference(now);

    if (mounted) {
      setState(() {
        _timeLeft = difference.isNegative ? Duration.zero : difference;
        if (_timeLeft == Duration.zero) {
          _cooldownTimer?.cancel();
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _cooldownTimer?.cancel();
    _rejectedUserSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    setState(() {
      _isLoggedIn = user != null;
    });
  }

  Future<void> _checkExistingRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => loading = true);
    try {
      final doc = await FirebaseService.getUserData(user.uid);
      if (!mounted) return;

      if (doc != null) {
        setState(() {
          _requestStatus = doc['status']?.toString().toLowerCase();
        });
      }
    } catch (e) {
      debugPrint('[REQUEST_PAGE] Error checking existing request: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendRequest() async {
    if (nameCtrl.text.trim().isEmpty ||
        emailCtrl.text.trim().isEmpty ||
        passwordCtrl.text.isEmpty ||
        confirmPasswordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (passwordCtrl.text != confirmPasswordCtrl.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => loading = true);
    try {
      await FirebaseService.signUp(
        emailCtrl.text.trim(),
        passwordCtrl.text,
        nameCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => loading = false);

      // Clear form
      nameCtrl.clear();
      emailCtrl.clear();
      passwordCtrl.clear();
      confirmPasswordCtrl.clear();

      if (!mounted) return;
      setState(() {
        _requestStatus = 'pending';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request sent successfully! Admin will review it.'),
          duration: Duration(seconds: 2),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request timed out - Please try again'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);

      final errorMsg = e.toString();
      String displayMessage = 'Error: $errorMsg';

      // Parse specific errors
      if (errorMsg.contains('Email already exists')) {
        displayMessage = 'Email already exists - Please use a different email';
      } else if (errorMsg.contains('Invalid')) {
        displayMessage = 'Invalid input - Please check your details';
      } else if (errorMsg.contains('Connection')) {
        displayMessage = 'Connection error - Check your internet';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildStatusSection({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(26),
          ),
          padding: const EdgeInsets.all(16),
          child: Icon(icon, size: 64, color: color),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color == Colors.red
                ? color
                : Config.getTextColor(context, level: 3),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameCtrl,
          focusNode: _nameFocus,
          style: TextStyle(color: Config.getTextColor(context)),
          decoration: InputDecoration(
            hoverColor: Colors.transparent,
            labelText: 'Full Name',
            labelStyle: TextStyle(
              color: Config.getTextColor(context, level: 3),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.getBackgroundColor(context),
            prefixIcon: Icon(
              Icons.person_outline,
              color: Config.getTextColor(context, level: 3),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _nameFocus.unfocus();
            FocusScope.of(context).requestFocus(_emailFocus);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: emailCtrl,
          focusNode: _emailFocus,
          style: TextStyle(color: Config.getTextColor(context)),
          decoration: InputDecoration(
            hoverColor: Colors.transparent,
            labelText: 'Email',
            labelStyle: TextStyle(
              color: Config.getTextColor(context, level: 3),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.getBackgroundColor(context),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: Config.getTextColor(context, level: 3),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _emailFocus.unfocus();
            FocusScope.of(context).requestFocus(_passwordFocus);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordCtrl,
          focusNode: _passwordFocus,
          style: TextStyle(color: Config.getTextColor(context)),
          decoration: InputDecoration(
            hoverColor: Colors.transparent,
            labelText: 'Password',
            labelStyle: TextStyle(
              color: Config.getTextColor(context, level: 3),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.getBackgroundColor(context),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: Config.getTextColor(context, level: 3),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Config.getTextColor(context, level: 3),
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            _passwordFocus.unfocus();
            FocusScope.of(context).requestFocus(_confirmPasswordFocus);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: confirmPasswordCtrl,
          focusNode: _confirmPasswordFocus,
          style: TextStyle(color: Config.getTextColor(context)),
          decoration: InputDecoration(
            hoverColor: Colors.transparent,
            labelText: 'Confirm Password',
            labelStyle: TextStyle(
              color: Config.getTextColor(context, level: 3),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.getDividerColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.getBackgroundColor(context),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: Config.getTextColor(context, level: 3),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility
                    : Icons.visibility_off,
                color: Config.getTextColor(context, level: 3),
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
          ),
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            _confirmPasswordFocus.unfocus();
            sendRequest();
          },
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: loading || _hasExistingRequest ? null : sendRequest,
          style: FilledButton.styleFrom(
            backgroundColor: Config.primaryColor,
            disabledBackgroundColor: Config.getDividerColor(context),
            padding: const EdgeInsets.all(16),
            textStyle: const TextStyle(fontSize: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _hasExistingRequest ? 'REQUEST PENDING' : 'SEND REQUEST',
                style: TextStyle(color: Config.textLight),
              ),
              const SizedBox(width: 8),
              loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Config.primaryColor,
                      ),
                    )
                  : Icon(Icons.send_rounded, size: 20, color: Config.textLight),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: Config.primaryColor),
        ),
      );
    }

    // Hide completely when verified and logged in
    if (_requestStatus == 'verified' && _isLoggedIn) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: Config.getSurfaceColor(context),
              shadowColor: Config.getShadowColor(context),
              elevation: Config.isDarkMode(context) ? 0 : 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: Config.isDarkMode(context)
                    ? BorderSide(color: Config.getDividerColor(context))
                    : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Device Cooldown Timer
                    if (_timeLeft > Duration.zero) ...[
                      _buildStatusSection(
                        icon: Icons.timer_outlined,
                        color: Config.error,
                        title: 'Request Cooldown',
                        message:
                            'This device is currently blocked from sending new requests due to a recent account rejection.',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text('You can try again in:'),
                            const SizedBox(height: 8),
                            Text(
                              _formatDuration(_timeLeft),
                              style: TextStyle(
                                color: Colors.red[300],
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]
                    // Existing Request Status
                    else if (_requestStatus == 'pending') ...[
                      _buildStatusSection(
                        icon: Icons.hourglass_top,
                        color: Colors.blue,
                        title: 'Request Pending',
                        message: 'Your request is waiting for admin approval.',
                      ),
                    ] else if (_requestStatus == 'verified') ...[
                      _buildStatusSection(
                        icon: Icons.check_circle_outline,
                        color: Colors.green,
                        title: 'Account Verified',
                        message:
                            'Your account has been verified. You can now login with your credentials.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          DefaultTabController.of(context).index = 0;
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('GO TO LOGIN'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ] else ...[
                      _buildStatusSection(
                        icon: Icons.app_registration,
                        color: Config.primaryColor,
                        title: 'Request Access',
                        message:
                            'Please fill in your details below to request access.',
                      ),
                      const SizedBox(height: 32),
                      _buildFormFields(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
