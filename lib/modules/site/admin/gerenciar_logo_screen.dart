import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/site/services/logo_service.dart';

class GerenciarLogoScreen extends StatefulWidget {
  const GerenciarLogoScreen({super.key});

  @override
  State<GerenciarLogoScreen> createState() => _GerenciarLogoScreenState();
}

class _GerenciarLogoScreenState extends State<GerenciarLogoScreen> {
  final LogoService _logoService = LogoService();
  final TextEditingController _urlController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
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

  Future<void> _carregarUrl() async {
    if (mounted) {
      setState(() => _carregando = true);
    }

    try {
      final url = await _logoService.getLogoUrl();

      if (!mounted) return;
      setState(() {
        _urlController.text = url ?? '';
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mostrarSnackBar('Erro ao carregar logo: $e', isErro: true);
    }
  }

  bool _urlPareceValida(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.trim().isNotEmpty;
  }

  Future<void> _salvar() async {
    final novaUrl = _urlController.text.trim();

    if (novaUrl.isEmpty) {
      _mostrarSnackBar('Por favor, insira uma URL.', isErro: true, isWarning: true);
      return;
    }

    if (!_urlPareceValida(novaUrl)) {
      _mostrarSnackBar(
        'Informe uma URL válida começando com http:// ou https://.',
        isErro: true,
        isWarning: true,
      );
      return;
    }

    if (mounted) setState(() => _salvando = true);

    try {
      await FirebaseFirestore.instance.collection('configuracoes').doc('logo').set({
        'url': novaUrl,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      _logoService.limparCache();

      if (!mounted) return;

      _mostrarSnackBar('✅ Logo salva com sucesso!');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        _mostrarSnackBar('Erro ao salvar logo: $e', isErro: true);
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarSnackBar(
      String mensagem, {
        bool isErro = false,
        bool isWarning = false,
      }) {
    final t = context.uai;
    final bg = isErro
        ? (isWarning ? t.warning : t.error)
        : t.success;
    final fg = _readableOn(bg);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensagem,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Future<void> _testarUrl() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      _mostrarSnackBar('Digite uma URL para pré-visualizar.', isErro: true, isWarning: true);
      return;
    }

    if (!_urlPareceValida(url)) {
      _mostrarSnackBar(
        'URL inválida. Use um link começando com http:// ou https://.',
        isErro: true,
        isWarning: true,
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return AlertDialog(
          backgroundColor: t.surface,
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: primary.withOpacity(0.16)),
                ),
                child: Icon(Icons.preview_rounded, color: primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pré-visualização',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              height: 240,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.cardRadius - 6),
                border: Border.all(color: t.border),
              ),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  final errorColor = _ensureVisible(t.error, t.cardAlt);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_rounded, color: errorColor, size: 54),
                      const SizedBox(height: 10),
                      Text(
                        'Não foi possível carregar a imagem.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confira se a URL está pública e acessível.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;

                  return Center(
                    child: CircularProgressIndicator(color: primary),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('FECHAR'),
            ),
          ],
        );
      },
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
        title: const Text(
          'Gerenciar Logo do Site',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _salvando ? null : _carregarUrl,
            tooltip: 'Recarregar logo',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth < 560 ? 14.0 : 22.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 106),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(),
                      const SizedBox(height: 14),
                      _buildPreviewCard(),
                      const SizedBox(height: 14),
                      _buildUrlCard(),
                      const SizedBox(height: 14),
                      _buildInfoCard(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildBottomBar(),
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
              Icons.image_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Logo do Site',
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
                'Configure a imagem exibida na página inicial e nas áreas públicas do site.',
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
                  _whiteChip(icon: Icons.link_rounded, label: 'URL pública'),
                  _whiteChip(icon: Icons.preview_rounded, label: 'Pré-visualização'),
                  _whiteChip(icon: Icons.cached_rounded, label: 'Cache atualizado'),
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

  Widget _buildPreviewCard() {
    final t = context.uai;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.visibility_rounded,
            title: 'Pré-visualização atual',
            subtitle: 'Veja como a logo cadastrada está carregando no app.',
            color: t.info,
          ),
          const SizedBox(height: 16),
          Container(
            height: 190,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: _logoService.buildLogo(height: 150),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlCard() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: Icons.link_rounded,
            title: 'URL da logo',
            subtitle: 'Insira o link direto de uma imagem PNG, JPG, WEBP ou SVG.',
            color: t.primary,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            style: TextStyle(color: t.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL da imagem',
              hintText: 'https://exemplo.com/logo.png',
              labelStyle: TextStyle(color: t.textSecondary),
              hintStyle: TextStyle(color: t.textMuted),
              prefixIcon: Icon(Icons.link_rounded, color: primary),
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
                borderSide: BorderSide(color: primary, width: 1.4),
              ),
            ),
            onSubmitted: (_) => _testarUrl(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _salvando ? null : _testarUrl,
            icon: const Icon(Icons.preview_rounded),
            label: const Text('PRÉ-VISUALIZAR ESTA URL'),
            style: OutlinedButton.styleFrom(
              foregroundColor: primary,
              side: BorderSide(color: primary.withOpacity(0.35)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.card);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(info.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: info.withOpacity(0.16)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: info.withOpacity(0.12),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: info.withOpacity(0.16)),
            ),
            child: Icon(Icons.info_rounded, color: info),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dicas importantes',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Use imagens com fundo transparente, de preferência PNG.\n'
                      '• Tamanho recomendado: 500x500px ou maior.\n'
                      '• A URL precisa ser pública para carregar no site.\n'
                      '• Após salvar, o cache da logo será limpo automaticamente.',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12.5,
                    height: 1.38,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
      ],
    );
  }

  Widget _cardShell({required Widget child}) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: child,
    );
  }

  Widget _buildBottomBar() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: ElevatedButton.icon(
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: onPrimary,
              strokeWidth: 2,
            ),
          )
              : const Icon(Icons.save_rounded),
          label: Text(_salvando ? 'SALVANDO...' : 'SALVAR LOGO'),
          style: ElevatedButton.styleFrom(
            backgroundColor: t.primary,
            foregroundColor: onPrimary,
            minimumSize: const Size.fromHeight(50),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        ),
      ),
    );
  }
}
