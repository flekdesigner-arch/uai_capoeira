import 'dart:async';
// =====================================================
// 📱 IMPORTAÇÕES - TELAS DO APP
// =====================================================
import 'package:uai_capoeira/modules/turmas/screens/tela_turma_screen.dart';
import 'package:uai_capoeira/modules/turmas/admin/vincular_aluno_turma_screen.dart';
import 'package:uai_capoeira/modules/sistema/admin/admin_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/alunos_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/aniversariantes_screen.dart';
import 'package:uai_capoeira/modules/auth/screens/auth_check.dart';
import 'package:uai_capoeira/app/splash/splash_auth_screen.dart';
import 'package:uai_capoeira/modules/usuarios/screens/profile_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/turmas_academia_screen.dart';
import 'package:uai_capoeira/modules/eventos/screens/eventos_screen.dart';
import 'package:uai_capoeira/modules/uniformes/screens/uniformes_screen.dart';
import 'package:uai_capoeira/shared/widgets/drawer_widget.dart';
import 'package:uai_capoeira/app/home_page.dart';
import 'package:uai_capoeira/modules/site/screens/landing_page.dart';

// =====================================================
// 🖼️ IMAGENS E CACHE
// =====================================================
import 'package:cached_network_image/cached_network_image.dart';

// =====================================================
// 🔥 FIREBASE CORE
// =====================================================
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

// =====================================================
// 🎨 FLUTTER CORE
// =====================================================
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/shared/widgets/uai_theme_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// =====================================================
// 📅 DATAS E INTERNACIONALIZAÇÃO
// =====================================================
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// =====================================================
// 🔔 NOTIFICAÇÕES PUSH
// =====================================================
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uai_capoeira/shared/services/notification_service.dart';
import 'package:uai_capoeira/shared/services/notification_badge_service.dart';

// =====================================================
// 💬 SERVIÇOS
// =====================================================
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/services/atualizacao_dialog_service.dart';
import 'package:uai_capoeira/core/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/modules/alunos/services/mensagem_aniversario_service.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_dashboard_screen.dart'
as area_aluno_dashboard;
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_session_service.dart';
import 'package:uai_capoeira/shared/widgets/em_desenvolvimento_screen.dart';

// =====================================================
// 🔑 CHAVE GLOBAL PARA NAVEGAÇÃO
// =====================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// =====================================================
// 🔔 HANDLER PARA NOTIFICAÇÕES EM BACKGROUND
// =====================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    print('⚠️ Firebase já inicializado ou erro no background handler: $e');
  }

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

// =====================================================
// 🚀 FUNÇÃO PRINCIPAL
// =====================================================
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

    // =====================================================
    // 🔐 PERSISTÊNCIA DE LOGIN - WEB
    // =====================================================
    if (kIsWeb) {
      print('💾 Configurando persistência LOCAL para web...');
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      print('✅ Persistência LOCAL configurada');
    }

    // Observação:
    // No Android/APK, o Firebase Auth já usa persistência local automaticamente.
    // A tela SplashAuthScreen é quem segura o fluxo até a sessão ser restaurada.

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      print('✅ Sessão inicial detectada: ${currentUser.email}');
      print('   UID: ${currentUser.uid}');
      print('   Email verificado: ${currentUser.emailVerified}');
    } else {
      print('ℹ️ Nenhuma sessão detectada imediatamente. Splash vai aguardar o Auth.');
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
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }

    print('🌍 Configurando locale...');
    Intl.defaultLocale = 'pt_BR';
    print('✅ Locale configurado');

    print('🎨 Inicializando tema do app...');
    await AppThemeController.instance.initialize();
    print('✅ Tema inicializado');

    print('🏁 Chamando runApp...');
    runApp(const UaiCapoeiraApp());
    print('✅ runApp executado');
  } catch (e, stack) {
    print('❌❌❌ ERRO FATAL NO MAIN: $e');
    print(stack);
    runApp(ErrorApp(error: e, stack: stack));
  }
}

