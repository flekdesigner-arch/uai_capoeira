import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/graduacoes/admin/editar_graduacao_screen.dart';

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

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null || _svgContent!.isEmpty) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.trim().length < 6) {
          return context.uai.textMuted;
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

        return context.uai.textMuted;
      }

      String colorToHex(Color color) {
        return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
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
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Detalhes da Graduação',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
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
              child: CircularProgressIndicator(color: t.primary),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return _buildErrorState();
          }

          final data = snapshot.data!.data()!;
          final modifiedSvg = _getModifiedSvg(data);

          return RefreshIndicator(
            color: t.primary,
            backgroundColor: t.surface,
            onRefresh: () async {
              setState(() {});
              await Future<void>.delayed(const Duration(milliseconds: 250));
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                final horizontal = constraints.maxWidth < 600 ? 14.0 : 18.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 96),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: isWide
                            ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 392,
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
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirEdicao,
        icon: const Icon(Icons.edit_rounded),
        label: const Text(
          'EDITAR',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> data, String modifiedSvg) {
    final t = context.uai;
    final onPrimary = _onPrimary();

    final color1 = _safeColor(data['hex_cor1'], fallback: t.primary);
    final color2 = _safeColor(data['hex_cor2'], fallback: color1);
    final visibleColor1 = _ensureVisible(color1, t.card);
    final visibleColor2 = _ensureVisible(color2, t.card);

    final nome = data['nome_graduacao']?.toString() ?? 'Nome não informado';
    final titulo = data['titulo_graduacao']?.toString() ?? '';
    final corda = data['corda']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: onPrimary,
              size: 32,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            nome,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onPrimary,
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
                color: onPrimary.withOpacity(0.78),
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
              color: t.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.14)),
            ),
            child: modifiedSvg.isNotEmpty
                ? SvgPicture.string(modifiedSvg, fit: BoxFit.contain)
                : Center(
              child: Icon(
                Icons.image_not_supported_rounded,
                color: t.textMuted,
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
              gradient: LinearGradient(colors: [visibleColor1, visibleColor2]),
              border: Border.all(color: onPrimary.withOpacity(0.12)),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(Icons.leaderboard_rounded, 'Nível ${data['nivel_graduacao'] ?? '--'}'),
              if ((data['tipo_publico']?.toString() ?? '').trim().isNotEmpty)
                _heroChip(Icons.groups_rounded, data['tipo_publico'].toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
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
          color: context.uai.info,
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
          color: context.uai.associacao,
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
            color: context.uai.success,
          ),
        ],
        if (frase.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildTextSectionCard(
            icon: Icons.text_snippet_rounded,
            title: 'Frase do certificado',
            text: frase,
            color: context.uai.warning,
          ),
        ],
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          children: [
            _sectionHeader(icon: icon, title: title, color: accent),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextSectionCard({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(icon: icon, title: title, color: accent),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.inputRadius),
                border: Border.all(color: t.border),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13.2,
                  height: 1.36,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: t.textPrimary,
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
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: t.textPrimary,
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

  Widget _buildErrorState() {
    final t = context.uai;
    final accent = _ensureVisible(t.error, t.card);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: accent.withOpacity(0.18)),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: accent,
                  size: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar os dados da graduação.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Verifique a conexão e tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
