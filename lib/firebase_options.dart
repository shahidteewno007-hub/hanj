// File generated manually based on Firebase project configuration.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
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
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAn3syfknc5Z5DHhCDBZApog6GVgTgva3g',
    authDomain: 'anime-tracker-275cc.firebaseapp.com',
    projectId: 'anime-tracker-275cc',
    storageBucket: 'anime-tracker-275cc.firebasestorage.app',
    messagingSenderId: '572595796065',
    appId: '1:572595796065:web:83130c14d521f706fd5220',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBi_acyTQLUHLj4xvhjuBPlUZZZazXQY1U',
    authDomain: 'anime-tracker-275cc.firebaseapp.com',
    projectId: 'anime-tracker-275cc',
    storageBucket: 'anime-tracker-275cc.firebasestorage.app',
    messagingSenderId: '572595796065',
    appId: '1:572595796065:android:0e7db48b66c03266fd5220',
  );

  // iOS can be added later when needed
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBi_acyTQLUHLj4xvhjuBPlUZZZazXQY1U',
    authDomain: 'anime-tracker-275cc.firebaseapp.com',
    projectId: 'anime-tracker-275cc',
    storageBucket: 'anime-tracker-275cc.firebasestorage.app',
    messagingSenderId: '572595796065',
    appId: '1:572595796065:android:0e7db48b66c03266fd5220',
  );
}
