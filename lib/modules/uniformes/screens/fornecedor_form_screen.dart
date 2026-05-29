import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/uniformes/services/fornecedor_service.dart';

class FornecedorFormScreen extends StatefulWidget {
  final String? fornecedorId;
  final Map<String, dynamic>? fornecedorData;

  const FornecedorFormScreen({super.key, this.fornecedorId, this.fornecedorData});

  @override
  State<FornecedorFormScreen> createState() => _FornecedorFormScreenState();
}

class _FornecedorFormScreenState extends State<FornecedorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final FornecedorService _fornecedorService = FornecedorService();

  final _nomeController = TextEditingController();
  final _contatoController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _observacoesController = TextEditingController();

  bool _isLoading = false;

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  @override
  void initState() {
    super.initState();
    if (widget.fornecedorData != null) {
      _nomeController.text = widget.fornecedorData!['nome'] ?? '';
      _contatoController.text = widget.fornecedorData!['contato'] ?? '';
      _telefoneController.text = widget.fornecedorData!['telefone'] ?? '';
      _emailController.text = widget.fornecedorData!['email'] ?? '';
      _cnpjController.text = widget.fornecedorData!['cnpj'] ?? '';
      _observacoesController.text = widget.fornecedorData!['observacoes'] ?? '';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _contatoController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _cnpjController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> dados = {
        'nome': _nomeController.text.trim(),
        'contato': _contatoController.text.trim(),
        'telefone': _telefoneController.text.trim(),
        'email': _emailController.text.trim(),
        'cnpj': _cnpjController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
      };

      if (widget.fornecedorId == null) {
        await _fornecedorService.criarFornecedor(dados);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Fornecedor cadastrado!',
                style: TextStyle(color: _readableOn(context.uai.success)),
              ),
              backgroundColor: context.uai.success,
            ),
          );
        }
      } else {
        await _fornecedorService.atualizarFornecedor(widget.fornecedorId!, dados);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Fornecedor atualizado!',
                style: TextStyle(color: _readableOn(context.uai.info)),
              ),
              backgroundColor: context.uai.info,
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao salvar fornecedor: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Erro: $e',
              style: TextStyle(color: _readableOn(context.uai.error)),
            ),
            backgroundColor: context.uai.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.uai.primary;
    final onPrimary = _readableOn(primary);
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final textMuted = context.uai.textMuted;
    final border = context.uai.border;
    final cardAlt = context.uai.cardAlt;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          widget.fornecedorId == null ? 'NOVO FORNECEDOR' : 'EDITAR FORNECEDOR',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: onPrimary, strokeWidth: 2),
            )
                : Icon(Icons.save, color: onPrimary),
            label: Text(
              _isLoading ? 'SALVANDO...' : 'SALVAR',
              style: TextStyle(color: onPrimary),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primary))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTextField(
              controller: _nomeController,
              label: 'Nome / Fantasia *',
              icon: Icons.business,
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _contatoController,
              label: 'Contato (pessoa)',
              icon: Icons.person,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _telefoneController,
              label: 'Telefone',
              icon: Icons.phone,
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _emailController,
              label: 'E-mail',
              icon: Icons.email,
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _cnpjController,
              label: 'CNPJ',
              icon: Icons.badge,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _observacoesController,
              label: 'Observações',
              icon: Icons.notes,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _salvar,
              icon: Icon(Icons.save, color: onPrimary),
              label: Text(
                'SALVAR FORNECEDOR',
                style: TextStyle(color: onPrimary),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.uai.buttonRadius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.uai.textSecondary),
        hintStyle: TextStyle(color: context.uai.textMuted),
        prefixIcon: Icon(icon, color: context.uai.primary),
        filled: true,
        fillColor: context.uai.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.inputRadius),
          borderSide: BorderSide(color: context.uai.primary, width: 1.4),
        ),
        alignLabelWithHint: maxLines > 1,
      ),
      validator: validator,
    );
  }
}