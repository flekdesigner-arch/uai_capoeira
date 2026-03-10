import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PagamentoDialog extends StatefulWidget {
  final String alunoNome;
  final double valorTotal;
  final double valorPago;
  final double valorRestante;
  final Function(double, String) onConfirm;

  const PagamentoDialog({
    super.key,
    required this.alunoNome,
    required this.valorTotal,
    required this.valorPago,
    required this.valorRestante,
    required this.onConfirm,
  });

  @override
  State<PagamentoDialog> createState() => _PagamentoDialogState();
}

class _PagamentoDialogState extends State<PagamentoDialog> {
  final TextEditingController _valorController = TextEditingController();
  String? _formaPagamento = 'dinheiro';
  final NumberFormat _realFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _isLoading = false;

  final List<Map<String, dynamic>> _formasPagamento = [
    {'valor': 'dinheiro', 'label': 'Dinheiro', 'icone': Icons.money},
    {'valor': 'pix', 'label': 'PIX', 'icone': Icons.pix},
    {'valor': 'cartao_credito', 'label': 'Cartão de Crédito', 'icone': Icons.credit_card},
    {'valor': 'cartao_debito', 'label': 'Cartão de Débito', 'icone': Icons.credit_card},
    {'valor': 'transferencia', 'label': 'Transferência', 'icone': Icons.compare_arrows},
  ];

  @override
  void initState() {
    super.initState();
    _valorController.text = widget.valorRestante.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Pagamento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informações da venda
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aluno: ${widget.alunoNome}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 12)),
                      Text(
                        _realFormat.format(widget.valorTotal),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Já pago:', style: TextStyle(fontSize: 12)),
                      Text(
                        _realFormat.format(widget.valorPago),
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Restante:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _realFormat.format(widget.valorRestante),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Campo de valor
            TextField(
              controller: _valorController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor do pagamento',
                prefixText: 'R\$ ',
                border: const OutlineInputBorder(),
                helperText: widget.valorRestante > 0
                    ? 'Máximo: ${_realFormat.format(widget.valorRestante)}'
                    : null,
              ),
            ),

            const SizedBox(height: 16),

            // Forma de pagamento
            const Text(
              'Forma de pagamento',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ..._formasPagamento.map((forma) {
              return RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(forma['icone'], size: 20, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(forma['label']),
                  ],
                ),
                value: forma['valor'],
                groupValue: _formaPagamento,
                onChanged: (value) {
                  setState(() {
                    _formaPagamento = value;
                  });
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),

            if (widget.valorRestante <= 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta venda já está totalmente paga!',
                        style: TextStyle(color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading || widget.valorRestante <= 0
              ? null
              : _confirmarPagamento,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Registrar'),
        ),
      ],
    );
  }

  void _confirmarPagamento() {
    double valor = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0;

    if (valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Valor deve ser maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (valor > widget.valorRestante) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Valor não pode ser maior que ${_realFormat.format(widget.valorRestante)}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // CORREÇÃO: Delay de 500ms para mostrar o loading
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onConfirm(valor, _formaPagamento!);
      }
    });
  }
}