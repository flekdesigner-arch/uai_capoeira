import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:xml/xml.dart' as xml;
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'editar_aluno_screen.dart';
import 'package:uai_capoeira/modules/turmas/screens/cadastro_aluno_turma_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/public/visualizar_termo_screen.dart';

//  IMPORTS DO SISTEMA DE FREQUÊNCIA
import 'package:uai_capoeira/modules/chamadas/models/frequencia_model.dart';
import 'package:uai_capoeira/modules/chamadas/services/frequencia_service.dart';
import 'package:uai_capoeira/shared/widgets/indicador_frequencia.dart';
import 'historico_frequencia_screen.dart';
import 'historico_edicoes_aluno_screen.dart';
import 'package:uai_capoeira/modules/alunos/screens/detalhe_participacao_screen.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';

// ============================================
//  SERVIÇO DE CACHE INTELIGENTE (30 MINUTOS)
// ============================================
bool get _isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}

Color _onCard(BuildContext context) => _readableOn(context.uai.card);
Color _onCardMuted(BuildContext context) => _onCard(context).withOpacity(0.68);

Color _onPrimary(BuildContext context) {
  final t = context.uai;
  final temaEscuro =
      t.background.computeLuminance() < 0.45 ||
          t.surface.computeLuminance() < 0.45;

  // No tema Verde Neon o primary é claro, mas o tema é dark.
  // Para cabeçalhos com primaryGradient, branco fica muito mais legível.
  if (temaEscuro) return Colors.white;

  return _readableOn(t.primary);
}

Color _appBarBgOf(BuildContext context) =>
    Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

Color _appBarFgOf(BuildContext context) =>
    Theme.of(context).appBarTheme.foregroundColor ??
        _readableOn(_appBarBgOf(context));


bool _isWideDashboardContext(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 900;
}

bool _isDesktopDashboardContext(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 1180;
}

double _dashboardMaxWidthOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1600) return 1460;
  if (width >= 1180) return 1320;
  if (width >= 900) return 1080;
  return width;
}

EdgeInsets _dashboardPagePaddingOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1180) return const EdgeInsets.fromLTRB(22, 18, 22, 28);
  if (width >= 900) return const EdgeInsets.fromLTRB(18, 16, 18, 24);
  return const EdgeInsets.fromLTRB(14, 14, 14, 22);
}

Widget _dashboardWidthLimiterOf(BuildContext context, Widget child) {
  if (!_isWideDashboardContext(context)) return child;

  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _dashboardMaxWidthOf(context)),
      child: child,
    ),
  );
}

int _dashboardColumnsOf(
    double width, {
      double minItemWidth = 360,
      int maxColumns = 4,
    }) {
  if (width <= 0) return 1;
  final raw = (width / minItemWidth).floor();
  return raw.clamp(1, maxColumns).toInt();
}

Widget _dashboardResponsiveWrapOf({
  required List<Widget> children,
  double minItemWidth = 360,
  int maxColumns = 4,
  double spacing = 12,
  double runSpacing = 12,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width < 720) {
        return Column(
          children: children
              .map(
                (child) => Padding(
              padding: EdgeInsets.only(bottom: runSpacing),
              child: SizedBox(width: double.infinity, child: child),
            ),
          )
              .toList(),
        );
      }

      final columns = _dashboardColumnsOf(
        width,
        minItemWidth: minItemWidth,
        maxColumns: maxColumns,
      );
      final itemWidth = (width - (spacing * (columns - 1))) / columns;

      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: children
            .map((child) => SizedBox(width: itemWidth, child: child))
            .toList(),
      );
    },
  );
}

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, CacheEntry> _memoryCache = {};
  final Duration cacheValidity = Duration(minutes: 30);

  // Verifica se o cache é válido (menos de 30 minutos)
  bool isCacheValid(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return false;

    final age = DateTime.now().difference(entry.timestamp);
    return age < cacheValidity;
  }

  // Salva no cache (memória + Firestore)
  Future<void> saveToCache(String key, Map<String, dynamic> data) async {
    // Cache em memória
    _memoryCache[key] = CacheEntry(data: data, timestamp: DateTime.now());

    if (_isWindowsDesktop) return;

    // Cache no Firestore (para persistência)
    try {
      await _firestore.collection('cache_alunos').doc(key).set({
        'dados': data,
        'timestamp': FieldValue.serverTimestamp(),
        'valido_ate': DateTime.now().add(cacheValidity).toIso8601String(),
      });
    } catch (e) {
      debugPrint('Erro ao salvar cache no Firestore: $e');
    }
  }

  // Carrega do cache (memória > Firestore)
  Future<Map<String, dynamic>?> loadFromCache(String key) async {
    // 1. Tenta memória primeiro
    if (_memoryCache.containsKey(key) && isCacheValid(key)) {
      debugPrint('✓ Cache válido encontrado na MEMÓRIA para $key');
      return _memoryCache[key]!.data;
    }

    if (_isWindowsDesktop) return null;

    // 2. Tenta Firestore cache
    try {
      final doc = await _firestore
          .collection('cache_alunos')
          .doc(key)
          .get(GetOptions(source: Source.cache));

      if (doc.exists) {
        final data = doc.data()!;
        final timestampStr = data['valido_ate'] as String?;

        if (timestampStr != null) {
          final validoAte = DateTime.parse(timestampStr);
          if (DateTime.now().isBefore(validoAte)) {
            debugPrint('✓ Cache válido encontrado no FIRESTORE para $key');

            // Salva também em memória
            _memoryCache[key] = CacheEntry(
              data: Map<String, dynamic>.from(data['dados']),
              timestamp: DateTime.now(),
            );

            return data['dados'] as Map<String, dynamic>;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao ler cache do Firestore: $e');
    }

    return null;
  }

  // Limpa cache antigo
  void limparCacheExpirado() {
    final agora = DateTime.now();
    _memoryCache.removeWhere((key, entry) {
      return agora.difference(entry.timestamp) >= cacheValidity;
    });
  }

  // Remove um item específico do cache em memória e do cache salvo no Firestore.
  Future<void> invalidateCache(String key) async {
    _memoryCache.remove(key);

    if (_isWindowsDesktop) return;

    try {
      await _firestore.collection('cache_alunos').doc(key).delete();
    } catch (e) {
      debugPrint('Erro ao invalidar cache $key: $e');
    }
  }

  Future<void> invalidateAluno(String alunoId) async {
    await invalidateCache('aluno_$alunoId');
  }
}

class CacheEntry {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  CacheEntry({required this.data, required this.timestamp});
}

// ============================================
//  SERVIÇO DE PERMISSÕES
// ============================================
class PermissaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();

  // Singleton
  static final PermissaoService _instance = PermissaoService._internal();
  factory PermissaoService() => _instance;
  PermissaoService._internal();

  Future<Map<String, bool>> carregarPermissoes(String userId) async {
    final cacheKey = 'permissoes_$userId';

    // Tenta cache primeiro
    final cached = await _cache.loadFromCache(cacheKey);
    if (cached != null) {
      return cached.map((key, value) => MapEntry(key, value as bool));
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .collection('permissoes_usuario')
            .doc('configuracoes')
            .get(GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          final permissoes = data.map(
                (key, value) => MapEntry(key, value as bool? ?? false),
          );

          // Salva no cache
          await _cache.saveToCache(cacheKey, permissoes);

          return permissoes;
        }
      }
    } catch (e) {
      print('Erro ao carregar permissões: $e');
    }

    return {};
  }

  Future<bool> temPermissao(String userId, String permissao) async {
    final permissoes = await carregarPermissoes(userId);
    return permissoes[permissao] ?? false;
  }

  Future<bool> isAdmin(String userId) async {
    final cacheKey = 'isAdmin_$userId';

    // Tenta cache primeiro
    final cached = await _cache.loadFromCache(cacheKey);
    if (cached != null) {
      return cached['isAdmin'] as bool;
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('usuarios')
            .doc(userId)
            .get(GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data is Map<String, dynamic>) {
          final peso = data['peso_permissao'] as int? ?? 0;
          final isAdmin = peso >= 90;

          // Salva no cache
          await _cache.saveToCache(cacheKey, {'isAdmin': isAdmin});

          return isAdmin;
        }
      }
    } catch (e) {
      print('Erro ao verificar admin: $e');
    }
    return false;
  }

  void limparCache(String userId) {
    _cache._memoryCache.remove('permissoes_$userId');
    _cache._memoryCache.remove('isAdmin_$userId');
  }
}

class _MotivoAlunoStatus {
  const _MotivoAlunoStatus({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.cor,
  });

  final String id;
  final String titulo;
  final String descricao;
  final IconData icone;
  final Color cor;
}

class _DesativacaoAlunoPayload {
  const _DesativacaoAlunoPayload({
    required this.motivo,
    required this.observacao,
    required this.enviarWhatsApp,
    required this.destinoWhatsApp,
  });

  final _MotivoAlunoStatus motivo;
  final String observacao;
  final bool enviarWhatsApp;
  final String destinoWhatsApp;
}

class _UsuarioAuditoriaAluno {
  const _UsuarioAuditoriaAluno({
    required this.uid,
    required this.nome,
    required this.email,
  });

  final String uid;
  final String nome;
  final String email;
}

class AlunoDetalheScreen extends StatefulWidget {
  final String alunoId;

  AlunoDetalheScreen({super.key, required this.alunoId});

  @override
  State<AlunoDetalheScreen> createState() => _AlunoDetalheScreenState();
}

class _AlunoDetalheScreenState extends State<AlunoDetalheScreen> {
  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard([BuildContext? c]) => _readableOn((c ?? context).uai.card);
  Color _onCardMuted([BuildContext? c]) =>
      _onCard(c ?? context).withOpacity(0.68);

  Color _onPrimary([BuildContext? c]) {
    final t = (c ?? context).uai;
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
            t.surface.computeLuminance() < 0.45;

    if (temaEscuro) return Colors.white;

    return _readableOn(t.primary);
  }

  Color _appBarBg([BuildContext? c]) =>
      Theme.of(c ?? context).appBarTheme.backgroundColor ??
          (c ?? context).uai.primary;

  Color _appBarFg([BuildContext? c]) =>
      Theme.of(c ?? context).appBarTheme.foregroundColor ??
          _readableOn(_appBarBg(c));

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissaoService _permissaoService = PermissaoService();
  final FrequenciaService _frequenciaService = FrequenciaService();
  final Connectivity _connectivity = Connectivity();
  final CacheService _cache = CacheService();

  // ID do usuário logado
  String? _currentUserId;

  // Cache das permissões
  Map<String, bool> _permissoes = {};
  bool _isAdmin = false;
  bool _carregandoPermissoes = true;
  bool _permissoesCarregadas = false;

  // Dados do aluno
  Map<String, dynamic>? _alunoData;
  bool _carregandoAluno = true;

  //  CONTROLE PARA RECARREGAR FREQUÊNCIA QUANDO VOLTAR DA EDIÇÃO
  int _frequenciaKey = 0;

  @override
  void initState() {
    super.initState();
    _carregarUsuarioLogado();
    _carregarDadosAluno();
  }

