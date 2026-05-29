import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/site_config_service.dart';

class ConfigurarMenuScreen extends StatefulWidget {
  final List<Map<String, dynamic>> secoes;
  final VoidCallback onSalvo;

  const ConfigurarMenuScreen({
    super.key,
    required this.secoes,
    required this.onSalvo,
  });

  @override
  State<ConfigurarMenuScreen> createState() => _ConfigurarMenuScreenState();
}

class _ConfigurarMenuScreenState extends State<ConfigurarMenuScreen> {
  late List<Map<String, dynamic>> _itens;
  late List<Map<String, dynamic>> _itensVisiveis;

  final SiteConfigService _configService = SiteConfigService();

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _itens = List<Map<String, dynamic>>.from(widget.secoes);
    _itensVisiveis = _itens.where((item) => item['is_config'] != true).toList();
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

  Color _safeColor(dynamic value, {Color? fallback}) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    return fallback ?? context.uai.primary;
  }

  IconData _safeIcon(dynamic value) {
    if (value is IconData) return value;
    return Icons.widgets_rounded;
  }

  String _safeText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Future<void> _salvarOrdem() async {
    if (_salvando) return;

    setState(() => _salvando = true);

    try {
      final ordem = _itensVisiveis.map((item) => item['id'] as String).toList();
      await _configService.salvarOrdemMenu(ordem);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Ordem salva com sucesso!'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.buttonRadius),
          ),
        ),
      );

      widget.onSalvo();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.uai.buttonRadius),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;

      final item = _itensVisiveis.removeAt(oldIndex);
      _itensVisiveis.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Ordenar Menu'),
        actions: [
          TextButton.icon(
            onPressed: _salvando ? null : _salvarOrdem,
            icon: _salvando
                ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _readableOn(t.primary),
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR'),
            style: TextButton.styleFrom(
              foregroundColor:
              Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(t.primary),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInfoHeader(),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 104),
              itemCount: _itensVisiveis.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final value = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: 1 + (value * 0.025),
                      child: Material(
                        elevation: 8,
                        color: Colors.transparent,
                        shadowColor: Colors.black.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(t.cardRadius),
                        child: child,
                      ),
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final item = _itensVisiveis[index];
                return _buildDraggableItem(item, index);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarOrdem,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _readableOn(t.primary),
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR ORDEM'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoHeader() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: t.primaryGradient,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              boxShadow: t.cardShadow,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 560;

                final icon = Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: onPrimary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(t.buttonRadius + 4),
                    border: Border.all(color: onPrimary.withOpacity(0.16)),
                  ),
                  child: Icon(
                    Icons.swap_vert_rounded,
                    color: onPrimary,
                    size: 31,
                  ),
                );

                final content = Column(
                  crossAxisAlignment:
                  narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organizar menu do site',
                      textAlign: narrow ? TextAlign.center : TextAlign.left,
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: narrow ? 21 : 24,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Arraste as seções para definir a ordem dos botões no site público.',
                      textAlign: narrow ? TextAlign.center : TextAlign.left,
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.84),
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Wrap(
                      alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _headerChip(
                          icon: Icons.drag_indicator_rounded,
                          label: 'Arraste para ordenar',
                        ),
                        _headerChip(
                          icon: Icons.widgets_rounded,
                          label: '${_itensVisiveis.length} itens',
                        ),
                      ],
                    ),
                  ],
                );

                if (narrow) {
                  return Column(
                    children: [
                      icon,
                      const SizedBox(height: 13),
                      content,
                    ],
                  );
                }

                return Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerChip({
    required IconData icon,
    required String label,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

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
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableItem(Map<String, dynamic> item, int index) {
    final t = context.uai;
    final bool isInicio = item['id'] == 'inicio';
    final rawColor = _safeColor(item['cor'], fallback: t.primary);
    final color = _ensureVisible(rawColor, t.card);
    final title = _safeText(item['titulo'], 'Sem título');
    final subtitle = _safeText(item['descricao'], 'Sem descrição');
    final icon = _safeIcon(item['icone']);

    return Padding(
      key: ValueKey(item['id'] ?? 'menu_$index'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: null,
              borderRadius: BorderRadius.circular(t.cardRadius),
              splashColor: isInicio ? Colors.transparent : color.withOpacity(0.08),
              highlightColor: isInicio ? Colors.transparent : color.withOpacity(0.04),
              child: Container(
                constraints: const BoxConstraints(minHeight: 78),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  border: Border.all(
                    color: isInicio ? t.border : color.withOpacity(0.16),
                  ),
                  boxShadow: t.softShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 48,
                      alignment: Alignment.center,
                      child: isInicio
                          ? Icon(Icons.lock_rounded, color: t.textMuted, size: 20)
                          : ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: t.textMuted,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withOpacity(isInicio ? 0.08 : 0.12),
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                        border: Border.all(color: color.withOpacity(0.14)),
                      ),
                      child: Icon(icon, color: color, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isInicio ? t.primary : t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              if (isInicio) ...[
                                const SizedBox(width: 6),
                                _lockedChip(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isInicio
                                ? 'Item fixo no topo do menu público.'
                                : subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11.5,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isInicio)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: color.withOpacity(0.13)),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.push_pin_rounded, color: t.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lockedChip() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: t.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.primary.withOpacity(0.14)),
      ),
      child: Text(
        'FIXO',
        style: TextStyle(
          color: _ensureVisible(t.primary, t.card),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
