import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:uai_capoeira/core/caca_bug/caca_bug_actions.dart';
import 'package:uai_capoeira/core/caca_bug/caca_bug_service.dart';

// Services
import 'package:uai_capoeira/modules/turmas/services/academia_cache_service.dart';
import 'package:uai_capoeira/core/emergency_offline/emergency_offline_service.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_acesso_service.dart';

// Telas
import 'package:uai_capoeira/modules/turmas/screens/turmas_academia_screen.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/shared/widgets/uai_dynamic_logo.dart';
import 'package:uai_capoeira/modules/jogo/screens/uai_arena_game_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final AcademiaCacheService _cacheService = AcademiaCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDataStream;
  late Future<List<Map<String, dynamic>>> _academiasFuture;

  bool _registrouUltimoAcesso = false;
  bool _cacaBugRegistrouHome = false;
  bool _cacaBugRegistrouPerfil = false;
  bool _cacaBugRegistrouErroPerfil = false;
  bool _cacaBugRegistrouPrimeiroCarregamentoAcademias = false;
  bool _homeInicializada = false;
  String? _ultimoPerfilLogSignature;

  // ============================================================
  // EASTER EGG DA LOGO UAI
  // 0-3s  : logo pisca / muda de tema e cor
  // 3-6s  : entra fumaça
  // 6s+   : roda gigante com alunos ativos
  // Ao soltar: tudo volta ao normal sem persistir troca de tema.
  // ============================================================
  late final AnimationController _logoFxController;
  Timer? _logoHoldTimer;
  DateTime? _logoHoldStartedAt;
  bool _logoPointerDown = false;
  int _logoFxStage = 0;
  int _logoThemeIndex = 0;
  double _logoBlink = 1.0;
  bool _carregandoAlunosRoda = false;
  bool _alunosRodaCarregados = false;
  bool _logoReleasing = false;
  Timer? _logoReleaseTimer;
  double _logoFxOpacity = 1.0;
  int? _logoThemeIndexCongeladoRoda;
  bool _logoGameTriggered = false;
  int _logoHoldElapsedMs = 0;
  List<Map<String, dynamic>> _alunosAtivosRoda = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _academiasCacheHome = <Map<String, dynamic>>[];

  static const List<Color> _logoFxColors = <Color>[
    Color(0xFFC51E24),
    Color(0xFF7C3AED),
    Color(0xFF00C853),
    Color(0xFFFFB300),
    Color(0xFF00A8FF),
    Color(0xFFFF2D95),
    Color(0xFFFF6D00),
  ];

  @override
  void initState() {
    super.initState();
    _logoFxController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _registrarUltimoAcessoUsuario();
    unawaited(_bootstrapHome());
  }

  @override
  void dispose() {
    _logoHoldTimer?.cancel();
    _logoReleaseTimer?.cancel();
    _logoFxController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapHome() async {
    // A abertura da Home nunca pode depender da inicialização do diagnóstico:
    // ele pode aguardar o Firebase quando o dispositivo está 100% offline.
    _inicializarStreams();
    if (!mounted) return;
    setState(() => _homeInicializada = true);
    unawaited(_inicializarCacaBug().catchError((Object error) {
      debugPrint('Caça Bugs: inicialização adiada: $error');
    }));
  }

  Future<void> _inicializarCacaBug() async {
    if (currentUser == null) return;
    if (_cacaBugRegistrouHome) return;

    await CacaBugService.instance.inicializar(user: currentUser);

    _cacaBugRegistrouHome = true;

    await CacaBugService.instance.registrarEvento(
      tipo: 'acao_usuario',
      acao: CacaBugActions.abriuHome,
      descricao: 'Usuário entrou na Home',
      tela: 'HomePage',
      arquivo: 'lib/app/home_page.dart',
      rota: '/home',
      status: 'success',
    );
  }

  void _inicializarStreams() {
    if (currentUser != null) {
      final userDoc = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser!.uid);

      // Windows Desktop: metadata-only snapshots geravam rebuilds extras e
      // aumentavam o churn dos canais nativos do Firestore. Para a Home nós
      // só precisamos redesenhar o perfil quando os dados realmente mudarem.
      final isWindowsDesktop =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

      _userDataStream = userDoc
          .snapshots(includeMetadataChanges: !isWindowsDesktop)
          .distinct((anterior, atual) {
            if (!isWindowsDesktop) return false;
            if (anterior.exists != atual.exists) return false;

            final a = anterior.data();
            final b = atual.data();
            return a?['nome_completo'] == b?['nome_completo'] &&
                a?['foto_url'] == b?['foto_url'] &&
                a?['status'] == b?['status'] &&
                a?['tipo_usuario'] == b?['tipo_usuario'];
          });
    } else {
      _userDataStream = Stream.empty();
    }

    // IMPORTANTE:
    // Antes isso começava como Future.value([]), então a Home podia mostrar
    // "Você não está vinculado..." antes da busca real terminar.
    _academiasFuture = _carregarAcademias();
  }

  Future<void> _registrarUltimoAcessoUsuario() async {
    if (_registrouUltimoAcesso) return;
    if (currentUser == null) return;

    _registrouUltimoAcesso = true;

    final acessoRegistrado = await UsuarioAcessoService(
      firestore: _firestore,
    ).registrarUltimoAcessoGestao(uid: currentUser!.uid);

    debugPrint(
      acessoRegistrado
          ? 'Último acesso confirmado para ${currentUser!.uid}'
          : 'Último acesso não foi confirmado para ${currentUser!.uid}',
    );
  }

  Future<List<Map<String, dynamic>>> _carregarAcademias({
    bool origemRefreshManual = false,
  }) async {
    final uid = currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      debugPrint('HomePage: usuário nulo ao carregar academias.');
      return [];
    }

    final temInternet = await _cacheService.temInternet();

    List<Map<String, dynamic>> academias;
    try {
      academias = await _cacheService.carregarAcademiasComAlunos(uid)
          .timeout(const Duration(seconds: 12));
    } catch (error) {
      debugPrint('Home: lista online indisponível; emergência local permanece acessível: $error');
      academias = <Map<String, dynamic>>[];
    }

    // A Home original também utiliza o pacote de emergência, sem tela paralela.
    if (academias.isEmpty) {
      final local = await EmergencyOfflineService.instance.read();
      final ac = (local?['academias'] as List?) ?? const [];
      final ts = (local?['turmas'] as List?) ?? const [];
      final as = (local?['alunos'] as List?) ?? const [];
      if (ac.isNotEmpty) {
        academias = ac.whereType<Map>().map((row) {
          final id = (row['id'] ?? '').toString();
          return <String, dynamic>{
            'id': id,
            'nome': row['nome'] ?? 'Academia',
            'cidade': row['cidade'] ?? '',
            'logo_url': row['logo_url'] ?? '',
            'turmas_count': ts.where((t) => t is Map && t['academiaId'] == id).length,
            'alunos_count': as.where((a) => a is Map && ts.any((t) => t is Map && t['id'] == a['turmaId'] && t['academiaId'] == id)).length,
          };
        }).toList();
      }
    }
    if (!mounted) return academias;
    _academiasCacheHome = List<Map<String, dynamic>>.from(academias);
    // Atualização antecipada: mantém o último snapshot íntegro ao falhar.
    if (academias.isNotEmpty && temInternet) {
      unawaited(EmergencyOfflineService.instance.refresh().catchError((Object error) {
        debugPrint('Cache de emergência: atualização adiada: $error');
      }));
    }
    debugPrint('HomePage: academias carregadas: ${academias.length}');

    if (origemRefreshManual) {
      unawaited(
        CacaBugService.instance.registrarEvento(
          tipo: 'acao_usuario',
          acao: CacaBugActions.atualizouAcademias,
          descricao: 'Usuário atualizou academias na Home',
          tela: 'HomePage',
          arquivo: 'lib/app/home_page.dart',
          rota: '/home',
          status: 'success',
          dados: {'quantidade': academias.length, 'origem': 'refresh_manual'},
        ),
      );
    } else if (!_cacaBugRegistrouPrimeiroCarregamentoAcademias) {
      _cacaBugRegistrouPrimeiroCarregamentoAcademias = true;
      unawaited(
        CacaBugService.instance.registrarEvento(
          tipo: 'acao_usuario',
          acao: CacaBugActions.carregouAcademias,
          descricao: 'Usuário carregou ${academias.length} academia(s)',
          tela: 'HomePage',
          arquivo: 'lib/app/home_page.dart',
          rota: '/home',
          status: 'success',
          dados: {
            'quantidade': academias.length,
            'origem': 'carregamento_inicial',
          },
        ),
      );
    }

    return academias;
  }

  Future<void> _recarregarAcademias() async {
    setState(() {
      _academiasFuture = _carregarAcademias(origemRefreshManual: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.uai;

    if (!_homeInicializada) {
      return _buildHomeBootstrapLoading();
    }

    return Scaffold(
      backgroundColor: t.background,
      body: _buildHomeComModoRoda(Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _recarregarAcademias();

              if (currentUser != null) {
                try {
                  await FirebaseFirestore.instance
                      .collection('usuarios')
                      .doc(currentUser!.uid)
                      .get(GetOptions(source: Source.server));
                } catch (e) {
                  debugPrint('Erro ao forçar atualização: $e');
                }
              }
            },
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 500),
                  child: Builder(
                    builder: (context) {
                      final compactHome = _isCompactHome(context);

                      return Column(
                        children: [
                          SizedBox(height: compactHome ? 10 : 30),
                          _buildPerfilStream(theme),
                          SizedBox(height: compactHome ? 10 : 30),
                          _buildLogo(),
                          SizedBox(height: compactHome ? 10 : 30),
                          _buildAcademiasFuture(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }

  bool _isCompactHome(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // A Home precisa considerar também a ALTURA útil da tela.
    // Em aparelhos menores (ex.: Moto G6 Play), usar somente a largura
    // fazia perfil + logo consumirem quase todo o primeiro viewport.
    return size.width < 390 || size.height < 720;
  }

  Widget _buildHomeBootstrapLoading() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      body: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  Widget _buildPerfilStream(ThemeData theme) {
    if (currentUser == null) {
      return _buildPerfilOffline();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDataStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildSkeletonPerfil(theme);
        }

        if (snapshot.hasError) {
          debugPrint('Erro no stream do usuário: ${snapshot.error}');
          if (!_cacaBugRegistrouErroPerfil) {
            _cacaBugRegistrouErroPerfil = true;
            unawaited(
              CacaBugService.instance.registrarErro(
                acao: CacaBugActions.erroCarregarPerfil,
                descricao: 'Erro ao carregar perfil na Home',
                tela: 'HomePage',
                arquivo: 'lib/app/home_page.dart',
                rota: '/home',
                erro: snapshot.error,
              ),
            );
          }
          return _buildPerfilComFallback(theme);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildPerfilVazio(theme);
        }

        final userData = snapshot.data!.data() ?? {};
        final String displayName = userData['nome_completo'] ?? 'Usuário';
        final String? photoUrl = userData['foto_url'] as String?;

        final perfilLogSignature = '${displayName.trim()}|${photoUrl ?? ''}';
        if (_ultimoPerfilLogSignature != perfilLogSignature) {
          _ultimoPerfilLogSignature = perfilLogSignature;
          debugPrint('Perfil atualizado: $displayName');
        }

        if (displayName.trim().isNotEmpty && !_cacaBugRegistrouPerfil) {
          _cacaBugRegistrouPerfil = true;
          unawaited(
            CacaBugService.instance.registrarEvento(
              tipo: 'acao_usuario',
              acao: CacaBugActions.carregouPerfil,
              descricao: 'Usuário carregou o perfil na Home',
              tela: 'HomePage',
              arquivo: 'lib/app/home_page.dart',
              rota: '/home',
              status: 'success',
              dados: {
                'nome': displayName,
                'temFoto': photoUrl != null && photoUrl.isNotEmpty,
              },
            ),
          );
        }

        final compactHome = _isCompactHome(context);
        final avatarRadius = compactHome ? 43.0 : 60.0;

        return Column(
          children: [
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: context.uai.cardAlt,
              child: ClipOval(
                child: _buildAvatarImageHome(
                  photoUrl: photoUrl,
                  displayName: displayName,
                  size: avatarRadius * 2,
                ),
              ),
            ),
            SizedBox(height: compactHome ? 8 : 15),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compactHome ? 14 : 20),
              child: Text(
                displayName.toUpperCase(),
                style: TextStyle(
                  fontSize: compactHome ? 16 : 20,
                  fontWeight: FontWeight.bold,
                  color: context.uai.textPrimary,
                  height: 1.08,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: compactHome ? 3 : 5),
            Text(
              'SEJA BEM VINDO(A) AO APP!',
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: compactHome ? 11.5 : 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerfilComFallback(ThemeData theme) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(currentUser?.uid)
          .get(GetOptions(source: Source.cache)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() ?? {};
          return _buildPerfilComDados(userData);
        }

        return _buildPerfilVazio(theme);
      },
    );
  }

  Widget _buildPerfilComDados(Map<String, dynamic> userData) {
    final String displayName = userData['nome_completo'] ?? 'Usuário';
    final String? photoUrl = userData['foto_url'] as String?;

    final compactHome = _isCompactHome(context);
    final avatarRadius = compactHome ? 43.0 : 60.0;

    return Column(
      children: [
        CircleAvatar(
          radius: avatarRadius,
          backgroundColor: context.uai.cardAlt,
          child: ClipOval(
            child: _buildAvatarImageHome(
              photoUrl: photoUrl,
              displayName: displayName,
              size: avatarRadius * 2,
            ),
          ),
        ),
        SizedBox(height: compactHome ? 8 : 15),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compactHome ? 14 : 20),
          child: Text(
            displayName.toUpperCase(),
            style: TextStyle(
              fontSize: compactHome ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: context.uai.textPrimary,
              height: 1.08,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: compactHome ? 3 : 5),
        Text(
          'SEJA BEM VINDO(A) AO APP!',
          style: TextStyle(
            color: context.uai.textSecondary,
            fontSize: compactHome ? 11.5 : 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPerfilVazio(ThemeData theme) {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: context.uai.cardAlt,
          child: Icon(Icons.person_off, size: 60, color: context.uai.textMuted),
        ),
        SizedBox(height: 15),
        Text(
          'USUÁRIO NÃO IDENTIFICADO',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 5),
        Text(
          'Faça login novamente',
          style: TextStyle(color: context.uai.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPerfilOffline() {
    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: context.uai.cardAlt,
          child: Icon(Icons.person_off, size: 60, color: context.uai.textMuted),
        ),
        SizedBox(height: 15),
        Text(
          'AGUARDANDO LOGIN...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _iniciarLogoEasterEgg() {
    if (_logoPointerDown) return;

    _logoPointerDown = true;
    _logoReleasing = false;
    _logoGameTriggered = false;
    _logoHoldElapsedMs = 0;
    _logoFxOpacity = 1.0;
    _logoThemeIndexCongeladoRoda = null;
    _logoHoldStartedAt = DateTime.now();
    _logoHoldTimer?.cancel();
    _logoReleaseTimer?.cancel();

    if (!_logoFxController.isAnimating) {
      _logoFxController.repeat();
    }

    setState(() {
      _logoFxStage = 1;
      _logoThemeIndex = 0;
      _logoBlink = 1.0;
    });

    _logoHaptic(HapticFeedback.lightImpact);

    _logoHoldTimer = Timer.periodic(
      const Duration(milliseconds: 170),
      (timer) {
        if (!mounted || !_logoPointerDown || _logoHoldStartedAt == null) {
          timer.cancel();
          return;
        }

        final elapsed =
            DateTime.now().difference(_logoHoldStartedAt!).inMilliseconds;

        _logoHoldElapsedMs = elapsed;

        if (elapsed >= 15000 && !_logoGameTriggered) {
          _logoGameTriggered = true;
          timer.cancel();
          unawaited(_abrirUaiArena());
          return;
        }

        // 0-3s: surto visual.
        // 3-6s: fumaça entra e os alunos já são pré-carregados.
        // 6s+: libera a roda gigante.
        final nextStage = elapsed >= 6000
            ? 3
            : elapsed >= 3000
                ? 2
                : 1;

        if (nextStage != _logoFxStage) {
          if (nextStage == 2) {
            _logoHaptic(HapticFeedback.mediumImpact);
            unawaited(_carregarAlunosParaRodaUai());
          } else if (nextStage == 3) {
            _logoHaptic(HapticFeedback.heavyImpact);
            unawaited(_carregarAlunosParaRodaUai());

            // A partir daqui a roda entra em modo contínuo:
            // congela a paleta/tema atual e não "reinicia" visualmente
            // enquanto o dedo continuar pressionado.
            _logoThemeIndexCongeladoRoda = _logoThemeIndex;
          }
        }

        setState(() {
          _logoFxStage = nextStage;

          if (nextStage < 3) {
            _logoThemeIndex++;
            _logoBlink = _logoBlink > 0.75 ? 0.48 : 1.0;
          } else {
            _logoBlink = 1.0;
          }
        });
      },
    );
  }

  void _encerrarLogoEasterEgg() {
    if (!_logoPointerDown && _logoFxStage == 0) return;

    _logoPointerDown = false;
    _logoHoldTimer?.cancel();
    _logoHoldTimer = null;
    _logoHoldStartedAt = null;

    if (_logoFxStage == 0) {
      if (_logoFxController.isAnimating) {
        _logoFxController.stop();
        _logoFxController.reset();
      }
      return;
    }

    // Saída suave: a roda não some de uma vez.
    // Ela vai perdendo força e recuando 3 -> 2 -> 1 -> 0.
    _logoReleaseTimer?.cancel();
    _logoReleasing = true;

    const steps = 10;
    var step = 0;

    _logoReleaseTimer = Timer.periodic(
      const Duration(milliseconds: 90),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        step++;
        final t = step / steps;

        setState(() {
          _logoFxOpacity = (1.0 - t).clamp(0.0, 1.0);

          if (t >= 0.34 && _logoFxStage > 2) {
            _logoFxStage = 2;
          }
          if (t >= 0.68 && _logoFxStage > 1) {
            _logoFxStage = 1;
          }
        });

        if (step >= steps) {
          timer.cancel();

          if (_logoFxController.isAnimating) {
            _logoFxController.stop();
            _logoFxController.reset();
          }

          if (!mounted) return;
          setState(() {
            _logoFxStage = 0;
            _logoThemeIndex = 0;
            _logoBlink = 1.0;
            _logoFxOpacity = 1.0;
            _logoReleasing = false;
            _logoThemeIndexCongeladoRoda = null;
          });
        }
      },
    );
  }

  Future<void> _abrirUaiArena() async {
    if (!mounted) return;

    final academiasValidas = _academiasCacheHome
        .where((a) => (a['id'] ?? '').toString().trim().isNotEmpty)
        .toList();

    if (academiasValidas.isEmpty) {
      _logoGameTriggered = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'A UAI Arena precisa de uma academia carregada na Home.',
          ),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _encerrarLogoEasterEgg();
      return;
    }

    final academiaIds = academiasValidas
        .map((a) => a['id'].toString())
        .toList();

    final academiaNomes = academiasValidas
        .map((a) => (a['nome'] ?? 'Academia').toString())
        .toList();

    _logoPointerDown = false;
    _logoHoldTimer?.cancel();
    _logoReleaseTimer?.cancel();
    _logoHoldStartedAt = null;

    if (_logoFxController.isAnimating) {
      _logoFxController.stop();
      _logoFxController.reset();
    }

    setState(() {
      _logoFxStage = 0;
      _logoThemeIndex = 0;
      _logoBlink = 1.0;
      _logoFxOpacity = 1.0;
      _logoReleasing = false;
      _logoThemeIndexCongeladoRoda = null;
      _logoHoldElapsedMs = 0;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UaiArenaGameScreen(
          academiaIds: academiaIds,
          academiaNomes: academiaNomes,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _logoGameTriggered = false;
    });
  }

  void _logoHaptic(Future<void> Function() feedback) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    unawaited(feedback());
  }

  Future<void> _carregarAlunosParaRodaUai() async {
    if (_carregandoAlunosRoda || _alunosRodaCarregados) return;

    final academiaIds = _academiasCacheHome
        .map((a) => (a['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (academiaIds.isEmpty) return;

    _carregandoAlunosRoda = true;

    try {
      final resultados = await Future.wait(
        academiaIds.map(
          (academiaId) => _firestore
              .collection('alunos')
              .where('academia_id', isEqualTo: academiaId)
              .get(),
        ),
      );

      final vistos = <String>{};
      final alunos = <Map<String, dynamic>>[];

      for (final snapshot in resultados) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final status =
              (data['status_atividade'] ?? '').toString().trim().toUpperCase();

          if (status != 'ATIVO(A)' && status != 'ATIVO') continue;
          if (!vistos.add(doc.id)) continue;

          final nome = (data['nome'] ?? 'Aluno').toString().trim();
          final foto = (
            data['foto_perfil_aluno'] ??
            data['foto_url'] ??
            data['fotoUrl'] ??
            data['foto'] ??
            ''
          ).toString().trim();

          alunos.add({
            'id': doc.id,
            'nome': nome.isEmpty ? 'Aluno' : nome,
            'foto': foto,
          });
        }
      }

      alunos.sort(
        (a, b) => (a['nome'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['nome'] ?? '').toString().toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _alunosAtivosRoda = alunos;
        _alunosRodaCarregados = true;
      });
    } catch (e) {
      debugPrint('Easter Egg UAI: erro ao carregar alunos ativos: $e');
    } finally {
      _carregandoAlunosRoda = false;
    }
  }

  String _iniciaisRodaUai(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      final texto = partes.first;
      return texto.substring(0, math.min(2, texto.length)).toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  Widget _buildHomeComModoRoda(Widget conteudoNormal) {
    final rodaExclusiva = _logoFxStage >= 3;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: rodaExclusiva,
          child: AnimatedOpacity(
            opacity: rodaExclusiva ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: conteudoNormal,
          ),
        ),
        if (rodaExclusiva)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _logoFxOpacity,
              duration: const Duration(milliseconds: 180),
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                alignment: Alignment.center,
                child: Center(
                  child: _buildLogo(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        final preset = AppThemeController.instance.effectivePreset;
        final compactHome = _isCompactHome(context);

        final presets = UaiThemePreset.values;
        final visualIndex = _logoFxStage >= 3 &&
                _logoThemeIndexCongeladoRoda != null
            ? _logoThemeIndexCongeladoRoda!
            : _logoThemeIndex;

        final temaMaluko = _logoFxStage > 0 && presets.isNotEmpty
            ? presets[visualIndex % presets.length]
            : preset;

        final logoHeight = compactHome ? 82.0 : 150.0;
        final wheelSize = compactHome ? 330.0 : 430.0;
        final fxColor =
            _logoFxColors[visualIndex % _logoFxColors.length];

        final logo = AnimatedOpacity(
          opacity: _logoReleasing
              ? 1.0
              : (_logoFxStage > 0 ? _logoBlink : 1.0),
          duration: const Duration(milliseconds: 110),
          child: AnimatedScale(
            scale: _logoFxStage == 0
                ? 1.0
                : (_logoFxStage == 1
                    ? 1.04
                    : (_logoFxStage == 2 ? 1.08 : 1.12)),
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutBack,
            child: Container(
              decoration: _logoFxStage == 0
                  ? null
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: fxColor.withAlpha((255.0 * (
                            _logoFxStage >= 2 ? 0.55 : 0.34)).round()),
                          blurRadius: _logoFxStage >= 2 ? 34 : 20,
                          spreadRadius: _logoFxStage >= 2 ? 8 : 2,
                        ),
                      ],
                    ),
              child: ColorFiltered(
                colorFilter: _logoFxStage > 0
                    ? ColorFilter.mode(
                        fxColor.withAlpha(242),
                        BlendMode.modulate,
                      )
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.dst,
                      ),
                child: UaiDynamicLogo(
                  height: logoHeight,
                  loadRemoteConfig: true,
                  themeId: temaMaluko.id,
                ),
              ),
            ),
          ),
        );

        final stageBoxWidth =
            _logoFxStage >= 3 ? wheelSize : (compactHome ? 300.0 : 360.0);
        final stageBoxHeight = _logoFxStage >= 3
            ? wheelSize
            : (_logoFxStage >= 2 ? logoHeight + 90 : logoHeight);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _iniciarLogoEasterEgg(),
          onPointerUp: (_) => _encerrarLogoEasterEgg(),
          onPointerCancel: (_) => _encerrarLogoEasterEgg(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: stageBoxWidth,
            height: stageBoxHeight,
            alignment: Alignment.center,
            child: Opacity(
              opacity: _logoFxStage > 0 ? _logoFxOpacity : 1.0,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                if (_logoFxStage >= 2)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _logoFxController,
                        builder: (context, _) => CustomPaint(
                          painter: _UaiEnergyBurstPainter(
                            progress: _logoFxController.value,
                            color: fxColor,
                            intensity: _logoFxStage >= 3 ? 1.0 : 0.86,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_logoFxStage >= 1)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _logoFxController,
                      builder: (context, _) {
                        final spin =
                            _logoFxController.value * math.pi * 2.0;
                        return Transform.rotate(
                          angle: spin * 0.16,
                          child: Container(
                            width: logoHeight + 34,
                            height: logoHeight + 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: fxColor.withAlpha(97),
                                width: 2,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (_logoFxStage >= 3)
                  Positioned(
                    width: wheelSize,
                    height: wheelSize,
                    child: IgnorePointer(
                      child: _buildRodaGiganteAlunos(wheelSize, fxColor),
                    ),
                  ),
                logo,
                if (_logoFxStage > 0)
                  Positioned(
                    bottom: _logoFxStage >= 3 ? 18 : -8,
                    child: IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          key: ValueKey(_logoFxStage),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: fxColor.withAlpha(36),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: fxColor.withAlpha(102),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: fxColor.withAlpha(36),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Text(
                            _logoFxStage == 1
                                ? 'UAI... CONTINUE SEGURANDO'
                                : _logoFxStage == 2
                                    ? 'AXÉ CARREGANDO...'
                                    : _alunosAtivosRoda.isEmpty
                                        ? 'CHAMANDO A RODA...'
                                        : _logoHoldElapsedMs >= 9000
                                            ? 'RODA UAI • ${_alunosAtivosRoda.length} ALUNOS • ARENA EM ${math.max(1, ((15000 - _logoHoldElapsedMs) / 1000).ceil())}s'
                                            : 'RODA UAI • ${_alunosAtivosRoda.length} ALUNOS',
                            style: TextStyle(
                              color: context.uai.textPrimary,
                              fontSize: compactHome ? 9.5 : 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRodaGiganteAlunos(double size, Color fxColor) {
    if (_carregandoAlunosRoda && _alunosAtivosRoda.isEmpty) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: fxColor,
          ),
        ),
      );
    }

    if (_alunosAtivosRoda.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _logoFxController,
      builder: (context, _) {
        final alunos = _alunosAtivosRoda;
        final center = size / 2;
        final maxRadius = size * 0.44;
        final minRadius = size * 0.31;

        // Anéis crescem de capacidade conforme se afastam da logo.
        const capacities = <int>[12, 18, 24, 32, 40];
        final rings = <List<Map<String, dynamic>>>[];
        var cursor = 0;

        for (final cap in capacities) {
          if (cursor >= alunos.length) break;
          final end = math.min(cursor + cap, alunos.length);
          rings.add(alunos.sublist(cursor, end));
          cursor = end;
        }

        // Se houver ainda mais alunos, distribui no último anel.
        if (cursor < alunos.length) {
          if (rings.isEmpty) {
            rings.add(alunos.sublist(cursor));
          } else {
            rings[rings.length - 1].addAll(alunos.sublist(cursor));
          }
        }

        final children = <Widget>[];

        for (var ringIndex = 0; ringIndex < rings.length; ringIndex++) {
          final ring = rings[ringIndex];
          final t = rings.length <= 1
              ? 1.0
              : ringIndex / math.max(1, rings.length - 1);
          final radius = minRadius + ((maxRadius - minRadius) * t);
          final direction = ringIndex.isEven ? 1.0 : -1.0;
          final speed = 0.45 + (ringIndex * 0.09);
          final baseRotation =
              _logoFxController.value * math.pi * 2 * speed * direction;
          final avatarSize = math.max(
            20.0,
            math.min(32.0, (2 * math.pi * radius) / (ring.length + 4) * 0.62),
          );

          for (var i = 0; i < ring.length; i++) {
            final aluno = ring[i];
            final angle =
                baseRotation + ((math.pi * 2 * i) / ring.length);
            final left =
                center + math.cos(angle) * radius - (avatarSize / 2);
            final top =
                center + math.sin(angle) * radius - (avatarSize / 2);

            children.add(
              Positioned(
                left: left,
                top: top,
                width: avatarSize,
                height: avatarSize,
                child: _buildAvatarRodaUai(
                  aluno: aluno,
                  size: avatarSize,
                  accent: _logoFxColors[
                      (i + ringIndex + _logoThemeIndex) %
                          _logoFxColors.length],
                ),
              ),
            );
          }
        }

        // linhas dos anéis
        for (var i = 0; i < rings.length; i++) {
          final t = rings.length <= 1
              ? 1.0
              : i / math.max(1, rings.length - 1);
          final radius = minRadius + ((maxRadius - minRadius) * t);
          children.insert(
            0,
            Positioned(
              left: center - radius,
              top: center - radius,
              width: radius * 2,
              height: radius * 2,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: fxColor.withAlpha(31),
                    width: 1,
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: children,
        );
      },
    );
  }

  Widget _buildAvatarRodaUai({
    required Map<String, dynamic> aluno,
    required double size,
    required Color accent,
  }) {
    final nome = (aluno['nome'] ?? 'Aluno').toString();
    final foto = (aluno['foto'] ?? '').toString().trim();

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.uai.card,
        border: Border.all(
          color: accent.withAlpha(224),
          width: math.max(1.4, size * 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(89),
            blurRadius: math.max(5, size * 0.30),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: foto.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: foto,
              fit: BoxFit.cover,
              memCacheWidth: 128,
              placeholder: (context, _) => _avatarRodaFallback(nome, accent),
              errorWidget: (context, _, _) =>
                  _avatarRodaFallback(nome, accent),
            )
          : _avatarRodaFallback(nome, accent),
    );
  }

  Widget _avatarRodaFallback(String nome, Color accent) {
    return Container(
      color: accent.withAlpha(41),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _iniciaisRodaUai(nome),
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildAcademiasFuture() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _academiasFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingAcademias();
        }

        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error.toString());
        }

        final academias = snapshot.data ?? [];

        if (academias.isEmpty) {
          return _buildEmptyAcademias();
        }

        return _buildAcademiasList(academias);
      },
    );
  }

  Widget _buildSkeletonPerfil(ThemeData theme) {
    final compactHome = _isCompactHome(context);
    final avatarSize = compactHome ? 86.0 : 120.0;

    return Column(
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            color: context.uai.border,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(height: compactHome ? 8 : 15),
        Container(
          width: compactHome ? 170 : 200,
          height: compactHome ? 18 : 24,
          color: context.uai.border,
        ),
        SizedBox(height: compactHome ? 3 : 5),
        Container(
          width: compactHome ? 130 : 150,
          height: compactHome ? 12 : 16,
          color: context.uai.border,
        ),
      ],
    );
  }

  Widget _buildLoadingAcademias() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Card(
        elevation: 1,
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(25),
          child: Column(
            children: [
              CircularProgressIndicator(color: context.uai.primary),
              SizedBox(height: 16),
              Text(
                'Carregando suas academias...',
                style: TextStyle(
                  fontSize: 15,
                  color: context.uai.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 50, color: context.uai.error),
          SizedBox(height: 15),
          Text(
            'Erro ao carregar academias',
            style: TextStyle(fontSize: 16, color: context.uai.error),
          ),
          SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: context.uai.textSecondary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _recarregarAcademias,
            icon: Icon(Icons.refresh),
            label: Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAcademias() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        elevation: 2,
        color: context.uai.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(25),
          child: Column(
            children: [
              Icon(Icons.location_off, size: 60, color: context.uai.textMuted),
              SizedBox(height: 15),
              Text(
                'Você não está vinculado a nenhuma academia',
                style: TextStyle(
                  fontSize: 16,
                  color: context.uai.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                'Entre em contato com o administrador',
                style: TextStyle(fontSize: 14, color: context.uai.textMuted),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _recarregarAcademias,
                icon: Icon(Icons.refresh),
                label: Text('Atualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcademiasList(List<Map<String, dynamic>> academias) {
    int totalAlunos = 0;
    for (var academia in academias) {
      totalAlunos += (academia['alunos_count'] ?? 0) as int;
    }

    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 380;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MINHAS ACADEMIAS (${academias.length})',
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.bold,
                        color: context.uai.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total de alunos: $totalAlunos',
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        color: context.uai.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _recarregarAcademias,
                icon: const Icon(Icons.refresh_rounded),
                color: context.uai.textSecondary,
                iconSize: compact ? 18 : 20,
                tooltip: 'Atualizar academias',
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        ...academias.map((academia) => _buildCardAcademia(academia)),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCardAcademia(Map<String, dynamic> academia) {
    final t = context.uai;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 380;
    final logoSize = compact ? 44.0 : 52.0;

    return Card(
      elevation: 0,
      color: t.card,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 6 : 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 18 : t.cardRadius - 6),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 18 : t.cardRadius - 6),
        onTap: () async {
          unawaited(
            CacaBugService.instance
                .registrarEvento(
                  tipo: 'acao_usuario',
                  acao: CacaBugActions.abriuAcademia,
                  descricao:
                      'Usuário abriu a academia ${academia['nome'] ?? 'Academia'}',
                  tela: 'HomePage',
                  arquivo: 'lib/app/home_page.dart',
                  rota: '/home',
                  status: 'success',
                  dados: {
                    'academiaId': academia['id'],
                    'academiaNome': academia['nome'],
                    'academiaCidade': academia['cidade'],
                    'alunosCount': academia['alunos_count'],
                    'turmasCount': academia['turmas_count'],
                  },
                )
                .then((_) => CacaBugService.instance.flush(force: true)),
          );

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TurmasAcademiaScreen(
                academiaId: academia['id'],
                academiaNome: academia['nome'],
                academiaCidade: academia['cidade'],
              ),
            ),
          );

          if (!mounted) return;

          unawaited(
            CacaBugService.instance.registrarEvento(
              tipo: 'navegacao',
              acao: CacaBugActions.voltouHome,
              descricao: 'Usuário voltou para a Home',
              tela: 'HomePage',
              arquivo: 'lib/app/home_page.dart',
              rota: '/home',
              status: 'success',
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: t.primary.withAlpha(26),
                  border: Border.all(color: t.primary.withAlpha(64)),
                ),
                child: academia['logo_url'] != null && academia['logo_url'].toString().isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: academia['logo_url'],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.1,
                                color: context.uai.primary,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(Icons.location_on_rounded, color: t.primary),
                        ),
                      )
                    : Icon(Icons.location_on_rounded, color: t.primary, size: compact ? 22 : 24),
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academia['nome'] ?? 'Academia',
                      style: TextStyle(
                        fontSize: compact ? 15 : 16,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                        height: 1.1,
                      ),
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (academia['cidade']?.toString().isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(
                        academia['cidade'],
                        style: TextStyle(
                          fontSize: compact ? 11.5 : 12,
                          color: context.uai.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildBadge(
                          icon: Icons.people_rounded,
                          text: '${academia['alunos_count'] ?? 0} alunos',
                          color: context.uai.info,
                        ),
                        if ((academia['turmas_count'] ?? 0) > 0)
                          _buildBadge(
                            icon: Icons.class_rounded,
                            text: '${academia['turmas_count']} turmas',
                            color: context.uai.success,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(Icons.chevron_right_rounded, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImageHome({
    required String? photoUrl,
    required String displayName,
    double size = 120,
  }) {
    final iconSize = size * 0.5;

    if (photoUrl == null || photoUrl.isEmpty) {
      return Icon(Icons.person, size: iconSize, color: context.uai.primary);
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: size,
      height: size,
      placeholder: (context, url) => SizedBox(
        width: size * 0.28,
        height: size * 0.28,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: context.uai.primary,
        ),
      ),
      errorWidget: (context, url, error) =>
          Icon(Icons.person, size: iconSize, color: context.uai.primary),
    );
  }
}


class _UaiEnergyBurstPainter extends CustomPainter {
  const _UaiEnergyBurstPainter({
    required this.progress,
    required this.color,
    required this.intensity,
  });

  final double progress;
  final Color color;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final minSide = math.min(size.width, size.height);
    final pulse = 0.5 + (0.5 * math.sin(progress * math.pi * 2));

    // Ondas de energia concêntricas: visíveis em tema claro e escuro.
    for (var i = 0; i < 4; i++) {
      final phase = (progress + i * 0.18) % 1.0;
      final radius = minSide * (0.17 + phase * 0.31);
      final alpha = (1.0 - phase) * 0.36 * intensity;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + ((1.0 - phase) * 2.0)
        ..color = color.withAlpha((255.0 * (alpha)).round());

      canvas.drawCircle(center, radius, paint);
    }

    // Raios elétricos / faíscas.
    for (var i = 0; i < 20; i++) {
      final angle =
          (i / 20.0) * math.pi * 2 +
          (progress * math.pi * 2 * (i.isEven ? 1 : -1));

      final inner = minSide * (0.23 + (i % 3) * 0.008);
      final outer = inner + minSide * (0.055 + 0.028 * pulse);

      final start = center +
          Offset(math.cos(angle) * inner, math.sin(angle) * inner);
      final end = center +
          Offset(math.cos(angle) * outer, math.sin(angle) * outer);

      final sparkColor = Color.lerp(
        color,
        Colors.white,
        i.isEven ? 0.30 : 0.10,
      )!;

      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = i % 4 == 0 ? 2.4 : 1.5
        ..color = sparkColor.withAlpha((255.0 * (
          (0.28 + 0.34 * pulse) * intensity)).round());

      canvas.drawLine(start, end, paint);
    }

    // Halo central.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = color.withAlpha((255.0 * ((0.16 + 0.12 * pulse) * intensity)).round());

    canvas.drawCircle(
      center,
      minSide * (0.20 + 0.018 * pulse),
      halo,
    );
  }

  @override
  bool shouldRepaint(covariant _UaiEnergyBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.intensity != intensity;
  }
}
