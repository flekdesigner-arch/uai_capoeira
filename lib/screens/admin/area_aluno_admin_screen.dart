import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/services/site_config_service.dart';

class AreaAlunoAdminScreen extends StatefulWidget {
  const AreaAlunoAdminScreen({super.key});

  @override
  State<AreaAlunoAdminScreen> createState() => _AreaAlunoAdminScreenState();
}

class _AreaAlunoAdminScreenState extends State<AreaAlunoAdminScreen>
    with SingleTickerProviderStateMixin {
  final SiteConfigService _configService = SiteConfigService();

  late final TabController _tabController;

  bool _carregando = true;
  bool _salvando = false;

  Map<String, dynamic> _config = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    final config = await _configService.carregarConfiguracoesAreaAluno();

    if (!mounted) return;

    setState(() {
      _config = config;
      _carregando = false;
    });
  }

  bool _getBool(String key, {bool padrao = false}) {
    final value = _config[key];
    if (value is bool) return value;
    return padrao;
  }

  String _getString(String key, {String padrao = ''}) {
    final value = _config[key];
    if (value == null) return padrao;
    return value.toString();
  }

  Future<void> _salvarCampo(String key, dynamic value) async {
    setState(() {
      _config[key] = value;
      _salvando = true;
    });

    try {
      await _configService.salvarConfiguracoesAreaAluno(_config);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configuração salva'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando = false;
        });
      }
    }
  }

  Future<void> _editarTexto({
    required String campo,
    required String titulo,
    required String label,
    int maxLines = 2,
  }) async {
    final controller = TextEditingController(text: _getString(campo));

    final novoTexto = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(titulo),
          content: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text('SALVAR'),
            ),
          ],
        );
      },
    );

    if (novoTexto != null) {
      await _salvarCampo(campo, novoTexto);
    }
  }

  Future<void> _alterarVisibilidadeAreaAluno(bool value) async {
    setState(() {
      _config['visivel_site'] = value;
      _salvando = true;
    });

    try {
      await _configService.alterarVisibilidadeAreaAluno(value);
      await _configService.salvarConfiguracoesAreaAluno(_config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? '✅ Área do Aluno ficará visível no site'
                  : '✅ Área do Aluno foi ocultada do site',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao alterar visibilidade: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Área do Aluno',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_salvando)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Center(
                child: SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recarregar',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            width: double.infinity,
            color: Colors.red.shade900,
            child: SafeArea(
              top: false,
              bottom: false,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_rounded), text: 'Geral'),
                  Tab(icon: Icon(Icons.security_rounded), text: 'Segurança'),
                  Tab(icon: Icon(Icons.badge_rounded), text: 'Dados'),
                  Tab(icon: Icon(Icons.edit_note_rounded), text: 'Textos'),
                  Tab(icon: Icon(Icons.assignment_turned_in_rounded), text: 'Solicitações'),
                  Tab(icon: Icon(Icons.history_rounded), text: 'Logs'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildTabGeral(),
          _buildTabSeguranca(),
          _buildTabDados(),
          _buildTabTextos(),
          _buildTabSolicitacoes(),
          _buildTabLogs(),
        ],
      ),
    );
  }

  Widget _buildTabGeral() {
    final visivel = _getBool('visivel_site');

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _buildResumoRapido(),
          const SizedBox(height: 14),
          _buildCard(
            icon: Icons.visibility_rounded,
            title: 'Visibilidade no site',
            subtitle: visivel
                ? 'A Área do Aluno está aparecendo no site público.'
                : 'A Área do Aluno está oculta no site público.',
            color: visivel ? Colors.green : Colors.grey,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar Área do Aluno no site'),
                subtitle: const Text('Ativa ou oculta a entrada pública no site.'),
                value: visivel,
                activeColor: Colors.green,
                onChanged: _alterarVisibilidadeAreaAluno,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildCard(
            icon: Icons.fact_check_rounded,
            title: 'Status da implementação',
            subtitle: 'Acompanhe o que já está pronto e o que vem depois.',
            color: Colors.indigo,
            children: [
              _buildChecklistItem('Login público com Cloud Function', true),
              _buildChecklistItem('Logs de acesso e erro', true),
              _buildChecklistItem('Dashboard inicial do aluno', true),
              _buildChecklistItem('Solicitações de alteração', true),
              _buildChecklistItem('Frequência detalhada no portal', true),
              _buildChecklistItem('Certificados e eventos participados', true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSeguranca() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildCard(
            icon: Icons.security_rounded,
            title: 'Segurança de acesso',
            subtitle: 'Controle quem pode entrar na Área do Aluno.',
            color: Colors.blue,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aceitar somente alunos ativos'),
                subtitle: const Text('Bloqueia alunos com status INATIVO(A).'),
                value: _getBool('aceitar_apenas_ativos', padrao: true),
                activeColor: Colors.blue,
                onChanged: (value) => _salvarCampo('aceitar_apenas_ativos', value),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exigir confirmação por telefone'),
                subtitle: const Text(
                  'Além da data e iniciais, pede os últimos 4 dígitos do contato.',
                ),
                value: _getBool('exigir_telefone_confirmacao', padrao: true),
                activeColor: Colors.blue,
                onChanged: (value) =>
                    _salvarCampo('exigir_telefone_confirmacao', value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            icon: Icons.privacy_tip_rounded,
            color: Colors.blue,
            title: 'Como a validação funciona',
            text:
            'O site não consulta a coleção de alunos diretamente. Ele chama uma Cloud Function, que valida data, iniciais e telefone usando o Admin SDK. Isso permite controlar melhor os dados retornados ao aluno.',
          ),
          const SizedBox(height: 14),
          _buildCard(
            icon: Icons.password_rounded,
            title: 'Modelo de identificação',
            subtitle: 'Campos usados na entrada pública.',
            color: Colors.teal,
            children: const [
              _ReadOnlyLine(
                title: 'Data de nascimento',
                value: 'Obrigatório',
              ),
              Divider(),
              _ReadOnlyLine(
                title: 'Iniciais do nome completo',
                value: 'Obrigatório',
              ),
              Divider(),
              _ReadOnlyLine(
                title: 'Últimos 4 dígitos do telefone',
                value: 'Configurável',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabDados() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildCard(
            icon: Icons.badge_rounded,
            title: 'Dados visíveis para o aluno',
            subtitle: 'Defina o que o aluno poderá visualizar quando entrar.',
            color: Colors.purple,
            children: [
              _buildSwitchCampo('Mostrar foto', 'mostrar_foto'),
              _buildSwitchCampo('Mostrar dados básicos', 'mostrar_dados_basicos'),
              _buildSwitchCampo(
                'Mostrar academia e turma',
                'mostrar_academia_turma',
              ),
              _buildSwitchCampo('Mostrar graduação', 'mostrar_graduacao'),
              _buildSwitchCampo('Mostrar presenças', 'mostrar_presencas'),
              _buildSwitchCampo(
                'Mostrar histórico de chamadas',
                'mostrar_historico_chamadas',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            icon: Icons.lock_outline_rounded,
            color: Colors.purple,
            title: 'Somente leitura',
            text:
            'Mesmo que os dados estejam visíveis, o aluno não altera a coleção original. Alterações futuras serão enviadas como solicitação para análise da coordenação.',
          ),
          const SizedBox(height: 14),
          _buildCard(
            icon: Icons.edit_document,
            title: 'Solicitações de alteração',
            subtitle: 'Agora disponível na aba Solicitações.',
            color: Colors.orange,
            children: [
              _buildInfoBox(
                icon: Icons.assignment_turned_in_rounded,
                color: Colors.orange,
                title: 'Fila de análise',
                text:
                'Quando o aluno solicitar alteração, a solicitação aparecerá na aba Solicitações com comparação lado a lado dos dados atuais e dos dados pedidos.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabTextos() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildCard(
            icon: Icons.edit_note_rounded,
            title: 'Textos da tela pública',
            subtitle: 'Personalize as mensagens que aparecerão para o aluno.',
            color: Colors.orange,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.title_rounded, color: Colors.orange.shade800),
                title: const Text('Mensagem do topo'),
                subtitle: Text(
                  _getString('mensagem_topo'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editarTexto(
                  campo: 'mensagem_topo',
                  titulo: 'Mensagem do topo',
                  label: 'Mensagem',
                  maxLines: 2,
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.help_outline_rounded,
                  color: Colors.orange.shade800,
                ),
                title: const Text('Texto de ajuda'),
                subtitle: Text(
                  _getString('texto_ajuda'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editarTexto(
                  campo: 'texto_ajuda',
                  titulo: 'Texto de ajuda',
                  label: 'Ajuda',
                  maxLines: 4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPreviewCard(),
        ],
      ),
    );
  }


  Widget _buildTabSolicitacoes() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildCard(
            icon: Icons.assignment_turned_in_rounded,
            title: 'Solicitações pendentes',
            subtitle: 'Compare o cadastro atual com a alteração solicitada.',
            color: Colors.deepOrange,
            children: [
              SizedBox(
                height: 420,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('area_aluno_solicitacoes_alteracao')
                      .where('status', isEqualTo: 'pendente')
                      .orderBy('criado_em', descending: true)
                      .limit(50)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return _buildEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Erro ao carregar',
                        text:
                        'Não foi possível carregar as solicitações. Talvez precise criar um índice no Firestore.',
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return _buildEmptyState(
                        icon: Icons.inbox_rounded,
                        title: 'Nenhuma pendente',
                        text: 'Quando um aluno pedir alteração, aparecerá aqui.',
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final campos = _camposAlterados(data);

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepOrange.withOpacity(0.12),
                            child: const Icon(
                              Icons.edit_document,
                              color: Colors.deepOrange,
                            ),
                          ),
                          title: Text(
                            data['aluno_nome']?.toString() ?? 'Aluno não informado',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${campos.length} campo(s): ${campos.map(_labelCampo).join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.chevron_right_rounded),
                              Text(
                                _formatTimestamp(data['criado_em']),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _abrirDetalheSolicitacao(doc),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSolicitacoesHistoricoCard(),
        ],
      ),
    );
  }

  Widget _buildSolicitacoesHistoricoCard() {
    return _buildCard(
      icon: Icons.history_edu_rounded,
      title: 'Últimas analisadas',
      subtitle: 'Solicitações aprovadas ou recusadas recentemente.',
      color: Colors.blueGrey,
      children: [
        SizedBox(
          height: 260,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('area_aluno_solicitacoes_alteracao')
                .where('status', whereIn: ['aprovado', 'recusado'])
                .orderBy('analisado_em', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Sem histórico',
                  text: 'As solicitações analisadas aparecerão aqui.',
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final aprovado = data['status'] == 'aprovado';

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      aprovado
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: aprovado ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      data['aluno_nome']?.toString() ?? 'Aluno não informado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      aprovado ? 'Aprovada' : 'Recusada',
                    ),
                    trailing: Text(
                      _formatTimestamp(data['analisado_em']),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    onTap: () => _abrirDetalheSolicitacao(docs[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _abrirDetalheSolicitacao(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    final data = doc.data();
    final status = data['status']?.toString() ?? 'pendente';
    final campos = _camposAlterados(data);
    final originais = _mapFrom(data['dados_originais']);
    final solicitados = _mapFrom(data['dados_solicitados']);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width > 760
            ? 760
            : MediaQuery.of(context).size.width,
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.88,
              minChildSize: 0.50,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSolicitacaoHeader(data, status),
                    const SizedBox(height: 14),
                    if ((data['observacao_aluno']?.toString() ?? '').isNotEmpty)
                      _buildObservacaoAluno(data['observacao_aluno'].toString()),
                    if ((data['observacao_aluno']?.toString() ?? '').isNotEmpty)
                      const SizedBox(height: 14),
                    _buildComparacaoSolicitacao(campos, originais, solicitados),
                    if (status == 'pendente') ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmarRecusaSolicitacao(doc),
                              icon: const Icon(Icons.cancel_rounded),
                              label: const Text('RECUSAR'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade800,
                                side: BorderSide(color: Colors.red.shade200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _confirmarAprovarSolicitacao(doc),
                              icon: const Icon(Icons.check_circle_rounded),
                              label: const Text('APROVAR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      _buildInfoBox(
                        icon: status == 'aprovado'
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: status == 'aprovado' ? Colors.green : Colors.red,
                        title: status == 'aprovado'
                            ? 'Solicitação aprovada'
                            : 'Solicitação recusada',
                        text:
                        'Analisado em ${_formatTimestamp(data['analisado_em'])}.',
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSolicitacaoHeader(Map<String, dynamic> data, String status) {
    final color = status == 'pendente'
        ? Colors.deepOrange
        : status == 'aprovado'
        ? Colors.green
        : Colors.red;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.assignment_turned_in_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['aluno_nome']?.toString() ?? 'Aluno não informado',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${data['turma'] ?? ''} • ${data['academia'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.80), fontSize: 12),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _buildWhiteChip(status.toUpperCase()),
                    _buildWhiteChip(_formatTimestamp(data['criado_em'])),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteChip(String text) {
    if (text.trim().isEmpty || text == '--') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildObservacaoAluno(String texto) {
    return _buildInfoBox(
      icon: Icons.notes_rounded,
      color: Colors.blue,
      title: 'Observação do aluno',
      text: texto,
    );
  }

  Widget _buildComparacaoSolicitacao(
      List<String> campos,
      Map<String, dynamic> originais,
      Map<String, dynamic> solicitados,
      ) {
    if (campos.isEmpty) {
      return _buildEmptyState(
        icon: Icons.info_outline_rounded,
        title: 'Sem diferença',
        text: 'Nenhum campo diferente foi encontrado nessa solicitação.',
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, color: Colors.red.shade900),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Comparação lado a lado',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...campos.map((campo) {
          final original = originais[campo]?.toString() ?? '';
          final solicitado = solicitados[campo]?.toString() ?? '';

          return _buildCampoComparacao(
            campo: campo,
            original: original,
            solicitado: solicitado,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCampoComparacao({
    required String campo,
    required String original,
    required String solicitado,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _labelCampo(campo),
            style: TextStyle(
              color: Colors.orange.shade900,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              if (narrow) {
                return Column(
                  children: [
                    _buildValorComparacao(
                      titulo: 'Atual',
                      valor: original,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    _buildValorComparacao(
                      titulo: 'Solicitado',
                      valor: solicitado,
                      color: Colors.green,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildValorComparacao(
                      titulo: 'Atual',
                      valor: original,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildValorComparacao(
                      titulo: 'Solicitado',
                      valor: solicitado,
                      color: Colors.green,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildValorComparacao({
    required String titulo,
    required String valor,
    required Color color,
  }) {
    final text = valor.trim().isEmpty ? 'Vazio' : valor.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: color == Colors.grey ? Colors.grey.shade700 : color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarAprovarSolicitacao(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    final confirmar = await _confirmarAcao(
      titulo: 'Aprovar solicitação?',
      mensagem:
      'Os campos alterados serão aplicados no cadastro oficial do aluno.',
      cor: Colors.green,
      textoBotao: 'APROVAR',
    );

    if (confirmar != true) return;

    await _aprovarSolicitacao(doc);
  }

  Future<void> _confirmarRecusaSolicitacao(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    final observacaoController = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.cancel_rounded, color: Colors.red.shade800),
              const SizedBox(width: 8),
              const Expanded(child: Text('Recusar solicitação?')),
            ],
          ),
          content: TextField(
            controller: observacaoController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Observação para registro',
              hintText: 'Opcional',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
              ),
              child: const Text('RECUSAR'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _recusarSolicitacao(doc, observacaoController.text.trim());
  }

  Future<bool?> _confirmarAcao({
    required String titulo,
    required String mensagem,
    required Color cor,
    required String textoBotao,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: cor),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo)),
            ],
          ),
          content: Text(mensagem),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: cor,
                foregroundColor: Colors.white,
              ),
              child: Text(textoBotao),
            ),
          ],
        );
      },
    );
  }

  Future<void> _aprovarSolicitacao(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    try {
      final data = doc.data();
      final alunoId = data['aluno_id']?.toString() ?? '';
      final solicitados = _mapFrom(data['dados_solicitados']);
      final campos = _camposAlterados(data);

      if (alunoId.isEmpty || campos.isEmpty) {
        _mostrarSnack('Solicitação inválida.', Colors.red);
        return;
      }

      final updateAluno = <String, dynamic>{};

      for (final campo in campos) {
        if (!solicitados.containsKey(campo)) continue;

        final valor = solicitados[campo];

        if (campo == 'data_nascimento') {
          final dataNascimento = _parseDate(valor?.toString() ?? '');
          if (dataNascimento != null) {
            updateAluno[campo] = Timestamp.fromDate(dataNascimento);
          }
        } else if (campo.contains('contato')) {
          updateAluno[campo] = _digitsOnly(valor?.toString() ?? '');
        } else if (campo == 'nome' ||
            campo == 'sexo' ||
            campo == 'cidade') {
          updateAluno[campo] = valor?.toString().trim().toUpperCase() ?? '';
        } else {
          updateAluno[campo] = valor?.toString().trim() ?? '';
        }
      }

      final admin = await _dadosAdminAtual();

      updateAluno['ultima_atualizacao'] = FieldValue.serverTimestamp();
      updateAluno['data_atualizacao'] = FieldValue.serverTimestamp();
      updateAluno['atualizado_por'] = admin['nome'];
      updateAluno['atualizado_por_uid'] = admin['uid'];

      final batch = FirebaseFirestore.instance.batch();

      batch.update(
        FirebaseFirestore.instance.collection('alunos').doc(alunoId),
        updateAluno,
      );

      batch.update(doc.reference, {
        'status': 'aprovado',
        'analisado_em': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
        'analisado_por': admin['uid'],
        'analisado_por_nome': admin['nome'],
        'observacao_admin': 'Solicitação aprovada e aplicada no cadastro.',
        'aplicado_no_aluno': updateAluno,
      });

      await batch.commit();

      if (mounted) Navigator.pop(context);

      _mostrarSnack('✅ Solicitação aprovada e cadastro atualizado.', Colors.green);
    } catch (e) {
      _mostrarSnack('Erro ao aprovar solicitação: $e', Colors.red);
    }
  }

  Future<void> _recusarSolicitacao(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String observacao,
      ) async {
    try {
      final admin = await _dadosAdminAtual();

      await doc.reference.update({
        'status': 'recusado',
        'analisado_em': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
        'analisado_por': admin['uid'],
        'analisado_por_nome': admin['nome'],
        'observacao_admin': observacao,
      });

      if (mounted) Navigator.pop(context);

      _mostrarSnack('Solicitação recusada.', Colors.orange.shade800);
    } catch (e) {
      _mostrarSnack('Erro ao recusar solicitação: $e', Colors.red);
    }
  }

  Future<Map<String, String>> _dadosAdminAtual() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {
        'uid': '',
        'nome': 'Sistema',
      };
    }

    String nome = user.email ?? 'Administrador';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      final data = doc.data();

      if (data != null) {
        nome = data['nome_completo']?.toString() ??
            data['nome']?.toString() ??
            data['email']?.toString() ??
            nome;
      }
    } catch (_) {}

    return {
      'uid': user.uid,
      'nome': nome,
    };
  }

  Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  List<String> _camposAlterados(Map<String, dynamic> data) {
    final raw = data['campos_alterados'];

    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }

    final originais = _mapFrom(data['dados_originais']);
    final solicitados = _mapFrom(data['dados_solicitados']);

    final campos = <String>[];

    for (final key in solicitados.keys) {
      final original = originais[key]?.toString().trim() ?? '';
      final novo = solicitados[key]?.toString().trim() ?? '';

      if (original != novo) campos.add(key);
    }

    return campos;
  }

  String _labelCampo(String campo) {
    const labels = {
      'nome': 'Nome completo',
      'apelido': 'Apelido',
      'data_nascimento': 'Data de nascimento',
      'sexo': 'Sexo',
      'cidade': 'Cidade',
      'endereco': 'Endereço',
      'contato_aluno': 'Contato do aluno',
      'nome_responsavel': 'Nome do responsável',
      'contato_responsavel': 'Contato do responsável',
    };

    return labels[campo] ?? campo;
  }

  DateTime? _parseDate(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value.trim());
    } catch (_) {
      return null;
    }
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
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

  Widget _buildTabLogs() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildLogsResumoHeader(),
          const SizedBox(height: 14),
          _buildLimparLogsCardCompacto(),
          const SizedBox(height: 14),
          _buildLogsSegmentadosCard(),
        ],
      ),
    );
  }

  Widget _buildLogsResumoHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.shade900.withOpacity(0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.manage_history_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Central de logs',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Acompanhe acessos, tentativas bloqueadas e faça limpeza quando necessário.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimparLogsCardCompacto() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.delete_sweep_rounded, color: Colors.red.shade800),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limpeza de logs',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Apague apenas logs de acesso/erro. Solicitações não são apagadas.',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              final botoes = [
                _buildLogActionButton(
                  label: 'Acessos',
                  icon: Icons.login_rounded,
                  color: Colors.green,
                  onTap: () => _confirmarLimparLogs(
                    collection: 'area_aluno_logs_acesso',
                    titulo: 'Apagar logs de acesso?',
                    descricao:
                    'Todos os registros de alunos que acessaram a Área do Aluno serão apagados.',
                  ),
                ),
                _buildLogActionButton(
                  label: 'Erros',
                  icon: Icons.warning_rounded,
                  color: Colors.orange,
                  onTap: () => _confirmarLimparLogs(
                    collection: 'area_aluno_logs_erro',
                    titulo: 'Apagar logs de erro?',
                    descricao:
                    'Todos os registros de tentativas inválidas ou bloqueadas serão apagados.',
                  ),
                ),
                _buildLogActionButton(
                  label: 'Todos',
                  icon: Icons.delete_forever_rounded,
                  color: Colors.red,
                  filled: true,
                  onTap: _confirmarLimparTodosLogs,
                ),
              ];

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: botoes[0]),
                        const SizedBox(width: 8),
                        Expanded(child: botoes[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    botoes[2],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: botoes[0]),
                  const SizedBox(width: 8),
                  Expanded(child: botoes[1]),
                  const SizedBox(width: 8),
                  Expanded(child: botoes[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.35)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildLogsSegmentadosCard() {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade100),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.blueGrey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Registros recentes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Últimos registros da Área do Aluno',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey.shade700,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.check_circle_rounded, size: 18),
                    text: 'Acessos',
                  ),
                  Tab(
                    icon: Icon(Icons.warning_rounded, size: 18),
                    text: 'Erros',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 470,
              child: TabBarView(
                children: [
                  _buildLogsAcessoLista(),
                  _buildLogsErroLista(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsAcessoLista() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _configService.streamLogsAcessoAreaAluno(limite: 40),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyLog(
            icon: Icons.error_outline_rounded,
            text: 'Erro ao carregar logs de acesso.',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyLog(
            icon: Icons.history_rounded,
            text: 'Nenhum acesso registrado ainda.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = docs[index].data();

            return _buildLogCard(
              icon: Icons.check_circle_rounded,
              color: Colors.green,
              title: data['aluno_nome']?.toString() ?? 'Aluno não informado',
              subtitle: data['turma']?.toString() ??
                  data['motivo']?.toString() ??
                  'Acesso liberado',
              timestamp: data['acesso_em'],
              chips: [
                if ((data['academia']?.toString() ?? '').isNotEmpty)
                  _LogChip(
                    icon: Icons.home_work_rounded,
                    label: data['academia'].toString(),
                    color: Colors.blue,
                  ),
                _LogChip(
                  icon: Icons.login_rounded,
                  label: 'Acesso',
                  color: Colors.green,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLogsErroLista() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _configService.streamLogsErroAreaAluno(limite: 40),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyLog(
            icon: Icons.error_outline_rounded,
            text: 'Erro ao carregar logs de erro.',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyLog(
            icon: Icons.history_rounded,
            text: 'Nenhum erro registrado ainda.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final iniciais = data['iniciais_usadas']?.toString() ?? '-';
            final nascimento = data['data_nascimento_usada']?.toString() ?? '-';
            final telefone = data['telefone_final_usado']?.toString() ?? '-';

            return _buildLogCard(
              icon: Icons.cancel_rounded,
              color: Colors.red,
              title: data['motivo']?.toString() ?? 'Tentativa bloqueada',
              subtitle: 'Dados usados na tentativa de acesso',
              timestamp: data['tentativa_em'],
              chips: [
                _LogChip(
                  icon: Icons.badge_rounded,
                  label: 'Iniciais: $iniciais',
                  color: Colors.deepOrange,
                ),
                _LogChip(
                  icon: Icons.cake_rounded,
                  label: nascimento,
                  color: Colors.purple,
                ),
                _LogChip(
                  icon: Icons.phone_android_rounded,
                  label: 'Tel: $telefone',
                  color: Colors.blueGrey,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLogCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required dynamic timestamp,
    required List<_LogChip> chips,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 11.5,
                    height: 1.20,
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips.map((chip) => _buildLogMiniChip(chip)).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              _formatTimestamp(timestamp),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogMiniChip(_LogChip chip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: chip.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: chip.color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, color: chip.color, size: 12),
          const SizedBox(width: 4),
          Text(
            chip.label,
            style: TextStyle(
              color: chip.color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final visivel = _getBool('visivel_site');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
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
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Painel da Área do Aluno',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Controle acesso, segurança, dados visíveis, textos e logs.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.80),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildHeaderStatusChip(visivel),
        ],
      ),
    );
  }

  Widget _buildHeaderStatusChip(bool visivel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: visivel
            ? Colors.green.withOpacity(0.22)
            : Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        visivel ? 'ATIVA' : 'OCULTA',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildResumoRapido() {
    final visivel = _getBool('visivel_site');
    final apenasAtivos = _getBool('aceitar_apenas_ativos', padrao: true);
    final telefone = _getBool('exigir_telefone_confirmacao', padrao: true);

    return Row(
      children: [
        Expanded(
          child: _buildMiniResumoCard(
            icon: visivel ? Icons.visibility : Icons.visibility_off,
            label: 'Site',
            value: visivel ? 'Ativo' : 'Oculto',
            color: visivel ? Colors.green : Colors.grey,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMiniResumoCard(
            icon: Icons.person_pin_rounded,
            label: 'Acesso',
            value: apenasAtivos ? 'Só ativos' : 'Todos',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMiniResumoCard(
            icon: Icons.phone_android_rounded,
            label: 'Telefone',
            value: telefone ? 'Exige' : 'Não exige',
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniResumoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.08)),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String text, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: done ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: done ? Colors.grey.shade900 : Colors.grey.shade600,
                fontWeight: done ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchCampo(String title, String key) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      value: _getBool(key, padrao: true),
      activeColor: Colors.purple,
      onChanged: (value) => _salvarCampo(key, value),
    );
  }

  Widget _buildPreviewCard() {
    return _buildCard(
      icon: Icons.preview_rounded,
      title: 'Prévia dos textos',
      subtitle: 'Como a mensagem aparecerá para o aluno.',
      color: Colors.brown,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getString(
                  'mensagem_topo',
                  padrao: 'Bem-vindo(a) à Área do Aluno',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getString(
                  'texto_ajuda',
                  padrao:
                  'Informe sua data de nascimento, as iniciais do seu nome completo e os últimos 4 dígitos do telefone cadastrado.',
                ),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimparLogsCard() {
    return _buildCard(
      icon: Icons.delete_sweep_rounded,
      title: 'Limpeza de logs',
      subtitle: 'Apague registros antigos de acesso e erro da Área do Aluno.',
      color: Colors.red,
      children: [
        _buildInfoBox(
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          title: 'Atenção',
          text:
          'Essa ação apaga os registros de logs permanentemente. As solicitações de alteração não serão apagadas.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 460;

            final botaoAcessos = OutlinedButton.icon(
              onPressed: () => _confirmarLimparLogs(
                collection: 'area_aluno_logs_acesso',
                titulo: 'Apagar logs de acesso?',
                descricao:
                'Todos os registros de alunos que acessaram a Área do Aluno serão apagados.',
              ),
              icon: const Icon(Icons.login_rounded),
              label: const Text('APAGAR ACESSOS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade800,
                side: BorderSide(color: Colors.red.shade200),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            );

            final botaoErros = OutlinedButton.icon(
              onPressed: () => _confirmarLimparLogs(
                collection: 'area_aluno_logs_erro',
                titulo: 'Apagar logs de erro?',
                descricao:
                'Todos os registros de tentativas inválidas ou bloqueadas serão apagados.',
              ),
              icon: const Icon(Icons.warning_rounded),
              label: const Text('APAGAR ERROS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade800,
                side: BorderSide(color: Colors.red.shade200),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  botaoAcessos,
                  const SizedBox(height: 10),
                  botaoErros,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: botaoAcessos),
                const SizedBox(width: 10),
                Expanded(child: botaoErros),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirmarLimparTodosLogs,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('APAGAR TODOS OS LOGS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmarLimparTodosLogs() async {
    final confirmar = await _confirmarAcao(
      titulo: 'Apagar todos os logs?',
      mensagem:
      'Isso apagará todos os logs de acesso e todos os logs de erro da Área do Aluno. Essa ação não pode ser desfeita.',
      cor: Colors.red,
      textoBotao: 'APAGAR TUDO',
    );

    if (confirmar != true) return;

    await _limparColecaoLogs('area_aluno_logs_acesso');
    await _limparColecaoLogs('area_aluno_logs_erro');

    _mostrarSnack('✅ Todos os logs foram apagados.', Colors.green);
  }

  Future<void> _confirmarLimparLogs({
    required String collection,
    required String titulo,
    required String descricao,
  }) async {
    final confirmar = await _confirmarAcao(
      titulo: titulo,
      mensagem: '$descricao\n\nEssa ação não pode ser desfeita.',
      cor: Colors.red,
      textoBotao: 'APAGAR',
    );

    if (confirmar != true) return;

    await _limparColecaoLogs(collection);

    _mostrarSnack('✅ Logs apagados com sucesso.', Colors.green);
  }

  Future<void> _limparColecaoLogs(String collection) async {
    try {
      const int limite = 450;
      bool aindaTem = true;

      while (aindaTem) {
        final snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .limit(limite)
            .get();

        if (snapshot.docs.isEmpty) {
          aindaTem = false;
          break;
        }

        final batch = FirebaseFirestore.instance.batch();

        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();

        if (snapshot.docs.length < limite) {
          aindaTem = false;
        }
      }
    } catch (e) {
      _mostrarSnack('Erro ao apagar logs: $e', Colors.red);
    }
  }

  Widget _buildLogsAcessoCard() {
    return _buildCard(
      icon: Icons.login_rounded,
      title: 'Últimos acessos',
      subtitle: 'Alunos que conseguiram acessar a Área do Aluno.',
      color: Colors.green,
      children: [
        SizedBox(
          height: 360,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _configService.streamLogsAcessoAreaAluno(limite: 40),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _buildEmptyLog(
                  icon: Icons.error_outline_rounded,
                  text: 'Erro ao carregar logs de acesso.',
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return _buildEmptyLog(
                  icon: Icons.history_rounded,
                  text: 'Nenhum acesso registrado ainda.',
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data();

                  return _buildLogTile(
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                    title: data['aluno_nome']?.toString() ?? 'Aluno não informado',
                    subtitle: data['turma']?.toString() ??
                        data['motivo']?.toString() ??
                        'Acesso liberado',
                    timestamp: data['acesso_em'],
                    extra: data['academia']?.toString(),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogsErroCard() {
    return _buildCard(
      icon: Icons.warning_rounded,
      title: 'Logs de erro',
      subtitle: 'Tentativas inválidas ou bloqueadas.',
      color: Colors.red,
      children: [
        SizedBox(
          height: 360,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _configService.streamLogsErroAreaAluno(limite: 40),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _buildEmptyLog(
                  icon: Icons.error_outline_rounded,
                  text: 'Erro ao carregar logs de erro.',
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return _buildEmptyLog(
                  icon: Icons.history_rounded,
                  text: 'Nenhum erro registrado ainda.',
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data();

                  return _buildLogTile(
                    icon: Icons.cancel_rounded,
                    color: Colors.red,
                    title: data['motivo']?.toString() ?? 'Tentativa bloqueada',
                    subtitle:
                    'Iniciais: ${data['iniciais_usadas'] ?? '-'} | Nasc.: ${data['data_nascimento_usada'] ?? '-'}',
                    timestamp: data['tentativa_em'],
                    extra: data['telefone_final_usado'] != null
                        ? 'Final tel.: ${data['telefone_final_usado']}'
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required dynamic timestamp,
    String? extra,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        extra == null || extra.isEmpty ? subtitle : '$subtitle\n$extra',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTimestamp(timestamp),
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _buildEmptyLog({
    required IconData icon,
    required String text,
  }) {
    return _buildEmptyState(
      icon: icon,
      title: 'Sem registros',
      text: text,
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 38, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.08)),
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
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes $hora:$min';
    }

    return '--';
  }
}

class _LogChip {
  final IconData icon;
  final String label;
  final Color color;

  const _LogChip({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _ReadOnlyLine extends StatelessWidget {
  final String title;
  final String value;

  const _ReadOnlyLine({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
