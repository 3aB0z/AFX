// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../auth.dart';
import '../services/supabase_service.dart';
import 'dart:async';
import 'chat_page.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});
  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  late final TextEditingController emailCtrl;
  late final TextEditingController passwordCtrl;
  bool loading = false;
  bool _obscurePassword = true;

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    emailCtrl = TextEditingController();
    passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final data = await SupabaseService.login(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // Handle pending status
      if (data['status'] == 'pending') {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account request is pending approval'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Validate required fields
      final id = data['id'];
      final role = data['role'];
      final name = data['name'];

      if (id == null || role == null || name == null) {
        throw Exception('Server returned incomplete user data');
      }

      // Convert ID to int
      final intId = id is int ? id : int.parse(id.toString());
      final userEmail = data['email'] as String?;
      final token = data['token'] as String?;

      // Persist login
      await Auth.saveLogin({
        'id': intId,
        'role': role,
        'name': name,
        'email': userEmail ?? email, // fallback to login email if not provided
        if (token != null)
          'token': token, // Save JWT token if present (admin users)
      });

      // Navigate to chat
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            userId: intId,
            userName: name,
            userEmail: userEmail ?? email,
            userRole: role,
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Login timed out - Check internet and Supabase credentials',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);

      final errorMsg = e.toString();
      String displayMessage = errorMsg;

      // Parse specific auth errors
      if (errorMsg.contains('Invalid email or password')) {
        displayMessage = 'Invalid email or password';
      } else if (errorMsg.contains('Account not found')) {
        displayMessage = 'Account not found - Please create one first';
      } else if (errorMsg.contains('pending')) {
        displayMessage = 'Your account is pending approval';
      } else if (errorMsg.contains('rejected')) {
        displayMessage = 'Your account request was rejected';
      } else if (errorMsg.contains('Connection timeout')) {
        displayMessage = 'Connection timeout - Check your internet';
      } else if (errorMsg.contains('Connection refused')) {
        displayMessage = 'Cannot reach server - Check credentials';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Config.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            color: Config.background,
            shadowColor: Colors.black54,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/images/logo.png', height: 100),
                    const SizedBox(height: 16),
                    Text(
                      'Login',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Config.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'if you have a verified account',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Config.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
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
                          borderSide: BorderSide(
                            color: Config.primaryColor,
                            width: 1,
                          ),
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
                          borderSide: BorderSide(
                            color: Config.primaryColor,
                            width: 1,
                          ),
                        ),
                        filled: true,
                        fillColor: Config.background,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: Config.textQuaternary,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Config.textQuaternary,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => login(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: loading ? null : login,
                      style: FilledButton.styleFrom(
                        backgroundColor: Config.primaryColor,
                        disabledBackgroundColor: Config.borderSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: loading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Config.textLight,
                              ),
                            )
                          : Text(
                              'LOGIN',
                              style: TextStyle(color: Config.textLight),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Don\'t have a verified account?',
                      style: TextStyle(
                        fontSize: 12,
                        color: Config.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Create one and request access ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Config.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            alignment: Alignment.centerLeft,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            DefaultTabController.of(context).animateTo(1);
                          },
                          child: Text(
                            'here!',
                            style: TextStyle(
                              fontSize: 12,
                              color: Config.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
