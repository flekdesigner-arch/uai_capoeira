import 'package:flutter/material.dart';

class EditarCamisaModal extends StatefulWidget {
  final String? tamanhoAtual;
  final bool entregue;
  final List<String> tamanhosDisponiveis;

  const EditarCamisaModal({
    super.key,
    this.tamanhoAtual,
    required this.entregue,
    required this.tamanhosDisponiveis,
  });

  @override
  State<EditarCamisaModal> createState() => _EditarCamisaModalState();
}

class _EditarCamisaModalState extends State<EditarCamisaModal> {
  late String? _tamanhoSelecionado;
  late bool _entregue;

  final List<String> _tamanhosPadrao = [
    '4A', '6A', '8A', '10A', '12A', '14A',
    'PP', 'P', 'M', 'G', 'GG', 'EGG',
  ];

  @override
  void initState() {
    super.initState();
    _tamanhoSelecionado = widget.tamanhoAtual;
    _entregue = widget.entregue;
  }

  List<String> get _tamanhos {
    if (widget.tamanhosDisponiveis.isNotEmpty) {
      return widget.tamanhosDisponiveis;
    }
    return _tamanhosPadrao;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              '👕 EDITAR CAMISA',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Seleção de tamanho
            const Text(
              'Tamanho:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tamanhos.map((tamanho) {
                final isSelected = _tamanhoSelecionado == tamanho;
                return FilterChip(
                  label: Text(
                    tamanho,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _tamanhoSelecionado = tamanho;
                    });
                  },
                  backgroundColor: Colors.grey.shade100,
                  selectedColor: Colors.blue,
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Checkbox de entrega
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status da entrega:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    title: const Text('Pendente'),
                    value: false,
                    groupValue: _entregue,
                    onChanged: (value) {
                      setState(() {
                        _entregue = value!;
                      });
                    },
                    activeColor: Colors.orange,
                  ),
                  RadioListTile<bool>(
                    title: const Text('Entregue'),
                    value: true,
                    groupValue: _entregue,
                    onChanged: (value) {
                      setState(() {
                        _entregue = value!;
                      });
                    },
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('SALVAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _salvar() {
    Navigator.pop(context, {
      'tamanho': _tamanhoSelecionado,
      'entregue': _entregue,
    });
  }
}