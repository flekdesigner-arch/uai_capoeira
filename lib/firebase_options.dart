// lib/firebase_options.dart
//
// =====================================================
// 🔥 FIREBASE OPTIONS - UAI CAPOEIRA
// =====================================================
//
// Correção importante:
// O Windows Desktop NÃO pode ficar com FirebaseOptions usando "..."
// porque isso inicializa Firebase com configuração inválida.
// Para Windows, usamos a configuração do App Web do Firebase,
// que é compatível para inicialização do Firebase no desktop.
//
// Android continua usando o google-services.json correto.
// PWA/Web continua usando a configuração web.
// =====================================================

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
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // =====================================================
  // 🌐 WEB / PWA
  // =====================================================
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I',
    authDomain: 'uai-capoeira-52753.firebaseapp.com',
    projectId: 'uai-capoeira-52753',
    storageBucket: 'uai-capoeira-52753.firebasestorage.app',
    messagingSenderId: '570246579920',
    appId: '1:570246579920:web:3af5e719aed0caace480d5',
  );

  // =====================================================
  // 🤖 ANDROID / APK
  // =====================================================
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD0UrFM1IMNtZS4p9NGHo9JurfMmfuYKIE',
    appId: '1:570246579920:android:3c0d8f9405c5cdcde480d5',
    messagingSenderId: '570246579920',
    projectId: 'uai-capoeira-52753',
    storageBucket: 'uai-capoeira-52753.firebasestorage.app',
  );

  // =====================================================
  // 🍎 IOS
  // =====================================================
  // Mantido como fallback. Configure pelo FlutterFire CLI se for usar iOS.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I',
    appId: '1:570246579920:web:3af5e719aed0caace480d5',
    messagingSenderId: '570246579920',
    projectId: 'uai-capoeira-52753',
    storageBucket: 'uai-capoeira-52753.firebasestorage.app',
    iosBundleId: 'com.uai.capoeira.uaiCapoeira',
  );

  // =====================================================
  // 🍎 MACOS
  // =====================================================
  // Mantido como fallback. Configure pelo FlutterFire CLI se for usar macOS.
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I',
    appId: '1:570246579920:web:3af5e719aed0caace480d5',
    messagingSenderId: '570246579920',
    projectId: 'uai-capoeira-52753',
    storageBucket: 'uai-capoeira-52753.firebasestorage.app',
    iosBundleId: 'com.uai.capoeira.uaiCapoeira',
  );

  // =====================================================
  // 🖥️ WINDOWS DESKTOP
  // =====================================================
  // IMPORTANTE:
  // Antes estava com "...", isso quebra a inicialização real do Firebase
  // no Windows e pode deixar Firestore/Auth/Storage instáveis/offline.
  //
  // No desktop Windows, usamos a configuração WEB do Firebase.
  // Isso é suficiente para conectar no projeto:
  // uai-capoeira-52753
  // =====================================================
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I',
    authDomain: 'uai-capoeira-52753.firebaseapp.com',
    projectId: 'uai-capoeira-52753',
    storageBucket: 'uai-capoeira-52753.firebasestorage.app',
    messagingSenderId: '570246579920',
    appId: '1:570246579920:web:3af5e719aed0caace480d5',
  );
}
