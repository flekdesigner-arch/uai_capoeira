import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegimentoScreen extends StatefulWidget {
  const RegimentoScreen({super.key});

  @override
  State<RegimentoScreen> createState() => _RegimentoScreenState();
}

class _RegimentoScreenState extends State<RegimentoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _secoesRegimento = [];
  bool _carregando = true;

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
          final List<dynamic> secoesRaw = data['secoes'] as List;

          List<Map<String, dynamic>> secoesConvertidas = [];
          for (var item in secoesRaw) {
            if (item is Map<String, dynamic>) {
              secoesConvertidas.add(item);
            }
          }

          if (mounted) {
            setState(() {
              _secoesRegimento = secoesConvertidas;
              _carregando = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _secoesRegimento = _getSecoesRegimentoPadrao();
              _carregando = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _secoesRegimento = _getSecoesRegimentoPadrao();
            _carregando = false;
          });
        }
      }
    } catch (e) {
      print('❌ Erro ao carregar regimento: $e');
      if (mounted) {
        setState(() {
          _secoesRegimento = _getSecoesRegimentoPadrao();
          _carregando = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getSecoesRegimentoPadrao() {
    return [
      {
        'titulo': '⚖️ REGRAS GERAIS',
        'icone': Icons.gavel,
        'cor': Colors.blue,
        'conteudo': '🚫 Proibido uso do uniforme em locais inadequados (bares, festas, baladas).\n'
            '❌ Não é permitido utilizar uniformes de outros grupos.\n'
            '📢 Participação em eventos externos deve ser comunicada antecipadamente.\n'
            '⏰ Cumprimento rigoroso dos horários de treinos, rodas e apresentações.\n'
            '👕 Em dias de roda ou apresentações é obrigatório o uniforme completo (calça branca, camisa e graduação).\n'
            '🧼 Manter a higiene pessoal: unhas cortadas, roupas limpas e bom cuidado com o uniforme.\n'
            '🙏 Respeitar mestres, professores, colegas e visitantes, independente de idade ou graduação.\n'
            '🤝 Ao visitar outras academias ou grupos de capoeira, o aluno deve:\n'
            '   • Avisar com antecedência os responsáveis do grupo\n'
            '   • Utilizar sempre a camisa oficial do grupo UAI Capoeira\n'
            '   • Não participar sem identificação do grupo',
      },
      {
        'titulo': '🆕 NOVOS ALUNOS',
        'icone': Icons.person_add,
        'cor': Colors.green,
        'conteudo': '⏳ Prazo de 2 meses para adquirir o uniforme completo.\n'
            '👀 Durante esse período, o aluno será avaliado pelos professores.\n'
            '🎖️ Primeira graduação possível após 6 meses de treino regular.\n'
            '📅 Indicação para início das atividades: preferencialmente em uma segunda-feira.\n'
            '📲 Cadastro no sistema + ingresso em grupo de WhatsApp para comunicações.\n'
            '⚠️ Caso falte por mais de 3 semanas sem justificativa, será considerado desligado.\n'
            '🙌 Todo aluno deve manter postura respeitosa e colaborativa dentro e fora da academia.',
      },
      {
        'titulo': '🎓 ALUNOS GRADUADOS',
        'icone': Icons.school,
        'cor': Colors.orange,
        'conteudo': '🙏 Respeito, disciplina e comprometimento são indispensáveis.\n'
            '👕 Uso do uniforme correto nos treinos e apresentações é obrigatório.\n'
            '⏳ Graduação só pode ser trocada após no mínimo 1 ano, conforme desempenho.\n'
            '🎭 Em eventos, utilizar somente o uniforme oficial (não camisas promocionais).\n'
            '⚠️ Faltas por mais de 1 mês sem aviso resultam em desligamento automático.\n'
            '💪 O graduado deve dar exemplo de postura, ajudando os iniciantes e fortalecendo a roda.',
      },
      {
        'titulo': '⭐ FORMADOS',
        'icone': Icons.workspace_premium,
        'cor': Colors.purple,
        'conteudo': 'São considerados formados os monitores, instrutores, professores, contra-mestres e mestres.\n\n'
            '📚 Devem estar sempre ativos nos treinos e rodas, transmitindo conhecimento.\n'
            '🪘 Devem incentivar a prática dos instrumentos, cantos e fundamentos da capoeira.\n'
            '🌍 Representam o grupo dentro e fora da cidade, mantendo o nome da Associação com honra e responsabilidade.\n\n'
            '📖 ESTÁGIOS DE FORMAÇÃO:\n\n'
            '👨‍🎓 MONITOR:\n'
            '• 🔞 Ter no mínimo 18 anos\n'
            '• 🎓 Ensino médio completo\n'
            '• 🔵 Pelo menos 1 ano de graduação na 6ª corda (azul)\n'
            '• 📖 Capacidade para ministrar aulas, com ou sem auxílio\n'
            '• 🥁 Conhecimento básico dos instrumentos e toques da capoeira\n'
            '• ⚔️ Conhecimento dos fundamentos e da história do grupo\n'
            '• 🪪 Ser associado ativo\n\n'
            '👨‍🏫 INSTRUTOR:\n'
            '• ✅ Requisitos de monitor atendidos\n'
            '• ⏳ No mínimo 4 anos como monitor\n'
            '• 📖 Capacidade de ministrar e planejar aulas de forma independente\n'
            '• 🔍 Habilidade de identificar e corrigir dificuldades dos alunos\n'
            '• 🚀 Busca contínua por conhecimento e aprimoramento\n\n'
            '👨‍🎓 PROFESSOR:\n'
            '• ✅ Todos os requisitos anteriores\n'
            '• 📜 Diploma emitido pelo grupo, com reconhecimento dos mestres e formados\n'
            '• 🌍 Responsabilidade em representar o grupo oficialmente em eventos nacionais e internacionais\n'
            '• 🎓 Reconhecimento como profissional da área da Capoeira',
      },
    ];
  }

  IconData _getIconFromName(String iconName) {
    switch (iconName) {
      case 'gavel': return Icons.gavel;
      case 'person_add': return Icons.person_add;
      case 'school': return Icons.school;
      case 'workspace_premium': return Icons.workspace_premium;
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
          title: const Text('📜 REGIMENTO INTERNO'),
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
    if (_secoesRegimento.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 80, color: Colors.grey.shade300),
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
                final secao = _secoesRegimento[index];
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
              childCount: _secoesRegimento.length,
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