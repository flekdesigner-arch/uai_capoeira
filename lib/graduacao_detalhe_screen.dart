import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'editar_graduacao_screen.dart';

class GraduacaoDetalheScreen extends StatefulWidget {
  final String graduacaoId;

  const GraduacaoDetalheScreen({super.key, required this.graduacaoId});

  @override
  State<GraduacaoDetalheScreen> createState() => _GraduacaoDetalheScreenState();
}

class _GraduacaoDetalheScreenState extends State<GraduacaoDetalheScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da Graduação'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EditarGraduacaoScreen(graduacaoId: widget.graduacaoId)),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('graduacoes').doc(widget.graduacaoId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _svgContent == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Erro ao carregar os dados da graduação."));
          }

          final data = snapshot.data!.data()!;
          final modifiedSvg = _getModifiedSvg(data);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- PREVIEW DA CORDA EM DESTAQUE ---
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  color: Colors.black.withOpacity(0.05),
                  child: SvgPicture.string(modifiedSvg, height: 80),
                ),
                
                // --- CARD DE INFORMAÇÕES PRINCIPAIS ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           _buildInfoRow(Icons.shield, "Nome da Graduação", data['nome_graduacao'] ?? 'Não informado'),
                           const SizedBox(height: 16),
                           _buildInfoRow(Icons.school, "Título", data['titulo_graduacao'] ?? 'Não informado'),
                        ],
                      ),
                    ),
                  ),
                ),

                // --- CARD DE REQUISITOS ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           _buildInfoRow(Icons.leaderboard, "Nível", data['nivel_graduacao']?.toString() ?? 'Não informado'),
                           const SizedBox(height: 16),
                           _buildInfoRow(Icons.cake, "Idade Mínima", data['idade_minima']?.toString() ?? 'Não informada'),
                            const SizedBox(height: 16),
                           _buildInfoRow(Icons.group, "Público", data['tipo_publico'] ?? 'Não informado'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget helper para criar linhas de informação com ícone
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.red.shade700, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
