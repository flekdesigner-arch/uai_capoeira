import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'gerenciar_inscricoes_screen.dart';

class ConfigurarInscricoesScreen extends StatefulWidget {
  const ConfigurarInscricoesScreen({super.key});

  @override
  State<ConfigurarInscricoesScreen> createState() =>
      _ConfigurarInscricoesScreenState();
}

class _ConfigurarInscricoesScreenState
    extends State<ConfigurarInscricoesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _inscricoesAbertas = false;
  int _vagasDisponiveis = 0;
  int _totalInscricoes = 0;

  int _idadeMinima = 5;
  int _idadeMaxima = 16;

  bool _recolherAssinatura = true;

  final TextEditingController _idadeMinimaController = TextEditingController();
  final TextEditingController _idadeMaximaController = TextEditingController();
  final TextEditingController _vagasController = TextEditingController();

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
    _vagasController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfiguracao() async {
    try {
      final doc =
      await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (doc.exists) {
        final data = doc.data()!;

        _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
        _vagasDisponiveis = data['vagas_disponiveis'] ?? 0;
        _totalInscricoes = data['total_inscricoes'] ?? 0;
        _idadeMinima = data['idade_minima'] ?? 5;
        _idadeMaxima = data['idade_maxima'] ?? 16;
        _recolherAssinatura = data['recolher_assinatura'] ?? true;
      }

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      _totalInscricoes = inscricoesSnapshot.docs.length;
      _idadeMinimaController.text = _idadeMinima.toString();
      _idadeMaximaController.text = _idadeMaxima.toString();
      _vagasController.text = _vagasDisponiveis.toString();

      if (mounted) {
        setState(() => _carregando = false);
      }
    } catch (e) {
      if (mounted) {
        _mostrarErro('Erro ao carregar: $e');
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _salvarConfiguracao() async {
    setState(() => _salvando = true);

    try {
      final idadeMin = int.tryParse(_idadeMinimaController.text) ?? 0;
      final idadeMax = int.tryParse(_idadeMaximaController.text) ?? 0;
      final vagas = int.tryParse(_vagasController.text) ?? 0;

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

      if (vagas < 0) {
        _mostrarErro('O número de vagas não pode ser negativo');
        setState(() => _salvando = false);
        return;
      }

      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'inscricoes_abertas': _inscricoesAbertas,
        'vagas_disponiveis': vagas,
        'total_inscricoes': _totalInscricoes,
        'idade_minima': idadeMin,
        'idade_maxima': idadeMax,
        'recolher_assinatura': _recolherAssinatura,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      });

      setState(() {
        _idadeMinima = idadeMin;
        _idadeMaxima = idadeMax;
        _vagasDisponiveis = vagas;
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
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  int get _vagasRestantes {
    final restantes = _vagasDisponiveis - _totalInscricoes;
    return restantes < 0 ? 0 : restantes;
  }

  double get _percentualVagas {
    if (_vagasDisponiveis <= 0) return 0;
    return (_totalInscricoes / _vagasDisponiveis).clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: CircularProgressIndicator(color: Colors.red.shade900),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Configurar Inscrições',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    children: [
                      _buildHeroCard(),
                      const SizedBox(height: 14),
                      _buildStatusCards(),
                      const SizedBox(height: 14),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildMainSettingsColumn()),
                            const SizedBox(width: 14),
                            Expanded(child: _buildResumoColumn()),
                          ],
                        )
                      else ...[
                        _buildMainSettingsColumn(),
                        const SizedBox(height: 14),
                        _buildResumoColumn(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR CONFIGURAÇÕES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(
              Icons.app_registration_rounded,
              color: Colors.white,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Inscrições da Aula Experimental',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Controle vagas, idade permitida, assinatura digital e status público do formulário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.80),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 680 ? 2 : 4;
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;

        final cards = [
          _miniStat(
            title: 'Status',
            value: _inscricoesAbertas ? 'Aberta' : 'Fechada',
            icon: _inscricoesAbertas
                ? Icons.check_circle_rounded
                : Icons.cancel_rounded,
            color: _inscricoesAbertas ? Colors.green : Colors.red,
          ),
          _miniStat(
            title: 'Vagas',
            value: '$_vagasDisponiveis',
            icon: Icons.event_seat_rounded,
            color: Colors.blue,
          ),
          _miniStat(
            title: 'Pendentes',
            value: '$_totalInscricoes',
            icon: Icons.pending_actions_rounded,
            color: Colors.orange,
          ),
          _miniStat(
            title: 'Restam',
            value: '$_vagasRestantes',
            icon: Icons.how_to_reg_rounded,
            color: Colors.purple,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      },
    );
  }

  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(color: color),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSettingsColumn() {
    return Column(
      children: [
        _buildSwitchCard(
          icon: Icons.public_rounded,
          title: 'Status das inscrições',
          subtitle: _inscricoesAbertas
              ? 'O formulário público está aceitando inscrições.'
              : 'O formulário público está fechado.',
          color: _inscricoesAbertas ? Colors.green : Colors.red,
          value: _inscricoesAbertas,
          onChanged: (value) => setState(() => _inscricoesAbertas = value),
        ),
        const SizedBox(height: 14),
        _buildSwitchCard(
          icon: Icons.draw_rounded,
          title: 'Assinatura digital',
          subtitle: _recolherAssinatura
              ? 'O responsável precisará assinar o termo digitalmente.'
              : 'A inscrição será concluída sem assinatura digital.',
          color: Colors.purple,
          value: _recolherAssinatura,
          onChanged: (value) => setState(() => _recolherAssinatura = value),
        ),
        const SizedBox(height: 14),
        _buildAgeCard(),
        const SizedBox(height: 14),
        _buildVagasCard(),
      ],
    );
  }

  Widget _buildResumoColumn() {
    return Column(
      children: [
        _buildResumoCard(),
        const SizedBox(height: 14),
        _buildInfoCard(),
        const SizedBox(height: 14),
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
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('VER INSCRIÇÕES PENDENTES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: color),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: color,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAgeCard() {
    final valido = _idadeMinima <= _idadeMaxima;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: valido ? Colors.orange : Colors.red),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.cake_rounded,
            title: 'Faixa etária aceita',
            color: valido ? Colors.orange.shade900 : Colors.red.shade800,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 460;

              final fields = [
                _numberField(
                  controller: _idadeMinimaController,
                  label: 'Idade mínima',
                  icon: Icons.child_care_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMinima = int.tryParse(value) ?? 0);
                  },
                ),
                _numberField(
                  controller: _idadeMaximaController,
                  label: 'Idade máxima',
                  icon: Icons.elderly_rounded,
                  onChanged: (value) {
                    setState(() => _idadeMaxima = int.tryParse(value) ?? 0);
                  },
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 10),
                    fields[1],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _noticeBox(
            icon: valido ? Icons.info_outline_rounded : Icons.warning_rounded,
            color: valido ? Colors.orange.shade900 : Colors.red.shade800,
            text: valido
                ? 'Serão aceitos alunos com idade entre $_idadeMinima e $_idadeMaxima anos.'
                : 'Idade mínima não pode ser maior que a idade máxima.',
          ),
        ],
      ),
    );
  }

  Widget _buildVagasCard() {
    final estourou = _vagasDisponiveis > 0 && _totalInscricoes > _vagasDisponiveis;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: estourou ? Colors.red : Colors.blue),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.event_seat_rounded,
            title: 'Controle de vagas',
            color: estourou ? Colors.red.shade800 : Colors.blue.shade800,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: _vagasController,
                  label: 'Vagas disponíveis',
                  icon: Icons.event_available_rounded,
                  onChanged: (value) {
                    setState(() {
                      _vagasDisponiveis = int.tryParse(value) ?? 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 104,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  children: [
                    Text(
                      '$_totalInscricoes',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const Text(
                      'Pendentes',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_vagasDisponiveis > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: _percentualVagas,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  estourou ? Colors.red : Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_percentualVagas * 100).toStringAsFixed(1)}% das vagas preenchidas',
              style: TextStyle(
                color: estourou ? Colors.red : Colors.green.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (estourou) ...[
            const SizedBox(height: 10),
            _noticeBox(
              icon: Icons.warning_rounded,
              color: Colors.red.shade800,
              text:
              '${_totalInscricoes - _vagasDisponiveis} inscrições excedem as vagas configuradas.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: Colors.green),
      child: Column(
        children: [
          _sectionHeader(
            icon: Icons.summarize_rounded,
            title: 'Resumo das configurações',
            color: Colors.green.shade800,
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
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: Colors.amber),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: Colors.amber.shade900, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Para aprovar, recusar ou acompanhar candidatos, acesse a lista de inscrições pendentes.',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.red.shade900),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
        ),
      ),
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.25,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration({required Color color}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withOpacity(0.10)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}
