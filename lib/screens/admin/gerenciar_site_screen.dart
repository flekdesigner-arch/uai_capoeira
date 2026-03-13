import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'regimento_interno_screen.dart';
import 'biografia_screen.dart';
import 'graduacoes_site_screen.dart';
import 'configurar_inscricoes_screen.dart';
import 'gerenciar_timeline_screen.dart';
import 'configurar_campeonato_screen.dart';
import 'configurar_menu_screen.dart';
import 'package:uai_capoeira/screens/site/editar_textos_screen.dart';
import 'package:uai_capoeira/services/site_config_service.dart';

class GerenciarSiteScreen extends StatefulWidget {
  const GerenciarSiteScreen({super.key});

  @override
  State<GerenciarSiteScreen> createState() => _GerenciarSiteScreenState();
}

class _GerenciarSiteScreenState extends State<GerenciarSiteScreen> {
  final SiteConfigService _configService = SiteConfigService();
  bool _carregando = true;
  String? _erro;

  // Configurações carregadas do Firestore
  Map<String, dynamic> _configuracoes = {};

  // Lista base de seções
  final List<Map<String, dynamic>> _secoesBase = [
    {
      'id': 'regimento',
      'titulo': 'REGIMENTO INTERNO',
      'icone': Icons.description,
      'cor': Colors.blue,
      'colecao': 'site_regimento',
      'descricao': 'Editar regras e normas do grupo',
      'tela': 'regimento',
      'ordem_padrao': 1,
    },
    {
      'id': 'biografia',
      'titulo': 'BIOGRAFIA',
      'icone': Icons.auto_stories,
      'cor': Colors.green,
      'colecao': 'site_biografia',
      'descricao': 'Editar história do grupo',
      'tela': 'biografia',
      'ordem_padrao': 2,
    },
    {
      'id': 'graduacoes',
      'titulo': 'GRADUAÇÕES',
      'icone': Icons.emoji_events,
      'cor': Colors.orange,
      'colecao': 'site_graduacoes',
      'descricao': 'Editar sistema de cordas',
      'tela': 'graduacoes',
      'ordem_padrao': 3,
    },
    {
      'id': 'inscricao',
      'titulo': 'INSCRIÇÃO',
      'icone': Icons.app_registration,
      'cor': Colors.red,
      'colecao': 'site_inscricao',
      'descricao': 'Configurar inscrições para aula experimental',
      'tela': 'inscricao',
      'ordem_padrao': 4,
    },
    {
      'id': 'campeonato',
      'titulo': 'CAMPEONATO',
      'icone': Icons.emoji_events,
      'cor': Colors.amber.shade800,
      'colecao': 'campeonato_inscricoes',
      'descricao': 'Configurar 1° Campeonato UAI Capoeira',
      'tela': 'campeonato',
      'ordem_padrao': 5,
    },
    {
      'id': 'portfolio',
      'titulo': 'LINHA DO TEMPO',
      'icone': Icons.timeline,
      'cor': Colors.purple,
      'colecao': 'timeline_publicacoes',
      'descricao': 'Gerenciar publicações do site',
      'tela': 'timeline',
      'ordem_padrao': 6,
    },
  ];

  // Lista final (com configurações aplicadas)
  late List<Map<String, dynamic>> _secoes;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  Future<void> _carregarConfiguracoes() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // Carrega configurações do Firestore
      final configs = await _configService.carregarConfiguracoesSite();

