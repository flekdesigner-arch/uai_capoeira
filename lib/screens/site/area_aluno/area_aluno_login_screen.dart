import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'area_aluno_dashboard_screen.dart';

class AreaAlunoLoginScreen extends StatefulWidget {
  const AreaAlunoLoginScreen({super.key});

  @override
  State<AreaAlunoLoginScreen> createState() => _AreaAlunoLoginScreenState();
}

class _AreaAlunoLoginScreenState extends State<AreaAlunoLoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _dataNascimentoController = TextEditingController();
  final TextEditingController _iniciaisController = TextEditingController();
  final TextEditingController _telefoneFinalController = TextEditingController();

  bool _carregando = false;

  @override
  void dispose() {
    _dataNascimentoController.dispose();
    _iniciaisController.dispose();
    _telefoneFinalController.dispose();
    super.dispose();
  }

  String _normalizarIniciais(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
  }

  Future<void> _acessarAreaAluno() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _carregando = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'validarAcessoAreaAluno',
      );

      final result = await callable.call({
        'dataNascimento': _dataNascimentoController.text.trim(),
        'iniciais': _normalizarIniciais(_iniciaisController.text),
        'telefoneFinal': _telefoneFinalController.text.trim(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      final success = data['success'] == true;

      if (!success) {
        _mostrarErro(
          data['message']?.toString() ??
              'Não foi possível validar o acesso. Confira os dados e tente novamente.',
        );
        return;
      }

      final aluno = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
      final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AreaAlunoDashboardScreen(
            aluno: aluno,
            config: config,
            authPayload: {
              'dataNascimento': _dataNascimentoController.text.trim(),
              'iniciais': _normalizarIniciais(_iniciaisController.text),
              'telefoneFinal': _telefoneFinalController.text.trim(),
            },
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      _mostrarErro(
        e.message ?? 'Erro ao validar acesso. Tente novamente em instantes.',
      );
    } catch (e) {
      _mostrarErro('Erro ao acessar a Área do Aluno: $e');
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 650;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 28),
              child: Column(
                children: [
                  _buildHeader(isMobile),
                  const SizedBox(height: 18),
                  _buildLoginCard(isMobile),
                  const SizedBox(height: 14),
                  _buildAjudaCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Área do Aluno',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Consulte seus dados, frequência, eventos e certificados.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Icon(
              Icons.verified_user_rounded,
              color: Colors.red.shade900,
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              'Identificação do aluno',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Digite seus dados exatamente como estão no cadastro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 22),

            TextFormField(
              controller: _dataNascimentoController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                LengthLimitingTextInputFormatter(10),
                _DataNascimentoInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'Data de nascimento',
                hintText: 'dd/mm/aaaa',
                prefixIcon: const Icon(Icons.cake_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Informe sua data de nascimento';
                if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
                  return 'Use o formato dd/mm/aaaa';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _iniciaisController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(10),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ú0-9]')),
                UpperCaseTextFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'Iniciais do nome completo',
                hintText: 'Ex: AESL',
                prefixIcon: const Icon(Icons.badge_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (value) {
                final text = _normalizarIniciais(value ?? '');
                if (text.isEmpty) return 'Informe as iniciais';
                if (text.length < 2) return 'Informe pelo menos 2 iniciais';
                return null;
              },
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _telefoneFinalController,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: InputDecoration(
                labelText: 'Últimos 4 dígitos do telefone',
                hintText: 'Ex: 6237',
                prefixIcon: const Icon(Icons.phone_android_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Informe os últimos 4 dígitos';
                if (text.length != 4) return 'Digite exatamente 4 números';
                return null;
              },
            ),
            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _carregando ? null : _acessarAreaAluno,
                icon: _carregando
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.login_rounded),
                label: Text(_carregando ? 'Validando...' : 'ACESSAR MINHA ÁREA'),
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
    );
  }

  Widget _buildAjudaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'As iniciais são formadas pelo primeiro caractere de cada nome. '
                  'Exemplo: ARTHUR EDUARDO SILVA LIMA = AESL. '
                  'Preposições como DE, DA, DO, DOS e DAS são ignoradas.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
