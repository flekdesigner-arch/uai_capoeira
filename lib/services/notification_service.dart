// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class NotificationService {
  // ✅ GETTERS LAZY – SÓ ACESSADOS QUANDO FIREBASE ESTIVER PRONTO
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  // ✅ CONTROLE DE ESTADO
  bool _isInitialized = false;
  bool _isRequestingPermission = false;

  // ═══════════════════════════════════════════════════════════
  // INICIALIZAR NOTIFICAÇÕES
  // ═══════════════════════════════════════════════════════════
  Future<void> initNotifications() async {
    // Verifica se Firebase app já foi inicializado
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

      // Mesmo já inicializado, tenta sincronizar o token atual.
      // Isso ajuda quando o app iniciou antes do login.
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

      // Configurar notificações locais
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
          print('🖱️ Notificação local clicada: ${response.payload}');
        },
      );

      // Android 13+ precisa dessa permissão para notificação local também
      if (!kIsWeb) {
        final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        await androidPlugin?.requestNotificationsPermission();
      }

      // Solicitar permissão FCM
      final NotificationSettings perm = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('🔔 Status da permissão: ${perm.authorizationStatus}');

      if (perm.authorizationStatus == AuthorizationStatus.authorized ||
          perm.authorizationStatus == AuthorizationStatus.provisional) {
        // Obter token FCM
        final String? token = await _fcm.getToken();
        print('🔔 Token FCM gerado: $token');

        if (token != null) {
          await _saveTokenCleaningOld(token);
        } else {
          print('⚠️ Token FCM retornou nulo.');
        }

        // Inscrever em tópico geral
        await _fcm.subscribeToTopic('all_users');
        print('🔔 Inscrito no tópico all_users');
      } else {
        print('⚠️ Permissão de notificação negada pelo usuário.');
      }

      // Escutar mensagens em primeiro plano
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Notificação recebida em primeiro plano: ${message.messageId}');
        print('📨 Título: ${message.notification?.title}');
        print('📨 Corpo: ${message.notification?.body}');
        print('📨 Data: ${message.data}');

        _showLocalNotification(message);
      });

      // Escutar clique em notificações
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🖱️ Notificação clicada: ${message.messageId}');
        print('🖱️ Data: ${message.data}');
        // TODO: navegar para tela específica se precisar
      });

      // Verifica se o app foi aberto por uma notificação com ele fechado
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        print('🚀 App aberto por notificação: ${initialMessage.messageId}');
        print('🚀 Data: ${initialMessage.data}');
      }

      // Listener para mudança de token
      _fcm.onTokenRefresh.listen((String newToken) async {
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
  // SINCRONIZAR TOKEN DO USUÁRIO ATUAL
  // Use depois do login ou quando entrar na tela principal.
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

      final String? token = await _fcm.getToken();

      if (token == null) {
        print('⚠️ FCM token veio nulo ao sincronizar.');
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
  // IMPORTANTE:
  // - NÃO mexe em status_conta.
  // - status_conta é aprovação do usuário e deve continuar controlado pelo admin.
  // - Usa set merge em UMA escrita só para não apagar token e falhar antes de salvar o novo.
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
      }, SetOptions(merge: true));

      print('✅ Token atual salvo e tokens antigos substituídos para: ${user.email}');
    } catch (e) {
      print('❌ Erro ao salvar token no Firestore: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REMOVER TOKEN NO LOGOUT
  // Remove apenas o token atual do array e apaga current_fcm_token
  // ═══════════════════════════════════════════════════════════
  Future<void> removeToken() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        print('⚠️ Nenhum usuário logado para remover token.');
        return;
      }

      final String? token = await _fcm.getToken();
      if (token == null) {
        print('⚠️ Token atual veio nulo no logout.');
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

      print('✅ Notificação local de teste enviada!');
    } catch (e) {
      print('❌ Erro ao enviar notificação de teste: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // MOSTRAR NOTIFICAÇÃO LOCAL QUANDO APP ESTÁ ABERTO
  // ═══════════════════════════════════════════════════════════
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
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
      final String? token = await _fcm.getToken();
      print('🔔 Token atual consultado: $token');
      return token;
    } catch (e) {
      print('❌ Erro ao obter token: $e');
      return null;
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      print('✅ Inscrito no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao inscrever no tópico $topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      print('✅ Cancelada inscrição no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao cancelar inscrição no tópico $topic: $e');
    }
  }
}
