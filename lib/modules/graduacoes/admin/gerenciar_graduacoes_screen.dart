import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:xml/xml.dart' as xml;

import 'editar_graduacao_screen.dart';
import 'package:uai_capoeira/modules/graduacoes/screens/graduacao_detalhe_screen.dart';

class GerenciarGraduacoesScreen extends StatefulWidget {
  const GerenciarGraduacoesScreen({super.key});

  @override
  State<GerenciarGraduacoesScreen> createState() =>
      _GerenciarGraduacoesScreenState();
}

class _GerenciarGraduacoesScreenState extends State<GerenciarGraduacoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _svgContent;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

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

  Future<void> _showDeleteConfirmation({
    required String docId,
    required String nome,
  }) async {
    final t = context.uai;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
            side: BorderSide(color: t.border),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: t.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Excluir graduação?',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Você tem certeza que deseja excluir "$nome"?\n\nEsta ação é irreversível.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'CANCELAR',
                style: TextStyle(color: t.textSecondary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('EXCLUIR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.error,
                foregroundColor: _readableOn(t.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      try {
        await _firestore.collection('graduacoes').doc(docId).delete();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Graduação excluída com sucesso.'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir graduação: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _abrirCriacao() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditarGraduacaoScreen()),
    );
  }

  Future<void> _abrirEdicao(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarGraduacaoScreen(graduacaoId: id),
      ),
    );
  }

  Future<void> _abrirDetalhe(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GraduacaoDetalheScreen(graduacaoId: id),
      ),
    );
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

  String _nivelTexto(dynamic nivel, String tipoPublico) {
    final nivelText = nivel?.toString().trim();

    final partes = [
      if (nivelText != null && nivelText.isNotEmpty) 'Nível $nivelText',
      if (tipoPublico.trim().isNotEmpty) tipoPublico.trim().toUpperCase(),
    ];

    return partes.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Catálogo de Graduações',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Nova graduação',
            onPressed: _abrirCriacao,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('graduacoes')
            .orderBy('nivel_graduacao')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _svgContent == null) {
            return Center(
              child: CircularProgressIndicator(color: t.primary),
            );
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future<void>.delayed(const Duration(milliseconds: 300));
            },
            color: t.primary,
            backgroundColor: t.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderCard(docs.length),
                        const SizedBox(height: 14),
                        _buildGraduacoesList(docs),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCriacao,
        backgroundColor: t.primary,
        foregroundColor: _onPrimary(),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'NOVA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(int total) {
    final t = context.uai;
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar Graduações',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cadastre cordas, cores, títulos e descrições exibidas no site.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildHeroChip(
                    icon: Icons.list_alt_rounded,
                    label: '$total graduações',
                  ),
                  _buildHeroChip(
                    icon: Icons.edit_rounded,
                    label: 'Edição rápida',
                  ),
                  _buildHeroChip(
                    icon: Icons.public_rounded,
                    label: 'Site e certificados',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroChip({
    required IconData icon,
    required String label,
  }) {
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

  Widget _buildGraduacoesList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;

        if (!wide) {
          return Column(
            children: docs.map((doc) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildGraduacaoCard(doc, compact: true),
              );
            }).toList(),
          );
        }

        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: docs.map((doc) {
            return SizedBox(
              width: itemWidth,
              child: _buildGraduacaoCard(doc, compact: false),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildGraduacaoCard(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, {
        required bool compact,
      }) {
    final t = context.uai;
    final data = doc.data();
    final modifiedSvg = _getModifiedSvg(data);

    final nome = data['nome_graduacao']?.toString() ?? 'Nome não informado';
    final titulo = data['titulo_graduacao']?.toString() ?? '';
    final corda = data['corda']?.toString() ?? '';
    final tipoPublico = data['tipo_publico']?.toString() ?? '';
    final descricao = _descricaoGraduacao(data);
    final nivel = data['nivel_graduacao'];
    final color1 = _ensureVisible(
      _safeColor(data['hex_cor1'], fallback: t.primary),
      t.card,
    );
    final color2 = _safeColor(data['hex_cor2'], fallback: color1);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalhe(doc.id),
        borderRadius: BorderRadius.circular(t.cardRadius),
        splashColor: color1.withOpacity(0.12),
        highlightColor: color1.withOpacity(0.06),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: color1.withOpacity(0.14)),
            boxShadow: t.softShadow,
          ),
          child: compact
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCardTop(
                modifiedSvg: modifiedSvg,
                color1: color1,
                color2: color2,
                data: data,
                compact: true,
              ),
              const SizedBox(height: 12),
              _buildCardText(
                nome: nome,
                titulo: titulo,
                corda: corda,
                tipoPublico: tipoPublico,
                descricao: descricao,
                nivel: nivel,
                centered: true,
              ),
              const SizedBox(height: 12),
              _buildCardActions(doc.id, nome),
            ],
          )
              : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: _buildCardTop(
                  modifiedSvg: modifiedSvg,
                  color1: color1,
                  color2: color2,
                  data: data,
                  compact: false,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildCardText(
                  nome: nome,
                  titulo: titulo,
                  corda: corda,
                  tipoPublico: tipoPublico,
                  descricao: descricao,
                  nivel: nivel,
                  centered: false,
                ),
              ),
              const SizedBox(width: 8),
              _buildPopupMenu(doc.id, nome),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardTop({
    required String modifiedSvg,
    required Color color1,
    required Color color2,
    required Map<String, dynamic> data,
    required bool compact,
  }) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          SizedBox(
            height: compact ? 92 : 98,
            child: Center(
              child: modifiedSvg.isNotEmpty
                  ? SvgPicture.string(modifiedSvg, fit: BoxFit.contain)
                  : Icon(
                Icons.image_not_supported_rounded,
                color: t.textMuted,
                size: 46,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 7,
            width: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [color1, color2]),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _nivelTexto(data['nivel_graduacao'], data['tipo_publico']?.toString() ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardText({
    required String nome,
    required String titulo,
    required String corda,
    required String tipoPublico,
    required String descricao,
    required dynamic nivel,
    required bool centered,
  }) {
    final t = context.uai;
    final meta = [
      if (nivel?.toString().trim().isNotEmpty == true) 'Nível $nivel',
      if (titulo.trim().isNotEmpty) titulo.trim(),
      if (corda.trim().isNotEmpty) corda.trim(),
      if (tipoPublico.trim().isNotEmpty) tipoPublico.trim().toUpperCase(),
    ].join(' • ');

    return Column(
      crossAxisAlignment:
      centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          nome,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 15.5,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            meta,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 11.5,
              height: 1.22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (descricao.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            descricao,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              height: 1.28,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCardActions(String id, String nome) {
    final t = context.uai;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _abrirDetalhe(id),
            icon: const Icon(Icons.visibility_rounded, size: 18),
            label: const Text('VER'),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.info,
              side: BorderSide(color: t.info.withOpacity(0.28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _abrirEdicao(id),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('EDITAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _onPrimary(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _showDeleteConfirmation(docId: id, nome: nome),
          icon: Icon(Icons.delete_rounded, color: t.error),
          tooltip: 'Excluir',
        ),
      ],
    );
  }

  Widget _buildPopupMenu(String id, String nome) {
    final t = context.uai;

    return PopupMenuButton<String>(
      color: t.surface,
      icon: Icon(Icons.more_vert_rounded, color: t.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'ver') {
          _abrirDetalhe(id);
        } else if (value == 'editar') {
          _abrirEdicao(id);
        } else if (value == 'excluir') {
          _showDeleteConfirmation(docId: id, nome: nome);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'ver',
          child: ListTile(
            leading: Icon(Icons.visibility_rounded, color: t.info),
            title: Text('Ver detalhes', style: TextStyle(color: t.textPrimary)),
          ),
        ),
        PopupMenuItem<String>(
          value: 'editar',
          child: ListTile(
            leading: Icon(Icons.edit_rounded, color: t.primary),
            title: Text('Editar', style: TextStyle(color: t.textPrimary)),
          ),
        ),
        PopupMenuItem<String>(
          value: 'excluir',
          child: ListTile(
            leading: Icon(Icons.delete_rounded, color: t.error),
            title: Text(
              'Excluir',
              style: TextStyle(color: t.error, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(String error) {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.error.withOpacity(0.18)),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 70, color: t.error),
              const SizedBox(height: 12),
              Text(
                'Erro ao carregar graduações',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 74,
                color: t.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                'Nenhuma graduação encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Toque em Nova para cadastrar a primeira graduação.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _abrirCriacao,
                icon: const Icon(Icons.add_rounded),
                label: const Text('NOVA GRADUAÇÃO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _onPrimary(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
