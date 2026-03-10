import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'regimento_interno_screen.dart';
import 'biografia_screen.dart';
import 'graduacoes_site_screen.dart';
import 'configurar_inscricoes_screen.dart';
import 'gerenciar_timeline_screen.dart';
import 'configurar_campeonato_screen.dart'; // 🔥 NOVO IMPORT!

class GerenciarSiteScreen extends StatefulWidget {
  const GerenciarSiteScreen({super.key});

  @override
  State<GerenciarSiteScreen> createState() => _GerenciarSiteScreenState();
}

class _GerenciarSiteScreenState extends State<GerenciarSiteScreen> {
  final List<Map<String, dynamic>> _secoes = [
    {
      'titulo': 'REGIMENTO INTERNO',
      'icone': Icons.description,
      'cor': Colors.blue,
      'colecao': 'site_regimento',
      'descricao': 'Editar regras e normas do grupo',
      'tela': 'regimento',
    },
    {
      'titulo': 'BIOGRAFIA',
      'icone': Icons.auto_stories,
      'cor': Colors.green,
      'colecao': 'site_biografia',
      'descricao': 'Editar história do grupo',
      'tela': 'biografia',
    },
    {
      'titulo': 'GRADUAÇÕES',
      'icone': Icons.emoji_events,
      'cor': Colors.orange,
      'colecao': 'site_graduacoes',
      'descricao': 'Editar sistema de cordas',
      'tela': 'graduacoes',
    },
    {
      'titulo': 'INSCRIÇÃO',
      'icone': Icons.app_registration,
      'cor': Colors.red,
      'colecao': 'site_inscricao',
      'descricao': 'Configurar inscrições para aula experimental',
      'tela': 'inscricao',
    },
    // 🔥 NOVO BOTÃO CAMPEONATO
    {
      'titulo': 'CAMPEONATO',
      'icone': Icons.emoji_events, // Troquei para um ícone mais adequado
      'cor': Colors.amber.shade800, // Cor dourada para destacar
      'colecao': 'campeonato_inscricoes',
      'descricao': 'Configurar 1° Campeonato UAI Capoeira',
      'tela': 'campeonato',
    },
    {
      'titulo': 'LINHA DO TEMPO',
      'icone': Icons.timeline,
      'cor': Colors.purple,
      'colecao': 'timeline_publicacoes',
      'descricao': 'Gerenciar publicações do site',
      'tela': 'timeline',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Site'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
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
        child: Column(
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
                  return _buildSecaoCard(secao);
                },
              ),
            ),
          ],
        ),
      ),
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

  void _abrirSecao(Map<String, dynamic> secao) {
    switch (secao['tela']) {
      case 'regimento':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RegimentoInternoScreen(),
          ),
        ).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Regimento salvo com sucesso!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
        break;

      case 'biografia':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const BiografiaScreen(),
          ),
        ).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Biografia salva com sucesso!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
        break;

      case 'graduacoes':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GraduacoesSiteScreen(),
          ),
        ).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Graduações salvas com sucesso!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
        break;

      case 'inscricao':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ConfigurarInscricoesScreen(),
          ),
        ).then((_) {
          if (mounted) {
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
          }
        });
        break;

    // 🔥 NOVO CASO PARA CAMPEONATO
      case 'campeonato':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ConfigurarCampeonatoScreen(),
          ),
        ).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Configurações do campeonato salvas!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
        break;

      case 'timeline':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GerenciarTimelineScreen(),
          ),
        ).then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Publicações atualizadas!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
        break;

      default:
        _mostrarEmBreve(secao);
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