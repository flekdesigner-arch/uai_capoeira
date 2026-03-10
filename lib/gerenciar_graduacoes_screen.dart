import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'editar_graduacao_screen.dart';
import 'graduacao_detalhe_screen.dart';

class GerenciarGraduacoesScreen extends StatefulWidget {
  const GerenciarGraduacoesScreen({super.key});

  @override
  State<GerenciarGraduacoesScreen> createState() => _GerenciarGraduacoesScreenState();
}

class _GerenciarGraduacoesScreenState extends State<GerenciarGraduacoesScreen> {
  String? _svgContent;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
    if (mounted) {
      setState(() {
        _svgContent = content;
      });
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null) return '';
    final document = xml.XmlDocument.parse(_svgContent!);

    Color colorFromHex(String? hexColor) {
      if (hexColor == null || hexColor.length < 7) return Colors.grey;
      return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
    }

    String colorToHex(Color color) {
      return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    }

    void changeColor(String id, Color color) {
      final element = document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere((e) => e.getAttribute('id') == id, orElse: () => xml.XmlElement(xml.XmlName('')));
      
      if(element.name.local.isNotEmpty){
        final style = element.getAttribute('style') ?? '';
        final hex = colorToHex(color).toLowerCase();
        final newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');
        element.setAttribute('style', 'fill:$hex;$newStyle');
      }
    }

    changeColor('cor1', colorFromHex(data['hex_cor1']));
    changeColor('cor2', colorFromHex(data['hex_cor2']));
    changeColor('corponta1', colorFromHex(data['hex_ponta1']));
    changeColor('corponta2', colorFromHex(data['hex_ponta2']));

    return document.toXmlString();
  }
  
  void _showDeleteConfirmation(BuildContext context, String docId, String nome) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text("Você tem certeza que deseja excluir a graduação \"$nome\"?\n\nEsta ação é irreversível."),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Excluir'),
              onPressed: () {
                FirebaseFirestore.instance.collection('graduacoes').doc(docId).delete();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de Graduações'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        // BOTÃO DE IMPORTAÇÃO REMOVIDO
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('graduacoes').orderBy('nivel_graduacao').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _svgContent == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Nenhuma graduação encontrada."));
          }

          final graduacoes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12.0),
            itemCount: graduacoes.length,
            itemBuilder: (context, index) {
              final graduacao = graduacoes[index];
              final data = graduacao.data() as Map<String, dynamic>;
              final modifiedSvg = _getModifiedSvg(data);
              final nomeGraduacao = data['nome_graduacao'] ?? 'Nome não informado';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shadowColor: Colors.black.withOpacity(0.2),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => GraduacaoDetalheScreen(graduacaoId: graduacao.id)));
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 140,
                        height: 110,
                        padding: const EdgeInsets.all(12.0),
                        color: Colors.grey[200],
                        child: SvgPicture.string(modifiedSvg, fit: BoxFit.contain),
                      ),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                nomeGraduacao,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data['titulo_graduacao'] ?? ' ',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),

                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.black54),
                        onSelected: (value) {
                          if (value == 'editar') {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => EditarGraduacaoScreen(graduacaoId: graduacao.id)));
                          } else if (value == 'excluir') {
                            _showDeleteConfirmation(context, graduacao.id, nomeGraduacao);
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'editar',
                            child: ListTile(leading: Icon(Icons.edit), title: Text('Editar')),
                          ),
                          const PopupMenuItem<String>(
                            value: 'excluir',
                            child: ListTile(leading: Icon(Icons.delete), title: Text('Excluir', style: TextStyle(color: Colors.red))),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditarGraduacaoScreen()),
          );
        },
        backgroundColor: Colors.red.shade900,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
