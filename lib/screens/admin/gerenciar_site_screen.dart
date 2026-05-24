import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'regimento_interno_screen.dart';
import 'biografia_screen.dart';
import 'graduacoes_site_screen.dart';
import 'configurar_inscricoes_screen.dart';
import 'gerenciar_timeline_screen.dart';
import 'configurar_campeonato_screen.dart';
import 'configurar_menu_screen.dart';

import 'package:uai_capoeira/screens/site/editar_textos_screen.dart';
import 'package:uai_capoeira/screens/admin/dashboard_estatisticas_screen.dart';
import 'package:uai_capoeira/services/site_config_service.dart';
import 'package:uai_capoeira/screens/admin/configurar_assistente_screen.dart';
import 'package:uai_capoeira/screens/admin/area_aluno_admin_screen.dart';

class GerenciarSiteScreen extends StatefulWidget {
  const GerenciarSiteScreen({super.key});

  @override
  State<GerenciarSiteScreen> createState() => _GerenciarSiteScreenState();
}

class _GerenciarSiteScreenState extends State<GerenciarSiteScreen> {
  final SiteConfigService _configService = SiteConfigService();

  bool _carregando = true;
  String? _erro;

  Map<String, dynamic> _configuracoes = {};
  Map<String, dynamic> _configAreaAluno = {};

  final List<Map<String, dynamic>> _secoesBase = [
    {
      'id': 'regimento',
      'titulo': 'REGIMENTO INTERNO',
      'icone': Icons.description_rounded,
      'cor': Colors.blue,
      'colecao': 'site_regimento',
      'descricao': 'Editar regras e normas do grupo',
      'tela': 'regimento',
      'ordem_padrao': 1,
    },
    {
      'id': 'biografia',
      'titulo': 'BIOGRAFIA',
      'icone': Icons.auto_stories_rounded,
      'cor': Colors.green,
      'colecao': 'site_biografia',
      'descricao': 'Editar história do grupo',
      'tela': 'biografia',
      'ordem_padrao': 2,
    },
    {
      'id': 'graduacoes',
      'titulo': 'GRADUAÇÕES',
      'icone': Icons.workspace_premium_rounded,
      'cor': Colors.orange,
      'colecao': 'site_graduacoes',
      'descricao': 'Editar sistema de cordas',
      'tela': 'graduacoes',
      'ordem_padrao': 3,
    },
    {
      'id': 'inscricao',
      'titulo': 'INSCRIÇÃO',
      'icone': Icons.app_registration_rounded,
      'cor': Colors.red,
      'colecao': 'site_inscricao',
      'descricao': 'Configurar inscrições para aula experimental',
      'tela': 'inscricao',
      'ordem_padrao': 4,
    },
    {
      'id': 'area_aluno',
      'titulo': 'ÁREA DO ALUNO',
      'icone': Icons.school_rounded,
      'cor': Colors.indigo,
      'colecao': 'configuracoes_site/area_aluno',
      'descricao': 'Configurar acesso público dos alunos',
      'tela': 'area_aluno',
      'ordem_padrao': 5,
      'destaque': true,
    },
    {
      'id': 'campeonato',
      'titulo': 'CAMPEONATO',
      'icone': Icons.emoji_events_rounded,
      'cor': Colors.amber,
      'colecao': 'campeonato_inscricoes',
      'descricao': 'Configurar 1° Campeonato UAI Capoeira',
      'tela': 'campeonato',
      'ordem_padrao': 6,
    },
    {
      'id': 'portfolio',
      'titulo': 'LINHA DO TEMPO',
      'icone': Icons.timeline_rounded,
      'cor': Colors.purple,
      'colecao': 'timeline_publicacoes',
      'descricao': 'Gerenciar publicações do site',
      'tela': 'timeline',
      'ordem_padrao': 7,
    },
  ];

  late List<Map<String, dynamic>> _secoes;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  Future<void> _carregarConfiguracoes() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final configs = await _configService.carregarConfiguracoesSite();
      final areaAlunoConfig = await _configService.carregarConfiguracoesAreaAluno();

      if (!mounted) return;

