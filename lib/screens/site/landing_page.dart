import 'package:flutter/material.dart';
import 'package:uai_capoeira/screens/auth/login_screen.dart';
import 'package:uai_capoeira/screens/inscricao/inscricao_publica_screen.dart';
import 'package:uai_capoeira/screens/site/portfolio_web_screen.dart';
import 'package:uai_capoeira/screens/inscricao/inscricao_campeonato_screen.dart';
import 'package:uai_capoeira/screens/site/biografia_screen.dart';
import 'package:uai_capoeira/screens/site/regimento_screen.dart';
import 'package:uai_capoeira/screens/site/graduacoes_screen.dart';
import 'package:uai_capoeira/services/logo_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final LogoService _logoService = LogoService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isDrawerOpen = false;

  // 🔐 SENHA DE ACESSO AO APP (agora DINÂMICA - carregada do Firestore)
  String _senhaAcessoApp = "uai2026app"; // Valor padrão

  // Controlador para o campo de senha
  final TextEditingController _senhaController = TextEditingController();

  // Controles de configurações existentes
  bool _inscricoesAbertas = false;
  bool _carregandoConfigInscricoes = true;
  bool _portfolioVisivel = false;
  bool _carregandoConfigPortfolio = true;
  bool _campeonatoAtivo = false;
  bool _carregandoConfigCampeonato = true;

  // 👁️ CONTADOR DE VISITAS
  int _totalVisitas = 0;
  bool _carregandoVisitas = true;

  // CONFIGURAÇÕES DO MENU (ordem, textos, visibilidade)
  List<Map<String, dynamic>> _itensMenu = [];
  Map<String, dynamic> _textosPersonalizados = {};
  Map<String, bool> _visibilidadePersonalizada = {};
  bool _carregandoConfigMenu = true;

  // Lista base de itens do menu (fonte da verdade)
  final List<Map<String, dynamic>> _itensMenuBase = [
    {
      'id': 'inicio',
      'icone': Icons.home,
      'label': 'INÍCIO',
      'index': 0,
      'isSpecial': false,
      'fixo': true, // INÍCIO é fixo no topo
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
      'condicional': true, // Depende de _inscricoesAbertas
    },
    {
      'id': 'campeonato',
      'icone': Icons.emoji_events,
      'label': 'CAMPEONATO',
      'index': 5,
      'isSpecial': false,
      'condicional': true, // Depende de _campeonatoAtivo
    },
    {
      'id': 'portfolio',
      'icone': Icons.photo_library, // Ícone de portfólio (não timeline)
      'label': 'PORTFÓLIO', // Nome correto para o usuário
      'index': 6,
      'isSpecial': false,
      'condicional': true, // Depende de _portfolioVisivel
    },
    {
      'id': 'acessar_app',
      'icone': Icons.lock_open,
      'label': 'ACESSAR APP',
      'index': 7,
      'isSpecial': true, // Abre diálogo de senha
    },
  ];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _incrementarContadorVisitas();
    _carregarSenhaApp();
    _carregarConfiguracoesMenu();
  }

  @override
  void dispose() {
    _senhaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== MÉTODOS EXISTENTES ====================

  Future<void> _incrementarContadorVisitas() async {
    try {
      print('📊 Atualizando contador de visitas...');
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
      print('✅ Contador atualizado: $_totalVisitas visitas');
    } catch (e) {
      print('❌ Erro ao atualizar contador: $e');
      setState(() => _carregandoVisitas = false);
    }
  }

  String _formatarNumero(int numero) {
    if (numero < 1000) return numero.toString();
    if (numero < 1000000) {
      final double milhares = numero / 1000;
      if (milhares < 10) {
        return '${milhares.toStringAsFixed(1).replaceAll('.', ',')}k';
      } else {
        return '${milhares.toStringAsFixed(0)}k';
      }
    } else {
      final double milhoes = numero / 1000000;
      return '${milhoes.toStringAsFixed(1).replaceAll('.', ',')}M';
    }
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      print('📥 Carregando configurações...');

      // Configuração de inscrições
      final docInscricoes = await _firestore.collection('configuracoes').doc('inscricoes').get();
      setState(() {
        if (docInscricoes.exists) {
          _inscricoesAbertas = docInscricoes.data()?['inscricoes_abertas'] ?? false;
        } else {
          _inscricoesAbertas = false;
        }
        _carregandoConfigInscricoes = false;
      });

      // Configuração do portfólio
      final docPortfolio = await _firestore.collection('configuracoes').doc('portfolio_site').get();
      setState(() {
        if (docPortfolio.exists) {
          _portfolioVisivel = docPortfolio.data()?['exibir'] ?? false;
        } else {
          _portfolioVisivel = false;
        }
        _carregandoConfigPortfolio = false;
      });

      // Configuração do campeonato
      final docCampeonato = await _firestore.collection('configuracoes').doc('campeonato').get();
      setState(() {
        if (docCampeonato.exists) {
          _campeonatoAtivo = docCampeonato.data()?['campeonato_ativo'] ?? false;
        } else {
          _campeonatoAtivo = false;
        }
        _carregandoConfigCampeonato = false;
      });
    } catch (e) {
      print('❌ Erro ao carregar configurações: $e');
      setState(() {
        _inscricoesAbertas = false;
        _portfolioVisivel = false;
        _campeonatoAtivo = false;
        _carregandoConfigInscricoes = false;
        _carregandoConfigPortfolio = false;
        _carregandoConfigCampeonato = false;
      });
    }
  }

  // ==================== NOVOS MÉTODOS ====================

  Future<void> _carregarSenhaApp() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('app').get();
      if (doc.exists && doc.data()?['senha_acesso'] != null) {
        setState(() {
          _senhaAcessoApp = doc.data()!['senha_acesso'];
          print('🔐 Senha carregada do Firestore: $_senhaAcessoApp');
        });
      }
    } catch (e) {
      print('⚠️ Erro ao carregar senha, usando padrão: $e');
    }
  }

  Future<void> _carregarConfiguracoesMenu() async {
    try {
      final doc = await _firestore.collection('configuracoes_site').doc('menu').get();

      if (doc.exists) {
        final data = doc.data()!;

        setState(() {
          // 1️⃣ CARREGA ORDEM PERSONALIZADA
          final List<dynamic>? ordem = data['ordem'];

          if (ordem != null && ordem.isNotEmpty) {
            // Constrói lista na ordem personalizada
            final List<Map<String, dynamic>> itensOrdenados = [];

            // Primeiro: INÍCIO (sempre primeiro)
            itensOrdenados.add(_itensMenuBase.firstWhere((item) => item['id'] == 'inicio'));

            // Depois: itens na ordem salva (exceto INÍCIO e ACESSAR APP)
            for (String id in ordem) {
              if (id != 'inicio' && id != 'acessar_app') {
                final item = _itensMenuBase.firstWhere(
                      (item) => item['id'] == id,
                  orElse: () => const {},
                );
                if (item.isNotEmpty) {
                  itensOrdenados.add(item);
                }
              }
            }

            // Por último: ACESSAR APP (sempre no final)
            itensOrdenados.add(_itensMenuBase.firstWhere((item) => item['id'] == 'acessar_app'));

            _itensMenu = itensOrdenados;
          } else {
            // Se não tem ordem personalizada, usa a base
            _itensMenu = List.from(_itensMenuBase);
          }

          // 2️⃣ CARREGA TEXTOS PERSONALIZADOS
          if (data['titulos'] != null) {
            _textosPersonalizados = Map<String, dynamic>.from(data['titulos']);
          }

          // 3️⃣ CARREGA VISIBILIDADE PERSONALIZADA
          if (data['visibilidade'] != null) {
            _visibilidadePersonalizada = Map<String, bool>.from(data['visibilidade']);
          }

          _carregandoConfigMenu = false;
        });
      } else {
        setState(() {
          _itensMenu = List.from(_itensMenuBase);
          _carregandoConfigMenu = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar configurações do menu: $e');
      setState(() {
        _itensMenu = List.from(_itensMenuBase);
        _carregandoConfigMenu = false;
      });
    }
  }

  // Verifica se um item deve ser mostrado (condicionais + visibilidade)
  bool _deveMostrarItem(Map<String, dynamic> item) {
    // Verifica visibilidade personalizada primeiro
    if (_visibilidadePersonalizada[item['id']] == false) {
      return false;
    }

    // Verifica condicionais originais
    if (item['id'] == 'inscricao') {
      return _inscricoesAbertas;
    }
    if (item['id'] == 'campeonato') {
      return _campeonatoAtivo;
    }
    if (item['id'] == 'portfolio') {
      return _portfolioVisivel;
    }

    return true; // Itens sem condicional sempre aparecem
  }

  // Pega o label personalizado de um item (se existir)
  String _getLabelItem(Map<String, dynamic> item) {
    if (_textosPersonalizados[item['id']] != null) {
      return _textosPersonalizados[item['id']];
    }
    return item['label'];
  }

  // ==================== MÉTODOS DE INTERAÇÃO ====================

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

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
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(child: Text('Senha incorreta! Acesso negado.')),
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
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
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

  // ==================== CONSTRUÇÃO DA UI ====================

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.red.shade900,
          title: const Text(''),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => setState(() => _isDrawerOpen = !_isDrawerOpen),
          ),
        ),
        body: Stack(
          children: [
            _buildMainContent(),
            if (_isDrawerOpen)
              GestureDetector(
                onTap: () => setState(() => _isDrawerOpen = false),
                child: Container(
                  color: Colors.black54,
                  child: Row(
                    children: [
                      Container(
                        width: isMobile ? 280 : 320,
                        height: double.infinity,
                        color: Colors.white,
                        child: _buildDrawer(),
                      ),
                      Expanded(child: Container()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContadorVisitas({bool comBackground = true}) {
    if (_carregandoVisitas) {
      return Container(
        width: 60,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: comBackground ? BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade100),
      ) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.remove_red_eye,
            size: 16,
            color: comBackground ? Colors.red.shade900 : Colors.red.shade300,
          ),
          const SizedBox(width: 4),
          Text(
            _formatarNumero(_totalVisitas),
            style: TextStyle(
              color: comBackground ? Colors.red.shade900 : Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // DRAWER COM ORDEM DINÂMICA
  Widget _buildDrawer() {
    if (_carregandoConfigMenu) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(height: 20, color: Colors.white),
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _isDrawerOpen = false),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: _itensMenu.map((item) {
              // Só mostra se deve aparecer
              if (!_deveMostrarItem(item)) {
                return const SizedBox.shrink();
              }

              // Pega o label personalizado
              final label = _getLabelItem(item);

              // Pega o índice real (baseado na posição atual)
              final index = _itensMenu.indexOf(item);

              return _buildDrawerItem(
                icon: item['icone'],
                label: label,
                index: index,
                isSpecial: item['isSpecial'] ?? false,
              );
            }).toList(),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSocialButton(
                    icon: Icons.photo_camera,
                    label: 'Instagram',
                    color: Colors.purple,
                    url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
                  ),
                  _buildSocialButton(
                    icon: Icons.play_circle_fill,
                    label: 'YouTube',
                    color: Colors.red,
                    url: 'https://www.youtube.com/@uaicapoeira',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '© ${DateTime.now().year} UAI CAPOEIRA',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  _buildContadorVisitas(comBackground: false),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchURL(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
              _isDrawerOpen = false;
              if (isSpecial) _mostrarDialogoSenha();
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.red.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSpecial ? Colors.green : (isSelected ? Colors.red.shade900 : Colors.grey.shade600),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSpecial ? Colors.green : (isSelected ? Colors.red.shade900 : Colors.grey.shade800),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
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

  Widget _buildMainContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.red.shade50, Colors.white],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isMobile ? double.infinity : 1200,
          ),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 24),
            child: _buildSelectedContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedContent() {
    // Mapeia o índice para a tela correta baseado no ID do item
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
        case 'campeonato':
          return const InscricaoCampeonatoScreen();
        case 'portfolio':
          return const PortfolioWebScreen(); // MANTÉM PortfolioWebScreen (que é a timeline)
        case 'acessar_app':
        // Não tem tela, abre diálogo
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mostrarDialogoSenha();
            setState(() => _selectedIndex = 0); // Volta pra home
          });
          return _buildHomeContent();
        default:
          return _buildHomeContent();
      }
    }

    return _buildHomeContent();
  }

  Widget _buildHomeContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return ListView(
      controller: _scrollController,
      children: [
        const SizedBox(height: 20),
        Center(child: _logoService.buildLogo(height: isMobile ? 120 : 150)),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'UAI CAPOEIRA: União, Amizade e Inteligência',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialButtonLarge(
              icon: Icons.photo_camera,
              label: 'Instagram',
              color: Colors.purple,
              url: 'https://www.instagram.com/uai.capoeira.bocaiuva/',
            ),
            const SizedBox(width: 20),
            _buildSocialButtonLarge(
              icon: Icons.play_circle_fill,
              label: 'YouTube',
              color: Colors.red,
              url: 'https://www.youtube.com/@uaicapoeira',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Bem-vindo ao site oficial do Grupo UAI Capoeira. '
                'Aqui você encontra informações sobre nossa história, '
                'regimento interno, sistema de graduações e pode solicitar '
                'uma aula experimental.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 30),

        // 🔥 CARDS DINÂMICOS - GERADOS NA MESMA ORDEM DO MENU
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: _itensMenu
              .where((item) =>
          item['id'] != 'inicio' &&
              item['id'] != 'acessar_app' &&
              _deveMostrarItem(item))
              .map((item) {

            // Define cores e descrições baseadas no ID
            Color cor;
            String descricao;
            IconData icone = item['icone'];

            switch (item['id']) {
              case 'regimento':
                cor = Colors.blue;
                descricao = 'Regras e normas';
                break;
              case 'biografia':
                cor = Colors.green;
                descricao = 'Nossa história';
                break;
              case 'graduacoes':
                cor = Colors.orange;
                descricao = 'Sistema de cordas';
                break;
              case 'inscricao':
                cor = Colors.purple;
                descricao = 'Aula experimental';
                break;
              case 'campeonato':
                cor = Colors.amber.shade800;
                descricao = '1° Campeonato UAI Capoeira';
                break;
              case 'portfolio':
                cor = Colors.teal;
                descricao = 'Nossos eventos';
                break;
              default:
                cor = Colors.grey;
                descricao = '';
            }

            return _buildQuickCard(
              titulo: _getLabelItem(item),
              descricao: descricao,
              icone: icone,
              cor: cor,
              onTap: () {
                final index = _itensMenu.indexOf(item);
                setState(() {
                  _selectedIndex = index;
                  _isDrawerOpen = false;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '© ${DateTime.now().year} UAI CAPOEIRA',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                height: 12,
                width: 1,
                color: Colors.grey.shade300,
              ),
              _buildContadorVisitas(comBackground: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButtonLarge({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchURL(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
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
      child: Container(
        width: 160,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icone, size: 30, color: cor),
            ),
            const SizedBox(height: 8),
            Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(descricao, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}