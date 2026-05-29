import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  String? _photoUrl;
  XFile? _pickedImage;

  String? _email;
  String? _tipo;
  String? _statusConta;
  Timestamp? _dataCadastro;
  Timestamp? _ultimaAtualizacao;

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

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _contatoController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_user.uid)
          .get();

      final data = doc.data();
      if (data != null) {
        _nomeController.text = data['nome_completo'] ?? '';
        _contatoController.text = data['contato'] ?? '';
        _photoUrl = data['foto_url'] as String?;

        _email = data['email'] as String?;
        _tipo = data['tipo'] as String?;
        _statusConta = data['status_conta'] as String?;
        _dataCadastro = data['data_cadastro'] as Timestamp?;
        _ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final image =
    await ImagePicker().pickImage(source: source, imageQuality: 50);
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.uai.card,
      barrierColor: Colors.black.withOpacity(0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.uai.cardRadius),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.uai.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              _bottomSheetTile(
                icon: Icons.photo_library_rounded,
                title: 'Escolher da galeria',
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
              _bottomSheetTile(
                icon: Icons.camera_alt_rounded,
                title: 'Tirar foto com a câmera',
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomSheetTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return Material(
      color: context.uai.cardAlt,
      borderRadius: BorderRadius.circular(context.uai.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _onCard(),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.uai.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    String? newPhotoUrl;

    try {
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${_user.uid}.jpg');

        if (kIsWeb) {
          final bytes = await _pickedImage!.readAsBytes();
          await ref.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
        } else {
          await ref.putFile(File(_pickedImage!.path));
        }

        newPhotoUrl = await ref.getDownloadURL();
      }

      final updateData = {
        'nome_completo': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        if (newPhotoUrl != null) 'foto_url': newPhotoUrl,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_user.uid)
          .update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Perfil atualizado com sucesso!',
              style: TextStyle(
                color: _readableOn(context.uai.success),
                fontWeight: FontWeight.w800,
              ),
            ),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar perfil: ${e.toString()}',
              style: TextStyle(
                color: _readableOn(context.uai.error),
                fontWeight: FontWeight.w800,
              ),
            ),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoField(String label, String value, {IconData? icon}) {
    final accent = _ensureVisible(context.uai.info, context.uai.card);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 13, horizontal: 15),
      decoration: BoxDecoration(
        color: context.uai.cardAlt,
        border: Border.all(color: context.uai.border),
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withOpacity(0.16)),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : 'Não informado',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: _onCard(),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Não disponível';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.uai.textSecondary),
      prefixIcon: Icon(icon, color: accent),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      filled: true,
      fillColor: context.uai.cardAlt,
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _onCard(),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _onCardMuted(),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final accent = _ensureVisible(context.uai.primary, context.uai.background);

    return Center(
      child: Stack(
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withOpacity(0.30), width: 3),
              boxShadow: context.uai.cardShadow,
            ),
            child: ClipOval(
              child: _pickedImage != null
                  ? kIsWeb
                  ? Image.network(
                _pickedImage!.path,
                fit: BoxFit.cover,
                width: 168,
                height: 168,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person_rounded,
                  size: 82,
                  color: context.uai.textMuted,
                ),
              )
                  : Image.file(
                File(_pickedImage!.path),
                fit: BoxFit.cover,
                width: 168,
                height: 168,
              )
                  : (_photoUrl != null && _photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: _photoUrl!,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(color: accent),
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.person_rounded,
                  size: 82,
                  color: context.uai.textMuted,
                ),
                fit: BoxFit.cover,
                width: 168,
                height: 168,
              )
                  : Container(
                color: context.uai.cardAlt,
                child: Icon(
                  Icons.person_rounded,
                  size: 82,
                  color: context.uai.textMuted,
                ),
              )),
            ),
          ),
          Positioned(
            bottom: 5,
            right: 5,
            child: Container(
              decoration: BoxDecoration(
                color: context.uai.primary,
                shape: BoxShape.circle,
                border: Border.all(color: context.uai.background, width: 3),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.camera_alt_rounded,
                  color: _readableOn(context.uai.primary),
                ),
                onPressed: _showImageSourceActionSheet,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text(
          'Configurações de Perfil',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(Icons.save_rounded),
              onPressed: _saveProfile,
              tooltip: 'Salvar alterações',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.uai.primary))
          : SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAvatar(),
                SizedBox(height: 22),
                _sectionCard(
                  title: 'Informações editáveis',
                  subtitle: 'Atualize seus dados principais',
                  icon: Icons.edit_rounded,
                  color: context.uai.primary,
                  child: Column(
                    children: [
                      TextField(
                        controller: _nomeController,
                        style: TextStyle(color: context.uai.textPrimary),
                        decoration: _inputDecoration(
                          label: 'Nome completo *',
                          icon: Icons.person_rounded,
                        ),
                      ),
                      SizedBox(height: 14),
                      TextField(
                        controller: _contatoController,
                        style: TextStyle(color: context.uai.textPrimary),
                        decoration: _inputDecoration(
                          label: 'Contato (telefone) *',
                          icon: Icons.phone_rounded,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                _sectionCard(
                  title: 'Informações do sistema',
                  subtitle: 'Dados protegidos do seu acesso',
                  icon: Icons.security_rounded,
                  color: context.uai.info,
                  child: Column(
                    children: [
                      _buildInfoField(
                        'E-mail',
                        _email ?? '',
                        icon: Icons.email_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoField(
                        'Tipo de usuário',
                        _tipo ?? '',
                        icon: Icons.group_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoField(
                        'Status da conta',
                        _statusConta ?? '',
                        icon: Icons.verified_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoField(
                        'Data de cadastro',
                        _formatTimestamp(_dataCadastro),
                        icon: Icons.calendar_today_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoField(
                        'Última atualização',
                        _formatTimestamp(_ultimaAtualizacao),
                        icon: Icons.update_rounded,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: Icon(Icons.save_rounded),
                  label: Text('SALVAR ALTERAÇÕES'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.uai.primary,
                    foregroundColor: _readableOn(context.uai.primary),
                    minimumSize: const Size(double.infinity, 52),
                    textStyle: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(context.uai.buttonRadius),
                    ),
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