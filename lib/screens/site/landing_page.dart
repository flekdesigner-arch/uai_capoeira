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

  // 🔐 SENHA DE ACESSO AO APP (para professores/monitores)
  final String _senhaAcessoApp = "uai2026app";

  // Controlador para o campo de senha
  final TextEditingController _senhaController = TextEditingController();

  // Controles de configurações
  bool _inscricoesAbertas = false;
  bool _carregandoConfigInscricoes = true;
  bool _portfolioVisivel = false;
  bool _carregandoConfigPortfolio = true;
  bool _campeonatoAtivo = false;
  bool _carregandoConfigCampeonato = true;

  // 👁️ CONTADOR DE VISITAS
  int _totalVisitas = 0;
  bool _carregandoVisitas = true;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _incrementarContadorVisitas();
  }

  @override
  void dispose() {
    _senhaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 👁️ MÉTODO PARA INCREMENTAR E CARREGAR VISITAS
  Future<void> _incrementarContadorVisitas() async {
    try {
      print('📊 Atualizando contador de visitas...');

      // Referência para o documento de estatísticas
      final docRef = _firestore.collection('estatisticas').doc('visitas');

      // Usando transação para garantir incremento atômico
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);

        if (docSnapshot.exists) {
          // Documento existe - incrementa
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
          // Primeira visita - cria documento
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
      setState(() {
        _carregandoVisitas = false;
      });
    }
  }

  // 🔧 MÉTODO PARA FORMATAR NÚMERO (1.234 ou 2.5k)
  String _formatarNumero(int numero) {
    if (numero < 1000) {
      return numero.toString();
    } else if (numero < 1000000) {
      // Ex: 1.234 ou 15.6k
      final double milhares = numero / 1000;
      if (milhares < 10) {
        return '${milhares.toStringAsFixed(1).replaceAll('.', ',')}k';
      } else {
        return '${milhares.toStringAsFixed(0)}k';
      }
    } else {
      // Ex: 1.2M
      final double milhoes = numero / 1000000;
      return '${milhoes.toStringAsFixed(1).replaceAll('.', ',')}M';
    }
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      print('📥 Carregando configurações...');

      // Configuração de inscrições
      final docInscricoes = await _firestore.collection('configuracoes').doc('inscricoes').get();
      if (docInscricoes.exists) {
        final data = docInscricoes.data()!;
        setState(() {
          _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
          _carregandoConfigInscricoes = false;
        });
      } else {
        setState(() {
          _inscricoesAbertas = false;
          _carregandoConfigInscricoes = false;
        });
      }

      // Configuração do portfólio
      final docPortfolio = await _firestore.collection('configuracoes').doc('portfolio_site').get();
      if (docPortfolio.exists) {
        final data = docPortfolio.data()!;
        setState(() {
          _portfolioVisivel = data['exibir'] ?? false;
          _carregandoConfigPortfolio = false;
        });
      } else {
        setState(() {
          _portfolioVisivel = false;
          _carregandoConfigPortfolio = false;
        });
      }

      // Configuração do campeonato
      final docCampeonato = await _firestore.collection('configuracoes').doc('campeonato').get();
      if (docCampeonato.exists) {
        final data = docCampeonato.data()!;
        setState(() {
          _campeonatoAtivo = data['campeonato_ativo'] ?? false;
          _carregandoConfigCampeonato = false;
        });
      } else {
        setState(() {
          _campeonatoAtivo = false;
          _carregandoConfigCampeonato = false;
        });
      }
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

  // 👁️ WIDGET DO CONTADOR DE VISITAS (REUTILIZÁVEL)
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

    final container = Container(
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

    return container;
  }

  Widget _buildDrawer() {
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
            children: [
              _buildDrawerItem(icon: Icons.home, label: 'INÍCIO', index: 0),
              _buildDrawerItem(icon: Icons.description, label: 'REGIMENTO INTERNO', index: 1),
              _buildDrawerItem(icon: Icons.auto_stories, label: 'BIOGRAFIA', index: 2),
              _buildDrawerItem(icon: Icons.emoji_events, label: 'GRADUAÇÕES', index: 3),
              if (!_carregandoConfigInscricoes && _inscricoesAbertas)
                _buildDrawerItem(icon: Icons.app_registration, label: 'INSCRIÇÃO', index: 4),
              if (!_carregandoConfigCampeonato && _campeonatoAtivo)
                _buildDrawerItem(icon: Icons.emoji_events, label: 'CAMPEONATO', index: 5),
              if (!_carregandoConfigPortfolio && _portfolioVisivel)
                _buildDrawerItem(icon: Icons.photo_library, label: 'PORTFÓLIO', index: 6),
              const Divider(height: 32),
              _buildDrawerItem(icon: Icons.lock_open, label: 'ACESSAR APP', index: 7, isSpecial: true),
            ],
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
              // 👁️ CONTADOR NO DRAWER
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
    switch (_selectedIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const RegimentoScreen();
      case 2:
        return const BiografiaScreen();
      case 3:
        return const GraduacoesScreen();
      case 4:
        return const InscricaoPublicaScreen();
      case 5:
        return const InscricaoCampeonatoScreen();
      case 6:
        return const PortfolioWebScreen();
      default:
        return _buildHomeContent();
    }
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
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            if (!_carregandoConfigInscricoes && _inscricoesAbertas)
              _buildQuickCard(
                titulo: 'INSCRIÇÃO',
                descricao: 'Aula experimental',
                icone: Icons.app_registration,
                cor: Colors.purple,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
            if (!_carregandoConfigCampeonato && _campeonatoAtivo)
              _buildQuickCard(
                titulo: 'CAMPEONATO',
                descricao: '1° Campeonato UAI Capoeira',
                icone: Icons.emoji_events,
                cor: Colors.amber.shade800,
                onTap: () => setState(() => _selectedIndex = 5),
              ),
            if (!_carregandoConfigPortfolio && _portfolioVisivel)
              _buildQuickCard(
                titulo: 'PORTFÓLIO',
                descricao: 'Nossos eventos',
                icone: Icons.photo_library,
                cor: Colors.teal,
                onTap: () => setState(() => _selectedIndex = 6),
              ),
            _buildQuickCard(
              titulo: 'REGIMENTO',
              descricao: 'Regras e normas',
              icone: Icons.description,
              cor: Colors.blue,
              onTap: () => setState(() => _selectedIndex = 1),
            ),
            _buildQuickCard(
              titulo: 'BIOGRAFIA',
              descricao: 'Nossa história',
              icone: Icons.auto_stories,
              cor: Colors.green,
              onTap: () => setState(() => _selectedIndex = 2),
            ),
            _buildQuickCard(
              titulo: 'GRADUAÇÕES',
              descricao: 'Sistema de cordas',
              icone: Icons.emoji_events,
              cor: Colors.orange,
              onTap: () => setState(() => _selectedIndex = 3),
            ),
          ],
        ),
        const SizedBox(height: 40),
        // 👁️ CONTADOR NO RODAPÉ DA HOME
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