      setState(() {
        _configuracoes = configs;
        _configAreaAluno = areaAlunoConfig;

        _secoes = _secoesBase.map((secao) {
          final Map<String, dynamic> secaoModificada = Map.from(secao);

          if (configs['titulos'] != null &&
              configs['titulos'][secao['id']] != null) {
            secaoModificada['titulo'] = configs['titulos'][secao['id']];
          }

          if (configs['descricoes'] != null &&
              configs['descricoes'][secao['id']] != null) {
            secaoModificada['descricao'] = configs['descricoes'][secao['id']];
          }

          if (configs['visibilidade'] != null &&
              configs['visibilidade'][secao['id']] == false) {
            secaoModificada['oculto'] = true;
          }

          if (secao['id'] == 'area_aluno') {
            final visivelArea = areaAlunoConfig['visivel_site'] == true;

            secaoModificada['oculto'] = !visivelArea;
            secaoModificada['descricao'] = visivelArea
                ? 'Área ativa no site. Configure segurança, dados e logs.'
                : 'Área criada, mas oculta no site. Toque para configurar.';
          }

          return secaoModificada;
        }).toList();

        if (configs['ordem'] != null && configs['ordem'].isNotEmpty) {
          _secoes.sort((a, b) {
            final indexA = configs['ordem'].indexOf(a['id']);
            final indexB = configs['ordem'].indexOf(b['id']);

            if (indexA == -1 && indexB == -1) {
              return (a['ordem_padrao'] ?? 999)
                  .compareTo(b['ordem_padrao'] ?? 999);
            }

            if (indexA == -1) return 1;
            if (indexB == -1) return -1;
            return indexA.compareTo(indexB);
          });
        } else {
          _secoes.sort(
                (a, b) => (a['ordem_padrao'] ?? 999)
                .compareTo(b['ordem_padrao'] ?? 999),
          );
        }

        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _erro = 'Erro ao carregar configurações: $e';
        _carregando = false;
        _secoes = List.from(_secoesBase);
      });
    }
  }

  int get _totalSecoes => _secoes.length;

  int get _secoesVisiveis {
    return _secoes.where((secao) => secao['oculto'] != true).length;
  }

  int get _secoesOcultas {
    return _secoes.where((secao) => secao['oculto'] == true).length;
  }

  bool get _areaAlunoVisivel {
    return _configAreaAluno['visivel_site'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Gerenciar Site',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardEstatisticasScreen(),
                ),
              );
            },
            tooltip: 'Dashboard de Visitas',
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _mostrarDialogoConfiguracoes,
            tooltip: 'Configurações do Site',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _carregarConfiguracoes,
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red.shade50, Colors.grey.shade50],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erro != null) {
      return _buildErro();
    }

    return RefreshIndicator(
      onRefresh: _carregarConfiguracoes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          _buildHeaderResumo(),
          const SizedBox(height: 14),
          _buildAtalhosSuperiores(),
          const SizedBox(height: 16),
          _buildSectionTitle(
            icon: Icons.dashboard_customize_rounded,
            title: 'Seções do site',
            subtitle: 'Toque em uma seção para configurar o conteúdo',
          ),
          const SizedBox(height: 10),
          ..._secoes.map((secao) {
            if (secao['id'] == 'area_aluno') {
              return _buildAreaAlunoCard(secao);
            }

            if (secao['oculto'] == true) {
              return _buildHiddenSectionCard(secao);
            }

            return _buildSecaoCard(secao);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 68, color: Colors.red.shade700),
            const SizedBox(height: 16),
            Text(
              'Ops! Algo deu errado',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _carregarConfiguracoes,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('TENTAR NOVAMENTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderResumo() {
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
            color: Colors.red.shade900.withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Central do Site',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Conteúdo público, menu, inscrições, área do aluno e estatísticas.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.80),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Seções',
                  value: '$_totalSecoes',
                  icon: Icons.widgets_rounded,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Visíveis',
                  value: '$_secoesVisiveis',
                  icon: Icons.visibility_rounded,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _buildHeaderMetric(
                  label: 'Ocultas',
                  value: '$_secoesOcultas',
                  icon: Icons.visibility_off_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.74),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtalhosSuperiores() {
    return Row(
      children: [
        Expanded(
          child: _buildAtalhoCard(
            icon: Icons.analytics_rounded,
            title: 'Visitas',
            subtitle: 'Dashboard',
            color: Colors.blue,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardEstatisticasScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildAtalhoCard(
            icon: Icons.smart_toy_rounded,
            title: 'Assistente',
            subtitle: 'Chat IA',
            color: Colors.teal,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConfigurarAssistenteScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildAtalhoCard(
            icon: Icons.school_rounded,
            title: 'Aluno',
            subtitle: _areaAlunoVisivel ? 'Ativo' : 'Oculto',
            color: _areaAlunoVisivel ? Colors.indigo : Colors.grey,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AreaAlunoAdminScreen(),
                ),
              ).then((_) => _carregarConfiguracoes());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAtalhoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.10)),
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
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _iconColor(color), size: 23),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: Colors.red.shade900, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAreaAlunoCard(Map<String, dynamic> secao) {
    final bool oculto = secao['oculto'] == true;
    final Color color = oculto ? Colors.grey : Colors.indigo;

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: oculto
              ? [Colors.grey.shade100, Colors.white]
              : [Colors.indigo.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: oculto ? Colors.grey.shade300 : Colors.indigo.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.040),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _abrirSecao(secao),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.school_rounded, color: _iconColor(color), size: 30),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'ÁREA DO ALUNO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            _buildStatusChip(
                              texto: oculto ? 'OCULTA' : 'ATIVA',
                              color: oculto ? Colors.grey : Colors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          secao['descricao'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, color: color),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniInfo(
                      icon: Icons.verified_user_rounded,
                      label: 'Segurança',
                      value: _configAreaAluno['exigir_telefone_confirmacao'] == true
                          ? 'Telefone'
                          : 'Simples',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniInfo(
                      icon: Icons.person_pin_rounded,
                      label: 'Status',
                      value: _configAreaAluno['aceitar_apenas_ativos'] == true
                          ? 'Só ativos'
                          : 'Todos',
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniInfo(
                      icon: Icons.history_rounded,
                      label: 'Logs',
                      value: 'Ativos',
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniInfo({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 17, color: _iconColor(color)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoCard(Map<String, dynamic> secao) {
    final Color color = secao['cor'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      child: InkWell(
        onTap: () => _abrirSecao(secao),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(secao['icone'], color: _iconColor(color), size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao['titulo'],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      secao['descricao'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildStatusChip(texto: 'VISÍVEL', color: Colors.green),
                        const SizedBox(width: 6),
                        if (secao['colecao'] != null)
                          Expanded(
                            child: Text(
                              '${secao['colecao']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenSectionCard(Map<String, dynamic> secao) {
    final Color color = secao['cor'] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: () => _mostrarDialogoVisibilidade(secao),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(secao['icone'], color: Colors.grey.shade600, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      secao['titulo'],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Seção oculta no site. Toque para gerenciar ou tornar visível.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusChip(texto: 'OCULTO', color: Colors.grey),
                  ],
                ),
              ),
              Icon(Icons.visibility_off_rounded, color: _iconColor(color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String texto,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: _iconColor(color),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _abrirSecao(Map<String, dynamic> secao) {
    switch (secao['tela']) {
      case 'regimento':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RegimentoInternoScreen()),
        ).then(_handleResult);
        break;
      case 'biografia':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BiografiaScreen()),
        ).then(_handleResult);
        break;
      case 'graduacoes':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GraduacoesSiteScreen()),
        ).then(_handleResult);
        break;
      case 'inscricao':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ConfigurarInscricoesScreen()),
        ).then(_handleResult);
        break;
      case 'area_aluno':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AreaAlunoAdminScreen()),
        ).then((_) => _carregarConfiguracoes());
        break;
      case 'campeonato':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ConfigurarCampeonatoScreen()),
        ).then(_handleResult);
        break;
      case 'timeline':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const GerenciarTimelineScreen()),
        ).then(_handleResult);
        break;
      default:
        _mostrarEmBreve(secao);
    }
  }

  void _mostrarDialogoConfiguracoes() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.tune_rounded, color: Colors.red.shade900),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Configurações do Site',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogOption(
              icone: Icons.swap_vert_rounded,
              cor: Colors.teal,
              titulo: 'Ordem do Menu',
              descricao: 'Reordenar botões do site',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConfigurarMenuScreen(
                      secoes: _secoesBase,
                      onSalvo: _carregarConfiguracoes,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 16),
            _buildDialogOption(
              icone: Icons.edit_note_rounded,
              cor: Colors.brown,
              titulo: 'Títulos e Textos',
              descricao: 'Personalizar nomes e descrições',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditarTextosScreen(
                      secoes: _secoesBase,
                      onSalvo: _carregarConfiguracoes,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 16),
            _buildDialogOption(
              icone: Icons.school_rounded,
              cor: Colors.indigo,
              titulo: 'Área do Aluno',
              descricao: 'Acesso, segurança, dados e logs',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AreaAlunoAdminScreen(),
                  ),
                ).then((_) => _carregarConfiguracoes());
              },
            ),
            const Divider(height: 16),
            _buildDialogOption(
              icone: Icons.chat_rounded,
              cor: Colors.blue,
              titulo: 'Assistente Chat',
              descricao: 'Configurar assistente virtual com IA',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ConfigurarAssistenteScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 16),
            _buildDialogOption(
              icone: Icons.lock_rounded,
              cor: Colors.red.shade900,
              titulo: 'Senha do App',
              descricao: 'Alterar senha de acesso dos professores',
              onTap: () {
                Navigator.pop(context);
                _mostrarDialogoAlterarSenha();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogOption({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 49,
              height: 49,
              decoration: BoxDecoration(
                color: cor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icone, color: _iconColor(cor), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _iconColor(cor)),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoVisibilidade(Map<String, dynamic> secao) {
    final bool isAreaAluno = secao['id'] == 'area_aluno';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(secao['icone'], color: secao['cor']),
            const SizedBox(width: 8),
            Expanded(child: Text(secao['titulo'])),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Esta seção está atualmente oculta no site.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              isAreaAluno
                  ? 'Você pode abrir o painel da Área do Aluno ou torná-la visível agora.'
                  : 'Deseja torná-la visível novamente?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          if (isAreaAluno)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _abrirSecao(secao);
              },
              child: const Text('CONFIGURAR'),
            ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              if (isAreaAluno) {
                await _configService.alterarVisibilidadeAreaAluno(true);
              } else {
                await _configService.alterarVisibilidade(secao['id'], true);
              }

              await _carregarConfiguracoes();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${secao['titulo']} agora está visível'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('TORNAR VISÍVEL'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAlterarSenha() {
    final TextEditingController senhaController = TextEditingController();
    final TextEditingController confirmarController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(
          children: [
            Icon(Icons.lock_rounded, size: 42, color: Colors.red.shade900),
            const SizedBox(height: 8),
            const Text('Alterar Senha do App'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Essa senha libera o acesso ao app para professores e monitores.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: senhaController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Nova senha',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.password_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmarController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirmar nova senha',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.password_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              final novaSenha = senhaController.text.trim();
              final confirmar = confirmarController.text.trim();

              if (novaSenha.isEmpty) {
                _mostrarErro('A senha não pode estar vazia');
                return;
              }

              if (novaSenha.length < 6) {
                _mostrarErro('A senha deve ter pelo menos 6 caracteres');
                return;
              }

              if (novaSenha != confirmar) {
                _mostrarErro('As senhas não coincidem');
                return;
              }

              Navigator.pop(context);
              await _configService.alterarSenhaApp(novaSenha);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Senha alterada com sucesso!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $mensagem'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleResult(dynamic result) {
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configurações salvas com sucesso!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );

      _carregarConfiguracoes();
    }
  }

  void _mostrarEmBreve(Map<String, dynamic> secao) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(secao['icone'], color: secao['cor']),
            const SizedBox(width: 8),
            Expanded(child: Text(secao['titulo'])),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: secao['cor'].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hourglass_empty_rounded, size: 50, color: secao['cor']),
            ),
            const SizedBox(height: 20),
            const Text(
              'Esta tela está em desenvolvimento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Em breve você poderá editar ${secao['titulo'].toLowerCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Color _iconColor(Color color) {
    if (color is MaterialColor) return color.shade700;
    return color;
  }
}
