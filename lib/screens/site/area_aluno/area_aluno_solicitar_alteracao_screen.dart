import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.red.shade900,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.grey.shade900,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
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

  Future<void> _enviarSolicitacao() async {
    if (!_formKey.currentState!.validate()) return;

    final camposAlterados = _camposAlterados();

    if (camposAlterados.isEmpty) {
      _mostrarSnack(
        'Nenhuma alteração foi identificada.',
        Colors.orange.shade800,
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
          Colors.red.shade800,
        );
        return;
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Expanded(child: Text('Solicitação enviada')),
              ],
            ),
            content: const Text(
              'Sua solicitação foi enviada para análise da coordenação. '
                  'Os dados oficiais só serão alterados depois da aprovação.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      _mostrarSnack(
        e.message ?? 'Erro ao enviar solicitação.',
        Colors.red.shade800,
      );
    } catch (e) {
      _mostrarSnack(
        'Erro ao enviar solicitação: $e',
        Colors.red.shade800,
      );
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  void _mostrarSnack(String msg, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Solicitar alterações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 780 ? 780.0 : constraints.maxWidth;

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
                      children: [
                        _buildTextField(
                          controller: _observacaoController,
                          label: 'Explique se quiser',
                          hint: 'Ex: Meu telefone mudou / meu endereço está incompleto...',
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
                            ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _enviando
                              ? 'ENVIANDO...'
                              : 'ENVIAR SOLICITAÇÃO PARA ANÁLISE',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          disabledBackgroundColor: Colors.red.shade200,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 31),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Correção de cadastro',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Atualize somente o que estiver incorreto.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAviso() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.blue.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Essa solicitação não altera seu cadastro automaticamente. '
                  'A coordenação irá comparar os dados atuais com os dados solicitados e aprovar ou recusar.',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w500,
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
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.red.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: _enviando ? null : () => _selectDate(context, controller),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'dd/mm/aaaa',
          prefixIcon: Icon(Icons.cake_rounded, color: Colors.red.shade900, size: 21),
          suffixIcon: Icon(Icons.calendar_month_rounded, color: Colors.red.shade900),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
          ),
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
    final valorAtual = _sexoController.text.trim().toUpperCase();
    final valorValido = ['MASCULINO', 'FEMININO'].contains(valorAtual)
        ? valorAtual
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: valorValido,
        decoration: InputDecoration(
          labelText: 'Sexo',
          prefixIcon: Icon(Icons.wc_rounded, color: Colors.red.shade900, size: 21),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
          ),
        ),
        items: const [
          DropdownMenuItem(
            value: null,
            child: Text('Não informado'),
          ),
          DropdownMenuItem(
            value: 'MASCULINO',
            child: Text('MASCULINO'),
          ),
          DropdownMenuItem(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        readOnly: _enviando,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
          _PhoneInputFormatter(),
        ],
        decoration: InputDecoration(
          labelText: obrigatorio ? '$label *' : label,
          hintText: '(00) 00000-0000',
          prefixIcon: Icon(Icons.phone_android_rounded, color: Colors.red.shade900, size: 21),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: obrigatorio ? '$label *' : label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.red.shade900, size: 21),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
          ),
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

  Widget _buildAlteracoesPreview() {
    final campos = _camposAlterados();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: campos.isEmpty ? Colors.grey.shade100 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: campos.isEmpty ? Colors.grey.shade300 : Colors.orange.shade100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            campos.isEmpty
                ? Icons.info_outline_rounded
                : Icons.change_circle_rounded,
            color: campos.isEmpty ? Colors.grey.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              campos.isEmpty
                  ? 'Nenhuma alteração identificada até agora.'
                  : '${campos.length} campo(s) alterado(s): ${campos.join(', ')}',
              style: TextStyle(
                color: campos.isEmpty ? Colors.grey.shade700 : Colors.orange.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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

class _DataNascimentoInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }

    final text = buffer.toString();

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
