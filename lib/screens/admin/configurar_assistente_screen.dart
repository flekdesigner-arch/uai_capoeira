import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/assistente_chat_service.dart';

class ConfigurarAssistenteScreen extends StatefulWidget {
  const ConfigurarAssistenteScreen({super.key});

  @override
  State<ConfigurarAssistenteScreen> createState() => _ConfigurarAssistenteScreenState();
}

class _ConfigurarAssistenteScreenState extends State<ConfigurarAssistenteScreen> {
  final AssistenteChatService _service = AssistenteChatService();
  bool _carregando = true;
  bool _salvando = false;
  int _tabIndex = 0;

  Map<String, dynamic> _config = {};
  Map<String, TextEditingController> _controllers = {};

  // Lista de turmas carregadas do Firestore
  List<Map<String, dynamic>> _turmas = [];
  Map<String, bool> _turmasSelecionadas = {};

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarConfiguracoes() async {
    setState(() => _carregando = true);

    _config = await _service.carregarConfiguracoesCompletas();
    _turmas = await _service.buscarTodasTurmas();
    _turmasSelecionadas = Map.from(_config['turmas_selecionadas'] ?? {});

    _inicializarControllers();
    setState(() => _carregando = false);
  }

  void _inicializarControllers() {
    // Perfil
    _controllers['perfil_nome'] = TextEditingController(text: _config['perfil']['nome']);
    _controllers['perfil_avatar'] = TextEditingController(text: _config['perfil']['avatar']);
    _controllers['perfil_mensagem_boas_vindas'] = TextEditingController(text: _config['perfil']['mensagem_boas_vindas']);
    _controllers['perfil_cor_assistente'] = TextEditingController(text: _config['perfil']['cor_assistente']);

    // Informações
    _controllers['info_nome_grupo'] = TextEditingController(text: _config['informacoes']['nome_grupo']);
    _controllers['info_cidade'] = TextEditingController(text: _config['informacoes']['cidade']);
    _controllers['info_endereco'] = TextEditingController(text: _config['informacoes']['endereco']);
    _controllers['info_telefone'] = TextEditingController(text: _config['informacoes']['telefone']);
    _controllers['info_email'] = TextEditingController(text: _config['informacoes']['email']);
    _controllers['info_dias_treino'] = TextEditingController(text: _config['informacoes']['dias_treino']);
    _controllers['info_horario_treino'] = TextEditingController(text: _config['informacoes']['horario_treino']);
    _controllers['info_local_treino'] = TextEditingController(text: _config['informacoes']['local_treino']);
    _controllers['info_valor_mensalidade'] = TextEditingController(text: _config['informacoes']['valor_mensalidade']);

    // Regras
    _controllers['regras_descricao'] = TextEditingController(text: _config['regras']['descricao_geral']);
    _controllers['regras_resposta_fora_tema'] = TextEditingController(text: _config['regras']['resposta_fora_tema']);

    // Aparência
    _controllers['aparencia_cor_primaria'] = TextEditingController(text: _config['aparencia']['cor_primaria']);
    _controllers['aparencia_cor_secundaria'] = TextEditingController(text: _config['aparencia']['cor_secundaria']);
  }

