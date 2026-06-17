import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';

class EscolherAlunoVinculadoScreen extends StatefulWidget {
  final List<AlunoVinculadoGoogle>? alunos;

  const EscolherAlunoVinculadoScreen({super.key, this.alunos});

  @override
  State<EscolherAlunoVinculadoScreen> createState() =>
      _EscolherAlunoVinculadoScreenState();
}

class _EscolherAlunoVinculadoScreenState
    extends State<EscolherAlunoVinculadoScreen> {
  final AreaAlunoGoogleService _googleService = AreaAlunoGoogleService();

  late Future<List<AlunoVinculadoGoogle>> _futureAlunos;
  String? _abrindoAlunoId;

  @override
  void initState() {
    super.initState();
    _futureAlunos = widget.alunos != null
        ? Future.value(widget.alunos!)
        : _googleService.buscarAlunosVinculados();
  }

  Future<void> _abrirAluno(AlunoVinculadoGoogle aluno) async {
    if (_abrindoAlunoId != null) return;

    setState(() => _abrindoAlunoId = aluno.alunoId);

    try {
      await _googleService.abrirAreaAlunoVinculado(context, aluno);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível abrir este perfil. Tente novamente.'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _abrindoAlunoId = null);
    }
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Escolher aluno',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
      ),
      body: FutureBuilder<List<AlunoVinculadoGoogle>>(
        future: _futureAlunos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.primary));
          }

          final alunos = snapshot.data ?? const <AlunoVinculadoGoogle>[];

          if (snapshot.hasError || alunos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(t.cardRadius),
                    border: Border.all(color: t.border),
                    boxShadow: t.softShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        color: t.textMuted,
                        size: 52,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Não encontramos perfis de aluno vinculados a esta conta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                    child: Text(
                      'Meus perfis vinculados',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ...alunos.map(_buildAlunoCard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlunoCard(AlunoVinculadoGoogle aluno) {
    final t = context.uai;
    final abrindo = _abrindoAlunoId == aluno.alunoId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.cardRadius),
        onTap: abrindo ? null : () => _abrirAluno(aluno),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: t.primary.withOpacity(0.10),
                backgroundImage: aluno.foto.isNotEmpty
                    ? NetworkImage(aluno.foto)
                    : null,
                child: aluno.foto.isEmpty
                    ? Icon(Icons.person_rounded, color: t.primary)
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aluno.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (aluno.graduacao.isNotEmpty) aluno.graduacao,
                        if (aluno.turma.isNotEmpty) aluno.turma,
                        if (aluno.academia.isNotEmpty) aluno.academia,
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (aluno.statusAtividade.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        aluno.statusAtividade,
                        style: TextStyle(
                          color: t.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: abrindo ? null : () => _abrirAluno(aluno),
                icon: abrindo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.school_rounded),
                label: const Text('Abrir'),
                style: FilledButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