// =====================================================
// 🚨 TELA DE ERRO (Fallback)
// =====================================================
class ErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;

  const ErrorApp({
    super.key,
    required this.error,
    required this.stack,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
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
                    '$error',
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
                      style: TextStyle(
                        fontSize: 10,
                        color: context.uai.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// 🏢 APP PRINCIPAL
// =====================================================
class UaiCapoeiraApp extends StatefulWidget {
  const UaiCapoeiraApp({super.key});

  @override
  State<UaiCapoeiraApp> createState() => _UaiCapoeiraAppState();
}

class _UaiCapoeiraAppState extends State<UaiCapoeiraApp> {
  @override
  void initState() {
    super.initState();

    // =====================================================
    // 🔐 MONITORA MUDANÇAS NA AUTENTICAÇÃO
    // =====================================================
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        print('🔐 Auth State: Usuário LOGADO - ${user.email}');
      } else {
        print('🔐 Auth State: Usuário DESLOGADO');
      }
    });

    // Verifica o usuário atual ao iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      print('👤 Usuário atual no build: ${user?.email ?? "Nenhum"}');
    });
  }

  @override
  Widget build(BuildContext context) {
    print('🏢 UaiCapoeiraApp.build()');

    final themeController = AppThemeController.instance;

    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'UAI CAPOEIRA',
          themeMode: themeController.themeMode,
          theme: AppTheme.buildLight(themeController.currentPreset),
          darkTheme: AppTheme.buildDark(themeController.currentPreset),
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

          // =====================================================
          // 🏠 HOME
          // Web mantém LandingPage.
          // APK abre SplashAuthScreen para aguardar restauração do login.
          // =====================================================
          home: kIsWeb ? PwaEntradaInteligente() : SplashAuthScreen(),
        );
      },
    );
  }
}


// =====================================================
// 🌐 ENTRADA INTELIGENTE DO PWA
// =====================================================
class PwaEntradaInteligente extends StatefulWidget {
  PwaEntradaInteligente({super.key});

  @override
  State<PwaEntradaInteligente> createState() => _PwaEntradaInteligenteState();
}

class _PwaEntradaInteligenteState extends State<PwaEntradaInteligente> {
  Widget? _destino;
  String _mensagem = 'Verificando sessão salva...';

  @override
  void initState() {
    super.initState();
    _resolverEntrada();
  }

