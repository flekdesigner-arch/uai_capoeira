import 'dart:developer' as developer;
// lib/shared/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static void Function(Map<String, dynamic> data)? _navigationHandler;
  static Map<String, dynamic>? _pendingNavigationData;

  static void registerNavigationHandler(
    void Function(Map<String, dynamic> data) handler,
  ) {
    _navigationHandler = handler;
    final pending = _pendingNavigationData;
    if (pending != null) {
      _pendingNavigationData = null;
      Future.microtask(() => handler(pending));
    }
  }

  static void _dispatchNavigation(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final handler = _navigationHandler;
    if (handler != null) {
      handler(data);
    } else {
      _pendingNavigationData = Map<String, dynamic>.from(data);
    }
  }

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

  bool get _supportsFirebaseMessaging {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _supportsLocalNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR NOTIFICAÇÕES
  // ═══════════════════════════════════════════════════════════
  Future<void> initNotifications() async {
    if (!_supportsFirebaseMessaging) {
      developer.log(
        'Firebase Messaging ignorado nesta plataforma: $defaultTargetPlatform',
      );
      return;
    }

    if (Firebase.apps.isEmpty) {
      developer.log('⚠️ Firebase não inicializado. Aguardando...');
      try {
        await Firebase.initializeApp();
        developer.log('✅ Firebase inicializado pelo NotificationService');
      } catch (e) {
        developer.log('❌ Erro ao inicializar Firebase no NotificationService: $e');
        return;
      }
    }

    if (_isInitialized) {
      developer.log('🔔 Notificações já inicializadas');
      await syncTokenForCurrentUser();
      return;
    }

    if (_isRequestingPermission) {
      developer.log('🔔 Solicitação de permissão já em andamento');
      return;
    }

    try {
      _isRequestingPermission = true;
      developer.log('🔔 Inicializando notificações...');

      await _initializeLocalNotifications();

      final NotificationSettings perm = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      developer.log('🔔 Status da permissão: ${perm.authorizationStatus}');

      if (_isPermissionAllowed(perm.authorizationStatus)) {
        final String? token = await _getTokenForCurrentPlatform();
        developer.log('🔔 Token FCM gerado (${kIsWeb ? 'PWA/Web' : 'App'}): $token');

        if (token != null && token.trim().isNotEmpty) {
          await _saveTokenCleaningOld(token);
        } else {
          developer.log('⚠️ Token FCM retornou nulo/vazio.');
        }

        // No Web/PWA, o foco agora é envio por token salvo no Firestore.
        // Tópicos no Web podem atrapalhar o diagnóstico e não são necessários
        // para a função de aniversário nem para o futuro módulo manual.
        if (!kIsWeb) {
          await _fcm.subscribeToTopic('all_users');
          developer.log('🔔 Inscrito no tópico all_users');
        } else {
          developer.log('🌐 PWA/Web: envio será por token, sem inscrição em tópico.');
        }
      } else {
        developer.log('⚠️ Permissão de notificação negada pelo usuário.');
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        developer.log(
          '📨 Notificação recebida em primeiro plano: ${message.messageId}',
        );
        developer.log('📨 Título: ${message.notification?.title}');
        developer.log('📨 Corpo: ${message.notification?.body}');
        developer.log('📨 Data: ${message.data}');

        _showLocalNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        developer.log('🖱️ Notificação clicada: ${message.messageId}');
        developer.log('🖱️ Data: ${message.data}');
        _dispatchNavigation(message.data);
      });

      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        developer.log('🚀 App aberto por notificação: ${initialMessage.messageId}');
        developer.log('🚀 Data: ${initialMessage.data}');
        _dispatchNavigation(initialMessage.data);
      }

      _tokenRefreshStream ??= _fcm.onTokenRefresh;
      _tokenRefreshStream!.listen((String newToken) async {
        developer.log('🔄 Token FCM atualizado: $newToken');
        await _saveTokenCleaningOld(newToken);
      });

      _isInitialized = true;
      developer.log('✅ Notificações inicializadas com sucesso!');
    } catch (e) {
      developer.log('❌ Erro ao inicializar notificações: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR NOTIFICAÇÕES LOCAIS
  // ═══════════════════════════════════════════════════════════
  Future<void> _initializeLocalNotifications() async {
    if (!_supportsLocalNotifications) {
      developer.log(
        'flutter_local_notifications ignorado nesta plataforma: $defaultTargetPlatform',
      );
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        developer.log('🖱️ Notificação local clicada: ${response.payload}');
        if (response.payload == 'gerenciar_inscricoes') {
          _dispatchNavigation(const {'rota': 'gerenciar_inscricoes'});
        }
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

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
    if (!_supportsFirebaseMessaging) {
      developer.log('Token FCM nao suportado nesta plataforma: $defaultTargetPlatform');
      return null;
    }

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
      if (!_supportsFirebaseMessaging) {
        developer.log(
          'Sincronizacao de token FCM ignorada nesta plataforma: $defaultTargetPlatform',
        );
        return;
      }

      if (Firebase.apps.isEmpty) {
        developer.log(
          '⚠️ Firebase ainda não inicializado. Não dá para sincronizar token.',
        );
        return;
      }

      final User? user = _auth.currentUser;

      if (user == null) {
        developer.log('⚠️ Não dá para sincronizar token: usuário não logado.');
        return;
      }

      final NotificationSettings settings = await _fcm
          .getNotificationSettings();
      developer.log(
        '🔔 Permissão atual para sincronizar: ${settings.authorizationStatus}',
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        developer.log('⚠️ Permissão negada. Token não será sincronizado.');
        return;
      }

      if (!_isPermissionAllowed(settings.authorizationStatus)) {
        final NotificationSettings perm = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        developer.log(
          '🔔 Permissão solicitada ao sincronizar: ${perm.authorizationStatus}',
        );

        if (!_isPermissionAllowed(perm.authorizationStatus)) {
          developer.log('⚠️ Usuário não autorizou notificações.');
          return;
        }
      }

      final String? token = await _getTokenForCurrentPlatform();

      if (token == null || token.trim().isEmpty) {
        developer.log('⚠️ FCM token veio nulo/vazio ao sincronizar.');
        return;
      }

      await _saveTokenCleaningOld(token);
      developer.log('✅ Token sincronizado manualmente para ${user.email}');
    } catch (e) {
      developer.log('❌ Erro ao sincronizar token: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SALVAR TOKEN – MANTÉM SÓ O TOKEN ATUAL
  // ═══════════════════════════════════════════════════════════
  Future<void> _saveTokenCleaningOld(String token) async {
    try {
      final User? user = _auth.currentUser;

      if (user == null) {
        developer.log('⚠️ Usuário ainda não está logado. Token não foi salvo agora.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef = _firestore
          .collection('usuarios')
          .doc(user.uid);

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

      developer.log(
        '✅ Token atual salvo e tokens antigos substituídos para: ${user.email}',
      );
    } catch (e) {
      developer.log('❌ Erro ao salvar token no Firestore: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REMOVER TOKEN NO LOGOUT
  // ═══════════════════════════════════════════════════════════
  Future<void> removeToken() async {
    try {
      if (!_supportsFirebaseMessaging) {
        developer.log(
          'Remocao de token FCM ignorada nesta plataforma: $defaultTargetPlatform',
        );
        return;
      }

      final User? user = _auth.currentUser;
      if (user == null) {
        developer.log('⚠️ Nenhum usuário logado para remover token.');
        return;
      }

      final String? token = await _getTokenForCurrentPlatform();
      if (token == null || token.trim().isEmpty) {
        developer.log('⚠️ Token atual veio nulo/vazio no logout.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef = _firestore
          .collection('usuarios')
          .doc(user.uid);

      final docSnapshot = await userRef.get();

      if (docSnapshot.exists) {
        await userRef.set({
          'fcm_tokens': FieldValue.arrayRemove([token]),
          'current_fcm_token': FieldValue.delete(),
          'ultimo_token_removido': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        developer.log('✅ Token removido do Firestore para: ${user.email}');
      }
    } catch (e) {
      developer.log('❌ Erro ao remover token: $e');
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
        developer.log('⚠️ Nenhum usuário logado para remover todos os tokens.');
        return;
      }

      final DocumentReference<Map<String, dynamic>> userRef = _firestore
          .collection('usuarios')
          .doc(user.uid);

      final docSnapshot = await userRef.get();

      if (docSnapshot.exists) {
        await userRef.set({
          'fcm_tokens': FieldValue.delete(),
          'current_fcm_token': FieldValue.delete(),
          'ultimo_token_removido': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        developer.log('✅ Todos os campos de token removidos para: ${user.email}');
      }
    } catch (e) {
      developer.log('❌ Erro ao remover todos os tokens: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // NOTIFICAÇÃO LOCAL DE TESTE
  // ═══════════════════════════════════════════════════════════
  Future<void> testLocalNotification() async {
    if (!_supportsLocalNotifications) {
      developer.log('Teste local ignorado nesta plataforma: $defaultTargetPlatform');
      return;
    }

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
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

      developer.log('✅ Notificação local de teste enviada!');
    } catch (e) {
      developer.log('❌ Erro ao enviar notificação de teste: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // MOSTRAR NOTIFICAÇÃO LOCAL QUANDO APP ESTÁ ABERTO
  // ═══════════════════════════════════════════════════════════
  String _resolvedTitle(RemoteMessage message) {
    final data = message.data;
    final direct = message.notification?.title?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final key in const ['title', 'titulo']) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    switch (data['tipo']?.toString()) {
      case 'nova_inscricao':
        return 'Nova inscrição pendente';
      case 'lembrete_aula_experimental':
        return 'Sua aula experimental é hoje';
      case 'nova_versao':
      case 'atualizacao_app':
        return 'Nova versão disponível';
      case 'aniversario':
        return 'Aniversariante do dia';
      default:
        return 'UAI Capoeira';
    }
  }

  String _resolvedBody(RemoteMessage message) {
    final data = message.data;
    final direct = message.notification?.body?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final key in const ['body', 'mensagem', 'message']) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    switch (data['tipo']?.toString()) {
      case 'nova_inscricao':
        return 'Uma nova inscrição foi recebida. Toque para analisar.';
      case 'lembrete_aula_experimental':
        return 'Você tem uma aula experimental agendada para hoje.';
      case 'nova_versao':
      case 'atualizacao_app':
        return 'Há uma nova versão do UAI Capoeira disponível.';
      case 'aniversario':
        return 'Hoje temos aniversariante no UAI Capoeira.';
      default:
        return 'Você recebeu um novo aviso do UAI Capoeira.';
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!_supportsLocalNotifications) {
      developer.log('🌐 PWA/Web recebeu foreground message.');
      developer.log(
        '🌐 Título: ${message.notification?.title ?? message.data['title']}',
      );
      developer.log('🌐 Corpo: ${message.notification?.body ?? message.data['body']}');
      return;
    }

    try {
      final isNovaInscricao =
          message.data['tipo']?.toString() == 'nova_inscricao';
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'default_channel',
            'Notificações UAI',
            channelDescription: 'Canal para notificações do app UAI Capoeira',
            importance: Importance.high,
            priority: Priority.high,
            icon: isNovaInscricao
                ? '@drawable/ic_notification_inscricao'
                : '@drawable/ic_notification',
            enableLights: true,
            enableVibration: true,
            playSound: true,
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        _resolvedTitle(message),
        _resolvedBody(message),
        details,
        payload: message.data['rota']?.toString(),
      );

      developer.log('✅ Notificação local exibida com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao mostrar notificação local: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UTILITÁRIOS
  // ═══════════════════════════════════════════════════════════
  Future<String?> getToken() async {
    try {
      final String? token = await _getTokenForCurrentPlatform();
      developer.log(
        '🔔 Token atual consultado (${kIsWeb ? 'PWA/Web' : 'App'}): $token',
      );
      return token;
    } catch (e) {
      developer.log('❌ Erro ao obter token: $e');
      return null;
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (!_supportsFirebaseMessaging || kIsWeb) {
      developer.log('Inscricao em topico ignorada para $topic nesta plataforma.');
      return;
    }

    try {
      await _fcm.subscribeToTopic(topic);
      developer.log('✅ Inscrito no tópico: $topic');
    } catch (e) {
      developer.log('❌ Erro ao inscrever no tópico $topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_supportsFirebaseMessaging || kIsWeb) {
      developer.log('Remocao de topico ignorada para $topic nesta plataforma.');
      return;
    }

    try {
      await _fcm.unsubscribeFromTopic(topic);
      developer.log('✅ Cancelada inscrição no tópico: $topic');
    } catch (e) {
      developer.log('❌ Erro ao cancelar inscrição no tópico $topic: $e');
    }
  }
}