  Future<void> _salvarConfiguracoes() async {
    setState(() => _salvando = true);

    // Atualiza perfil
    _config['perfil']['nome'] = _controllers['perfil_nome']?.text ?? '';
    _config['perfil']['avatar'] = _controllers['perfil_avatar']?.text ?? '';
    _config['perfil']['mensagem_boas_vindas'] = _controllers['perfil_mensagem_boas_vindas']?.text ?? '';
    _config['perfil']['cor_assistente'] = _controllers['perfil_cor_assistente']?.text ?? '';

    // Atualiza informações
    _config['informacoes']['nome_grupo'] = _controllers['info_nome_grupo']?.text ?? '';
    _config['informacoes']['cidade'] = _controllers['info_cidade']?.text ?? '';
    _config['informacoes']['endereco'] = _controllers['info_endereco']?.text ?? '';
    _config['informacoes']['telefone'] = _controllers['info_telefone']?.text ?? '';
    _config['informacoes']['email'] = _controllers['info_email']?.text ?? '';
    _config['informacoes']['dias_treino'] = _controllers['info_dias_treino']?.text ?? '';
    _config['informacoes']['horario_treino'] = _controllers['info_horario_treino']?.text ?? '';
    _config['informacoes']['local_treino'] = _controllers['info_local_treino']?.text ?? '';
    _config['informacoes']['valor_mensalidade'] = _controllers['info_valor_mensalidade']?.text ?? '';

    // Atualiza regras
    _config['regras']['descricao_geral'] = _controllers['regras_descricao']?.text ?? '';
    _config['regras']['resposta_fora_tema'] = _controllers['regras_resposta_fora_tema']?.text ?? '';

    // Atualiza aparência
    _config['aparencia']['cor_primaria'] = _controllers['aparencia_cor_primaria']?.text ?? '';
    _config['aparencia']['cor_secundaria'] = _controllers['aparencia_cor_secundaria']?.text ?? '';

    // Atualiza turmas selecionadas
    _config['turmas_selecionadas'] = _turmasSelecionadas;

    await _service.salvarConfiguracoesCompletas(_config);

    setState(() => _salvando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Configurações salvas com sucesso!'), backgroundColor: Colors.green),
      );
    }
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
        title: const Text('Configurar Assistente Chat'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          Row(
            children: [
              const Text('ATIVAR', style: TextStyle(fontSize: 12)),
              Switch(
                value: _config['ativo'] ?? false,
                onChanged: (value) {
                  setState(() {
                    _config['ativo'] = value;
                  });
                  _salvarConfiguracoes();
                },
                activeColor: Colors.green,
              ),
              const SizedBox(width: 16),
            ],
          ),
          if (!_salvando)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _salvarConfiguracoes,
              tooltip: 'Salvar',
            ),
          if (_salvando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: DefaultTabController(
        length: 7, // 🔥 AGORA SÃO 7 ABAS (ADICIONEI TURMAS)
        child: Column(
          children: [
            Container(
              color: Colors.grey.shade100,
              child: const TabBar(
                isScrollable: true,
                indicatorColor: Colors.red,
                labelColor: Colors.red,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(text: 'PERFIL', icon: Icon(Icons.person)),
                  Tab(text: 'INFORMAÇÕES', icon: Icon(Icons.info)),
                  Tab(text: 'REGRAS', icon: Icon(Icons.gavel)),
                  Tab(text: 'AÇÕES', icon: Icon(Icons.touch_app)),
                  Tab(text: 'APARÊNCIA', icon: Icon(Icons.palette)),
                  Tab(text: 'RESPOSTAS', icon: Icon(Icons.quickreply)),
                  Tab(text: 'TURMAS', icon: Icon(Icons.school)), // 🔥 NOVA ABA
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildPerfilTab(),
                  _buildInformacoesTab(),
                  _buildRegrasTab(),
                  _buildAcoesTab(),
                  _buildAparenciaTab(),
                  _buildRespostasTab(),
                  _buildTurmasTab(), // 🔥 NOVA ABA
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ABAS EXISTENTES (PERFIL, INFORMAÇÕES, REGRAS, AÇÕES, APARÊNCIA, RESPOSTAS) ====================
  // Mantenha as mesmas implementações que você já tinha para essas abas
  // Vou colocar versões resumidas aqui, mas você pode manter as suas

  Widget _buildPerfilTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '🤖 Identidade do Assistente',
            children: [
              _buildTextField('Nome do Assistente', 'perfil_nome', 'Ex: Assistente UAI'),
              const SizedBox(height: 12),
              _buildTextField('Avatar (emoji)', 'perfil_avatar', 'Ex: 🤖, 💬, 🎭'),
              const SizedBox(height: 12),
              _buildTextField('Mensagem de Boas Vindas', 'perfil_mensagem_boas_vindas', 'Mensagem inicial do chat'),
              const SizedBox(height: 12),
              _buildColorField('Cor do Assistente', 'perfil_cor_assistente'),
            ],
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: '⚙️ Status',
            children: [
              SwitchListTile(
                title: const Text('Assistente Ativo'),
                subtitle: const Text('Ativar/desativar o chat no site'),
                value: _config['ativo'] ?? false,
                onChanged: (value) {
                  setState(() => _config['ativo'] = value);
                  _salvarConfiguracoes();
                },
                activeColor: Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInformacoesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '🏢 Informações do Grupo',
            children: [
              _buildTextField('Nome do Grupo', 'info_nome_grupo', 'Ex: UAI Capoeira'),
              const SizedBox(height: 12),
              _buildTextField('Cidade', 'info_cidade', 'Ex: Bocaiuva - MG'),
              const SizedBox(height: 12),
              _buildTextField('Endereço Completo', 'info_endereco', 'Rua, número, bairro'),
              const SizedBox(height: 12),
              _buildTextField('Telefone (com DDD)', 'info_telefone', 'Ex: (38) 99999-9999'),
              const SizedBox(height: 12),
              _buildTextField('Email', 'info_email', 'contato@uaicapoeira.com.br'),
            ],
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: '🥋 Treinos',
            children: [
              _buildTextField('Dias de Treino', 'info_dias_treino', 'Ex: Terças e Quintas'),
              const SizedBox(height: 12),
              _buildTextField('Horário', 'info_horario_treino', 'Ex: 19h às 21h'),
              const SizedBox(height: 12),
              _buildTextField('Local', 'info_local_treino', 'Ex: Centro Cultural'),
              const SizedBox(height: 12),
              _buildTextField('Valor da Mensalidade', 'info_valor_mensalidade', r'Ex: R$ 80,00'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegrasTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '📋 Regras de Comportamento',
            children: [
              _buildTextField('Descrição do Assistente', 'regras_descricao', 'Defina a personalidade e propósito', maxLines: 4),
              const SizedBox(height: 12),
              _buildTextField('Resposta para assunto fora do tema', 'regras_resposta_fora_tema', 'O que responder quando perguntarem algo fora do escopo', maxLines: 3),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Limitar Assuntos'),
                subtitle: const Text('Responder apenas sobre capoeira'),
                value: _config['regras']['limitar_assuntos'] ?? true,
                onChanged: (value) {
                  setState(() => _config['regras']['limitar_assuntos'] = value);
                },
              ),
              const SizedBox(height: 12),
              _buildTagInput(
                title: 'Assuntos Permitidos',
                tags: List<String>.from(_config['regras']['assuntos_permitidos'] ?? []),
                onChanged: (tags) => _config['regras']['assuntos_permitidos'] = tags,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcoesTab() {
    final acoes = _config['acoes'] ?? {};

    if (acoes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nenhuma ação configurada'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: acoes.entries.map<Widget>((entry) {
          return _buildCard(
            title: '⚡ ${entry.key.toUpperCase()}',
            children: [
              SwitchListTile(
                title: Text('Ativar ação ${entry.key}'),
                value: entry.value['ativo'] ?? true,
                onChanged: (value) {
                  setState(() {
                    _config['acoes'][entry.key]['ativo'] = value;
                  });
                },
              ),
              if (entry.value['ativo'] != false) ...[
                _buildTagInput(
                  title: 'Palavras-chave',
                  tags: List<String>.from(entry.value['palavras_chave'] ?? []),
                  onChanged: (tags) => _config['acoes'][entry.key]['palavras_chave'] = tags,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  'Texto do Botão',
                  null,
                  entry.value['texto_botao'] ?? '',
                  onChanged: (value) => _config['acoes'][entry.key]['texto_botao'] = value,
                ),
              ],
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAparenciaTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '🎨 Cores e Estilo',
            children: [
              _buildColorField('Cor Primária', 'aparencia_cor_primaria'),
              const SizedBox(height: 12),
              _buildColorField('Cor Secundária', 'aparencia_cor_secundaria'),
              const SizedBox(height: 12),
              _buildSliderField(
                title: 'Tamanho da Fonte',
                value: (_config['aparencia']['tamanho_fonte'] ?? 14).toDouble(),
                min: 10,
                max: 20,
                onChanged: (value) => _config['aparencia']['tamanho_fonte'] = value.toInt(),
              ),
              const SizedBox(height: 12),
              _buildSliderField(
                title: 'Arredondamento',
                value: (_config['aparencia']['border_radius'] ?? 20).toDouble(),
                min: 0,
                max: 40,
                onChanged: (value) => _config['aparencia']['border_radius'] = value.toInt(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Mostrar Avatar'),
                value: _config['aparencia']['mostrar_avatar'] ?? true,
                onChanged: (value) => _config['aparencia']['mostrar_avatar'] = value,
              ),
              SwitchListTile(
                title: const Text('Animações'),
                value: _config['aparencia']['animacao'] ?? true,
                onChanged: (value) => _config['aparencia']['animacao'] = value,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRespostasTab() {
    final respostas = _config['respostas_rapidas']?['respostas'] ?? {};
    final perguntasSugeridas = _config['respostas_rapidas']?['perguntas_sugeridas'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '💬 Perguntas Sugeridas',
            subtitle: 'Aparecem como botões rápidos no chat',
            children: [
              _buildTagInput(
                title: 'Perguntas Rápidas',
                tags: List<String>.from(perguntasSugeridas),
                onChanged: (tags) => _config['respostas_rapidas']['perguntas_sugeridas'] = tags,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: '📝 Respostas Personalizadas',
            subtitle: 'Defina respostas específicas para perguntas comuns',
            children: [
              ...respostas.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: entry.value,
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        hintText: 'Resposta...',
                      ),
                      onChanged: (value) => _config['respostas_rapidas']['respostas'][entry.key] = value,
                    ),
                  ],
                ),
              )),
              ElevatedButton.icon(
                onPressed: _adicionarNovaResposta,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar Resposta'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 🔥 NOVA ABA: TURMAS ====================

  Widget _buildTurmasTab() {
    if (_turmas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Nenhuma turma encontrada no Firestore',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Adicione turmas na coleção /turmas/ do Firestore',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCard(
            title: '🏫 Turmas Disponíveis',
            subtitle: 'Marque as turmas que o assistente deve mostrar quando perguntarem sobre horários',
            children: [
              const SizedBox(height: 8),
              ..._turmas.map((turma) => _buildTurmaTile(turma)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade900),
                const SizedBox(width: 12),
                Expanded(  // 🔥 ADICIONADO Expanded
                  child: Text(
                    'As turmas marcadas aparecerão quando o usuário perguntar sobre horários de treino. As desmarcadas serão ignoradas pelo assistente.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurmaTile(Map<String, dynamic> turma) {
    final id = turma['id'];
    final selecionada = _turmasSelecionadas[id] ?? false;
    final cor = _parseColor(turma['cor'] ?? '#EF4444');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        value: selecionada,
        onChanged: (value) {
          setState(() {
            if (value) {
              _turmasSelecionadas[id] = true;
            } else {
              _turmasSelecionadas.remove(id);
            }
          });
        },
        activeColor: cor,
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(  // 🔥 ADICIONADO Expanded para evitar overflow
              child: Text(
                turma['nome'] ?? 'Sem nome',
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,  // 🔥 ADICIONADO
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                turma['nivel'] ?? '',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '📅 ${(turma['dias'] as List).join(', ')}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,  // 🔥 ADICIONADO
            ),
            Text(
              '⏰ ${turma['horario_inicio']} às ${turma['horario_fim']}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '📍 ${turma['local']}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,  // 🔥 ADICIONADO
            ),
            Text(
              '👥 ${turma['vagas'] - turma['alunos_ativos']} vagas disponíveis de ${turma['vagas']}',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700),
            ),
          ],
        ),
        secondary: selecionada
            ? Icon(Icons.visibility, color: Colors.green)
            : Icon(Icons.visibility_off, color: Colors.grey),
      ),
    );
  }

  // ==================== WIDGETS AUXILIARES ====================

  Widget _buildCard({required String title, String? subtitle, required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String? controllerKey, String hint, {int maxLines = 1, Function(String)? onChanged}) {
    final controller = controllerKey != null ? _controllers[controllerKey] : null;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildColorField(String label, String controllerKey) {
    return GestureDetector(
      onTap: () async {
        await showDialog<Color>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Selecione $label'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ColorPicker(
                pickerColor: _parseColor(_controllers[controllerKey]!.text),
                onColorChanged: (color) {
                  _controllers[controllerKey]!.text = '#${color.value.toRadixString(16).substring(2, 8).toUpperCase()}';
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        );
      },
      child: AbsorbPointer(
        child: TextFormField(
          controller: _controllers[controllerKey],
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: Container(
              margin: const EdgeInsets.all(8),
              width: 32,
              decoration: BoxDecoration(
                color: _parseColor(_controllers[controllerKey]!.text),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.red;
    }
  }

  Widget _buildSliderField({required String title, required double value, required double min, required double max, required Function(double) onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: (max - min).toInt(),
                onChanged: onChanged,
              ),
            ),
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${value.toInt()}', textAlign: TextAlign.center),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagInput({required String title, required List<String> tags, required Function(List<String>) onChanged}) {
    final controller = TextEditingController();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...tags.map((tag) => Chip(
              label: Text(tag),
              onDeleted: () {
                tags.remove(tag);
                onChanged(tags);
                setState(() {});
              },
            )),
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Adicionar...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    tags.add(value);
                    onChanged(tags);
                    controller.clear();
                    setState(() {});
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _adicionarNovaResposta() {
    String novaPergunta = '';
    String novaResposta = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova Resposta Rápida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Pergunta',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (value) => novaPergunta = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: 'Resposta',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
              onChanged: (value) => novaResposta = value,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () {
              if (novaPergunta.isNotEmpty && novaResposta.isNotEmpty) {
                setState(() {
                  _config['respostas_rapidas']['respostas'][novaPergunta] = novaResposta;
                });
                Navigator.pop(context);
              }
            },
            child: const Text('ADICIONAR'),
          ),
        ],
      ),
    );
  }
}

// Widget para seleção de cor
class ColorPicker extends StatelessWidget {
  final Color pickerColor;
  final Function(Color) onColorChanged;

  const ColorPicker({super.key, required this.pickerColor, required this.onColorChanged});

  @override
  Widget build(BuildContext context) {
    final cores = [
      Colors.red, Colors.blue, Colors.green, Colors.orange,
      Colors.purple, Colors.teal, Colors.brown, Colors.pink,
      Colors.amber, Colors.cyan, Colors.indigo, Colors.lime,
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cores.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => onColorChanged(cores[index]),
          child: Container(
            decoration: BoxDecoration(
              color: cores[index],
              shape: BoxShape.circle,
              border: pickerColor == cores[index] ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}