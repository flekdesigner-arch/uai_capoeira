import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';

class EventoCertificadoConfigDialog extends StatefulWidget {
  final ConfiguracoesCertificadoEvento configuracaoInicial;

  const EventoCertificadoConfigDialog({
    super.key,
    required this.configuracaoInicial,
  });

  static Future<ConfiguracoesCertificadoEvento?> show({
    required BuildContext context,
    required ConfiguracoesCertificadoEvento configuracaoInicial,
  }) {
    return showDialog<ConfiguracoesCertificadoEvento>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return EventoCertificadoConfigDialog(
          configuracaoInicial: configuracaoInicial,
        );
      },
    );
  }

  @override
  State<EventoCertificadoConfigDialog> createState() =>
      _EventoCertificadoConfigDialogState();
}

class _EventoCertificadoConfigDialogState
    extends State<EventoCertificadoConfigDialog> {
  late bool _ativo;
  late String _modeloPadrao;
  late bool _usarCidadeDoEvento;
  late bool _usarDataDoEvento;

  late final List<TextEditingController> _nomeControllers;
  late final List<TextEditingController> _apelidoControllers;

  final List<_ModeloCertificadoOption> _modelos = const [
    _ModeloCertificadoOption(
      id: ConfiguracoesCertificadoEvento.modeloAutomatico,
      title: 'Automático pela graduação',
      subtitle:
      'Usa CERTIFICADO, CERTIFICADO COM CPF ou DIPLOMA conforme a graduação do aluno.',
      icon: Icons.auto_awesome_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'CERTIFICADO',
      title: 'Forçar certificado simples',
      subtitle: 'Usa o modelo sem CPF para todos os participantes.',
      icon: Icons.card_membership_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'CERTIFICADOCOMCPF',
      title: 'Forçar certificado com CPF',
      subtitle: 'Usa o modelo com CPF para todos os participantes.',
      icon: Icons.badge_rounded,
    ),
    _ModeloCertificadoOption(
      id: 'DIPLOMA',
      title: 'Forçar diploma',
      subtitle: 'Usa o modelo de diploma para todos os participantes.',
      icon: Icons.history_edu_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();

    final config = widget.configuracaoInicial;
    final assinaturas = List<AssinaturaCertificadoEvento>.from(
      config.assinaturas.isEmpty
          ? ConfiguracoesCertificadoEvento.padrao().assinaturas
          : config.assinaturas,
    );

    while (assinaturas.length < 5) {
      assinaturas.add(const AssinaturaCertificadoEvento(nome: '', apelido: ''));
    }

    _ativo = config.ativo;
    _modeloPadrao = config.modeloPadrao;
    _usarCidadeDoEvento = config.usarCidadeDoEvento;
    _usarDataDoEvento = config.usarDataDoEvento;

    _nomeControllers = List.generate(
      5,
          (index) => TextEditingController(text: assinaturas[index].nome),
    );

    _apelidoControllers = List.generate(
      5,
          (index) => TextEditingController(text: assinaturas[index].apelido),
    );
  }

  @override
  void dispose() {
    for (final controller in _nomeControllers) {
      controller.dispose();
    }
    for (final controller in _apelidoControllers) {
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _salvar() {
    final assinaturas = <AssinaturaCertificadoEvento>[];

    for (var i = 0; i < 5; i++) {
      final nome = _nomeControllers[i].text.trim();
      final apelido = _apelidoControllers[i].text.trim();

      if (nome.isEmpty && apelido.isEmpty) continue;

      assinaturas.add(
        AssinaturaCertificadoEvento(
          nome: nome,
          apelido: apelido,
        ),
      );
    }

    if (_ativo && assinaturas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Informe pelo menos uma assinatura.'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      ConfiguracoesCertificadoEvento(
        ativo: _ativo,
        modeloPadrao: _modeloPadrao,
        assinaturas: assinaturas,
        usarCidadeDoEvento: _usarCidadeDoEvento,
        usarDataDoEvento: _usarDataDoEvento,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final onPrimary = _readableOn(primary);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 760),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 4),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              children: [
                _buildHeader(primary, onPrimary),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    children: [
                      _buildAtivacaoCard(),
                      const SizedBox(height: 12),
                      _buildModeloCard(),
                      const SizedBox(height: 12),
                      _buildOrigemLocalDataCard(),
                      const SizedBox(height: 12),
                      _buildAssinaturasCard(),
                    ],
                  ),
                ),
                _buildFooter(primary, onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color primary, Color onPrimary) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.card_membership_rounded,
              color: onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações do certificado',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Defina modelo, assinaturas e origem de local/data.',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.80),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: onPrimary),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildAtivacaoCard() {
    final t = context.uai;
    final accent = _ensureVisible(_ativo ? t.success : t.warning, t.card);

    return _dialogSection(
      icon: _ativo ? Icons.check_circle_rounded : Icons.block_rounded,
      title: 'Status do certificado',
      subtitle: _ativo
          ? 'As configurações serão salvas junto com o evento.'
          : 'O evento ficará sem configuração personalizada de certificado.',
      color: accent,
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _ativo,
          activeColor: accent,
          onChanged: (value) => setState(() => _ativo = value),
          title: Text(
            _ativo ? 'Certificados ativos' : 'Certificados desativados',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            'Esse controle acompanha o botão principal de certificados do evento.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeloCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.view_quilt_rounded,
      title: 'Modelo do certificado',
      subtitle: 'O recomendado é deixar automático pela graduação.',
      color: t.info,
      child: Column(
        children: _modelos.map((modelo) {
          final selected = _modeloPadrao == modelo.id;
          final accent = _ensureVisible(selected ? t.primary : t.textSecondary, t.card);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: selected
                  ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
                  : t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _modeloPadrao = modelo.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    border: Border.all(
                      color: selected ? accent.withOpacity(0.28) : t.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(modelo.icon, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelo.title,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              modelo.subtitle,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11.6,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrigemLocalDataCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.location_on_rounded,
      title: 'Local e data',
      subtitle: 'O certificado usa cidade e data cadastradas no evento.',
      color: t.warning,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _usarCidadeDoEvento,
              activeColor: _ensureVisible(t.primary, t.card),
              onChanged: (value) {
                setState(() => _usarCidadeDoEvento = value ?? true);
              },
              title: Text(
                'Usar cidade do evento',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Ex.: BOCAIUVA-MG',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _usarDataDoEvento,
              activeColor: _ensureVisible(t.primary, t.card),
              onChanged: (value) {
                setState(() => _usarDataDoEvento = value ?? true);
              },
              title: Text(
                'Usar data do evento',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                'Ex.: 20 DE JUNHO DE 2026',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssinaturasCard() {
    final t = context.uai;

    return _dialogSection(
      icon: Icons.draw_rounded,
      title: 'Assinaturas',
      subtitle: 'Configure até 5 nomes e apelidos/cargos.',
      color: t.associacao,
      child: Column(
        children: List.generate(5, (index) {
          return _assinaturaFields(index);
        }),
      ),
    );
  }

  Widget _assinaturaFields(int index) {
    final t = context.uai;
    final number = index + 1;

    return Container(
      margin: EdgeInsets.only(bottom: index == 4 ? 0 : 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final nome = TextFormField(
            controller: _nomeControllers[index],
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: t.textPrimary),
            decoration: _inputDecoration(
              label: 'Nome assinatura $number',
              icon: Icons.person_rounded,
              hint: 'Ex.: JOÃO LUCAS SILVA RABELO',
            ),
          );

          final apelido = TextFormField(
            controller: _apelidoControllers[index],
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: t.textPrimary),
            decoration: _inputDecoration(
              label: 'Apelido/Cargo $number',
              icon: Icons.workspace_premium_rounded,
              hint: 'Ex.: PROFESSOR TICO-TICO',
            ),
          );

          if (narrow) {
            return Column(
              children: [
                nome,
                const SizedBox(height: 10),
                apelido,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: nome),
              const SizedBox(width: 10),
              Expanded(child: apelido),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.14)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11.7,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _buildFooter(Color primary, Color onPrimary) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textPrimary,
                side: BorderSide(color: t.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text(
                'CANCELAR',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_rounded),
              label: const Text('SALVAR CONFIG.'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeloCertificadoOption {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const _ModeloCertificadoOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
