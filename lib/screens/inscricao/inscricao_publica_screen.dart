import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:uai_capoeira/screens/inscricao/signature_screen.dart';
import 'package:uai_capoeira/widgets/regimento_dialog.dart'; // 🔥 IMPORT DO DIALOG DO REGIMENTO

class InscricaoPublicaScreen extends StatefulWidget {
  const InscricaoPublicaScreen({super.key});

  @override
  State<InscricaoPublicaScreen> createState() => _InscricaoPublicaScreenState();
}

class _InscricaoPublicaScreenState extends State<InscricaoPublicaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Controladores
  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'apelido': TextEditingController(),
    'cpf': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'rua': TextEditingController(),
    'numero': TextEditingController(),
    'bairro': TextEditingController(),
    'cidade': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
  };

  String? _sexo;
  bool _inscricoesAbertas = true;
  bool _carregando = true;
  bool _enviando = false;
  String _mensagem = '';
  bool _autorizacao = false;

  // CONFIGURAÇÕES
  int _idadeMinima = 5;
  int _idadeMaxima = 16;
  int _vagasDisponiveis = 0;
  int _vagasRestantes = 0;
  bool _configuracoesCarregadas = false;
  bool _temVagas = true;
  bool _recolherAssinatura = true;
  String? _assinaturaUrl;

  // MAPA DE VALIDAÇÃO
  final Map<int, bool> _etapaValida = {
    0: false,
    1: false,
    2: false,
    3: false,
    4: true,
    5: false,
  };

  // 🔙 CONTROLE DO BOTÃO VOLTAR
  DateTime? _ultimoBotaoVoltar;
  final int _tempoParaSair = 2000; // 2 segundos

  @override
  void initState() {
    super.initState();
    _controllers['cidade']!.text = 'BOCAIÚVA-MG';

    _controllers['nome']!.addListener(_validarEtapa1);
    _controllers['apelido']!.addListener(_validarEtapa1);
    _controllers['data_nascimento']!.addListener(_validarEtapa1);
    _controllers['contato_aluno']!.addListener(_validarEtapa2);
    _controllers['nome_responsavel']!.addListener(_validarEtapa2);
    _controllers['contato_responsavel']!.addListener(_validarEtapa2);
    _controllers['rua']!.addListener(_validarEtapa3);
    _controllers['numero']!.addListener(_validarEtapa3);
    _controllers['bairro']!.addListener(_validarEtapa3);

    _verificarInscricoes();
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) {
      controller.removeListener(_validarEtapa1);
      controller.removeListener(_validarEtapa2);
      controller.removeListener(_validarEtapa3);
      controller.dispose();
    });
    _pageController.dispose();
    super.dispose();
  }

  bool _isMaiorIdade() {
    final dataNasc = _controllers['data_nascimento']!.text;
    if (dataNasc.isEmpty) return false;
    final idade = _calcularIdade(dataNasc);
    return idade >= 18;
  }

  void _validarEtapa1() {
    if (!mounted) return;
    final nomeValido = _controllers['nome']!.text.isNotEmpty && _validarNome(_controllers['nome']!.text);
    final apelidoValido = _controllers['apelido']!.text.isNotEmpty && _validarNome(_controllers['apelido']!.text);
    final dataValida = _controllers['data_nascimento']!.text.isNotEmpty;
    final sexoValido = _sexo != null;

    bool idadeValida = true;
    if (dataValida) {
      final idade = _calcularIdade(_controllers['data_nascimento']!.text);
      idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;
    }

    setState(() {
      _etapaValida[1] = nomeValido && apelidoValido && dataValida && sexoValido && idadeValida;
    });
  }

  void _validarEtapa2() {
    if (!mounted) return;
    final contatoAlunoValido = _controllers['contato_aluno']!.text.length >= 14;
    bool nomeRespValido = true;
    bool contatoRespValido = true;

    if (!_isMaiorIdade()) {
      nomeRespValido = _controllers['nome_responsavel']!.text.isNotEmpty && _validarNome(_controllers['nome_responsavel']!.text);
      contatoRespValido = _controllers['contato_responsavel']!.text.length >= 14;
    }

    setState(() {
      _etapaValida[2] = contatoAlunoValido && nomeRespValido && contatoRespValido;
    });
  }

  void _validarEtapa3() {
    if (!mounted) return;
    final ruaValida = _controllers['rua']!.text.isNotEmpty && _validarNome(_controllers['rua']!.text);
    final numeroValido = _controllers['numero']!.text.length <= 5 && _controllers['numero']!.text.isNotEmpty;
    final bairroValido = _controllers['bairro']!.text.isNotEmpty && _validarNome(_controllers['bairro']!.text);

    setState(() {
      _etapaValida[3] = ruaValida && numeroValido && bairroValido;
    });
  }

  void _validarEtapaFinal() {
    setState(() {
      // SÓ EXIGE ASSINATURA SE A CONFIGURAÇÃO MANDAR
      _etapaValida[5] = _autorizacao && (_recolherAssinatura ? _assinaturaUrl != null : true);
    });
  }

  bool _validarNome(String nome) {
    if (nome.isEmpty) return false;
    final regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ\s]+$');
    return regex.hasMatch(nome);
  }

  int _calcularIdade(String dataNascimento) {
    try {
      final data = DateFormat('dd/MM/yyyy').parse(dataNascimento);
      final hoje = DateTime.now();
      int idade = hoje.year - data.year;
      if (hoje.month < data.month || (hoje.month == data.month && hoje.day < data.day)) idade--;
      return idade;
    } catch (e) {
      return 0;
    }
  }

  String _getPrimeiroNome(String? nomeCompleto) {
    if (nomeCompleto == null || nomeCompleto.isEmpty) return '...';
    return nomeCompleto.split(' ')[0];
  }

  String _toUpperCase(String? text) {
    return text?.toUpperCase().trim() ?? '';
  }

  Future<void> _verificarInscricoes() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (doc.exists) {
        final data = doc.data()!;
        final inscricoesSnapshot = await _firestore
            .collection('inscricoes')
            .where('status', isEqualTo: 'pendente')
            .get();

        final vagasTotal = data['vagas_disponiveis'] ?? 0;
        final inscricoesPendentes = inscricoesSnapshot.docs.length;
        final vagasRestantes = vagasTotal - inscricoesPendentes;

        setState(() {
          _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
          _vagasDisponiveis = vagasTotal;
          _vagasRestantes = vagasRestantes;
          _temVagas = vagasRestantes > 0;
          _idadeMinima = data['idade_minima'] ?? 5;
          _idadeMaxima = data['idade_maxima'] ?? 16;
          _recolherAssinatura = data['recolher_assinatura'] ?? true;
          _configuracoesCarregadas = true;
          _etapaValida[0] = _inscricoesAbertas && _temVagas;
          _carregando = false;
        });
      } else {
        setState(() {
          _inscricoesAbertas = false;
          _configuracoesCarregadas = true;
          _etapaValida[0] = false;
          _carregando = false;
        });
      }
    } catch (e) {
      setState(() {
        _inscricoesAbertas = false;
        _configuracoesCarregadas = true;
        _etapaValida[0] = false;
        _carregando = false;
        _mensagem = 'Erro ao verificar disponibilidade';
      });
    }
  }

  // 🔥 TERMO - ASSINATURA SÓ APARECE SE CONFIGURADA
  Widget _buildTermoElaborado() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp = isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TÍTULO DO TERMO
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'TERMO DE RESPONSABILIDADE',
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TEXTO DO TERMO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMaior) ...[
                  _buildTermoLinha('📌', 'Eu, $nomeAluno, declaro para os devidos fins que:'),
                  const SizedBox(height: 8),
                  _buildTermoLinha('1️⃣', 'ESTOU CIENTE de que a Capoeira é uma arte marcial que envolve atividades físicas de médio a alto impacto, podendo resultar em lesões.'),
                  _buildTermoLinha('2️⃣', 'ASSUMO total responsabilidade por qualquer dano físico que possa ocorrer durante a prática, isentando o Grupo UAI CAPOEIRA de qualquer ônus.'),
                  _buildTermoLinha('3️⃣', 'COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física.'),
                  _buildTermoLinha('4️⃣', 'AUTORIZO a participação na aula experimental de Capoeira.'),
                  _buildTermoLinha('5️⃣', 'CONCORDO com as filmagens e fotografias para fins institucionais.'),
                ] else ...[
                  _buildTermoLinha('📌', 'Eu, $nomeResp, responsável legal por $nomeAluno, declaro para os devidos fins que:'),
                  const SizedBox(height: 8),
                  _buildTermoLinha('1️⃣', 'AUTORIZO a participação do(a) menor acima identificado(a) na aula experimental de Capoeira oferecida pelo Grupo UAI CAPOEIRA.'),
                  _buildTermoLinha('2️⃣', 'ESTOU CIENTE dos riscos da prática esportiva e assumo total responsabilidade.'),
                  _buildTermoLinha('3️⃣', 'COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física do aluno.'),
                  _buildTermoLinha('4️⃣', 'CONCORDO com as filmagens e fotografias para fins institucionais.'),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // DATA E HORA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade900),
                const SizedBox(width: 8),
                Text(
                  'Data e hora: $dataHora',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 🔥 SÓ MOSTRA A ASSINATURA SE A CONFIGURAÇÃO MANDAR
          if (_recolherAssinatura) ...[
            // CAMPO DE ASSINATURA
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assinatura:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // ÁREA DA ASSINATURA
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final isMobile = screenWidth < 600;

                      return Center(
                        child: Container(
                          width: isMobile ? screenWidth * 0.8 : 300,
                          height: isMobile ? 60 : 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: _assinaturaUrl != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _assinaturaUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          )
                              : const Center(
                            child: Text(
                              '____________________________',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermoLinha(String bullet, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$bullet ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 GERAR TEXTO DO TERMO PARA SALVAR
  String _gerarTermoTexto() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp = isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    if (isMaior) {
      return '''
TERMO DE RESPONSABILIDADE

Eu, $nomeAluno, declaro para os devidos fins que:

1. ESTOU CIENTE de que a Capoeira é uma arte marcial que envolve atividades físicas de médio a alto impacto, podendo resultar em lesões.

2. ASSUMO total responsabilidade por qualquer dano físico que possa ocorrer durante a prática, isentando o Grupo UAI CAPOEIRA de qualquer ônus.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física.

4. AUTORIZO a participação na aula experimental de Capoeira.

5. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura: ${_assinaturaUrl != null ? '[ASSINATURA DIGITAL]' : '_____________________________'}
''';
    } else {
      return '''
TERMO DE RESPONSABILIDADE

Eu, $nomeResp, responsável legal por $nomeAluno, declaro para os devidos fins que:

1. AUTORIZO a participação do(a) menor acima identificado(a) na aula experimental de Capoeira oferecida pelo Grupo UAI CAPOEIRA.

2. ESTOU CIENTE dos riscos da prática esportiva e assumo total responsabilidade.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física do aluno.

4. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura do Responsável: ${_assinaturaUrl != null ? '[ASSINATURA DIGITAL]' : '_____________________________'}
''';
    }
  }

  Future<void> _abrirTelaAssinatura() async {
    final isMaior = _isMaiorIdade();
    final nomeResponsavel = isMaior
        ? _controllers['nome']!.text
        : _controllers['nome_responsavel']!.text;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignatureScreen(
          inscricaoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          nomeResponsavel: nomeResponsavel,
          nomeAluno: _controllers['nome']!.text,
          onConfirm: (imageUrl) {
            setState(() {
              _assinaturaUrl = imageUrl;
              _validarEtapaFinal();
            });
          },
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _validarEtapaFinal();
      });
    }
  }

  Future<void> _enviarInscricao() async {
    setState(() => _enviando = true);

    try {
      final configDoc = await _firestore.collection('configuracoes').doc('inscricoes').get();
      final config = configDoc.data() ?? {};
      final vagasDisponiveis = config['vagas_disponiveis'] ?? 0;

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      if (vagasDisponiveis > 0 && inscricoesSnapshot.docs.length >= vagasDisponiveis) {
        setState(() {
          _mensagem = 'Desculpe, as vagas para inscrições estão esgotadas.';
          _enviando = false;
        });
        return;
      }

      final isMaior = _isMaiorIdade();
      final nomeResponsavel = isMaior ? _controllers['nome']!.text : _controllers['nome_responsavel']!.text;

      Map<String, dynamic> dados = {
        'nome': _toUpperCase(_controllers['nome']!.text),
        'apelido': _toUpperCase(_controllers['apelido']!.text),
        'data_nascimento': _controllers['data_nascimento']!.text.trim(),
        'sexo': _sexo,
        'contato_aluno': _controllers['contato_aluno']!.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'autorizacao': _autorizacao,
        'termo_autorizacao': _gerarTermoTexto(),
        'status': 'pendente',
        'data_inscricao': FieldValue.serverTimestamp(),
        'is_maior_idade': isMaior,
        'assinatura_recolhida': _recolherAssinatura,
      };

      if (_assinaturaUrl != null) {
        dados['assinatura_url'] = _assinaturaUrl;
      }

      if (!isMaior) {
        dados['nome_responsavel'] = _toUpperCase(_controllers['nome_responsavel']!.text);
        dados['contato_responsavel'] = _controllers['contato_responsavel']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      } else {
        dados['nome_responsavel'] = _toUpperCase(_controllers['nome']!.text);
        dados['contato_responsavel'] = _controllers['contato_aluno']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      }

      if (_controllers['cpf']!.text.trim().isNotEmpty) {
        dados['cpf'] = _controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      }

      List<String> enderecoParts = [];
      if (_controllers['rua']!.text.isNotEmpty) {
        String ruaNumero = _toUpperCase(_controllers['rua']!.text);
        if (_controllers['numero']!.text.isNotEmpty) ruaNumero += ' - ${_toUpperCase(_controllers['numero']!.text)}';
        enderecoParts.add(ruaNumero);
      }
      if (_controllers['bairro']!.text.isNotEmpty) enderecoParts.add(_toUpperCase(_controllers['bairro']!.text));
      if (_controllers['cidade']!.text.isNotEmpty) enderecoParts.add(_toUpperCase(_controllers['cidade']!.text));
      dados['endereco'] = enderecoParts.join(', ');

      await _firestore.collection('inscricoes').add(dados);

      final novoTotal = inscricoesSnapshot.docs.length + 1;
      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'total_inscricoes': novoTotal,
      }, SetOptions(merge: true));

      if (mounted) _mostrarDialogSucesso(dados);
    } catch (e) {
      setState(() {
        _mensagem = 'Erro ao enviar inscrição: $e';
        _enviando = false;
      });
    }
  }

  void _mostrarDialogSucesso(Map<String, dynamic> dados) {
    final isMaior = dados['is_maior_idade'] ?? false;
    final nomeResponsavel = _getPrimeiroNome(dados['nome_responsavel']);
    final nomeAluno = _getPrimeiroNome(dados['nome']);
    final idadeAluno = _calcularIdade(dados['data_nascimento']);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade700, Colors.green.shade500],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle, color: Colors.white, size: 60),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'INSCRIÇÃO REALIZADA!',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.waving_hand, color: Colors.blue, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              isMaior ? 'Olá, $nomeAluno!' : 'Olá, $nomeResponsavel!',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isMaior ? 'Sua inscrição foi recebida com sucesso!' : 'Inscrição de $nomeAluno recebida com sucesso!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.blue.shade900),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildInfoDialog('Aluno', dados['nome']),
                            _buildInfoDialog('Idade', '$idadeAluno anos'),
                            _buildInfoDialog('Contato', dados['contato_aluno']),
                            if (!isMaior) _buildInfoDialog('Responsável', dados['nome_responsavel']),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_recolherAssinatura)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _assinaturaUrl != null ? Colors.green.shade50 : Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _assinaturaUrl != null ? Icons.draw : Icons.gavel,
                                color: _assinaturaUrl != null ? Colors.green.shade700 : Colors.purple.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _assinaturaUrl != null
                                      ? '✅ Assinatura digital registrada'
                                      : '📝 Termo de responsabilidade aceito',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _assinaturaUrl != null ? Colors.green.shade800 : Colors.purple.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.amber),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('🔔 Próximos passos:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  SizedBox(height: 4),
                                  Text('1️⃣ Aguarde contato do professor (até 48h)\n2️⃣ Agendamento da aula experimental', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('FINALIZAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoDialog(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value ?? 'Não informado', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  void _proximaEtapa() {
    if (_currentStep < 5 && _etapaValida[_currentStep] == true) {
      setState(() => _currentStep++);
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _etapaAnterior() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  // 🔙 FUNÇÃO PARA CONTROLAR O BOTÃO DE VOLTAR
  Future<bool> _onWillPop() async {
    // Se estiver na primeira etapa, pergunta se quer sair
    if (_currentStep == 0) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.exit_to_app,
                  color: Colors.orange.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sair da inscrição?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Se você sair agora, os dados preenchidos serão perdidos.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'CONTINUAR',
                style: TextStyle(color: Colors.green),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('SAIR'),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        Navigator.pop(context); // Volta para a LandingPage
        return false; // Não deixa o sistema fechar
      }
      return false; // Não sai da tela
    }
    // Se não estiver na primeira etapa, volta uma etapa
    else {
      _etapaAnterior();
      return false; // Não deixa o sistema fechar
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_inscricoesAbertas) {
      return WillPopScope(
        onWillPop: () async {
          Navigator.pop(context); // Volta para a LandingPage
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('📝 Inscrição'),
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 20),
                  Text(
                    'Inscrições Fechadas',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _mensagem.isNotEmpty
                        ? _mensagem
                        : 'No momento não estamos aceitando novas inscrições.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📝 Inscrição para Aula Experimental'),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 6,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        body: _enviando
            ? const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Enviando sua inscrição...'),
            ],
          ),
        )
            : Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStepWelcome(),
                  _buildStepAluno(),
                  _buildStepContato(),
                  _buildStepEndereco(),
                  _buildStepCpf(),
                  _buildStepRevisao(),
                ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _temVagas ? Colors.blue.shade50 : Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _temVagas ? Icons.waving_hand : Icons.warning,
              size: 80,
              color: _temVagas ? Colors.blue : Colors.red,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _temVagas ? 'Olá! Vamos começar?' : 'Que pena!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _temVagas ? Colors.black87 : Colors.red.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _temVagas
                ? 'Precisamos de algumas informações para oferecer a melhor experiência.'
                : 'No momento todas as vagas estão preenchidas.',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 🔥 NOVO BOTÃO DE REGIMENTO INTERNO
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.menu_book,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  title: const Text(
                    'REGIMENTO INTERNO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: const Text(
                    'Leia as regras e diretrizes do grupo',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const RegimentoDialog(),
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Leia atentamente antes de prosseguir',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_configuracoesCarregadas)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _temVagas ? Colors.blue.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _temVagas ? Colors.blue.shade200 : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _temVagas ? Icons.info : Icons.error,
                    color: _temVagas ? Colors.blue.shade900 : Colors.red.shade900,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _temVagas
                              ? '✅ Aceitamos alunos de $_idadeMinima a $_idadeMaxima anos'
                              : '❌ Vagas esgotadas!',
                          style: TextStyle(
                            fontSize: 14,
                            color: _temVagas ? Colors.blue.shade900 : Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_temVagas)
                          Text(
                            '🎯 $_vagasRestantes vagas disponíveis',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepAluno() {
    final idade = _controllers['data_nascimento']!.text.isNotEmpty
        ? _calcularIdade(_controllers['data_nascimento']!.text)
        : 0;
    final idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 DADOS DO ALUNO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quem vai praticar capoeira?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            _controllers['nome']!,
            'Nome Completo *',
            validator: (value) => value == null || value.isEmpty
                ? 'Campo obrigatório'
                : (!_validarNome(value) ? 'Use apenas letras' : null),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            _controllers['apelido']!,
            'Apelido *',
            validator: (value) => value == null || value.isEmpty
                ? 'Campo obrigatório'
                : (!_validarNome(value) ? 'Use apenas letras' : null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDateField(_controllers['data_nascimento']!, 'Data Nasc. *'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sexo,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Sexo *')),
                    DropdownMenuItem(value: 'MASCULINO', child: Text('MASCULINO')),
                    DropdownMenuItem(value: 'FEMININO', child: Text('FEMININO')),
                  ],
                  onChanged: (v) {
                    setState(() => _sexo = v);
                    _validarEtapa1();
                  },
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  validator: (v) => v == null ? 'Campo obrigatório' : null,
                ),
              ),
            ],
          ),
          if (_controllers['data_nascimento']!.text.isNotEmpty && !idadeValida)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '❌ Idade não permitida. Aceitamos de $_idadeMinima a $_idadeMaxima anos.',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepContato() {
    final isMaior = _isMaiorIdade();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📞 CONTATO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isMaior ? 'Como vamos falar com você?' : 'Como vamos falar com vocês?',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildPhoneField(_controllers['contato_aluno']!, 'Telefone do Aluno *'),
          const SizedBox(height: 16),
          if (!isMaior) ...[
            _buildTextField(
              _controllers['nome_responsavel']!,
              'Nome do Responsável *',
              validator: (value) => value == null || value.isEmpty
                  ? 'Campo obrigatório'
                  : (!_validarNome(value) ? 'Use apenas letras' : null),
            ),
            const SizedBox(height: 16),
            _buildPhoneField(_controllers['contato_responsavel']!, 'Telefone do Responsável *'),
          ],
        ],
      ),
    );
  }

  Widget _buildStepEndereco() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🏠 ENDEREÇO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Onde vocês moram?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            _controllers['rua']!,
            'Rua *',
            validator: (value) => value == null || value.isEmpty
                ? 'Campo obrigatório'
                : (!_validarNome(value) ? 'Use apenas letras' : null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  _controllers['numero']!,
                  'Número *',
                  isNumberOnly: true,
                  maxLength: 5,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Campo obrigatório'
                      : (value.length > 5 ? 'Máximo 5 dígitos' : null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  _controllers['bairro']!,
                  'Bairro *',
                  validator: (value) => value == null || value.isEmpty
                      ? 'Campo obrigatório'
                      : (!_validarNome(value) ? 'Use apenas letras' : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(_controllers['cidade']!, 'Cidade *'),
        ],
      ),
    );
  }

  Widget _buildStepCpf() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📄 DOCUMENTO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'CPF (opcional)',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'O CPF é opcional, mas ajuda no cadastro futuro.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildCpfField(),
        ],
      ),
    );
  }

  Widget _buildStepRevisao() {
    final isMaior = _isMaiorIdade();
    final nomeResponsavel = isMaior
        ? _controllers['nome']!.text
        : _controllers['nome_responsavel']!.text;
    final nomeAluno = _controllers['nome']!.text;
    final idadeAluno = _calcularIdade(_controllers['data_nascimento']!.text);
    final precisaAssinar = _recolherAssinatura && _assinaturaUrl == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TÍTULO
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '✅ REVISÃO E AUTORIZAÇÃO',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // CARD DE RESUMO DOS DADOS
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildResumoLinhaIcon(
                    Icons.person,
                    'Aluno',
                    nomeAluno,
                    Colors.blue,
                  ),
                  const Divider(height: 16),
                  _buildResumoLinhaIcon(
                    Icons.cake,
                    'Idade',
                    '$idadeAluno anos',
                    Colors.orange,
                  ),
                  const Divider(height: 16),
                  _buildResumoLinhaIcon(
                    Icons.phone,
                    'Contato',
                    _controllers['contato_aluno']!.text,
                    Colors.green,
                  ),
                  if (!isMaior) ...[
                    const Divider(height: 16),
                    _buildResumoLinhaIcon(
                      Icons.person_outline,
                      'Responsável',
                      nomeResponsavel,
                      Colors.purple,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // TERMO DE RESPONSABILIDADE
          _buildTermoElaborado(),
          const SizedBox(height: 16),

          // CHECKBOX DE AUTORIZAÇÃO
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: CheckboxListTile(
              value: _autorizacao,
              onChanged: (value) {
                setState(() {
                  _autorizacao = value ?? false;
                  _validarEtapaFinal();
                });
              },
              title: Text(
                isMaior
                    ? '☑️ Li e concordo com todos os termos acima'
                    : '☑️ Li e concordo com todos os termos acima como responsável',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.green,
              checkboxShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ALERTA SE PRECISAR ASSINAR
          if (precisaAssinar)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ Você precisa assinar o termo antes de finalizar',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // BOTÃO DE ASSINATURA
          if (_recolherAssinatura) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _assinaturaUrl == null ? _abrirTelaAssinatura : null,
                icon: Icon(
                  _assinaturaUrl == null ? Icons.draw : Icons.check_circle,
                  color: Colors.white,
                  size: 28,
                ),
                label: Text(
                  _assinaturaUrl == null ? '✍️ ASSINAR TERMO' : '✅ TERMO ASSINADO',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  _assinaturaUrl == null ? Colors.blue.shade900 : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoLinhaIcon(IconData icon, String label, String valor, Color cor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: cor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                valor,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final bool podeAvancar = _etapaValida[_currentStep] ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _etapaAnterior,
                icon: const Icon(Icons.arrow_back),
                label: const Text('VOLTAR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: _currentStep == 0 ? 2 : 1,
            child: ElevatedButton.icon(
              onPressed: _currentStep == 5
                  ? (podeAvancar ? _enviarInscricao : null)
                  : (podeAvancar ? _proximaEtapa : null),
              icon: Icon(_currentStep == 5 ? Icons.send : Icons.arrow_forward),
              label: Text(
                _currentStep == 5 ? 'ENVIAR INSCRIÇÃO' : 'CONTINUAR',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label, {
        bool isNumberOnly = false,
        int? maxLength,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorText: validator != null ? validator(controller.text) : null,
        counterText: '',
      ),
      keyboardType: isNumberOnly ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumberOnly
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxLength ?? 5)]
          : [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ\s]'))],
      textCapitalization: TextCapitalization.characters,
      onChanged: (value) {
        if (_currentStep == 1) _validarEtapa1();
        if (_currentStep == 2) _validarEtapa2();
        if (_currentStep == 3) _validarEtapa3();
      },
    );
  }

  Widget _buildPhoneField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: '(00) 00000-0000',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorText:
        controller.text.isNotEmpty && controller.text.length < 14 ? 'Telefone incompleto' : null,
      ),
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _PhoneInputFormatter(),
      ],
      onChanged: (value) {
        if (_currentStep == 2) _validarEtapa2();
      },
    );
  }

  Widget _buildCpfField() {
    return TextFormField(
      controller: _controllers['cpf'],
      decoration: InputDecoration(
        labelText: 'CPF (opcional)',
        hintText: '000.000.000-00',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _CpfInputFormatter(),
      ],
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorText: controller.text.isEmpty ? 'Campo obrigatório' : null,
      ),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
    );
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 3650)),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
        _validarEtapa1();
      });
    }
  }
}

// FORMATTERS
class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.length <= 6) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    } else if (digits.length <= 9) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    } else {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 2) {
      formatted = '($digits';
    } else if (digits.length <= 6) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else if (digits.length <= 10) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    } else {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}