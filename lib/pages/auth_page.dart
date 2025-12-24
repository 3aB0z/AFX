// lib/pages/auth_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import 'login_page.dart';
import 'request_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key}) : super();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.grey[100],
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Config.primaryColor,
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.light,
          ),
          toolbarHeight: 0,
          bottom: const TabBar(
            labelColor: Config.primaryColor,
            indicatorColor: Config.primaryColor,
            unselectedLabelColor: Config.textTertiary,
            dividerColor: Config.divider,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login),
                    SizedBox(width: 8),
                    Text('Login'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add),
                    SizedBox(width: 8),
                    Text('Request Access'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: const TabBarView(children: [LoginForm(), RequestPage()]),
      ),
    );
  }
}
