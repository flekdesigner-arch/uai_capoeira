import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/logo_service.dart';

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

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString(
        'assets/images/corda.svg',
      );

      if (!mounted) return;

      setState(() {
        _svgContent = content;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar SVG: $e');

      if (!mounted) return;

      setState(() => _carregando = false);
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return context.uai.textMuted;

        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (_) {
          return context.uai.textMuted;
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

          if (element.name.local.isEmpty) return;

          final style = element.getAttribute('style') ?? '';
          final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
          final newStyle = style.contains('fill:')
              ? style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), 'fill:$hex')
              : 'fill:$hex;$style';

          element.setAttribute('style', newStyle);
        } catch (e) {
          debugPrint('Erro ao mudar cor da parte $id: $e');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']?.toString()));
      changeColor('cor2', colorFromHex(data['hex_cor2']?.toString()));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']?.toString()));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']?.toString()));

      return document.toXmlString();
    } catch (e) {
      debugPrint('Erro ao modificar SVG: $e');
      return _svgContent!;
    }
  }

  Future<List<Map<String, dynamic>>> _getAlunosPorGraduacao(
      String graduacaoId,
      String nomeGraduacao,
      ) async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('graduacao_id', isEqualTo: graduacaoId)
          .orderBy('nome')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        final dataGraduacao = data['data_graduacao_atual'] as Timestamp?;

        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Nome não informado',
          'data_graduacao': dataGraduacao?.toDate(),
          'foto': data['foto_perfil_aluno'] as String?,
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao buscar alunos: $e');
      return [];
    }
  }

  void _mostrarAlunosDialog(
      BuildContext context,
      String nomeGraduacao,
      List<Map<String, dynamic>> alunos,
      ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        final onPrimary = _readableOn(t.primary);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.76,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(gradient: t.primaryGradient),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: onPrimary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                            border: Border.all(color: onPrimary.withOpacity(0.16)),
                          ),
                          child: Icon(Icons.people_rounded, color: onPrimary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nomeGraduacao,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: onPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${alunos.length} aluno(s) nesta graduação',
                                style: TextStyle(
                                  color: onPrimary.withOpacity(0.82),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: onPrimary),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: alunos.isEmpty
                        ? _buildDialogEmptyState(t)
                        : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: alunos.length,
                      itemBuilder: (context, index) {
                        final aluno = alunos[index];
                        final nome = aluno['nome']?.toString() ?? 'Aluno';
                        final foto = aluno['foto']?.toString() ?? '';
                        final dataGraduacao = aluno['data_graduacao'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: t.card,
                            borderRadius: BorderRadius.circular(t.cardRadius - 6),
                            border: Border.all(color: t.border),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              radius: 21,
                              backgroundColor: t.primary.withOpacity(0.12),
                              backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                              child: foto.isEmpty
                                  ? Text(
                                nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: _ensureVisible(t.primary, t.card),
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                                  : null,
                            ),
                            title: Text(
                              nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: dataGraduacao != null
                                ? Text(
                              'Graduado em: ${DateFormat('dd/MM/yyyy').format(dataGraduacao)}',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                              ),
                            )
                                : Text(
                              'Data de graduação não informada',
                              style: TextStyle(
                                color: t.textMuted,
                                fontSize: 12,
                              ),
                            ),
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
      },
    );
  }

  Widget _buildDialogEmptyState(dynamic t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 56, color: t.textMuted),
            const SizedBox(height: 10),
            Text(
              'Nenhum aluno com esta graduação',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quando houver alunos vinculados, eles aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Catálogo de Graduações'),
      ),
      body: RefreshIndicator(
        color: t.primary,
        backgroundColor: t.surface,
        onRefresh: _loadSvg,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: _buildHero(),
                  ),
                ),
              ),
            ),
            if (_svgContent == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildSvgErrorState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                sliver: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore
                      .collection('graduacoes')
                      .orderBy('nivel_graduacao')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(color: t.primary),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildErrorState(snapshot.error),
                      );
                    }

                    final graduacoes = snapshot.data?.docs ?? [];

                    if (graduacoes.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      );
                    }

                    return SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final crossAxisCount = width >= 980
                                  ? 4
                                  : width >= 720
                                  ? 3
                                  : 2;
                              final childAspectRatio = width < 420 ? 0.74 : 0.82;

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: childAspectRatio,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: graduacoes.length,
                                itemBuilder: (context, index) {
                                  final doc = graduacoes[index];
                                  final data = doc.data();
                                  final modifiedSvg = _getModifiedSvg(data);

                                  return _buildGraduacaoCard(
                                    docId: doc.id,
                                    data: data,
                                    modifiedSvg: modifiedSvg,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
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

          final logo = Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Color.alphaBlend(onPrimary.withOpacity(0.94), t.primary),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.18)),
            ),
            child: _logoService.buildLogo(height: 58),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Sistema de Cordas',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 23 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Catálogo visual das graduações cadastradas. Toque em uma corda para ver os alunos vinculados.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.workspace_premium_rounded, 'Graduações'),
                  _heroChip(Icons.people_rounded, 'Alunos por corda'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                logo,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              logo,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
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

  Widget _buildGraduacaoCard({
    required String docId,
    required Map<String, dynamic> data,
    required String modifiedSvg,
  }) {
    final t = context.uai;
    final nome = data['nome_graduacao']?.toString() ?? 'Sem nome';
    final tipo = data['tipo_publico']?.toString() ?? 'Geral';
    final nivel = data['nivel_graduacao']?.toString() ?? '—';
    final cor1 = _parseHexColor(data['hex_cor1']?.toString(), fallback: t.primary);
    final accent = _ensureVisible(cor1, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final alunos = await _getAlunosPorGraduacao(docId, nome);

          if (!mounted) return;

          _mostrarAlunosDialog(context, nome, alunos);
        },
        splashColor: accent.withOpacity(0.10),
        highlightColor: accent.withOpacity(0.05),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: accent.withOpacity(0.18)),
            boxShadow: t.softShadow,
          ),
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(accent.withOpacity(0.06), t.cardAlt),
                    border: Border(
                      bottom: BorderSide(color: accent.withOpacity(0.10)),
                    ),
                  ),
                  child: SvgPicture.string(
                    modifiedSvg,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.alphaBlend(accent.withOpacity(0.10), t.card),
                        t.card,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nome,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _miniChip(
                            icon: Icons.groups_rounded,
                            label: tipo,
                            color: accent,
                          ),
                          _miniChip(
                            icon: Icons.stairs_rounded,
                            label: 'Nv $nivel',
                            color: t.info,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 11),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSvgErrorState() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _stateDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, size: 64, color: t.error),
              const SizedBox(height: 12),
              Text(
                'SVG da corda não encontrado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Verifique o arquivo assets/images/corda.svg.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
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
          padding: const EdgeInsets.all(22),
          decoration: _stateDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_outlined, size: 64, color: t.textMuted),
              const SizedBox(height: 12),
              Text(
                'Nenhuma graduação encontrada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'As graduações cadastradas aparecerão aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object? error) {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          decoration: _stateDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: t.error),
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
              const SizedBox(height: 6),
              Text(
                error?.toString() ?? 'Tente novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _stateDecoration() {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }

  Color _parseHexColor(String? value, {required Color fallback}) {
    if (value == null || value.trim().isEmpty) return fallback;

    try {
      final normalized = value.trim().replaceAll('#', '');
      return Color(int.parse('FF$normalized', radix: 16));
    } catch (_) {
      return fallback;
    }
  }
}