      setState(() {
        _configuracoes = configs;

        // Aplica as configurações na lista base
        _secoes = _secoesBase.map((secao) {
          final Map<String, dynamic> secaoModificada = Map.from(secao);

          // Aplica título personalizado se existir
          if (configs['titulos'] != null && configs['titulos'][secao['id']] != null) {
            secaoModificada['titulo'] = configs['titulos'][secao['id']];
          }

          // Aplica descrição personalizada se existir
          if (configs['descricoes'] != null && configs['descricoes'][secao['id']] != null) {
            secaoModificada['descricao'] = configs['descricoes'][secao['id']];
          }

          // Aplica visibilidade
          if (configs['visibilidade'] != null &&
              configs['visibilidade'][secao['id']] == false) {
            secaoModificada['oculto'] = true;
          }

          return secaoModificada;
        }).toList();

        // Ordena as seções baseado na ordem personalizada
        if (configs['ordem'] != null && configs['ordem'].isNotEmpty) {
          _secoes.sort((a, b) {
            final indexA = configs['ordem'].indexOf(a['id']);
            final indexB = configs['ordem'].indexOf(b['id']);

            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });
        } else {
          // Ordena pela ordem padrão
          _secoes.sort((a, b) => (a['ordem_padrao'] ?? 999).compareTo(b['ordem_padrao'] ?? 999));
        }

        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar configurações: $e';
        _carregando = false;
        // Fallback: usa a lista base
        _secoes = List.from(_secoesBase);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Site'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // BOTÃO DE CONFIGURAÇÕES (ENGRENAGEM)
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _mostrarDialogoConfiguracoes,
            tooltip: 'Configurações do Site',
          ),
          // Botão de recarregar
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarConfiguracoes,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.red.shade50,
              Colors.white,
            ],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  // DIALOGO DE CONFIGURAÇÕES
  void _mostrarDialogoConfiguracoes() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.red),
            SizedBox(width: 8),
            Text('Configurações do Site'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Opção 1: Ordem do Menu
            _buildDialogOption(
              icone: Icons.swap_vert,
              cor: Colors.teal,
              titulo: 'Ordem do Menu',
              descricao: 'Reordenar botões do site',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConfigurarMenuScreen(
                      secoes: _secoesBase,
                      onSalvo: _carregarConfiguracoes,
                    ),
                  ),
                );
              },
            ),

            const Divider(height: 16),

            // Opção 2: Títulos e Textos
            _buildDialogOption(
              icone: Icons.edit,
              cor: Colors.brown,
              titulo: 'Títulos e Textos',
              descricao: 'Personalizar nomes e descrições',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditarTextosScreen(
                      secoes: _secoesBase,
                      onSalvo: _carregarConfiguracoes,
                    ),
                  ),
                );
              },
            ),

            const Divider(height: 16),

            // Opção 3: Senha do App
            _buildDialogOption(
              icone: Icons.lock,
              cor: Colors.red.shade900,
              titulo: 'Senha do App',
              descricao: 'Alterar senha de acesso (atual: uai2026app)',
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoAlterarSenha();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  // Widget auxiliar para as opções do diálogo
  Widget _buildDialogOption({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icone,
                color: cor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade700),
              const SizedBox(height: 16),
              Text(
                'Ops! Algo deu errado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade900),
              ),
              const SizedBox(height: 8),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _carregarConfiguracoes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
                child: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CABEÇALHO INFORMATIVO
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Gerencie todo o conteúdo do site da UAI Capoeira',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // LEGENDA
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Seções visíveis no site',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Seções ocultas',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),

        // LISTA DE SEÇÕES
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _secoes.length,
            itemBuilder: (context, index) {
              final secao = _secoes[index];

              // Se for uma seção oculta
              if (secao['oculto'] == true) {
                return _buildHiddenSectionCard(secao);
              }

              // Seção normal (visível)
              return _buildSecaoCard(secao);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoCard(Map<String, dynamic> secao) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _abrirSecao(secao),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone com fundo colorido
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: secao['cor'].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  secao['icone'],
                  color: secao['cor'],
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),

              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao['titulo'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      secao['descricao'],
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (secao['colecao'] != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Coleção: ${secao['colecao']}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Seta
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: secao['cor'].withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward,
                  color: secao['cor'],
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenSectionCard(Map<String, dynamic> secao) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Ícone cinza
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                secao['icone'],
                color: Colors.grey.shade600,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),

            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        secao['titulo'],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'OCULTO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Clique para gerenciar visibilidade',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            // Botão de olho
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.visibility_off, color: Colors.grey.shade700, size: 20),
                onPressed: () => _mostrarDialogoVisibilidade(secao),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirSecao(Map<String, dynamic> secao) {
    switch (secao['tela']) {
      case 'regimento':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RegimentoInternoScreen(),
          ),
        ).then(_handleResult);
        break;

      case 'biografia':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const BiografiaScreen(),
          ),
        ).then(_handleResult);
        break;

      case 'graduacoes':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GraduacoesSiteScreen(),
          ),
        ).then(_handleResult);
        break;

      case 'inscricao':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ConfigurarInscricoesScreen(),
          ),
        ).then(_handleResult);
        break;

      case 'campeonato':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ConfigurarCampeonatoScreen(),
          ),
        ).then(_handleResult);
        break;

      case 'timeline':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GerenciarTimelineScreen(),
          ),
        ).then(_handleResult);
        break;

      default:
        _mostrarEmBreve(secao);
    }
  }

  void _mostrarDialogoVisibilidade(Map<String, dynamic> secao) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(secao['icone'], color: secao['cor']),
            const SizedBox(width: 8),
            Expanded(child: Text(secao['titulo'])),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Esta seção está atualmente oculta no site.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Deseja torná-la visível novamente?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _configService.alterarVisibilidade(secao['id'], true);
              _carregarConfiguracoes();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${secao['titulo']} agora está visível'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('TORNAR VISÍVEL'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAlterarSenha() {
    final TextEditingController senhaController = TextEditingController();
    final TextEditingController confirmarController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Column(
          children: [
            Icon(Icons.lock, size: 40, color: Colors.red),
            SizedBox(height: 8),
            Text('Alterar Senha do App'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Senha atual: uai2026app',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: senhaController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Nova senha',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmarController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirmar nova senha',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.password),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              final novaSenha = senhaController.text.trim();
              final confirmar = confirmarController.text.trim();

              if (novaSenha.isEmpty) {
                _mostrarErro('A senha não pode estar vazia');
                return;
              }

              if (novaSenha.length < 6) {
                _mostrarErro('A senha deve ter pelo menos 6 caracteres');
                return;
              }

              if (novaSenha != confirmar) {
                _mostrarErro('As senhas não coincidem');
                return;
              }

              Navigator.pop(context);

              await _configService.alterarSenhaApp(novaSenha);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✅ Senha alterada com sucesso!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $mensagem'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleResult(dynamic result) {
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Configurações salvas com sucesso!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      _carregarConfiguracoes();
    }
  }

  void _mostrarEmBreve(Map<String, dynamic> secao) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(secao['icone'], color: secao['cor']),
            const SizedBox(width: 8),
            Text(secao['titulo']),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: secao['cor'].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hourglass_empty,
                size: 50,
                color: secao['cor'],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Esta tela está em desenvolvimento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Em breve você poderá editar ${secao['titulo'].toLowerCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }
}