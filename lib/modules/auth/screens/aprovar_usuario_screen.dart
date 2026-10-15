import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/usuarios/widgets/usuario_action_overlay.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/usuarios/models/permissao_predefinida_model.dart';
import 'package:uai_capoeira/modules/usuarios/services/permissao_predefinida_service.dart';
import 'package:uai_capoeira/modules/usuarios/admin/usuario_role_catalog.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_auditoria_service.dart';

class AprovarUsuarioScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> adminData;

  const AprovarUsuarioScreen({
    super.key,
    required this.userId,
    required this.userData,
    required this.adminData,
  });

  @override
  State<AprovarUsuarioScreen> createState() => _AprovarUsuarioScreenState();
}

class _AprovarUsuarioScreenState extends State<AprovarUsuarioScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PermissaoPredefinidaService _presetService =
      PermissaoPredefinidaService();

  List<Map<String, dynamic>> _tiposUsuarios = [];
  List<PermissaoPredefinidaModel> _predefinicoes = [];
  String? _selectedTipo;
  String? _selectedPresetId;
  bool _carregando = true;
  bool _aprovando = false;
  String? _erroCarregamento;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erroCarregamento = null;
    });

    try {
      final resultados = await Future.wait<dynamic>([
        _firestore.collection('configuracoes').doc('tipos_usuario').get(),
        _presetService.streamPredefinicoes(apenasAtivas: true).first,
      ]);

      final docTipos = resultados[0] as DocumentSnapshot<Map<String, dynamic>>;
      final presets = resultados[1] as List<PermissaoPredefinidaModel>;

      var tipos = <Map<String, dynamic>>[];
      final raw = docTipos.data()?['tipos'];
      if (raw is List) {
        tipos = raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where(_ehTipoAdministrativo)
            .toList(growable: false);
      }

      if (tipos.isEmpty) tipos = _tiposFallback();

      final tipoAtual = widget.userData['tipo']?.toString().trim();
      final selecionado = tipoAtual != null &&
              tipos.any((item) => item['tipo']?.toString() == tipoAtual)
          ? tipoAtual
          : tipos.first['tipo']?.toString();

      if (!mounted) return;
      setState(() {
        _tiposUsuarios = tipos;
        _predefinicoes = presets;
        _selectedTipo = selecionado;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tiposUsuarios = _tiposFallback();
        _selectedTipo = _tiposUsuarios.first['tipo']?.toString();
        _predefinicoes = [];
        _erroCarregamento = e.toString();
        _carregando = false;
      });
    }
  }

  bool _ehTipoAdministrativo(Map<String, dynamic> tipo) {
    final nome = (tipo['tipo'] ?? '').toString().trim().toLowerCase();
    if (nome.isEmpty) return false;
    // Área do Aluno é um acesso independente. A aprovação desta tela é
    // exclusivamente para a gestão administrativa.
    if (nome == 'aluno' ||
        nome == 'area_aluno' ||
        nome == 'área_aluno' ||
        nome == 'usuario' ||
        nome == 'usuário') {
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> _tiposFallback() => UsuarioRoleCatalog
      .administrativos
      .map((role) => {
            'tipo': role.id,
            'peso': role.peso,
            'descricao': role.descricao,
            'icone': switch (role.id) {
              'administrador' => 'admin_panel_settings',
              'professor' => 'school',
              'monitor' => 'supervised_user_circle',
              _ => 'badge',
            },
          })
      .toList(growable: false);


  Map<String, dynamic> get _tipoSelecionado {
    if (_tiposUsuarios.isEmpty) return const <String, dynamic>{};
    return _tiposUsuarios.firstWhere(
      (item) => item['tipo']?.toString() == _selectedTipo,
      orElse: () => _tiposUsuarios.first,
    );
  }

  PermissaoPredefinidaModel? get _presetSelecionado {
    final id = _selectedPresetId;
    if (id == null || id.isEmpty) return null;
    for (final preset in _predefinicoes) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  int _peso(Map<String, dynamic> tipo) {
    final value = tipo['peso'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _descricao(Map<String, dynamic> tipo) =>
      tipo['descricao']?.toString().trim().isNotEmpty == true
          ? tipo['descricao'].toString().trim()
          : 'Perfil administrativo do sistema.';

  Color _corTipo(Map<String, dynamic> tipo) {
    final hex = tipo['cor']?.toString().replaceAll('#', '').trim() ?? '';
    if (hex.length == 6 || hex.length == 8) {
      try {
        return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
      } catch (_) {}
    }
    switch (tipo['tipo']?.toString().toLowerCase()) {
      case 'administrador':
        return Colors.red;
      case 'professor':
        return Colors.orange;
      case 'monitor':
        return Colors.blue;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _iconeTipo(Map<String, dynamic> tipo) {
    switch (tipo['icone']?.toString()) {
      case 'admin_panel_settings':
        return Icons.admin_panel_settings_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'supervised_user_circle':
        return Icons.supervised_user_circle_rounded;
      case 'badge':
        return Icons.badge_rounded;
      default:
        return Icons.manage_accounts_rounded;
    }
  }

  bool get _possuiAreaAluno =>
      widget.userData['acesso_area_aluno'] == true ||
      widget.userData['vinculado_area_aluno'] == true ||
      widget.userData['area_aluno'] == true ||
      (widget.userData['tipo_identidade']?.toString() == 'hibrido');

  Future<void> _aprovarUsuario() async {
    if (_aprovando || _selectedTipo == null) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _snack('Usuário administrador não autenticado.', erro: true);
      return;
    }

    final tipo = _tipoSelecionado;
    final preset = _presetSelecionado;
    final nome = _nomeUsuario;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar acesso à gestão'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$nome será aprovado como ${_labelTipo(_selectedTipo!)}.'),
            const SizedBox(height: 10),
            Text(
              preset == null
                  ? 'Nenhuma predefinição será aplicada agora. As permissões específicas poderão ser configuradas depois.'
                  : 'Predefinição: ${preset.nome} (${preset.totalAtivas} permissões ativas).',
            ),
            if (_possuiAreaAluno) ...[
              const SizedBox(height: 10),
              const Text(
                'O vínculo existente com a Área do Aluno será preservado. A conta ficará híbrida: Gestão + Área do Aluno.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_user_rounded),
            label: const Text('Aprovar acesso'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    if (!mounted) return;
    setState(() => _aprovando = true);
    UsuarioActionOverlay.show(
      context,
      title: 'Aprovando $nome...',
      subtitle: preset == null
          ? 'Liberando o acesso à gestão.'
          : 'Liberando o acesso e aplicando a predefinição ${preset.nome}.',
      icon: Icons.verified_user_rounded,
    );
    try {
      final adminNome = widget.adminData['nome_completo']?.toString().trim();
      final userRef = _firestore.collection('usuarios').doc(widget.userId);
      final permissoesRef = userRef
          .collection('permissoes_usuario')
          .doc('configuracoes');
      final batch = _firestore.batch();

      batch.set(
        userRef,
        {
          'tipo': _selectedTipo,
          'peso_permissao': _peso(tipo),
          'status_conta': 'ativa',
          'acesso_gestao': true,
          'exibir_na_gestao': true,
          'solicitacao_acesso_gestao': false,
          'aprovado_por': currentUser.uid,
          'aprovado_por_nome':
              (adminNome == null || adminNome.isEmpty) ? 'Administrador' : adminNome,
          'aprovado_em': FieldValue.serverTimestamp(),
          'ultima_atualizacao': FieldValue.serverTimestamp(),
          'predefinicao_permissoes_id': preset?.id,
          'predefinicao_permissoes_nome': preset?.nome,
          'predefinicao_aplicada_em':
              preset == null ? null : FieldValue.serverTimestamp(),
          'predefinicao_aplicada_por': preset == null ? null : currentUser.uid,
        },
        SetOptions(merge: true),
      );

      if (preset != null) {
        batch.set(
          permissoesRef,
          Map<String, bool>.from(preset.permissoes),
          SetOptions(merge: true),
        );
      }

      batch.set(
        UsuarioAuditoriaService.novoEventoRef(widget.userId),
        UsuarioAuditoriaService.evento(
          tipo: 'aprovacao',
          titulo: 'Acesso à gestão aprovado',
          descricao: preset == null
              ? '$nome aprovado como ${_labelTipo(_selectedTipo!)}.'
              : '$nome aprovado como ${_labelTipo(_selectedTipo!)} com a predefinição ${preset.nome}.',
          atorUid: currentUser.uid,
          atorNome: (adminNome == null || adminNome.isEmpty) ? 'Administrador' : adminNome,
          antes: {
            'status_conta': widget.userData['status_conta'],
            'tipo': widget.userData['tipo'],
          },
          depois: {
            'status_conta': 'ativa',
            'tipo': _selectedTipo,
            'predefinicao': preset?.nome,
          },
        ),
      );

      await batch.commit();

      if (!mounted) return;
      _snack(
        preset == null
            ? '$nome aprovado como ${_labelTipo(_selectedTipo!)}.'
            : '$nome aprovado e permissões de "${preset.nome}" aplicadas.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('Não foi possível aprovar o acesso: $e', erro: true);
    } finally {
      UsuarioActionOverlay.hide();
      if (mounted) setState(() => _aprovando = false);
    }
  }

  String get _nomeUsuario {
    for (final key in ['nome_completo', 'nome', 'name', 'displayName']) {
      final value = widget.userData[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return 'Usuário';
  }

  String get _emailUsuario {
    final value = widget.userData['email']?.toString().trim() ?? '';
    return value.isEmpty ? 'E-mail não informado' : value;
  }

  String _labelTipo(String tipo) => UsuarioRoleCatalog.label(tipo);

  void _snack(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? context.uai.error : context.uai.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aprovar acesso')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Preparando aprovação...'),
            ],
          ),
        ),
      );
    }

    final preset = _presetSelecionado;
    final foto = (widget.userData['foto_url'] ??
            widget.userData['photoURL'] ??
            widget.userData['photoUrl'])
        ?.toString()
        .trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprovar acesso'),
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth >= 1000 ? 940.0 : double.infinity;
              final horizontal = constraints.maxWidth >= 700 ? 28.0 : 14.0;
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: maxWidth,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 32),
                    children: [
                      _UsuarioResumoCard(
                        nome: _nomeUsuario,
                        email: _emailUsuario,
                        fotoUrl: foto,
                        hibrido: _possuiAreaAluno,
                      ),
                      if (_erroCarregamento != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Algumas configurações online não carregaram. Perfis padrão foram usados com segurança.',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Tentar novamente',
                                onPressed: _carregarDados,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const _TituloEtapa(
                        numero: 1,
                        titulo: 'Função administrativa',
                        subtitulo: 'Escolha o papel que a pessoa terá na gestão.',
                      ),
                      const SizedBox(height: 12),
                      ..._tiposUsuarios.map((item) {
                        final selecionado = item['tipo']?.toString() == _selectedTipo;
                        final cor = _corTipo(item);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _aprovando
                                ? null
                                : () => setState(
                                      () => _selectedTipo = item['tipo']?.toString(),
                                    ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: selecionado
                                    ? cor.withValues(alpha: 0.10)
                                    : colors.surfaceContainerLow,
                                border: Border.all(
                                  color: selecionado ? cor : colors.outlineVariant,
                                  width: selecionado ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: cor.withValues(alpha: 0.14),
                                    foregroundColor: cor,
                                    child: Icon(_iconeTipo(item)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _labelTipo(item['tipo']?.toString() ?? ''),
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _descricao(item),
                                          style: TextStyle(color: colors.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selecionado)
                                    Icon(Icons.check_circle_rounded, color: cor),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                      const _TituloEtapa(
                        numero: 2,
                        titulo: 'Predefinição de permissões',
                        subtitulo:
                            'Opcional. Aplique um modelo pronto junto com a aprovação.',
                      ),
                      const SizedBox(height: 12),
                      _PresetCard(
                        selecionado: _selectedPresetId == null,
                        titulo: 'Configurar depois',
                        descricao:
                            'Aprova a função agora sem alterar as permissões específicas.',
                        total: null,
                        onTap: _aprovando
                            ? null
                            : () => setState(() => _selectedPresetId = null),
                      ),
                      ..._predefinicoes.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _PresetCard(
                            selecionado: _selectedPresetId == item.id,
                            titulo: item.nome,
                            descricao: item.descricao.isEmpty
                                ? 'Predefinição administrativa'
                                : item.descricao,
                            total: item.totalAtivas,
                            onTap: _aprovando
                                ? null
                                : () => setState(() => _selectedPresetId = item.id),
                          ),
                        ),
                      ),
                      if (_predefinicoes.isEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Nenhuma predefinição ativa cadastrada. Você ainda pode aprovar e configurar as permissões depois.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const _TituloEtapa(
                        numero: 3,
                        titulo: 'Revisão',
                        subtitulo: 'Confira o que será concedido antes de finalizar.',
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _LinhaResumo(
                                icone: Icons.badge_rounded,
                                titulo: 'Função',
                                valor: _selectedTipo == null
                                    ? 'Não definida'
                                    : _labelTipo(_selectedTipo!),
                              ),
                              const Divider(height: 24),
                              _LinhaResumo(
                                icone: Icons.fact_check_rounded,
                                titulo: 'Permissões',
                                valor: preset == null
                                    ? 'Configurar depois'
                                    : '${preset.nome} • ${preset.totalAtivas} ativas',
                              ),
                              if (_possuiAreaAluno) ...[
                                const Divider(height: 24),
                                const _LinhaResumo(
                                  icone: Icons.school_rounded,
                                  titulo: 'Área do Aluno',
                                  valor: 'Preservada • conta híbrida',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _aprovando ? null : _aprovarUsuario,
                        icon: const Icon(Icons.verified_user_rounded),
                        label: Text(
                          _aprovando ? 'Aprovando acesso...' : 'Aprovar acesso à gestão',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A rejeição continua disponível na tela de Solicitações. Esta tela apenas concede acesso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_aprovando)
            Positioned.fill(
              child: ColoredBox(
                color: colors.scrim.withValues(alpha: 0.34),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(
                            'Aprovando $_nomeUsuario...',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          const Text('Aplicando função e permissões com segurança.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UsuarioResumoCard extends StatelessWidget {
  final String nome;
  final String email;
  final String? fotoUrl;
  final bool hibrido;

  const _UsuarioResumoCard({
    required this.nome,
    required this.email,
    required this.fotoUrl,
    required this.hibrido,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final temFoto = fotoUrl != null && fotoUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: colors.primary.withValues(alpha: 0.12),
            backgroundImage: temFoto ? NetworkImage(fotoUrl!) : null,
            child: temFoto
                ? null
                : Text(
                    nome.isEmpty ? '?' : nome[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(email, style: TextStyle(color: colors.onSurfaceVariant)),
                if (hibrido) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'ÁREA DO ALUNO JÁ VINCULADA',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TituloEtapa extends StatelessWidget {
  final int numero;
  final String titulo;
  final String subtitulo;

  const _TituloEtapa({
    required this.numero,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          child: Text('$numero', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(subtitulo, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final bool selecionado;
  final String titulo;
  final String descricao;
  final int? total;
  final VoidCallback? onTap;

  const _PresetCard({
    required this.selecionado,
    required this.titulo,
    required this.descricao,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selecionado
              ? colors.primaryContainer.withValues(alpha: 0.52)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selecionado ? colors.primary : colors.outlineVariant,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              total == null ? Icons.tune_rounded : Icons.fact_check_rounded,
              color: selecionado ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(descricao, style: TextStyle(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            if (total != null) ...[
              const SizedBox(width: 8),
              Text('$total', style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
            if (selecionado) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: colors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String valor;

  const _LinhaResumo({
    required this.icone,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icone, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(valor, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }
}
