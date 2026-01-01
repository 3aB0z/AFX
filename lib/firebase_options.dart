import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB0U6qRL0s0IqPR9qyea2YJQnsUsVVnKjU',
    appId: '1:451371205080:web:aa6563725ffafd551d72ad',
    messagingSenderId: '451371205080',
    projectId: 'afx-chat-app',
    authDomain: 'afx-chat-app.firebaseapp.com',
    storageBucket: 'afx-chat-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB0U6qRL0s0IqPR9qyea2YJQnsUsVVnKjU',
    appId: '1:451371205080:android:aa6563725ffafd551d72ad',
    messagingSenderId: '451371205080',
    projectId: 'afx-chat-app',
    storageBucket: 'afx-chat-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB0U6qRL0s0IqPR9qyea2YJQnsUsVVnKjU',
    appId: '1:451371205080:ios:aa6563725ffafd551d72ad',
    messagingSenderId: '451371205080',
    projectId: 'afx-chat-app',
    storageBucket: 'afx-chat-app.firebasestorage.app',
    iosBundleId: 'com.android.application',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB0U6qRL0s0IqPR9qyea2YJQnsUsVVnKjU',
    appId: '1:451371205080:ios:aa6563725ffafd551d72ad',
    messagingSenderId: '451371205080',
    projectId: 'afx-chat-app',
    storageBucket: 'afx-chat-app.firebasestorage.app',
    iosBundleId: 'com.android.application',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyB0U6qRL0s0IqPR9qyea2YJQnsUsVVnKjU',
    appId: '1:451371205080:android:aa6563725ffafd551d72ad',
    messagingSenderId: '451371205080',
    projectId: 'afx-chat-app',
    authDomain: 'afx-chat-app.firebaseapp.com',
    storageBucket: 'afx-chat-app.firebasestorage.app',
  );
}
