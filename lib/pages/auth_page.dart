// lib/pages/auth_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import 'login_page.dart';
import 'request_page.dart';

class AuthPage extends StatelessWidget {
  final int initialIndex;
  const AuthPage({this.initialIndex = 0, super.key}) : super();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Config.primaryColor,
            statusBarBrightness: Theme.of(context).brightness,
            statusBarIconBrightness:
                Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
          toolbarHeight: 0,
          bottom: TabBar(
            labelColor: Config.primaryColor,
            indicatorColor: Config.primaryColor,
            unselectedLabelColor: Config.getTextColor(context, level: 3),
            dividerColor: Theme.of(context).dividerColor,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.login),
                    const SizedBox(width: 8),
                    Text(
                      'Login',
                      style: TextStyle(
                        color: Config.getTextColor(context, level: 2),
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add),
                    const SizedBox(width: 8),
                    Text(
                      'Request Access',
                      style: TextStyle(
                        color: Config.getTextColor(context, level: 2),
                      ),
                    ),
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
