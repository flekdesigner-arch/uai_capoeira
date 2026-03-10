// 📱 TELAS DO APP
import 'package:uai_capoeira/screens/turmas/tela_turma_screen.dart';
import 'package:uai_capoeira/vincular_aluno_turma_screen.dart';
import 'package:uai_capoeira/screens/admin/admin_screen.dart';
import 'package:uai_capoeira/screens/alunos/alunos_screen.dart';
import 'package:uai_capoeira/screens/alunos/aniversariantes_screen.dart';
import 'package:uai_capoeira/screens/auth/auth_check.dart';
import 'package:uai_capoeira/profile_screen.dart';
import 'package:uai_capoeira/turmas_academia_screen.dart';
import 'package:uai_capoeira/screens/eventos/eventos_screen.dart';
import 'screens/uniformes/uniformes_screen.dart';
import 'package:uai_capoeira/widgets/drawer_widget.dart';
import 'package:uai_capoeira/screens/home_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🔥 UMA ÚNICA VEZ
import 'screens/site/landing_page.dart';

// 🖼️ IMAGENS E CACHE
import 'package:cached_network_image/cached_network_image.dart';

// 🔥 FIREBASE CORE
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 🎨 FLUTTER CORE
import 'package:flutter/material.dart';

// 📅 DATAS E INTERNACIONALIZAÇÃO
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// 🎯 CONFIGURAÇÃO DO FIREBASE
import 'firebase_options.dart';

// 🔔 NOTIFICAÇÕES PUSH
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/notification_service.dart';
import 'services/notification_badge_service.dart';

// 💬 SERVIÇO DE MENSAGENS DE ANIVERSÁRIO
import 'services/mensagem_aniversario_service.dart';

// ==================== SERVIÇOS ====================
import 'screens/em_desenvolvimento_screen.dart';
import 'services/permissao_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uai_capoeira/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/services/atualizacao_dialog_service.dart'; // 🔥 IMPORT ADICIONADO!
// ====================================================

// =====================================================
// CHAVE GLOBAL PARA NAVEGAÇÃO
// =====================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔔 HANDLER PARA NOTIFICAÇÕES EM BACKGROUND
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📨 Background message: ${message.messageId}');

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'background_channel',
    'Notificações',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title ?? 'UAI CAPOEIRA',
    message.notification?.body ?? 'Nova notificação',
    details,
  );
}

