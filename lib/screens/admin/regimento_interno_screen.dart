import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/logo_service.dart'; // 🔥 IMPORT DO LOGO SERVICE

class RegimentoInternoScreen extends StatefulWidget {
  const RegimentoInternoScreen({super.key});

  @override
  State<RegimentoInternoScreen> createState() => _RegimentoInternoScreenState();
}

class _RegimentoInternoScreenState extends State<RegimentoInternoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LogoService _logoService = LogoService(); // 🔥 LOGO SERVICE

  // Lista de seções dinâmicas
  List<Map<String, dynamic>> _secoes = [];

  bool _carregando = true;
  bool _salvando = false;

  // Lista de ícones disponíveis
  final List<Map<String, dynamic>> _iconesDisponiveis = [
    {'nome': 'Gavel', 'icon': Icons.gavel, 'iconName': 'gavel', 'cor': Colors.blue},
    {'nome': 'Person Add', 'icon': Icons.person_add, 'iconName': 'person_add', 'cor': Colors.green},
    {'nome': 'School', 'icon': Icons.school, 'iconName': 'school', 'cor': Colors.orange},
    {'nome': 'Workspace Premium', 'icon': Icons.workspace_premium, 'iconName': 'workspace_premium', 'cor': Colors.purple},
    {'nome': 'Security', 'icon': Icons.security, 'iconName': 'security', 'cor': Colors.red},
    {'nome': 'Group', 'icon': Icons.group, 'iconName': 'group', 'cor': Colors.teal},
    {'nome': 'Star', 'icon': Icons.star, 'iconName': 'star', 'cor': Colors.amber},
    {'nome': 'Emoji Events', 'icon': Icons.emoji_events, 'iconName': 'emoji_events', 'cor': Colors.deepOrange},
    {'nome': 'Menu Book', 'icon': Icons.menu_book, 'iconName': 'menu_book', 'cor': Colors.brown},
    {'nome': 'Rule', 'icon': Icons.rule, 'iconName': 'rule', 'cor': Colors.indigo},
  ];

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'gavel': return Icons.gavel;
      case 'person_add': return Icons.person_add;
      case 'school': return Icons.school;
      case 'workspace_premium': return Icons.workspace_premium;
      case 'security': return Icons.security;
      case 'group': return Icons.group;
      case 'star': return Icons.star;
      case 'emoji_events': return Icons.emoji_events;
      case 'menu_book': return Icons.menu_book;
      case 'rule': return Icons.rule;
      default: return Icons.description;
    }
  }

  @override
  void initState() {
    super.initState();
    _carregarRegimento();
  }

  Future<void> _carregarRegimento() async {
    try {
      final doc = await _firestore.collection('site_conteudo').doc('regimento').get();

      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('secoes') && data['secoes'] is List) {
          _secoes = List<Map<String, dynamic>>.from(data['secoes']);
        } else {
          _secoes = _getSecoesPadrao();
        }
      } else {
        _secoes = _getSecoesPadrao();
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar: $e');
      _secoes = _getSecoesPadrao();
    } finally {
      setState(() => _carregando = false);
    }
  }

  List<Map<String, dynamic>> _getSecoesPadrao() {
    return [
      {
        'id': 'regras_gerais',
        'titulo': '⚖️ REGRAS GERAIS',
        'icone': 'gavel',
        'cor': Colors.blue.value,
        'conteudo': _getRegrasGeraisPadrao(),
      },
      {
        'id': 'novos_alunos',
        'titulo': '🆕 NOVOS ALUNOS',
        'icone': 'person_add',
        'cor': Colors.green.value,
        'conteudo': _getNovosAlunosPadrao(),
      },
      {
        'id': 'alunos_graduados',
        'titulo': '🎓 ALUNOS GRADUADOS',
        'icone': 'school',
        'cor': Colors.orange.value,
        'conteudo': _getAlunosGraduadosPadrao(),
      },
      {
        'id': 'formados',
        'titulo': '⭐ FORMADOS',
        'icone': 'workspace_premium',
        'cor': Colors.purple.value,
        'conteudo': _getFormadosPadrao(),
      },
    ];
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);

    try {
      await _firestore.collection('site_conteudo').doc('regimento').set({
        'secoes': _secoes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Regimento salvo com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ========== CONTEÚDOS PADRÃO ==========
  String _getRegrasGeraisPadrao() {
    return '''🚫 Proibido uso do uniforme em locais inadequados (bares, festas, baladas).
❌ Não é permitido utilizar uniformes de outros grupos.
📢 Participação em eventos externos deve ser comunicada antecipadamente.
⏰ Cumprimento rigoroso dos horários de treinos, rodas e apresentações.
👕 Em dias de roda ou apresentações é obrigatório o uniforme completo (calça branca, camisa e graduação).
🧼 Manter a higiene pessoal: unhas cortadas, roupas limpas e bom cuidado com o uniforme.
🙏 Respeitar mestres, professores, colegas e visitantes, independente de idade ou graduação.
🤝 Ao visitar outras academias ou grupos de capoeira, o aluno deve:
   • Avisar com antecedência os responsáveis do grupo
   • Utilizar sempre a camisa oficial do grupo UAI Capoeira
   • Não participar sem identificação do grupo''';
  }

  String _getNovosAlunosPadrao() {
    return '''⏳ Prazo de 2 meses para adquirir o uniforme completo.
👀 Durante esse período, o aluno será avaliado pelos professores.
🎖️ Primeira graduação possível após 6 meses de treino regular.
📅 Indicação para início das atividades: preferencialmente em uma segunda-feira.
📲 Cadastro no sistema + ingresso em grupo de WhatsApp para comunicações.
⚠️ Caso falte por mais de 3 semanas sem justificativa, será considerado desligado.
🙌 Todo aluno deve manter postura respeitosa e colaborativa dentro e fora da academia.''';
  }

  String _getAlunosGraduadosPadrao() {
    return '''🙏 Respeito, disciplina e comprometimento são indispensáveis.
👕 Uso do uniforme correto nos treinos e apresentações é obrigatório.
⏳ Graduação só pode ser trocada após no mínimo 1 ano, conforme desempenho.
🎭 Em eventos, utilizar somente o uniforme oficial (não camisas promocionais).
⚠️ Faltas por mais de 1 mês sem aviso resultam em desligamento automático.
💪 O graduado deve dar exemplo de postura, ajudando os iniciantes e fortalecendo a roda.''';
  }

  String _getFormadosPadrao() {
    return '''São considerados formados os monitores, instrutores, professores, contra-mestres e mestres.

📚 Devem estar sempre ativos nos treinos e rodas, transmitindo conhecimento.
🪘 Devem incentivar a prática dos instrumentos, cantos e fundamentos da capoeira.
🌍 Representam o grupo dentro e fora da cidade, mantendo o nome da Associação com honra e responsabilidade.

📖 ESTÁGIOS DE FORMAÇÃO:

👨‍🎓 MONITOR:
• 🔞 Ter no mínimo 18 anos
• 🎓 Ensino médio completo
• 🔵 Pelo menos 1 ano de graduação na 6ª corda (azul)
• 📖 Capacidade para ministrar aulas, com ou sem auxílio
• 🥁 Conhecimento básico dos instrumentos e toques da capoeira
• ⚔️ Conhecimento dos fundamentos e da história do grupo
• 🪪 Ser associado ativo

👨‍🏫 INSTRUTOR:
• ✅ Requisitos de monitor atendidos
• ⏳ No mínimo 4 anos como monitor
• 📖 Capacidade de ministrar e planejar aulas de forma independente
• 🔍 Habilidade de identificar e corrigir dificuldades dos alunos
• 🚀 Busca contínua por conhecimento e aprimoramento

👨‍🎓 PROFESSOR:
• ✅ Todos os requisitos anteriores
• 📜 Diploma emitido pelo grupo, com reconhecimento dos mestres e formados
• 🌍 Responsabilidade em representar o grupo oficialmente em eventos nacionais e internacionais
• 🎓 Reconhecimento como profissional da área da Capoeira, apto a ministrar aulas em academias, escolas, projetos sociais e demais espaços culturais''';
  }

  void _adicionarSecao() {
    showDialog(
      context: context,
      builder: (context) => _DialogNovaSecao(
        iconesDisponiveis: _iconesDisponiveis,
        onSalvar: (titulo, iconName, cor) {
          setState(() {
            _secoes.add({
              'id': 'secao_${DateTime.now().millisecondsSinceEpoch}',
              'titulo': titulo,
              'icone': iconName,
              'cor': cor.value,
              'conteudo': 'Digite o conteúdo aqui...',
            });
          });
        },
      ),
    );
  }

  void _editarSecao(int index) {
    final secao = _secoes[index];
    showDialog(
      context: context,
      builder: (context) => _DialogEditarSecao(
        secao: secao,
        iconesDisponiveis: _iconesDisponiveis,
        onSalvar: (titulo, iconName, cor) {
          setState(() {
            _secoes[index]['titulo'] = titulo;
            _secoes[index]['icone'] = iconName;
            _secoes[index]['cor'] = cor.value;
          });
        },
      ),
    );
  }

  void _removerSecao(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover seção'),
        content: const Text('Tem certeza que deseja remover esta seção?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _secoes.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('📜 Regimento Interno'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _adicionarSecao,
          ),
          TextButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _salvando ? 'SALVANDO...' : 'SALVAR',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // 🔥 LOGO ACIMA DAS SEÇÕES
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _logoService.buildLogo(height: 100), // LOGO AQUI!
              ),
            ),
          ),

          // SEÇÕES
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final secao = _secoes[index];
                  return _buildSecao(
                    index: index,
                    titulo: secao['titulo'],
                    icone: _getIconFromName(secao['icone']),
                    cor: Color(secao['cor']),
                    controller: TextEditingController(text: secao['conteudo']),
                    onChanged: (value) {
                      _secoes[index]['conteudo'] = value;
                    },
                  );
                },
                childCount: _secoes.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecao({
    required int index,
    required String titulo,
    required IconData icone,
    required Color cor,
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icone, color: cor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editarSecao(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: () => _removerSecao(index),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: 'Digite o conteúdo aqui...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ========== DIALOG PARA NOVA SEÇÃO (SIMPLIFICADO) ==========
class _DialogNovaSecao extends StatefulWidget {
  final List<Map<String, dynamic>> iconesDisponiveis;
  final Function(String titulo, String iconName, Color cor) onSalvar;

  const _DialogNovaSecao({
    required this.iconesDisponiveis,
    required this.onSalvar,
  });

  @override
  State<_DialogNovaSecao> createState() => _DialogNovaSecaoState();
}

class _DialogNovaSecaoState extends State<_DialogNovaSecao> {
  final TextEditingController _tituloController = TextEditingController();
  int _iconeSelecionado = 0;
  Color _corSelecionada = Colors.blue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova Seção'),
      content: Container(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _tituloController,
                decoration: const InputDecoration(
                  labelText: 'Título da seção',
                  hintText: 'Ex: ⚖️ REGRAS GERAIS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Escolha o ícone:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // Wrap em vez de GridView
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.iconesDisponiveis.asMap().entries.map((entry) {
                  final index = entry.key;
                  final icone = entry.value;
                  final isSelected = _iconeSelecionado == index;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _iconeSelecionado = index;
                        _corSelecionada = icone['cor'];
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isSelected ? icone['cor'].withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? icone['cor'] : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icone['icon'],
                        color: icone['cor'],
                        size: 30,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_tituloController.text.isNotEmpty) {
              final icone = widget.iconesDisponiveis[_iconeSelecionado];
              widget.onSalvar(
                _tituloController.text,
                icone['iconName'],
                _corSelecionada,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('ADICIONAR'),
        ),
      ],
    );
  }
}

// ========== DIALOG PARA EDITAR SEÇÃO (SIMPLIFICADO) ==========
class _DialogEditarSecao extends StatefulWidget {
  final Map<String, dynamic> secao;
  final List<Map<String, dynamic>> iconesDisponiveis;
  final Function(String titulo, String iconName, Color cor) onSalvar;

  const _DialogEditarSecao({
    required this.secao,
    required this.iconesDisponiveis,
    required this.onSalvar,
  });

  @override
  State<_DialogEditarSecao> createState() => _DialogEditarSecaoState();
}

class _DialogEditarSecaoState extends State<_DialogEditarSecao> {
  late TextEditingController _tituloController;
  late int _iconeSelecionado;
  late Color _corSelecionada;

  @override
  void initState() {
    super.initState();
    _tituloController = TextEditingController(text: widget.secao['titulo']);

    _iconeSelecionado = widget.iconesDisponiveis.indexWhere(
            (icone) => icone['iconName'] == widget.secao['icone']
    );
    if (_iconeSelecionado == -1) _iconeSelecionado = 0;

    _corSelecionada = Color(widget.secao['cor']);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Seção'),
      content: Container(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _tituloController,
                decoration: const InputDecoration(
                  labelText: 'Título da seção',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Escolha o ícone:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // Wrap em vez de GridView
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.iconesDisponiveis.asMap().entries.map((entry) {
                  final index = entry.key;
                  final icone = entry.value;
                  final isSelected = _iconeSelecionado == index;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _iconeSelecionado = index;
                        _corSelecionada = icone['cor'];
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isSelected ? icone['cor'].withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? icone['cor'] : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        icone['icon'],
                        color: icone['cor'],
                        size: 30,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_tituloController.text.isNotEmpty) {
              final icone = widget.iconesDisponiveis[_iconeSelecionado];
              widget.onSalvar(
                _tituloController.text,
                icone['iconName'],
                _corSelecionada,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('SALVAR'),
        ),
      ],
    );
  }
}