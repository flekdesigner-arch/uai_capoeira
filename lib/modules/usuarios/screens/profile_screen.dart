import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uai_capoeira/core/preferences/user_preferences_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_controller.dart';
import 'package:uai_capoeira/core/theme/app_theme_preset.dart';
import 'package:uai_capoeira/core/services/update_wifi_service.dart';
import 'package:uai_capoeira/shared/widgets/update_wifi_preference_tile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nomeController = TextEditingController();
  final _contatoController = TextEditingController();
  final _user = FirebaseAuth.instance.currentUser!;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _photoUrl;
  XFile? _pickedImage;
  String? _email;
  String? _tipo;
  String? _statusConta;
  Timestamp? _dataCadastro;
  Timestamp? _ultimaAtualizacao;
  String _appVersion = '';

  UserSearchDefaultFilter _searchDefaultFilter = UserSearchDefaultFilter.todos;
  bool _searchResponsavelEnabled = true;
  bool _searchTelefoneEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _contatoController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait<dynamic>([
        FirebaseFirestore.instance.collection('usuarios').doc(_user.uid).get(),
        PackageInfo.fromPlatform(),
        UserPreferencesService.instance.getSearchDefaultFilter(),
        UserPreferencesService.instance.getSearchResponsavelEnabled(),
        UserPreferencesService.instance.getSearchTelefoneEnabled(),
      ]);

      final doc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final packageInfo = results[1] as PackageInfo;
      final data = doc.data();

      if (data != null) {
        _nomeController.text = data['nome_completo']?.toString() ?? '';
        _contatoController.text = data['contato']?.toString() ?? '';
        _photoUrl = data['foto_url']?.toString();
        _email = data['email']?.toString();
        _tipo = data['tipo']?.toString();
        _statusConta = data['status_conta']?.toString();
        _dataCadastro = data['data_cadastro'] as Timestamp?;
        _ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;
      }

      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      _searchDefaultFilter = results[2] as UserSearchDefaultFilter;
      _searchResponsavelEnabled = results[3] as bool;
      _searchTelefoneEnabled = results[4] as bool;
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : Colors.white;

  Color _visibleAccent(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.24) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(background.computeLuminance() < 0.45 ? 0.72 : 0.34)
        .toColor();
  }

  String get _displayName {
    final value = _nomeController.text.trim();
    return value.isEmpty ? (_user.displayName ?? 'Usuário UAI Capoeira') : value;
  }

  String get _displayEmail => (_email?.trim().isNotEmpty == true)
      ? _email!.trim()
      : (_user.email ?? 'E-mail não informado');

  bool get _accountActive {
    final normalized = (_statusConta ?? '').toLowerCase().trim();
    return normalized == 'ativa' || normalized == 'ativo' || normalized == 'active';
  }

  String get _roleLabel {
    final raw = (_tipo ?? '').trim();
    if (raw.isEmpty) return 'Usuário';
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Não disponível';
    final date = timestamp.toDate();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source, imageQuality: 68);
    if (image != null && mounted) setState(() => _pickedImage = image);
  }

  Future<void> _chooseImageSource() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.uai.card,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Atualizar foto',
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              _sheetAction(
                icon: Icons.photo_library_rounded,
                title: 'Escolher da galeria',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
              _sheetAction(
                icon: Icons.camera_alt_rounded,
                title: 'Tirar uma foto',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.buttonRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: t.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile({bool closeEditor = false}) async {
    if (_nomeController.text.trim().isEmpty) {
      _showMessage('Informe seu nome completo.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? newPhotoUrl;
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${_user.uid}.jpg');
        if (kIsWeb) {
          final bytes = await _pickedImage!.readAsBytes();
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(_pickedImage!.path));
        }
        newPhotoUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(_user.uid).update({
        'nome_completo': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        'foto_url': ?newPhotoUrl,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (newPhotoUrl != null) _photoUrl = newPhotoUrl;
      _pickedImage = null;
      _ultimaAtualizacao = Timestamp.now();
      if (!mounted) return;
      setState(() {});
      if (closeEditor && Navigator.of(context).canPop()) Navigator.of(context).pop();
      _showMessage('Perfil atualizado com sucesso.');
    } catch (e) {
      if (mounted) _showMessage('Erro ao atualizar perfil: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final color = isError ? context.uai.error : context.uai.success;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: _readableOn(color),
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

  Future<void> _showEditProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.uai.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (sheetContext) {
        final t = context.uai;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            2,
            18,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Editar dados pessoais',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Atualize as informações usadas no aplicativo.',
                  style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _nomeController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contatoController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contato / telefone',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _chooseImageSource,
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('ALTERAR FOTO'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          Navigator.pop(sheetContext);
                          await _saveProfile();
                        },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('SALVAR ALTERAÇÕES'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showThemePicker() async {
    final controller = AppThemeController.instance;
    final allowed = controller.allowedSystemPresets;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final t = context.uai;
            final forced = controller.isGlobalThemeForced;
            final canChoose = controller.allowsUserThemeChoice && !forced;

            return SafeArea(
              top: false,
              child: Material(
                color: t.surface,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(t.cardRadius),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .82,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Aparência e tema',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              forced
                                  ? 'O tema está definido pela administração.'
                                  : canChoose
                                      ? 'Escolha entre os temas liberados para seu usuário.'
                                      : 'A escolha de tema está desativada pela administração.',
                              style: TextStyle(
                                color: t.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          shrinkWrap: true,
                          itemCount: allowed.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 9),
                          itemBuilder: (context, index) {
                            final preset = allowed[index];
                            final selected =
                                controller.effectivePreset == preset &&
                                controller.activeThemeSource ==
                                    ActiveThemeSource.official;
                            final preview = AppTheme.tokensFor(preset);

                            return Material(
                              color: t.card,
                              borderRadius: BorderRadius.circular(18),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: canChoose
                                    ? () async {
                                        await controller.setPreset(preset);
                                        if (context.mounted) {
                                          setLocalState(() {});
                                        }
                                        if (mounted) {
                                          setState(() {});
                                        }
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: selected ? t.primary : t.border,
                                      width: selected ? 1.6 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: preview.background,
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(
                                            color: preview.border,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: Container(
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: preview.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Container(
                                                height: 18,
                                                decoration: BoxDecoration(
                                                  color: preview.card,
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              preset.label,
                                              style: TextStyle(
                                                color: t.textPrimary,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              preset.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: t.textMuted,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (selected)
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: t.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: _readableOn(t.primary),
                                          ),
                                        )
                                      else
                                        Icon(
                                          forced
                                              ? Icons.lock_rounded
                                              : Icons.chevron_right_rounded,
                                          color: t.textMuted,
                                        ),
                                    ],
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
      },
    );
  }

  Future<void> _showSearchPreferences() async {
    var filter = _searchDefaultFilter;
    var responsavel = _searchResponsavelEnabled;
    var telefone = _searchTelefoneEnabled;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.uai.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(context.uai.cardRadius)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final t = context.uai;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pesquisa de alunos', style: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Defina como a Busca deve começar e quais campos secundários ela usa.', style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  Text('Filtro inicial', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: UserSearchDefaultFilter.values.map((item) {
                      final selected = filter == item;
                      return ChoiceChip(
                        selected: selected,
                        showCheckmark: false,
                        label: Text(item.label),
                        onSelected: (_) => setLocalState(() => filter = item),
                        avatar: selected ? const Icon(Icons.check_rounded, size: 17) : null,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _preferenceSwitch(
                    title: 'Pesquisar responsáveis',
                    subtitle: 'Encontra alunos pelo nome do pai, mãe ou responsável.',
                    icon: Icons.family_restroom_rounded,
                    value: responsavel,
                    onChanged: (value) => setLocalState(() => responsavel = value),
                  ),
                  const SizedBox(height: 8),
                  _preferenceSwitch(
                    title: 'Pesquisar telefones',
                    subtitle: 'Permite localizar usando qualquer trecho do número.',
                    icon: Icons.phone_in_talk_rounded,
                    value: telefone,
                    onChanged: (value) => setLocalState(() => telefone = value),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prefs = UserPreferencesService.instance;
                      await prefs.setSearchDefaultFilter(filter);
                      await prefs.setSearchResponsavelEnabled(responsavel);
                      await prefs.setSearchTelefoneEnabled(telefone);
                      if (!mounted) return;
                      setState(() {
                        _searchDefaultFilter = filter;
                        _searchResponsavelEnabled = responsavel;
                        _searchTelefoneEnabled = telefone;
                      });
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      _showMessage('Preferências de pesquisa salvas.');
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('SALVAR PREFERÊNCIAS'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _preferenceSwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _visibleAccent(t.primary, t.card), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => null,
                  _ => t.primary,
                },
                activeTrackColor: switch (Theme.of(context).platform) {
                  TargetPlatform.iOS || TargetPlatform.macOS => t.primary,
                  _ => null,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountInfo() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.uai.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(context.uai.cardRadius)),
      ),
      builder: (sheetContext) {
        final t = context.uai;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Conta e acesso', style: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Informações protegidas do seu acesso ao UAI Capoeira.', style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                _systemInfo(Icons.email_rounded, 'E-mail', _displayEmail),
                _systemInfo(Icons.admin_panel_settings_rounded, 'Tipo de usuário', _roleLabel),
                _systemInfo(Icons.verified_user_rounded, 'Status da conta', _statusConta ?? 'Não informado'),
                _systemInfo(Icons.calendar_today_rounded, 'Data de cadastro', _formatTimestamp(_dataCadastro)),
                _systemInfo(Icons.update_rounded, 'Última atualização', _formatTimestamp(_ultimaAtualizacao)),
                _systemInfo(Icons.fingerprint_rounded, 'ID do usuário', _user.uid),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _systemInfo(IconData icon, String label, String value) {
    final t = context.uai;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: t.info.withAlpha(28), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _visibleAccent(t.info, t.card), size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: t.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                SelectableText(value, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Você precisará entrar novamente para acessar o aplicativo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('SAIR')),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _avatar({double size = 108}) {
    final t = context.uai;
    Widget image;
    if (_pickedImage != null) {
      image = kIsWeb
          ? Image.network(_pickedImage!.path, fit: BoxFit.cover)
          : Image.file(File(_pickedImage!.path), fit: BoxFit.cover);
    } else if (_photoUrl?.trim().isNotEmpty == true) {
      image = CachedNetworkImage(
        imageUrl: _photoUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => Center(child: CircularProgressIndicator(color: t.primary, strokeWidth: 2)),
        errorWidget: (_, _, _) => Icon(Icons.person_rounded, size: size * .55, color: t.textMuted),
      );
    } else {
      image = Icon(Icons.person_rounded, size: size * .55, color: t.textMuted);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [t.primary, t.accent]),
            boxShadow: t.cardShadow,
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.background),
            child: ClipOval(child: Container(color: t.cardAlt, child: image)),
          ),
        ),
        Positioned(
          right: -2,
          bottom: 2,
          child: Material(
            color: t.primary,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _chooseImageSource,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(Icons.camera_alt_rounded, size: 18, color: _readableOn(t.primary)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCard({required bool compact}) {
    final t = context.uai;
    final statusColor = _accountActive ? t.success : t.warning;
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: compact
          ? Column(
              children: [
                _avatar(size: 112),
                const SizedBox(height: 16),
                _identityBlock(statusColor, centered: true),
                const SizedBox(height: 14),
                OutlinedButton.icon(onPressed: _showEditProfile, icon: const Icon(Icons.edit_rounded), label: const Text('EDITAR PERFIL')),
              ],
            )
          : Row(
              children: [
                _avatar(size: 118),
                const SizedBox(width: 22),
                Expanded(child: _identityBlock(statusColor)),
                const SizedBox(width: 14),
                OutlinedButton.icon(onPressed: _showEditProfile, icon: const Icon(Icons.edit_rounded), label: const Text('Editar perfil')),
              ],
            ),
    );
  }

  Widget _identityBlock(Color statusColor, {bool centered = false}) {
    final t = context.uai;
    return Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          _displayName,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(color: t.textPrimary, fontSize: 21, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          _displayEmail,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(color: t.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 7,
          runSpacing: 7,
          children: [
            _pill(Icons.admin_panel_settings_rounded, _roleLabel, t.primary),
            _pill(Icons.circle, _accountActive ? 'Conta ativa' : (_statusConta ?? 'Status'), statusColor),
          ],
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String label, Color color) {
    final t = context.uai;
    final visible = _visibleAccent(color, t.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: visible.withAlpha(26), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: icon == Icons.circle ? 8 : 14, color: visible),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: visible, fontSize: 10.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 3, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: context.uai.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.05,
        ),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> children) {
    final t = context.uai;
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(children: children),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
    bool showDivider = true,
  }) {
    final t = context.uai;
    final accent = _visibleAccent(color ?? t.primary, t.card);
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(t.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: accent.withAlpha(26), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textMuted, fontSize: 11.3, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: t.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 67),
            child: Divider(height: 1, color: t.border.withAlpha(179)),
          ),
      ],
    );
  }

  String _themeSummary() {
    final controller = AppThemeController.instance;
    if (controller.isGlobalThemeForced) return 'Definido pela administração';
    return controller.effectivePreset.label;
  }

  String _searchSummary() {
    final extras = <String>[];
    if (_searchResponsavelEnabled) extras.add('responsável');
    if (_searchTelefoneEnabled) extras.add('telefone');
    final extra = extras.isEmpty ? '' : ' • ${extras.join(' + ')}';
    return 'Abre em ${_searchDefaultFilter.label}$extra';
  }

  Widget _mainContent({required bool wide}) {
    final preferences = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Preferências'),
        _settingsGroup([
          _settingsTile(
            icon: Icons.palette_rounded,
            title: 'Aparência e tema',
            subtitle: _themeSummary(),
            onTap: _showThemePicker,
          ),
          _settingsTile(
            icon: Icons.manage_search_rounded,
            title: 'Pesquisa de alunos',
            subtitle: _searchSummary(),
            onTap: _showSearchPreferences,
            showDivider: false,
          ),
        ]),
        const SizedBox(height: 18),
        if (UpdateWifiService.instance.isSupported) ...[
          const SizedBox(height: 14),
          _sectionTitle('Atualizações automáticas'),
          const UpdateWifiPreferenceTile(),
          const SizedBox(height: 18),
        ],
        _sectionTitle('Conta'),
        _settingsGroup([
          _settingsTile(
            icon: Icons.person_rounded,
            title: 'Dados pessoais',
            subtitle: 'Nome, telefone e foto do perfil',
            onTap: _showEditProfile,
          ),
          _settingsTile(
            icon: Icons.shield_rounded,
            title: 'Conta e acesso',
            subtitle: '$_roleLabel • ${_accountActive ? 'Ativa' : (_statusConta ?? 'Status')}',
            onTap: _showAccountInfo,
            color: context.uai.info,
            showDivider: false,
          ),
        ]),
      ],
    );

    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('UAI Capoeira'),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(context.uai.cardRadius),
            border: Border.all(color: context.uai.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: context.uai.primary.withAlpha(26), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.sports_martial_arts_rounded, color: context.uai.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('UAI CAPOEIRA', style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(_appVersion.isEmpty ? 'Versão do aplicativo' : 'Versão $_appVersion', style: TextStyle(color: context.uai.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.verified_rounded, color: context.uai.success, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _logout,
          icon: Icon(Icons.logout_rounded, color: context.uai.error),
          label: Text('SAIR DA CONTA', style: TextStyle(color: context.uai.error, fontWeight: FontWeight.w900)),
        ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroCard(compact: true),
          const SizedBox(height: 20),
          preferences,
          const SizedBox(height: 18),
          about,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroCard(compact: false),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: preferences),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: about),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text('Meu perfil', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.uai.primary))
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 850;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 18, wide ? 24 : 14, 34),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: _mainContent(wide: wide),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
