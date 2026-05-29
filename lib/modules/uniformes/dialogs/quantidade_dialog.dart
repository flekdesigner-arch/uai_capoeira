import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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

  // Helpers de contraste
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

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
    final tema = context.uai;
    final bool isEntrada = widget.titulo.contains('Entrada');
    final Color corAcao = isEntrada ? tema.success : tema.warning;
    final Color corAcaoFg = _readableOn(corAcao);
    final Color cardBg = tema.card;
    final Color cardAlt = tema.cardAlt;
    final Color border = tema.border;
    final Color textPrimary = tema.textPrimary;
    final Color textSecondary = tema.textSecondary;
    final Color errorColor = tema.error;
    final Color infoColor = tema.info;

    return AlertDialog(
      backgroundColor: tema.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tema.cardRadius),
      ),
      title: Text(
        widget.titulo,
        style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações do item
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item: ${widget.itemNome}',
                  style: TextStyle(fontWeight: FontWeight.w500, color: textPrimary),
                ),
                if (widget.precoUnitario != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Preço unitário: ${_realFormat.format(widget.precoUnitario!)}',
                    style: TextStyle(color: tema.success),
                  ),
                ],
                if (widget.maxQuantidade != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Disponível: ${widget.maxQuantidade}',
                    style: TextStyle(
                      color: widget.maxQuantidade! > 0 ? infoColor : errorColor,
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
                    color: _quantidade > 1 ? errorColor : tema.textMuted,
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
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Quantidade',
                    labelStyle: TextStyle(color: textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tema.inputRadius),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tema.inputRadius),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tema.inputRadius),
                      borderSide: BorderSide(color: tema.primary, width: 1.4),
                    ),
                    filled: true,
                    fillColor: cardAlt,
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
                        ? tema.success
                        : tema.textMuted,
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
                color: tema.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  Text(
                    _realFormat.format(_quantidade * widget.precoUnitario!),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: tema.success,
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
                color: errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, size: 16, color: errorColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Quantidade maior que o disponível em estoque!',
                      style: TextStyle(
                        fontSize: 12,
                        color: errorColor,
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
          child: Text('Cancelar', style: TextStyle(color: tema.primary)),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          style: ElevatedButton.styleFrom(
            backgroundColor: corAcao,
            foregroundColor: corAcaoFg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tema.buttonRadius),
            ),
          ),
          child: Text(
            isEntrada ? 'Registrar Entrada' : 'Registrar Saída',
            style: TextStyle(color: corAcaoFg),
          ),
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
        SnackBar(
          content: Text(
            'Quantidade deve ser maior que zero',
            style: TextStyle(color: _readableOn(context.uai.error)),
          ),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    if (widget.maxQuantidade != null && _quantidade > widget.maxQuantidade!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantidade máxima disponível: ${widget.maxQuantidade}',
            style: TextStyle(color: _readableOn(context.uai.error)),
          ),
          backgroundColor: context.uai.error,
        ),
      );
      return;
    }

    Navigator.pop(context);
    widget.onConfirm(_quantidade);
  }
}