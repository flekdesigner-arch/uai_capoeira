import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class GraduacoesScreen extends StatefulWidget {
  const GraduacoesScreen({super.key});

  @override
  State<GraduacoesScreen> createState() => _GraduacoesScreenState();
}

class _GraduacoesScreenState extends State<GraduacoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _graduacoes = [];
  bool _carregando = true;
  String? _svgContent;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    await Future.wait([
      _carregarGraduacoes(),
      _loadSvgFromAssets(),
    ]);
  }

  Future<void> _carregarGraduacoes() async {
    try {
      final snapshot = await _firestore
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      List<Map<String, dynamic>> graduacoesConvertidas = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        graduacoesConvertidas.add(data);
      }

      if (mounted) {
        setState(() {
          _graduacoes = graduacoesConvertidas;
          _carregando = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar graduações: $e');
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  Future<void> _loadSvgFromAssets() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (mounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      print('Erro ao carregar SVG: $e');
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data, String svgContent) {
    try {
      final document = xml.XmlDocument.parse(svgContent);

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
              .firstWhere(
                (e) => e.getAttribute('id') == id,
            orElse: () => xml.XmlElement(xml.XmlName('')),
          );

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
      return svgContent;
    }
  }

  String _getPrimeiroESegundoNome(String nomeCompleto) {
    if (nomeCompleto.isEmpty) return '?';
    final partes = nomeCompleto.trim().split(' ');
    if (partes.length == 1) return partes[0];
    if (partes.length >= 2) return '${partes[0]} ${partes[1]}';
    return partes[0];
  }

  Future<void> _mostrarAlunosGraduacao(BuildContext context, Map<String, dynamic> graduacao) async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('graduacao_id', isEqualTo: graduacao['id'])
          .orderBy('nome')
          .get();

      final alunos = snapshot.docs.map((doc) {
        final data = doc.data();
        Timestamp? dataGraduacao = data['data_graduacao_atual'] as Timestamp?;
        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Nome não informado',
          'data_graduacao': dataGraduacao?.toDate(),
          'foto': data['foto_perfil_aluno'] as String?,
        };
      }).toList();

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: Column(
              children: [
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
                          '${graduacao['nome_graduacao']} (${alunos.length})',
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
                      String nomeExibicao = _getPrimeiroESegundoNome(aluno['nome']);

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
                              nomeExibicao.isNotEmpty ? nomeExibicao[0] : '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            )
                                : null,
                          ),
                          title: Text(nomeExibicao),
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
    } catch (e) {
      print('Erro ao buscar alunos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar alunos: $e'), backgroundColor: Colors.red),
      );
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
          title: const Text('🥋 GRADUAÇÕES'),
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
    final screenWidth = MediaQuery.of(context).size.width;

    if (_svgContent == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text(
              'Erro ao carregar SVG',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_graduacoes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma graduação encontrada',
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

    // Grid responsivo
    int crossAxisCount;
    double childAspectRatio;
    double horizontalPadding;

    if (screenWidth > 1200) {
      crossAxisCount = 4;
      childAspectRatio = 0.9;
      horizontalPadding = 24;
    } else if (screenWidth > 900) {
      crossAxisCount = 3;
      childAspectRatio = 0.9;
      horizontalPadding = 20;
    } else if (screenWidth > 600) {
      crossAxisCount = 2;
      childAspectRatio = 0.9;
      horizontalPadding = 16;
    } else {
      crossAxisCount = 2;
      childAspectRatio = 0.85;
      horizontalPadding = 12;
    }

    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _graduacoes.length,
      itemBuilder: (context, index) {
        final graduacao = _graduacoes[index];
        final modifiedSvg = _getModifiedSvg(graduacao, _svgContent!);

        return GestureDetector(
          onTap: () => _mostrarAlunosGraduacao(context, graduacao),
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
                          graduacao['nome_graduacao'] ?? 'Sem nome',
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
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
                            graduacao['tipo_publico'] ?? 'Geral',
                            style: TextStyle(
                              fontSize: isMobile ? 9 : 10,
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
  }
}