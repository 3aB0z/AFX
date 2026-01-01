// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/firebase_service.dart';
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
      final credential = await FirebaseService.login(email, password);

      if (!mounted || credential.user == null) return;

      // Fetch user details from Firestore
      var userData = await FirebaseService.getUserData(credential.user!.uid);

      if (userData == null) {
        throw Exception('User data not found in Firestore');
      }

      // Handle pending status
      if (userData['status'] == 'pending') {
        setState(() => loading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account request is pending approval'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Validate required fields
      final name = userData['name'];
      final role = userData['role'];

      if (name == null || role == null) {
        throw Exception('Incomplete user data in Firestore');
      }

      // Navigate to chat
      if (!mounted) return;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            userId: credential.user!.uid, // Now a String UID
            userName: name,
            userEmail: email,
            userRole: role,
          ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
                        color: Config.getTextColor(context, level: 3),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
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
                          borderSide: BorderSide(
                            color: Config.getDividerColor(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Config.getDividerColor(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Config.primaryColor,
                            width: 1,
                          ),
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
                      cursorColor: Config.primaryColor,
                      style: TextStyle(color: Config.getTextColor(context)),
                      decoration: InputDecoration(
                        hoverColor: Colors.transparent,
                        labelText: 'Password',
                        labelStyle: TextStyle(
                          color: Config.getTextColor(context, level: 3),
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Config.getDividerColor(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Config.getDividerColor(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Config.primaryColor,
                            width: 1,
                          ),
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
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Config.getTextColor(context, level: 3),
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
                        disabledBackgroundColor: Config.getDividerColor(
                          context,
                        ),
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
                        color: Config.getTextColor(context, level: 3),
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
                            color: Config.getTextColor(context, level: 3),
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
