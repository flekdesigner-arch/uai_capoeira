import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class QuantidadeDialog extends StatefulWidget {
  final String titulo;
  final String itemNome;
  final double? precoUnitario;
  final int? maxQuantidade;
  final Function(int) onConfirm;

  const QuantidadeDialog({
    super.key,
    required this.titulo,
    required this.itemNome,
    required this.onConfirm,
    this.precoUnitario,
    this.maxQuantidade,
  });

  @override
  State<QuantidadeDialog> createState() => _QuantidadeDialogState();
}

class _QuantidadeDialogState extends State<QuantidadeDialog> {
  final TextEditingController _quantidadeController = TextEditingController();
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  int _quantidade = 1;

  @override
  void initState() {
    super.initState();
    _quantidadeController.text = '1';
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações do item
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
                Text(
                  'Item: ${widget.itemNome}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (widget.precoUnitario != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Preço unitário: ${_realFormat.format(widget.precoUnitario!)}',
                    style: const TextStyle(color: Colors.green),
                  ),
                ],
                if (widget.maxQuantidade != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Disponível: ${widget.maxQuantidade}',
                    style: TextStyle(
                      color: widget.maxQuantidade! > 0 ? Colors.blue : Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Controles de quantidade
          Row(
            children: [
              // Botão diminuir
              Expanded(
                flex: 2,
                child: IconButton(
                  onPressed: _quantidade > 1 ? _diminuir : null,
                  icon: Icon(
                    Icons.remove_circle,
                    color: _quantidade > 1 ? Colors.red : Colors.grey,
                  ),
                ),
              ),

              // Campo de texto
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _quantidadeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Quantidade',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) {
                    int? novaQuantidade = int.tryParse(value);
                    if (novaQuantidade != null && novaQuantidade > 0) {
                      if (widget.maxQuantidade == null || novaQuantidade <= widget.maxQuantidade!) {
                        setState(() {
                          _quantidade = novaQuantidade;
                        });
                      }
                    }
                  },
                ),
              ),

              // Botão aumentar
              Expanded(
                flex: 2,
                child: IconButton(
                  onPressed: widget.maxQuantidade == null || _quantidade < widget.maxQuantidade!
                      ? _aumentar
                      : null,
                  icon: Icon(
                    Icons.add_circle,
                    color: widget.maxQuantidade == null || _quantidade < widget.maxQuantidade!
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),

          if (widget.precoUnitario != null) ...[
            const SizedBox(height: 16),
            // Total parcial
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _realFormat.format(_quantidade * widget.precoUnitario!),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (widget.maxQuantidade != null && _quantidade > widget.maxQuantidade!) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quantidade maior que o disponível em estoque!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.titulo.contains('Entrada') ? Colors.green : Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.titulo.contains('Entrada') ? 'Registrar Entrada' : 'Registrar Saída'),
        ),
      ],
    );
  }

  void _aumentar() {
    if (widget.maxQuantidade == null || _quantidade < widget.maxQuantidade!) {
      setState(() {
        _quantidade++;
        _quantidadeController.text = _quantidade.toString();
      });
    }
  }

  void _diminuir() {
    if (_quantidade > 1) {
      setState(() {
        _quantidade--;
        _quantidadeController.text = _quantidade.toString();
      });
    }
  }

  void _confirmar() {
    if (_quantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantidade deve ser maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.maxQuantidade != null && _quantidade > widget.maxQuantidade!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quantidade máxima disponível: ${widget.maxQuantidade}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context);
    widget.onConfirm(_quantidade);
  }
}