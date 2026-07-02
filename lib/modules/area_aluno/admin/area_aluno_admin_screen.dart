import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';
import 'package:uai_capoeira/modules/site/services/site_config_service.dart';
import 'package:xml/xml.dart' as xml;

class AreaAlunoAdminScreen extends StatefulWidget {
  const AreaAlunoAdminScreen({super.key});

  @override
  State<AreaAlunoAdminScreen> createState() => _AreaAlunoAdminScreenState();
}

class _AreaAlunoAdminScreenState extends State<AreaAlunoAdminScreen>
    with SingleTickerProviderStateMixin {
  final SiteConfigService _configService = SiteConfigService();

  late final TabController _tabController;
  final TextEditingController _contasBuscaController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  final Set<String> _contasSelecionadas = {};
  String? _contasCordaSvg;
  final Map<String, Map<String, dynamic>> _contasGraduacoesCache = {};
  final Map<String, String> _contasSvgCache = {};

  Map<String, dynamic> _config = {};

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  LinearGradient _accentGradient(Color color) {
    final t = context.uai;
    final visible = _ensureVisible(color, t.card);
    return LinearGradient(
      colors: [
        Color.alphaBlend(visible.withOpacity(0.14), t.card),
        Color.alphaBlend(visible.withOpacity(0.05), t.card),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _carregarCordaSvgContas();
    _carregar();
  }

  Future<void> _carregarCordaSvgContas() async {
    try {
      final svg = await rootBundle.loadString('assets/images/corda.svg');
      if (!mounted) return;
      setState(() => _contasCordaSvg = svg);
    } catch (e) {
      debugPrint('Erro ao carregar corda.svg na aba Contas: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _contasBuscaController.dispose();
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
        SnackBar(
          content: const Text('✅ Configuração salva'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erro ao salvar: $e'),
          backgroundColor: context.uai.error,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
                backgroundColor: context.uai.primary,
                foregroundColor: _readableOn(context.uai.primary),
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
      _config['ativo'] = value;
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
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao alterar visibilidade: $e'),
            backgroundColor: context.uai.error,
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
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: const Text(
          'Área do Aluno',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_salvando)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    color: _onPrimary(),
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
            color: context.uai.primary,
            child: SafeArea(
              top: false,
              bottom: false,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: _onPrimary(),
                indicatorWeight: 3,
                labelColor: _onPrimary(),
                unselectedLabelColor: _onPrimary().withOpacity(0.72),
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
                  Tab(
                    icon: Icon(Icons.assignment_turned_in_rounded),
                    text: 'Solicitações',
                  ),
                  Tab(icon: Icon(Icons.account_circle_rounded), text: 'Contas'),
                  Tab(icon: Icon(Icons.history_rounded), text: 'Logs'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _carregando
          ? Center(child: CircularProgressIndicator(color: context.uai.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabGeral(),
                _buildTabSeguranca(),
                _buildTabDados(),
                _buildTabTextos(),
                _buildTabSolicitacoes(),
                _buildTabContasGoogle(),
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
                subtitle: const Text(
                  'Ativa ou oculta a entrada pública no site.',
                ),
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
                onChanged: (value) =>
                    _salvarCampo('aceitar_apenas_ativos', value),
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
          _buildCard(
            icon: Icons.account_circle_rounded,
            title: 'Conta Google e acesso',
            subtitle: 'Controle vínculo Google e nível de acesso do aluno.',
            color: Colors.deepPurple,
            children: [
              _buildSwitchCampo(
                'Ativar acesso com Google',
                'google_login_ativo',
                description:
                    'Ativa a opção de vincular uma conta Google ao perfil do aluno.',
                padrao: false,
              ),
              _buildModoCampo(
                title: 'Modo de vinculação',
                keyName: 'google_vinculacao_modo',
                description: 'Define quando o vínculo Google será pedido.',
                options: const {
                  'desativada': 'Desativada',
                  'opcional': 'Opcional',
                  'recomendada': 'Recomendada',
                  'obrigatoria_para_completo': 'Obrigatória p/ completo',
                  'obrigatoria_apos_vincular': 'Obrigatória após vínculo',
                },
              ),
              const Divider(),
              _buildSwitchCampo(
                'Permitir acesso básico sem Google',
                'permitir_acesso_basico_sem_google',
                description:
                    'Quando ativado, o aluno pode ver informações limitadas usando o login básico.',
              ),
              _buildSwitchCampo(
                'Permitir vincular no primeiro acesso',
                'permitir_vincular_google_no_primeiro_acesso',
                description:
                    'Permite criar o vínculo Google durante a primeira entrada.',
              ),
              _buildSwitchCampo(
                'Permitir trocar Google sem Admin',
                'permitir_trocar_google_sem_admin',
                description:
                    'Permite trocar a conta Google vinculada sem ação do admin.',
                padrao: false,
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
            color: context.uai.inscricoes,
            children: const [
              _ReadOnlyLine(title: 'Data de nascimento', value: 'Obrigatório'),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            children: [
              _buildResponsiveConfigGrid(
                maxWidth: constraints.maxWidth,
                children: [
                  _buildCard(
                    icon: Icons.badge_rounded,
                    title: 'Status geral',
                    subtitle: 'Módulos principais da Área do Aluno.',
                    color: context.uai.associacao,
                    children: [
                      _buildConfigSwitchTile(
                        title: 'Dashboard',
                        keyName: 'mostrar_dashboard',
                        activeDescription:
                            'Mostra o painel principal depois do login.',
                        inactiveDescription:
                            'O painel principal não aparece para o aluno.',
                        icon: Icons.dashboard_rounded,
                        color: context.uai.associacao,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Foto',
                        keyName: 'mostrar_foto',
                        activeDescription:
                            'Mostra a foto cadastrada no perfil do aluno.',
                        inactiveDescription:
                            'A foto do perfil fica oculta no painel.',
                        icon: Icons.photo_camera_rounded,
                        color: context.uai.info,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Academia e turma',
                        keyName: 'mostrar_academia_turma',
                        activeDescription:
                            'Mostra academia, turma e dados básicos da turma.',
                        inactiveDescription:
                            'Academia e turma não aparecem para o aluno.',
                        icon: Icons.groups_rounded,
                        color: context.uai.associacao,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Graduação atual',
                        keyName: 'mostrar_graduacao_atual',
                        activeDescription:
                            'Mostra a graduação atual no resumo do aluno.',
                        inactiveDescription:
                            'A graduação atual fica oculta no painel.',
                        icon: Icons.military_tech_rounded,
                        color: Colors.indigo,
                      ),
                    ],
                  ),
                  _buildPermissoesGoogleCard(
                    titulo: 'Acesso sem Google',
                    subtitulo: 'O que aparece usando apenas o login básico.',
                    prefixo: 'sem_google',
                    color: Colors.orange,
                  ),
                  _buildPermissoesGoogleCard(
                    titulo: 'Acesso com Google',
                    subtitulo:
                        'O que aparece com conta Google vinculada e confirmada.',
                    prefixo: 'com_google',
                    color: Colors.green,
                  ),
                  _buildCard(
                    icon: Icons.event_available_rounded,
                    title: 'Evento e participação',
                    subtitle: 'Detalhes exibidos nos eventos do aluno.',
                    color: Colors.indigo,
                    children: [
                      _buildConfigSwitchTile(
                        title: 'Eventos',
                        keyName: 'mostrar_eventos',
                        activeDescription:
                            'Mostra eventos em andamento e participações.',
                        inactiveDescription:
                            'Eventos e participações não aparecem.',
                        icon: Icons.event_rounded,
                        color: Colors.indigo,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Financeiro do evento',
                        keyName: 'mostrar_financeiro_eventos',
                        activeDescription:
                            'Valores do evento aparecem no detalhe da participação.',
                        inactiveDescription:
                            'Valores e saldos ficam ocultos no evento.',
                        icon: Icons.payments_rounded,
                        color: context.uai.success,
                      ),
                      _buildConfigDropdownTile(
                        title: 'Modo financeiro',
                        keyName: 'modo_financeiro',
                        description:
                            'Define se o aluno vê valores completos, resumo ou nada.',
                        icon: Icons.account_balance_wallet_rounded,
                        color: context.uai.success,
                        options: const {
                          'completo': 'Completo',
                          'resumo': 'Resumo',
                          'oculto': 'Oculto',
                        },
                      ),
                      _buildConfigSwitchTile(
                        title: 'Graduação do evento',
                        keyName: 'mostrar_graduacao_evento',
                        activeDescription:
                            'A nova graduação pode aparecer no evento.',
                        inactiveDescription:
                            'A nova graduação não aparece no evento.',
                        icon: Icons.emoji_events_rounded,
                        color: Colors.deepPurple,
                      ),
                      _buildConfigDropdownTile(
                        title: 'Modo graduação do evento',
                        keyName: 'modo_graduacao_evento',
                        description:
                            'Controla se a graduação aparece, fica em suspense ou é ocultada.',
                        icon: Icons.auto_awesome_rounded,
                        color: Colors.deepPurple,
                        options: const {
                          'completo': 'Completo',
                          'suspense': 'Suspense',
                          'oculto': 'Oculto',
                        },
                      ),
                      _buildConfigSwitchTile(
                        title: 'Camisa',
                        keyName: 'mostrar_camisa_evento',
                        activeDescription:
                            'Mostra tamanho e situação de entrega da camisa.',
                        inactiveDescription:
                            'Tamanho e entrega da camisa ficam ocultos.',
                        icon: Icons.checkroom_rounded,
                        color: Colors.orange,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Presença',
                        keyName: 'mostrar_presenca_evento',
                        activeDescription:
                            'Mostra se a presença no evento foi confirmada.',
                        inactiveDescription:
                            'A presença no evento não aparece.',
                        icon: Icons.fact_check_rounded,
                        color: context.uai.info,
                      ),
                      _buildConfigSwitchTile(
                        title: 'Certificados',
                        keyName: 'mostrar_certificados',
                        activeDescription:
                            'Mostra certificados liberados para visualização.',
                        inactiveDescription:
                            'Certificados não aparecem para o aluno.',
                        icon: Icons.card_membership_rounded,
                        color: Colors.brown,
                      ),
                    ],
                  ),
                  _buildCard(
                    icon: Icons.privacy_tip_rounded,
                    title: 'Dados pessoais',
                    subtitle: 'Nível de exposição dos dados do cadastro.',
                    color: Colors.teal,
                    children: [
                      _buildConfigSwitchTile(
                        title: 'Dados básicos',
                        keyName: 'mostrar_dados_basicos',
                        activeDescription:
                            'Mostra as informações básicas permitidas.',
                        inactiveDescription:
                            'Quando desativado, o card de dados básicos não aparece para o aluno.',
                        icon: Icons.badge_rounded,
                        color: Colors.teal,
                      ),
                      _buildConfigDropdownTile(
                        title: 'Modo dados básicos',
                        keyName: 'modo_dados_basicos',
                        description:
                            'Controla se os dados aparecem completos, limitados ou ocultos.',
                        icon: Icons.manage_accounts_rounded,
                        color: Colors.teal,
                        options: const {
                          'completo': 'Completo',
                          'limitado': 'Limitado',
                          'oculto': 'Oculto',
                        },
                      ),
                      _buildConfigDropdownTile(
                        title: 'Telefone',
                        keyName: 'modo_telefone',
                        description:
                            'Define se telefone aparece completo, mascarado ou oculto.',
                        icon: Icons.phone_android_rounded,
                        color: context.uai.warning,
                        options: const {
                          'completo': 'Completo',
                          'mascarado': 'Mascarado',
                          'oculto': 'Oculto',
                        },
                      ),
                      _buildConfigDropdownTile(
                        title: 'Endereço',
                        keyName: 'modo_endereco',
                        description:
                            'Define se endereço aparece completo, resumido ou oculto.',
                        icon: Icons.location_city_rounded,
                        color: Colors.blueGrey,
                        options: const {
                          'completo': 'Completo',
                          'cidade_bairro': 'Bairro e cidade',
                          'oculto': 'Oculto',
                        },
                      ),
                      _buildConfigDropdownTile(
                        title: 'Responsável',
                        keyName: 'modo_responsavel',
                        description:
                            'Define se os dados do responsável aparecem completos, só nome ou ocultos.',
                        icon: Icons.supervisor_account_rounded,
                        color: Colors.purple,
                        options: const {
                          'completo': 'Completo',
                          'nome': 'Somente nome',
                          'oculto': 'Oculto',
                        },
                      ),
                    ],
                  ),
                  _buildCard(
                    icon: Icons.edit_document,
                    title: 'Solicitações',
                    subtitle: 'Correções enviadas pelo aluno.',
                    color: Colors.orange,
                    children: [
                      _buildConfigSwitchTile(
                        title: 'Solicitar alteração',
                        keyName: 'mostrar_solicitacao_alteracao',
                        activeDescription:
                            'Permite enviar pedidos de correção para análise.',
                        inactiveDescription:
                            'O botão de solicitar alteração não aparece.',
                        icon: Icons.edit_note_rounded,
                        color: Colors.orange,
                      ),
                      _buildInfoBox(
                        icon: Icons.assignment_turned_in_rounded,
                        color: Colors.orange,
                        title: 'Fila de análise',
                        text:
                            'As solicitações continuam na aba Solicitações com comparação dos dados atuais e pedidos.',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildInfoBox(
                icon: Icons.lock_outline_rounded,
                color: context.uai.associacao,
                title: 'Somente leitura',
                text:
                    'Mesmo que os dados estejam visíveis, o aluno não altera a coleção original. Alterações futuras são enviadas como solicitação.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPermissoesGoogleCard({
    required String titulo,
    required String subtitulo,
    required String prefixo,
    required Color color,
  }) {
    return _buildCard(
      icon: Icons.tune_rounded,
      title: titulo,
      subtitle: subtitulo,
      color: color,
      children: [
        _buildSwitchCampo(
          'Mostrar dashboard',
          '${prefixo}_mostrar_dashboard',
          description: 'Mostra o painel principal depois do login.',
        ),
        _buildSwitchCampo(
          'Mostrar dados básicos',
          '${prefixo}_mostrar_dados_basicos',
          description:
              'Quando desativado, o card de dados básicos não aparece para o aluno.',
        ),
        _buildModoCampo(
          title: 'Modo dados básicos',
          keyName: '${prefixo}_modo_dados_basicos',
          description: 'Define se os dados aparecem completos ou limitados.',
          options: const {
            'completo': 'Completo',
            'limitado': 'Limitado',
            'oculto': 'Oculto',
          },
        ),
        const Divider(),
        _buildSwitchCampo(
          'Mostrar frequência',
          '${prefixo}_mostrar_frequencia',
          description: 'Permite que o aluno acompanhe presença e faltas.',
        ),
        _buildSwitchCampo(
          'Mostrar eventos',
          '${prefixo}_mostrar_eventos',
          description: 'Mostra eventos em andamento e participações.',
        ),
        _buildSwitchCampo(
          'Mostrar certificados',
          '${prefixo}_mostrar_certificados',
          description: 'Mostra certificados liberados para visualização.',
        ),
        _buildSwitchCampo(
          'Permitir solicitação de alteração',
          '${prefixo}_mostrar_solicitacao_alteracao',
          description:
              'Permite enviar pedidos de correção dos dados cadastrais.',
        ),
        const Divider(),
        _buildSwitchCampo(
          'Mostrar financeiro do evento',
          '${prefixo}_mostrar_financeiro_eventos',
          description: 'Mostra valores e situação financeira nos eventos.',
        ),
        _buildModoCampo(
          title: 'Modo financeiro',
          keyName: '${prefixo}_modo_financeiro',
          description: 'Define o nível de detalhe financeiro exibido.',
          options: const {
            'completo': 'Completo',
            'resumo': 'Resumo',
            'oculto': 'Oculto',
          },
        ),
        _buildSwitchCampo(
          'Mostrar graduação do evento',
          '${prefixo}_mostrar_graduacao_evento',
          description: 'Mostra a graduação relacionada à participação.',
        ),
        _buildModoCampo(
          title: 'Modo graduação do evento',
          keyName: '${prefixo}_modo_graduacao_evento',
          description: 'Define se a graduação aparece completa ou em suspense.',
          options: const {
            'completo': 'Completo',
            'suspense': 'Suspense',
            'oculto': 'Oculto',
          },
        ),
        _buildSwitchCampo(
          'Mostrar camisa',
          '${prefixo}_mostrar_camisa_evento',
          description: 'Mostra tamanho e situação de entrega da camisa.',
        ),
        _buildSwitchCampo(
          'Mostrar presença',
          '${prefixo}_mostrar_presenca_evento',
          description: 'Mostra se a presença no evento foi confirmada.',
        ),
      ],
    );
  }

  Widget _buildResponsiveConfigGrid({
    required double maxWidth,
    required List<Widget> children,
  }) {
    final columns = maxWidth >= 980 ? 2 : 1;
    final gap = columns > 1 ? 14.0 : 0.0;
    final itemWidth = columns > 1 ? (maxWidth - gap) / 2 : maxWidth;

    return Wrap(
      spacing: gap,
      runSpacing: 14,
      children: children
          .map((child) => SizedBox(width: itemWidth, child: child))
          .toList(),
    );
  }

  Widget _buildConfigSwitchTile({
    required String title,
    required String keyName,
    required String activeDescription,
    required String inactiveDescription,
    required IconData icon,
    required Color color,
  }) {
    final enabled = _getBool(keyName, padrao: true);
    final accent = _ensureVisible(color, context.uai.card);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;

        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    enabled ? activeDescription : inactiveDescription,
                    style: TextStyle(
                      color: context.uai.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Switch(
                        value: enabled,
                        activeColor: accent,
                        onChanged: (value) => _salvarCampo(keyName, value),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 12),
                    Switch(
                      value: enabled,
                      activeColor: accent,
                      onChanged: (value) => _salvarCampo(keyName, value),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildConfigDropdownTile({
    required String title,
    required String keyName,
    required String description,
    required IconData icon,
    required Color color,
    required Map<String, String> options,
  }) {
    return _buildModoCampo(
      title: title,
      keyName: keyName,
      description: description,
      icon: icon,
      color: color,
      options: options,
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
                leading: Icon(Icons.title_rounded, color: context.uai.warning),
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
                  color: context.uai.warning,
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
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.block_rounded, color: context.uai.warning),
                title: const Text('Mensagem da área desativada'),
                subtitle: Text(
                  _getString('mensagem_area_desativada'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editarTexto(
                  campo: 'mensagem_area_desativada',
                  titulo: 'Mensagem da área desativada',
                  label: 'Mensagem',
                  maxLines: 3,
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.visibility_off_rounded,
                  color: context.uai.warning,
                ),
                title: const Text('Mensagem de dados ocultos'),
                subtitle: Text(
                  _getString('mensagem_dados_ocultos'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editarTexto(
                  campo: 'mensagem_dados_ocultos',
                  titulo: 'Mensagem de dados ocultos',
                  label: 'Mensagem',
                  maxLines: 3,
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
            color: context.uai.warning,
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
                      return Center(
                        child: CircularProgressIndicator(
                          color: context.uai.primary,
                        ),
                      );
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
                        text:
                            'Quando um aluno pedir alteração, aparecerá aqui.',
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
                            backgroundColor: context.uai.warning.withOpacity(
                              0.12,
                            ),
                            child: Icon(
                              Icons.edit_document,
                              color: context.uai.warning,
                            ),
                          ),
                          title: Text(
                            data['aluno_nome']?.toString() ??
                                'Aluno não informado',
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
                                  color: context.uai.textSecondary,
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
      color: context.uai.textMuted,
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
                return Center(
                  child: CircularProgressIndicator(color: context.uai.primary),
                );
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
                    subtitle: Text(aprovado ? 'Aprovada' : 'Recusada'),
                    trailing: Text(
                      _formatTimestamp(data['analisado_em']),
                      style: TextStyle(
                        fontSize: 10,
                        color: context.uai.textSecondary,
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
              color: context.uai.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: context.uai.textPrimary.withOpacity(0.16),
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
                          color: context.uai.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSolicitacaoHeader(data, status),
                    const SizedBox(height: 14),
                    if ((data['observacao_aluno']?.toString() ?? '').isNotEmpty)
                      _buildObservacaoAluno(
                        data['observacao_aluno'].toString(),
                      ),
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
                                foregroundColor: context.uai.error,
                                side: BorderSide(
                                  color: context.uai.error.withOpacity(0.28),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _confirmarAprovarSolicitacao(doc),
                              icon: const Icon(Icons.check_circle_rounded),
                              label: const Text('APROVAR'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.uai.success,
                                foregroundColor: _readableOn(
                                  context.uai.success,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
        ? context.uai.warning
        : status == 'aprovado'
        ? context.uai.success
        : context.uai.error;

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
              color: _onPrimary().withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.assignment_turned_in_rounded,
              color: _onPrimary(),
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
                  style: TextStyle(
                    color: _onPrimary(),
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
                  style: TextStyle(
                    color: _onPrimary().withOpacity(0.80),
                    fontSize: 12,
                  ),
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
        color: _onPrimary().withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _onPrimary().withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _onPrimary(),
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
            Icon(Icons.compare_arrows_rounded, color: context.uai.primary),
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
        color: Color.alphaBlend(
          context.uai.warning.withOpacity(0.10),
          context.uai.card,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.uai.warning.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _labelCampo(campo),
            style: TextStyle(
              color: context.uai.warning,
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
                  Icon(Icons.arrow_forward_rounded, color: context.uai.warning),
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
        color: Color.alphaBlend(
          _ensureVisible(color, context.uai.card).withOpacity(0.08),
          context.uai.cardAlt,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _ensureVisible(color, context.uai.card).withOpacity(0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: color == Colors.grey
                  ? context.uai.textSecondary
                  : _ensureVisible(color, context.uai.card),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: [
              Icon(Icons.cancel_rounded, color: context.uai.error),
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
                backgroundColor: context.uai.error,
                foregroundColor: _readableOn(context.uai.error),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
                foregroundColor: _readableOn(cor),
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
        } else if (campo == 'nome' || campo == 'sexo' || campo == 'cidade') {
          updateAluno[campo] = valor?.toString().trim().toUpperCase() ?? '';
        } else {
          updateAluno[campo] = valor?.toString().trim() ?? '';
        }
      }

      final alunoRef = FirebaseFirestore.instance
          .collection('alunos')
          .doc(alunoId);
      DocumentSnapshot<Map<String, dynamic>> alunoSnapshot;

      try {
        alunoSnapshot = await alunoRef.get(
          const GetOptions(source: Source.server),
        );
      } catch (_) {
        alunoSnapshot = await alunoRef.get();
      }

      final dadosAntes = alunoSnapshot.data() ?? <String, dynamic>{};
      final dadosDepois = Map<String, dynamic>.from(dadosAntes)
        ..addAll(updateAluno);

      final admin = await _dadosAdminAtual();

      updateAluno['ultima_atualizacao'] = FieldValue.serverTimestamp();
      updateAluno['data_atualizacao'] = FieldValue.serverTimestamp();
      updateAluno['atualizado_por'] = admin['nome'];
      updateAluno['atualizado_por_uid'] = admin['uid'];

      final batch = FirebaseFirestore.instance.batch();

      batch.update(alunoRef, updateAluno);

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

      await AlunoHistoricoEdicaoService().registrarEdicaoPorSolicitacao(
        alunoId: alunoId,
        dadosAntes: dadosAntes,
        dadosDepois: dadosDepois,
        solicitacaoId: doc.id,
        observacaoAluno: data['observacao_aluno']?.toString(),
        observacaoAprovacao: 'Solicitação aprovada e aplicada no cadastro.',
      );
      if (!mounted) return;
      Navigator.pop(context);

      _mostrarSnack(
        '✅ Solicitação aprovada e cadastro atualizado.',
        Colors.green,
      );
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

      _mostrarSnack('Solicitação recusada.', context.uai.warning);
    } catch (e) {
      _mostrarSnack('Erro ao recusar solicitação: $e', Colors.red);
    }
  }

  Future<Map<String, String>> _dadosAdminAtual() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {'uid': '', 'nome': 'Sistema'};
    }

    String nome = user.email ?? 'Administrador';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();

      final data = doc.data();

      if (data != null) {
        nome =
            data['nome_completo']?.toString() ??
            data['nome']?.toString() ??
            data['email']?.toString() ??
            nome;
      }
    } catch (_) {}

    return {'uid': user.uid, 'nome': nome};
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

  Widget _buildTabContasGoogle() {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _buildCard(
            icon: Icons.account_circle_rounded,
            title: 'Contas vinculadas',
            subtitle: 'Acompanhe e resete vínculos Google da Área do Aluno.',
            color: Colors.deepPurple,
            children: [
              TextField(
                controller: _contasBuscaController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  labelText:
                      'Buscar por aluno, turma, e-mail Google ou nome Google',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  suffixIcon: _contasBuscaController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          onPressed: () {
                            _contasBuscaController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _buildContasAcoes(),
            ],
          ),
          const SizedBox(height: 14),
          _buildListaContasVinculadas(),
        ],
      ),
    );
  }

  Widget _buildContasAcoes() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _contasSelecionadas.isEmpty
              ? null
              : () => _confirmarResetVinculos(
                  alunoIds: _contasSelecionadas.toList(),
                ),
          icon: const Icon(Icons.link_off_rounded),
          label: Text('Resetar selecionados (${_contasSelecionadas.length})'),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmarResetVinculos(resetarTodos: true),
          icon: const Icon(Icons.warning_amber_rounded),
          label: const Text('Resetar todos'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _buildListaContasVinculadas() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('alunos')
          .orderBy('nome')
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: CircularProgressIndicator(color: context.uai.primary),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildInfoBox(
            icon: Icons.error_outline_rounded,
            color: Colors.red,
            title: 'Erro ao carregar alunos',
            text:
                'Pode ser necessário revisar permissões ou índices do Firestore.',
          );
        }

        final busca = _contasBuscaController.text.trim().toLowerCase();
        final todosDocs = snapshot.data?.docs ?? [];
        final docsVinculados = todosDocs
            .where((doc) => _isContaGoogleVinculada(doc.data()))
            .toList();
        final idsVinculados = docsVinculados.map((doc) => doc.id).toSet();
        _contasSelecionadas.removeWhere((id) => !idsVinculados.contains(id));

        final docs = docsVinculados.where((doc) {
          final data = doc.data();
          if (busca.isEmpty) return true;

          final haystack = [
            data['nome'],
            data['turma'],
            data['graduacao_nome'],
            data['graduacao_atual'],
            data['graduacao_nova'],
            data['graduacao'],
            data['corda'],
            data['corda_atual'],
            data['faixa'],
            data['areaAlunoGoogleUid'],
            data['areaAlunoGoogleEmail'],
            data['areaAlunoGoogleNome'],
          ].map((item) => item?.toString().toLowerCase() ?? '').join(' ');

          return haystack.contains(busca);
        }).toList();

        return Column(
          children: [
            _buildContasResumo(
              total: todosDocs.length,
              vinculadas: docsVinculados.length,
              semVinculo: todosDocs.length - docsVinculados.length,
              filtradas: docs.length,
              selecionadas: _contasSelecionadas.length,
              buscaAtiva: busca.isNotEmpty,
            ),
            const SizedBox(height: 12),
            if (docsVinculados.isEmpty)
              _buildInfoBox(
                icon: Icons.account_circle_outlined,
                color: Colors.grey,
                title: 'Sem contas vinculadas',
                text: 'Nenhuma conta Google vinculada ainda.',
              )
            else if (docs.isEmpty)
              _buildInfoBox(
                icon: Icons.search_off_rounded,
                color: Colors.grey,
                title: 'Nenhuma conta encontrada',
                text: 'A busca não encontrou contas vinculadas.',
              )
            else
              _buildContasGridResponsivo(docs),
          ],
        );
      },
    );
  }

  bool _isContaGoogleVinculada(Map<String, dynamic> data) {
    final uid = data['areaAlunoGoogleUid']?.toString().trim() ?? '';
    final email = data['areaAlunoGoogleEmail']?.toString().trim() ?? '';

    return data['areaAlunoGoogleVinculado'] == true ||
        uid.isNotEmpty ||
        email.isNotEmpty;
  }

  Widget _buildContasResumo({
    required int total,
    required int vinculadas,
    required int semVinculo,
    required int filtradas,
    required int selecionadas,
    required bool buscaAtiva,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildResumoPill(
          icon: Icons.groups_rounded,
          label: 'Total de alunos',
          value: total.toString(),
          color: context.uai.associacao,
        ),
        _buildResumoPill(
          icon: Icons.verified_user_rounded,
          label: 'Contas vinculadas',
          value: vinculadas.toString(),
          color: Colors.green,
        ),
        _buildResumoPill(
          icon: Icons.link_off_rounded,
          label: 'Sem vínculo',
          value: semVinculo.toString(),
          color: Colors.orange,
        ),
        if (buscaAtiva)
          _buildResumoPill(
            icon: Icons.manage_search_rounded,
            label: 'Resultados da busca',
            value: filtradas.toString(),
            color: context.uai.primary,
          ),
        if (selecionadas > 0)
          _buildResumoPill(
            icon: Icons.check_circle_rounded,
            label: 'Selecionados',
            value: selecionadas.toString(),
            color: context.uai.warning,
          ),
        if (selecionadas > 0)
          OutlinedButton.icon(
            onPressed: () => setState(_contasSelecionadas.clear),
            icon: const Icon(Icons.clear_all_rounded),
            label: const Text('Limpar seleção'),
          ),
      ],
    );
  }

  Widget _buildResumoPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContasGridResponsivo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final colunas = _calcularColunasContas(width);
        const spacing = 12.0;
        final itemWidth = colunas == 1
            ? width
            : (width - spacing * (colunas - 1)) / colunas;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: docs
              .map(
                (doc) => SizedBox(
                  width: itemWidth.isFinite ? itemWidth : double.infinity,
                  child: _buildContaAlunoTile(doc),
                ),
              )
              .toList(),
        );
      },
    );
  }

  int _calcularColunasContas(double width) {
    if (width >= 1500) return 3;
    if (width >= 1100) return 2;
    return 1;
  }

  Widget _buildContaAlunoTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    return FutureBuilder<String?>(
      future: _getSvgConta(data),
      builder: (context, snapshot) {
        return _buildContaGoogleCard(
          doc: doc,
          data: data,
          cordaSvg: snapshot.data,
          carregandoCorda: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }

  Widget _buildContaGoogleCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Map<String, dynamic> data,
    required String? cordaSvg,
    required bool carregandoCorda,
  }) {
    final t = context.uai;
    final selected = _contasSelecionadas.contains(doc.id);
    final nome = _textoConta(data['nome'], fallback: 'Aluno');
    final turma = _textoConta(data['turma'], fallback: 'Turma não informada');
    final graduacao = _obterNomeGraduacaoConta(data);
    final email = _textoConta(data['areaAlunoGoogleEmail']);
    final googleNome = _textoConta(data['areaAlunoGoogleNome']);
    final uid = _textoConta(data['areaAlunoGoogleUid']);
    final vinculadoEm = _formatTimestamp(data['areaAlunoVinculadoEm']);
    final ultimoAcesso = _formatTimestamp(
      data['areaAlunoUltimoAcessoGoogleEm'],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _toggleContaSelecionada(doc.id, !selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(t.primary.withOpacity(0.08), t.card)
                : t.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? t.primary : t.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAlunoFotoConta(data, nome),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nome.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                  height: 1.08,
                                ),
                              ),
                            ),
                            Checkbox(
                              value: selected,
                              onChanged: (value) => _toggleContaSelecionada(
                                doc.id,
                                value == true,
                              ),
                              visualDensity: VisualDensity.compact,
                              activeColor: t.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        _buildContaMiniInfo(
                          icon: Icons.groups_rounded,
                          text: turma,
                        ),
                        const SizedBox(height: 4),
                        _buildContaMiniInfo(
                          icon: Icons.workspace_premium_rounded,
                          text: graduacao,
                        ),
                      ],
                    ),
                  ),
                  if (cordaSvg != null || carregandoCorda) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      height: 60,
                      child: Center(
                        child: carregandoCorda
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: t.primary,
                                ),
                              )
                            : SvgPicture.string(
                                cordaSvg!,
                                height: 56,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildContaStatusChip(
                    icon: Icons.verified_user_rounded,
                    label: 'Google vinculado',
                    color: t.success,
                  ),
                  _buildContaStatusChip(
                    icon: Icons.school_rounded,
                    label: turma,
                    color: t.primary,
                  ),
                  if (!_isSemGraduacaoConta(graduacao))
                    _buildContaStatusChip(
                      icon: Icons.military_tech_rounded,
                      label: graduacao,
                      color: t.associacao,
                    ),
                  if (uid.isNotEmpty)
                    _buildContaStatusChip(
                      icon: Icons.fingerprint_rounded,
                      label: 'UID ${_uidCurto(uid)}',
                      color: t.warning,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  children: [
                    if (email.isNotEmpty)
                      _buildContaMiniInfo(
                        icon: Icons.alternate_email_rounded,
                        text: email,
                      ),
                    if (googleNome.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildContaMiniInfo(
                        icon: Icons.person_pin_rounded,
                        text: googleNome,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildContaMiniInfo(
                      icon: Icons.link_rounded,
                      text: vinculadoEm == '--'
                          ? 'Data do vínculo não registrada'
                          : 'Vinculado em $vinculadoEm',
                    ),
                    const SizedBox(height: 6),
                    _buildContaMiniInfo(
                      icon: Icons.history_rounded,
                      text: ultimoAcesso == '--'
                          ? 'Sem acesso Google registrado'
                          : 'Último acesso Google $ultimoAcesso',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmarResetVinculos(alunoIds: [doc.id]),
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                  label: const Text('Resetar vínculo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.error,
                    side: BorderSide(color: t.error.withOpacity(0.45)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleContaSelecionada(String alunoId, bool selected) {
    setState(() {
      if (selected) {
        _contasSelecionadas.add(alunoId);
      } else {
        _contasSelecionadas.remove(alunoId);
      }
    });
  }

  Widget _buildAlunoFotoConta(Map<String, dynamic> data, String nome) {
    final t = context.uai;
    final fotoUrl = _textoConta(data['foto_perfil_aluno']);
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

    Widget fallback() {
      return Container(
        color: t.primary.withOpacity(0.12),
        alignment: Alignment.center,
        child: Text(
          inicial,
          style: TextStyle(
            color: t.primary,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: 72,
        height: 72,
        child: fotoUrl.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => fallback(),
                errorWidget: (context, url, error) => fallback(),
              ),
      ),
    );
  }

  Widget _buildContaStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContaMiniInfo({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: context.uai.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _textoConta(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _uidCurto(String uid) {
    if (uid.length <= 8) return uid;
    return uid.substring(0, 8);
  }

  String _graduacaoKeyConta(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _obterNomeGraduacaoConta(Map<String, dynamic> data) {
    final graduacaoId = _textoConta(data['graduacao_id']);
    if (graduacaoId.isNotEmpty) {
      final cached = _contasGraduacoesCache[graduacaoId];
      if (cached != null) {
        return _textoConta(
          cached['nome_graduacao'] ?? cached['nome'],
          fallback: graduacaoId,
        );
      }
    }

    final campos = [
      data['graduacao_nome'],
      data['graduacao_atual'],
      data['graduacao_nova'],
      data['graduacao'],
      data['corda'],
      data['corda_atual'],
      data['faixa'],
    ];

    for (final value in campos) {
      final text = _textoConta(value);
      if (text.isNotEmpty && !_isSemGraduacaoConta(text)) {
        return text;
      }
    }

    return 'SEM GRADUACAO';
  }

  bool _isSemGraduacaoConta(String value) {
    final normalized = value.toUpperCase().replaceAll('Ç', 'C');
    return normalized == 'SEM GRADUACAO';
  }

  Future<String?> _getSvgConta(Map<String, dynamic> data) async {
    final svgBase = _contasCordaSvg;
    if (svgBase == null) return null;

    final nomeGraduacao = _obterNomeGraduacaoConta(data);
    if (nomeGraduacao.isEmpty || _isSemGraduacaoConta(nomeGraduacao)) {
      return null;
    }

    final graduacaoId = _textoConta(data['graduacao_id']);
    final cacheKey =
        'conta_${graduacaoId}_${_graduacaoKeyConta(nomeGraduacao)}';
    if (_contasSvgCache.containsKey(cacheKey)) return _contasSvgCache[cacheKey];

    Map<String, dynamic>? graduacao;
    if (graduacaoId.isNotEmpty) {
      graduacao = await _carregarGraduacaoConta(
        id: graduacaoId,
        nomeFallback: nomeGraduacao,
      );
    }

    graduacao ??= _contasGraduacoesCache[_graduacaoKeyConta(nomeGraduacao)];
    graduacao ??= await _carregarGraduacaoConta(nome: nomeGraduacao);
    if (graduacao == null) return null;

    final document = xml.XmlDocument.parse(svgBase);
    void changeColor(String id, Color color) {
      final element = document.rootElement.descendants
          .whereType<xml.XmlElement>()
          .firstWhere(
            (e) => e.getAttribute('id') == id,
            orElse: () => xml.XmlElement(xml.XmlName('')),
          );
      if (element.name.local.isEmpty) return;

      final hex =
          '#${color.value.toRadixString(16).substring(2).toLowerCase()}';
      final oldStyle = element.getAttribute('style') ?? '';
      element.setAttribute('fill', hex);
      element.setAttribute(
        'style',
        oldStyle.contains('fill:')
            ? oldStyle.replaceAll(
                RegExp(r'fill:\s*#[0-9a-fA-F]{3,8}'),
                'fill:$hex',
              )
            : 'fill:$hex;$oldStyle',
      );
    }

    changeColor('cor1', _colorFromHexConta(graduacao['hex_cor1']));
    changeColor('cor2', _colorFromHexConta(graduacao['hex_cor2']));
    changeColor('corponta1', _colorFromHexConta(graduacao['hex_ponta1']));
    changeColor('corponta2', _colorFromHexConta(graduacao['hex_ponta2']));

    final result = document.toXmlString();
    _contasSvgCache[cacheKey] = result;
    return result;
  }

  Future<Map<String, dynamic>?> _carregarGraduacaoConta({
    String? id,
    String? nome,
    String? nomeFallback,
  }) async {
    try {
      if (id != null && id.trim().isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('graduacoes')
            .doc(id.trim())
            .get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          _salvarGraduacaoContaNoCache(
            doc.id,
            data,
            nomeFallback: nomeFallback,
          );
          return _contasGraduacoesCache[doc.id];
        }
      }

      final nomeBusca = nome?.trim() ?? '';
      if (nomeBusca.isEmpty) return null;

      final snapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .where('nome_graduacao', isEqualTo: nomeBusca)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      _salvarGraduacaoContaNoCache(doc.id, doc.data(), nomeFallback: nomeBusca);
      return _contasGraduacoesCache[_graduacaoKeyConta(nomeBusca)];
    } catch (e) {
      debugPrint('Erro ao carregar graduação da conta: $e');
      return null;
    }
  }

  void _salvarGraduacaoContaNoCache(
    String id,
    Map<String, dynamic> data, {
    String? nomeFallback,
  }) {
    final nome = _textoConta(
      data['nome_graduacao'] ?? data['nome'] ?? data['titulo'],
      fallback: nomeFallback ?? '',
    );
    if (nome.isEmpty) return;

    final item = {...data, 'id': id, 'nome_graduacao': nome};
    _contasGraduacoesCache[id] = item;
    _contasGraduacoesCache[nome] = item;
    _contasGraduacoesCache[_graduacaoKeyConta(nome)] = item;
  }

  Color _colorFromHexConta(dynamic value) {
    final cleaned = value?.toString().replaceAll('#', '').trim() ?? '';
    try {
      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }
      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {
      return context.uai.textMuted;
    }
    return context.uai.textMuted;
  }

  Widget buildContaAlunoTileAntigo(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final t = context.uai;
    final vinculado = _isContaGoogleVinculada(data);
    final selected = _contasSelecionadas.contains(doc.id);
    final nome = data['nome']?.toString() ?? 'Aluno';
    final turma = data['turma']?.toString() ?? '';
    final email = data['areaAlunoGoogleEmail']?.toString() ?? '';
    final googleNome = data['areaAlunoGoogleNome']?.toString() ?? '';
    final vinculadoEm = _formatTimestamp(data['areaAlunoVinculadoEm']);
    final ultimoAcesso = _formatTimestamp(
      data['areaAlunoUltimoAcessoGoogleEm'],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? t.primary : t.border),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (value) {
          setState(() {
            if (value == true) {
              _contasSelecionadas.add(doc.id);
            } else {
              _contasSelecionadas.remove(doc.id);
            }
          });
        },
        title: Text(
          nome,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(turma.isEmpty ? 'Turma não informada' : turma),
              const SizedBox(height: 3),
              Text(
                vinculado
                    ? [
                        if (email.isNotEmpty) email,
                        if (googleNome.isNotEmpty) googleNome,
                        if (vinculadoEm.isNotEmpty) 'Vinculado em $vinculadoEm',
                        if (ultimoAcesso.isNotEmpty)
                          'Último acesso Google $ultimoAcesso',
                      ].join(' • ')
                    : 'Aguardando vínculo',
              ),
              if (vinculado) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _confirmarResetVinculos(alunoIds: [doc.id]),
                    icon: const Icon(Icons.link_off_rounded, size: 16),
                    label: const Text('Resetar vínculo'),
                  ),
                ),
              ],
            ],
          ),
        ),
        secondary: Icon(
          vinculado ? Icons.verified_user_rounded : Icons.link_off_rounded,
          color: vinculado ? Colors.green : Colors.grey,
        ),
        controlAffinity: ListTileControlAffinity.leading,
        isThreeLine: vinculado,
        dense: true,
        activeColor: t.primary,
      ),
    );
  }

  Future<void> _confirmarResetVinculos({
    List<String> alunoIds = const [],
    bool resetarTodos = false,
  }) async {
    final total = resetarTodos
        ? 'todos os alunos'
        : '${alunoIds.length} aluno(s)';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resetar vínculo Google'),
        content: Text(
          'Esta ação vai remover o vínculo Google de $total. Eles poderão vincular uma nova conta no próximo acesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESETAR'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final callable = resetarTodos
          ? 'resetarVinculosGoogleAreaAlunoEmMassa'
          : 'resetarVinculoGoogleAreaAluno';
      final payload = resetarTodos
          ? {'resetarTodos': true}
          : alunoIds.length == 1
          ? {'alunoId': alunoIds.first}
          : {'alunoIds': alunoIds};

      final result = await FirebaseFunctions.instance
          .httpsCallable(callable)
          .call(payload);
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] == true) {
        setState(_contasSelecionadas.clear);
        _mostrarSnack('Vínculo Google resetado.', Colors.green);
      } else {
        _mostrarSnack(
          data['message']?.toString() ?? 'Não foi possível resetar o vínculo.',
          Colors.red,
        );
      }
    } catch (e) {
      _mostrarSnack('Erro ao resetar vínculo: $e', Colors.red);
    }
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
          colors: [context.uai.textPrimary, context.uai.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.textPrimary.withOpacity(0.16),
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
              color: _onPrimary().withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.manage_history_rounded,
              color: _onPrimary(),
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Central de logs',
                  style: TextStyle(
                    color: _onPrimary(),
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Acompanhe acessos, tentativas bloqueadas e faça limpeza quando necessário.',
                  style: TextStyle(
                    color: _onPrimary().withOpacity(0.78),
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
        color: Color.alphaBlend(
          context.uai.error.withOpacity(0.10),
          context.uai.card,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.error.withOpacity(0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.delete_sweep_rounded, color: context.uai.error),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limpeza de logs',
                      style: TextStyle(
                        color: context.uai.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Apague apenas logs de acesso/erro. Solicitações não são apagadas.',
                      style: TextStyle(
                        color: context.uai.error,
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
          foregroundColor: _readableOn(color),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
      length: 3,
      child: Container(
        decoration: BoxDecoration(
          color: context.uai.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.uai.cardAlt),
          boxShadow: [
            BoxShadow(
              color: context.uai.textPrimary.withOpacity(0.035),
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
                      color: context.uai.textMuted.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: context.uai.textMuted,
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
                            color: context.uai.textSecondary,
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
                color: context.uai.cardAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: context.uai.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: _onPrimary(),
                unselectedLabelColor: context.uai.textSecondary,
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
                  Tab(
                    icon: Icon(Icons.security_rounded, size: 18),
                    text: 'Alertas',
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
                  _buildAlertasSegurancaLista(),
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
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
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
            final dispositivo = _mapFromDynamic(data['dispositivo']);
            final possivelTroca = data['possivel_troca_aluno'] == true;

            return _buildLogCard(
              icon: Icons.check_circle_rounded,
              color: possivelTroca ? Colors.deepOrange : Colors.green,
              title: data['aluno_nome']?.toString() ?? 'Aluno não informado',
              subtitle:
                  data['turma']?.toString() ??
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
                if ((data['turma']?.toString() ?? '').isNotEmpty)
                  _LogChip(
                    icon: Icons.groups_rounded,
                    label: data['turma'].toString(),
                    color: context.uai.associacao,
                  ),
                if (dispositivo.isNotEmpty)
                  _LogChip(
                    icon: Icons.devices_rounded,
                    label: _textoDispositivoLog(dispositivo),
                    color: context.uai.textSecondary,
                  ),
                if ((dispositivo['navegador_nome']?.toString() ?? '')
                    .isNotEmpty)
                  _LogChip(
                    icon: Icons.public_rounded,
                    label: dispositivo['navegador_nome'].toString(),
                    color: Colors.indigo,
                  ),
                if ((dispositivo['sistema_operacional_aproximado']
                            ?.toString() ??
                        '')
                    .isNotEmpty)
                  _LogChip(
                    icon: Icons.memory_rounded,
                    label: dispositivo['sistema_operacional_aproximado']
                        .toString(),
                    color: Colors.purple,
                  ),
                if (possivelTroca)
                  _LogChip(
                    icon: Icons.report_rounded,
                    label: 'Mesmo aparelho em outro aluno',
                    color: Colors.deepOrange,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _textoDispositivoLog(Map<String, dynamic> dispositivo) {
    final tipo = dispositivo['tipo_dispositivo']?.toString().trim() ?? '';
    final sistema =
        dispositivo['sistema_operacional_aproximado']?.toString().trim() ??
        dispositivo['tipo_plataforma']?.toString().trim() ??
        '';
    final marca =
        dispositivo['celular_marca_aproximada']?.toString().trim() ?? '';
    final modelo =
        dispositivo['celular_modelo_aproximado']?.toString().trim() ?? '';

    final partes = <String>[
      if (tipo.isNotEmpty) tipo,
      if (sistema.isNotEmpty) sistema,
      if (marca.isNotEmpty &&
          marca != 'desconhecido' &&
          marca != 'nao_aplicavel')
        marca,
      if (modelo.isNotEmpty && modelo != 'nao_disponivel_pelo_navegador')
        modelo,
    ];

    return partes.isEmpty ? 'Dispositivo' : partes.join(' / ');
  }

  Widget _buildLogsErroLista() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _configService.streamLogsErroAreaAluno(limite: 40),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
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
                  color: context.uai.warning,
                ),
                _LogChip(
                  icon: Icons.cake_rounded,
                  label: nascimento,
                  color: context.uai.associacao,
                ),
                _LogChip(
                  icon: Icons.phone_android_rounded,
                  label: 'Tel: $telefone',
                  color: context.uai.textMuted,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAlertasSegurancaLista() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('area_aluno_alertas_seguranca')
          .where('resolvido', isEqualTo: false)
          .orderBy('criado_em', descending: true)
          .limit(40)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: context.uai.primary),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyLog(
            icon: Icons.error_outline_rounded,
            text:
                'Erro ao carregar alertas. Pode ser necessário criar índice no Firestore.',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyLog(
            icon: Icons.verified_user_rounded,
            text: 'Nenhum alerta pendente.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final dispositivo = _mapFromDynamic(data['dispositivo']);

            return _buildLogCard(
              icon: Icons.report_rounded,
              color: Colors.deepOrange,
              title:
                  data['aluno_nome_atual']?.toString() ?? 'Aluno não informado',
              subtitle: 'Mesmo dispositivo usado em múltiplos alunos',
              timestamp: data['criado_em'],
              chips: [
                _LogChip(
                  icon: Icons.devices_rounded,
                  label: _textoDispositivoLog(dispositivo),
                  color: Colors.deepOrange,
                ),
                _LogChip(
                  icon: Icons.security_rounded,
                  label: data['tipo']?.toString() ?? 'alerta',
                  color: Colors.red,
                ),
              ],
              trailing: TextButton(
                onPressed: () => _marcarAlertaResolvido(doc.reference),
                child: const Text('RESOLVER'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _marcarAlertaResolvido(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      await ref.set({
        'resolvido': true,
        'resolvido_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _mostrarSnack('Alerta marcado como resolvido.', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack('Erro ao resolver alerta: $e', Colors.red);
    }
  }

  Widget _buildLogCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required dynamic timestamp,
    required List<_LogChip> chips,
    Widget? trailing,
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
                    color: context.uai.textSecondary,
                    fontSize: 11.5,
                    height: 1.20,
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips
                        .map((chip) => _buildLogMiniChip(chip))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: context.uai.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.uai.border),
                ),
                child: Text(
                  _formatTimestamp(timestamp),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.uai.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(height: 6), trailing],
            ],
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
          colors: [context.uai.primary, context.uai.error],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withOpacity(0.16),
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
              color: _onPrimary().withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.school_rounded, color: _onPrimary(), size: 30),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Painel da Área do Aluno',
                  style: TextStyle(
                    color: _onPrimary(),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Controle acesso, segurança, dados visíveis, textos e logs.',
                  style: TextStyle(
                    color: _onPrimary().withOpacity(0.80),
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
            : _onPrimary().withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _onPrimary().withOpacity(0.24)),
      ),
      child: Text(
        visivel ? 'ATIVA' : 'OCULTA',
        style: TextStyle(
          color: _onPrimary(),
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

    final cards = [
      _ResumoCardData(
        icon: visivel ? Icons.visibility : Icons.visibility_off,
        label: 'Site',
        value: visivel ? 'Ativo' : 'Oculto',
        color: visivel ? context.uai.success : context.uai.textMuted,
      ),
      _ResumoCardData(
        icon: Icons.person_pin_rounded,
        label: 'Acesso',
        value: apenasAtivos ? 'Só ativos' : 'Todos',
        color: context.uai.info,
      ),
      _ResumoCardData(
        icon: Icons.phone_android_rounded,
        label: 'Telefone',
        value: telefone ? 'Exige' : 'Não exige',
        color: context.uai.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final spacing = compact ? 8.0 : 10.0;
        final itemWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * 2) / 3;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            return SizedBox(
              width: itemWidth,
              child: _buildMiniResumoCard(
                icon: card.icon,
                label: card.label,
                value: card.value,
                color: card.color,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMiniResumoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    final bg = Color.alphaBlend(accent.withOpacity(0.055), t.card);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: accent.withOpacity(0.16)),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem(String text, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: done ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: done
                    ? context.uai.textPrimary
                    : context.uai.textSecondary,
                fontWeight: done ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchCampo(
    String title,
    String key, {
    String? description,
    bool padrao = true,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;
        final value = _getBool(key, padrao: padrao);

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (description != null && description.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: context.uai.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Switch(
                        value: value,
                        activeColor: context.uai.associacao,
                        onChanged: (value) => _salvarCampo(key, value),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    Switch(
                      value: value,
                      activeColor: context.uai.associacao,
                      onChanged: (value) => _salvarCampo(key, value),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildModoCampo({
    required String title,
    required String keyName,
    required Map<String, String> options,
    String? description,
    IconData? icon,
    Color? color,
  }) {
    final value = options.containsKey(_getString(keyName))
        ? _getString(keyName)
        : options.keys.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 500;
        final accent = _ensureVisible(
          color ?? context.uai.associacao,
          context.uai.card,
        );

        final label = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (description != null && description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

        final dropdown = DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: options.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (newValue) {
            if (newValue == null) return;
            _salvarCampo(keyName, newValue);
          },
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [label, const SizedBox(height: 8), dropdown],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    SizedBox(width: 210, child: dropdown),
                  ],
                ),
        );
      },
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
            color: context.uai.cardAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.uai.border),
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
                  color: context.uai.textSecondary,
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
        border: Border.all(
          color: _ensureVisible(color, context.uai.card).withOpacity(0.14),
        ),
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
                    color: context.uai.textPrimary,
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
                foregroundColor: context.uai.error,
                side: BorderSide(color: context.uai.error.withOpacity(0.28)),
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
                foregroundColor: context.uai.error,
                side: BorderSide(color: context.uai.error.withOpacity(0.28)),
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
              backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error),
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
                return Center(
                  child: CircularProgressIndicator(color: context.uai.primary),
                );
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
                    title:
                        data['aluno_nome']?.toString() ?? 'Aluno não informado',
                    subtitle:
                        data['turma']?.toString() ??
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
                return Center(
                  child: CircularProgressIndicator(color: context.uai.primary),
                );
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
        style: TextStyle(fontSize: 10, color: context.uai.textSecondary),
      ),
    );
  }

  Widget _buildEmptyLog({required IconData icon, required String text}) {
    return _buildEmptyState(icon: icon, title: 'Sem registros', text: text);
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
            Icon(icon, size: 38, color: context.uai.textMuted),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textSecondary, fontSize: 12),
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
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 47,
                  height: 47,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                    border: Border.all(color: accent.withOpacity(0.16)),
                  ),
                  child: Icon(icon, color: accent, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
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

class _ResumoCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ResumoCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
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

  const _ReadOnlyLine({required this.title, required this.value});

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
                color: context.uai.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
