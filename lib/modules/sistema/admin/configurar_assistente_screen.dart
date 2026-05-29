import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/shared/services/assistente_chat_service.dart';

class ConfigurarAssistenteScreen extends StatefulWidget {
  const ConfigurarAssistenteScreen({super.key});

  @override
  State<ConfigurarAssistenteScreen> createState() =>
      _ConfigurarAssistenteScreenState();
}

class _ConfigurarAssistenteScreenState
    extends State<ConfigurarAssistenteScreen> {
  final AssistenteChatService _service = AssistenteChatService();

  bool _carregando = true;
  bool _salvando = false;

  Map<String, dynamic> _config = {};
  final Map<String, TextEditingController> _controllers = {};

  List<Map<String, dynamic>> _turmas = [];
  Map<String, bool> _turmasSelecionadas = {};

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
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

  Color _onPrimary() => _readableOn(context.uai.primary);

  Map<String, dynamic> _section(String key) {
    final value = _config[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);

    final created = <String, dynamic>{};
    _config[key] = created;
    return created;
  }

  Future<void> _carregarConfiguracoes() async {
    if (mounted) setState(() => _carregando = true);

    try {
      _config = await _service.carregarConfiguracoesCompletas();
      _turmas = await _service.buscarTodasTurmas();
      _turmasSelecionadas = Map<String, bool>.from(
        (_config['turmas_selecionadas'] as Map?) ?? <String, bool>{},
      );

      _inicializarControllers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar configurações: $e'),
            backgroundColor: context.uai.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _setController(String key, String value) {
    _controllers[key]?.dispose();
    _controllers[key] = TextEditingController(text: value);
  }

  void _inicializarControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();

    final perfil = _section('perfil');
    final informacoes = _section('informacoes');
    final regras = _section('regras');
    final aparencia = _section('aparencia');

    _setController('perfil_nome', perfil['nome']?.toString() ?? 'Assistente UAI');
    _setController('perfil_avatar', perfil['avatar']?.toString() ?? '🤖');
    _setController(
      'perfil_mensagem_boas_vindas',
      perfil['mensagem_boas_vindas']?.toString() ?? '',
    );
    _setController(
      'perfil_cor_assistente',
      perfil['cor_assistente']?.toString() ?? '#B71C1C',
    );

    _setController(
      'info_nome_grupo',
      informacoes['nome_grupo']?.toString() ?? 'UAI Capoeira',
    );
    _setController('info_cidade', informacoes['cidade']?.toString() ?? '');
    _setController('info_endereco', informacoes['endereco']?.toString() ?? '');
    _setController('info_telefone', informacoes['telefone']?.toString() ?? '');
    _setController('info_email', informacoes['email']?.toString() ?? '');
    _setController(
      'info_dias_treino',
      informacoes['dias_treino']?.toString() ?? '',
    );
    _setController(
      'info_horario_treino',
      informacoes['horario_treino']?.toString() ?? '',
    );
    _setController(
      'info_local_treino',
      informacoes['local_treino']?.toString() ?? '',
    );
    _setController(
      'info_valor_mensalidade',
      informacoes['valor_mensalidade']?.toString() ?? '',
    );

    _setController(
      'regras_descricao',
      regras['descricao_geral']?.toString() ?? '',
    );
    _setController(
      'regras_resposta_fora_tema',
      regras['resposta_fora_tema']?.toString() ?? '',
    );

    _setController(
      'aparencia_cor_primaria',
      aparencia['cor_primaria']?.toString() ?? '#B71C1C',
    );
    _setController(
      'aparencia_cor_secundaria',
      aparencia['cor_secundaria']?.toString() ?? '#F44336',
    );
  }

  Future<void> _salvarConfiguracoes() async {
    if (!mounted) return;
    setState(() => _salvando = true);

    try {
      final perfil = _section('perfil');
      final informacoes = _section('informacoes');
      final regras = _section('regras');
      final aparencia = _section('aparencia');

      perfil['nome'] = _controllers['perfil_nome']?.text.trim() ?? '';
      perfil['avatar'] = _controllers['perfil_avatar']?.text.trim() ?? '';
      perfil['mensagem_boas_vindas'] =
          _controllers['perfil_mensagem_boas_vindas']?.text.trim() ?? '';
      perfil['cor_assistente'] =
          _controllers['perfil_cor_assistente']?.text.trim() ?? '';

      informacoes['nome_grupo'] =
          _controllers['info_nome_grupo']?.text.trim() ?? '';
      informacoes['cidade'] = _controllers['info_cidade']?.text.trim() ?? '';
      informacoes['endereco'] = _controllers['info_endereco']?.text.trim() ?? '';
      informacoes['telefone'] = _controllers['info_telefone']?.text.trim() ?? '';
      informacoes['email'] = _controllers['info_email']?.text.trim() ?? '';
      informacoes['dias_treino'] =
          _controllers['info_dias_treino']?.text.trim() ?? '';
      informacoes['horario_treino'] =
          _controllers['info_horario_treino']?.text.trim() ?? '';
      informacoes['local_treino'] =
          _controllers['info_local_treino']?.text.trim() ?? '';
      informacoes['valor_mensalidade'] =
          _controllers['info_valor_mensalidade']?.text.trim() ?? '';

      regras['descricao_geral'] =
          _controllers['regras_descricao']?.text.trim() ?? '';
      regras['resposta_fora_tema'] =
          _controllers['regras_resposta_fora_tema']?.text.trim() ?? '';

      aparencia['cor_primaria'] =
          _controllers['aparencia_cor_primaria']?.text.trim() ?? '';
      aparencia['cor_secundaria'] =
          _controllers['aparencia_cor_secundaria']?.text.trim() ?? '';

      _config['perfil'] = perfil;
      _config['informacoes'] = informacoes;
      _config['regras'] = regras;
      _config['aparencia'] = aparencia;
      _config['turmas_selecionadas'] = _turmasSelecionadas;

      await _service.salvarConfiguracoesCompletas(_config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Configurações salvas com sucesso!'),
            backgroundColor: context.uai.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
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
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: const Text(
            'Configurar Assistente',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ATIVAR',
                    style: TextStyle(
                      color: _onPrimary(),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Switch(
                    value: _config['ativo'] == true,
                    activeColor: t.success,
                    onChanged: (value) async {
                      setState(() => _config['ativo'] = value);
                      await _salvarConfiguracoes();
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              icon: _salvando
                  ? SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  color: _onPrimary(),
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.save_rounded),
              onPressed: _salvando ? null : _salvarConfiguracoes,
              tooltip: 'Salvar',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Container(
              color: t.primary,
              width: double.infinity,
              child: SafeArea(
                top: false,
                bottom: false,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: _onPrimary(),
                  indicatorWeight: 3,
                  labelColor: _onPrimary(),
                  unselectedLabelColor: _onPrimary().withOpacity(0.70),
                  labelStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'PERFIL', icon: Icon(Icons.person_rounded)),
                    Tab(text: 'INFORMAÇÕES', icon: Icon(Icons.info_rounded)),
                    Tab(text: 'REGRAS', icon: Icon(Icons.gavel_rounded)),
                    Tab(text: 'AÇÕES', icon: Icon(Icons.touch_app_rounded)),
                    Tab(text: 'APARÊNCIA', icon: Icon(Icons.palette_rounded)),
                    Tab(text: 'RESPOSTAS', icon: Icon(Icons.quickreply_rounded)),
                    Tab(text: 'TURMAS', icon: Icon(Icons.school_rounded)),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildPerfilTab(),
            _buildInformacoesTab(),
            _buildRegrasTab(),
            _buildAcoesTab(),
            _buildAparenciaTab(),
            _buildRespostasTab(),
            _buildTurmasTab(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border(top: BorderSide(color: t.border)),
              boxShadow: t.softShadow,
            ),
            child: ElevatedButton.icon(
              onPressed: _salvando ? null : _salvarConfiguracoes,
              icon: _salvando
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _readableOn(t.primary),
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.save_rounded),
              label: Text(_salvando ? 'SALVANDO...' : 'SALVAR ASSISTENTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabScaffold(List<Widget> children) {
    return RefreshIndicator(
      color: context.uai.primary,
      backgroundColor: context.uai.surface,
      onRefresh: _carregarConfiguracoes,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerfilTab() {
    return _tabScaffold([
      _buildHero(
        icon: Icons.smart_toy_rounded,
        title: 'Assistente Chat',
        subtitle:
        'Configure identidade, comportamento e informações que o assistente usa no site.',
        chips: [
          _heroChip(Icons.power_settings_new_rounded,
              _config['ativo'] == true ? 'Ativo' : 'Inativo'),
          _heroChip(Icons.school_rounded, '${_turmasSelecionadas.length} turmas'),
        ],
      ),
      const SizedBox(height: 14),
      _buildCard(
        icon: Icons.badge_rounded,
        title: 'Identidade do Assistente',
        subtitle: 'Nome, avatar e mensagem inicial exibida para o visitante.',
        color: context.uai.primary,
        children: [
          _buildTextField(
            label: 'Nome do Assistente',
            controllerKey: 'perfil_nome',
            hint: 'Ex: Assistente UAI',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Avatar',
            controllerKey: 'perfil_avatar',
            hint: 'Ex: 🤖, 💬, 🎭',
            icon: Icons.emoji_emotions_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Mensagem de boas-vindas',
            controllerKey: 'perfil_mensagem_boas_vindas',
            hint: 'Mensagem inicial do chat',
            icon: Icons.waving_hand_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _buildColorField('Cor do Assistente', 'perfil_cor_assistente'),
        ],
      ),
      const SizedBox(height: 14),
      _buildCard(
        icon: Icons.power_settings_new_rounded,
        title: 'Status',
        subtitle: 'Ative ou desative o chat no site público.',
        color: _config['ativo'] == true ? context.uai.success : context.uai.error,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Assistente ativo',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              _config['ativo'] == true
                  ? 'O chat aparece no site.'
                  : 'O chat fica oculto no site.',
              style: TextStyle(color: context.uai.textSecondary),
            ),
            value: _config['ativo'] == true,
            activeColor: context.uai.success,
            onChanged: (value) async {
              setState(() => _config['ativo'] = value);
              await _salvarConfiguracoes();
            },
          ),
        ],
      ),
    ]);
  }

  Widget _buildInformacoesTab() {
    return _tabScaffold([
      _buildCard(
        icon: Icons.business_rounded,
        title: 'Informações do Grupo',
        subtitle: 'Dados principais usados nas respostas automáticas.',
        color: context.uai.info,
        children: [
          _buildTextField(
            label: 'Nome do Grupo',
            controllerKey: 'info_nome_grupo',
            hint: 'Ex: UAI Capoeira',
            icon: Icons.groups_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Cidade',
            controllerKey: 'info_cidade',
            hint: 'Ex: Bocaiuva - MG',
            icon: Icons.location_city_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Endereço completo',
            controllerKey: 'info_endereco',
            hint: 'Rua, número, bairro',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Telefone',
            controllerKey: 'info_telefone',
            hint: 'Ex: (38) 99999-9999',
            icon: Icons.phone_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Email',
            controllerKey: 'info_email',
            hint: 'contato@uaicapoeira.com.br',
            icon: Icons.email_rounded,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _buildCard(
        icon: Icons.sports_martial_arts_rounded,
        title: 'Treinos',
        subtitle: 'Horários, local e mensalidade informados pelo assistente.',
        color: context.uai.success,
        children: [
          _buildTextField(
            label: 'Dias de treino',
            controllerKey: 'info_dias_treino',
            hint: 'Ex: Terças e Quintas',
            icon: Icons.calendar_month_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Horário',
            controllerKey: 'info_horario_treino',
            hint: 'Ex: 19h às 21h',
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Local',
            controllerKey: 'info_local_treino',
            hint: 'Ex: Centro Cultural',
            icon: Icons.place_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Valor da mensalidade',
            controllerKey: 'info_valor_mensalidade',
            hint: r'Ex: R$ 80,00',
            icon: Icons.payments_rounded,
          ),
        ],
      ),
    ]);
  }

  Widget _buildRegrasTab() {
    final regras = _section('regras');

    return _tabScaffold([
      _buildCard(
        icon: Icons.rule_rounded,
        title: 'Regras de comportamento',
        subtitle: 'Defina como o assistente deve responder.',
        color: context.uai.warning,
        children: [
          _buildTextField(
            label: 'Descrição do Assistente',
            controllerKey: 'regras_descricao',
            hint: 'Defina a personalidade e propósito',
            icon: Icons.description_rounded,
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Resposta para assunto fora do tema',
            controllerKey: 'regras_resposta_fora_tema',
            hint: 'O que responder quando perguntarem algo fora do escopo',
            icon: Icons.forum_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Limitar assuntos',
              style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              'Responder apenas sobre capoeira e informações do grupo.',
              style: TextStyle(color: context.uai.textSecondary),
            ),
            value: regras['limitar_assuntos'] ?? true,
            activeColor: context.uai.warning,
            onChanged: (value) {
              setState(() => regras['limitar_assuntos'] = value);
            },
          ),
          const SizedBox(height: 12),
          _buildTagInput(
            title: 'Assuntos permitidos',
            tags: List<String>.from(regras['assuntos_permitidos'] ?? []),
            color: context.uai.warning,
            onChanged: (tags) => regras['assuntos_permitidos'] = tags,
          ),
        ],
      ),
    ]);
  }

  Widget _buildAcoesTab() {
    final acoesRaw = _config['acoes'];
    final acoes = acoesRaw is Map ? Map<String, dynamic>.from(acoesRaw) : {};

    if (acoes.isEmpty) {
      return _tabScaffold([
        _buildEmptyState(
          icon: Icons.touch_app_rounded,
          title: 'Nenhuma ação configurada',
          text: 'Quando houver ações no serviço, elas aparecerão aqui.',
        ),
      ]);
    }

    return _tabScaffold([
      ...acoes.entries.map((entry) {
        final action = entry.value is Map
            ? Map<String, dynamic>.from(entry.value as Map)
            : <String, dynamic>{};
        final active = action['ativo'] ?? true;
        final title = entry.key.toString().toUpperCase();

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _buildCard(
            icon: Icons.bolt_rounded,
            title: title,
            subtitle: 'Palavras-chave e botão desta ação.',
            color: active ? context.uai.success : context.uai.textMuted,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Ativar ação ${entry.key}'),
                value: active,
                activeColor: context.uai.success,
                onChanged: (value) {
                  setState(() {
                    _section('acoes')[entry.key] ??= <String, dynamic>{};
                    _section('acoes')[entry.key]['ativo'] = value;
                  });
                },
              ),
              if (active != false) ...[
                const SizedBox(height: 10),
                _buildTagInput(
                  title: 'Palavras-chave',
                  tags: List<String>.from(action['palavras_chave'] ?? []),
                  color: context.uai.info,
                  onChanged: (tags) {
                    _section('acoes')[entry.key] ??= <String, dynamic>{};
                    _section('acoes')[entry.key]['palavras_chave'] = tags;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'Texto do botão',
                  hint: action['texto_botao']?.toString() ?? '',
                  icon: Icons.smart_button_rounded,
                  onChanged: (value) {
                    _section('acoes')[entry.key] ??= <String, dynamic>{};
                    _section('acoes')[entry.key]['texto_botao'] = value;
                  },
                ),
              ],
            ],
          ),
        );
      }),
    ]);
  }

  Widget _buildAparenciaTab() {
    final aparencia = _section('aparencia');

    return _tabScaffold([
      _buildCard(
        icon: Icons.palette_rounded,
        title: 'Cores e Estilo',
        subtitle: 'Ajustes visuais próprios do chat no site.',
        color: context.uai.associacao,
        children: [
          _buildColorField('Cor Primária', 'aparencia_cor_primaria'),
          const SizedBox(height: 12),
          _buildColorField('Cor Secundária', 'aparencia_cor_secundaria'),
          const SizedBox(height: 16),
          _buildSliderField(
            title: 'Tamanho da Fonte',
            value: ((aparencia['tamanho_fonte'] ?? 14) as num).toDouble(),
            min: 10,
            max: 20,
            color: context.uai.associacao,
            onChanged: (value) {
              setState(() => aparencia['tamanho_fonte'] = value.round());
            },
          ),
          const SizedBox(height: 12),
          _buildSliderField(
            title: 'Arredondamento',
            value: ((aparencia['border_radius'] ?? 20) as num).toDouble(),
            min: 0,
            max: 40,
            color: context.uai.associacao,
            onChanged: (value) {
              setState(() => aparencia['border_radius'] = value.round());
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar Avatar'),
            value: aparencia['mostrar_avatar'] ?? true,
            activeColor: context.uai.associacao,
            onChanged: (value) {
              setState(() => aparencia['mostrar_avatar'] = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Animações'),
            value: aparencia['animacao'] ?? true,
            activeColor: context.uai.associacao,
            onChanged: (value) {
              setState(() => aparencia['animacao'] = value);
            },
          ),
        ],
      ),
    ]);
  }

  Widget _buildRespostasTab() {
    final respostasRapidas = _section('respostas_rapidas');
    final respostasRaw = respostasRapidas['respostas'];
    final respostas = respostasRaw is Map
        ? Map<String, dynamic>.from(respostasRaw)
        : <String, dynamic>{};

    respostasRapidas['respostas'] = respostas;

    final perguntasSugeridas =
    List<String>.from(respostasRapidas['perguntas_sugeridas'] ?? []);

    return _tabScaffold([
      _buildCard(
        icon: Icons.question_answer_rounded,
        title: 'Perguntas sugeridas',
        subtitle: 'Aparecem como botões rápidos no chat.',
        color: context.uai.info,
        children: [
          _buildTagInput(
            title: 'Perguntas rápidas',
            tags: perguntasSugeridas,
            color: context.uai.info,
            onChanged: (tags) =>
            respostasRapidas['perguntas_sugeridas'] = tags,
          ),
        ],
      ),
      const SizedBox(height: 14),
      _buildCard(
        icon: Icons.quickreply_rounded,
        title: 'Respostas personalizadas',
        subtitle: 'Defina respostas específicas para perguntas comuns.',
        color: context.uai.success,
        children: [
          if (respostas.isEmpty)
            _buildEmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Sem respostas cadastradas',
              text: 'Use o botão abaixo para criar a primeira resposta.',
              compact: true,
            ),
          ...respostas.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.cardAlt,
                borderRadius: BorderRadius.circular(context.uai.inputRadius),
                border: Border.all(color: context.uai.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key.toString(),
                          style: TextStyle(
                            color: context.uai.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover resposta',
                        onPressed: () {
                          setState(() => respostas.remove(entry.key));
                        },
                        icon: Icon(
                          Icons.delete_rounded,
                          color: context.uai.error,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: entry.value?.toString() ?? '',
                    maxLines: 3,
                    style: TextStyle(color: context.uai.textPrimary),
                    decoration: _inputDecoration(
                      label: 'Resposta',
                      hint: 'Resposta...',
                      icon: Icons.chat_rounded,
                    ),
                    onChanged: (value) => respostas[entry.key] = value,
                  ),
                ],
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _adicionarNovaResposta,
              icon: const Icon(Icons.add_rounded),
              label: const Text('ADICIONAR RESPOSTA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.uai.success,
                side: BorderSide(color: context.uai.success.withOpacity(0.28)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.uai.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildTurmasTab() {
    if (_turmas.isEmpty) {
      return _tabScaffold([
        _buildEmptyState(
          icon: Icons.school_rounded,
          title: 'Nenhuma turma encontrada',
          text: 'Adicione turmas na coleção /turmas/ do Firestore.',
        ),
      ]);
    }

    return _tabScaffold([
      _buildCard(
        icon: Icons.school_rounded,
        title: 'Turmas Disponíveis',
        subtitle:
        'Marque as turmas que o assistente deve mostrar quando perguntarem sobre horários.',
        color: context.uai.inscricoes,
        children: [
          ..._turmas.map(_buildTurmaTile),
        ],
      ),
      const SizedBox(height: 14),
      _buildInfoBox(
        icon: Icons.info_outline_rounded,
        color: context.uai.info,
        title: 'Como funciona',
        text:
        'As turmas marcadas aparecerão quando o usuário perguntar sobre horários de treino. As desmarcadas serão ignoradas pelo assistente.',
      ),
    ]);
  }

  Widget _buildTurmaTile(Map<String, dynamic> turma) {
    final t = context.uai;
    final id = turma['id']?.toString() ?? '';
    final selecionada = _turmasSelecionadas[id] ?? false;
    final corOriginal = _parseColor(turma['cor']?.toString() ?? '#EF4444');
    final cor = _ensureVisible(corOriginal, t.card);
    final dias = turma['dias'];
    final diasTexto = dias is List ? dias.join(', ') : dias?.toString() ?? '';
    final vagas = _asInt(turma['vagas']);
    final ativos = _asInt(turma['alunos_ativos']);
    final vagasDisponiveis = vagas - ativos;
    final bg = selecionada
        ? Color.alphaBlend(cor.withOpacity(0.08), t.card)
        : t.cardAlt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(t.inputRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(
              color: selecionada ? cor.withOpacity(0.32) : t.border,
            ),
          ),
          child: SwitchListTile(
            value: selecionada,
            activeColor: cor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            onChanged: (value) {
              setState(() {
                if (value) {
                  _turmasSelecionadas[id] = true;
                } else {
                  _turmasSelecionadas.remove(id);
                }
              });
            },
            secondary: Icon(
              selecionada
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: selecionada ? cor : t.textMuted,
            ),
            title: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    turma['nome']?.toString() ?? 'Sem nome',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if ((turma['nivel']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _smallChip(turma['nivel'].toString(), cor),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (diasTexto.isNotEmpty)
                    Text(
                      '📅 $diasTexto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 12),
                    ),
                  Text(
                    '⏰ ${turma['horario_inicio'] ?? '--'} às ${turma['horario_fim'] ?? '--'}',
                    style: TextStyle(color: t.textSecondary, fontSize: 12),
                  ),
                  if ((turma['local']?.toString() ?? '').isNotEmpty)
                    Text(
                      '📍 ${turma['local']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 12),
                    ),
                  if (vagas > 0)
                    Text(
                      '👥 $vagasDisponiveis vagas disponíveis de $vagas',
                      style: TextStyle(
                        color: _ensureVisible(t.success, t.card),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _buildHero({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> chips,
  }) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(context.uai.cardRadius + 2),
        boxShadow: context.uai.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final iconBox = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(icon, color: onPrimary, size: 34),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: chips,
              ),
            ],
          );

          if (narrow) {
            return Column(children: [iconBox, const SizedBox(height: 14), text]);
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final onPrimary = _onPrimary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      shadowColor: t.textPrimary.withOpacity(0.16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: accent),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    String? controllerKey,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final controller = controllerKey != null ? _controllers[controllerKey] : null;

    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: _inputDecoration(label: label, hint: hint, icon: icon),
      onChanged: onChanged,
    );
  }

  Widget _buildColorField(String label, String controllerKey) {
    final controller = _controllers[controllerKey];
    final current = _parseColor(controller?.text ?? '#B71C1C');
    final visible = _ensureVisible(current, context.uai.cardAlt);

    return InkWell(
      onTap: () async {
        final selected = await showDialog<Color>(
          context: context,
          builder: (context) => _ColorPickerDialog(
            initialColor: current,
            readOn: _readableOn,
            ensureVisible: _ensureVisible,
          ),
        );

        if (selected != null && controller != null) {
          setState(() {
            controller.text = _colorToHex(selected);
          });
        }
      },
      borderRadius: BorderRadius.circular(context.uai.inputRadius),
      child: AbsorbPointer(
        child: TextFormField(
          controller: controller,
          style: TextStyle(color: context.uai.textPrimary),
          decoration: _inputDecoration(
            label: label,
            hint: '#B71C1C',
            icon: Icons.color_lens_rounded,
          ).copyWith(
            suffixIcon: Container(
              margin: const EdgeInsets.all(8),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: visible,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.uai.border),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderField({
    required String title,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: context.uai.cardAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.uai.border),
              ),
              child: Text(
                '${value.round()}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.uai.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).round(),
          activeColor: accent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTagInput({
    required String title,
    required List<String> tags,
    required Color color,
    required ValueChanged<List<String>> onChanged,
  }) {
    final controller = TextEditingController();
    final accent = _ensureVisible(color, context.uai.card);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.uai.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...tags.map((tag) {
              return Chip(
                label: Text(tag),
                backgroundColor: Color.alphaBlend(
                  accent.withOpacity(0.10),
                  context.uai.cardAlt,
                ),
                labelStyle: TextStyle(
                  color: _ensureVisible(accent, context.uai.cardAlt),
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(color: accent.withOpacity(0.16)),
                deleteIconColor: context.uai.error,
                onDeleted: () {
                  setState(() {
                    tags.remove(tag);
                    onChanged(List<String>.from(tags));
                  });
                },
              );
            }),
            SizedBox(
              width: 170,
              child: TextField(
                controller: controller,
                style: TextStyle(color: context.uai.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Adicionar...',
                  hintStyle: TextStyle(color: context.uai.textMuted),
                  filled: true,
                  fillColor: context.uai.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                    borderSide: BorderSide(color: context.uai.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                    borderSide: BorderSide(color: accent),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (value) {
                  final clean = value.trim();
                  if (clean.isEmpty) return;

                  setState(() {
                    tags.add(clean);
                    onChanged(List<String>.from(tags));
                    controller.clear();
                  });
                },
              ),
            ),
          ],
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
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), context.uai.card),
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
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

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String text,
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 24),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
        boxShadow: compact ? null : context.uai.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 38 : 62, color: context.uai.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.textPrimary,
              fontSize: compact ? 14 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _adicionarNovaResposta() {
    String novaPergunta = '';
    String novaResposta = '';

    showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.uai;

        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: t.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                        ),
                        child: Icon(Icons.add_rounded, color: t.success),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Nova resposta rápida',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    style: TextStyle(color: t.textPrimary),
                    decoration: _inputDecoration(
                      label: 'Pergunta',
                      hint: 'Ex: Quais são os horários?',
                      icon: Icons.help_rounded,
                    ),
                    onChanged: (value) => novaPergunta = value,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    maxLines: 3,
                    style: TextStyle(color: t.textPrimary),
                    decoration: _inputDecoration(
                      label: 'Resposta',
                      hint: 'Resposta que o assistente deve retornar',
                      icon: Icons.chat_rounded,
                    ),
                    onChanged: (value) => novaResposta = value,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('CANCELAR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final pergunta = novaPergunta.trim();
                            final resposta = novaResposta.trim();
                            if (pergunta.isEmpty || resposta.isEmpty) return;

                            setState(() {
                              final respostasRapidas = _section('respostas_rapidas');
                              final respostas = respostasRapidas['respostas'] is Map
                                  ? Map<String, dynamic>.from(
                                respostasRapidas['respostas'] as Map,
                              )
                                  : <String, dynamic>{};

                              respostas[pergunta] = resposta;
                              respostasRapidas['respostas'] = respostas;
                            });

                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primary,
                            foregroundColor: _readableOn(t.primary),
                          ),
                          child: const Text('ADICIONAR'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _parseColor(String hex) {
    try {
      var clean = hex.trim();
      if (clean.isEmpty) return context.uai.primary;
      clean = clean.replaceFirst('#', '');
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return context.uai.primary;
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}

class _ColorPickerDialog extends StatelessWidget {
  final Color initialColor;
  final Color Function(Color background) readOn;
  final Color Function(Color color, Color background) ensureVisible;

  const _ColorPickerDialog({
    required this.initialColor,
    required this.readOn,
    required this.ensureVisible,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final colors = <Color>[
      t.primary,
      t.success,
      t.info,
      t.warning,
      t.error,
      t.associacao,
      t.inscricoes,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.brown,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.lime,
      Colors.deepOrange,
    ];

    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 2),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_rounded, color: t.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Selecionar cor',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: t.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              itemCount: colors.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final color = colors[index];
                final selected = color.value == initialColor.value;

                return InkWell(
                  onTap: () => Navigator.pop(context, color),
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? readOn(color) : t.border,
                        width: selected ? 3 : 1,
                      ),
                      boxShadow: t.softShadow,
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded, color: readOn(color))
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
