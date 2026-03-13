import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/site_config_service.dart';

class ConfigurarMenuScreen extends StatefulWidget {
  final List<Map<String, dynamic>> secoes;
  final VoidCallback onSalvo;

  const ConfigurarMenuScreen({
    super.key,
    required this.secoes,
    required this.onSalvo,
  });

  @override
  State<ConfigurarMenuScreen> createState() => _ConfigurarMenuScreenState();
}

class _ConfigurarMenuScreenState extends State<ConfigurarMenuScreen> {
  late List<Map<String, dynamic>> _itens;
  late List<Map<String, dynamic>> _itensVisiveis;
  final SiteConfigService _configService = SiteConfigService();
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _itens = List.from(widget.secoes);
    _itensVisiveis = _itens.where((item) => item['is_config'] != true).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordenar Menu'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _salvarOrdem,
            child: Text(
              'SALVAR',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instruções
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Arraste as seções para reordenar. O item INÍCIO permanece fixo no topo.',
                    style: TextStyle(color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
          // Lista arrastável
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _itensVisiveis.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final item = _itensVisiveis[index];
                return _buildDraggableItem(item, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableItem(Map<String, dynamic> item, int index) {
    final bool isInicio = item['id'] == 'inicio';

    return Container(
      key: ValueKey(item['id']),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: item['cor'].withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            item['icone'],
            color: item['cor'],
            size: 20,
          ),
        ),
        title: Text(
          item['titulo'],
          style: TextStyle(
            fontWeight: isInicio ? FontWeight.bold : FontWeight.normal,
            color: isInicio ? Colors.red.shade900 : Colors.black,
          ),
        ),
        subtitle: Text(item['descricao']),
        trailing: isInicio
            ? const Icon(Icons.lock, color: Colors.grey)
            : const Icon(Icons.drag_handle),
        enabled: !isInicio,
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _itensVisiveis.removeAt(oldIndex);
      _itensVisiveis.insert(newIndex, item);
    });
  }

  Future<void> _salvarOrdem() async {
    setState(() => _salvando = true);

    try {
      final ordem = _itensVisiveis.map((item) => item['id'] as String).toList();
      await _configService.salvarOrdemMenu(ordem);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Ordem salva com sucesso!'),
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