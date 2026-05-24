import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'editar_graduacao_screen.dart';

class GraduacaoDetalheScreen extends StatefulWidget {
  final String graduacaoId;

  const GraduacaoDetalheScreen({
    super.key,
    required this.graduacaoId,
  });

  @override
  State<GraduacaoDetalheScreen> createState() => _GraduacaoDetalheScreenState();
}

class _GraduacaoDetalheScreenState extends State<GraduacaoDetalheScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _svgContent;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (mounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('Erro ao carregar corda.svg: $e');
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null || _svgContent!.isEmpty) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.trim().length < 6) {
          return Colors.grey;
        }

        try {
          final cleaned = hexColor.replaceAll('#', '').trim();

          if (cleaned.length == 6) {
            return Color(int.parse('FF$cleaned', radix: 16));
          }

          if (cleaned.length == 8) {
            return Color(int.parse(cleaned, radix: 16));
          }
        } catch (_) {}

        return Colors.grey;
      }

      String colorToHex(Color color) {
        return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
      }

      void changeColor(String id, Color color) {
        final element = document.rootElement.descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.getAttribute('id') == id,
          orElse: () => xml.XmlElement(xml.XmlName('')),
        );

        if (element.name.local.isNotEmpty) {
          final style = element.getAttribute('style') ?? '';
          final hex = colorToHex(color).toLowerCase();
          final newStyle =
          style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');

          element.setAttribute('style', 'fill:$hex;$newStyle');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']?.toString()));
      changeColor('cor2', colorFromHex(data['hex_cor2']?.toString()));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']?.toString()));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']?.toString()));

      return document.toXmlString();
    } catch (e) {
      debugPrint('Erro ao modificar SVG: $e');
      return _svgContent ?? '';
    }
  }

  String _descricaoGraduacao(Map<String, dynamic> data) {
    final candidatos = [
      data['descricao_site'],
      data['descricao_graduacao'],
      data['descricao'],
      data['frase_descricao'],
    ];

    for (final value in candidatos) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }

    return '';
  }

  Color _safeColor(dynamic hex, {required Color fallback}) {
    final value = hex?.toString().trim();

    if (value == null || value.isEmpty) return fallback;

    try {
      final cleaned = value.replaceAll('#', '').toUpperCase();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  Future<void> _abrirEdicao() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarGraduacaoScreen(
          graduacaoId: widget.graduacaoId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Detalhes da Graduação',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: _abrirEdicao,
            tooltip: 'Editar graduação',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('graduacoes')
            .doc(widget.graduacaoId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _svgContent == null) {
            return Center(
              child: CircularProgressIndicator(color: Colors.red.shade900),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return _buildErrorState();
          }

          final data = snapshot.data!.data()!;
          final modifiedSvg = _getModifiedSvg(data);

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1060),
                      child: isWide
                          ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 390,
                            child: _buildHeroCard(data, modifiedSvg),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: _buildInfoContent(data)),
                        ],
                      )
                          : Column(
                        children: [
                          _buildHeroCard(data, modifiedSvg),
                          const SizedBox(height: 14),
                          _buildInfoContent(data),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirEdicao,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded),
        label: const Text(
          'EDITAR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> data, String modifiedSvg) {
    final color1 = _safeColor(data['hex_cor1'], fallback: Colors.red.shade900);
    final color2 = _safeColor(data['hex_cor2'], fallback: color1);

    final nome = data['nome_graduacao']?.toString() ?? 'Nome não informado';
    final titulo = data['titulo_graduacao']?.toString() ?? '';
    final corda = data['corda']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            nome,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          if (titulo.trim().isNotEmpty || corda.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              [
                if (titulo.trim().isNotEmpty) titulo.trim(),
                if (corda.trim().isNotEmpty) corda.trim(),
              ].join(' • '),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            height: 150,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: modifiedSvg.isNotEmpty
                ? SvgPicture.string(modifiedSvg, fit: BoxFit.contain)
                : Center(
              child: Icon(
                Icons.image_not_supported_rounded,
                color: Colors.grey.shade300,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 8,
            width: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [color1, color2]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoContent(Map<String, dynamic> data) {
    final descricao = _descricaoGraduacao(data);
    final frase = data['frase']?.toString().trim() ?? '';

    return Column(
      children: [
        _buildSectionCard(
          icon: Icons.info_rounded,
          title: 'Informações principais',
          children: [
            _buildInfoTile(
              icon: Icons.shield_rounded,
              label: 'Nome da Graduação',
              value: data['nome_graduacao']?.toString() ?? 'Não informado',
            ),
            _buildInfoTile(
              icon: Icons.school_rounded,
              label: 'Título',
              value: data['titulo_graduacao']?.toString() ?? 'Não informado',
            ),
            _buildInfoTile(
              icon: Icons.linear_scale_rounded,
              label: 'Corda',
              value: data['corda']?.toString() ?? 'Não informada',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          icon: Icons.tune_rounded,
          title: 'Configurações',
          children: [
            _buildInfoTile(
              icon: Icons.leaderboard_rounded,
              label: 'Nível',
              value: data['nivel_graduacao']?.toString() ?? 'Não informado',
            ),
            _buildInfoTile(
              icon: Icons.cake_rounded,
              label: 'Idade mínima',
              value: data['idade_minima']?.toString() ?? 'Não informada',
            ),
            _buildInfoTile(
              icon: Icons.groups_rounded,
              label: 'Público',
              value: data['tipo_publico']?.toString() ?? 'Não informado',
            ),
            _buildInfoTile(
              icon: Icons.description_rounded,
              label: 'Tipo documento',
              value: data['certificado_ou_diploma']?.toString() ??
                  'Não informado',
            ),
          ],
        ),
        if (descricao.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildTextSectionCard(
            icon: Icons.public_rounded,
            title: 'Descrição no site',
            text: descricao,
          ),
        ],
        if (frase.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildTextSectionCard(
            icon: Icons.text_snippet_rounded,
            title: 'Frase do certificado',
            text: frase,
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _sectionHeader(icon: icon, title: title),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextSectionCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: icon, title: title),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 13.2,
                height: 1.36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: Colors.red.shade900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade800, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade700,
                size: 72,
              ),
              const SizedBox(height: 12),
              const Text(
                'Erro ao carregar os dados da graduação.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
