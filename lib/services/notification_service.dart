// services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ ADICIONADO!

class NotificationService {
  // ❌ REMOVIDO: inicializações diretas que causavam erro
  // ✅ AGORA USA GETTERS - SÓ SÃO ACESSADOS QUANDO FIREBASE ESTIVER PRONTO
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  // ✅ CONTROLE DE ESTADO - EVITA CHAMADAS DUPLICADAS
  bool _isInitialized = false;
  bool _isRequestingPermission = false;

  // INICIALIZAR NOTIFICAÇÕES
  Future<void> initNotifications() async {
    // ✅ VERIFICA SE FIREBASE JÁ INICIALIZOU
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

    // ✅ PREVINE INICIALIZAÇÃO DUPLICADA
    if (_isInitialized) {
      print('🔔 Notificações já inicializadas');
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

      await _localNotifications.initialize(settings);

      // Solicitar permissão
      NotificationSettings settings2 = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );

      print('🔔 Status da permissão: ${settings2.authorizationStatus}');

      if (settings2.authorizationStatus == AuthorizationStatus.authorized) {
        // Pegar token FCM
        String? token = await _fcm.getToken();
        print('🔔 Token FCM gerado: $token');

        // Salvar token no Firestore
        if (token != null) {
          await _saveTokenToFirestore(token);
        }

        // INSCREVER EM TÓPICO PARA TESTES
        await _fcm.subscribeToTopic('all_users');
        print('🔔 Inscrito no tópico all_users');
      }

      // Escutar notificações em primeiro plano
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Notificação recebida em primeiro plano: ${message.messageId}');
        print('📨 Título: ${message.notification?.title}');
        print('📨 Corpo: ${message.notification?.body}');
        _showLocalNotification(message);
      });

      // Escutar quando abrir notificação
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('🖱️ Notificação clicada: ${message.messageId}');
        // TODO: Navegar para tela específica se necessário
      });

      // VERIFICAR TOKEN INICIAL
      _fcm.getToken().then((token) {
        if (token != null) {
          print('🔔 Token atual: $token');
        }
      });

      // OUVIR MUDANÇAS NO TOKEN
      _fcm.onTokenRefresh.listen((newToken) {
        print('🔄 Token FCM atualizado: $newToken');
        _saveTokenToFirestore(newToken);
      });

      _isInitialized = true;
      print('✅ Notificações inicializadas com sucesso!');

    } catch (e) {
      print('❌ Erro ao inicializar notificações: $e');
    } finally {
      _isRequestingPermission = false;
    }
  }

  // SALVAR TOKEN NO FIRESTORE
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        final userRef = _firestore.collection('usuarios').doc(user.uid);

        // VERIFICA SE O DOCUMENTO EXISTE
        final docSnapshot = await userRef.get();

        if (docSnapshot.exists) {
          await userRef.update({
            'fcm_tokens': FieldValue.arrayUnion([token]),
            'ultimo_token_atualizado': FieldValue.serverTimestamp(),
          });
          print('✅ Token salvo no Firestore para: ${user.email}');
        } else {
          // CRIA O DOCUMENTO SE NÃO EXISTIR
          await userRef.set({
            'fcm_tokens': [token],
            'ultimo_token_atualizado': FieldValue.serverTimestamp(),
            'email': user.email,
            'uid': user.uid,
          }, SetOptions(merge: true)); // ✅ MERGE para não sobrescrever
          print('✅ Documento criado e token salvo para: ${user.email}');
        }
      }
    } catch (e) {
      print('❌ Erro ao salvar token no Firestore: $e');
    }
  }

  // REMOVER TOKEN (LOGOUT)
  Future<void> removeToken() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        String? token = await _fcm.getToken();
        if (token != null) {
          final userRef = _firestore.collection('usuarios').doc(user.uid);

          // VERIFICA SE O DOCUMENTO EXISTE ANTES DE REMOVER
          final docSnapshot = await userRef.get();

          if (docSnapshot.exists) {
            await userRef.update({
              'fcm_tokens': FieldValue.arrayRemove([token]),
              'ultimo_token_removido': FieldValue.serverTimestamp(),
            });
            print('✅ Token removido do Firestore para: ${user.email}');
          }
        }
      }
    } catch (e) {
      print('❌ Erro ao remover token: $e');
    }
  }

  // REMOVER TODOS OS TOKENS (LOGOUT COMPLETO)
  Future<void> removeAllTokens() async {
    try {
      final User? user = _auth.currentUser;
      if (user != null) {
        final userRef = _firestore.collection('usuarios').doc(user.uid);

        final docSnapshot = await userRef.get();

        if (docSnapshot.exists) {
          await userRef.update({
            'fcm_tokens': [],
            'ultimo_token_removido': FieldValue.serverTimestamp(),
          });
          print('✅ Todos os tokens removidos para: ${user.email}');
        }
      }
    } catch (e) {
      print('❌ Erro ao remover todos os tokens: $e');
    }
  }

  // TESTAR NOTIFICAÇÃO LOCAL
  Future<void> testLocalNotification() async {
    try {
      const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
        'test_channel',
        'Canal de Teste',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        0,
        '🎉 Teste de Notificação',
        'Se você está vendo isso, as notificações estão funcionando!',
        details,
      );

      print('✅ Notificação de teste enviada!');
    } catch (e) {
      print('❌ Erro ao enviar notificação de teste: $e');
    }
  }

  // MOSTRAR NOTIFICAÇÃO LOCAL
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
        DateTime.now().millisecond,
        message.notification?.title ?? 'UAI CAPOEIRA',
        message.notification?.body ?? 'Você tem uma nova notificação',
        details,
      );

      print('✅ Notificação local exibida com sucesso');
    } catch (e) {
      print('❌ Erro ao mostrar notificação local: $e');
    }
  }

  // GET TOKEN ATUAL
  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      print('❌ Erro ao obter token: $e');
      return null;
    }
  }

  // INSCREVER EM TÓPICO
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      print('✅ Inscrito no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao inscrever no tópico $topic: $e');
    }
  }

  // CANCELAR INSCRIÇÃO DE TÓPICO
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      print('✅ Cancelada inscrição no tópico: $topic');
    } catch (e) {
      print('❌ Erro ao cancelar inscrição no tópico $topic: $e');
    }
  }
}