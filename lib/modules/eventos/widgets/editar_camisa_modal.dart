import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

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
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  InputDecoration _uaiInputDecoration({
    required String label,
    IconData? icon,
    String? hint,
    String? prefixText,
  }) {
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(color: context.uai.textSecondary),
      hintStyle: TextStyle(color: context.uai.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: context.uai.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: context.uai.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.uai.buttonRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }


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
      backgroundColor: context.uai.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20),
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
                  color: context.uai.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),

            Text(
              '👕 EDITAR CAMISA',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.uai.info,
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
                      color: isSelected ? Colors.white : context.uai.textPrimary,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _tamanhoSelecionado = tamanho;
                    });
                  },
                  backgroundColor: context.uai.cardAlt,
                  selectedColor: context.uai.info,
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),

            SizedBox(height: 20),

            // Checkbox de entrega
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.uai.cardAlt),
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
                    activeColor: context.uai.warning,
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
                    activeColor: context.uai.success,
                  ),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: context.uai.error,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('CANCELAR'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.uai.info,
                      foregroundColor: _appBarFg(),
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