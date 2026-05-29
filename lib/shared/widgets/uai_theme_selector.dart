import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';

class UaiThemeIconButton extends StatelessWidget {
  const UaiThemeIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Escolher tema',
      child: Material(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () => showUaiThemeSelector(context),
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: const Icon(
              Icons.palette_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class UaiThemeSelectorButton extends StatelessWidget {
  final bool compact;

  const UaiThemeSelectorButton({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final controller = AppThemeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final activeName = controller.activeSavedThemeId == null
            ? controller.currentPreset.label
            : 'Tema salvo ativo';

        return Material(
          color: tokens.card,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          child: InkWell(
            onTap: () => showUaiThemeSelector(context),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            child: Container(
              padding: EdgeInsets.all(compact ? 12 : 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.cardRadius),
                border: Border.all(color: tokens.border),
                boxShadow: tokens.softShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 38 : 46,
                    height: compact ? 38 : 46,
                    decoration: BoxDecoration(
                      gradient: tokens.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.palette_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      activeName,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: tokens.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showUaiThemeSelector(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _UaiThemeSelectorSheet(),
  );
}

class _UaiThemeSelectorSheet extends StatefulWidget {
  const _UaiThemeSelectorSheet();

  @override
  State<_UaiThemeSelectorSheet> createState() => _UaiThemeSelectorSheetState();
}

class _UaiThemeSelectorSheetState extends State<_UaiThemeSelectorSheet> {
  late Future<List<SavedUserTheme>> _savedThemesFuture;

  @override
  void initState() {
    super.initState();
    _reloadSavedThemes();
  }

  void _reloadSavedThemes() {
    _savedThemesFuture = AppThemeController.instance.loadSavedUserThemes();
  }

  Future<void> _refresh() async {
    setState(_reloadSavedThemes);
    await _savedThemesFuture;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final controller = AppThemeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: tokens.border),
            boxShadow: tokens.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: tokens.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: tokens.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.palette_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Escolher tema',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar temas salvos',
                    onPressed: _refresh,
                    icon: Icon(Icons.refresh_rounded, color: tokens.textSecondary),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: tokens.primary,
                  backgroundColor: tokens.surface,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _SectionTitle(
                        title: 'Temas do sistema',
                        icon: Icons.auto_awesome_rounded,
                      ),
                      const SizedBox(height: 8),
                      for (final preset in UaiThemePreset.values) ...[
                        _PresetTile(
                          preset: preset,
                          selected: preset == controller.currentPreset &&
                              (preset != UaiThemePreset.usuarioPersonalizado ||
                                  controller.activeSavedThemeId == null),
                          onTap: () async {
                            if (preset == UaiThemePreset.usuarioPersonalizado) {
                              await controller.apply(
                                preset: UaiThemePreset.usuarioPersonalizado,
                                mode: ThemeMode.light,
                              );
                              if (context.mounted) {
                                await showUaiUserThemeEditor(context);
                                await _refresh();
                              }
                              return;
                            }

                            await controller.apply(
                              preset: preset,
                              mode: ThemeMode.light,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                      _SectionTitle(
                        title: 'Meus temas salvos na nuvem',
                        icon: Icons.cloud_done_rounded,
                        trailing: TextButton.icon(
                          onPressed: () async {
                            await showUaiUserThemeEditor(context);
                            if (mounted) await _refresh();
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Novo'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<SavedUserTheme>>(
                        future: _savedThemesFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Padding(
                              padding: const EdgeInsets.all(18),
                              child: Center(
                                child: CircularProgressIndicator(color: tokens.primary),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return _InfoCard(
                              icon: Icons.cloud_off_rounded,
                              title: 'Não foi possível carregar temas',
                              subtitle: snapshot.error.toString(),
                            );
                          }

                          final themes = snapshot.data ?? [];

                          if (themes.isEmpty) {
                            return const _InfoCard(
                              icon: Icons.palette_outlined,
                              title: 'Nenhum tema salvo ainda',
                              subtitle: 'Crie um tema e toque em “Salvar na nuvem”.',
                            );
                          }

                          return Column(
                            children: [
                              for (final theme in themes) ...[
                                _SavedThemeTile(
                                  theme: theme,
                                  selected: controller.activeSavedThemeId == theme.id,
                                  onApply: () async {
                                    await controller.applySavedUserTheme(theme);
                                  },
                                  onEdit: () async {
                                    await showUaiUserThemeEditor(
                                      context,
                                      savedTheme: theme,
                                    );
                                    if (mounted) await _refresh();
                                  },
                                  onDelete: () async {
                                    final ok = await _confirmDelete(context, theme);
                                    if (ok != true) return;

                                    await controller.deleteSavedUserTheme(theme.id);
                                    if (mounted) await _refresh();
                                  },
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, SavedUserTheme theme) {
    final tokens = context.uai;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Excluir tema?',
          style: TextStyle(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'O tema “${theme.name}” será removido da sua conta.',
          style: TextStyle(color: tokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionTitle({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;

    return Row(
      children: [
        Icon(icon, color: tokens.primary, size: 19),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: tokens.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final UaiThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;

    return Material(
      color: selected ? tokens.primary.withOpacity(0.12) : tokens.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? tokens.primary.withOpacity(0.55) : tokens.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: preset.previewColor,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: preset.previewColor.withOpacity(0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  preset.icon,
                  color: _readableOn(preset.previewColor),
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.description,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (preset == UaiThemePreset.usuarioPersonalizado)
                IconButton(
                  tooltip: 'Configurar',
                  onPressed: () => showUaiUserThemeEditor(context),
                  icon: Icon(Icons.tune_rounded, color: tokens.primary),
                )
              else if (selected)
                Icon(Icons.check_circle_rounded, color: tokens.primary)
              else
                Icon(Icons.circle_outlined, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedThemeTile extends StatelessWidget {
  final SavedUserTheme theme;
  final bool selected;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SavedThemeTile({
    required this.theme,
    required this.selected,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final preview = theme.settings.toTokens();

    return Material(
      color: selected ? tokens.primary.withOpacity(0.12) : tokens.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onApply,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? tokens.primary.withOpacity(0.55) : tokens.border,
            ),
          ),
          child: Row(
            children: [
              _ThemePreviewDots(tokens: preview),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.name,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? 'Ativo neste dispositivo' : 'Toque para usar este tema',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: onEdit,
                icon: Icon(Icons.edit_rounded, color: tokens.info),
              ),
              IconButton(
                tooltip: 'Excluir',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: tokens.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewDots extends StatelessWidget {
  final UaiThemeTokens tokens;

  const _ThemePreviewDots({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 42,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tokens.border),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: _dot(tokens.primary, 19),
          ),
          Positioned(
            right: 0,
            top: 3,
            child: _dot(tokens.card, 22),
          ),
          Positioned(
            left: 11,
            bottom: 0,
            child: _dot(tokens.accent, 17),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
    );
  }
}

Future<void> showUaiUserThemeEditor(
    BuildContext context, {
      SavedUserTheme? savedTheme,
    }) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _UserThemeEditorDialog(savedTheme: savedTheme),
  );
}

class _UserThemeEditorDialog extends StatefulWidget {
  final SavedUserTheme? savedTheme;

  const _UserThemeEditorDialog({this.savedTheme});

  @override
  State<_UserThemeEditorDialog> createState() => _UserThemeEditorDialogState();
}

class _UserThemeEditorDialogState extends State<_UserThemeEditorDialog> {
  late TextEditingController _nameController;
  late TextEditingController _primaryController;
  late TextEditingController _backgroundController;
  late TextEditingController _surfaceController;
  late TextEditingController _cardController;
  late TextEditingController _textController;
  late TextEditingController _accentController;

  late double _cardRadius;
  late double _buttonRadius;
  late String _fontFamily;
  bool _savingCloud = false;

  @override
  void initState() {
    super.initState();

    final initialSettings =
        widget.savedTheme?.settings ?? AppThemeController.instance.userTheme;

    _nameController = TextEditingController(
      text: widget.savedTheme?.name ?? '',
    );
    _primaryController = TextEditingController(text: _hex(initialSettings.primary));
    _backgroundController = TextEditingController(text: _hex(initialSettings.background));
    _surfaceController = TextEditingController(text: _hex(initialSettings.surface));
    _cardController = TextEditingController(text: _hex(initialSettings.card));
    _textController = TextEditingController(text: _hex(initialSettings.textPrimary));
    _accentController = TextEditingController(
      text: _hex(initialSettings.accent ?? initialSettings.primary),
    );

    _cardRadius = initialSettings.cardRadius;
    _buttonRadius = initialSettings.buttonRadius;
    _fontFamily = initialSettings.fontFamily ?? 'default';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _primaryController.dispose();
    _backgroundController.dispose();
    _surfaceController.dispose();
    _cardController.dispose();
    _textController.dispose();
    _accentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final preview = _settingsFromFields().toTokens();

    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: tokens.border),
            boxShadow: tokens.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: tokens.primaryGradient),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.savedTheme == null
                              ? 'Tema do Usuário'
                              : 'Editar tema salvo',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _previewCard(preview),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do tema salvo',
                            hintText: 'Ex: Verde Duende, Café Premium...',
                            prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _colorField('Cor principal', _primaryController),
                        _colorField('Fundo geral', _backgroundController),
                        _colorField('Surface / painéis', _surfaceController),
                        _colorField('Cards', _cardController),
                        _colorField('Texto principal', _textController),
                        _colorField('Accent / destaque extra', _accentController),
                        const SizedBox(height: 10),
                        _radiusSlider(
                          label: 'Arredondamento dos cards',
                          value: _cardRadius,
                          min: 8,
                          max: 32,
                          onChanged: (v) => setState(() => _cardRadius = v),
                        ),
                        _radiusSlider(
                          label: 'Arredondamento dos botões',
                          value: _buttonRadius,
                          min: 8,
                          max: 28,
                          onChanged: (v) => setState(() => _buttonRadius = v),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _fontFamily,
                          dropdownColor: tokens.surface,
                          decoration: const InputDecoration(
                            labelText: 'Fonte',
                            prefixIcon: Icon(Icons.font_download_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'default', child: Text('Padrão')),
                            DropdownMenuItem(value: 'monospace', child: Text('Robótica / monospace')),
                            DropdownMenuItem(value: 'serif', child: Text('Serifada')),
                            DropdownMenuItem(value: 'sans-serif', child: Text('Sans-serif')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _fontFamily = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        _contrastWarning(preview),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.card,
                    border: Border(top: BorderSide(color: tokens.border)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 520;

                      final reset = OutlinedButton.icon(
                        onPressed: _savingCloud
                            ? null
                            : () async {
                          await AppThemeController.instance.resetUserTheme();
                          if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Resetar'),
                      );

                      final local = OutlinedButton.icon(
                        onPressed: _savingCloud
                            ? null
                            : () async {
                          await AppThemeController.instance.applyUserTheme(
                            _settingsFromFields(),
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.phone_android_rounded),
                        label: const Text('Só neste aparelho'),
                      );

                      final cloud = ElevatedButton.icon(
                        onPressed: _savingCloud ? null : _saveCloud,
                        icon: _savingCloud
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          widget.savedTheme == null
                              ? 'Salvar na nuvem'
                              : 'Atualizar na nuvem',
                        ),
                      );

                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            reset,
                            const SizedBox(height: 8),
                            local,
                            const SizedBox(height: 8),
                            cloud,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: reset),
                          const SizedBox(width: 8),
                          Expanded(child: local),
                          const SizedBox(width: 8),
                          Expanded(child: cloud),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCloud() async {
    final tokens = context.uai;
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showSnack('Dê um nome para salvar esse tema.', tokens.warning);
      return;
    }

    setState(() => _savingCloud = true);

    try {
      await AppThemeController.instance.saveUserThemeToFirebase(
        name: name,
        settings: _settingsFromFields(),
        themeId: widget.savedTheme?.id,
        activateAfterSave: true,
      );

      if (!mounted) return;
      _showSnack('Tema salvo na nuvem e aplicado!', tokens.success);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao salvar tema: $e', tokens.error);
    } finally {
      if (mounted) setState(() => _savingCloud = false);
    }
  }

  void _showSnack(String message, Color color) {
    final onColor = _readableOn(color);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: TextStyle(
            color: onColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _previewCard(UaiThemeTokens preview) {
    final onPrimary = _readableOn(preview.primary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: preview.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: preview.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: preview.primaryGradient,
              borderRadius: BorderRadius.circular(preview.cardRadius),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_rounded, color: onPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prévia do tema',
                    style: TextStyle(
                      color: onPrimary,
                      fontWeight: FontWeight.w900,
                      fontFamily: preview.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: preview.card,
              borderRadius: BorderRadius.circular(preview.cardRadius),
              border: Border.all(color: preview.border),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: preview.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Texto legível em card personalizado',
                    style: TextStyle(
                      color: preview.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontFamily: preview.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorField(String label, TextEditingController controller) {
    final tokens = context.uai;
    final color = _parseColor(controller.text) ?? tokens.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.inputRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.inputRadius),
          onTap: () async {
            final selected = await showDialog<Color>(
              context: context,
              builder: (_) => _UaiColorPickerDialog(
                title: label,
                initialColor: color,
              ),
            );

            if (selected == null) return;

            controller.text = _hex(selected);
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.inputRadius),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tokens.border),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.26),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _hex(color),
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.color_lens_rounded, color: tokens.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _radiusSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final tokens = context.uai;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.round()}',
          style: TextStyle(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _contrastWarning(UaiThemeTokens preview) {
    final diff = (preview.textPrimary.computeLuminance() -
        preview.card.computeLuminance())
        .abs();

    final ok = diff >= 0.34;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? preview.success.withOpacity(0.12)
            : preview.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ok
              ? preview.success.withOpacity(0.28)
              : preview.error.withOpacity(0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: ok ? preview.success : preview.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? 'Contraste bom: os textos devem ficar legíveis.'
                  : 'Atenção: texto e card estão próximos. O sistema tentará corrigir ao salvar.',
              style: TextStyle(
                color: preview.textPrimary,
                fontWeight: FontWeight.w700,
                fontFamily: preview.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  UserThemeSettings _settingsFromFields() {
    return UserThemeSettings(
      primary: _parseColor(_primaryController.text) ?? UserThemeSettings.defaultDark.primary,
      background: _parseColor(_backgroundController.text) ?? UserThemeSettings.defaultDark.background,
      surface: _parseColor(_surfaceController.text) ?? UserThemeSettings.defaultDark.surface,
      card: _parseColor(_cardController.text) ?? UserThemeSettings.defaultDark.card,
      textPrimary: _parseColor(_textController.text) ?? UserThemeSettings.defaultDark.textPrimary,
      accent: _parseColor(_accentController.text) ?? UserThemeSettings.defaultDark.accent,
      cardRadius: _cardRadius,
      buttonRadius: _buttonRadius,
      inputRadius: _buttonRadius,
      fontFamily: _fontFamily == 'default' ? null : _fontFamily,
    );
  }

  String _hex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Color? _parseColor(String raw) {
    var value = raw.trim().replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return null;

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;

    return Color(parsed);
  }
}

class _UaiColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;

  const _UaiColorPickerDialog({
    required this.title,
    required this.initialColor,
  });

  @override
  State<_UaiColorPickerDialog> createState() => _UaiColorPickerDialogState();
}

class _UaiColorPickerDialogState extends State<_UaiColorPickerDialog> {
  late double _red;
  late double _green;
  late double _blue;

  static const List<Color> _quickColors = [
    Color(0xFFB71C1C),
    Color(0xFFD21F35),
    Color(0xFF39FF14),
    Color(0xFF00FFD1),
    Color(0xFF8B4A24),
    Color(0xFFD9A45F),
    Color(0xFF6D5DF7),
    Color(0xFFBDA0FF),
    Color(0xFF101018),
    Color(0xFF171A24),
    Color(0xFF202232),
    Color(0xFFFFFFFF),
    Color(0xFFF8F8F2),
    Color(0xFF111827),
  ];

  @override
  void initState() {
    super.initState();
    _red = widget.initialColor.red.toDouble();
    _green = widget.initialColor.green.toDouble();
    _blue = widget.initialColor.blue.toDouble();
  }

  Color get _color => Color.fromARGB(
    255,
    _red.round(),
    _green.round(),
    _blue.round(),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.uai;
    final color = _color;
    final textOnColor = _readableOn(color);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: tokens.border),
            boxShadow: tokens.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withOpacity(0.68),
                        color,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.color_lens_rounded, color: textOnColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            color: textOnColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: textOnColor),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          height: 96,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: tokens.border),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.28),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _hex(color),
                            style: TextStyle(
                              color: textOnColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Cores rápidas',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: [
                            for (final quickColor in _quickColors)
                              _quickColorButton(quickColor),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _slider(
                          label: 'Vermelho',
                          value: _red,
                          color: const Color(0xFFE53935),
                          onChanged: (value) => setState(() => _red = value),
                        ),
                        _slider(
                          label: 'Verde',
                          value: _green,
                          color: const Color(0xFF43A047),
                          onChanged: (value) => setState(() => _green = value),
                        ),
                        _slider(
                          label: 'Azul',
                          value: _blue,
                          color: const Color(0xFF1E88E5),
                          onChanged: (value) => setState(() => _blue = value),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.card,
                    border: Border(top: BorderSide(color: tokens.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, color),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Usar cor'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickColorButton(Color color) {
    final selected = color.value == _color.value;
    final tokens = context.uai;

    return InkWell(
      onTap: () {
        setState(() {
          _red = color.red.toDouble();
          _green = color.green.toDouble();
          _blue = color.blue.toDouble();
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? tokens.textPrimary : tokens.border,
            width: selected ? 3 : 1,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ]
              : null,
        ),
        child: selected
            ? Icon(
          Icons.check_rounded,
          color: _readableOn(color),
        )
            : null,
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final tokens = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              divisions: 255,
              activeColor: color,
              label: value.round().toString(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.end,
              style: TextStyle(
                color: tokens.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}
