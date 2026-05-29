import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/site_config_service.dart';

class EditarTextosScreen extends StatefulWidget {
  final List<Map<String, dynamic>> secoes;
  final VoidCallback onSalvo;

  const EditarTextosScreen({
    super.key,
    required this.secoes,
    required this.onSalvo,
  });

  @override
  State<EditarTextosScreen> createState() => _EditarTextosScreenState();
}

class _EditarTextosScreenState extends State<EditarTextosScreen> {
  final SiteConfigService _configService = SiteConfigService();
  final Map<String, TextEditingController> _tituloControllers = {};
  final Map<String, TextEditingController> _descricaoControllers = {};

  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _inicializarControllers();
  }

  void _inicializarControllers() {
    for (final secao in widget.secoes) {
      final id = secao['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      _tituloControllers[id] = TextEditingController(
        text: secao['titulo']?.toString() ?? '',
      );
      _descricaoControllers[id] = TextEditingController(
        text: secao['descricao']?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _tituloControllers.values) {
      controller.dispose();
    }
    for (final controller in _descricaoControllers.values) {
      controller.dispose();
    }
    super.dispose();
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

  Color _safeColor(dynamic value) {
    if (value is Color) return value;
    if (value is int) return Color(value);
    return context.uai.primary;
  }

  IconData _safeIcon(dynamic value) {
    if (value is IconData) return value;
    return Icons.article_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Editar Textos',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarTextos,
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: _salvando && widget.secoes.isEmpty
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 104),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(),
                      const SizedBox(height: 14),
                      if (widget.secoes.isEmpty)
                        _buildEmptyState()
                      else
                        ...widget.secoes.map(_buildSecaoEditor),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarTextos,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _onPrimary(),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR TEXTOS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _onPrimary(),
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
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

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.edit_note_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Textos do Site',
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
                'Edite os títulos e descrições exibidos no menu e nas seções públicas do site.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(
                    icon: Icons.article_rounded,
                    label: '${widget.secoes.length} seções',
                  ),
                  _whiteChip(
                    icon: Icons.visibility_rounded,
                    label: 'Site público',
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

  Widget _whiteChip({
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

  Widget _buildSecaoEditor(Map<String, dynamic> secao) {
    final t = context.uai;
    final id = secao['id']?.toString() ?? '';
    final titleController = _tituloControllers[id];
    final descriptionController = _descricaoControllers[id];

    if (id.isEmpty || titleController == null || descriptionController == null) {
      return const SizedBox.shrink();
    }

    final icon = _safeIcon(secao['icone']);
    final rawColor = _safeColor(secao['cor']);
    final accent = _ensureVisible(rawColor, t.card);
    final tituloAtual = secao['titulo']?.toString() ?? 'Seção';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.13), t.cardAlt),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tituloAtual,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: $id',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: titleController,
            label: 'Título no menu',
            hint: 'Digite o título exibido no site',
            icon: Icons.title_rounded,
            accent: accent,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: descriptionController,
            label: 'Descrição',
            hint: 'Digite a descrição da seção',
            icon: Icons.description_rounded,
            accent: accent,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color accent,
    int maxLines = 1,
  }) {
    final t = context.uai;

    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        labelStyle: TextStyle(color: t.textSecondary),
        hintStyle: TextStyle(color: t.textMuted),
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 24 : 0),
          child: Icon(icon, color: accent),
        ),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 62, color: t.textMuted),
          const SizedBox(height: 12),
          Text(
            'Nenhuma seção recebida',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Volte para a tela anterior e carregue as seções do site antes de editar os textos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Future<void> _salvarTextos() async {
    if (_salvando) return;

    setState(() => _salvando = true);

    try {
      final Map<String, String> titulos = {};
      final Map<String, String> descricoes = {};

      for (final secao in widget.secoes) {
        final id = secao['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        titulos[id] = _tituloControllers[id]?.text.trim() ?? '';
        descricoes[id] = _descricaoControllers[id]?.text.trim() ?? '';
      }

      await _configService.salvarTitulos(titulos);
      await _configService.salvarDescricoes(descricoes);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Textos salvos com sucesso!'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
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
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }
}
