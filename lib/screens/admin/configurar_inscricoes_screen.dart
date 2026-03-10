import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gerenciar_inscricoes_screen.dart';

class ConfigurarInscricoesScreen extends StatefulWidget {
  const ConfigurarInscricoesScreen({super.key});

  @override
  State<ConfigurarInscricoesScreen> createState() => _ConfigurarInscricoesScreenState();
}

class _ConfigurarInscricoesScreenState extends State<ConfigurarInscricoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _inscricoesAbertas = false;
  int _vagasDisponiveis = 0;
  int _totalInscricoes = 0;

  // 🔥 CAMPOS DE IDADE
  int _idadeMinima = 5;
  int _idadeMaxima = 16;

  // 🔥 NOVO: OPÇÃO DE ASSINATURA
  bool _recolherAssinatura = true;

  // Controladores
  final TextEditingController _idadeMinimaController = TextEditingController();
  final TextEditingController _idadeMaximaController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracao();
  }

  @override
  void dispose() {
    _idadeMinimaController.dispose();
    _idadeMaximaController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfiguracao() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
          _vagasDisponiveis = data['vagas_disponiveis'] ?? 0;
          _totalInscricoes = data['total_inscricoes'] ?? 0;

          // 🔥 CARREGAR IDADES
          _idadeMinima = data['idade_minima'] ?? 5;
          _idadeMaxima = data['idade_maxima'] ?? 16;

          // 🔥 CARREGAR OPÇÃO DE ASSINATURA
          _recolherAssinatura = data['recolher_assinatura'] ?? true;

          // Atualizar controladores
          _idadeMinimaController.text = _idadeMinima.toString();
          _idadeMaximaController.text = _idadeMaxima.toString();
        });
      }

      // Carrega total atual de inscrições pendentes
      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      setState(() {
        _totalInscricoes = inscricoesSnapshot.docs.length;
        _carregando = false;
      });
    } catch (e) {
      _mostrarErro('Erro ao carregar: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _salvarConfiguracao() async {
    setState(() => _salvando = true);

    try {
      // 🔥 VALIDAR IDADES
      final idadeMin = int.tryParse(_idadeMinimaController.text) ?? 0;
      final idadeMax = int.tryParse(_idadeMaximaController.text) ?? 0;

      if (idadeMin < 1) {
        _mostrarErro('Idade mínima deve ser maior que 0');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax < idadeMin) {
        _mostrarErro('Idade máxima não pode ser menor que a idade mínima');
        setState(() => _salvando = false);
        return;
      }

      if (idadeMax > 120) {
        _mostrarErro('Idade máxima inválida');
        setState(() => _salvando = false);
        return;
      }

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'inscricoes_abertas': _inscricoesAbertas,
        'vagas_disponiveis': _vagasDisponiveis,
        'total_inscricoes': _totalInscricoes,
        'idade_minima': idadeMin,
        'idade_maxima': idadeMax,
        'recolher_assinatura': _recolherAssinatura,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configurações salvas!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ Configurar Inscrições'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _salvando ? 'SALVANDO...' : 'SALVAR',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CARD DE STATUS
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STATUS DAS INSCRIÇÕES',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      'Inscrições Abertas',
                      style: TextStyle(fontSize: 16),
                    ),
                    subtitle: Text(
                      _inscricoesAbertas
                          ? 'Pais podem se inscrever'
                          : 'Inscrições fechadas',
                      style: TextStyle(
                        color: _inscricoesAbertas ? Colors.green : Colors.red,
                      ),
                    ),
                    value: _inscricoesAbertas,
                    onChanged: (value) {
                      setState(() {
                        _inscricoesAbertas = value;
                      });
                    },
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 🔥 NOVO CARD DE ASSINATURA DIGITAL
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.draw, color: Colors.purple.shade900),
                      const SizedBox(width: 8),
                      const Text(
                        'ASSINATURA DIGITAL',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      'Recolher Assinatura',
                      style: TextStyle(fontSize: 16),
                    ),
                    subtitle: Text(
                      _recolherAssinatura
                          ? '✅ Usuário precisará assinar digitalmente'
                          : '❌ Inscrição sem assinatura digital',
                      style: TextStyle(
                        color: _recolherAssinatura ? Colors.green : Colors.red,
                      ),
                    ),
                    value: _recolherAssinatura,
                    onChanged: (value) {
                      setState(() {
                        _recolherAssinatura = value;
                      });
                    },
                    activeColor: Colors.purple,
                    secondary: Icon(
                      _recolherAssinatura ? Icons.draw : Icons.block,
                      color: _recolherAssinatura ? Colors.purple : Colors.grey,
                    ),
                  ),
                  if (_recolherAssinatura)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.purple.shade900, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'O usuário deverá desenhar a assinatura na tela antes de finalizar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // CARD DE FAIXA ETÁRIA
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cake, color: Colors.orange.shade900),
                      const SizedBox(width: 8),
                      const Text(
                        'FAIXA ETÁRIA ACEITA',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _idadeMinimaController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Idade Mínima',
                            hintText: 'Ex: 5',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.child_care, size: 20),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _idadeMinima = int.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _idadeMaximaController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Idade Máxima',
                            hintText: 'Ex: 16',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.elderly, size: 20),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _idadeMaxima = int.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _idadeMinima <= _idadeMaxima
                          ? Colors.orange.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _idadeMinima <= _idadeMaxima
                              ? Icons.info_outline
                              : Icons.warning_amber,
                          color: _idadeMinima <= _idadeMaxima
                              ? Colors.orange.shade900
                              : Colors.red.shade900,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _idadeMinima <= _idadeMaxima
                                ? 'Serão aceitos alunos com idade entre $_idadeMinima e $_idadeMaxima anos'
                                : '⚠️ Idade mínima não pode ser maior que a idade máxima!',
                            style: TextStyle(
                              fontSize: 12,
                              color: _idadeMinima <= _idadeMaxima
                                  ? Colors.orange.shade900
                                  : Colors.red.shade900,
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
          ),

          const SizedBox(height: 16),

          // CARD DE VAGAS
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTROLE DE VAGAS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _vagasDisponiveis.toString(),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Vagas Disponíveis',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _vagasDisponiveis = int.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$_totalInscricoes',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const Text(
                              'Inscrições\nPendentes',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_vagasDisponiveis > 0 && _totalInscricoes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _totalInscricoes / _vagasDisponiveis,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _totalInscricoes > _vagasDisponiveis ? Colors.red : Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(_totalInscricoes / _vagasDisponiveis * 100).toStringAsFixed(1)}% das vagas preenchidas',
                            style: TextStyle(
                              fontSize: 12,
                              color: _totalInscricoes > _vagasDisponiveis ? Colors.red : Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_totalInscricoes > _vagasDisponiveis && _vagasDisponiveis > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠️ ${_totalInscricoes - _vagasDisponiveis} inscrições excedem as vagas',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // CARD DE RESUMO
          Card(
            elevation: 2,
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.summarize, color: Colors.green.shade900),
                      const SizedBox(width: 8),
                      const Text(
                        'RESUMO DAS CONFIGURAÇÕES',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildResumoRow(
                    label: 'Status',
                    value: _inscricoesAbertas ? 'ABERTAS' : 'FECHADAS',
                    color: _inscricoesAbertas ? Colors.green : Colors.red,
                  ),
                  _buildResumoRow(
                    label: 'Assinatura',
                    value: _recolherAssinatura ? 'SIM' : 'NÃO',
                    color: Colors.purple,
                  ),
                  _buildResumoRow(
                    label: 'Vagas',
                    value: '$_vagasDisponiveis vagas',
                    color: Colors.blue,
                  ),
                  _buildResumoRow(
                    label: 'Inscrições',
                    value: '$_totalInscricoes pendentes',
                    color: Colors.orange,
                  ),
                  _buildResumoRow(
                    label: 'Idade',
                    value: '$_idadeMinima a $_idadeMaxima anos',
                    color: Colors.purple,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // CARD DE INFORMAÇÕES
          Card(
            elevation: 2,
            color: Colors.amber.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.amber.shade900),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gerenciar Inscrições',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vá para "Gerenciar Inscrições" para ver a lista de candidatos e aprovar/recusar',
                          style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // BOTÃO PARA VER INSCRIÇÕES
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GerenciarInscricoesScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.list_alt),
              label: const Text('VER INSCRIÇÕES PENDENTES'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoRow({
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}