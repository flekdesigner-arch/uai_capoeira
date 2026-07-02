// lib/modules/sistema/admin/modo_troll_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class ModoTrollScreen extends StatefulWidget {
  const ModoTrollScreen({super.key});

  @override
  State<ModoTrollScreen> createState() => _ModoTrollScreenState();
}

class _ModoTrollScreenState extends State<ModoTrollScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PermissionAccessGuard _accessGuard = PermissionAccessGuard();

  bool _carregando = true;
  bool _salvando = false;
  bool _verificandoAcesso = true;
  bool _acessoNegado = false;
  bool _ativo = false;
  bool _chamadaTelepatia = false;
  bool _chamadaInversa = false;

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

  @override
  void initState() {
    super.initState();
    _verificarAcesso();
  }

  Future<void> _verificarAcesso() async {
    final permitido = await _accessGuard.canAccess(
      permission: 'pode_configurar_chamada',
    );
    if (!mounted) return;

    setState(() {
      _verificandoAcesso = false;
      _acessoNegado = !permitido;
    });

    if (permitido) {
      await _carregarConfiguracao();
    }
  }

  Future<bool> _revalidarAcesso() async {
    final permitido = await _accessGuard.canAccess(
      permission: 'pode_configurar_chamada',
    );
    if (!mounted) return false;

    if (!permitido) {
      setState(() => _acessoNegado = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Você não tem permissão para configurar brincadeiras da chamada.',
          ),
          backgroundColor: context.uai.error,
        ),
      );
    }

    return permitido;
  }

  Future<void> _carregarConfiguracao() async {
    if (!await _revalidarAcesso()) return;

    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('modo_troll')
          .get();

      final data = doc.data() ?? {};
      final trolagens = data['trolagens'];

      bool telepatia = false;
      bool inversa = false;

      if (trolagens is Map) {
        telepatia = trolagens['chamada_telepatia'] == true;
        inversa = trolagens['chamada_inversa'] == true;
      }

      if (!mounted) return;
      setState(() {
        _ativo = data['ativo'] == true;
        _chamadaTelepatia = telepatia;
        _chamadaInversa = inversa;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar configurações: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    }
  }

  Future<void> _salvarConfiguracao() async {
    if (!await _revalidarAcesso()) return;

    setState(() => _salvando = true);

    try {
      await _firestore
          .collection('configuracoes_sistema')
          .doc('modo_troll')
          .set({
            'ativo': _ativo,
            'trolagens': {
              'chamada_telepatia': _chamadaTelepatia,
              'chamada_inversa': _chamadaInversa,
            },
            'atualizado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configuração salva com sucesso!'),
          backgroundColor: context.uai.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar configurações: $e'),
          backgroundColor: context.uai.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAcesso) {
      return PermissionAccessGuard.loadingScaffold(
        context,
        title: 'Brincadeiras da Chamada',
      );
    }

    if (_acessoNegado) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: 'Brincadeiras da Chamada',
        message:
            'Você não tem permissão para configurar brincadeiras da chamada.',
      );
    }

    final t = context.uai;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor ?? t.primary;
    final appBarFg =
        Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(appBarBg);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Brincadeiras da Chamada',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracao,
            icon: _salvando
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: appBarFg,
                    ),
                  )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: _carregando
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                _buildHeader(context),
                const SizedBox(height: 14),
                _buildGeralSwitch(context),
                const SizedBox(height: 14),
                _buildItem(
                  context: context,
                  icon: Icons.psychology_alt_rounded,
                  title: 'Chamada por Telepatia',
                  subtitle:
                      'Só acontece quando já existe uma chamada real salva para o dia. A tela reproduz visualmente os dados reais, registra em trolldata do usuário e depois volta a aparecer normal.',
                  color: t.associacao,
                  value: _chamadaTelepatia,
                  onChanged: (value) =>
                      setState(() => _chamadaTelepatia = value),
                ),
                const SizedBox(height: 10),
                _buildItem(
                  context: context,
                  icon: Icons.swap_vert_circle_rounded,
                  title: 'Chamada Inversa',
                  subtitle:
                      'Nos primeiros 20 segundos de uma chamada real nova, ao tocar em um aluno, o app marca o card vizinho. Depois volta ao normal para o professor corrigir e salvar de verdade.',
                  color: t.warning,
                  value: _chamadaInversa,
                  onChanged: (value) => setState(() => _chamadaInversa = value),
                ),
                const SizedBox(height: 16),
                _buildAvisoSeguro(context),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvarConfiguracao,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _salvando ? 'SALVANDO...' : 'SALVAR CONFIGURAÇÃO',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appBarBg,
                    foregroundColor: appBarFg,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: onPrimary.withOpacity(0.16)),
                ),
                child: Icon(
                  Icons.theater_comedy_rounded,
                  color: onPrimary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Painel secreto da chamada',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ative apenas brincadeiras que já têm efeito real na tela de chamada.',
                      style: TextStyle(
                        color: onPrimary.withOpacity(0.80),
                        fontSize: 12,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeralSwitch(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: SwitchListTile(
        value: _ativo,
        onChanged: (value) => setState(() => _ativo = value),
        activeColor: t.success,
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Ativar painel secreto',
          style: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          _ativo
              ? 'As brincadeiras selecionadas podem funcionar nas próximas chamadas.'
              : 'Tudo fica desligado, mesmo que os itens abaixo estejam marcados.',
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(
          color: value ? accent.withOpacity(0.32) : t.border,
          width: value ? 1.4 : 1,
        ),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(t.buttonRadius),
              border: Border.all(color: accent.withOpacity(0.16)),
            ),
            child: Icon(icon, color: accent, size: 26),
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
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, activeColor: t.success, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildAvisoSeguro(BuildContext context) {
    final t = context.uai;
    final accent = _ensureVisible(t.info, t.card);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security_rounded, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A telepatia só reproduz chamada já existente. A chamada inversa altera apenas a marcação visual inicial, e o professor ainda salva a chamada real normalmente depois de conferir.',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                height: 1.32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