Future<void> main() async {
  try {
    print('🚀 INICIANDO APP - PASSO 1');
    WidgetsFlutterBinding.ensureInitialized();
    print('✅ WidgetsFlutterBinding inicializado');

    print('📅 Inicializando date format...');
    await initializeDateFormatting('pt_BR', null);
    print('✅ Date format inicializado');

    print('🔥 Inicializando Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase inicializado');

    // 🔥 FORÇAR PERSISTÊNCIA NO WEB
    if (kIsWeb) {
      print('💾 Configurando persistência LOCAL para web...');
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      print('✅ Persistência configurada');
    }

    print('📦 Configurando Firestore...');
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    print('✅ Firestore configurado');

    print('🎂 Verificando mensagens de aniversário...');
    try {
      await MensagemAniversarioService().inicializarMensagensPadrao();
      print('✅ Mensagens de aniversário verificadas');
    } catch (e) {
      print('⚠️ Erro em mensagens (não crítico): $e');
    }

    if (!kIsWeb) {
      // Código de notificações só para mobile
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    print('🌍 Configurando locale...');
    Intl.defaultLocale = 'pt_BR';
    print('✅ Locale configurado');

    print('🏁 Chamando runApp...');
    runApp(const UaiCapoeiraApp());
    print('✅ runApp executado');

  } catch (e, stack) {
    print('❌❌❌ ERRO FATAL NO MAIN: $e');
    print(stack);

    // Mesmo com erro, tenta rodar algo
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 80),
                SizedBox(height: 20),
                Text(
                  'Erro ao inicializar o app',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$e',
                    style: TextStyle(color: Colors.red.shade900),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Detalhes técnicos:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      stack.toString(),
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class UaiCapoeiraApp extends StatelessWidget {
  const UaiCapoeiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('🏢 UaiCapoeiraApp.build()');
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'UAI CAPOEIRA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red.shade900),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('pt', 'BR'),
      home: kIsWeb ? const LandingPage() : const AuthCheck(),
    );
  }
}

// =====================================================
// WIDGET DO BOTÃO DE ANIVERSARIANTE COM CONTADOR
// =====================================================
class AniversariantesTab extends StatelessWidget {
  final int selectedIndex;
  final int index;
  final VoidCallback onTap;

  const AniversariantesTab({
    super.key,
    required this.selectedIndex,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<bool>(
      stream: user != null
          ? firestore
          .collection('academias')
          .where('professores_ids', arrayContains: user.uid)
          .snapshots()
          .map((snapshot) {
        final temVinculo = snapshot.docs.isNotEmpty;
        print('🔍 AniversariantesTab - Tem vínculo: $temVinculo');
        return temVinculo;
      })
          : Stream.value(false),
      builder: (context, snapshot) {
        final bool temVinculo = snapshot.data ?? false;

        if (!temVinculo) {
          return const SizedBox.shrink();
        }

        return _buildAniversariantesButton();
      },
    );
  }

  Widget _buildAniversariantesButton() {
    final isSelected = selectedIndex == index;

    return StreamBuilder<int>(
      stream: NotificationBadgeService().getTodayBirthdayCount(),
      builder: (context, snapshot) {
        final int birthdayCount = snapshot.data ?? 0;

        return InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.cake,
                      color: isSelected ? Colors.red.shade900 : Colors.grey,
                      size: 24,
                    ),
                    if (birthdayCount > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Center(
                            child: Text(
                              birthdayCount > 9 ? '9+' : '$birthdayCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    'ANIVERSÁRIOS',
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.red.shade900 : Colors.grey,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _selectedIndex = 0;
  final PermissaoService _permissaoService = PermissaoService();

  // 🔥 FLAG PARA CONTROLAR SE JÁ MOSTROU O DIÁLOGO
  bool _dialogoAtualizacaoVerificado = false;

  static const List<Widget> _widgetOptions = <Widget>[
    HomePage(),
    AniversariantesPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    try {
      final notificationService = NotificationService();
      await notificationService.removeToken();
      _permissaoService.limparCache();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao sair: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildNotificationBell() {
    return StreamBuilder<int>(
      stream: NotificationBadgeService().getUnreadNotificationsCount(),
      builder: (context, snapshot) {
        final int unreadCount = snapshot.data ?? 0;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              color: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔔 Tela de notificações - Em breve!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // 🔥 MÉTODO PARA VERIFICAR ATUALIZAÇÃO AO ENTRAR
  Future<void> _verificarAtualizacaoAoEntrar() async {
    // Evita verificar múltiplas vezes
    if (_dialogoAtualizacaoVerificado) return;

    // Pequeno delay para a tela carregar completamente
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      debugPrint('🔍 Verificando atualização ao entrar...');
      await AtualizacaoDialogService().verificarEMostrarDialogo(context);
      _dialogoAtualizacaoVerificado = true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FirebaseAuth.instance.currentUser != null) {
        NotificationService().initNotifications();

        // 🔥 CHAMAR VERIFICAÇÃO DE ATUALIZAÇÃO
        _verificarAtualizacaoAoEntrar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Usuário não autenticado'),
        ),
      );
    }

    return Scaffold(
      drawer: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('usuarios')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Drawer(
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Drawer(
              child: Center(
                child: Text(
                  "Não foi possível carregar os dados.",
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          final userData = snapshot.data!.data();
          if (userData == null) {
            return const Drawer(
              child: Center(child: Text("Dados não encontrados")),
            );
          }

          return AppDrawer(
            userData: userData,
            currentUser: currentUser,
            onLogout: _logout,
            permissaoService: _permissaoService,
          );
        },
      ),
      appBar: AppBar(
        backgroundColor: Colors.red.shade900,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _selectedIndex == 0 ? 'UAI CAPOEIRA' : 'Aniversariantes',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          _buildNotificationBell(),
        ],
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 8,
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            InkWell(
              onTap: () => _onItemTapped(0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.home,
                      color: _selectedIndex == 0
                          ? Colors.red.shade900
                          : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        'INÍCIO',
                        style: TextStyle(
                          fontSize: 11,
                          color: _selectedIndex == 0
                              ? Colors.red.shade900
                              : Colors.grey,
                          fontWeight: _selectedIndex == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            AniversariantesTab(
              selectedIndex: _selectedIndex,
              index: 1,
              onTap: () => _onItemTapped(1),
            ),
          ],
        ),
      ),
    );
  }
}