// lib/shared/screens/notificacoes/notificacoes_screen.dart
//
// =====================================================
// 🔔 CENTRAL DE NOTIFICAÇÕES - UAI CAPOEIRA
// =====================================================
//
// Usa o sininho do AppBar.
//
// Abas:
// 1. Notificações
//    Lê usuarios/{uid}/notificacoes
//
// 2. Atualizações
//    Lê versoes_app publicadas e mostra histórico/changelog.
//
// Observação:
// - Push de nova versão APK continua indo só para APK.
// - PWA não recebe diálogo de APK.
// - Mesmo no PWA, o usuário consegue abrir o sininho e ver o histórico
//   de atualizações publicadas.
// =====================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/sistema/atualizacoes/models/app_version_model.dart';

class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.25) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.12).clamp(0.0, 1.0))
        .toColor();
  }

  Color _softFill(Color color, Color base, [double opacity = 0.10]) {
    return Color.alphaBlend(color.withOpacity(opacity), base);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Notificações',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            height: 58,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.20)),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withOpacity(0.72),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.notifications_active_rounded),
                  text: 'Notificações',
                ),
                Tab(
                  icon: Icon(Icons.system_update_alt_rounded),
                  text: 'Atualizações',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaNotificacoes(),
          _buildAbaAtualizacoes(),
        ],
      ),
    );
  }

  Widget _page({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 640 ? 14.0 : 22.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 30),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAbaNotificacoes() {
    final user = _auth.currentUser;
    final t = context.uai;

    if (user == null) {
      return _page(
        children: [
          _emptyState(
            icon: Icons.person_off_rounded,
            title: 'Usuário não autenticado',
            subtitle: 'Faça login para visualizar suas notificações.',
          ),
        ],
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('usuarios')
          .doc(user.uid)
          .collection('notificacoes')
          .orderBy('criada_em', descending: true)
          .limit(80)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.primary));
        }

        if (snapshot.hasError) {
          return _page(
            children: [
              _premiumInfo(
                icon: Icons.error_outline_rounded,
                title: 'Erro ao carregar notificações',
                text: '${snapshot.error}',
                color: t.error,
              ),
            ],
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _page(
            children: [
              _hero(),
              const SizedBox(height: 14),
              _emptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Nenhuma notificação ainda',
                subtitle:
                'Quando chegarem avisos de aniversário, atualizações e comunicados, eles aparecerão aqui.',
              ),
            ],
          );
        }

        final naoLidas = docs.where((doc) => doc.data()['lida'] != true).length;

        return _page(
          children: [
            _hero(total: docs.length, naoLidas: naoLidas),
            const SizedBox(height: 14),
            if (naoLidas > 0) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _marcarTodasComoLidas(user.uid, docs),
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Marcar todas como lidas'),
                ),
              ),
              const SizedBox(height: 4),
            ],
            for (final doc in docs) ...[
              _notificationCard(doc),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAbaAtualizacoes() {
    final t = context.uai;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('versoes_app')
          .where('publicada', isEqualTo: true)
          .orderBy('publicadoEm', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: t.primary));
        }

        if (snapshot.hasError) {
          return _page(
            children: [
              _premiumInfo(
                icon: Icons.error_outline_rounded,
                title: 'Erro ao carregar histórico',
                text:
                'Talvez precise criar índice no Firestore para publicada + publicadoEm.\n\n${snapshot.error}',
                color: t.error,
              ),
            ],
          );
        }

        final versions = (snapshot.data?.docs ?? [])
            .map(AppVersionModel.fromFirestore)
            .toList();

        if (versions.isEmpty) {
          return _page(
            children: [
              _emptyState(
                icon: Icons.system_update_alt_rounded,
                title: 'Nenhuma atualização publicada',
                subtitle:
                'Quando você publicar uma versão pelo laboratório, o histórico aparecerá aqui.',
              ),
            ],
          );
        }

        return _page(
          children: [
            _updatesHero(versions),
            const SizedBox(height: 14),
            for (final version in versions) ...[
              _versionHistoryCard(version),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _hero({int total = 0, int naoLidas = 0}) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.alphaBlend(Colors.black.withOpacity(0.14), primary),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius + 4),
              border: Border.all(color: onPrimary.withOpacity(0.18)),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: onPrimary,
              size: 31,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'Central de notificações'
                      : '$total notificação(ões)',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 20,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  naoLidas > 0
                      ? '$naoLidas ainda não lida(s)'
                      : 'Aniversários, atualizações e avisos importantes em um só lugar.',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.84),
                    height: 1.25,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _updatesHero(List<AppVersionModel> versions) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final onPrimary = _readableOn(primary);
    final latest = versions.first;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.alphaBlend(Colors.black.withOpacity(0.14), primary),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(t.cardRadius + 6),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.buttonRadius + 4),
              border: Border.all(color: onPrimary.withOpacity(0.18)),
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              color: onPrimary,
              size: 31,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Histórico de atualizações',
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 20,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Última versão: ${latest.versao} • ${latest.obrigatoria ? "Obrigatória" : "Opcional"}',
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.84),
                    height: 1.25,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final t = context.uai;
    final data = doc.data();

    final tipo = (data['tipo'] ?? 'geral').toString();
    final titulo = (data['titulo'] ?? 'Notificação').toString();
    final mensagem = (data['mensagem'] ?? '').toString();
    final lida = data['lida'] == true;
    final criadaEm = _asDate(data['criada_em']);
    final color = _colorForTipo(tipo);
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _marcarComoLida(doc),
        borderRadius: BorderRadius.circular(t.cardRadius),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: lida ? t.card : _softFill(accent, t.card, 0.055),
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: lida ? t.border : accent.withOpacity(0.20),
            ),
            boxShadow: t.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _softFill(accent, t.cardAlt, 0.14),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: accent.withOpacity(0.12)),
                    ),
                    child: Icon(_iconForTipo(tipo), color: accent),
                  ),
                  if (!lida)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mensagem.isEmpty ? 'Sem mensagem.' : mensagem,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.28,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tipo.toLowerCase().contains('chamada')) ...[
                      const SizedBox(height: 9),
                      _chamadaMiniResumo(data),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      _formatDate(criadaEm),
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _chamadaMiniResumo(Map<String, dynamic> data) {
    final t = context.uai;

    final payloadRaw = data['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};

    final turma = (payload['turma_nome'] ?? '').toString();
    final academia = (payload['academia_nome'] ?? '').toString();
    final presentes = (payload['presentes'] ?? '').toString();
    final ausentes = (payload['ausentes'] ?? '').toString();
    final frequencia = (payload['porcentagem_frequencia'] ?? '').toString();
    final hora = (payload['hora_brasilia'] ?? '').toString();

    final chips = <Widget>[];

    if (turma.isNotEmpty) {
      chips.add(_miniChip(Icons.groups_rounded, turma, t.primary));
    }

    if (academia.isNotEmpty) {
      chips.add(_miniChip(Icons.location_city_rounded, academia, t.info));
    }

    if (hora.isNotEmpty) {
      chips.add(_miniChip(Icons.schedule_rounded, '$hora BR', t.warning));
    }

    if (presentes.isNotEmpty) {
      chips.add(_miniChip(Icons.check_circle_rounded, '$presentes presentes', t.success));
    }

    if (ausentes.isNotEmpty) {
      chips.add(_miniChip(Icons.cancel_rounded, '$ausentes ausentes', t.error));
    }

    if (frequencia.isNotEmpty) {
      chips.add(_miniChip(Icons.percent_rounded, '$frequencia%', t.primary));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _miniChip(IconData icon, String text, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _softFill(accent, t.cardAlt, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionHistoryCard(AppVersionModel version) {
    final t = context.uai;
    final color = _ensureVisible(
      version.obrigatoria ? t.warning : t.success,
      t.card,
    );

    final publicado = _formatDate(version.publicadoEm ?? version.criadoEm);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: color.withOpacity(0.16)),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _softFill(color, t.cardAlt, 0.14),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: color.withOpacity(0.12)),
                ),
                child: Icon(
                  version.obrigatoria
                      ? Icons.lock_rounded
                      : Icons.verified_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version.titulo.trim().isEmpty
                          ? 'Versão ${version.versao}'
                          : version.titulo,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'v${version.versao} • ${version.obrigatoria ? "Obrigatória" : "Opcional"} • $publicado',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (version.resumo.trim().isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              version.resumo,
              style: TextStyle(
                color: t.textSecondary,
                height: 1.28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 11),
          _changelogPreview(version),
        ],
      ),
    );
  }

  Widget _changelogPreview(AppVersionModel version) {
    final items = <_ChangeGroup>[
      _ChangeGroup('Implementações', Icons.add_circle_outline_rounded, version.implementacoes),
      _ChangeGroup('Melhorias', Icons.trending_up_rounded, version.melhorias),
      _ChangeGroup('Correções', Icons.bug_report_rounded, version.correcoes),
      _ChangeGroup('Removidos', Icons.remove_circle_outline_rounded, version.removidos),
    ].where((g) => g.items.isNotEmpty).toList();

    if (items.isEmpty) {
      return _premiumInfo(
        icon: Icons.info_outline_rounded,
        title: 'Sem changelog detalhado',
        text: 'Esta versão não possui detalhes cadastrados.',
        color: context.uai.info,
      );
    }

    return Column(
      children: [
        for (final group in items.take(4)) ...[
          _changeGroup(group),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _changeGroup(_ChangeGroup group) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(group.icon, color: primary, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  group.title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final item in group.items.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.25,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        children: [
          Icon(icon, color: t.textMuted, size: 52),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumInfo({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _softFill(accent, t.card, 0.07),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _marcarComoLida(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) async {
    final data = doc.data();
    if (data['lida'] == true) return;

    try {
      await doc.reference.set({
        'lida': true,
        'lida_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao marcar notificação como lida: $e');
    }
  }

  Future<void> _marcarTodasComoLidas(
      String uid,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    try {
      final batch = _firestore.batch();

      for (final doc in docs) {
        if (doc.data()['lida'] == true) continue;

        batch.set(doc.reference, {
          'lida': true,
          'lida_em': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Erro ao marcar todas como lidas: $e');
    }
  }

  Color _colorForTipo(String tipo) {
    final t = context.uai;
    final normalized = tipo.toLowerCase();

    if (normalized.contains('anivers')) return t.warning;
    if (normalized.contains('chamada') || normalized.contains('presenca')) {
      return t.primary;
    }
    if (normalized.contains('versao') || normalized.contains('atualiz')) {
      return t.success;
    }

    return t.info;
  }

  IconData _iconForTipo(String tipo) {
    final normalized = tipo.toLowerCase();

    if (normalized.contains('anivers')) return Icons.cake_rounded;
    if (normalized.contains('chamada') || normalized.contains('presenca')) {
      return Icons.fact_check_rounded;
    }
    if (normalized.contains('versao') || normalized.contains('atualiz')) {
      return Icons.system_update_alt_rounded;
    }

    return Icons.notifications_active_rounded;
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Sem data';

    final d = date.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');

    return '$day/$month/$year às $hour:$minute';
  }
}

class _ChangeGroup {
  final String title;
  final IconData icon;
  final List<String> items;

  const _ChangeGroup(this.title, this.icon, this.items);
}
