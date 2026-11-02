import 'dart:developer' as developer;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'birthday_inbox_notification.dart';
import 'package:path_provider/path_provider.dart';
// lib/shared/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uai_capoeira/core/services/update_wifi_push_dispatcher.dart';
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
  static const String _defaultChannelId = 'uai_default_channel_v2';
  static const String _birthdayChannelId = 'uai_birthday_channel_v2';
  static const String _inscricaoChannelId = 'uai_inscricao_channel_v2';

  bool _isRequestingPermission = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;


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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _subscribeUpdateSignals();
      }
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

      // A autorização para exibir notificações é diferente do consentimento
      // para baixar APK pelo Wi-Fi. FCM data-only precisa estar inscrito
      // mesmo quando o usuário recusou avisos visuais do Android 13+.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _subscribeUpdateSignals();
      }

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

      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        developer.log(
          '📨 Notificação recebida em primeiro plano: ${message.messageId}',
        );
        developer.log('📨 Título: ${message.notification?.title}');
        developer.log('📨 Corpo: ${message.notification?.body}');
        developer.log('📨 Data: ${message.data}');

        if (message.data['tipo'] == 'uai_update_check') {
          dispatchWifiUpdateSignal(message.data);
        } else {
          _showLocalNotification(message);
        }
      });

      _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
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

      _tokenRefreshSubscription ??= _fcm.onTokenRefresh.listen((String newToken) async {
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

  Future<void> _subscribeUpdateSignals() async {
    try {
      await _fcm.subscribeToTopic('uai_updates_push_v183');
      developer.log('Smart Update: sinal técnico inscrito (sem depender da permissão visual).');
    } catch (e) {
      // WorkManager periódico permanece ativo como alternativa.
      developer.log('Smart Update: falha ao inscrever sinal técnico: $e');
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
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _dispatchNavigation(Map<String, dynamic>.from(decoded));
            return;
          }
        } catch (_) {
          // Compatibilidade com notificações locais antigas (payload = rota).
        }
        _dispatchNavigation({'rota': payload});
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.requestNotificationsPermission();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _defaultChannelId,
        'Notificações UAI',
        description: 'Canal geral de notificações do UAI Capoeira',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _birthdayChannelId,
        'Aniversariantes UAI',
        description: 'Canal premium para aniversariantes do UAI Capoeira',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _inscricaoChannelId,
        'Inscrições UAI',
        description: 'Canal de inscrições pendentes do UAI Capoeira',
        importance: Importance.high,
      ),
    );

    // Ao iniciar pelo toque numa notificação local (app encerrado),
    // o payload precisa seguir o mesmo roteador usado pelo FCM.
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _dispatchNavigation(Map<String, dynamic>.from(decoded));
          } else {
            _dispatchNavigation({'rota': payload});
          }
        } catch (_) {
          _dispatchNavigation({'rota': payload});
        }
      }
    }
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
        'fcm_tokens': FieldValue.arrayUnion([token]),
        'current_fcm_token': token,
        'ultimo_token_atualizado': FieldValue.serverTimestamp(),
        'plataforma_token': kIsWeb ? 'web' : 'app',
        'token_origem': kIsWeb ? 'pwa_web' : 'android_app',
        'token_versao_service': 2,
      }, SetOptions(merge: true));

      developer.log('✅ Token do dispositivo preservado para: ${user.email}');
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

      await _firestore.runTransaction((tx) async {
        final snapshot = await tx.get(userRef);
        if (!snapshot.exists) return;
        final current = snapshot.data()?['current_fcm_token']?.toString();
        tx.set(userRef, {
          'fcm_tokens': FieldValue.arrayRemove([token]),
          if (current == token) 'current_fcm_token': FieldValue.delete(),
          'ultimo_token_removido': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      developer.log('✅ Token deste dispositivo removido: ${user.email}');
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

  String _channelIdForMessage(RemoteMessage message) {
    switch (message.data['tipo']?.toString()) {
      case 'aniversario':
        return _birthdayChannelId;
      case 'nova_inscricao':
        return _inscricaoChannelId;
      default:
        return _defaultChannelId;
    }
  }

  String _channelNameForMessage(RemoteMessage message) {
    switch (message.data['tipo']?.toString()) {
      case 'aniversario':
        return 'Aniversariantes UAI';
      case 'nova_inscricao':
        return 'Inscrições UAI';
      default:
        return 'Notificações UAI';
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
      final isBirthday = message.data['tipo']?.toString() == 'aniversario';
      // A lista por aluno usa estilo de conversa com avatares (Android).
      // O estilo anterior de foto única permanece como fallback para payloads antigos.
      final birthdayInbox = isBirthday && defaultTargetPlatform == TargetPlatform.android
          ? await BirthdayInboxNotification.style(message.data)
          : null;
      final birthdayPhoto = isBirthday && birthdayInbox == null
          ? await _birthdayImage(message.data['foto_url']?.toString())
          : null;
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            _channelIdForMessage(message),
            _channelNameForMessage(message),
            channelDescription: 'Canal para notificações do app UAI Capoeira',
            importance: Importance.high,
            priority: Priority.high,
            icon: isNovaInscricao
                ? '@drawable/ic_notification_inscricao'
                : isBirthday
                    ? '@drawable/ic_notification_birthday'
                    : '@drawable/ic_notification',
            styleInformation: birthdayInbox ?? (birthdayPhoto == null
                ? BigTextStyleInformation(_resolvedBody(message))
                : BigPictureStyleInformation(
                    FilePathAndroidBitmap(birthdayPhoto),
                    contentTitle: _resolvedTitle(message),
                    summaryText: _resolvedBody(message),
                    largeIcon: FilePathAndroidBitmap(birthdayPhoto),
                  )),
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
        payload: jsonEncode(message.data),
      );

      developer.log('✅ Notificação local exibida com sucesso');
    } catch (e) {
      developer.log('❌ Erro ao mostrar notificação local: $e');
    }
  }

  // Foto opcional da notificação de aniversário em primeiro plano.
  // Só aceita HTTPS, tem timeout e nunca impede a notificação textual.
  Future<String?> _birthdayImage(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https') return null;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 750000) return null;
      }
      if (bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/uai_birthday_notification.jpg');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
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
