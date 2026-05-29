import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_login_screen.dart';
import 'package:uai_capoeira/modules/auth/screens/auth_check.dart';
import 'package:uai_capoeira/modules/auth/screens/login_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/public/inscricao_campeonato_screen.dart';
import 'package:uai_capoeira/modules/inscricoes/public/inscricao_publica_screen.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';
import 'package:uai_capoeira/modules/rastreio/widgets/arvore_visitas_dialog.dart';
import 'package:uai_capoeira/modules/site/screens/biografia_screen.dart';
import 'package:uai_capoeira/modules/site/screens/graduacoes_screen.dart';
import 'package:uai_capoeira/modules/site/screens/portfolio_web_screen.dart';
import 'package:uai_capoeira/modules/site/screens/regimento_screen.dart';
import 'package:uai_capoeira/shared/widgets/chat_assistente_widget.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RastreioSiteService _rastreioService = RastreioSiteService();

  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  String _senhaAcessoApp = 'uai2026app';
  final TextEditingController _senhaController = TextEditingController();

  bool _inscricoesAbertas = false;
  bool _carregandoConfigInscricoes = true;
  bool _portfolioVisivel = false;
  bool _carregandoConfigPortfolio = true;
  bool _campeonatoAtivo = false;
  bool _carregandoConfigCampeonato = true;
  bool _areaAlunoVisivel = false;
  bool _carregandoConfigAreaAluno = true;

  int _totalVisitas = 0;
  bool _carregandoVisitas = true;

  List<Map<String, dynamic>> _itensMenu = [];
  Map<String, dynamic> _textosPersonalizados = {};
  Map<String, bool> _visibilidadePersonalizada = {};
  bool _carregandoConfigMenu = true;

  final List<Map<String, dynamic>> _itensMenuBase = [
    {
      'id': 'inicio',
      'icone': Icons.home,
      'label': 'INÍCIO',
      'index': 0,
      'isSpecial': false,
      'fixo': true,
    },
    {
      'id': 'regimento',
      'icone': Icons.description,
      'label': 'REGIMENTO INTERNO',
      'index': 1,
      'isSpecial': false,
    },
    {
      'id': 'biografia',
      'icone': Icons.auto_stories,
      'label': 'BIOGRAFIA',
      'index': 2,
      'isSpecial': false,
    },
    {
      'id': 'graduacoes',
      'icone': Icons.emoji_events,
      'label': 'GRADUAÇÕES',
      'index': 3,
      'isSpecial': false,
    },
    {
      'id': 'inscricao',
      'icone': Icons.app_registration,
      'label': 'INSCRIÇÃO',
      'index': 4,
      'isSpecial': false,
      'condicional': true,
    },
    {
      'id': 'area_aluno',
      'icone': Icons.school,
      'label': 'ÁREA DO ALUNO',
      'index': 5,
      'isSpecial': false,
      'condicional': true,
    },
    {
      'id': 'campeonato',
      'icone': Icons.emoji_events,
      'label': 'CAMPEONATO',
      'index': 6,
      'isSpecial': false,
      'condicional': true,
    },
    {
      'id': 'portfolio',
      'icone': Icons.photo_library,
      'label': 'PORTFÓLIO',
      'index': 7,
      'isSpecial': false,
      'condicional': true,
    },
    {
      'id': 'acessar_app',
      'icone': Icons.lock_open,
      'label': 'ACESSAR APP',
      'index': 8,
      'isSpecial': true,
    },
  ];

  @override
  void initState() {
    super.initState();

    _garantirTemaPublicoPadrao();
    _carregarConfiguracoes();
    _incrementarContadorVisitas();
    _carregarSenhaApp();
    _carregarConfiguracoesMenu();
    _registrarLocalizacao();
  }

  @override
  void dispose() {
    _rastreioService.finalizarSessao();
    _senhaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _garantirTemaPublicoPadrao() async {
    final controller = AppThemeController.instance;

    if (!controller.initialized) {
      await controller.initialize();
    }

    if (controller.currentPreset == UaiThemePreset.usuarioPersonalizado ||
        controller.activeSavedThemeId != null) {
      await controller.apply(
        preset: UaiThemePreset.uaiClassico,
        mode: ThemeMode.light,
      );
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  bool get _isUaiClassicoPublicTheme {
    return AppThemeController.instance.currentPreset == UaiThemePreset.uaiClassico;
  }

  // ==================== RASTREAMENTO ====================
  Future<void> _registrarLocalizacao() async {
    try {
      debugPrint('🌐 Obtendo IP público...');
      final ipResponse = await http.get(Uri.parse('https://api.ipify.org'));
      final ip = ipResponse.body.trim();
      debugPrint('📡 IP obtido: $ip');

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('registrarLocalizacaoAcesso');
      debugPrint('📡 Chamando Cloud Function...');
      final result = await callable.call({'ip': ip});

      debugPrint('📡 Resposta da Cloud Function: ${result.data}');

      if (result.data['success'] == true) {
        final docId = result.data['docId'] as String;
        debugPrint('📄 Documento criado com ID: $docId');

        _rastreioService.iniciarSessaoComDocumento(docId);
        await _rastreioService.registrarPaginaVista('home', 'inicial');

        debugPrint('✅ Rastreamento iniciado com sucesso para documento $docId');
      } else {
        debugPrint('❌ Falha na Cloud Function: ${result.data['error']}');
      }
    } catch (e) {
      debugPrint('❌ Erro ao registrar localização: $e');
    }
  }

  // ==================== CONTADOR DE VISITAS ====================
  Future<void> _incrementarContadorVisitas() async {
    try {
      final docRef = _firestore.collection('estatisticas').doc('visitas');

      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);

        if (docSnapshot.exists) {
          final totalAtual = docSnapshot.data()?['total'] ?? 0;
          final novoTotal = totalAtual + 1;

          transaction.update(docRef, {
            'total': novoTotal,
            'ultima_visita': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            setState(() {
              _totalVisitas = novoTotal;
              _carregandoVisitas = false;
            });
          }
        } else {
          transaction.set(docRef, {
            'total': 1,
            'ultima_visita': FieldValue.serverTimestamp(),
            'criado_em': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            setState(() {
              _totalVisitas = 1;
              _carregandoVisitas = false;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _carregandoVisitas = false);
    }
  }

  String _formatarNumero(int numero) {
    if (numero < 1000) return numero.toString();

    if (numero < 1000000) {
      final milhares = numero / 1000;
      return milhares < 10
          ? '${milhares.toStringAsFixed(1).replaceAll('.', ',')}k'
          : '${milhares.toStringAsFixed(0)}k';
    }

    final milhoes = numero / 1000000;
    return '${milhoes.toStringAsFixed(1).replaceAll('.', ',')}M';
  }

  // ==================== CONFIGURAÇÕES ====================
  Future<void> _carregarConfiguracoes() async {
    try {
      final docInscricoes =
      await _firestore.collection('configuracoes').doc('inscricoes').get();
      if (mounted) {
        setState(() {
          _inscricoesAbertas =
              docInscricoes.data()?['inscricoes_abertas'] ?? false;
          _carregandoConfigInscricoes = false;
        });
      }

      final docPortfolio = await _firestore
          .collection('configuracoes')
          .doc('portfolio_site')
          .get();
      if (mounted) {
        setState(() {
          _portfolioVisivel = docPortfolio.data()?['exibir'] ?? false;
          _carregandoConfigPortfolio = false;
        });
      }

      final docCampeonato =
      await _firestore.collection('configuracoes').doc('campeonato').get();
      if (mounted) {
        setState(() {
          _campeonatoAtivo = docCampeonato.data()?['campeonato_ativo'] ?? false;
          _carregandoConfigCampeonato = false;
        });
      }

      final docAreaAluno = await _firestore
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get();
      if (mounted) {
        setState(() {
          _areaAlunoVisivel = docAreaAluno.data()?['visivel_site'] == true;
          _carregandoConfigAreaAluno = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _inscricoesAbertas = false;
        _portfolioVisivel = false;
        _campeonatoAtivo = false;
        _areaAlunoVisivel = false;
        _carregandoConfigInscricoes = false;
        _carregandoConfigPortfolio = false;
        _carregandoConfigCampeonato = false;
        _carregandoConfigAreaAluno = false;
      });
    }
  }

  Future<void> _carregarSenhaApp() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('app').get();
      if (doc.exists && doc.data()?['senha_acesso'] != null && mounted) {
        setState(() => _senhaAcessoApp = doc.data()!['senha_acesso']);
      }
    } catch (e) {
      debugPrint('Erro ao carregar senha de acesso: $e');
    }
  }

  Future<void> _carregarConfiguracoesMenu() async {
    try {
      final doc =
      await _firestore.collection('configuracoes_site').doc('menu').get();

      if (doc.exists) {
        final data = doc.data()!;

        final List<Map<String, dynamic>> itensOrdenados = [];

        final ordemRaw = data['ordem'];
        final ordem = ordemRaw is List ? ordemRaw.map((e) => e.toString()) : <String>[];

        if (ordem.isNotEmpty) {
          itensOrdenados.add(
            _itensMenuBase.firstWhere((item) => item['id'] == 'inicio'),
          );

          for (final id in ordem) {
            if (id != 'inicio' && id != 'acessar_app') {
              final item = _itensMenuBase.firstWhere(
                    (item) => item['id'] == id,
                orElse: () => <String, dynamic>{},
              );
              if (item.isNotEmpty) itensOrdenados.add(item);
            }
          }

          for (final item in _itensMenuBase) {
            final id = item['id'];
            final jaExiste = itensOrdenados.any((i) => i['id'] == id);

            if (!jaExiste && id != 'acessar_app') {
              itensOrdenados.add(item);
            }
          }

          itensOrdenados.add(
            _itensMenuBase.firstWhere((item) => item['id'] == 'acessar_app'),
          );
        }

        if (!mounted) return;

        setState(() {
          _itensMenu =
          itensOrdenados.isEmpty ? List.from(_itensMenuBase) : itensOrdenados;

          if (data['titulos'] != null) {
            _textosPersonalizados = Map<String, dynamic>.from(data['titulos']);
          }

          if (data['visibilidade'] != null) {
            _visibilidadePersonalizada =
            Map<String, bool>.from(data['visibilidade']);
          }

          _carregandoConfigMenu = false;
        });
      } else {
        if (!mounted) return;

        setState(() {
          _itensMenu = List.from(_itensMenuBase);
          _carregandoConfigMenu = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _itensMenu = List.from(_itensMenuBase);
        _carregandoConfigMenu = false;
      });
    }
  }

  bool _deveMostrarItem(Map<String, dynamic> item) {
    if (_visibilidadePersonalizada[item['id']] == false) return false;
    if (item['id'] == 'inscricao') return _inscricoesAbertas;
    if (item['id'] == 'campeonato') return _campeonatoAtivo;
    if (item['id'] == 'portfolio') return _portfolioVisivel;
    if (item['id'] == 'area_aluno') return _areaAlunoVisivel;
    return true;
  }

  String _getLabelItem(Map<String, dynamic> item) {
    return _textosPersonalizados[item['id']] ?? item['label'];
  }

  // ==================== NAVEGAÇÃO E RASTREIO ====================
  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  void _onMenuItemTap(int index, String itemId, String label, bool isSpecial) {
    debugPrint('🔘 Menu clicado: $itemId (origem: drawer)');

    _rastreioService.registrarEvento(
      tipo: 'menu',
      nome: itemId,
      origem: 'drawer',
      metadata: {'label': label, 'isSpecial': isSpecial},
    );

    if (isSpecial) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _abrirAcessoApp();
      });
      return;
    }

    setState(() => _selectedIndex = index);
  }

  void _onCardTap(String itemId, String titulo, int index) {
    debugPrint('🔘 Card clicado: $itemId (origem: home_grid)');

    _rastreioService.registrarEvento(
      tipo: 'card',
      nome: itemId,
      origem: 'home_grid',
      metadata: {'titulo': titulo},
    );

    setState(() => _selectedIndex = index);
  }

  void _onSocialButtonTap(String rede, String url, String origem) {
    debugPrint('🔘 Botão social clicado: $rede (origem: $origem)');

    _rastreioService.registrarEvento(
      tipo: 'botao_social',
      nome: rede,
      origem: origem,
      metadata: {'url': url},
    );

    _launchURL(url);
  }

  Future<User?> _aguardarUsuarioFirebaseSalvo() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;

    try {
      user = await FirebaseAuth.instance
          .idTokenChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }

    return user;
  }

  Future<void> _abrirAcessoApp() async {
    final user = await _aguardarUsuarioFirebaseSalvo();

    if (!mounted) return;

    if (user != null) {
      _rastreioService.registrarEvento(
        tipo: 'acesso_app',
        nome: 'sessao_professor_restaurada',
        origem: 'landing_page',
        metadata: {
          'email': user.email,
          'uid': user.uid,
        },
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AuthCheck()),
      );
      return;
    }

    await _mostrarDialogoSenha();
  }

  // ==================== DIÁLOGO DE SENHA ====================
  Future<void> _mostrarDialogoSenha() async {
    _senhaController.clear();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_rounded, color: primary, size: 32),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '🔐 ACESSO RESTRITO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Este acesso é exclusivo para professores e monitores do grupo UAI Capoeira.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.35,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _senhaController,
                      obscureText: true,
                      style: TextStyle(color: t.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Digite a senha de acesso',
                        labelStyle: TextStyle(color: t.textSecondary),
                        prefixIcon:
                        Icon(Icons.password_rounded, color: primary),
                        filled: true,
                        fillColor: t.cardAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.inputRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.inputRadius),
                          borderSide: BorderSide(color: t.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(t.inputRadius),
                          borderSide: BorderSide(color: primary, width: 1.4),
                        ),
                      ),
                      autofocus: true,
                      onSubmitted: (_) => _verificarSenha(dialogContext),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 380;

                        final cancel = OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textPrimary,
                            side: BorderSide(color: t.border),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                          child: const Text(
                            'CANCELAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );

                        final acessar = ElevatedButton(
                          onPressed: () => _verificarSenha(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primary,
                            foregroundColor: _readableOn(t.primary),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                          child: const Text(
                            'ACESSAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancel,
                              const SizedBox(height: 10),
                              acessar,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: 10),
                            Expanded(child: acessar),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _verificarSenha(BuildContext dialogContext) {
    final senhaDigitada = _senhaController.text.trim();

    if (senhaDigitada == _senhaAcessoApp) {
      Navigator.pop(dialogContext);

      final user = FirebaseAuth.instance.currentUser;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => user != null ? const AuthCheck() : const LoginScreen(),
        ),
      );
      return;
    }

    final t = context.uai;

    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Senha incorreta! Acesso negado.')),
          ],
        ),
        backgroundColor: t.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    _senhaController.clear();
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex == 0) {
      final t = context.uai;
      final warning = _ensureVisible(t.warning, t.surface);

      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.all(18),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Material(
                color: t.surface,
                borderRadius: BorderRadius.circular(t.cardRadius + 2),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.cardRadius + 2),
                    border: Border.all(color: t.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.exit_to_app_rounded, size: 52, color: warning),
                      const SizedBox(height: 12),
                      Text(
                        'Sair do App?',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tem certeza que deseja fechar o aplicativo?',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: warning,
                                foregroundColor: _readableOn(warning),
                              ),
                              child: const Text('SAIR'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      return shouldExit == true;
    }

    setState(() => _selectedIndex = 0);
    return false;
  }

  // ==================== TEMA PÚBLICO ====================
  Future<void> _mostrarSeletorTemaPublico() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PublicThemeSelectorSheet(),
    );
  }

  Widget _buildThemeIconButton({bool compact = false}) {
    final t = context.uai;

    final appBarBg = UaiThemeTokens.isDarkBackground(t.background)
        ? t.cardAlt
        : t.primary;
    final fallback = _readableOn(appBarBg);
    final iconColor = _ensureVisible(t.accent, appBarBg);
    final bg = Color.alphaBlend(iconColor.withOpacity(0.16), appBarBg);

    return Tooltip(
      message: 'Escolher tema',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _mostrarSeletorTemaPublico,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: compact ? 40 : 42,
            height: compact ? 40 : 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: iconColor.withOpacity(0.36)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.palette_rounded,
              color: iconColor == appBarBg ? fallback : iconColor,
              size: compact ? 20 : 21,
            ),
          ),
        ),
      ),
    );
  }

  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final isMobile = largura < 700;
    final t = context.uai;

    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        final t = context.uai;

        return WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            backgroundColor: t.background,
            drawer: Drawer(
              width: isMobile ? largura.clamp(280.0, 330.0) : 360,
              child: _buildDrawer(),
            ),
            appBar: AppBar(
              toolbarHeight: isMobile ? 56 : 62,
              titleSpacing: 0,
              title: Text(
                _tituloPaginaAtual(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              leading: Builder(
                builder: (context) {
                  return IconButton(
                    tooltip: 'Abrir menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () {
                      _rastreioService.registrarEvento(
                        tipo: 'ui',
                        nome: 'abrir_drawer',
                        origem: 'appbar',
                      );
                      Scaffold.of(context).openDrawer();
                    },
                  );
                },
              ),
              actions: [
                _buildThemeIconButton(compact: true),
                const SizedBox(width: 8),
                if (!isMobile)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContadorVisitas(comBackground: false),
                    ),
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
            body: Stack(
              children: [
                _buildMainContent(),
                const ChatAssistenteWidget(),
              ],
            ),
          ),
        );
      },
    );
  }

  String _tituloPaginaAtual() {
    if (_itensMenu.isEmpty || _selectedIndex >= _itensMenu.length) {
      return 'UAI Capoeira';
    }

    final item = _itensMenu[_selectedIndex];
    final id = item['id']?.toString() ?? '';

    if (id == 'inicio') return 'UAI CAPOEIRA';
    return _getLabelItem(item);
  }

  Widget _buildContadorVisitas({bool comBackground = true}) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, comBackground ? t.cardAlt : t.primary);
    final onPrimary = _readableOn(t.primary);

    if (_carregandoVisitas) {
      return Container(
        width: 58,
        height: 24,
        decoration: BoxDecoration(
          color: comBackground ? t.cardAlt : onPrimary.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: comBackground ? t.border : onPrimary.withOpacity(0.16),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const ArvoreVisitasDialog(),
      ),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: comBackground ? t.cardAlt : onPrimary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: comBackground ? t.border : onPrimary.withOpacity(0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.remove_red_eye_rounded,
              size: 15,
              color: comBackground ? primary : onPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              _formatarNumero(_totalVisitas),
              style: TextStyle(
                color: comBackground ? primary : onPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final t = context.uai;

    if (_carregandoConfigMenu) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }

    final itensVisiveis = _itensMenu.where(_deveMostrarItem).toList();
    final onPrimary = _readableOn(t.primary);

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 18),
            decoration: BoxDecoration(gradient: t.primaryGradient),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: onPrimary.withOpacity(0.16)),
                  ),
                  child: _buildLogoSvg(height: 54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UAI Capoeira',
                        style: TextStyle(
                          color: onPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'União • Amizade • Inteligência',
                        style: TextStyle(
                          color: onPrimary.withOpacity(0.74),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    return IconButton(
                      icon: Icon(Icons.close_rounded, color: onPrimary),
                      onPressed: () => Navigator.pop(context),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              itemCount: itensVisiveis.length,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final item = itensVisiveis[index];
                final originalIndex = _itensMenu.indexOf(item);
                final label = _getLabelItem(item);
                final isSpecial = item['isSpecial'] ?? false;

                return _buildDrawerItem(
                  icon: item['icone'],
                  label: label,
                  index: originalIndex,
                  isSpecial: isSpecial,
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border(top: BorderSide(color: t.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSocialButton(
                        icon: Icons.photo_camera,
                        label: 'Instagram',
                        color: t.associacao,
                        url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
                        origem: 'drawer',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSocialButton(
                        icon: Icons.play_circle_fill_rounded,
                        label: 'YouTube',
                        color: t.error,
                        url: 'https://www.youtube.com/@uaicapoeira',
                        origem: 'drawer',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildThemeSelectorSmallTile(),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      '© ${DateTime.now().year} UAI CAPOEIRA',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _buildContadorVisitas(comBackground: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelectorSmallTile() {
    final t = context.uai;
    final controller = AppThemeController.instance;
    final preset = controller.currentPreset == UaiThemePreset.usuarioPersonalizado
        ? UaiThemePreset.uaiClassico
        : controller.currentPreset;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.buttonRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _mostrarSeletorTemaPublico,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.palette_rounded, color: t.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tema: ${preset.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
    required String origem,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return InkWell(
      onTap: () => _onSocialButtonTap(label.toLowerCase(), url, origem),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required int index,
    bool isSpecial = false,
  }) {
    final t = context.uai;
    final isSelected = _selectedIndex == index;
    final color = _ensureVisible(isSpecial ? t.success : t.primary, t.surface);

    return Builder(
      builder: (context) {
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              final itemId = index >= 0 && index < _itensMenu.length
                  ? _itensMenu[index]['id']?.toString() ?? ''
                  : '';

              Navigator.pop(context);

              Future.delayed(const Duration(milliseconds: 140), () {
                if (mounted) _onMenuItemTap(index, itemId, label, isSpecial);
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: isSelected
                    ? Color.alphaBlend(color.withOpacity(0.10), t.cardAlt)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? color.withOpacity(0.18) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? _readableOn(color) : color,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : t.textPrimary,
                        fontWeight:
                        isSelected ? FontWeight.w900 : FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (isSpecial)
                    Icon(Icons.lock_rounded, color: color, size: 17)
                  else if (isSelected)
                    Icon(Icons.chevron_right_rounded, color: color, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent() {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return ColoredBox(
      color: context.uai.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 1180),
          child: _buildSelectedContent(),
        ),
      ),
    );
  }

  Widget _buildSelectedContent() {
    if (_itensMenu.isNotEmpty && _selectedIndex < _itensMenu.length) {
      final itemId = _itensMenu[_selectedIndex]['id'];

      switch (itemId) {
        case 'inicio':
          return _buildHomeContent();
        case 'regimento':
          return const RegimentoScreen();
        case 'biografia':
          return const BiografiaScreen();
        case 'graduacoes':
          return const GraduacoesScreen();
        case 'inscricao':
          return const InscricaoPublicaScreen();
        case 'area_aluno':
          return const AreaAlunoLoginScreen();
        case 'campeonato':
          return const InscricaoCampeonatoScreen();
        case 'portfolio':
          return const PortfolioWebScreen();
        case 'acessar_app':
          return _buildHomeContent();
        default:
          return _buildHomeContent();
      }
    }

    return _buildHomeContent();
  }

  List<Map<String, dynamic>> _homeItemsVisiveis() {
    return _itensMenu
        .where(
          (item) =>
      item['id'] != 'inicio' &&
          item['id'] != 'acessar_app' &&
          _deveMostrarItem(item),
    )
        .toList();
  }

  Widget _buildHomeContent() {
    final largura = MediaQuery.of(context).size.width;
    final isMobile = largura < 700;
    final paddingHorizontal = isMobile ? 14.0 : 24.0;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        paddingHorizontal,
        isMobile ? 10 : 22,
        paddingHorizontal,
        22,
      ),
      children: [
        _buildHeroMobileFirst(isMobile),
        const SizedBox(height: 10),
        _buildSocialRow(isMobile),
        const SizedBox(height: 10),
        _buildTextoBoasVindas(),
        const SizedBox(height: 12),
        _buildGridAcessos(isMobile),
        const SizedBox(height: 26),
        _buildFooter(isMobile),
      ],
    );
  }

  Widget _buildHeroMobileFirst(bool isMobile) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        isMobile ? 16 : 26,
        isMobile ? 14 : 24,
        isMobile ? 14 : 22,
      ),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(isMobile ? 18 : t.cardRadius + 4),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            width: isMobile ? 214 : 284,
            height: isMobile ? 108 : 138,
            child: FittedBox(
              fit: BoxFit.contain,
              child: _buildLogoSvg(height: isMobile ? 102 : 128),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'União, Amizade e Inteligência',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: isMobile ? 11.5 : 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 7,
            runSpacing: 7,
            children: [
              _buildHeroChip(Icons.verified_rounded, 'Site oficial'),
              if (_areaAlunoVisivel)
                _buildHeroChip(Icons.school_rounded, 'Área do Aluno'),
              if (_inscricoesAbertas)
                _buildHeroChip(Icons.app_registration_rounded, 'Inscrições'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSvg({required double height}) {
    final t = context.uai;

    return FutureBuilder<String>(
      future: rootBundle.loadString('assets/images/logo_uai_tema.svg'),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final svg = _aplicarTemaNoLogoUai(snapshot.data!, t);

          return SvgPicture.string(
            svg,
            height: height,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => SizedBox(
              height: height,
              child: Center(
                child: CircularProgressIndicator(color: t.primary),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            height: height,
            width: height * 1.55,
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sports_martial_arts_rounded,
                  size: height * 0.38,
                  color: t.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'UAI Capoeira',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          height: height,
          child: Center(child: CircularProgressIndicator(color: t.primary)),
        );
      },
    );
  }

  String _aplicarTemaNoLogoUai(String svg, dynamic t) {
    final uaiColor = _colorToHex(t.primary);

    final faixaColor = _isUaiClassicoPublicTheme
        ? '#111111'
        : _colorToHex(t.cardAlt);

    final textoColor = _isUaiClassicoPublicTheme
        ? '#FFFFFF'
        : _colorToHex(_readableOn(t.cardAlt));

    final strokeColor = _isUaiClassicoPublicTheme
        ? '#111111'
        : _colorToHex(t.border);

    var result = svg;

    final replacements = <String, String>{
      '#FF0000': uaiColor,
      '#ff0000': uaiColor,
      'red': uaiColor,
      '#373435': faixaColor,
      '#FEFEFE': textoColor,
      '#fefefe': textoColor,
    };

    replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });

    result = result.replaceFirstMapped(
      RegExp(r'(<polygon[^>]*id="faixa"[^>]*)(/?>)', caseSensitive: false),
          (match) {
        var tag = match.group(1) ?? '';
        final close = match.group(2) ?? '>';

        if (RegExp(r'\sstroke="[^"]*"').hasMatch(tag)) {
          tag = tag.replaceFirst(
            RegExp(r'\sstroke="[^"]*"'),
            ' stroke="$strokeColor"',
          );
        } else {
          tag = '$tag stroke="$strokeColor"';
        }

        return '$tag$close';
      },
    );

    return result;
  }

  Widget _buildHeroChip(IconData icon, String label) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(primary.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: primary, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: primary,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialRow(bool isMobile) {
    final t = context.uai;

    final buttons = [
      _buildSocialButtonLarge(
        icon: Icons.photo_camera,
        label: 'Instagram',
        color: t.associacao,
        url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
        origem: 'home',
      ),
      _buildSocialButtonLarge(
        icon: Icons.play_circle_fill_rounded,
        label: 'YouTube',
        color: t.error,
        url: 'https://www.youtube.com/@uaicapoeira',
        origem: 'home',
      ),
    ];

    if (isMobile) {
      return Row(
        children: [
          Expanded(child: buttons[0]),
          const SizedBox(width: 10),
          Expanded(child: buttons[1]),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        buttons[0],
        const SizedBox(width: 12),
        buttons[1],
      ],
    );
  }

  Widget _buildSocialButtonLarge({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
    required String origem,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.background);

    return InkWell(
      onTap: () => _onSocialButtonTap(label.toLowerCase(), url, origem),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextoBoasVindas() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.border),
      ),
      child: Text(
        'Bem-vindo ao site oficial do Grupo UAI Capoeira. Aqui você encontra informações sobre nossa história, regimento interno, sistema de graduações, Área do Aluno e inscrições disponíveis.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          height: 1.42,
          color: t.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildGridAcessos(bool isMobile) {
    final itens = _homeItemsVisiveis();

    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final colunas = largura < 520
            ? 2
            : largura < 850
            ? 3
            : 4;

        const spacing = 12.0;
        final cardWidth = (largura - spacing * (colunas - 1)) / colunas;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: itens.map((item) {
            final id = item['id']?.toString() ?? '';
            final tituloCard = _getLabelItem(item);
            final index = _itensMenu.indexOf(item);

            return SizedBox(
              width: cardWidth,
              child: _buildQuickCard(
                titulo: tituloCard,
                descricao: _descricaoCard(id),
                icone: item['icone'],
                cor: _corCard(id),
                onTap: () => _onCardTap(id, tituloCard, index),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _corCard(String id) {
    final t = context.uai;

    switch (id) {
      case 'regimento':
        return t.info;
      case 'biografia':
        return t.success;
      case 'graduacoes':
        return t.warning;
      case 'inscricao':
        return t.associacao;
      case 'area_aluno':
        return t.eventos;
      case 'campeonato':
        return t.rifas;
      case 'portfolio':
        return t.inscricoes;
      default:
        return t.textSecondary;
    }
  }

  String _descricaoCard(String id) {
    switch (id) {
      case 'regimento':
        return 'Regras e normas';
      case 'biografia':
        return 'Nossa história';
      case 'graduacoes':
        return 'Sistema de cordas';
      case 'inscricao':
        return 'Aula experimental';
      case 'area_aluno':
        return 'Consultar dados';
      case 'campeonato':
        return 'Campeonato';
      case 'portfolio':
        return 'Eventos e fotos';
      default:
        return '';
    }
  }

  Widget _buildQuickCard({
    required String titulo,
    required String descricao,
    required IconData icone,
    required Color cor,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 126),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withOpacity(0.13)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: accent.withOpacity(0.15)),
              ),
              child: Icon(icone, size: 25, color: accent),
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.8,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              descricao,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    final t = context.uai;

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(
              '© ${DateTime.now().year} UAI CAPOEIRA',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            _buildContadorVisitas(comBackground: true),
          ],
        ),
      ],
    );
  }
}

class _PublicThemeSelectorSheet extends StatelessWidget {
  const _PublicThemeSelectorSheet();

  static const List<UaiThemePreset> _publicPresets = [
    UaiThemePreset.uaiClassico,
    UaiThemePreset.draculaUai,
    UaiThemePreset.cafeTerra,
    UaiThemePreset.verdeNeon,
  ];

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final controller = AppThemeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.currentPreset == UaiThemePreset.usuarioPersonalizado
            ? UaiThemePreset.uaiClassico
            : controller.currentPreset;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: tokens.border),
            boxShadow: tokens.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: tokens.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: tokens.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: _readableOn(tokens.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Escolher tema do site',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Disponível para visitantes: apenas temas prontos do sistema.',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _publicPresets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final preset = _publicPresets[index];
                    final selected = preset == current;

                    return _PublicPresetTile(
                      preset: preset,
                      selected: selected,
                      onTap: () async {
                        await controller.apply(
                          preset: preset,
                          mode: ThemeMode.light,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PublicPresetTile extends StatelessWidget {
  final UaiThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PublicPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;

    return Material(
      color: selected
          ? Color.alphaBlend(tokens.primary.withOpacity(0.12), tokens.card)
          : tokens.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? tokens.primary.withOpacity(0.55) : tokens.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: preset.previewColor,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: preset.previewColor.withOpacity(0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  preset.icon,
                  color: _readableOn(preset.previewColor),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? tokens.primary : tokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
