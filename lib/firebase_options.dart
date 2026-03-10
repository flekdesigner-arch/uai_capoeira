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

  // 🔥 CONFIGURAÇÃO WEB (já está correta)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDfwrnXGru6o-ZcHPYRKot6I8UCpM_LC3I",
    authDomain: "uai-capoeira-52753.firebaseapp.com",
    projectId: "uai-capoeira-52753",
    storageBucket: "uai-capoeira-52753.firebasestorage.app",
    messagingSenderId: "570246579920",
    appId: "1:570246579920:web:3af5e719aed0caace480d5",
  );

  // ✅ ANDROID CORRIGIDO COM SEUS DADOS DO JSON!
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyD0UrFM1IMNtZS4p9NGHo9JurfMmfuYKIE", // ✅ API KEY CORRETA!
    appId: "1:570246579920:android:3c0d8f9405c5cdcde480d5", // ✅ APP ID CORRETO!
    messagingSenderId: "570246579920",
    projectId: "uai-capoeira-52753",
    storageBucket: "uai-capoeira-52753.firebasestorage.app",
  );

  // iOS (vc pode deixar assim por enquanto)
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "...",
    appId: "...",
    messagingSenderId: "...",
    projectId: "uai-capoeira-52753",
    storageBucket: "uai-capoeira-52753.firebasestorage.app",
    iosClientId: "...",
    iosBundleId: "...",
  );

  // macOS
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: "...",
    appId: "...",
    messagingSenderId: "...",
    projectId: "uai-capoeira-52753",
    storageBucket: "uai-capoeira-52753.firebasestorage.app",
    iosClientId: "...",
    iosBundleId: "...",
  );

  // Windows
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: "...",
    appId: "...",
    messagingSenderId: "...",
    projectId: "uai-capoeira-52753",
    storageBucket: "uai-capoeira-52753.firebasestorage.app",
  );
}