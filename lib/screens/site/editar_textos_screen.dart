import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/site_config_service.dart';

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
    for (var secao in widget.secoes) {
      _tituloControllers[secao['id']] = TextEditingController(text: secao['titulo']);
      _descricaoControllers[secao['id']] = TextEditingController(text: secao['descricao']);
    }
  }

  @override
  void dispose() {
    for (var controller in _tituloControllers.values) {
      controller.dispose();
    }
    for (var controller in _descricaoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Textos'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _salvarTextos,
            child: Text(
              'SALVAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _salvando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.secoes.length,
        itemBuilder: (context, index) {
          final secao = widget.secoes[index];
          return _buildSecaoEditor(secao);
        },
      ),
    );
  }

  Widget _buildSecaoEditor(Map<String, dynamic> secao) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: secao['cor'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(secao['icone'], color: secao['cor']),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    secao['titulo'],
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tituloControllers[secao['id']],
              decoration: InputDecoration(
                labelText: 'Título no menu',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descricaoControllers[secao['id']],
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.description),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvarTextos() async {
    setState(() => _salvando = true);

    try {
      final Map<String, String> titulos = {};
      final Map<String, String> descricoes = {};

      for (var secao in widget.secoes) {
        titulos[secao['id']] = _tituloControllers[secao['id']]!.text;
        descricoes[secao['id']] = _descricaoControllers[secao['id']]!.text;
      }

      await _configService.salvarTitulos(titulos);
      await _configService.salvarDescricoes(descricoes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Textos salvos com sucesso!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSalvo();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao salvar: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _salvando = false);
    }
  }
}