// lib/pages/request_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/supabase_service.dart';
import '../auth.dart';
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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _requestStatus;
  String? _requestMessage;
  bool get _hasExistingRequest => _requestStatus == 'pending';

  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
    _checkLoginStatus();
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
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final loginData = await Auth.getLogin();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = loginData != null;
    });
  }

  Future<void> _checkExistingRequest() async {
    try {
      final email = emailCtrl.text.trim();
      if (email.isEmpty) return;

      final exists = await SupabaseService.checkRequestStatus(email);
      if (!mounted) return;
      setState(() {
        _requestStatus = exists ? 'pending' : null;
      });
    } catch (e) {
      debugPrint('Error checking existing request: $e');
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
      final response = await SupabaseService.sendRequest(
        name: nameCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        password: passwordCtrl.text,
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
        SnackBar(
          content: Text(response['message'] ?? 'Request sent successfully'),
          duration: const Duration(seconds: 2),
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
            color: color == Colors.red ? color : Config.textTertiary,
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
          cursorColor: Config.primaryColor,
          decoration: InputDecoration(
            hoverColor: Config.background,
            labelText: 'Full Name',
            labelStyle: TextStyle(color: Config.textQuaternary),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.background,
            prefixIcon: Icon(
              Icons.person_outline,
              color: Config.textQuaternary,
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
          cursorColor: Config.primaryColor,
          decoration: InputDecoration(
            hoverColor: Config.background,
            labelText: 'Email',
            labelStyle: TextStyle(color: Config.textQuaternary),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.background,
            prefixIcon: Icon(
              Icons.email_outlined,
              color: Config.textQuaternary,
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
          cursorColor: Config.primaryColor,
          decoration: InputDecoration(
            hoverColor: Config.background,
            labelText: 'Password',
            labelStyle: TextStyle(color: Config.textQuaternary),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.background,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: Icon(Icons.lock_outline, color: Config.textQuaternary),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Config.textQuaternary,
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
          cursorColor: Config.primaryColor,
          decoration: InputDecoration(
            hoverColor: Config.background,
            labelText: 'Confirm Password',
            labelStyle: TextStyle(color: Config.textQuaternary),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.borderSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Config.primaryColor, width: 1),
            ),
            filled: true,
            fillColor: Config.background,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            prefixIcon: Icon(Icons.lock_outline, color: Config.textQuaternary),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility
                    : Icons.visibility_off,
                color: Config.textQuaternary,
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
            disabledBackgroundColor: Config.borderSecondary,
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
                        color: Config.textLight,
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
    // Hide completely when verified and logged in
    if (_requestStatus == 'verified' && _isLoggedIn) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Config.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: Config.background,
              shadowColor: Colors.black54,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Status Icon and Message
                    if (_requestStatus == 'pending') ...[
                      _buildStatusSection(
                        icon: Icons.hourglass_top,
                        color: Colors.orange,
                        title: 'Request Pending',
                        message: 'Your request is waiting for admin approval.',
                      ),
                    ] else if (_requestStatus == 'rejected' &&
                        !_isLoggedIn) ...[
                      _buildStatusSection(
                        icon: Icons.error_outline,
                        color: Colors.red,
                        title: 'Previous Request Rejected',
                        message:
                            _requestMessage ??
                            'Your previous request was rejected. You can submit a new request below.',
                      ),
                      const SizedBox(height: 32),
                      _buildFormFields(),
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
