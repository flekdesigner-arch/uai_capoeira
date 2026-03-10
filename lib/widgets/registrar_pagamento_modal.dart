import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RegistrarPagamentoModal extends StatefulWidget {
  final double saldoAtual;
  final double valorTotal;
  final List<double> sugestoes;
  final bool temPatrocinio;

  const RegistrarPagamentoModal({
    super.key,
    required this.saldoAtual,
    required this.valorTotal,
    required this.sugestoes,
    this.temPatrocinio = false,
  });

  @override
  State<RegistrarPagamentoModal> createState() => _RegistrarPagamentoModalState();
}

class _RegistrarPagamentoModalState extends State<RegistrarPagamentoModal> {
  final _formKey = GlobalKey<FormState>();
  final _valorController = TextEditingController();
  final _observacoesController = TextEditingController();

  String _formaPagamento = 'DINHEIRO';
  bool _anexarComprovante = false;
  int _parcelas = 1;

  final List<String> _formasPagamento = [
    'DINHEIRO',
    'PIX',
    'CARTÃO DE CRÉDITO',
    'CARTÃO DE DÉBITO',
    'TRANSFERÊNCIA',
    'CHEQUE',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.temPatrocinio) {
      _formasPagamento.add('PATROCÍNIO');
    }

    if (widget.saldoAtual > 0) {
      _valorController.text = widget.saldoAtual.toStringAsFixed(2);
    }

    debugPrint('💰 Modal aberto - Saldo: ${widget.saldoAtual}');
  }

  String _formatarMoeda(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  '💰 REGISTRAR PAGAMENTO',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Saldo devedor:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatarMoeda(widget.saldoAtual),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.saldoAtual > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total do evento:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatarMoeda(widget.valorTotal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                if (widget.sugestoes.isNotEmpty) ...[
                  const Text(
                    '⚡ Sugestões de pagamento:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.sugestoes.map((valor) {
                      final isSelected = _valorController.text == valor.toStringAsFixed(2);
                      return FilterChip(
                        label: Text(_formatarMoeda(valor)),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _valorController.text = valor.toStringAsFixed(2);
                          });
                        },
                        backgroundColor: Colors.grey.shade100,
                        selectedColor: Colors.green.shade100,
                        checkmarkColor: Colors.green,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _valorController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Valor do pagamento',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(value.replaceAll(',', '.'));
                    if (valor == null || valor <= 0) {
                      return 'Valor deve ser maior que zero';
                    }
                    if (valor > widget.saldoAtual + 0.01) {
                      return 'Valor não pode ser maior que o saldo devedor (${_formatarMoeda(widget.saldoAtual)})';
                    }
                    return null;
                  },
                ),

                if (widget.saldoAtual > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 12),
                    child: Text(
                      'Após pagamento: ${_formatarMoeda(widget.saldoAtual - (double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0))}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: _formaPagamento,
                  decoration: InputDecoration(
                    labelText: 'Forma de pagamento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _formasPagamento.map((forma) {
                    return DropdownMenuItem(
                      value: forma,
                      child: Row(
                        children: [
                          Icon(
                            forma == 'PIX' ? Icons.pix :
                            forma == 'PATROCÍNIO' ? Icons.volunteer_activism :
                            Icons.payment,
                            size: 16,
                            color: forma == 'PATROCÍNIO' ? Colors.purple : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(forma),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _formaPagamento = value!;
                    });
                  },
                ),

                const SizedBox(height: 16),

                if (_formaPagamento == 'CARTÃO DE CRÉDITO')
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<int>(
                      value: _parcelas,
                      decoration: InputDecoration(
                        labelText: 'Número de parcelas',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((parcela) {
                        final valorParcela = (double.tryParse(_valorController.text.replaceAll(',', '.')) ?? 0) / parcela;
                        return DropdownMenuItem(
                          value: parcela,
                          child: Text('$parcela x ${_formatarMoeda(valorParcela)}'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _parcelas = value ?? 1;
                        });
                      },
                    ),
                  ),

                TextFormField(
                  controller: _observacoesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Observações (opcional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),

                const SizedBox(height: 16),

                CheckboxListTile(
                  title: const Text('Anexar comprovante'),
                  value: _anexarComprovante,
                  onChanged: (value) {
                    setState(() {
                      _anexarComprovante = value!;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 20),

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
                        onPressed: _confirmarPagamento,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('REGISTRAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmarPagamento() {
    if (_formKey.currentState!.validate()) {
      final valor = double.parse(_valorController.text.replaceAll(',', '.'));

      final Map<String, dynamic> result = {
        'valor': valor,
        'formaPagamento': _formaPagamento,
        'observacoes': _observacoesController.text.isNotEmpty
            ? _observacoesController.text
            : null,
        'anexo': _anexarComprovante ? 'pendente' : null,
      };

      if (_formaPagamento == 'CARTÃO DE CRÉDITO') {
        result['parcela'] = _parcelas;
      }

      Navigator.pop(context, result);
    }
  }

  @override
  void dispose() {
    _valorController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }
}