import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BiografiaScreen extends StatefulWidget {
  const BiografiaScreen({super.key});

  @override
  State<BiografiaScreen> createState() => _BiografiaScreenState();
}

class _BiografiaScreenState extends State<BiografiaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _secoesBiografia = [];
  bool _carregando = true;

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
          final List<dynamic> secoesRaw = data['secoes'] as List;

          List<Map<String, dynamic>> secoesConvertidas = [];
          for (var item in secoesRaw) {
            if (item is Map<String, dynamic>) {
              secoesConvertidas.add(item);
            }
          }

          if (mounted) {
            setState(() {
              _secoesBiografia = secoesConvertidas;
              _carregando = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _secoesBiografia = _getSecoesBiografiaPadrao();
              _carregando = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _secoesBiografia = _getSecoesBiografiaPadrao();
            _carregando = false;
          });
        }
      }
    } catch (e) {
      print('❌ Erro ao carregar biografia: $e');
      if (mounted) {
        setState(() {
          _secoesBiografia = _getSecoesBiografiaPadrao();
          _carregando = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getSecoesBiografiaPadrao() {
    return [
      {
        'titulo': '📖 INTRODUÇÃO',
        'icone': Icons.menu_book,
        'cor': const Color(0xFF800020),
        'conteudo': 'Em 1º de setembro de 2015, na cidade de Engenheiro Navarro, MG, um grupo de visionários se uniu para fundar o UAI Capoeira.\n\nSob a liderança de seus fundadores - Taika Altair (Mestre Grilo), Paulo Afonso (Contra Mestre Zumbi), Felipe Almeida (Professor Barrãozinho) e Admilson Pereira (Professor Didi) - o grupo nasceu com o propósito de disseminar não apenas a prática da capoeira, mas também os valores de união, amizade e inteligência.',
      },
      {
        'titulo': '🌳 RAÍZES DA FUNDAÇÃO',
        'icone': Icons.forest,
        'cor': const Color(0xFF0055aa),
        'conteudo': 'Desde o momento da fundação, o UAI Capoeira foi enraizado na paixão pela capoeira e no compromisso com a comunidade. Os fundadores buscavam não apenas ensinar uma arte marcial, mas também compartilhar a riqueza cultural e histórica que a capoeira representa, sempre com foco na união e na força coletiva.',
      },
      {
        'titulo': '📈 EXPANSÃO E CONSOLIDAÇÃO',
        'icone': Icons.trending_up,
        'cor': const Color(0xFFcc6600),
        'conteudo': 'O sucesso do UAI Capoeira em Engenheiro Navarro rapidamente se espalhou para além de suas fronteiras. Em junho de 2017, uma nova unidade foi estabelecida em Bocaiuva, MG, liderada por João Lucas (Professor Tico-Tico), Joaquim Filho (Professor Jacu), Warley (Professor Scorpion) e João Paulo (Monitor Bode). Essa expansão não apenas fortaleceu o grupo, mas também demonstrou o poder da união e da cooperação.',
      },
      {
        'titulo': '🎯 MISSÃO E VALORES',
        'icone': Icons.flag,
        'cor': const Color(0xFF228844),
        'conteudo': 'Para o UAI Capoeira, a capoeira é mais do que apenas uma forma de arte marcial - é uma ferramenta para o desenvolvimento pessoal e comunitário. Os valores de união, amizade e inteligência são cultivados em cada aula e evento, preparando os membros não apenas para os desafios dentro do jogo da capoeira, mas também para os desafios da vida cotidiana.',
      },
      {
        'titulo': '⭐ LEGADO E ATUALIDADE',
        'icone': Icons.history,
        'cor': const Color(0xFFaa0066),
        'conteudo': 'Atualmente, o UAI Capoeira continua a prosperar em Engenheiro Navarro e Bocaiuva, mantendo viva a tradição da capoeira e os valores que a acompanham. Com uma comunidade unida e dedicada, o grupo continua a inspirar aqueles ao seu redor, deixando um legado de união, amizade e inteligência para as gerações futuras.',
      },
      {
        'titulo': '✨ CONCLUSÃO',
        'icone': Icons.done_all,
        'cor': const Color(0xFF999900),
        'conteudo': 'A história do UAI Capoeira é uma prova viva da força da união, da importância da amizade e do poder da inteligência coletiva. Enquanto o grupo continua sua jornada, seu compromisso com esses valores fundamentais permanece inabalável, inspirando todos os que têm a sorte de cruzar seu caminho.',
      },
    ];
  }

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'menu_book': return Icons.menu_book;
      case 'forest': return Icons.forest;
      case 'expand': return Icons.trending_up;
      case 'flag': return Icons.flag;
      case 'history': return Icons.history;
      case 'done_all': return Icons.done_all;
      default: return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📖 BIOGRAFIA'),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
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
          child: _carregando
              ? const Center(child: CircularProgressIndicator(color: Colors.red))
              : _buildContent(isMobile),
        ),
      ),
    );
  }

  Widget _buildContent(bool isMobile) {
    if (_secoesBiografia.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma seção encontrada',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final secao = _secoesBiografia[index];
                return _buildSecaoLeitura(
                  titulo: secao['titulo'],
                  icone: secao['icone'] is IconData
                      ? secao['icone']
                      : _getIconFromName(secao['icone']),
                  cor: secao['cor'] is Color
                      ? secao['cor']
                      : Color(secao['cor']),
                  conteudo: secao['conteudo'],
                  isMobile: isMobile,
                );
              },
              childCount: _secoesBiografia.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoLeitura({
    required String titulo,
    required IconData icone,
    required Color cor,
    required String conteudo,
    required bool isMobile,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 20),
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
                    child: Icon(icone, color: cor, size: isMobile ? 22 : 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: cor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                conteudo,
                style: TextStyle(
                  fontSize: isMobile ? 13 : 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}