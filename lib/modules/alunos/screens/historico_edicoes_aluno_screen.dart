import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';

class HistoricoEdicoesAlunoScreen extends StatefulWidget {
  const HistoricoEdicoesAlunoScreen({
    super.key,
    required this.alunoId,
    required this.alunoNome,
  });

  final String alunoId;
  final String alunoNome;

  @override
  State<HistoricoEdicoesAlunoScreen> createState() =>
      _HistoricoEdicoesAlunoScreenState();
}

class _HistoricoEdicoesAlunoScreenState
    extends State<HistoricoEdicoesAlunoScreen> {
  final AlunoHistoricoEdicaoService _historicoService =
      AlunoHistoricoEdicaoService();
  final PermissaoService _permissaoService = PermissaoService();

  bool _revertendo = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _historicoStream() {
    return FirebaseFirestore.instance
        .collection('alunos')
        .doc(widget.alunoId)
        .collection('historico_edicoes')
        .orderBy('criado_em', descending: true)
        .snapshots();
  }

  Future<bool> _temInternet() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((item) => item != ConnectivityResult.none);
  }

  Future<bool> _podeReverter() async {
    final isAdmin = await _permissaoService.usuarioAtualEhAdmin();
    if (isAdmin) return true;
    return _permissaoService.temPermissao('pode_editar_aluno');
  }

  Future<void> _confirmarReversao(
    String historicoId,
    Map<String, dynamic> data,
  ) async {
    if (_revertendo) return;

    final temInternet = await _temInternet();
    if (!mounted) return;

    if (!temInternet) {
      _mostrarSnack(
        'Você precisa estar conectado à internet para reverter uma edição.',
        context.uai.warning,
      );
      return;
    }

    final podeReverter = await _podeReverter();
    if (!mounted) return;

    if (!podeReverter) {
      _mostrarSnack(
        'Você não tem permissão para reverter histórico de edição.',
        context.uai.error,
      );
      return;
    }

    final campos = _camposAlterados(data);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: t.warning),
              const SizedBox(width: 8),
              const Expanded(child: Text('Reverter edição?')),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Essa ação irá restaurar os campos alterados nessa edição para os valores anteriores registrados no histórico. Um novo registro de reversão será criado.',
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Campos que serão revertidos',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...campos.map((campo) {
                    final label = campo['label']?.toString() ?? 'Campo';
                    final antes = campo['antes'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.restore_rounded,
                            size: 17,
                            color: t.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$label: ${AlunoHistoricoEdicaoService.formatarValor(antes, somenteData: _campoEhData(campo['campo']))}',
                              style: TextStyle(color: t.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Reverter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.warning,
                foregroundColor: _readableOn(t.warning),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    setState(() => _revertendo = true);
    try {
      await _historicoService.reverterEdicao(
        alunoId: widget.alunoId,
        historicoId: historicoId,
      );
      if (!mounted) return;
      _mostrarSnack('Edição revertida com sucesso.', context.uai.success);
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack('Erro ao reverter edição: $e', context.uai.error);
    } finally {
      if (mounted) setState(() => _revertendo = false);
    }
  }

  void _mostrarSnack(String mensagem, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Histórico de Edições'),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(t.primary),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _historicoStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }

          if (snapshot.hasError) {
            return _buildEstado(
              icon: Icons.error_outline_rounded,
              titulo: 'Não foi possível carregar o histórico.',
              subtitulo: snapshot.error.toString(),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _buildEstado(
              icon: Icons.manage_history_rounded,
              titulo: 'Nenhuma edição registrada para este aluno.',
              subtitulo: 'As próximas alterações da ficha aparecerão aqui.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader();
              final doc = docs[index - 1];
              return _buildHistoricoCard(doc.id, doc.data());
            },
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.history_edu_rounded, color: t.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.alunoNome,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Registro de alterações oficiais da ficha do aluno.',
                  style: TextStyle(color: t.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricoCard(String historicoId, Map<String, dynamic> data) {
    final t = context.uai;
    final tipo = data['tipo_edicao']?.toString();
    final subtipo = data['subtipo_edicao']?.toString();
    final revertido = data['revertido'] == true;
    final podeReverter =
        data['pode_reverter'] == true && !revertido && tipo != 'reversao';
    final campos = _camposAlterados(data);
    final criadoEm = data['criado_em'];
    final autor =
        data['aplicado_por_nome']?.toString() ??
        data['criado_por_nome']?.toString() ??
        'Usuário';

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        iconColor: t.primary,
        collapsedIconColor: t.textSecondary,
        title: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _chipTipo(tipo, subtipo: subtipo),
            if (revertido) _chip('Revertida', t.warning),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['resumo']?.toString() ?? 'Edição sem resumo',
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${AlunoHistoricoEdicaoService.formatarValor(criadoEm)} • por $autor',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
              if ((data['motivo_titulo']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Motivo: ${data['motivo_titulo']}',
                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if ((data['observacao']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Observação: ${data['observacao']}',
                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if ((data['origem']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Origem: ${_origemLegivel(data['origem']?.toString())}',
                  style: TextStyle(color: t.textMuted, fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        children: [
          if (campos.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Nenhum campo detalhado registrado.',
                style: TextStyle(color: t.textSecondary),
              ),
            )
          else
            ...campos.map(_buildCampoAlterado),
          if (revertido) _buildRevertidoInfo(data),
          if (podeReverter) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _revertendo
                    ? null
                    : () => _confirmarReversao(historicoId, data),
                icon: const Icon(Icons.restore_rounded),
                label: Text(_revertendo ? 'Revertendo...' : 'Reverter edição'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.warning,
                  side: BorderSide(color: t.warning),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCampoAlterado(Map<String, dynamic> campo) {
    final t = context.uai;
    final nomeCampo = campo['campo'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            campo['label']?.toString() ?? 'Campo',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _linhaValor('Antes', campo['antes'], _campoEhData(nomeCampo)),
          const SizedBox(height: 5),
          _linhaValor('Depois', campo['depois'], _campoEhData(nomeCampo)),
        ],
      ),
    );
  }

  Widget _linhaValor(String label, dynamic value, bool somenteData) {
    final t = context.uai;
    return RichText(
      text: TextSpan(
        style: TextStyle(color: t.textSecondary, fontSize: 13),
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: AlunoHistoricoEdicaoService.formatarValor(
              value,
              somenteData: somenteData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevertidoInfo(Map<String, dynamic> data) {
    final t = context.uai;
    final quando = AlunoHistoricoEdicaoService.formatarValor(
      data['revertido_em'],
    );
    final por = data['revertido_por_nome']?.toString() ?? 'Usuário';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Text(
        'Edição revertida em $quando por $por',
        style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildEstado({
    required IconData icon,
    required String titulo,
    required String subtitulo,
  }) {
    final t = context.uai;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: t.primary),
              const SizedBox(height: 14),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipTipo(String? tipo, {String? subtipo}) {
    final t = context.uai;

    if (subtipo == 'mudanca_turma') {
      return _chip('Mudança de turma', t.associacao);
    }
    if (subtipo == 'reversao_mudanca_turma') {
      return _chip('Reversão de turma', t.warning);
    }
    if (subtipo == 'desativacao_aluno') {
      return _chip('Desativação', t.error);
    }
    if (subtipo == 'reativacao_aluno') {
      return _chip('Reativação', t.success);
    }

    switch (tipo) {
      case 'manual':
        return _chip('Manual', t.info);
      case 'solicitacao_area_aluno':
        return _chip('Solicitação aprovada', t.success);
      case 'reversao':
        return _chip('Reversão', t.warning);
      case 'desativacao':
        return _chip('Desativação', t.error);
      case 'reativacao':
        return _chip('Reativação', t.success);
      default:
        return _chip('Histórico', t.textMuted);
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _camposAlterados(Map<String, dynamic> data) {
    final raw = data['campos_alterados'];
    if (raw is! List) return const [];

    final campos = raw.whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      final campo = map['campo']?.toString() ?? '';
      map['label'] ??= AlunoHistoricoEdicaoService.labelCampo(campo);
      return map;
    }).toList();

    final nomesPresentes = campos
        .map((item) => item['campo']?.toString())
        .whereType<String>()
        .toSet();

    return campos.where((item) {
      final campo = item['campo']?.toString();
      if (campo == 'academia_id' && nomesPresentes.contains('academia')) {
        return false;
      }
      if (campo == 'turma_id' && nomesPresentes.contains('turma')) {
        return false;
      }
      return true;
    }).toList();
  }

  String _origemLegivel(String? origem) {
    switch (origem) {
      case 'editar_aluno_screen':
        return 'Edição da ficha';
      case 'aluno_detalhe_screen':
        return 'Perfil do aluno';
      case 'aluno_detalhe_mudar_turma':
        return 'Mudança de turma pelo perfil';
      case 'solicitacao_area_aluno_aprovada':
        return 'Solicitação aprovada da Área do Aluno';
      case 'vincular_aluno_inativo_turma_screen':
        return 'Reativação/vinculação em turma';
      case 'historico_edicoes_aluno':
        return 'Histórico de edições';
      default:
        return origem?.replaceAll('_', ' ') ?? 'Não informado';
    }
  }

  bool _campoEhData(dynamic campo) {
    return campo == 'data_nascimento' ||
        campo == 'data_graduacao_atual' ||
        campo == 'tempo_capoeira' ||
        campo == 'data_desativacao' ||
        campo == 'data_ativacao' ||
        campo == 'desativado_em' ||
        campo == 'reativado_em';
  }
}

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}
