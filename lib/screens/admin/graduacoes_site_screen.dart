import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:intl/intl.dart';
import '../../services/logo_service.dart';

class GraduacoesSiteScreen extends StatefulWidget {
  const GraduacoesSiteScreen({super.key});

  @override
  State<GraduacoesSiteScreen> createState() => _GraduacoesSiteScreenState();
}

class _GraduacoesSiteScreenState extends State<GraduacoesSiteScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LogoService _logoService = LogoService();

  String? _svgContent;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
          _carregando = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar SVG: $e');
      setState(() {
        _carregando = false;
      });
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return Colors.grey;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return Colors.grey;
        }
      }

      void changeColor(String id, Color color) {
        try {
          final element = document.rootElement.descendants
              .whereType<xml.XmlElement>()
              .firstWhere((e) => e.getAttribute('id') == id,
              orElse: () => xml.XmlElement(xml.XmlName('')));

          if (element.name.local.isNotEmpty) {
            final style = element.getAttribute('style') ?? '';
            final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
            String newStyle;
            if (style.contains('fill:')) {
              newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), 'fill:$hex');
            } else {
              newStyle = 'fill:$hex;$style';
            }
            element.setAttribute('style', newStyle);
          }
        } catch (e) {
          print('Erro ao mudar cor da parte $id: $e');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']));
      changeColor('cor2', colorFromHex(data['hex_cor2']));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']));

      return document.toXmlString();
    } catch (e) {
      print('Erro ao modificar SVG: $e');
      return _svgContent!;
    }
  }

  Future<List<Map<String, dynamic>>> _getAlunosPorGraduacao(String graduacaoId, String nomeGraduacao) async {
    try {
      // Busca todos os alunos com esta graduação
      final snapshot = await _firestore
          .collection('alunos')
          .where('graduacao_id', isEqualTo: graduacaoId)
          .orderBy('nome')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        Timestamp? dataGraduacao = data['data_graduacao_atual'] as Timestamp?;

        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Nome não informado',
          'data_graduacao': dataGraduacao?.toDate(),
          'foto': data['foto_perfil_aluno'] as String?,
        };
      }).toList();
    } catch (e) {
      print('Erro ao buscar alunos: $e');
      return [];
    }
  }

  void _mostrarAlunosDialog(BuildContext context, String nomeGraduacao, List<Map<String, dynamic>> alunos) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Column(
            children: [
              // CABEÇALHO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$nomeGraduacao (${alunos.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // LISTA DE ALUNOS (SIMPLIFICADA)
              Expanded(
                child: alunos.isEmpty
                    ? const Center(
                  child: Text('Nenhum aluno com esta graduação'),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: alunos.length,
                  itemBuilder: (context, index) {
                    final aluno = alunos[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.red.shade100,
                          backgroundImage: aluno['foto'] != null && aluno['foto'].toString().isNotEmpty
                              ? NetworkImage(aluno['foto'].toString())
                              : null,
                          child: aluno['foto'] == null || aluno['foto'].toString().isEmpty
                              ? Text(
                            aluno['nome'].isNotEmpty ? aluno['nome'][0] : '?',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )
                              : null,
                        ),
                        title: Text(aluno['nome']),
                        subtitle: aluno['data_graduacao'] != null
                            ? Text(
                          'Graduado em: ${DateFormat('dd/MM/yyyy').format(aluno['data_graduacao'])}',
                          style: const TextStyle(fontSize: 12),
                        )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
        title: const Text('🥋 Catálogo de Graduações'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // LOGO
          Container(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _logoService.buildLogo(height: 80),
            ),
          ),

          // TÍTULO
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Sistema de Cordas e Graduações',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // GRADUAÇÕES EM GRADE
          Expanded(
            child: _svgContent == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('graduacoes')
                  .orderBy('nivel_graduacao')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma graduação encontrada'),
                  );
                }

                final graduacoes = snapshot.data!.docs;

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: graduacoes.length,
                  itemBuilder: (context, index) {
                    final doc = graduacoes[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final modifiedSvg = _getModifiedSvg(data);

                    return GestureDetector(
                      onTap: () async {
                        final alunos = await _getAlunosPorGraduacao(
                            doc.id,
                            data['nome_graduacao'] ?? 'Graduação'
                        );
                        if (context.mounted) {
                          _mostrarAlunosDialog(
                            context,
                            data['nome_graduacao'] ?? 'Graduação',
                            alunos,
                          );
                        }
                      },
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // SVG
                            Expanded(
                              flex: 3,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                color: Colors.grey.shade50,
                                child: SvgPicture.string(
                                  modifiedSvg,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),

                            // INFORMAÇÕES
                            Expanded(
                              flex: 2,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      data['nome_graduacao'] ?? 'Sem nome',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        data['tipo_publico'] ?? 'Geral',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}