import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

class AreaAlunoSolicitarAlteracaoScreen extends StatefulWidget {
  final Map<String, dynamic> aluno;
  final Map<String, dynamic> authPayload;

  const AreaAlunoSolicitarAlteracaoScreen({
    super.key,
    required this.aluno,
    required this.authPayload,
  });

  @override
  State<AreaAlunoSolicitarAlteracaoScreen> createState() =>
      _AreaAlunoSolicitarAlteracaoScreenState();
}

class _AreaAlunoSolicitarAlteracaoScreenState
    extends State<AreaAlunoSolicitarAlteracaoScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomeController;
  late final TextEditingController _apelidoController;
  late final TextEditingController _dataNascimentoController;
  late final TextEditingController _sexoController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _enderecoController;
  late final TextEditingController _contatoAlunoController;
  late final TextEditingController _nomeResponsavelController;
  late final TextEditingController _contatoResponsavelController;
  late final TextEditingController _observacaoController;

  bool _enviando = false;

  @override
  void initState() {
    super.initState();

    _nomeController = TextEditingController(text: _txt('nome'));
    _apelidoController = TextEditingController(text: _txt('apelido'));
    _dataNascimentoController =
        TextEditingController(text: _txt('data_nascimento'));
    _sexoController = TextEditingController(text: _txt('sexo'));
    _cidadeController = TextEditingController(text: _txt('cidade'));
    _enderecoController = TextEditingController(text: _txt('endereco'));
    _contatoAlunoController = TextEditingController(
      text: _formatPhoneNumber(_txt('contato_aluno')),
    );
    _nomeResponsavelController =
        TextEditingController(text: _txt('nome_responsavel'));
    _contatoResponsavelController = TextEditingController(
      text: _formatPhoneNumber(_txt('contato_responsavel')),
    );
    _observacaoController = TextEditingController();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _apelidoController.dispose();
    _dataNascimentoController.dispose();
    _sexoController.dispose();
    _cidadeController.dispose();
    _enderecoController.dispose();
    _contatoAlunoController.dispose();
    _nomeResponsavelController.dispose();
    _contatoResponsavelController.dispose();
    _observacaoController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _txt(String key) {
    final value = widget.aluno[key];

    if (value == null) return '';

    final text = value.toString().trim();

    if (text == 'null') return '';

    return text;
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr.trim().isEmpty) return null;

    try {
      return DateFormat('dd/MM/yyyy').parseStrict(dateStr.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _selectDate(
      BuildContext context,
      TextEditingController controller,
      ) async {
    final t = context.uai;
    final atual = _parseDate(controller.text);

    final picked = await showDatePicker(
      context: context,
      initialDate: atual ?? DateTime.now(),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Selecionar data de nascimento',
      cancelText: 'CANCELAR',
      confirmText: 'CONFIRMAR',
      fieldLabelText: 'Data de nascimento',
      fieldHintText: 'dd/mm/aaaa',
      builder: (context, child) {
        final primary = _ensureVisible(t.primary, t.surface);

        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme(
              brightness:
              t.background.computeLuminance() < 0.45 ? Brightness.dark : Brightness.light,
              primary: primary,
              onPrimary: _readableOn(primary),
              secondary: primary,
              onSecondary: _readableOn(primary),
              error: t.error,
              onError: _readableOn(t.error),
              surface: t.surface,
              onSurface: t.textPrimary,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: t.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.cardRadius),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  String _formatPhoneNumber(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';
    if (digits.length <= 2) return '($digits';
    if (digits.length <= 6) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    }
    if (digits.length <= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }

    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
  }

  String _cleanPhone(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  Map<String, dynamic> _montarDadosSolicitados() {
    return {
      'nome': _nomeController.text.trim(),
      'apelido': _apelidoController.text.trim(),
      'data_nascimento': _dataNascimentoController.text.trim(),
      'sexo': _sexoController.text.trim().toUpperCase(),
      'cidade': _cidadeController.text.trim().toUpperCase(),
      'endereco': _enderecoController.text.trim(),
      'contato_aluno': _cleanPhone(_contatoAlunoController.text),
      'nome_responsavel': _nomeResponsavelController.text.trim(),
      'contato_responsavel': _cleanPhone(_contatoResponsavelController.text),
    };
  }

  Map<String, dynamic> _montarDadosOriginaisVisiveis() {
    return {
      'nome': _txt('nome'),
      'apelido': _txt('apelido'),
      'data_nascimento': _txt('data_nascimento'),
      'sexo': _txt('sexo'),
      'cidade': _txt('cidade'),
      'endereco': _txt('endereco'),
      'contato_aluno': _txt('contato_aluno'),
      'nome_responsavel': _txt('nome_responsavel'),
      'contato_responsavel': _txt('contato_responsavel'),
    };
  }

  List<String> _camposAlterados() {
    final originais = _montarDadosOriginaisVisiveis();
    final solicitados = _montarDadosSolicitados();

    final campos = <String>[];

    for (final key in solicitados.keys) {
      final original = (originais[key] ?? '').toString().trim();
      final novo = (solicitados[key] ?? '').toString().trim();

      if (key.contains('contato')) {
        if (_cleanPhone(original) != _cleanPhone(novo)) {
          campos.add(key);
        }
      } else if (original != novo) {
        campos.add(key);
      }
    }

    return campos;
  }

  String _campoLabel(String key) {
    switch (key) {
      case 'nome':
        return 'Nome';
      case 'apelido':
        return 'Apelido';
      case 'data_nascimento':
        return 'Data de nascimento';
      case 'sexo':
        return 'Sexo';
      case 'cidade':
        return 'Cidade';
      case 'endereco':
        return 'Endereço';
      case 'contato_aluno':
        return 'Contato do aluno';
      case 'nome_responsavel':
        return 'Nome do responsável';
      case 'contato_responsavel':
        return 'Contato do responsável';
      default:
        return key;
    }
  }

  Future<void> _enviarSolicitacao() async {
    if (!_formKey.currentState!.validate()) return;

    final t = context.uai;
    final camposAlterados = _camposAlterados();

    if (camposAlterados.isEmpty) {
      _mostrarSnack(
        'Nenhuma alteração foi identificada.',
        t.warning,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _enviando = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'criarSolicitacaoAlteracaoAreaAluno',
      );

      final result = await callable.call({
        'alunoId': widget.aluno['aluno_id'],
        'auth': widget.authPayload,
        'dadosSolicitados': _montarDadosSolicitados(),
        'observacaoAluno': _observacaoController.text.trim(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        _mostrarSnack(
          data['message']?.toString() ??
              'Não foi possível enviar a solicitação.',
          t.error,
        );
        return;
      }

      if (!mounted) return;

      await _mostrarDialogSucesso();

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      _mostrarSnack(
        e.message ?? 'Erro ao enviar solicitação.',
        t.error,
      );
    } catch (e) {
      _mostrarSnack(
        'Erro ao enviar solicitação: $e',
        t.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  Future<void> _mostrarDialogSucesso() async {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.surface);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Solicitação enviada',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Sua solicitação foi enviada para análise da coordenação. '
                'Os dados oficiais só serão alterados depois da aprovação.',
            style: TextStyle(
              color: t.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: success,
                foregroundColor: _readableOn(success),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostrarSnack(String msg, Color color) {
    if (!mounted) return;

    final visible = _ensureVisible(color, context.uai.background);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: visible,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg = _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Solicitar alterações',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        iconTheme: IconThemeData(color: appBarFg),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
          constraints.maxWidth > 780 ? 780.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    _buildAviso(),
                    const SizedBox(height: 14),
                    _buildSection(
                      title: 'Dados pessoais',
                      icon: Icons.badge_rounded,
                      color: t.primary,
                      children: [
                        _buildTextField(
                          controller: _nomeController,
                          label: 'Nome completo',
                          icon: Icons.person_rounded,
                          obrigatorio: true,
                        ),
                        _buildTextField(
                          controller: _apelidoController,
                          label: 'Apelido',
                          icon: Icons.alternate_email_rounded,
                        ),
                        _buildDateField(
                          controller: _dataNascimentoController,
                          label: 'Data de nascimento',
                        ),
                        _buildSexoField(),
                        _buildTextField(
                          controller: _cidadeController,
                          label: 'Cidade',
                          icon: Icons.location_city_rounded,
                        ),
                        _buildTextField(
                          controller: _enderecoController,
                          label: 'Endereço',
                          icon: Icons.home_rounded,
                          maxLines: 2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      title: 'Contato',
                      icon: Icons.phone_android_rounded,
                      color: t.info,
                      children: [
                        _buildPhoneField(
                          controller: _contatoAlunoController,
                          label: 'Contato do aluno',
                          obrigatorio: false,
                        ),
                        _buildTextField(
                          controller: _nomeResponsavelController,
                          label: 'Nome do responsável',
                          icon: Icons.supervisor_account_rounded,
                        ),
                        _buildPhoneField(
                          controller: _contatoResponsavelController,
                          label: 'Contato do responsável',
                          obrigatorio: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSection(
                      title: 'Observação',
                      icon: Icons.notes_rounded,
                      color: t.warning,
                      children: [
                        _buildTextField(
                          controller: _observacaoController,
                          label: 'Explique se quiser',
                          hint:
                          'Ex: Meu telefone mudou / meu endereço está incompleto...',
                          icon: Icons.edit_note_rounded,
                          maxLines: 4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildAlteracoesPreview(),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _enviando ? null : _enviarSolicitacao,
                        icon: _enviando
                            ? SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            color: _readableOn(t.primary),
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _enviando
                              ? 'ENVIANDO...'
                              : 'ENVIAR SOLICITAÇÃO PARA ANÁLISE',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.primary,
                          disabledBackgroundColor: t.cardAlt,
                          foregroundColor: _readableOn(t.primary),
                          disabledForegroundColor: t.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 4),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.edit_note_rounded,
              color: onPrimary,
              size: 31,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Correção de cadastro',
                  style: TextStyle(
                    color: onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Atualize somente o que estiver incorreto.',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.76),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAviso() {
    final t = context.uai;

    return _infoBox(
      icon: Icons.lock_outline_rounded,
      color: t.info,
      text:
      'Essa solicitação não altera seu cadastro automaticamente. '
          'A coordenação irá comparar os dados atuais com os dados solicitados e aprovar ou recusar.',
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.12)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.12)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: _enviando ? null : () => _selectDate(context, controller),
        style: TextStyle(color: t.textPrimary),
        decoration: _inputDecoration(
          label: label,
          hint: 'dd/mm/aaaa',
          prefixIcon: Icons.cake_rounded,
          suffixIcon: Icons.calendar_month_rounded,
          color: primary,
        ),
        validator: (value) {
          final text = value?.trim() ?? '';

          if (text.isEmpty) return null;

          final data = _parseDate(text);

          if (data == null) return 'Data inválida';

          if (data.isAfter(DateTime.now())) {
            return 'A data não pode ser futura';
          }

          return null;
        },
      ),
    );
  }

  Widget _buildSexoField() {
    final t = context.uai;
    final valorAtual = _sexoController.text.trim().toUpperCase();
    final valorValido = ['MASCULINO', 'FEMININO'].contains(valorAtual)
        ? valorAtual
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        value: valorValido,
        dropdownColor: t.surface,
        style: TextStyle(color: t.textPrimary),
        decoration: _inputDecoration(
          label: 'Sexo',
          prefixIcon: Icons.wc_rounded,
          color: t.primary,
        ),
        items: const [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('Não informado'),
          ),
          DropdownMenuItem<String?>(
            value: 'MASCULINO',
            child: Text('MASCULINO'),
          ),
          DropdownMenuItem<String?>(
            value: 'FEMININO',
            child: Text('FEMININO'),
          ),
        ],
        onChanged: _enviando
            ? null
            : (value) {
          setState(() {
            _sexoController.text = value ?? '';
          });
        },
      ),
    );
  }

  Widget _buildPhoneField({
    required TextEditingController controller,
    required String label,
    bool obrigatorio = false,
  }) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        readOnly: _enviando,
        style: TextStyle(color: t.textPrimary),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
          _PhoneInputFormatter(),
        ],
        decoration: _inputDecoration(
          label: obrigatorio ? '$label *' : label,
          hint: '(00) 00000-0000',
          prefixIcon: Icons.phone_android_rounded,
          color: t.info,
        ),
        validator: (value) {
          final digits = _cleanPhone(value ?? '');

          if (obrigatorio && digits.isEmpty) {
            return 'Campo obrigatório';
          }

          if (digits.isNotEmpty && digits.length != 11) {
            return 'Telefone deve ter 11 dígitos com DDD';
          }

          return null;
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obrigatorio = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: _enviando,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: TextStyle(color: t.textPrimary),
        decoration: _inputDecoration(
          label: obrigatorio ? '$label *' : label,
          hint: hint,
          prefixIcon: icon,
          color: t.primary,
        ),
        validator: validator ??
            (obrigatorio
                ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Campo obrigatório';
              }
              return null;
            }
                : null),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required IconData prefixIcon,
    IconData? suffixIcon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: Icon(prefixIcon, color: accent, size: 21),
      suffixIcon:
      suffixIcon == null ? null : Icon(suffixIcon, color: accent),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error, width: 1.4),
      ),
    );
  }

  Widget _buildAlteracoesPreview() {
    final t = context.uai;
    final campos = _camposAlterados();
    final temAlteracao = campos.isNotEmpty;
    final color = temAlteracao ? t.warning : t.textSecondary;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(
            temAlteracao
                ? Icons.change_circle_rounded
                : Icons.info_outline_rounded,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              temAlteracao
                  ? '${campos.length} campo(s) alterado(s): ${campos.map(_campoLabel).join(', ')}'
                  : 'Nenhuma alteração identificada até agora.',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    String formatted;

    if (digits.length <= 2) {
      formatted = digits.isEmpty ? '' : '($digits';
    } else if (digits.length <= 6) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else if (digits.length <= 10) {
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    } else {
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