  void _abrirFotoTelaCheia(String? fotoUrl, String nomeAluno) {
    if (fotoUrl == null || fotoUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Este aluno não possui foto cadastrada.'),
          backgroundColor: context.uai.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.95),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: fotoUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade800,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                size: 64,
                                color: Colors.white54,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Erro ao carregar imagem',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 32,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  nomeAluno,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Toque para fechar',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Future<void> _verTermoAluno(
      BuildContext context,
      String alunoId,
      Map<String, dynamic> alunoData,
      ) async {
    final inscricaoId = alunoData['inscricao_id'];

    if (inscricaoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Este aluno não possui termo de inscrição'),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('inscricoes_aprovadas')
          .doc(inscricaoId)
          .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Termo não encontrado'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final dados = doc.data()!;
      dados['aluno_id'] = alunoId;
      dados['aluno_nome'] = alunoData['nome'];
      dados['aluno_apelido'] = alunoData['apelido'];

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              VisualizarTermoScreen(dados: dados, inscricaoId: inscricaoId),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar termo: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  // VERIFICAR CONEXÃO COM INTERNET
  Future<bool> _temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Erro ao verificar internet: $e');
      return false;
    }
  }

  //  CARREGAR DADOS DO ALUNO COM CACHE INTELIGENTE
  Future<void> _carregarDadosAluno({bool forcarServidor = false}) async {
    try {
      final cacheKey = 'aluno_${widget.alunoId}';

      if (mounted) {
        setState(() {
          _carregandoAluno = true;
        });
      }

      final temInternet = await _temInternet();

      // Sempre que houve escrita recente, elimina qualquer versão antiga.
      if (forcarServidor) {
        await _cache.invalidateAluno(widget.alunoId);
      }

      if (!forcarServidor && _isWindowsDesktop) {
        final cachedData = await _cache.loadFromCache(cacheKey);
        if (cachedData != null) {
          if (!mounted) return;
          setState(() {
            _alunoData = cachedData;
            _carregandoAluno = false;
            _frequenciaKey++;
          });
          debugPrint(
            'Dados do aluno carregados do cache em memoria no Windows',
          );
          return;
        }
      }

      // Com internet, a tela de detalhe deve priorizar o servidor para não
      // exibir status/turma antigos depois de ativar, desativar ou mudar turma.
      // O cache fica como fallback/offline.
      if (!forcarServidor && !temInternet) {
        final cachedData = await _cache.loadFromCache(cacheKey);
        if (cachedData != null) {
          if (!mounted) return;
          setState(() {
            _alunoData = cachedData;
            _carregandoAluno = false;
            _frequenciaKey++;
          });
          debugPrint('✓ Dados do aluno carregados do CACHE offline');
          return;
        }
      }

      debugPrint(
        temInternet
            ? '📡 Buscando dados do aluno do servidor...'
            : '⚠️ Sem internet e sem cache válido para o aluno.',
      );

      DocumentSnapshot doc;
      try {
        final alunoRef = _firestore.collection('alunos').doc(widget.alunoId);
        doc = _isWindowsDesktop
            ? await alunoRef.get()
            : await alunoRef.get(const GetOptions(source: Source.server));
      } catch (e) {
        // Se o servidor falhar, usa cache apenas como plano B.
        final fallbackCache = await _cache.loadFromCache(cacheKey);
        if (fallbackCache != null) {
          if (!mounted) return;
          setState(() {
            _alunoData = fallbackCache;
            _carregandoAluno = false;
            _frequenciaKey++;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Modo offline - usando dados salvos'),
              backgroundColor: context.uai.warning,
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        rethrow;
      }

      if (doc.exists) {
        final data = Map<String, dynamic>.from(
          doc.data() as Map<String, dynamic>,
        );

        await _cache.saveToCache(cacheKey, data);

        if (!mounted) return;
        setState(() {
          _alunoData = data;
          _carregandoAluno = false;
          _frequenciaKey++;
        });
      } else {
        await _cache.invalidateAluno(widget.alunoId);
        if (!mounted) return;
        setState(() {
          _alunoData = null;
          _carregandoAluno = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar aluno: $e');
      if (!mounted) return;
      setState(() {
        _carregandoAluno = false;
      });
    }
  }

  //  CARREGAR USUÁRIO LOGADO E SUAS PERMISSÕES
  Future<void> _carregarUsuarioLogado() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        _currentUserId = user.uid;
        print('✓ Usuário logado ID: $_currentUserId');
        await _carregarPermissoes();
      } else {
        print('Erro: Nenhum usuário logado');
        if (!mounted) return;
        setState(() {
          _carregandoPermissoes = false;
          _permissoesCarregadas = true;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Usuário não autenticado. Faça login novamente.'),
                backgroundColor: context.uai.error,
              ),
            );
          }
        });
      }
    } catch (e) {
      print('Erro: Erro ao carregar usuário logado: $e');
      if (!mounted) return;
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
    }
  }

  //  CARREGAR PERMISSÕES DO USUÁRIO
  Future<void> _carregarPermissoes() async {
    if (_currentUserId == null) {
      if (!mounted) return;
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
      return;
    }

    try {
      final permissoes = await _permissaoService.carregarPermissoes(
        _currentUserId!,
      );
      final isAdmin = await _permissaoService.isAdmin(_currentUserId!);

      if (!mounted) return;
      setState(() {
        _permissoes = permissoes;
        _isAdmin = isAdmin;
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
    } catch (e) {
      print('Erro: Erro ao carregar permissões: $e');
      if (!mounted) return;
      setState(() {
        _carregandoPermissoes = false;
        _permissoesCarregadas = true;
      });
    }
  }

  //  VERIFICAR PERMISSÃO E INTERNET PARA AÇÕES ESCRITA
  Future<bool> _verificarPermissaoEOnline(
      String permissao, {
        String? acao,
      }) async {
    if (_carregandoPermissoes || !_permissoesCarregadas) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Carregando permissões...'),
          backgroundColor: context.uai.info,
          duration: Duration(seconds: 1),
        ),
      );
      return false;
    }

    // VERIFICA INTERNET (OBRIGATÓRIO PARA AÇÕES ESCRITA)
    final bool isOnline = await _temInternet();
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ' Você precisa estar conectado à internet para realizar esta ação.',
          ),
          backgroundColor: context.uai.warning,
          duration: Duration(seconds: 4),
        ),
      );
      return false;
    }

    if (_isAdmin) {
      return true;
    }

    final temPermissao = _permissoes[permissao] ?? false;

    if (!temPermissao) {
      await _mostrarDialogoSemPermissao(acao ?? permissao);
    }

    return temPermissao;
  }

  //  DIÁLOGO DE SEM PERMISSÃO
  Future<void> _mostrarDialogoSemPermissao(String acao) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.uai.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
          ),
          title: Row(
            children: [
              Icon(Icons.no_accounts, color: context.uai.primary, size: 28),
              SizedBox(width: 12),
              Text(
                'Sem Permissão',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.uai.textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você não tem permissão para $acao.',
                style: TextStyle(fontSize: 16, color: context.uai.textPrimary),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.error.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.uai.error.withOpacity(0.16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.uai.primary,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: _onCard(context),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: context.uai.primary),
              child: Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  // FUNÇÕES DE CONTATO (FUNCIONAM OFFLINE)
  Future<void> _launchPhone(String phone) async {
    try {
      var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

      if (digits.isEmpty) {
        throw Exception('Número de telefone não cadastrado');
      }

      // Para LIGAÇÃO telefônica, o discador recebe formato local:
      // 38998262404 -> 038998262404.
      // WhatsApp continua usando 55 no método próprio _formatarNumeroWhatsApp.
      if (digits.startsWith('55') && digits.length >= 12) {
        digits = digits.substring(2);
      }

      if (!digits.startsWith('0')) {
        digits = '0$digits';
      }

      final url = Uri(scheme: 'tel', path: digits);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Não foi possível abrir o aplicativo de telefone');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao realizar chamada: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  String _formatarNumeroWhatsApp(String numero) {
    String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedPhone.startsWith('0')) {
      cleanedPhone = cleanedPhone.substring(1);
    }
    if (!cleanedPhone.startsWith('55')) {
      cleanedPhone = '55$cleanedPhone';
    }
    return cleanedPhone;
  }

  Future<void> _abrirWhatsApp(
      String numero, {
        String? mensagem,
        bool isApp = true,
      }) async {
    try {
      String cleanedPhone = _formatarNumeroWhatsApp(numero);
      String url = 'https://wa.me/$cleanedPhone';

      if (mensagem != null && mensagem.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(mensagem);
        url += '?text=$encodedMessage';
      }

      final uri = Uri.parse(url);

      if (isApp) {
        try {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          if (!launched) {
            throw Exception('Não foi possível abrir o app do WhatsApp');
          }
        } catch (appError) {
          final webUrl = Uri.parse(
            'https://web.whatsapp.com/send?phone=$cleanedPhone' +
                (mensagem != null && mensagem.isNotEmpty
                    ? '&text=${Uri.encodeComponent(mensagem)}'
                    : ''),
          );

          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        final webUrl = Uri.parse(
          'https://web.whatsapp.com/send?phone=$cleanedPhone' +
              (mensagem != null && mensagem.isNotEmpty
                  ? '&text=${Uri.encodeComponent(mensagem)}'
                  : ''),
        );

        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: context.uai.error,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _convidarParaGrupo(
      BuildContext context,
      String? linkGrupo,
      String contatoAluno,
      String? contatoResponsavel,
      ) async {
    if (linkGrupo == null || linkGrupo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link do grupo não disponível'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    try {
      final alunoDoc = await _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .get();
      if (!alunoDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno não encontrado'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final alunoData = alunoDoc.data() as Map<String, dynamic>;
      final nomeAluno = alunoData['nome'] ?? 'Aluno';
      final turmaId = alunoData['turma_id'] as String?;

      String mensagemConvite =
          'Olá! Aqui está o link para entrar no nosso grupo:';

      if (turmaId != null && turmaId.isNotEmpty) {
        final turmaDoc = await _firestore
            .collection('turmas')
            .doc(turmaId)
            .get();
        if (turmaDoc.exists) {
          final turmaData = turmaDoc.data() as Map<String, dynamic>?;
          String msgConvite =
              turmaData?['msg_convite_grupo_whatsapp'] as String? ?? '';

          if (msgConvite.isNotEmpty) {
            //  SUBSTITUI O {nome_aluno} PELO NOME REAL DO ALUNO
            mensagemConvite = msgConvite.replaceAll('{nome_aluno}', nomeAluno);
          }
        }
      }

      final mensagem =
          '$mensagemConvite\n\n ENTRE NO GRUPO PELO LINK ABAIXO:\n$linkGrupo';

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.uai.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
          ),
          title: Text(
            'Convidar para Grupo',
            style: TextStyle(
              color: context.uai.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Enviar convite para o grupo para:',
            style: TextStyle(color: context.uai.textSecondary),
          ),
          actions: [
            if (contatoAluno.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoAluno, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  Theme.of(context).appBarTheme.backgroundColor ??
                      context.uai.primary,
                  foregroundColor:
                  Theme.of(context).appBarTheme.foregroundColor ??
                      _readableOn(
                        Theme.of(context).appBarTheme.backgroundColor ??
                            context.uai.primary,
                      ),
                ),
                child: Text('Aluno'),
              ),
            if (contatoResponsavel != null && contatoResponsavel.isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _abrirWhatsApp(contatoResponsavel, mensagem: mensagem);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  Theme.of(context).appBarTheme.backgroundColor ??
                      context.uai.primary,
                  foregroundColor:
                  Theme.of(context).appBarTheme.foregroundColor ??
                      _readableOn(
                        Theme.of(context).appBarTheme.backgroundColor ??
                            context.uai.primary,
                      ),
                ),
                child: Text('Responsável'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancelar',
                style: TextStyle(color: context.uai.textMuted),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar mensagem de convite: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    }
  }

  String _iniciaisAreaAluno(String nomeCompleto) {
    final ignorar = {'DE', 'DA', 'DO', 'DAS', 'DOS', 'E'};

    final partes = nomeCompleto
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty && !ignorar.contains(p.trim()))
        .toList();

    if (partes.isEmpty) return '';

    return partes
        .map((p) => p.characters.first)
        .join()
        .replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
  }

  String _formatarDataNascimentoAreaAluno(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      final raw = value.trim();

      if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(raw)) {
        return raw;
      }

      date = DateTime.tryParse(raw);
    }

    if (date == null) return '';

    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _ultimosQuatroDigitos(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');

    if (digits.length <= 4) return digits;

    return digits.substring(digits.length - 4);
  }

  Future<Map<String, dynamic>> _configAreaAlunoAtual() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get(GetOptions(source: Source.server));

      return doc.data() ?? {};
    } catch (_) {
      try {
        final doc = await _firestore
            .collection('configuracoes_site')
            .doc('area_aluno')
            .get(GetOptions(source: Source.cache));

        return doc.data() ?? {};
      } catch (_) {
        return {};
      }
    }
  }

  bool _areaAlunoVisivel(Map<String, dynamic> config) {
    final value = config['visivel_site'];
    return value == true;
  }

  Future<void> _enviarAcessoAreaAlunoWhatsApp({
    required String nomeAluno,
    required String contatoAluno,
    required String? contatoResponsavel,
    required String nomeResponsavel,
  }) async {
    try {
      final config = await _configAreaAlunoAtual();

      if (!_areaAlunoVisivel(config)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A Área do Aluno não está ativa no site.'),
            backgroundColor: context.uai.warning,
          ),
        );
        return;
      }

      final alunoDoc = await _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .get();

      if (!alunoDoc.exists) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aluno não encontrado.'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final alunoData = alunoDoc.data() ?? {};
      final nome = alunoData['nome']?.toString() ?? nomeAluno;
      final dataNascimento = _formatarDataNascimentoAreaAluno(
        alunoData['data_nascimento'],
      );
      final iniciais = _iniciaisAreaAluno(nome);
      final exigeTelefone = config['exigir_telefone_confirmacao'] != false;

      final contatoAlunoAtual =
          alunoData['contato_aluno']?.toString() ?? contatoAluno;
      final contatoResponsavelAtual =
          alunoData['contato_responsavel']?.toString() ?? contatoResponsavel;

      final telefoneBase = _temContatoValido(contatoAlunoAtual)
          ? contatoAlunoAtual
          : (contatoResponsavelAtual ?? '');
      final telefoneFinal = _ultimosQuatroDigitos(telefoneBase);

      if (dataNascimento.isEmpty ||
          iniciais.isEmpty ||
          (exigeTelefone && telefoneFinal.length != 4)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dados insuficientes para montar o acesso da Área do Aluno.',
            ),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      final linhas = <String>[
        ' *ÁREA DO ALUNO - UAI CAPOEIRA* ',
        '',
        'Olá! Seguem as instruções para acessar a Área do Aluno de *$nome*.',
        '',
        ' Acesse o site:',
        'http://uaicapoeira.com.br',
        '',
        'No site, toque em *Área do Aluno* e preencha:',
        '',
        '📅 *Data de nascimento:* $dataNascimento',
        '- *Iniciais do nome:* $iniciais',
      ];

      if (exigeTelefone) {
        linhas.add('📱 *Últimos 4 dígitos do telefone:* $telefoneFinal');
      }

      linhas.addAll([
        '',
        '✓ Depois de entrar, o aluno poderá consultar dados, turma, frequência, eventos e certificados.',
        '',
        'Aviso: Não compartilhe esses dados com outras pessoas.',
      ]);

      final mensagem = linhas.join('\n');

      final destinos = <Map<String, String>>[];

      if (_temContatoValido(contatoAlunoAtual)) {
        destinos.add({'label': 'Aluno', 'numero': contatoAlunoAtual});
      }

      if (_temContatoValido(contatoResponsavelAtual) &&
          _limparNumeroContato(contatoResponsavelAtual) !=
              _limparNumeroContato(contatoAlunoAtual)) {
        destinos.add({
          'label': nomeResponsavel.trim().isNotEmpty
              ? nomeResponsavel
              : 'Responsável',
          'numero': contatoResponsavelAtual!,
        });
      }

      if (destinos.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nenhum WhatsApp válido cadastrado para o aluno ou responsável.',
            ),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: context.uai.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
            ),
            title: Row(
              children: [
                Icon(Icons.school_rounded, color: context.uai.associacao),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enviar acesso da Área do Aluno',
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escolha para quem enviar as instruções de acesso:',
                  style: TextStyle(color: context.uai.textSecondary),
                ),
                SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.uai.associacao.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: context.uai.associacao.withOpacity(0.16),
                    ),
                  ),
                  child: Text(
                    'Iniciais: $iniciais\nData: $dataNascimento${exigeTelefone ? '\nFinal do telefone: $telefoneFinal' : ''}',
                    style: TextStyle(
                      color: context.uai.associacao,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCELAR'),
              ),
              ...destinos.map((destino) {
                return ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _abrirWhatsApp(
                      destino['numero']!,
                      mensagem: mensagem,
                    );
                  },
                  icon: Icon(Icons.send_rounded, size: 18),
                  label: Text(destino['label']!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: destino['label'] == 'Aluno'
                        ? context.uai.success
                        : context.uai.info,
                    foregroundColor: _readableOn(
                      destino['label'] == 'Aluno'
                          ? context.uai.success
                          : context.uai.info,
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar acesso da Área do Aluno: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  //  FUNÇÕES DE GERENCIAMENTO COM VALIDAÇÃO DE PERMISSÃO E INTERNET
  Future<void> _editarAluno(BuildContext context) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_editar_aluno',
      acao: 'editar informações do aluno',
    );

    if (!temPermissao || !mounted) return;

    //  VERIFICAR O PESO_PERMISSAO DO USUÁRIO
    int pesoPermissao = 0;

    try {
      if (_currentUserId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(_currentUserId)
            .get(GetOptions(source: Source.cache));

        if (userDoc.exists) {
          pesoPermissao = userDoc.data()?['peso_permissao'] as int? ?? 0;
        }
      }
    } catch (e) {
      print('Erro ao verificar peso_permissao: $e');
    }

    // ✓ REDIRECIONAMENTO BASEADO NO PESO
    if (pesoPermissao >= 100) {
      print('✓ Redirecionando para EditarAlunoScreen (peso: $pesoPermissao)');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditarAlunoScreen(alunoId: widget.alunoId),
        ),
      ).then((_) {
        _carregarDadosAluno(forcarServidor: true);
      });
    } else {
      print(
        'Redirecionando para CadastroAlunoTurmaScreen (peso: $pesoPermissao)',
      );

      try {
        final alunoDoc = await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .get(GetOptions(source: Source.cache));

        if (alunoDoc.exists) {
          final alunoData = alunoDoc.data()!;
          final academiaId = alunoData['academia_id'] as String? ?? '';
          final academiaNome = alunoData['academia'] as String? ?? '';
          final turmaId = alunoData['turma_id'] as String? ?? '';
          final turmaNome = alunoData['turma'] as String? ?? '';

          if (academiaId.isEmpty) {
            print(
              'Aviso: Academia não encontrada, redirecionando para EditarAlunoScreen',
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    EditarAlunoScreen(alunoId: widget.alunoId),
              ),
            ).then((_) {
              _carregarDadosAluno(forcarServidor: true);
            });
            return;
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CadastroAlunoTurmaScreen(
                alunoId: widget.alunoId,
                turmaId: turmaId,
                turmaNome: turmaNome,
                academiaId: academiaId,
                academiaNome: academiaNome,
              ),
            ),
          ).then((_) {
            _carregarDadosAluno(forcarServidor: true);
          });
        } else {
          print(
            'Aviso: Aluno não encontrado, redirecionando para EditarAlunoScreen',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditarAlunoScreen(alunoId: widget.alunoId),
            ),
          ).then((_) {
            _carregarDadosAluno(forcarServidor: true);
          });
        }
      } catch (e) {
        print('Erro ao buscar dados do aluno: $e');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados. Usando editor completo.'),
            backgroundColor: context.uai.warning,
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditarAlunoScreen(alunoId: widget.alunoId),
          ),
        ).then((_) {
          _carregarDadosAluno(forcarServidor: true);
        });
      }
    }
  }

  List<_MotivoAlunoStatus> _motivosDesativacaoAluno() {
    final t = context.uai;
    return [
      _MotivoAlunoStatus(
        id: 'longo_periodo_inatividade',
        titulo: 'Longo período de inatividade',
        descricao: 'Aluno ficou muito tempo sem frequentar as aulas.',
        icone: Icons.schedule_rounded,
        cor: t.warning,
      ),
      _MotivoAlunoStatus(
        id: 'aluno_nao_deseja_continuar',
        titulo: 'Aluno informou que não deseja continuar',
        descricao: 'Saída solicitada pelo próprio aluno.',
        icone: Icons.person_remove_alt_1_rounded,
        cor: t.error,
      ),
      _MotivoAlunoStatus(
        id: 'responsavel_solicitou_saida',
        titulo: 'Responsável',
        descricao: 'Saída solicitada pelo responsável.',
        icone: Icons.family_restroom_rounded,
        cor: t.info,
      ),
      _MotivoAlunoStatus(
        id: 'mudanca_cidade_endereco',
        titulo: 'Mudança de cidade/endereço',
        descricao: 'Aluno mudou de localidade ou endereço.',
        icone: Icons.location_city_rounded,
        cor: t.associacao,
      ),
      _MotivoAlunoStatus(
        id: 'incompatibilidade_horario',
        titulo: 'Incompatibilidade de horário',
        descricao: 'Horários atuais não atendem o aluno.',
        icone: Icons.event_busy_rounded,
        cor: t.warning,
      ),
      _MotivoAlunoStatus(
        id: 'questoes_pessoais_familiares',
        titulo: 'Questões pessoais ou familiares',
        descricao: 'Pausa por situação pessoal ou familiar.',
        icone: Icons.home_rounded,
        cor: t.info,
      ),
      _MotivoAlunoStatus(
        id: 'motivo_saude',
        titulo: 'Motivo de saúde',
        descricao: 'Afastamento por motivo de saúde.',
        icone: Icons.health_and_safety_rounded,
        cor: t.error,
      ),
      _MotivoAlunoStatus(
        id: 'comportamento_inadequado',
        titulo: 'Comportamento inadequado/descumprimento de regras',
        descricao: 'Desativação por regras internas.',
        icone: Icons.gavel_rounded,
        cor: t.error,
      ),
      _MotivoAlunoStatus(
        id: 'transferido_outro_grupo',
        titulo: 'Transferido para outro grupo/projeto',
        descricao: 'Aluno seguiu para outro grupo ou projeto.',
        icone: Icons.swap_horiz_rounded,
        cor: t.success,
      ),
      _MotivoAlunoStatus(
        id: 'outro',
        titulo: 'Outro motivo',
        descricao: 'Use a observação para detalhar internamente.',
        icone: Icons.more_horiz_rounded,
        cor: t.textMuted,
      ),
    ];
  }

  List<Map<String, String>> _destinosWhatsAppAluno(
      Map<String, dynamic> alunoData,
      ) {
    final contatoAluno = alunoData['contato_aluno']?.toString();
    final contatoResponsavel = alunoData['contato_responsavel']?.toString();
    final destinos = <Map<String, String>>[];

    if (_temContatoValido(contatoAluno)) {
      destinos.add({'id': 'aluno', 'label': 'Aluno', 'numero': contatoAluno!});
    }

    if (_temContatoValido(contatoResponsavel) &&
        _limparNumeroContato(contatoResponsavel) !=
            _limparNumeroContato(contatoAluno)) {
      destinos.add({
        'id': 'responsavel',
        'label': 'Responsável',
        'numero': contatoResponsavel!,
      });
    }

    if (destinos.length > 1) {
      destinos.add({'id': 'ambos', 'label': 'Ambos', 'numero': ''});
    }

    return destinos;
  }

  Future<_DesativacaoAlunoPayload?> _mostrarDialogDesativacaoAluno(
      Map<String, dynamic> alunoData,
      ) async {
    final motivos = _motivosDesativacaoAluno();
    final destinos = _destinosWhatsAppAluno(alunoData);
    final observacaoController = TextEditingController();
    _MotivoAlunoStatus? motivoSelecionado;
    var enviarWhatsApp = destinos.isNotEmpty;
    var destinoWhatsApp = destinos.isNotEmpty
        ? destinos.first['id']!
        : 'nenhum';

    final result = await showModalBottomSheet<_DesativacaoAlunoPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final t = context.uai;
            final nome = alunoData['nome']?.toString() ?? 'Aluno';
            final turma = alunoData['turma']?.toString();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_off_rounded, color: t.warning),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Desativar aluno',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.warning.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: t.warning.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            'Aluno: $nome${turma?.isNotEmpty == true ? '\nTurma atual: $turma' : ''}\nO aluno será removido da turma atual e ficará como INATIVO(A).',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Motivo da desativação',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...motivos.map((motivo) {
                          final selected = motivoSelecionado?.id == motivo.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setSheetState(
                                    () => motivoSelecionado = motivo,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? motivo.cor.withOpacity(0.12)
                                      : t.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? motivo.cor.withOpacity(0.55)
                                        : t.border,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(motivo.icone, color: motivo.cor),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            motivo.titulo,
                                            style: TextStyle(
                                              color: t.textPrimary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            motivo.descricao,
                                            style: TextStyle(
                                              color: t.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Radio<String>(
                                      value: motivo.id,
                                      groupValue: motivoSelecionado?.id,
                                      onChanged: (_) => setSheetState(
                                            () => motivoSelecionado = motivo,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        TextField(
                          controller: observacaoController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Observação interna (opcional)',
                            filled: true,
                            fillColor: t.card,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            value: enviarWhatsApp,
                            onChanged: destinos.isEmpty
                                ? null
                                : (value) => setSheetState(
                                  () => enviarWhatsApp = value ?? false,
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Enviar aviso por WhatsApp após desativar',
                            ),
                            subtitle: destinos.isEmpty
                                ? const Text(
                              'Nenhum contato válido cadastrado.',
                            )
                                : null,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        if (enviarWhatsApp && destinos.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: destinos.map((destino) {
                              return ChoiceChip(
                                selected: destinoWhatsApp == destino['id'],
                                label: Text(destino['label']!),
                                onSelected: (_) => setSheetState(
                                      () => destinoWhatsApp = destino['id']!,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (motivoSelecionado == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Selecione um motivo para desativar.',
                                    ),
                                    backgroundColor: t.warning,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(
                                context,
                                _DesativacaoAlunoPayload(
                                  motivo: motivoSelecionado!,
                                  observacao: observacaoController.text.trim(),
                                  enviarWhatsApp:
                                  enviarWhatsApp && destinos.isNotEmpty,
                                  destinoWhatsApp: destinoWhatsApp,
                                ),
                              );
                            },
                            icon: const Icon(Icons.person_off_rounded),
                            label: const Text('DESATIVAR ALUNO'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.warning,
                              foregroundColor: _readableOn(t.warning),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    observacaoController.dispose();
    return result;
  }

  Future<_UsuarioAuditoriaAluno> _dadosUsuarioAuditoriaAtual() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');

    var nome = user.displayName ?? user.email ?? 'Usuário';
    var email = user.email ?? '';

    final doc = await _firestore.collection('usuarios').doc(user.uid).get();
    final data = doc.data();
    if (data != null) {
      nome =
          data['nome_completo']?.toString() ?? data['nome']?.toString() ?? nome;
      email = data['email']?.toString() ?? email;
    }

    return _UsuarioAuditoriaAluno(uid: user.uid, nome: nome, email: email);
  }

  Future<void> _registrarWhatsAppDesativacao(
      String alunoId,
      _DesativacaoAlunoPayload payload,
      ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('alunos').doc(alunoId).set({
      'whatsapp_desativacao_ultimo_envio_em': FieldValue.serverTimestamp(),
      'whatsapp_desativacao_ultimo_envio_por_uid': user.uid,
      'whatsapp_desativacao_destino': payload.destinoWhatsApp,
      'whatsapp_desativacao_motivo_id': payload.motivo.id,
    }, SetOptions(merge: true));
  }

  Future<void> _enviarWhatsAppDesativacao(
      Map<String, dynamic> alunoData,
      _DesativacaoAlunoPayload payload,
      ) async {
    if (!payload.enviarWhatsApp) return;

    final destinos = _destinosWhatsAppAluno(alunoData).where((destino) {
      if (payload.destinoWhatsApp == 'ambos') {
        return destino['id'] == 'aluno' || destino['id'] == 'responsavel';
      }
      return destino['id'] == payload.destinoWhatsApp;
    }).toList();

    if (destinos.isEmpty) return;

    final nome = alunoData['nome']?.toString() ?? 'Aluno';
    final mensagem = [
      'Olá, tudo bem?',
      '',
      'Informamos que o cadastro de $nome foi desativado no sistema da UAI Capoeira.',
      '',
      'Motivo: ${payload.motivo.titulo}',
      '',
      'Essa desativação apenas organiza o controle interno do grupo. Caso deseje retornar às atividades futuramente, entre em contato com a coordenação.',
      '',
      'Atenciosamente,',
      'UAI Capoeira',
    ].join('\n');

    for (final destino in destinos) {
      await _abrirWhatsApp(destino['numero']!, mensagem: mensagem);
    }
  }

  Future<void> _desativarAluno(BuildContext context, String alunoId) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_desativar_aluno',
      acao: 'desativar aluno',
    );

    if (!temPermissao || !mounted) return;

    final alunoSnap = await _firestore
        .collection('alunos')
        .doc(alunoId)
        .get(GetOptions(source: Source.server));
    if (!mounted) return;

    if (!alunoSnap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aluno não encontrado.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    final dadosAntes = Map<String, dynamic>.from(alunoSnap.data() ?? {});
    final payload = await _mostrarDialogDesativacaoAluno(dadosAntes);
    if (payload == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: t.warning),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Desativando aluno e registrando histórico...',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final usuario = await _dadosUsuarioAuditoriaAtual();
      final turmasQuery = await _firestore
          .collection('turmas')
          .where('alunos', arrayContains: alunoId)
          .get(GetOptions(source: Source.server));

      final alunoRef = _firestore.collection('alunos').doc(alunoId);
      final batch = _firestore.batch();
      for (final turmaDoc in turmasQuery.docs) {
        batch.update(turmaDoc.reference, {
          'alunos': FieldValue.arrayRemove([alunoId]),
          'atualizado_em': FieldValue.serverTimestamp(),
        });
      }

      final turmaAnteriorId = dadosAntes['turma_id']?.toString();
      final turmaAnteriorNome = dadosAntes['turma']?.toString();
      final academiaId = dadosAntes['academia_id']?.toString();
      final academiaNome = dadosAntes['academia']?.toString();
      final updateAluno = <String, dynamic>{
        'status_atividade': 'INATIVO(A)',
        'data_desativacao': FieldValue.serverTimestamp(),
        'turma': null,
        'turma_id': null,
        'desativado_em': FieldValue.serverTimestamp(),
        'desativado_por_uid': usuario.uid,
        'desativado_por_nome': usuario.nome,
        'desativado_por_email': usuario.email,
        'desativacao_motivo_id': payload.motivo.id,
        'desativacao_motivo_titulo': payload.motivo.titulo,
        'desativacao_observacao': payload.observacao.isEmpty
            ? null
            : payload.observacao,
        'desativacao_origem': 'aluno_detalhe_screen',
        'desativacao_turma_anterior_id': turmaAnteriorId,
        'desativacao_turma_anterior_nome': turmaAnteriorNome,
        'desativacao_academia_id': academiaId,
        'desativacao_academia_nome': academiaNome,
        'ultima_edicao_em': FieldValue.serverTimestamp(),
        'ultima_edicao_por_uid': usuario.uid,
        'ultima_edicao_por_nome': usuario.nome,
        'ultima_edicao_por_email': usuario.email,
        'ultima_edicao_tipo': 'desativacao',
        'ultima_edicao_subtipo': 'desativacao_aluno',
        'ultima_edicao_origem': 'aluno_detalhe_screen',
        'ultima_edicao_resumo': 'Aluno desativado: ${payload.motivo.titulo}',
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      batch.update(alunoRef, updateAluno);
      await batch.commit();
      if (turmaAnteriorId != null && turmaAnteriorId.isNotEmpty) {
        await _atualizarContadorTurmaAuditoria(turmaAnteriorId);
      }

      final dadosDepois = Map<String, dynamic>.from(dadosAntes)
        ..addAll({
          'status_atividade': 'INATIVO(A)',
          'turma': null,
          'turma_id': null,
        });
      await AlunoHistoricoEdicaoService().registrarDesativacaoAluno(
        alunoId: alunoId,
        dadosAntes: dadosAntes,
        dadosDepois: dadosDepois,
        motivoId: payload.motivo.id,
        motivoTitulo: payload.motivo.titulo,
        observacao: payload.observacao,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aluno desativado com sucesso.'),
          backgroundColor: context.uai.success,
        ),
      );

      await _carregarDadosAluno(forcarServidor: true);

      if (payload.enviarWhatsApp) {
        await _enviarWhatsAppDesativacao(dadosAntes, payload);
        await _registrarWhatsAppDesativacao(alunoId, payload);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao desativar aluno: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Future<void> _atualizarContadorTurmaAuditoria(String turmaId) async {
    if (turmaId.trim().isEmpty) return;
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get(GetOptions(source: Source.server));
      final alunosCount = snapshot.docs.length;
      await _firestore.collection('turmas').doc(turmaId).set({
        'alunos_count': alunosCount,
        'alunos_ativos': alunosCount,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma na auditoria: $e');
    }
  }

  Future<void> _ativarAluno(
      BuildContext context,
      String alunoId,
      Map<String, dynamic> alunoData,
      ) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_ativar_alunos',
      acao: 'ativar aluno',
    );

    if (!temPermissao || !mounted) return;

    final academiaId = alunoData['academia_id'] as String?;
    if (academiaId == null || academiaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Este aluno não está vinculado a uma academia.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(GetOptions(source: Source.server));

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não há turmas ativas disponíveis nesta academia.'),
            backgroundColor: context.uai.error,
          ),
        );
      }
      return;
    }

    turmasAtivas.sort((a, b) {
      final nomeA = a['nome'] as String? ?? '';
      final nomeB = b['nome'] as String? ?? '';
      return nomeA.compareTo(nomeB);
    });

    final turmas = await Future.wait(
      turmasAtivas.map((doc) async {
        final dados = doc.data() as Map<String, dynamic>;
        final capacidadeMaxima = dados['capacidade_maxima'] as int? ?? 0;
        final alunos = (dados['alunos'] as List? ?? []).length;
        final alunosCount = dados['alunos_count'] as int? ?? 0;
        final totalAlunos = alunos > alunosCount ? alunos : alunosCount;
        final temVaga = totalAlunos < capacidadeMaxima;

        return {
          'id': doc.id,
          'nome': dados['nome'] ?? 'Sem nome',
          'horario':
          dados['horario_display'] ??
              dados['horario_inicio'] ??
              'Sem horário',
          'dias':
          (dados['dias_semana_display'] as List?)?.join(', ') ??
              (dados['dias_semana'] as List?)?.join(', ') ??
              'Sem dias definidos',
          'nivel': dados['nivel'] ?? 'Não especificado',
          'faixa_etaria': dados['faixa_etaria'] ?? 'Não especificada',
          'capacidade_maxima': capacidadeMaxima,
          'total_alunos': totalAlunos,
          'tem_vaga': temVaga,
        };
      }),
    );

    String? selectedTurmaId;
    String? selectedTurmaNome;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: context.uai.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
            ),
            title: Text(
              'Ativar Aluno',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selecione a turma para vincular o aluno:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.uai.textPrimary,
                      ),
                    ),
                    SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima =
                      turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        color: isSelected
                            ? Color.alphaBlend(
                          context.uai.error.withOpacity(0.08),
                          context.uai.card,
                        )
                            : !temVaga
                            ? context.uai.cardAlt
                            : context.uai.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? context.uai.error
                                : !temVaga
                                ? context.uai.textMuted
                                : context.uai.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: temVaga
                              ? () {
                            setState(() {
                              selectedTurmaId = turma['id'];
                              selectedTurmaNome = turma['nome'];
                            });
                          }
                              : null,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? context.uai.primary
                                        : !temVaga
                                        ? context.uai.textMuted
                                        : context.uai.textMuted,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              turma['nome']!,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? context.uai.primary
                                                    : !temVaga
                                                    ? context.uai.textSecondary
                                                    : context.uai.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (!temVaga)
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.error
                                                    .withOpacity(0.16),
                                                borderRadius:
                                                BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.uai.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        turma['horario']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: !temVaga
                                              ? context.uai.textMuted
                                              : context.uai.textMuted,
                                        ),
                                      ),
                                      Text(
                                        turma['dias']!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: !temVaga
                                              ? context.uai.textMuted
                                              : context.uai.textMuted,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _buildTurmaChip(
                                            label: turma['nivel']!,
                                            color: context.uai.info.withOpacity(
                                              0.16,
                                            ),
                                            textColor: context.uai.info,
                                          ),
                                          SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label: turma['faixa_etaria']!,
                                            color: context.uai.success
                                                .withOpacity(0.16),
                                            textColor: context.uai.success,
                                          ),
                                          SizedBox(width: 6),
                                          _buildTurmaChip(
                                            label:
                                            '$totalAlunos/$capacidadeMaxima alunos',
                                            color: temVaga
                                                ? context.uai.warning
                                                .withOpacity(0.16)
                                                : context.uai.error.withOpacity(
                                              0.16,
                                            ),
                                            textColor: temVaga
                                                ? context.uai.warning
                                                : context.uai.error,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedTurmaId != null
                    ? () async {
                  final temVaga = await _verificarCapacidadeTurma(
                    selectedTurmaId!,
                  );

                  if (!temVaga) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Esta turma não tem mais vagas disponíveis.',
                          ),
                          backgroundColor: context.uai.error,
                        ),
                      );
                    }
                    return;
                  }

                  await _firestore
                      .collection('turmas')
                      .doc(selectedTurmaId!)
                      .update({
                    'alunos': FieldValue.arrayUnion([widget.alunoId]),
                  });

                  final alunoRef = _firestore
                      .collection('alunos')
                      .doc(widget.alunoId);
                  final turmaRef = _firestore
                      .collection('turmas')
                      .doc(selectedTurmaId!);
                  final batch = _firestore.batch();

                  batch.set(turmaRef, {
                    'alunos': FieldValue.arrayUnion([widget.alunoId]),
                    'atualizado_em': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));

                  batch.update(alunoRef, {
                    'status_atividade': 'ATIVO(A)',
                    'turma_id': selectedTurmaId,
                    'turma': selectedTurmaNome,
                    'data_ativacao': FieldValue.serverTimestamp(),
                    'data_desativacao': null,
                    'atualizado_em': FieldValue.serverTimestamp(),
                  });

                  await batch.commit();
                  await _atualizarContadorTurmaAuditoria(
                    selectedTurmaId!,
                  );
                  await _cache.invalidateAluno(widget.alunoId);

                  if (!mounted) return;
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Aluno ativado com sucesso!'),
                      backgroundColor: context.uai.success,
                    ),
                  );

                  await _carregarDadosAluno(forcarServidor: true);
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.success,
                  foregroundColor: _readableOn(context.uai.success),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Ativar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _verificarCapacidadeTurma(String turmaId) async {
    try {
      final turmaDoc = await _firestore
          .collection('turmas')
          .doc(turmaId)
          .get(GetOptions(source: Source.server));

      if (!turmaDoc.exists) {
        return false;
      }

      final dadosTurma = turmaDoc.data()!;
      final capacidadeMaxima = dadosTurma['capacidade_maxima'] as int? ?? 0;
      final alunos = (dadosTurma['alunos'] as List? ?? []).length;
      final alunosCount = dadosTurma['alunos_count'] as int? ?? 0;

      final totalAlunos = alunos > alunosCount ? alunos : alunosCount;

      if (capacidadeMaxima <= 0) return true;
      return totalAlunos < capacidadeMaxima;
    } catch (e) {
      print('Erro ao verificar capacidade da turma: $e');
      return false;
    }
  }

  Future<void> _mudarTurma(
      BuildContext context,
      String alunoId,
      Map<String, dynamic> alunoData,
      ) async {
    final temPermissao = await _verificarPermissaoEOnline(
      'pode_mudar_turma',
      acao: 'mudar aluno de turma',
    );

    if (!temPermissao || !mounted) return;

    // Sempre busca o aluno no servidor para não usar turma antiga vinda do cache.
    final alunoSnapAtual = await _firestore
        .collection('alunos')
        .doc(alunoId)
        .get(const GetOptions(source: Source.server));

    if (!mounted) return;

    if (!alunoSnapAtual.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aluno não encontrado.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    final dadosAntes = Map<String, dynamic>.from(alunoSnapAtual.data() ?? {});
    final academiaId = dadosAntes['academia_id']?.toString();
    final academiaNome = dadosAntes['academia']?.toString();
    final turmaAtualId = dadosAntes['turma_id']?.toString();
    final turmaAtualNome = dadosAntes['turma']?.toString();

    if (academiaId == null || academiaId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Este aluno não está vinculado a uma academia.',
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
      return;
    }

    final turmasSnapshot = await _firestore
        .collection('turmas')
        .where('academia_id', isEqualTo: academiaId)
        .get(const GetOptions(source: Source.server));

    if (!mounted) return;

    final turmasAtivas = turmasSnapshot.docs.where((doc) {
      final status = doc.data()['status'] as String?;
      return status != null && status.toUpperCase() == 'ATIVA';
    }).toList();

    if (turmasAtivas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Não há turmas ativas disponíveis nesta academia.',
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
      return;
    }

    turmasAtivas.sort((a, b) {
      final nomeA = a.data()['nome'] as String? ?? '';
      final nomeB = b.data()['nome'] as String? ?? '';
      return nomeA.compareTo(nomeB);
    });

    final turmas = await Future.wait(
      turmasAtivas.map((doc) async {
        final dados = doc.data();
        final isTurmaAtual = doc.id == turmaAtualId;
        final capacidadeMaxima = dados['capacidade_maxima'] as int? ?? 0;
        final alunos = (dados['alunos'] as List? ?? []).length;
        final alunosCount = dados['alunos_count'] as int? ?? 0;
        final alunosAtivos = dados['alunos_ativos'] as int? ?? 0;
        final totalAlunos = alunosAtivos > 0
            ? alunosAtivos
            : (alunos > alunosCount ? alunos : alunosCount);
        final temVaga =
            capacidadeMaxima <= 0 ||
                totalAlunos < capacidadeMaxima ||
                isTurmaAtual;

        return {
          'id': doc.id,
          'nome': dados['nome'] ?? 'Sem nome',
          'horario':
          dados['horario_display'] ??
              dados['horario_inicio'] ??
              'Sem horário',
          'dias':
          (dados['dias_semana_display'] as List?)?.join(', ') ??
              (dados['dias_semana'] as List?)?.join(', ') ??
              'Sem dias definidos',
          'nivel': dados['nivel'] ?? 'Não especificado',
          'faixa_etaria': dados['faixa_etaria'] ?? 'Não especificada',
          'capacidade_maxima': capacidadeMaxima,
          'total_alunos': totalAlunos,
          'tem_vaga': temVaga,
          'isTurmaAtual': isTurmaAtual,
        };
      }),
    );

    String? selectedTurmaId = turmaAtualId;
    String? selectedTurmaNome = turmaAtualNome;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: context.uai.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.cardRadius),
            ),
            title: Text(
              'Mudar de Turma',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selecione a nova turma para o aluno:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.uai.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...turmas.map((turma) {
                      final isSelected = selectedTurmaId == turma['id'];
                      final isTurmaAtual = turma['isTurmaAtual'] == true;
                      final temVaga = turma['tem_vaga'] as bool;
                      final capacidadeMaxima =
                      turma['capacidade_maxima'] as int;
                      final totalAlunos = turma['total_alunos'] as int;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSelected
                            ? Color.alphaBlend(
                          context.uai.error.withOpacity(0.08),
                          context.uai.card,
                        )
                            : isTurmaAtual
                            ? context.uai.cardAlt
                            : !temVaga
                            ? context.uai.cardAlt
                            : context.uai.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected
                                ? context.uai.error
                                : isTurmaAtual
                                ? context.uai.textMuted
                                : !temVaga
                                ? context.uai.textMuted
                                : context.uai.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: temVaga || isTurmaAtual
                              ? () {
                            setState(() {
                              selectedTurmaId = turma['id'] as String?;
                              selectedTurmaNome = turma['nome']
                                  ?.toString();
                            });
                          }
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? context.uai.primary
                                        : isTurmaAtual
                                        ? context.uai.textSecondary
                                        : !temVaga
                                        ? context.uai.textMuted
                                        : context.uai.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              turma['nome']?.toString() ??
                                                  'Sem nome',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? context.uai.primary
                                                    : isTurmaAtual
                                                    ? context.uai.textPrimary
                                                    : !temVaga
                                                    ? context.uai.textSecondary
                                                    : context.uai.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isTurmaAtual)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.border,
                                                borderRadius:
                                                BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'ATUAL',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _onCardMuted(context),
                                                ),
                                              ),
                                            ),
                                          if (!temVaga && !isTurmaAtual)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: context.uai.error
                                                    .withOpacity(0.16),
                                                borderRadius:
                                                BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'LOTADA',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: context.uai.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        turma['horario']?.toString() ??
                                            'Sem horário',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isTurmaAtual
                                              ? context.uai.textSecondary
                                              : context.uai.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        turma['dias']?.toString() ??
                                            'Sem dias definidos',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isTurmaAtual
                                              ? context.uai.textSecondary
                                              : context.uai.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label:
                                              turma['nivel']?.toString() ??
                                                  'N/A',
                                              color: context.uai.info
                                                  .withOpacity(0.16),
                                              textColor: context.uai.info,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label:
                                              turma['faixa_etaria']
                                                  ?.toString() ??
                                                  'N/A',
                                              color: context.uai.success
                                                  .withOpacity(0.16),
                                              textColor: context.uai.success,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: _buildTurmaChip(
                                              label: capacidadeMaxima <= 0
                                                  ? '$totalAlunos alunos'
                                                  : '$totalAlunos/$capacidadeMaxima alunos',
                                              color: isTurmaAtual
                                                  ? context.uai.border
                                                  : temVaga
                                                  ? context.uai.warning
                                                  .withOpacity(0.16)
                                                  : context.uai.error
                                                  .withOpacity(0.16),
                                              textColor: isTurmaAtual
                                                  ? context.uai.textSecondary
                                                  : temVaga
                                                  ? context.uai.warning
                                                  : context.uai.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: selectedTurmaId != null
                    ? () async {
                  if (selectedTurmaId == turmaAtualId) {
                    Navigator.pop(context);
                    return;
                  }

                  try {
                    final temVaga = await _verificarCapacidadeTurma(
                      selectedTurmaId!,
                    );

                    if (!temVaga) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Esta turma não tem mais vagas disponíveis.',
                            ),
                            backgroundColor: context.uai.error,
                          ),
                        );
                      }
                      return;
                    }

                    final turmaNovaId = selectedTurmaId!;
                    final turmaNovaNome = selectedTurmaNome ?? 'Sem nome';
                    final alunoRef = _firestore
                        .collection('alunos')
                        .doc(alunoId);
                    final batch = _firestore.batch();

                    if (turmaAtualId != null && turmaAtualId.isNotEmpty) {
                      batch.update(
                        _firestore.collection('turmas').doc(turmaAtualId),
                        {
                          'alunos': FieldValue.arrayRemove([alunoId]),
                          'atualizado_em': FieldValue.serverTimestamp(),
                        },
                      );
                    }

                    batch.update(
                      _firestore.collection('turmas').doc(turmaNovaId),
                      {
                        'alunos': FieldValue.arrayUnion([alunoId]),
                        'atualizado_em': FieldValue.serverTimestamp(),
                      },
                    );

                    batch.update(alunoRef, {
                      'turma_id': turmaNovaId,
                      'turma': turmaNovaNome,
                      'data_mudanca_turma': FieldValue.serverTimestamp(),
                      'atualizado_em': FieldValue.serverTimestamp(),
                    });

                    await batch.commit();

                    if (turmaAtualId != null && turmaAtualId.isNotEmpty) {
                      await _atualizarContadorTurmaAuditoria(
                        turmaAtualId,
                      );
                    }
                    await _atualizarContadorTurmaAuditoria(turmaNovaId);

                    final resumo =
                        'Mudança de turma: ${turmaAtualNome ?? 'Sem turma'} → $turmaNovaNome';
                    final dadosDepois =
                    Map<String, dynamic>.from(dadosAntes)..addAll({
                      'turma_id': turmaNovaId,
                      'turma': turmaNovaNome,
                      'academia_id': academiaId,
                      'academia': academiaNome,
                    });

                    await AlunoHistoricoEdicaoService()
                        .registrarEdicaoManual(
                      alunoId: alunoId,
                      dadosAntes: dadosAntes,
                      dadosDepois: dadosDepois,
                      origem: 'aluno_detalhe_mudar_turma',
                      subtipoEdicao: 'mudanca_turma',
                      resumoPersonalizado: resumo,
                    );

                    await _cache.invalidateAluno(alunoId);

                    if (!mounted) return;
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Aluno transferido para nova turma com sucesso!',
                        ),
                        backgroundColor: context.uai.success,
                      ),
                    );

                    await _carregarDadosAluno(forcarServidor: true);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao mudar turma: $e'),
                          backgroundColor: context.uai.error,
                        ),
                      );
                    }
                  }
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
                  foregroundColor: _readableOn(context.uai.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTurmaChip({
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  bool _isAlunoAtivo(String? statusAtividade) {
    return statusAtividade == 'ATIVO(A)' || statusAtividade == 'ATIVO';
  }

  Widget _buildWhatsAppIcon({required bool enabled, required Color color}) {
    return SvgPicture.asset(
      'assets/images/whatsapp.svg',
      width: 20,
      height: 20,
      color: enabled ? color : context.uai.textMuted,
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: context.uai.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (label.contains('WhatsApp'))
                  _buildWhatsAppIcon(enabled: onPressed != null, color: color)
                else
                  Icon(
                    icon,
                    color: onPressed != null ? color : context.uai.textMuted,
                    size: 20,
                  ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onPressed != null
                          ? context.uai.textPrimary
                          : context.uai.textMuted,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  //  CONTATOS DE EMERGÊNCIA - UI PREMIUM
  // ============================================
  String _limparNumeroContato(String? numero) {
    if (numero == null) return '';
    return numero.replaceAll(RegExp(r'[^0-9+]'), '').trim();
  }

  bool _temContatoValido(String? numero) {
    final limpo = _limparNumeroContato(numero);
    return limpo.length >= 8;
  }

  String _formatarTelefoneVisual(String? numero) {
    final limpo = _limparNumeroContato(
      numero,
    ).replaceAll('+55', '').replaceAll('+', '');

    if (limpo.length == 11) {
      return '(${limpo.substring(0, 2)}) ${limpo.substring(2, 7)}-${limpo.substring(7)}';
    }

    if (limpo.length == 10) {
      return '(${limpo.substring(0, 2)}) ${limpo.substring(2, 6)}-${limpo.substring(6)}';
    }

    return numero?.trim().isNotEmpty == true
        ? numero!.trim()
        : 'Não cadastrado';
  }

  Future<void> _mostrarOpcoesContatoEmergencia({
    required String nomeAluno,
    required String contatoAluno,
    required String nomeResponsavel,
    required String? contatoResponsavel,
    required String nomeContatoEmergencia,
    required String contatoEmergencia,
  }) async {
    final contatos = <Map<String, dynamic>>[];

    if (_temContatoValido(contatoResponsavel)) {
      contatos.add({
        'titulo': nomeResponsavel,
        'subtitulo': 'Responsável principal',
        'numero': contatoResponsavel!,
        'cor': context.uai.error,
        'icone': Icons.family_restroom_rounded,
        'prioridade': 'PRIORIDADE 1',
      });
    }

    if (_temContatoValido(contatoEmergencia) &&
        _limparNumeroContato(contatoEmergencia) !=
            _limparNumeroContato(contatoResponsavel)) {
      contatos.add({
        'titulo': nomeContatoEmergencia,
        'subtitulo': 'Contato de emergência',
        'numero': contatoEmergencia,
        'cor': context.uai.warning,
        'icone': Icons.emergency_share_rounded,
        'prioridade': 'EMERGÊNCIA',
      });
    }

    if (_temContatoValido(contatoAluno) &&
        _limparNumeroContato(contatoAluno) !=
            _limparNumeroContato(contatoResponsavel) &&
        _limparNumeroContato(contatoAluno) !=
            _limparNumeroContato(contatoEmergencia)) {
      contatos.add({
        'titulo': nomeAluno,
        'subtitulo': 'Contato do aluno',
        'numero': contatoAluno,
        'cor': context.uai.info,
        'icone': Icons.person_rounded,
        'prioridade': 'ALUNO',
      });
    }

    if (contatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nenhum contato válido cadastrado para emergência.'),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.uai.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.uai.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.uai.error.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.sos_rounded,
                        color: context.uai.primary,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contatos de emergência',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.uai.textPrimary,
                            ),
                          ),
                          Text(
                            nomeAluno,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.uai.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                ...contatos.map((contato) {
                  final color = contato['cor'] as Color;
                  final numero = contato['numero'] as String;

                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withOpacity(0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                contato['icone'] as IconData,
                                color: _readableOn(color),
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          contato['titulo'] as String,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: _onCard(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: Text(
                                          contato['prioridade'] as String,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '${contato['subtitulo']} • ${_formatarTelefoneVisual(numero)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.uai.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _launchPhone(numero);
                                },
                                icon: Icon(Icons.call_rounded, size: 20),
                                label: Text('LIGAR AGORA'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: color,
                                  foregroundColor: _readableOn(color),
                                  padding: EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            SizedBox(
                              width: 54,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _abrirWhatsApp(
                                    numero,
                                    mensagem:
                                    'Olá, preciso falar sobre $nomeAluno.',
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _appBarBg(context),
                                  foregroundColor: _appBarFg(context),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _buildWhatsAppIcon(
                                  enabled: true,
                                  color: _appBarFg(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergencyContactsSection({
    required String nomeAluno,
    required String contatoAluno,
    required String nomeResponsavel,
    required String? contatoResponsavel,
    required String nomeContatoEmergencia,
    required String contatoEmergencia,
    required String? turmaId,
  }) {
    final contatoPrincipal = _temContatoValido(contatoResponsavel)
        ? contatoResponsavel!
        : _temContatoValido(contatoEmergencia)
        ? contatoEmergencia
        : contatoAluno;

    final nomePrincipal = _temContatoValido(contatoResponsavel)
        ? nomeResponsavel
        : _temContatoValido(contatoEmergencia)
        ? nomeContatoEmergencia
        : nomeAluno;

    final tipoPrincipal = _temContatoValido(contatoResponsavel)
        ? 'Responsável principal'
        : _temContatoValido(contatoEmergencia)
        ? 'Contato de emergência'
        : 'Aluno';

    final temPrincipal = _temContatoValido(contatoPrincipal);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.13),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: context.uai.card,
            border: Border.all(color: context.uai.error.withOpacity(0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: context.uai.primaryGradient,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _onPrimary(context).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _onPrimary(context).withOpacity(0.16),
                        ),
                      ),
                      child: Icon(
                        Icons.health_and_safety_rounded,
                        color: _onPrimary(context),
                        size: 28,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergência e contatos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _onPrimary(context),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Acesso rápido para ligar ou chamar no WhatsApp',
                            style: TextStyle(
                              fontSize: 12,
                              color: _onPrimary(context).withOpacity(0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: temPrincipal
                            ? () => _launchPhone(contatoPrincipal)
                            : null,
                        icon: Icon(
                          temPrincipal
                              ? Icons.sos_rounded
                              : Icons.phone_disabled_rounded,
                          size: 26,
                        ),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              temPrincipal
                                  ? 'LIGAR EMERGÊNCIA AGORA'
                                  : 'SEM CONTATO DE EMERGÊNCIA',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            if (temPrincipal)
                              Text(
                                '$nomePrincipal • $tipoPrincipal',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.uai.error,
                          disabledBackgroundColor: context.uai.border,
                          foregroundColor: _readableOn(context.uai.error),
                          disabledForegroundColor: context.uai.textSecondary,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: temPrincipal ? 3 : 0,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    if (temPrincipal)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.uai.error.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: context.uai.error.withOpacity(0.16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.priority_high_rounded,
                              color: context.uai.error,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Contato principal: $nomePrincipal • ${_formatarTelefoneVisual(contatoPrincipal)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.uai.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 520;
                        final responsavelCard = _buildContactPersonCard(
                          titulo: 'Responsável',
                          nome: nomeResponsavel,
                          numero: contatoResponsavel,
                          color: context.uai.primaryDark,
                          icon: Icons.family_restroom_rounded,
                          mensagemWhatsApp:
                          'Olá, preciso falar sobre $nomeAluno.',
                        );
                        final alunoCard = _buildContactPersonCard(
                          titulo: 'Aluno',
                          nome: nomeAluno,
                          numero: contatoAluno,
                          color: context.uai.info,
                          icon: Icons.person_rounded,
                          mensagemWhatsApp: 'Olá, $nomeAluno. Tudo bem?',
                        );
                        if (narrow) {
                          return Column(
                            children: [
                              responsavelCard,
                              const SizedBox(height: 10),
                              alunoCard,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: responsavelCard),
                            const SizedBox(width: 10),
                            Expanded(child: alunoCard),
                          ],
                        );
                      },
                    ),
                    if (_temContatoValido(contatoEmergencia)) ...[
                      SizedBox(height: 10),
                      _buildContactPersonCard(
                        titulo: 'Contato extra de emergência',
                        nome: nomeContatoEmergencia,
                        numero: contatoEmergencia,
                        color: context.uai.warning,
                        icon: Icons.emergency_share_rounded,
                        fullWidth: true,
                        mensagemWhatsApp:
                        'Olá, preciso falar sobre $nomeAluno.',
                      ),
                    ],
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: temPrincipal
                                ? () => _mostrarOpcoesContatoEmergencia(
                              nomeAluno: nomeAluno,
                              contatoAluno: contatoAluno,
                              nomeResponsavel: nomeResponsavel,
                              contatoResponsavel: contatoResponsavel,
                              nomeContatoEmergencia:
                              nomeContatoEmergencia,
                              contatoEmergencia: contatoEmergencia,
                            )
                                : null,
                            icon: Icon(Icons.contact_phone_rounded, size: 18),
                            label: const Text(
                              'Ver opções',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.uai.primary,
                              side: BorderSide(
                                color: context.uai.error.withOpacity(0.28),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: turmaId != null && turmaId.isNotEmpty
                                ? _firestore
                                .collection('turmas')
                                .doc(turmaId)
                                .get()
                                : null,
                            builder: (context, snapshot) {
                              String? whatsappUrl;
                              if (snapshot.hasData && snapshot.data!.exists) {
                                final turmaData =
                                snapshot.data!.data()
                                as Map<String, dynamic>?;
                                whatsappUrl =
                                turmaData?['whatsapp_url'] as String?;
                              }

                              return OutlinedButton.icon(
                                onPressed:
                                whatsappUrl != null &&
                                    whatsappUrl.isNotEmpty
                                    ? () => _convidarParaGrupo(
                                  context,
                                  whatsappUrl,
                                  contatoAluno,
                                  contatoResponsavel,
                                )
                                    : null,
                                icon: Icon(Icons.group_add_rounded, size: 18),
                                label: const Text(
                                  'Grupo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.uai.warning,
                                  side: BorderSide(
                                    color: context.uai.warning.withOpacity(
                                      0.28,
                                    ),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    _buildAreaAlunoAcessoButton(
                      nomeAluno: nomeAluno,
                      contatoAluno: contatoAluno,
                      contatoResponsavel: contatoResponsavel,
                      nomeResponsavel: nomeResponsavel,
                    ),
                    if (!temPrincipal) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.uai.warning.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: context.uai.warning.withOpacity(0.28),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: context.uai.warning,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cadastre pelo menos um telefone para emergências.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAreaAlunoAcessoButton({
    required String nomeAluno,
    required String contatoAluno,
    required String? contatoResponsavel,
    required String nomeResponsavel,
  }) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final visivel = data['visivel_site'] == true;

        if (!visivel) return SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(top: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _enviarAcessoAreaAlunoWhatsApp(
                nomeAluno: nomeAluno,
                contatoAluno: contatoAluno,
                contatoResponsavel: contatoResponsavel,
                nomeResponsavel: nomeResponsavel,
              ),
              icon: Icon(Icons.school_rounded, size: 18),
              label: const Text(
                'Enviar acesso da Área do Aluno',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.uai.associacao,
                side: BorderSide(
                  color: context.uai.associacao.withOpacity(0.35),
                ),
                padding: EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactPersonCard({
    required String titulo,
    required String nome,
    required String? numero,
    required Color color,
    required IconData icon,
    required String mensagemWhatsApp,
    bool fullWidth = false,
  }) {
    final temNumero = _temContatoValido(numero);

    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: temNumero ? color.withOpacity(0.07) : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: temNumero ? color.withOpacity(0.18) : context.uai.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: temNumero ? color : context.uai.textMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: _readableOn(temNumero ? color : context.uai.textMuted),
                  size: 17,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 11,
                        color: temNumero ? color : context.uai.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      nome.trim().isNotEmpty ? nome : titulo,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _onCard(context),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            _formatarTelefoneVisual(numero),
            style: TextStyle(
              fontSize: 12,
              color: temNumero
                  ? context.uai.textPrimary
                  : context.uai.textMuted,
              fontWeight: temNumero ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: temNumero ? () => _launchPhone(numero!) : null,
                  icon: Icon(Icons.call_rounded, size: 16),
                  label: Text(
                    fullWidth ? 'Ligar' : 'Ligar',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    disabledBackgroundColor: context.uai.border,
                    foregroundColor: _readableOn(color),
                    disabledForegroundColor: context.uai.textSecondary,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 40,
                child: ElevatedButton(
                  onPressed: temNumero
                      ? () =>
                      _abrirWhatsApp(numero!, mensagem: mensagemWhatsApp)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.success,
                    disabledBackgroundColor: context.uai.border,
                    foregroundColor: _readableOn(context.uai.success),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _buildWhatsAppIcon(
                    enabled: temNumero,
                    color: _readableOn(context.uai.success),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getMonitorColor(String monitor) {
    final lowerMonitor = monitor.toLowerCase();
    if (lowerMonitor.contains('azul')) return context.uai.info;
    if (lowerMonitor.contains('roxo') || lowerMonitor.contains('roxa'))
      return context.uai.associacao;
    if (lowerMonitor.contains('vermelho') || lowerMonitor.contains('vermelha'))
      return context.uai.error;
    if (lowerMonitor.contains('verde')) return context.uai.success;
    if (lowerMonitor.contains('amarelo') || lowerMonitor.contains('amarela'))
      return context.uai.warning;
    if (lowerMonitor.contains('branco') || lowerMonitor.contains('branca'))
      return context.uai.border;
    if (lowerMonitor.contains('marrom')) return context.uai.warning;
    return context.uai.textMuted;
  }

  String _formatarDataHoraAuditoria(dynamic value) {
    if (value == null) return 'Não informado';
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (date == null) return value.toString();
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  Widget _buildAuditoriaFichaCard(Map<String, dynamic> data) {
    final t = context.uai;
    final ultimaEdicao = data['ultima_edicao_em'];
    final nomeUsuario = data['ultima_edicao_por_nome']?.toString();
    final tipo = data['ultima_edicao_tipo']?.toString();
    final subtipo = data['ultima_edicao_subtipo']?.toString();
    final resumo = data['ultima_edicao_resumo']?.toString();
    final motivoAuditoria = tipo == 'desativacao'
        ? data['desativacao_motivo_titulo']?.toString()
        : tipo == 'reativacao'
        ? data['reativacao_motivo_titulo']?.toString()
        : null;
    final temHistorico =
        ultimaEdicao != null ||
            (nomeUsuario != null && nomeUsuario.isNotEmpty) ||
            (resumo != null && resumo.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.manage_history_rounded, color: t.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Auditoria da ficha',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistoricoEdicoesAlunoScreen(
                          alunoId: widget.alunoId,
                          alunoNome: data['nome']?.toString() ?? 'Aluno',
                        ),
                      ),
                    );
                    if (mounted) _carregarDadosAluno();
                  },
                  icon: const Icon(Icons.history_edu_rounded, size: 18),
                  label: const Text('Ver histórico'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!temHistorico)
              Text(
                'Sem histórico de edição registrado.',
                style: TextStyle(color: t.textSecondary),
              )
            else ...[
              _auditoriaLinha(
                Icons.schedule_rounded,
                'Última edição',
                _formatarDataHoraAuditoria(ultimaEdicao),
              ),
              const SizedBox(height: 6),
              _auditoriaLinha(
                Icons.person_rounded,
                'Por',
                nomeUsuario?.isNotEmpty == true
                    ? nomeUsuario!
                    : 'Não informado',
              ),
              const SizedBox(height: 6),
              _auditoriaLinha(
                Icons.category_rounded,
                'Tipo',
                AlunoHistoricoEdicaoService.tipoLegivel(tipo, subtipo: subtipo),
              ),
              if (resumo != null && resumo.isNotEmpty) ...[
                const SizedBox(height: 6),
                _auditoriaLinha(Icons.notes_rounded, 'Resumo', resumo),
              ],
              if (motivoAuditoria != null && motivoAuditoria.isNotEmpty) ...[
                const SizedBox(height: 6),
                _auditoriaLinha(Icons.flag_rounded, 'Motivo', motivoAuditoria),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _auditoriaLinha(IconData icon, String label, String value) {
    final t = context.uai;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: t.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
        ),
        Expanded(
          child: Text(value, style: TextStyle(color: t.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildPerfilStateScaffold({
    required IconData icon,
    required String title,
    required String message,
    required Color accent,
    String? buttonText,
    VoidCallback? onPressed,
    bool loading = false,
  }) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Perfil do Aluno'),
        backgroundColor: _appBarBg(context),
        foregroundColor: _appBarFg(context),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: _dashboardPagePaddingOf(context),
            child: _dashboardWidthLimiterOf(
              context,
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withOpacity(0.20)),
                      ),
                      child: loading
                          ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 3,
                        ),
                      )
                          : Icon(icon, size: 40, color: accent),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _onCard(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _onCardMuted(context),
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (buttonText != null && onPressed != null) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onPressed,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: Text(buttonText),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: _readableOn(accent),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPerfilConteudo({
    required Map<String, dynamic> data,
    required String? fotoUrl,
    required String contatoAluno,
    required String? contatoResponsavel,
    required String nomeResponsavel,
    required String contatoEmergencia,
    required String nomeContatoEmergencia,
    required String? monitor,
    required String? idade,
    required String nome,
    required String? apelido,
    required String? statusAtividade,
    required String? turma,
    required String? turmaId,
    required bool isAtivo,
  }) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: _dashboardPagePaddingOf(context),
        child: _dashboardWidthLimiterOf(
          context,
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1040;
              final hero = _buildPerfilHeroCard(
                fotoUrl: fotoUrl,
                nome: nome,
                apelido: apelido,
                idade: idade,
                turma: turma,
                monitor: monitor,
                isAtivo: isAtivo,
              );

              final emergency = _buildEmergencyContactsSection(
                nomeAluno: nome,
                contatoAluno: contatoAluno,
                nomeResponsavel: nomeResponsavel,
                contatoResponsavel: contatoResponsavel,
                nomeContatoEmergencia: nomeContatoEmergencia,
                contatoEmergencia: contatoEmergencia,
                turmaId: turmaId,
              );

              final frequencia = CardFrequenciaModerno(
                key: ValueKey(_frequenciaKey),
                alunoId: widget.alunoId,
                filtroTemporal: 'Ano',
                anoSelecionado: '2026',
              );

              final informacoes = CardInformacoesModerno(
                key: ValueKey('info_${widget.alunoId}_$_frequenciaKey'),
                alunoId: widget.alunoId,
                initialData: data,
              );

              final eventos = CardEventosParticipados(
                alunoId: widget.alunoId,
                alunoData: data,
              );

              if (wide) {
                return Column(
                  children: [
                    hero,
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              emergency,
                              informacoes,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              frequencia,
                              eventos,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              }

              return Column(
                children: [
                  hero,
                  const SizedBox(height: 14),
                  emergency,
                  frequencia,
                  informacoes,
                  const SizedBox(height: 4),
                  eventos,
                  const SizedBox(height: 22),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPerfilHeroCard({
    required String? fotoUrl,
    required String nome,
    required String? apelido,
    required String? idade,
    required String? turma,
    required String? monitor,
    required bool isAtivo,
  }) {
    final t = context.uai;
    final onGradient = _onPrimary(context);
    final statusColor = isAtivo ? t.success : t.warning;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 560;

    final foto = _buildFotoPerfilHero(
      fotoUrl: fotoUrl,
      nome: nome,
      isAtivo: isAtivo,
      statusColor: statusColor,
    );

    final infos = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          nome,
          style: TextStyle(
            color: onGradient,
            fontSize: compact ? 23 : 28,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: compact ? TextAlign.center : TextAlign.start,
        ),
        if (apelido != null && apelido.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            '"$apelido"',
            style: TextStyle(
              color: onGradient.withOpacity(0.76),
              fontSize: 15,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.center : TextAlign.start,
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPerfilHeroChip(
              icon: isAtivo
                  ? Icons.check_circle_rounded
                  : Icons.pause_circle_filled_rounded,
              label: isAtivo ? 'ATIVO' : 'INATIVO',
              color: statusColor,
              onGradient: onGradient,
            ),
            if (idade != null && idade.trim().isNotEmpty)
              _buildPerfilHeroChip(
                icon: Icons.cake_rounded,
                label: '$idade anos',
                color: t.warning,
                onGradient: onGradient,
              ),
            if (turma != null && turma.trim().isNotEmpty)
              _buildPerfilHeroChip(
                icon: Icons.groups_rounded,
                label: turma,
                color: t.info,
                onGradient: onGradient,
              ),
            if (monitor != null && monitor.trim().isNotEmpty)
              _buildPerfilHeroChip(
                icon: Icons.military_tech_rounded,
                label: 'Monitor $monitor',
                color: _getMonitorColor(monitor),
                onGradient: onGradient,
              ),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: onGradient.withOpacity(0.12)),
        boxShadow: t.cardShadow,
      ),
      child: compact
          ? Column(
        children: [
          foto,
          const SizedBox(height: 16),
          infos,
        ],
      )
          : Row(
        children: [
          foto,
          const SizedBox(width: 22),
          Expanded(child: infos),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: onGradient.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: onGradient.withOpacity(0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, color: onGradient, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Toque na foto',
                  style: TextStyle(
                    color: onGradient.withOpacity(0.86),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoPerfilHero({
    required String? fotoUrl,
    required String nome,
    required bool isAtivo,
    required Color statusColor,
  }) {
    final t = context.uai;
    final inicial = nome.trim().isNotEmpty ? nome.trim()[0].toUpperCase() : '?';

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        GestureDetector(
          onTap: () => _abrirFotoTelaCheia(fotoUrl, nome),
          child: Hero(
            tag: 'foto_aluno_${widget.alunoId}',
            child: Container(
              width: 124,
              height: 124,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.card.withOpacity(0.22),
                border: Border.all(color: _onPrimary(context).withOpacity(0.45), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: fotoUrl != null && fotoUrl.trim().isNotEmpty
                    ? CachedNetworkImage(
                  imageUrl: fotoUrl,
                  fit: BoxFit.cover,
                  width: 116,
                  height: 116,
                  placeholder: (context, url) => Container(
                    color: t.cardAlt,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.primary,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => _fotoHeroFallback(inicial),
                )
                    : _fotoHeroFallback(inicial),
              ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _readableOn(statusColor).withOpacity(0.90), width: 2),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              isAtivo ? 'ATIVO' : 'INATIVO',
              style: TextStyle(
                color: _readableOn(statusColor),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fotoHeroFallback(String inicial) {
    final t = context.uai;
    return Container(
      color: Color.alphaBlend(t.primary.withOpacity(0.12), t.card),
      alignment: Alignment.center,
      child: Text(
        inicial,
        style: TextStyle(
          color: _onCard(context),
          fontSize: 42,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildPerfilHeroChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color onGradient,
  }) {
    final chipBg = onGradient.withOpacity(0.12);
    final visibleColor = _ensureVisible(color, context.uai.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onGradient.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: visibleColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onGradient,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoAluno || _carregandoPermissoes || !_permissoesCarregadas) {
      return _buildPerfilStateScaffold(
        icon: Icons.person_search_rounded,
        title: 'Carregando perfil do aluno',
        message: 'Buscando dados, permissões e informações salvas no sistema.',
        accent: context.uai.primary,
        loading: true,
      );
    }

    if (_alunoData == null) {
      return _buildPerfilStateScaffold(
        icon: Icons.person_off_rounded,
        title: 'Aluno não encontrado',
        message: 'Não foi possível localizar este cadastro. Ele pode ter sido removido ou estar indisponível no momento.',
        accent: context.uai.error,
        buttonText: 'Voltar',
        onPressed: () => Navigator.pop(context),
      );
    }

    final data = _alunoData!;
    final fotoUrl = data['foto_perfil_aluno'] as String?;
    final contatoAluno = data['contato_aluno'] as String? ?? '';
    final contatoResponsavel = data['contato_responsavel'] as String?;
    final nomeResponsavel =
        data['nome_responsavel']?.toString() ??
            data['responsavel']?.toString() ??
            data['responsavel_nome']?.toString() ??
            'Responsável';
    final contatoEmergencia =
        data['contato_emergencia']?.toString() ??
            data['telefone_emergencia']?.toString() ??
            data['emergencia_contato']?.toString() ??
            '';
    final nomeContatoEmergencia =
        data['nome_contato_emergencia']?.toString() ??
            data['responsavel_emergencia']?.toString() ??
            'Contato de emergência';
    final monitor = data['monitor'] as String?;
    final idade = data['idade'] as String?;
    final nome = data['nome'] as String? ?? 'N/A';
    final apelido = data['apelido'] as String?;
    final statusAtividade = data['status_atividade'] as String?;
    final turma = data['turma'] as String?;
    final turmaId = data['turma_id'] as String?;

    final isAtivo = _isAlunoAtivo(statusAtividade);

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text('Perfil do Aluno'),
        backgroundColor:
        Theme.of(context).appBarTheme.backgroundColor ??
            context.uai.primary,
        foregroundColor:
        Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(
              Theme.of(context).appBarTheme.backgroundColor ??
                  context.uai.primary,
            ),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) {
              final List<PopupMenuItem<String>> menuItems = [];

              menuItems.add(
                PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: context.uai.info),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editar Perfil',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              //  BOTÃO VER TERMO (sempre aparece)
              menuItems.add(
                PopupMenuItem(
                  value: 'ver_termo',
                  child: Row(
                    children: [
                      Icon(Icons.description, color: context.uai.success),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ver Termo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              if (isAtivo) {
                menuItems.add(
                  PopupMenuItem(
                    value: 'desativar',
                    child: Row(
                      children: [
                        Icon(Icons.pause_circle, color: context.uai.warning),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Desativar Aluno',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                menuItems.add(
                  PopupMenuItem(
                    value: 'ativar',
                    child: Row(
                      children: [
                        Icon(Icons.play_circle, color: context.uai.success),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ativar Aluno',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (isAtivo) {
                menuItems.add(
                  PopupMenuItem(
                    value: 'mudar_turma',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, color: context.uai.associacao),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mudar de Turma',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              menuItems.add(
                PopupMenuItem(
                  value: 'historico_edicoes',
                  child: Row(
                    children: [
                      Icon(
                        Icons.manage_history_rounded,
                        color: context.uai.warning,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Histórico de Edições',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              menuItems.add(
                PopupMenuItem(
                  value: 'historico',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: context.uai.info),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Histórico de Frequência',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              return menuItems;
            },
            onSelected: (value) async {
              switch (value) {
                case 'editar':
                  await _editarAluno(context);
                  break;
                case 'ver_termo': //  NOVO CASE
                  await _verTermoAluno(context, widget.alunoId, data);
                  break;
                case 'desativar':
                  await _desativarAluno(context, widget.alunoId);
                  break;
                case 'ativar':
                  await _ativarAluno(context, widget.alunoId, data);
                  break;
                case 'mudar_turma':
                  await _mudarTurma(context, widget.alunoId, data);
                  await _carregarDadosAluno(forcarServidor: true);
                  break;
                case 'historico_edicoes':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoricoEdicoesAlunoScreen(
                        alunoId: widget.alunoId,
                        alunoNome: nome,
                      ),
                    ),
                  );
                  await _carregarDadosAluno(forcarServidor: true);
                  break;
                case 'historico':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoricoFrequenciaScreen(
                        alunoId: widget.alunoId,
                        alunoNome: nome,
                      ),
                    ),
                  );
                  break;
              }
            },
            icon: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: _buildPerfilConteudo(
        data: data,
        fotoUrl: fotoUrl,
        contatoAluno: contatoAluno,
        contatoResponsavel: contatoResponsavel,
        nomeResponsavel: nomeResponsavel,
        contatoEmergencia: contatoEmergencia,
        nomeContatoEmergencia: nomeContatoEmergencia,
        monitor: monitor,
        idade: idade,
        nome: nome,
        apelido: apelido,
        statusAtividade: statusAtividade,
        turma: turma,
        turmaId: turmaId,
        isAtivo: isAtivo,
      ),
    );
  }
}

// ============================================
// ✓ CARD DE FREQUÊNCIA - CACHE INTELIGENTE (30 MINUTOS)
// ============================================
class CardFrequenciaModerno extends StatefulWidget {
  final String alunoId;
  final String? filtroTemporal;
  final String? anoSelecionado;

  CardFrequenciaModerno({
    super.key,
    required this.alunoId,
    this.filtroTemporal,
    this.anoSelecionado,
  });

  @override
  State<CardFrequenciaModerno> createState() => _CardFrequenciaModernoState();
}

class _CardFrequenciaModernoState extends State<CardFrequenciaModerno> {
  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FrequenciaService _frequenciaService = FrequenciaService();
  final CacheService _cache = CacheService();
  final Connectivity _connectivity = Connectivity();

  Map<String, dynamic>? _dadosAluno;
  FrequenciaModel? _frequencia;
  List<Map<String, dynamic>> _logsFrequencia = [];
  bool _isLoading = true;
  bool _expanded = false;
  bool _isAtualizando = false;
  bool _isOffline = false;
  bool _aguardandoCarregamentoManual = false;

  //  FILTROS INTERNOS
  String? _filtroAtual;
  String? _anoAtual;

  // Contadores calculados dos logs
  int _totalPresencas = 0;
  int _totalAusencias = 0;
  late Map<String, int> _presencasPorDia;
  Timestamp? _ultimaPresenca;

  @override
  void initState() {
    super.initState();

    _filtroAtual = widget.filtroTemporal;
    _anoAtual = widget.anoSelecionado;

    _resetContadores();
    _carregarDados();
  }

  void _resetContadores() {
    _presencasPorDia = {
      'seg': 0,
      'ter': 0,
      'qua': 0,
      'qui': 0,
      'sex': 0,
      'sab': 0,
      'dom': 0,
    };
    _totalPresencas = 0;
    _totalAusencias = 0;
    _ultimaPresenca = null;
  }

  //  VERIFICAR INTERNET
  Future<bool> _temInternet() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  //  FUNÇÃO PARA MUDAR O FILTRO
  void _aplicarFiltro(String? filtro, {String? ano}) {
    setState(() {
      _filtroAtual = filtro;
      if (filtro == 'Ano' && ano != null) {
        _anoAtual = ano;
      } else if (filtro != 'Ano') {
        _anoAtual = null;
      }
    });
    _carregarDados();
  }

  //  FUNÇÃO PARA FORÇAR ATUALIZAÇÃO DO SERVIDOR
  Future<void> _forcarAtualizacao() async {
    setState(() {
      _isAtualizando = true;
    });

    try {
      debugPrint(
        ' FORÇANDO ATUALIZAÇÃO DO SERVIDOR PARA ALUNO ${widget.alunoId}',
      );
      await _carregarDados(forcarServidor: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Dados atualizados com sucesso!'),
            backgroundColor: context.uai.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro: Erro ao forçar atualização: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAtualizando = false;
        });
      }
    }
  }

  //  CARREGAR DADOS COM CACHE INTELIGENTE
  Future<void> _carregarDados({bool forcarServidor = false}) async {
    setState(() {
      _isLoading = true;
      _resetContadores();
      _isOffline = false;
      _aguardandoCarregamentoManual = false;
    });

    try {
      final cacheKey =
          'frequencia_${widget.alunoId}_${_filtroAtual ?? 'total'}_${_anoAtual ?? ''}';
      final temInternet = await _temInternet();

      //  1. Se NÃO forçar servidor e tiver cache válido, usa cache
      if (!forcarServidor && temInternet) {
        final cachedData = await _cache.loadFromCache(cacheKey);
        if (cachedData != null) {
          _logsFrequencia = List<Map<String, dynamic>>.from(
            cachedData['logs'] ?? [],
          );
          _dadosAluno = cachedData['dados_aluno'] as Map<String, dynamic>?;
          _calcularFrequenciaDosLogs();

          if (!mounted) return;
          setState(() => _isLoading = false);
          debugPrint('✓ Frequência carregada do CACHE (válido)');
          return;
        }
      }

      //  2. Se estiver offline e sem cache, tenta cache mesmo expirado
      if (!temInternet) {
        final fallbackCache = await _cache.loadFromCache(cacheKey);
        if (fallbackCache != null) {
          _logsFrequencia = List<Map<String, dynamic>>.from(
            fallbackCache['logs'] ?? [],
          );
          _dadosAluno = fallbackCache['dados_aluno'] as Map<String, dynamic>?;
          _calcularFrequenciaDosLogs();

          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _isOffline = true;
          });

          debugPrint('Modo offline - usando cache expirado');
          return;
        }
      }

      if (_isWindowsDesktop && !forcarServidor) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _aguardandoCarregamentoManual = true;
        });
        return;
      }

      //  3. Busca do servidor
      debugPrint('Buscando frequência do servidor...');

      // Buscar dados do aluno
      final alunoDoc = await _firestore
          .collection('alunos')
          .doc(widget.alunoId)
          .get(GetOptions(source: Source.server));

      if (!alunoDoc.exists) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      _dadosAluno = alunoDoc.data();

      // Buscar logs
      await _carregarLogsComFiltro();

      // Calcular frequência
      _calcularFrequenciaDosLogs();

      //  4. Salvar no cache
      if (_logsFrequencia.isNotEmpty) {
        await _cache.saveToCache(cacheKey, {
          'logs': _logsFrequencia,
          'dados_aluno': _dadosAluno,
        });
      }
    } catch (e) {
      debugPrint('Erro: Erro ao carregar frequência: $e');

      //  Fallback: tenta cache em caso de erro
      final fallbackCache = await _cache.loadFromCache(
        'frequencia_${widget.alunoId}',
      );
      if (fallbackCache != null) {
        _logsFrequencia = List<Map<String, dynamic>>.from(
          fallbackCache['logs'] ?? [],
        );
        _dadosAluno = fallbackCache['dados_aluno'] as Map<String, dynamic>?;
        _calcularFrequenciaDosLogs();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Usando dados offline'),
              backgroundColor: context.uai.warning,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Carrega logs aplicando o filtro
  Future<void> _carregarLogsComFiltro() async {
    try {
      Query query = _firestore
          .collection('log_presenca_alunos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_aula', descending: true);

      // Aplica filtro temporal
      if (_filtroAtual != null) {
        final now = DateTime.now();

        switch (_filtroAtual) {
          case 'Semana':
            final umaSemanaAtras = now.subtract(Duration(days: 7));
            query = query.where(
              'data_aula',
              isGreaterThanOrEqualTo: Timestamp.fromDate(umaSemanaAtras),
            );
            break;
          case 'Mês':
            final umMesAtras = DateTime(now.year, now.month - 1, now.day);
            query = query.where(
              'data_aula',
              isGreaterThanOrEqualTo: Timestamp.fromDate(umMesAtras),
            );
            break;
          case 'Ano':
            if (_anoAtual != null) {
              final inicioAno = DateTime(int.parse(_anoAtual!), 1, 1);
              final fimAno = DateTime(
                int.parse(_anoAtual!),
                12,
                31,
                23,
                59,
                59,
              );
              query = query
                  .where(
                'data_aula',
                isGreaterThanOrEqualTo: Timestamp.fromDate(inicioAno),
              )
                  .where(
                'data_aula',
                isLessThanOrEqualTo: Timestamp.fromDate(fimAno),
              );
            }
            break;
        }
      }

      final snapshot = await query.get(GetOptions(source: Source.server));

      _logsFrequencia = snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      debugPrint(' Logs carregados do servidor: ${_logsFrequencia.length}');
    } catch (e) {
      debugPrint('Erro ao carregar logs: $e');
      _logsFrequencia = [];
    }
  }

  // Calcula estatísticas dos logs
  void _calcularFrequenciaDosLogs() {
    for (var log in _logsFrequencia) {
      final presente = log['presente'] as bool? ?? false;
      final dataLog = log['data_aula'] as Timestamp?;
      final diaSemana = log['dia_semana_abrev'] as String?;

      if (presente) {
        _totalPresencas++;

        if (dataLog != null) {
          if (_ultimaPresenca == null ||
              dataLog.toDate().isAfter(_ultimaPresenca!.toDate())) {
            _ultimaPresenca = dataLog;
          }
        }

        if (diaSemana != null && _presencasPorDia.containsKey(diaSemana)) {
          _presencasPorDia[diaSemana] = _presencasPorDia[diaSemana]! + 1;
        }
      } else {
        _totalAusencias++;
      }
    }

    final dadosCompletos = <String, dynamic>{
      if (_dadosAluno != null) ..._dadosAluno!,
      'seg': _presencasPorDia['seg'],
      'ter': _presencasPorDia['ter'],
      'qua': _presencasPorDia['qua'],
      'qui': _presencasPorDia['qui'],
      'sex': _presencasPorDia['sex'],
      'sab': _presencasPorDia['sab'],
      'dom': _presencasPorDia['dom'],
      'total_presencas': _totalPresencas,
      'total_ausencias': _totalAusencias,
      'ultimo_dia_presente': _ultimaPresenca,
    };

    _frequencia = _frequenciaService.calcularFrequencia(dadosCompletos);

    if (mounted) {
      setState(() {});
    }

    debugPrint(' Frequência calculada - Total: $_totalPresencas');
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return "Nunca";
    return DateFormat("dd/MM/yyyy").format(timestamp.toDate());
  }

  Widget _buildAlunoAvatar() {
    final fotoUrl = _dadosAluno?['foto_perfil_aluno'] as String?;

    return CircleAvatar(
      radius: 40,
      backgroundColor: context.uai.border,
      backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty
          ? NetworkImage(fotoUrl)
          : null,
      child: fotoUrl == null || fotoUrl.isEmpty
          ? Text(
        _dadosAluno?['nome']?.toString().substring(0, 1).toUpperCase() ??
            '?',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _onCardMuted(context),
        ),
      )
          : null,
    );
  }

  Widget _buildMetricCard({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: _onCardMuted(context)),
        ),
      ],
    );
  }

  Widget _buildDiaCardCompacto(String dia, int quantidade) {
    return Container(
      width: 38,
      padding: EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: quantidade > 0
            ? context.uai.error.withOpacity(0.10)
            : context.uai.cardAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: quantidade > 0
              ? context.uai.error.withOpacity(0.24)
              : context.uai.border,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            dia,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: quantidade > 0
                  ? context.uai.primary
                  : context.uai.textMuted,
            ),
          ),
          SizedBox(height: 2),
          Text(
            quantidade.toString(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: quantidade > 0
                  ? context.uai.primary
                  : context.uai.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _getTituloFiltro() {
    if (_filtroAtual == null) return '';

    if (_filtroAtual == 'Ano' && _anoAtual != null) {
      return ' • $_anoAtual';
    }
    return ' • $_filtroAtual';
  }

  String _getSubtituloFiltro() {
    if (_filtroAtual == null) return '';

    switch (_filtroAtual) {
      case 'Semana':
        return 'Últimos 7 dias';
      case 'Mês':
        return 'Últimos 30 dias';
      case 'Ano':
        return _anoAtual ?? 'Ano selecionado';
      case 'Total':
        return 'Todo histórico';
      default:
        return '';
    }
  }

  Widget _buildFiltrosRow() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildFiltroChip('Semana', Icons.calendar_view_week),
            SizedBox(width: 8),
            _buildFiltroChip('Mês', Icons.calendar_month),
            SizedBox(width: 8),
            _buildFiltroChip('Ano', Icons.calendar_today),
            SizedBox(width: 8),
            _buildFiltroChip('Total', Icons.history),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroChip(String label, IconData icon) {
    final isSelected = _filtroAtual == label;

    return FilterChip(
      label: Text(label),
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected
            ? _readableOn(context.uai.primary)
            : context.uai.textSecondary,
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          if (label == 'Ano') {
            _mostrarSeletorAno();
          } else {
            _aplicarFiltro(label);
          }
        } else {
          _aplicarFiltro(null);
        }
      },
      selectedColor: context.uai.primary,
      labelStyle: TextStyle(
        color: isSelected
            ? _readableOn(context.uai.primary)
            : context.uai.textPrimary,
        fontSize: 12,
      ),
      backgroundColor: context.uai.cardAlt,
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Future<void> _mostrarSeletorAno() async {
    final anoAtual = DateTime.now().year;
    final anos = List.generate(10, (index) => (anoAtual - index).toString());

    final anoSelecionado = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: context.uai.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.uai.cardRadius),
        ),
        title: Text(
          'Selecione o ano',
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: anos.map((ano) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ano),
            child: Text(
              ano,
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      ),
    );

    if (anoSelecionado != null) {
      _aplicarFiltro('Ano', ano: anoSelecionado);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(color: context.uai.error),
        ),
      );
    }

    if (_aguardandoCarregamentoManual) {
      return Container(
        height: 200,
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 42, color: context.uai.textMuted),
              SizedBox(height: 12),
              Text(
                'Frequência não carregada automaticamente no Windows.',
                style: TextStyle(color: context.uai.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _forcarAtualizacao,
                icon: Icon(Icons.download_rounded),
                label: Text('Carregar frequência'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
                  foregroundColor: _readableOn(context.uai.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_frequencia == null || _dadosAluno == null) {
      return Container(
        height: 200,
        padding: EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: context.uai.error),
              SizedBox(height: 12),
              Text(
                'Erro ao carregar dados de frequência',
                style: TextStyle(color: context.uai.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _forcarAtualizacao,
                icon: Icon(Icons.refresh),
                label: Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.uai.primary,
                  foregroundColor: _readableOn(context.uai.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final frequencia = _frequencia!;
    final nome = _dadosAluno!['nome'] ?? 'Aluno';

    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho com nome, foto e indicador offline
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: frequencia.corIndicador.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildAlunoAvatar(),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nome,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: context.uai.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                //  INDICADOR OFFLINE
                                if (_isOffline)
                                  Container(
                                    margin: EdgeInsets.only(right: 8),
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: context.uai.warning.withOpacity(
                                        0.16,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.wifi_off,
                                      size: 16,
                                      color: context.uai.warning,
                                    ),
                                  ),
                                //  BOTÃO DE ATUALIZAÇÃO
                                if (!_isAtualizando)
                                  IconButton(
                                    icon: Icon(Icons.refresh, size: 20),
                                    onPressed: _forcarAtualizacao,
                                    color: context.uai.primary,
                                    tooltip: 'Atualizar dados',
                                  ),
                                if (_isAtualizando)
                                  Container(
                                    width: 30,
                                    height: 30,
                                    padding: EdgeInsets.all(4),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.uai.error,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: frequencia.corIndicador.withOpacity(
                                      0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    frequencia.nivel,
                                    style: TextStyle(
                                      color: frequencia.corIndicador,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (_filtroAtual != null) ...[
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getTituloFiltro(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _onCardMuted(context),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (_filtroAtual != null) ...[
                              SizedBox(height: 2),
                              Text(
                                _getSubtituloFiltro(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.uai.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  _buildFiltrosRow(),
                ],
              ),
            ),

            // Conteúdo
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  // Métricas principais
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricCard(
                        value: '$_totalPresencas',
                        label: 'Presenças',
                        color: context.uai.info,
                        icon: Icons.event_available,
                      ),
                      _buildMetricCard(
                        value: '$_totalAusencias',
                        label: 'Faltas',
                        color: context.uai.error,
                        icon: Icons.event_busy,
                      ),
                      _buildMetricCard(
                        value: '${frequencia.diasSemTreinar}',
                        label: 'Dias sem',
                        color: frequencia.corIndicador,
                        icon: Icons.calendar_today,
                      ),
                    ],
                  ),

                  SizedBox(height: 20),

                  // Última presença
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uai.cardAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.uai.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: frequencia.corIndicador,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Última presença',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _onCardMuted(context),
                                ),
                              ),
                              Text(
                                _formatarData(_ultimaPresenca),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: context.uai.textPrimary,
                                ),
                              ),
                              Text(
                                frequencia.statusTexto,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: frequencia.corIndicador,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  // Dias da semana
                  Text(
                    'Presenças por dia',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.uai.textPrimary,
                    ),
                  ),
                  SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDiaCardCompacto('S', _presencasPorDia['seg']!),
                      _buildDiaCardCompacto('T', _presencasPorDia['ter']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qua']!),
                      _buildDiaCardCompacto('Q', _presencasPorDia['qui']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sex']!),
                      _buildDiaCardCompacto('S', _presencasPorDia['sab']!),
                      _buildDiaCardCompacto('D', _presencasPorDia['dom']!),
                    ],
                  ),

                  if (_expanded) ...[
                    SizedBox(height: 20),

                    // Lista dos últimos logs
                    Container(
                      constraints: BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _logsFrequencia.length > 10
                            ? 10
                            : _logsFrequencia.length,
                        itemBuilder: (context, index) {
                          final log = _logsFrequencia[index];
                          final presente = log['presente'] as bool? ?? false;
                          final data = log['data_aula'] as Timestamp?;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              presente ? Icons.check_circle : Icons.cancel,
                              color: presente
                                  ? context.uai.success
                                  : context.uai.error,
                              size: 18,
                            ),
                            title: Text(
                              _formatarData(data),
                              style: TextStyle(
                                fontSize: 13,
                                color: context.uai.textPrimary,
                              ),
                            ),
                            trailing: Text(
                              log['tipo_aula']?.toString() ?? 'N/A',
                              style: TextStyle(
                                fontSize: 11,
                                color: _onCardMuted(context),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    SizedBox(height: 20),

                    // Botão de ver histórico
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.history, size: 18),
                      label: Text('FECHAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _appBarBgOf(context),
                        foregroundColor: _appBarFgOf(context),
                        minimumSize: Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: 8),

                  // Botão de expandir/recolher
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: context.uai.primary,
                    ),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// ✓ CARD DE EVENTOS PARTICIPADOS
// ============================================
class CardEventosParticipados extends StatefulWidget {
  final String alunoId;
  final Map<String, dynamic> alunoData;

  CardEventosParticipados({
    super.key,
    required this.alunoId,
    required this.alunoData,
  });

  @override
  State<CardEventosParticipados> createState() =>
      _CardEventosParticipadosState();
}

class _CardEventosParticipadosState extends State<CardEventosParticipados> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CacheService _cache = CacheService();

  List<Map<String, dynamic>> _participacoes = [];
  bool _isLoading = true;
  bool _expanded = false;
  bool _aguardandoCarregamentoManual = false;
  String? _erro;

  // Cache para as cores das graduações
  final Map<String, Map<String, dynamic>> _graduacoesCache = {};

  // Cache para o SVG
  String? _svgContent;
  final Map<String, String?> _svgCache = {};

  @override
  void initState() {
    super.initState();
    _carregarSvg();
    _carregarParticipacoes();
  }

  Future<void> _carregarSvg() async {
    try {
      final content = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar SVG: $e');
    }
  }

  //  CARREGAR PARTICIPAÇÕES COM CACHE INTELIGENTE
  Future<void> _carregarParticipacoes({bool forcarServidor = false}) async {
    if (forcarServidor && mounted) {
      setState(() {
        _isLoading = true;
        _aguardandoCarregamentoManual = false;
        _erro = null;
      });
    }

    try {
      final cacheKey = 'eventos_${widget.alunoId}';

      // Tenta cache primeiro
      final cachedData = await _cache.loadFromCache(cacheKey);
      if (cachedData != null) {
        _participacoes = List<Map<String, dynamic>>.from(
          cachedData['participacoes'] ?? [],
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _erro = null;
        });
        return;
      }

      if (_isWindowsDesktop && !forcarServidor) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _aguardandoCarregamentoManual = true;
          _erro = null;
        });
        return;
      }

      // Busca do servidor
      final participacoesSnapshot = await _firestore
          .collection('participacoes_eventos')
          .where('aluno_id', isEqualTo: widget.alunoId)
          .orderBy('data_evento', descending: true)
          .get(GetOptions(source: Source.server));

      if (participacoesSnapshot.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _participacoes = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> participacoesCompletas = [];

      for (var doc in participacoesSnapshot.docs) {
        final participacao = doc.data();
        final eventoId = participacao['evento_id'] as String?;

        if (eventoId != null) {
          final eventoDoc = await _firestore
              .collection('eventos')
              .doc(eventoId)
              .get(GetOptions(source: Source.server));

          if (eventoDoc.exists) {
            final eventoData = eventoDoc.data()!;
            participacoesCompletas.add({
              'id': doc.id,
              ...participacao,
              'evento_detalhes': eventoData,
            });
          } else {
            participacoesCompletas.add({'id': doc.id, ...participacao});
          }
        } else {
          participacoesCompletas.add({'id': doc.id, ...participacao});
        }
      }

      // Salva no cache
      await _cache.saveToCache(cacheKey, {
        'participacoes': participacoesCompletas,
      });

      if (!mounted) return;
      setState(() {
        _participacoes = participacoesCompletas;
        _isLoading = false;
        _erro = null;
      });
    } catch (e) {
      debugPrint('Erro: Erro ao carregar participações: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _erro = e.toString();
      });
    }
  }

  Future<Map<String, dynamic>?> _getCoresGraduacao(String? graduacaoId) async {
    if (graduacaoId == null || graduacaoId.isEmpty) return null;

    if (_graduacoesCache.containsKey(graduacaoId)) {
      return _graduacoesCache[graduacaoId];
    }

    try {
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection('graduacoes')
            .doc(graduacaoId)
            .get(GetOptions(source: Source.cache));
      } catch (e) {
        doc = await _firestore
            .collection('graduacoes')
            .doc(graduacaoId)
            .get(GetOptions(source: Source.server));
      }

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;

        if (data != null) {
          _graduacoesCache[graduacaoId] = {
            'hex_cor1': data['hex_cor1'],
            'hex_cor2': data['hex_cor2'],
            'hex_ponta1': data['hex_ponta1'],
            'hex_ponta2': data['hex_ponta2'],
            'nome_graduacao': data['nome_graduacao'],
          };
          return _graduacoesCache[graduacaoId];
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar graduação: $e');
    }
    return null;
  }

  Future<String?> _getSvgColorido(String? graduacaoId) async {
    if (graduacaoId == null || _svgContent == null) return null;

    final cacheKey = 'svg_$graduacaoId';
    if (_svgCache.containsKey(cacheKey)) {
      return _svgCache[cacheKey];
    }

    final cores = await _getCoresGraduacao(graduacaoId);
    if (cores == null) return null;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7)
          return context.uai.textMuted;
        try {
          return Color(
            int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16),
          );
        } catch (e) {
          return context.uai.textMuted;
        }
      }

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );
        if (element.name.local.isNotEmpty) {
          final style = element.getAttribute('style') ?? '';
          final hex =
              '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
          final newStyle = style.replaceAll(
            RegExp(r'fill:#[0-9a-fA-F]{6}'),
            '',
          );
          element.setAttribute('style', 'fill:$hex;$newStyle');
        }
      }

      changeColor('cor1', colorFromHex(cores['hex_cor1']));
      changeColor('cor2', colorFromHex(cores['hex_cor2']));
      changeColor('corponta1', colorFromHex(cores['hex_ponta1']));
      changeColor('corponta2', colorFromHex(cores['hex_ponta2']));

      final svgString = document.toXmlString();
      _svgCache[cacheKey] = svgString;
      return svgString;
    } catch (e) {
      debugPrint('Erro ao colorir SVG: $e');
      return null;
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';
    if (data is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(data.toDate());
    }
    return data.toString();
  }

  Future<void> _abrirDetalhesParticipacao(
      Map<String, dynamic> participacao,
      String id,
      ) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetalheParticipacaoScreen(
          participacao: participacao,
          participacaoId: id,
        ),
      ),
    );
  }

  String? _extrairCertificadoUrl(Map<String, dynamic> participacao) {
    const campos = [
      'link_certificado',
      'linkCertificado',
      'certificado_url',
      'certificadoUrl',
      'url_certificado',
      'urlCertificado',
      'pdf_certificado',
      'pdfCertificado',
      'certificado_link',
      'certificadoLink',
      'certificado',
      'arquivo_certificado',
      'arquivoCertificado',
    ];

    for (final campo in campos) {
      final value = participacao[campo]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final graduacaoId = widget.alunoData['graduacao_id']?.toString();

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                context.uai.warning.withOpacity(0.10),
                context.uai.cardAlt,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.uai.warning.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.emoji_events,
                    color: context.uai.warning,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Eventos Participados',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _readableOn(context.uai.card),
                        ),
                      ),
                      Text(
                        _isLoading
                            ? 'Carregando...'
                            : _erro != null
                            ? 'Erro ao carregar'
                            : '${_participacoes.length} ${_participacoes.length == 1 ? 'evento' : 'eventos'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _erro != null
                              ? context.uai.error
                              : _readableOn(context.uai.card).withOpacity(0.68),
                        ),
                      ),
                    ],
                  ),
                ),
                if (graduacaoId != null &&
                    (!_isWindowsDesktop ||
                        (!_isLoading && !_aguardandoCarregamentoManual)))
                  FutureBuilder<String?>(
                    future: _getSvgColorido(graduacaoId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return SizedBox(
                          width: 50,
                          height: 50,
                          child: SvgPicture.string(
                            snapshot.data!,
                            placeholderBuilder: (context) => SizedBox(),
                          ),
                        );
                      }
                      return SizedBox(
                        width: 50,
                        height: 50,
                        child: Icon(
                          Icons.emoji_events,
                          color: context.uai.warning,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Conteúdo
          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: context.uai.warning),
              ),
            )
          else if (_aguardandoCarregamentoManual)
            Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.event_available,
                    size: 44,
                    color: context.uai.textMuted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Eventos não carregados automaticamente no Windows.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.uai.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _carregarParticipacoes(forcarServidor: true),
                    icon: Icon(Icons.download_rounded),
                    label: Text('Carregar eventos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.uai.primary,
                      foregroundColor: _readableOn(context.uai.primary),
                    ),
                  ),
                ],
              ),
            )
          else if (_erro != null)
              Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 48, color: context.uai.error),
                    SizedBox(height: 12),
                    Text(
                      'Erro ao carregar eventos',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.uai.primaryDark,
                      ),
                    ),
                    Text(
                      _erro!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _onCardMuted(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (_participacoes.isEmpty)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy, size: 48, color: context.uai.border),
                      SizedBox(height: 12),
                      Text(
                        'Nenhum evento participado',
                        style: TextStyle(
                          fontSize: 14,
                          color: _onCardMuted(context),
                        ),
                      ),
                      Text(
                        'Este aluno ainda não participou de eventos',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.uai.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ..._participacoes
                          .take(_expanded ? _participacoes.length : 3)
                          .map((participacao) {
                        final eventoDetalhes =
                        participacao['evento_detalhes']
                        as Map<String, dynamic>?;
                        final nomeEvento =
                            eventoDetalhes?['nome'] ??
                                participacao['evento_nome'] ??
                                'Evento';
                        final dataEvento = _formatarData(
                          eventoDetalhes?['data'] ??
                              participacao['data_evento'],
                        );
                        final tipoEvento =
                            eventoDetalhes?['tipo_evento'] ??
                                participacao['tipo_evento'] ??
                                '';
                        final certificado = _extrairCertificadoUrl(
                          participacao,
                        );
                        final graduacaoEvento =
                        participacao['graduacao'] as String?;

                        return InkWell(
                          onTap: () => _abrirDetalhesParticipacao(
                            participacao,
                            participacao['id'],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.uai.cardAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.uai.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: context.uai.warning.withOpacity(
                                      0.16,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.event,
                                    color: context.uai.warning,
                                    size: 20,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nomeEvento,
                                        style: TextStyle(
                                          color: _readableOn(
                                            context.uai.cardAlt,
                                          ),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 10,
                                            color: context.uai.textSecondary,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            dataEvento,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _onCardMuted(context),
                                            ),
                                          ),
                                          if (tipoEvento.isNotEmpty) ...[
                                            SizedBox(width: 8),
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: context.uai.textMuted,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                tipoEvento,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: _onCardMuted(context),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (graduacaoEvento != null &&
                                          graduacaoEvento.isNotEmpty) ...[
                                        SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.emoji_events,
                                              size: 10,
                                              color: context.uai.warning,
                                            ),
                                            SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                graduacaoEvento,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.uai.warning,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (certificado != null &&
                                    certificado.isNotEmpty)
                                  Tooltip(
                                    message: 'Certificado disponível',
                                    child: Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: context.uai.success.withOpacity(
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: context.uai.success
                                              .withOpacity(0.18),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.verified,
                                        color: context.uai.success,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      })
                          .toList(),

                      if (_participacoes.length > 3)
                        Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _expanded = !_expanded;
                              });
                            },
                            icon: Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              color: context.uai.warning,
                            ),
                            label: Text(
                              _expanded
                                  ? 'Ver menos'
                                  : 'Ver todos (${_participacoes.length})',
                              style: TextStyle(
                                color: context.uai.warning,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

// CARD DE INFORMAÇÕES COM DESIGN MODERNO
class CardInformacoesModerno extends StatefulWidget {
  final String alunoId;
  final Map<String, dynamic>? initialData;

  CardInformacoesModerno({super.key, required this.alunoId, this.initialData});

  @override
  State<CardInformacoesModerno> createState() => _CardInformacoesModernoState();
}

class _CardInformacoesModernoState extends State<CardInformacoesModerno> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _dadosAluno;
  bool _isLoading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _dadosAluno = Map<String, dynamic>.from(widget.initialData!);
      _isLoading = false;
    } else {
      _carregarDadosAluno();
    }
  }

  Future<void> _carregarDadosAluno() async {
    try {
      DocumentSnapshot alunoDoc;
      try {
        alunoDoc = await _firestore
            .collection('alunos')
            .doc(widget.alunoId)
            .get(GetOptions(source: Source.server));
      } catch (e) {
        alunoDoc = await _firestore
            .collection('alunos')
            .doc(widget.alunoId)
            .get(GetOptions(source: Source.cache));
      }

      if (!alunoDoc.exists) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _dadosAluno = alunoDoc.data() as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      print('Erro ao carregar dados do aluno: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _formatarData(dynamic data) {
    if (data == null) return "Não informado";

    if (data is Timestamp) {
      return DateFormat("dd/MM/yyyy").format(data.toDate());
    }

    if (data is String) {
      try {
        final date = DateTime.parse(data);
        return DateFormat("dd/MM/yyyy").format(date);
      } catch (e) {
        return data;
      }
    }

    return data.toString();
  }

  Widget _buildInfoItem({
    required String label,
    required String value,
    IconData? icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Icon(icon, size: 16, color: iconColor ?? context.uai.primary),
          SizedBox(width: icon != null ? 12 : 0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: _onCardMuted(context)),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _readableOn(context.uai.card),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        margin: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: CircularProgressIndicator(color: context.uai.primary),
        ),
      );
    }

    if (_dadosAluno == null) {
      return SizedBox.shrink();
    }

    final dados = _dadosAluno!;

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                context.uai.info.withOpacity(0.10),
                context.uai.cardAlt,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: context.uai.info, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Informações do Aluno',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _readableOn(context.uai.card),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: context.uai.info,
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Conteúdo
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoItem(
                  label: 'Nome completo',
                  value: dados['nome']?.toString() ?? 'Não informado',
                  icon: Icons.person,
                  iconColor: context.uai.primary,
                ),

                _buildInfoItem(
                  label: 'Apelido',
                  value: dados['apelido']?.toString() ?? 'Sem apelido',
                  icon: Icons.emoji_emotions,
                  iconColor: context.uai.warning,
                ),

                _buildInfoItem(
                  label: 'Data de nascimento',
                  value: _formatarData(dados['data_nascimento']),
                  icon: Icons.cake,
                  iconColor: context.uai.error,
                ),

                if (_expanded) ...[
                  Divider(color: context.uai.border),
                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Contato',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Telefone',
                    value:
                    dados['contato_aluno']?.toString() ?? 'Não informado',
                    icon: Icons.phone,
                    iconColor: context.uai.success,
                  ),

                  _buildInfoItem(
                    label: 'Endereço',
                    value: dados['endereco']?.toString() ?? 'Não informado',
                    icon: Icons.home,
                    iconColor: context.uai.info,
                  ),

                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Responsável',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Nome do responsável',
                    value:
                    dados['nome_responsavel']?.toString() ??
                        'Não informado',
                    icon: Icons.person_outline,
                    iconColor: context.uai.associacao,
                  ),

                  _buildInfoItem(
                    label: 'Contato do responsável',
                    value:
                    dados['contato_responsavel']?.toString() ??
                        'Não informado',
                    icon: Icons.phone_android,
                    iconColor: context.uai.inscricoes,
                  ),

                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Cadastro',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _readableOn(context.uai.card),
                      ),
                    ),
                  ),

                  _buildInfoItem(
                    label: 'Data do cadastro',
                    value: _formatarData(dados['data_do_cadastro']),
                    icon: Icons.calendar_today,
                    iconColor: context.uai.textMuted,
                  ),

                  _buildInfoItem(
                    label: 'Cadastrado por',
                    value:
                    dados['cadastro_realizado_por']?.toString() ??
                        'Sistema',
                    icon: Icons.person_add,
                    iconColor: context.uai.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tela refatorada visualmente em 03/07/2026 às 03:13
// Refatoração focada em tema dinâmico, responsividade e layout adaptativo.
// Lógica original preservada.
// ============================================================