  Future<User?> _aguardarFirebaseAuth() async {
    var user = FirebaseAuth.instance.currentUser;

    if (user != null) return user;

    try {
      user = await FirebaseAuth.instance
          .idTokenChanges()
          .first
          .timeout(Duration(seconds: 2));
    } on TimeoutException {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    return user;
  }

  Future<void> _resolverEntrada() async {
    try {
      setState(() => _mensagem = 'Restaurando login do app...');

      final user = await _aguardarFirebaseAuth();

      if (!mounted) return;

      if (user != null) {
        debugPrint('✅ PWA: sessão Firebase restaurada para ${user.email}');
        setState(() => _destino = AuthCheck());
        return;
      }

      setState(() => _mensagem = 'Verificando Área do Aluno...');

      final sessaoAluno =
      await AreaAlunoSessionService().restaurarSessaoRevalidando();

      if (!mounted) return;

      if (sessaoAluno != null) {
        debugPrint('✅ PWA: sessão da Área do Aluno restaurada.');

        setState(() {
          _destino = area_aluno_dashboard.AreaAlunoDashboardScreen(
            aluno: Map<String, dynamic>.from(sessaoAluno['aluno'] as Map),
            config: Map<String, dynamic>.from(sessaoAluno['config'] as Map),
            authPayload: Map<String, dynamic>.from(
              sessaoAluno['authPayload'] as Map,
            ),
          );
        });
        return;
      }

      debugPrint('ℹ️ PWA: nenhuma sessão salva. Abrindo LandingPage.');
      setState(() => _destino = LandingPage());
    } catch (e) {
      debugPrint('⚠️ Erro ao resolver entrada do PWA: $e');

      if (!mounted) return;

      setState(() => _destino = LandingPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final destino = _destino;

    if (destino != null) {
      return destino;
    }

    return Scaffold(
      backgroundColor: context.uai.background,
      body: Center(
        child: Container(
          padding: EdgeInsets.all(24),
          margin: EdgeInsets.all(22),
          constraints: BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: context.uai.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logoprincipal.png',
                width: 104,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.sports_martial_arts_rounded,
                  color: context.uai.primary,
                  size: 64,
                ),
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(color: context.uai.primary),
              SizedBox(height: 14),
              Text(
                _mensagem,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// =====================================================
// 🎂 WIDGET DO BOTÃO DE ANIVERSARIANTE COM CONTADOR
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
          .map((snapshot) => snapshot.docs.isNotEmpty)
          : Stream.value(false),
      builder: (context, snapshot) {
        final bool temVinculo = snapshot.data ?? false;

        if (!temVinculo) {
          return SizedBox.shrink();
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
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            constraints: BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.cake,
                      color: isSelected ? context.uai.primary : context.uai.textMuted,
                      size: 24,
                    ),
                    if (birthdayCount > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: context.uai.error,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: context.uai.surface, width: 1.5),
                          ),
                          constraints: BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Center(
                            child: Text(
                              birthdayCount > 9 ? '9+' : '$birthdayCount',
                              style: TextStyle(
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
                SizedBox(height: 2),
                Flexible(
                  child: Text(
                    'ANIVERSÁRIOS',
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? context.uai.primary : context.uai.textMuted,
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

// =====================================================
// 📱 TELA PRINCIPAL (APÓS LOGIN)
// =====================================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissaoService _permissaoService = PermissaoService();

  int _selectedIndex = 0;
  bool _dialogoAtualizacaoVerificado = false;

  static final List<Widget> _widgetOptions = <Widget>[
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
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  Widget _buildNotificationBell() {
    final t = context.uai;

    return StreamBuilder<int>(
      stream: NotificationBadgeService().getUnreadNotificationsCount(),
      builder: (context, snapshot) {
        final int unreadCount = snapshot.data ?? 0;

        return Stack(
          children: [
            IconButton(
              icon: Icon(Icons.notifications_outlined),
              color: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
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
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface, width: 1.5),
                  ),
                  constraints: BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: TextStyle(
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

  Future<void> _verificarAtualizacaoAoEntrar() async {
    if (_dialogoAtualizacaoVerificado) return;

    await Future.delayed(Duration(seconds: 2));

    if (mounted) {
      debugPrint('🔍 Verificando atualização ao entrar...');
      await AtualizacaoDialogService().verificarEMostrarDialogo(context);
      _dialogoAtualizacaoVerificado = true;
    }
  }

  Future<void> _inicializarNotificacoesAoEntrar() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('⚠️ Notificações não iniciadas: usuário não logado.');
      return;
    }

    try {
      final notificationService = NotificationService();

      // Inicializa permissões, canais, listeners e tenta salvar o token.
      await notificationService.initNotifications();

      // Garante a sincronização depois do login/sessão restaurada.
      await notificationService.syncTokenForCurrentUser();

      debugPrint('✅ Notificações inicializadas e token sincronizado para: ${user.email}');
    } catch (e) {
      debugPrint('❌ Erro ao inicializar/sincronizar notificações: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (FirebaseAuth.instance.currentUser != null) {
        await _inicializarNotificacoesAoEntrar();
        await _verificarAtualizacaoAoEntrar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

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
                  style: TextStyle(color: t.textSecondary),
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
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _selectedIndex == 0 ? 'UAI CAPOEIRA' : 'Aniversariantes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        actions: [
          _buildNotificationBell(),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: UaiThemeIconButton(),
          ),
        ],
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomAppBar(
        color: t.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        shadowColor: Colors.black.withOpacity(0.18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Botão INÍCIO
            InkWell(
              onTap: () => _onItemTapped(0),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                constraints: BoxConstraints(minHeight: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.home,
                      color: _selectedIndex == 0
                          ? t.primary
                          : t.textMuted,
                      size: 24,
                    ),
                    SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        'INÍCIO',
                        style: TextStyle(
                          fontSize: 11,
                          color: _selectedIndex == 0
                              ? t.primary
                              : t.textMuted,
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

            // Botão ANIVERSARIANTES
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