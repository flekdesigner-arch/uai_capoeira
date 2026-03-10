import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  // Campos que não podem ser editados (apenas para exibição)
  String? _email;
  String? _tipo;
  String? _statusConta;
  Timestamp? _dataCadastro;
  Timestamp? _ultimaAtualizacao;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_user.uid)
          .get();

      final data = doc.data();
      if (data != null) {
        // Campos editáveis
        _nomeController.text = data['nome_completo'] ?? '';
        _contatoController.text = data['contato'] ?? '';
        _photoUrl = data['foto_url'] as String?;

        // Campos apenas leitura (para exibição)
        _email = data['email'] as String?;
        _tipo = data['tipo'] as String?;
        _statusConta = data['status_conta'] as String?;
        _dataCadastro = data['data_cadastro'] as Timestamp?;
        _ultimaAtualizacao = data['ultima_atualizacao'] as Timestamp?;
      }
    } catch (e) {
      print('Erro ao carregar dados: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(source: source, imageQuality: 50);
    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da Galeria'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar Foto com a Câmera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    String? newPhotoUrl;

    try {
      // Upload da nova imagem se selecionada
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profile_pictures')
            .child('${_user.uid}.jpg');
        await ref.putFile(File(_pickedImage!.path));
        newPhotoUrl = await ref.getDownloadURL();
      }

      // Preparar dados para atualização
      final updateData = {
        'nome_completo': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        if (newPhotoUrl != null) 'foto_url': newPhotoUrl,
        'ultima_atualizacao': FieldValue.serverTimestamp(), // Atualiza automaticamente
      };

      // Atualizar no Firestore
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_user.uid)
          .update(updateData);

      // Mostrar mensagem de sucesso
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao atualizar perfil: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildInfoField(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.grey.shade600, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : 'Não informado',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações de Perfil'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveProfile,
              tooltip: 'Salvar alterações',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seção da Foto de Perfil
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 80,
                    backgroundColor: Colors.grey.shade300,
                    child: ClipOval(
                      child: _pickedImage != null
                          ? Image.file(
                        File(_pickedImage!.path),
                        fit: BoxFit.cover,
                        width: 160,
                        height: 160,
                      )
                          : (_photoUrl != null && _photoUrl!.isNotEmpty
                          ? CachedNetworkImage(
                        imageUrl: _photoUrl!,
                        placeholder: (context, url) =>
                        const CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                        const Icon(Icons.person, size: 80),
                        fit: BoxFit.cover,
                        width: 160,
                        height: 160,
                      )
                          : const Icon(Icons.person,
                          size: 80, color: Colors.white)),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.red.shade900,
                      child: IconButton(
                        icon:
                        const Icon(Icons.camera_alt, color: Colors.white),
                        onPressed: _showImageSourceActionSheet,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Informações Editáveis',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 20),

            // Campos editáveis
            TextField(
              controller: _nomeController,
              decoration: InputDecoration(
                labelText: 'Nome Completo *',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _contatoController,
              decoration: InputDecoration(
                labelText: 'Contato (Telefone) *',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 40),

            // Informações apenas leitura
            const Text(
              'Informações do Sistema',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 20),

            // Campos não editáveis (SEM NÍVEL DE ACESSO)
            _buildInfoField('E-mail', _email ?? '', icon: Icons.email),
            const SizedBox(height: 15),
            _buildInfoField('Tipo de Usuário', _tipo ?? '', icon: Icons.group),
            const SizedBox(height: 15),
            _buildInfoField('Status da Conta', _statusConta ?? '',
                icon: Icons.verified),
            const SizedBox(height: 15),
            _buildInfoField('Data de Cadastro',
                _formatTimestamp(_dataCadastro), icon: Icons.calendar_today),
            const SizedBox(height: 15),
            _buildInfoField('Última Atualização',
                _formatTimestamp(_ultimaAtualizacao), icon: Icons.update),

            const SizedBox(height: 40),

            // Botão de salvar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'SALVAR ALTERAÇÕES',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}