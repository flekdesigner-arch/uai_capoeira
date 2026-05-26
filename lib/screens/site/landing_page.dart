import 'package:flutter/material.dart';
import 'package:uai_capoeira/screens/auth/login_screen.dart';
import 'package:uai_capoeira/screens/inscricao/inscricao_publica_screen.dart';
import 'package:uai_capoeira/screens/site/portfolio_web_screen.dart';
import 'package:uai_capoeira/screens/inscricao/inscricao_campeonato_screen.dart';
import 'package:uai_capoeira/screens/site/biografia_screen.dart';
import 'package:uai_capoeira/screens/site/regimento_screen.dart';
import 'package:uai_capoeira/screens/site/graduacoes_screen.dart';
import 'package:uai_capoeira/screens/site/area_aluno/area_aluno_login_screen.dart';
import 'package:uai_capoeira/services/logo_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uai_capoeira/widgets/arvore_visitas_dialog.dart';
import 'package:uai_capoeira/services/rastreio_site.dart';
import 'package:uai_capoeira/widgets/chat_assistente_widget.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final LogoService _logoService = LogoService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RastreioSiteService _rastreioService = RastreioSiteService();

  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isDrawerOpen = false;

  String _senhaAcessoApp = "uai2026app";
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
    {'id': 'inicio', 'icone': Icons.home, 'label': 'INÍCIO', 'index': 0, 'isSpecial': false, 'fixo': true},
    {'id': 'regimento', 'icone': Icons.description, 'label': 'REGIMENTO INTERNO', 'index': 1, 'isSpecial': false},
    {'id': 'biografia', 'icone': Icons.auto_stories, 'label': 'BIOGRAFIA', 'index': 2, 'isSpecial': false},
    {'id': 'graduacoes', 'icone': Icons.emoji_events, 'label': 'GRADUAÇÕES', 'index': 3, 'isSpecial': false},
    {'id': 'inscricao', 'icone': Icons.app_registration, 'label': 'INSCRIÇÃO', 'index': 4, 'isSpecial': false, 'condicional': true},
    {'id': 'area_aluno', 'icone': Icons.school, 'label': 'ÁREA DO ALUNO', 'index': 5, 'isSpecial': false, 'condicional': true},
    {'id': 'campeonato', 'icone': Icons.emoji_events, 'label': 'CAMPEONATO', 'index': 6, 'isSpecial': false, 'condicional': true},
    {'id': 'portfolio', 'icone': Icons.photo_library, 'label': 'PORTFÓLIO', 'index': 7, 'isSpecial': false, 'condicional': true},
    {'id': 'acessar_app', 'icone': Icons.lock_open, 'label': 'ACESSAR APP', 'index': 8, 'isSpecial': true},
  ];

  @override
  void initState() {
    super.initState();
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

  // ==================== RASTREAMENTO ====================
  Future<void> _registrarLocalizacao() async {
    try {
      print('🌐 Obtendo IP público...');
      final ipResponse = await http.get(Uri.parse('https://api.ipify.org'));
      final ip = ipResponse.body.trim();
      print('📡 IP obtido: $ip');

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('registrarLocalizacaoAcesso');
      print('📡 Chamando Cloud Function...');
      final result = await callable.call({'ip': ip});

      print('📡 Resposta da Cloud Function: ${result.data}');

      if (result.data['success'] == true) {
        final docId = result.data['docId'] as String;
        print('📄 Documento criado com ID: $docId');

        _rastreioService.iniciarSessaoComDocumento(docId);

        await _rastreioService.registrarPaginaVista('home', 'inicial');

        print('✅ Rastreamento iniciado com sucesso para documento $docId');
      } else {
        print('❌ Falha na Cloud Function: ${result.data['error']}');
      }
    } catch (e) {
      print('❌ Erro ao registrar localização: $e');
    }
  }

  // ==================== CONTADOR DE VISITAS ====================
  Future<void> _incrementarContadorVisitas() async {
    try {
      final docRef = _firestore.collection('estatisticas').doc('visitas');
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (docSnapshot.exists) {
          final novosDados = {
            'total': (docSnapshot.data()?['total'] ?? 0) + 1,
            'ultima_visita': FieldValue.serverTimestamp(),
          };
          transaction.update(docRef, novosDados);
          setState(() {
            _totalVisitas = (docSnapshot.data()?['total'] ?? 0) + 1;
            _carregandoVisitas = false;
          });
        } else {
          final novosDados = {
            'total': 1,
            'ultima_visita': FieldValue.serverTimestamp(),
            'criado_em': FieldValue.serverTimestamp(),
          };
          transaction.set(docRef, novosDados);
          setState(() {
            _totalVisitas = 1;
            _carregandoVisitas = false;
          });
        }
      });
    } catch (e) {
      setState(() => _carregandoVisitas = false);
    }
  }

  String _formatarNumero(int numero) {
    if (numero < 1000) return numero.toString();
    if (numero < 1000000) {
      final double milhares = numero / 1000;
      return milhares < 10 ? '${milhares.toStringAsFixed(1).replaceAll('.', ',')}k' : '${milhares.toStringAsFixed(0)}k';
    } else {
      final double milhoes = numero / 1000000;
      return '${milhoes.toStringAsFixed(1).replaceAll('.', ',')}M';
    }
  }

  // ==================== CONFIGURAÇÕES ====================
  Future<void> _carregarConfiguracoes() async {
    try {
      final docInscricoes = await _firestore.collection('configuracoes').doc('inscricoes').get();
      setState(() {
        _inscricoesAbertas = docInscricoes.data()?['inscricoes_abertas'] ?? false;
        _carregandoConfigInscricoes = false;
      });

      final docPortfolio = await _firestore.collection('configuracoes').doc('portfolio_site').get();
      setState(() {
        _portfolioVisivel = docPortfolio.data()?['exibir'] ?? false;
        _carregandoConfigPortfolio = false;
      });

      final docCampeonato = await _firestore.collection('configuracoes').doc('campeonato').get();
      setState(() {
        _campeonatoAtivo = docCampeonato.data()?['campeonato_ativo'] ?? false;
        _carregandoConfigCampeonato = false;
      });

      final docAreaAluno = await _firestore.collection('configuracoes_site').doc('area_aluno').get();
      setState(() {
        _areaAlunoVisivel = docAreaAluno.data()?['visivel_site'] == true;
        _carregandoConfigAreaAluno = false;
      });
    } catch (e) {
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
      if (doc.exists && doc.data()?['senha_acesso'] != null) {
        setState(() => _senhaAcessoApp = doc.data()!['senha_acesso']);
      }
    } catch (e) {}
  }

  Future<void> _carregarConfiguracoesMenu() async {
    try {
      final doc = await _firestore.collection('configuracoes_site').doc('menu').get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          final List<dynamic>? ordem = data['ordem'];
          if (ordem != null && ordem.isNotEmpty) {
            final List<Map<String, dynamic>> itensOrdenados = [];
            itensOrdenados.add(_itensMenuBase.firstWhere((item) => item['id'] == 'inicio'));

            for (String id in ordem) {
              if (id != 'inicio' && id != 'acessar_app') {
                final item = _itensMenuBase.firstWhere((item) => item['id'] == id, orElse: () => const {});
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

            itensOrdenados.add(_itensMenuBase.firstWhere((item) => item['id'] == 'acessar_app'));
            _itensMenu = itensOrdenados;
          } else {
            _itensMenu = List.from(_itensMenuBase);
          }

          if (data['titulos'] != null) _textosPersonalizados = Map<String, dynamic>.from(data['titulos']);
          if (data['visibilidade'] != null) _visibilidadePersonalizada = Map<String, bool>.from(data['visibilidade']);
          _carregandoConfigMenu = false;
        });
      } else {
        setState(() {
          _itensMenu = List.from(_itensMenuBase);
          _carregandoConfigMenu = false;
        });
      }
    } catch (e) {
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
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  void _onMenuItemTap(int index, String itemId, String label, bool isSpecial) {
    print('🔘 Menu clicado: $itemId (origem: drawer)');
    _rastreioService.registrarEvento(
      tipo: 'menu',
      nome: itemId,
      origem: 'drawer',
      metadata: {'label': label, 'isSpecial': isSpecial},
    );

    if (isSpecial) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _mostrarDialogoSenha();
      });
      return;
    }

    setState(() {
      _selectedIndex = index;
      _isDrawerOpen = false;
    });
  }

  void _onCardTap(String itemId, String titulo, int index) {
    print('🔘 Card clicado: $itemId (origem: home_grid)');
    _rastreioService.registrarEvento(
      tipo: 'card',
      nome: itemId,
      origem: 'home_grid',
      metadata: {'titulo': titulo},
    );
    setState(() {
      _selectedIndex = index;
      _isDrawerOpen = false;
    });
  }

  void _onSocialButtonTap(String rede, String url, String origem) {
    print('🔘 Botão social clicado: $rede (origem: $origem)');
    _rastreioService.registrarEvento(
      tipo: 'botao_social',
      nome: rede,
      origem: origem,
      metadata: {'url': url},
    );
    _launchURL(url);
  }

  // ==================== DIÁLOGO DE SENHA ====================
  Future<void> _mostrarDialogoSenha() async {
    _senhaController.clear();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
                child: Icon(Icons.lock, color: Colors.red.shade900, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('🔐 ACESSO RESTRITO', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Este acesso é exclusivo para professores e monitores do grupo UAI Capoeira.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _senhaController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Digite a senha de acesso',
                  prefixIcon: const Icon(Icons.password),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                autofocus: true,
                onSubmitted: (_) => _verificarSenha(context),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => _verificarSenha(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('ACESSAR'),
            ),
          ],
        );
      },
    );
  }

  void _verificarSenha(BuildContext dialogContext) {
    final senhaDigitada = _senhaController.text.trim();

    if (senhaDigitada == _senhaAcessoApp) {
      Navigator.pop(dialogContext);
      Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Senha incorreta! Acesso negado.')),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
      _senhaController.clear();
    }
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex == 0) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                child: Icon(Icons.exit_to_app, color: Colors.orange.shade700, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('Sair do App?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text('Tem certeza que deseja fechar o aplicativo?', textAlign: TextAlign.center),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.green)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('SAIR'),
            ),
          ],
        ),
      );
      return shouldExit == true;
    } else {
      setState(() => _selectedIndex = 0);
      return false;
    }
  }

  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final isMobile = largura < 700;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        drawer: Drawer(
          width: isMobile ? largura.clamp(280.0, 330.0) : 360,
          child: _buildDrawer(),
        ),
        appBar: AppBar(
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: isMobile ? 56 : 62,
          titleSpacing: 0,
          title: const SizedBox.shrink(),
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
            if (!isMobile)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildContadorVisitas(comBackground: false),
                ),
              ),
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
    if (_carregandoVisitas) {
      return Container(
        width: 58,
        height: 24,
        decoration: BoxDecoration(
          color: comBackground ? Colors.grey.shade200 : Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (context) => const ArvoreVisitasDialog(),
      ),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: comBackground ? Colors.red.shade50 : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: comBackground ? Colors.red.shade100 : Colors.white.withOpacity(0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.remove_red_eye_rounded,
              size: 15,
              color: comBackground ? Colors.red.shade900 : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              _formatarNumero(_totalVisitas),
              style: TextStyle(
                color: comBackground ? Colors.red.shade900 : Colors.white,
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
    if (_carregandoConfigMenu) {
      return const Center(child: CircularProgressIndicator());
    }

    final itensVisiveis = _itensMenu.where(_deveMostrarItem).toList();

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade900, Colors.red.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _logoService.buildLogo(height: 54),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UAI Capoeira',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'União • Amizade • Inteligência',
                        style: TextStyle(
                          color: Colors.white70,
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
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
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
              color: Colors.grey.shade50,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSocialButton(
                        icon: Icons.photo_camera,
                        label: 'Instagram',
                        color: Colors.purple,
                        url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
                        origem: 'drawer',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSocialButton(
                        icon: Icons.play_circle_fill_rounded,
                        label: 'YouTube',
                        color: Colors.red,
                        url: 'https://www.youtube.com/@uaicapoeira',
                        origem: 'drawer',
                      ),
                    ),
                  ],
                ),
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
                        color: Colors.grey.shade600,
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

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
    required String origem,
  }) {
    return InkWell(
      onTap: () => _onSocialButtonTap(label.toLowerCase(), url, origem),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
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
    final isSelected = _selectedIndex == index;
    final color = isSpecial ? Colors.green.shade700 : Colors.red.shade900;

    return Builder(
      builder: (context) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              final itemId = index >= 0 && index < _itensMenu.length
                  ? _itensMenu[index]['id']?.toString() ?? ''
                  : '';

              Navigator.pop(context);

              Future.delayed(const Duration(milliseconds: 140), () {
                if (mounted) {
                  _onMenuItemTap(index, itemId, label, isSpecial);
                }
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? color.withOpacity(0.16) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? Colors.white : color,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : Colors.grey.shade800,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
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
      color: Colors.grey.shade50,
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
        .where((item) =>
    item['id'] != 'inicio' &&
        item['id'] != 'acessar_app' &&
        _deveMostrarItem(item))
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
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        isMobile ? 16 : 26,
        isMobile ? 14 : 24,
        isMobile ? 14 : 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 18 : 28),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: isMobile ? 206 : 270,
            height: isMobile ? 100 : 128,
            child: FittedBox(
              fit: BoxFit.contain,
              child: _logoService.buildLogo(height: isMobile ? 96 : 120),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'União, Amizade e Inteligência',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade800,
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

  Widget _buildHeroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.red.shade800, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.red.shade800,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialRow(bool isMobile) {
    final buttons = [
      _buildSocialButtonLarge(
        icon: Icons.photo_camera,
        label: 'Instagram',
        color: Colors.purple,
        url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
        origem: 'home',
      ),
      _buildSocialButtonLarge(
        icon: Icons.play_circle_fill_rounded,
        label: 'YouTube',
        color: Colors.red,
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
    return InkWell(
      onTap: () => _onSocialButtonTap(label.toLowerCase(), url, origem),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
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
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Text(
        'Bem-vindo ao site oficial do Grupo UAI Capoeira. Aqui você encontra informações sobre nossa história, regimento interno, sistema de graduações, Área do Aluno e inscrições disponíveis.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          height: 1.42,
          color: Colors.grey.shade700,
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
    switch (id) {
      case 'regimento':
        return Colors.blue;
      case 'biografia':
        return Colors.green;
      case 'graduacoes':
        return Colors.orange;
      case 'inscricao':
        return Colors.purple;
      case 'area_aluno':
        return Colors.indigo;
      case 'campeonato':
        return Colors.amber.shade800;
      case 'portfolio':
        return Colors.teal;
      default:
        return Colors.grey;
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 126),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cor.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icone, size: 25, color: cor),
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
                color: Colors.grey.shade600,
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
                color: Colors.grey.shade600,
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
