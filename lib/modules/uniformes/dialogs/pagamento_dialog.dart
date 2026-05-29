import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

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
    final success = context.uai.success;
    final error = context.uai.error;
    final warning = context.uai.warning;
    final primary = context.uai.primary;
    final textPrimary = context.uai.textPrimary;
    final textSecondary = context.uai.textSecondary;
    final cardAlt = context.uai.cardAlt;
    final surface = context.uai.surface;

    return AlertDialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
      ),
      title: Text(
        'Registrar Pagamento',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informações da venda
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: success.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aluno: ${widget.alunoNome}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total:', style: TextStyle(fontSize: 12, color: textSecondary)),
                      Text(
                        _realFormat.format(widget.valorTotal),
                        style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Já pago:', style: TextStyle(fontSize: 12, color: textSecondary)),
                      Text(
                        _realFormat.format(widget.valorPago),
                        style: TextStyle(color: success),
                      ),
                    ],
                  ),
                  Divider(height: 16, color: context.uai.border),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Restante:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                      Text(
                        _realFormat.format(widget.valorRestante),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: error,
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
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(
                labelText: 'Valor do pagamento',
                labelStyle: TextStyle(color: textSecondary),
                prefixText: 'R\$ ',
                helperText: widget.valorRestante > 0
                    ? 'Máximo: ${_realFormat.format(widget.valorRestante)}'
                    : null,
                helperStyle: TextStyle(color: textSecondary),
                filled: true,
                fillColor: cardAlt,
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
                  borderSide: BorderSide(color: primary, width: 1.4),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Forma de pagamento
            Text(
              'Forma de pagamento',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ..._formasPagamento.map((forma) {
              return RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(forma['icone'], size: 20, color: success),
                    const SizedBox(width: 8),
                    Text(
                      forma['label'],
                      style: TextStyle(color: textPrimary),
                    ),
                  ],
                ),
                value: forma['valor'],
                groupValue: _formaPagamento,
                onChanged: (value) {
                  setState(() {
                    _formaPagamento = value;
                  });
                },
                activeColor: success,
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),

            if (widget.valorRestante <= 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: warning.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta venda já está totalmente paga!',
                        style: TextStyle(color: warning),
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
          child: Text(
            'Cancelar',
            style: TextStyle(color: primary),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading || widget.valorRestante <= 0 ? null : _confirmarPagamento,
          style: ElevatedButton.styleFrom(
            backgroundColor: success,
            foregroundColor: _readableOn(success),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.uai.buttonRadius),
            ),
          ),
          child: _isLoading
              ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _readableOn(success),
            ),
          )
              : Text(
            'Registrar',
            style: TextStyle(color: _readableOn(success)),
          ),
        ),
      ],
    );
  }

  void _confirmarPagamento() {
    double valor = double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0;

    if (valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Valor deve ser maior que zero',
            style: TextStyle(color: _readableOn(context.uai.error)),
          ),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    if (valor > widget.valorRestante) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Valor não pode ser maior que ${_realFormat.format(widget.valorRestante)}',
            style: TextStyle(color: _readableOn(context.uai.error)),
          ),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onConfirm(valor, _formaPagamento!);
      }
    });
  }
}