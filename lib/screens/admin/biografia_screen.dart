import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/logo_service.dart';

class BiografiaScreen extends StatefulWidget {
  const BiografiaScreen({super.key});

  @override
  State<BiografiaScreen> createState() => _BiografiaScreenState();
}

class _BiografiaScreenState extends State<BiografiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LogoService _logoService = LogoService();

  // Lista de seções dinâmicas
  List<Map<String, dynamic>> _secoes = [];

  bool _carregando = true;
  bool _salvando = false;

  // Lista de ícones disponíveis (mesma do regimento)
  final List<Map<String, dynamic>> _iconesDisponiveis = [
    {'nome': 'Introdução', 'icon': Icons.menu_book, 'iconName': 'menu_book', 'cor': Color(0xFF800020)},
    {'nome': 'Raízes', 'icon': Icons.forest, 'iconName': 'forest', 'cor': Color(0xFF0055aa)},
    {'nome': 'Expansão', 'icon': Icons.expand, 'iconName': 'expand', 'cor': Color(0xFFcc6600)},
    {'nome': 'Missão', 'icon': Icons.flag, 'iconName': 'flag', 'cor': Color(0xFF228844)},
    {'nome': 'Legado', 'icon': Icons.history, 'iconName': 'history', 'cor': Color(0xFFaa0066)},
    {'nome': 'Conclusão', 'icon': Icons.done_all, 'iconName': 'done_all', 'cor': Color(0xFF999900)},
    {'nome': 'História', 'icon': Icons.auto_stories, 'iconName': 'auto_stories', 'cor': Colors.purple},
    {'nome': 'Fotos', 'icon': Icons.photo_library, 'iconName': 'photo_library', 'cor': Colors.teal},
    {'nome': 'Fundadores', 'icon': Icons.group, 'iconName': 'group', 'cor': Colors.orange},
    {'nome': 'Eventos', 'icon': Icons.event, 'iconName': 'event', 'cor': Colors.red},
  ];

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'menu_book': return Icons.menu_book;
      case 'forest': return Icons.forest;
      case 'expand': return Icons.expand;
      case 'flag': return Icons.flag;
      case 'history': return Icons.history;
      case 'done_all': return Icons.done_all;
      case 'auto_stories': return Icons.auto_stories;
      case 'photo_library': return Icons.photo_library;
      case 'group': return Icons.group;
      case 'event': return Icons.event;
      default: return Icons.description;
    }
  }

  @override
  void initState() {
    super.initState();
    _carregarBiografia();
  }

  Future<void> _carregarBiografia() async {
    try {
      final doc = await _firestore.collection('site_conteudo').doc('biografia').get();

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
        'id': 'introducao',
        'titulo': '📖 INTRODUÇÃO',
        'icone': 'menu_book',
        'cor': Color(0xFF800020).value,
        'conteudo': _getIntroducaoPadrao(),
      },
      {
        'id': 'raizes',
        'titulo': '🌳 RAÍZES DA FUNDAÇÃO',
        'icone': 'forest',
        'cor': Color(0xFF0055aa).value,
        'conteudo': _getRaizesPadrao(),
      },
      {
        'id': 'expansao',
        'titulo': '📈 EXPANSÃO E CONSOLIDAÇÃO',
        'icone': 'expand',
        'cor': Color(0xFFcc6600).value,
        'conteudo': _getExpansaoPadrao(),
      },
      {
        'id': 'missao',
        'titulo': '🎯 MISSÃO E VALORES',
        'icone': 'flag',
        'cor': Color(0xFF228844).value,
        'conteudo': _getMissaoPadrao(),
      },
      {
        'id': 'legado',
        'titulo': '⭐ LEGADO E ATUALIDADE',
        'icone': 'history',
        'cor': Color(0xFFaa0066).value,
        'conteudo': _getLegadoPadrao(),
      },
      {
        'id': 'conclusao',
        'titulo': '✨ CONCLUSÃO',
        'icone': 'done_all',
        'cor': Color(0xFF999900).value,
        'conteudo': _getConclusaoPadrao(),
      },
    ];
  }

  String _getIntroducaoPadrao() {
    return '''Em 1º de setembro de 2015, na cidade de Engenheiro Navarro, MG, um grupo de visionários se uniu para fundar o UAI Capoeira. 

Sob a liderança de seus fundadores - Taika Altair (Mestre Grilo), Paulo Afonso (Contra Mestre Zumbi), Felipe Almeida (Professor Barrãozinho) e Admilson Pereira (Professor Didi) - o grupo nasceu com o propósito de disseminar não apenas a prática da capoeira, mas também os valores de união, amizade e inteligência.''';
  }

  String _getRaizesPadrao() {
    return '''Desde o momento da fundação, o UAI Capoeira foi enraizado na paixão pela capoeira e no compromisso com a comunidade. Os fundadores buscavam não apenas ensinar uma arte marcial, mas também compartilhar a riqueza cultural e histórica que a capoeira representa, sempre com foco na união e na força coletiva.''';
  }

  String _getExpansaoPadrao() {
    return '''O sucesso do UAI Capoeira em Engenheiro Navarro rapidamente se espalhou para além de suas fronteiras. Em junho de 2017, uma nova unidade foi estabelecida em Bocaiuva, MG, liderada por João Lucas (Professor Tico-Tico), Joaquim Filho (Professor Jacu), Warley (Professor Scorpion) e João Paulo (Monitor Bode). Essa expansão não apenas fortaleceu o grupo, mas também demonstrou o poder da união e da cooperação.''';
  }

  String _getMissaoPadrao() {
    return '''Para o UAI Capoeira, a capoeira é mais do que apenas uma forma de arte marcial - é uma ferramenta para o desenvolvimento pessoal e comunitário. Os valores de união, amizade e inteligência são cultivados em cada aula e evento, preparando os membros não apenas para os desafios dentro do jogo da capoeira, mas também para os desafios da vida cotidiana.''';
  }

  String _getLegadoPadrao() {
    return '''Atualmente, o UAI Capoeira continua a prosperar em Engenheiro Navarro e Bocaiuva, mantendo viva a tradição da capoeira e os valores que a acompanham. Com uma comunidade unida e dedicada, o grupo continua a inspirar aqueles ao seu redor, deixando um legado de união, amizade e inteligência para as gerações futuras.''';
  }

  String _getConclusaoPadrao() {
    return '''A história do UAI Capoeira é uma prova viva da força da união, da importância da amizade e do poder da inteligência coletiva. Enquanto o grupo continua sua jornada, seu compromisso com esses valores fundamentais permanece inabalável, inspirando todos os que têm a sorte de cruzar seu caminho.''';
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);

    try {
      await _firestore.collection('site_conteudo').doc('biografia').set({
        'secoes': _secoes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Biografia salva com sucesso!'),
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
        title: const Text('📖 Biografia do Grupo'),
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
          // LOGO
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _logoService.buildLogo(height: 100),
              ),
            ),
          ),

          // TÍTULO PRINCIPAL
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'UAI CAPOEIRA: União, Amizade e Inteligência',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // SEÇÕES DINÂMICAS
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
                border: Border.all(color: cor.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: 'Digite o conteúdo aqui...',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 16, height: 1.5),
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

// ========== DIALOG PARA NOVA SEÇÃO ==========
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
  Color _corSelecionada = Color(0xFF800020);

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
                  hintText: 'Ex: 📖 INTRODUÇÃO',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Escolha o ícone:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

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

// ========== DIALOG PARA EDITAR SEÇÃO ==========
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