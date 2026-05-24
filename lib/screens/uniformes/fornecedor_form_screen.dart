import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/services/fornecedor_service.dart';

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
      // 🔥 Garantimos que o mapa seja explicitamente Map<String, dynamic>
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
            const SnackBar(content: Text('✅ Fornecedor cadastrado!'), backgroundColor: Colors.green),
          );
        }
      } else {
        await _fornecedorService.atualizarFornecedor(widget.fornecedorId!, dados);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Fornecedor atualizado!'), backgroundColor: Colors.blue),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e, stackTrace) {
      // 🔥 Exibe o erro completo no console para debug
      debugPrint('❌ Erro ao salvar fornecedor: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fornecedorId == null ? 'NOVO FORNECEDOR' : 'EDITAR FORNECEDOR'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _salvar,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, color: Colors.white),
            label: Text(_isLoading ? 'SALVANDO...' : 'SALVAR', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome / Fantasia *', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contatoController,
              decoration: const InputDecoration(labelText: 'Contato (pessoa)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telefoneController,
              decoration: const InputDecoration(labelText: 'Telefone', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cnpjController,
              decoration: const InputDecoration(labelText: 'CNPJ', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacoesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save),
              label: const Text('SALVAR FORNECEDOR'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}