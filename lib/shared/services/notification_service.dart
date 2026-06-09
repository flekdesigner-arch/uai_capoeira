// lib/shared/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  // =====================================================
  // 🔐 CHAVE PÚBLICA VAPID - WEB/PWA
  // =====================================================
  // Firebase Console > Configurações do projeto > Cloud Messaging
  // > Configuração da Web > Certificados push da Web > Chave pública.
  static const String _webVapidKey =
      'BBY2BjsT27eaHO_flTngBcSKzbty_jDgcJpfLs7hgLYF_gdgdqm_hJU_rNRYuWbLfO9SF4TObf8jx59a1pHr8OY';

  // ✅ GETTERS LAZY – SÓ ACESSADOS QUANDO FIREBASE ESTIVER PRONTO
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  // ✅ CONTROLE DE ESTADO
  bool _isInitialized = false;
  bool _isRequestingPermission = false;
  Stream<String>? _tokenRefreshStream;

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR NOTIFICAÇÕES
  // ═══════════════════════════════════════════════════════════
  Future<void> initNotifications() async {
    if (Firebase.apps.isEmpty) {
      print('⚠️ Firebase não inicializado. Aguardando...');
      try {
        await Firebase.initializeApp();
        print('✅ Firebase inicializado pelo NotificationService');
      } catch (e) {
        print('❌ Erro ao inicializar Firebase no NotificationService: $e');
        return;
      }
    }

    if (_isInitialized) {
      print('🔔 Notificações já inicializadas');
      await syncTokenForCurrentUser();
      return;
    }

    if (_isRequestingPermission) {
      print('🔔 Solicitação de permissão já em andamento');
      return;
    }

    try {
      _isRequestingPermission = true;
      print('🔔 Inicializando notificações...');

      await _initializeLocalNotifications();

      final NotificationSettings perm = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('🔔 Status da permissão: ${perm.authorizationStatus}');

      if (_isPermissionAllowed(perm.authorizationStatus)) {
        final String? token = await _getTokenForCurrentPlatform();
        print('🔔 Token FCM gerado (${kIsWeb ? 'PWA/Web' : 'App'}): $token');

        if (token != null && token.trim().isNotEmpty) {
          await _saveTokenCleaningOld(token);
        } else {
          print('⚠️ Token FCM retornou nulo/vazio.');
        }

        // No Web/PWA, o foco agora é envio por token salvo no Firestore.
        // Tópicos no Web podem atrapalhar o diagnóstico e não são necessários
        // para a função de aniversário nem para o futuro módulo manual.
        if (!kIsWeb) {
          await _fcm.subscribeToTopic('all_users');
          print('🔔 Inscrito no tópico all_users');
        } else {
          print('🌐 PWA/Web: envio será por token, sem inscrição em tópico.');
        }
      } else {
        print('⚠️ Permissão de notificação negada pelo usuário.');
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Notificação recebida em primeiro plano: ${message.messageId}');
        print('📨 Título: ${message.notification?.title}');
        print('📨 Corpo: ${message.notification?.body}');
        print('📨 Data: ${message.data}');

        _showLocalNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🖱️ Notificação clicada: ${message.messageId}');
        print('🖱️ Data: ${message.data}');
      });

      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        print('🚀 App aberto por notificação: ${initialMessage.messageId}');
        print('🚀 Data: ${initialMessage.data}');
      }

      _tokenRefreshStream ??= _fcm.onTokenRefresh;
      _tokenRefreshStream!.listen((String newToken) async {
        print('🔄 Token FCM atualizado: $newToken');
        await _saveTokenCleaningOld(newToken);
      });

      _isInitialized = true;
      print('✅ Notificações inicializadas com sucesso!');
    } catch (e) {
      print('❌ Erro ao inicializar notificações: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR NOTIFICAÇÕES LOCAIS
  // ═══════════════════════════════════════════════════════════
  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) {
      print('🌐 PWA/Web: pulando inicialização de flutter_local_notifications.');
      return;
    }

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('🖱️ Notificação local clicada: ${response.payload}');
      },
    );

    final androidPlugin =
    _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();
  }

  bool _isPermissionAllowed(AuthorizationStatus status) {
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }

  // ═══════════════════════════════════════════════════════════
  // PEGAR TOKEN CORRETO POR PLATAFORMA
  // ═══════════════════════════════════════════════════════════
  Future<String?> _getTokenForCurrentPlatform() async {
    if (kIsWeb) {
      return _fcm.getToken(vapidKey: _webVapidKey);
    }

    return _fcm.getToken();
  }

  // ═══════════════════════════════════════════════════════════
  // SINCRONIZAR TOKEN DO USUÁRIO ATUAL
  // ═══════════════════════════════════════════════════════════
  Future<void> syncTokenForCurrentUser() async {
    try {
      if (Firebase.apps.isEmpty) {
        print('⚠️ Firebase ainda não inicializado. Não dá para sincronizar token.');
        return;
      }

      final User? user = _auth.currentUser;

      if (user == null) {
        print('⚠️ Não dá para sincronizar token: usuário não logado.');
        return;
      }

      final NotificationSettings settings = await _fcm.getNotificationSettings();
      print('🔔 Permissão atual para sincronizar: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('⚠️ Permissão negada. Token não será sincronizado.');
        return;
      }

      if (!_isPermissionAllowed(settings.authorizationStatus)) {
        final NotificationSettings perm = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        print('🔔 Permissão solicitada ao sincronizar: ${perm.authorizationStatus}');

        if (!_isPermissionAllowed(perm.authorizationStatus)) {
          print('⚠️ Usuário não autorizou notificações.');
          return;
        }
      }

      final String? token = await _getTokenForCurrentPlatform();

      if (token == null || token.trim().isEmpty) {
        print('⚠️ FCM token veio nulo/vazio ao sincronizar.');
        return;
      }

      await _saveTokenCleaningOld(token);
      print('✅ Token sincronizado manualmente para ${user.email}');
    } catch (e) {
      print('❌ Erro ao sincronizar token: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SALVAR TOKEN – MANTÉM SÓ O TOKEN ATUAL
  // ═══════════════════════════════════════════════════════════
  Future<void> _saveTokenCleaningOld(String token) async {
    try {
      final User? user = _auth.currentUser;

      if (user == null) {
        print('⚠️ Usuário ainda não está logado. Token não foi salvo agora.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef =
      _firestore.collection('usuarios').doc(user.uid);

      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'fcm_tokens': [token],
        'current_fcm_token': token,
        'ultimo_token_atualizado': FieldValue.serverTimestamp(),
        'plataforma_token': kIsWeb ? 'web' : 'app',
        'token_origem': kIsWeb ? 'pwa_web' : 'android_app',
        'token_versao_service': 2,
      }, SetOptions(merge: true));

      print('✅ Token atual salvo e tokens antigos substituídos para: ${user.email}');
    } catch (e) {
      print('❌ Erro ao salvar token no Firestore: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REMOVER TOKEN NO LOGOUT
  // ═══════════════════════════════════════════════════════════
  Future<void> removeToken() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        print('⚠️ Nenhum usuário logado para remover token.');
        return;
      }

      final String? token = await _getTokenForCurrentPlatform();
      if (token == null || token.trim().isEmpty) {
        print('⚠️ Token atual veio nulo/vazio no logout.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef =
      _firestore.collection('usuarios').doc(user.uid);

      final docSnapshot = await userRef.get();

      if (docSnapshot.exists) {
        await userRef.set({
          'fcm_tokens': FieldValue.arrayRemove([token]),
          'current_fcm_token': FieldValue.delete(),
          'ultimo_token_removido': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print('✅ Token removido do Firestore para: ${user.email}');
      }
    } catch (e) {
      print('❌ Erro ao remover token: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REMOVER TODOS OS TOKENS
  // Use só para limpeza manual/debug, não no fluxo normal.
  // ═══════════════════════════════════════════════════════════
  Future<void> removeAllTokens() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        print('⚠️ Nenhum usuário logado para remover todos os tokens.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef =
      _firestore.collection('usuarios').doc(user.uid);

      final docSnapshot = await userRef.get();

      if (docSnapshot.exists) {
        await userRef.set({
          'fcm_tokens': FieldValue.delete(),
          'current_fcm_token': FieldValue.delete(),
          'ultimo_token_removido': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print('✅ Todos os campos de token removidos para: ${user.email}');
      }
    } catch (e) {
      print('❌ Erro ao remover todos os tokens: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // NOTIFICAÇÃO LOCAL DE TESTE
  // ═══════════════════════════════════════════════════════════
  Future<void> testLocalNotification() async {
    if (kIsWeb) {
      print('🌐 PWA/Web: teste local via flutter_local_notifications não será usado.');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'test_channel',
        'Canal de Teste',
        channelDescription: 'Canal para testes locais de notificação',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableLights: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '🎉 Teste de Notificação',
        'Se você está vendo isso, as notificações locais estão funcionando!',
        details,
        payload: 'teste_local',
      );

      print('✅ Notificação local de teste enviada!');
    } catch (e) {
      print('❌ Erro ao enviar notificação de teste: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // MOSTRAR NOTIFICAÇÃO LOCAL QUANDO APP ESTÁ ABERTO
  // ═══════════════════════════════════════════════════════════
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) {
      print('🌐 PWA/Web recebeu foreground message.');
      print('🌐 Título: ${message.notification?.title ?? message.data['title']}');
      print('🌐 Corpo: ${message.notification?.body ?? message.data['body']}');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'default_channel',
        'Notificações UAI',
        channelDescription: 'Canal para notificações do app UAI Capoeira',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableLights: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        message.notification?.title ?? 'UAI CAPOEIRA',
        message.notification?.body ?? 'Você tem uma nova notificação',
        details,
        payload: message.data.toString(),
      );

      print('✅ Notificação local exibida com sucesso');
    } catch (e) {
      print('❌ Erro ao mostrar notificação local: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UTILITÁRIOS
  // ═══════════════════════════════════════════════════════════
  Future<String?> getToken() async {
    try {
      final String? token = await _getTokenForCurrentPlatform();
      print('🔔 Token atual consultado (${kIsWeb ? 'PWA/Web' : 'App'}): $token');
      return token;
    } catch (e) {
      print('❌ Erro ao obter token: $e');
      return null;
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      print('🌐 PWA/Web: inscrição em tópico ignorada para $topic.');
      return;
    }

    try {
      await _fcm.subscribeToTopic(topic);
      print('✅ Inscrito no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao inscrever no tópico $topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      print('🌐 PWA/Web: remoção de tópico ignorada para $topic.');
      return;
    }

    try {
      await _fcm.unsubscribeFromTopic(topic);
      print('✅ Cancelada inscrição no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao cancelar inscrição no tópico $topic: $e');
    }
  }
}
