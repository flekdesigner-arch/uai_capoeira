import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'caca_bug_actions.dart';
import 'models/caca_bug_config.dart';
import 'models/caca_bug_event_model.dart';
import 'models/caca_bug_session_model.dart';

class CacaBugService {
  CacaBugService._();

  static final CacaBugService instance = CacaBugService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<CacaBugEventModel> _fila = [];
  final Map<String, DateTime> _dedupe = {};

  CacaBugConfig _config = CacaBugConfig.defaults();
  CacaBugSessionModel? _sessao;
  Timer? _flushTimer;
  bool _configCarregada = false;
  bool _flushEmAndamento = false;
  bool _limiteRegistrado = false;
  int _ordem = 0;
  int _eventosPersistidos = 0;
  String? _uidInicializado;

  bool get ativo => _config.ativo;
  bool get coletando => _sessao != null && _config.ativo;
  CacaBugConfig get configAtual => _config;

  Future<void> inicializar({User? user}) async {
    try {
      if (user == null) return;
      if (_sessao != null && _sessao!.uid == user.uid && _config.ativo) return;
      if (_uidInicializado == user.uid && _configCarregada) return;

      _uidInicializado = user.uid;
      await _carregarConfigUmaVez();

      if (!_config.ativo || !_config.deveMonitorarUsuario(user.uid)) {
        _desligarColetaLocal();
        return;
      }

      if (_sessao?.uid == user.uid) return;
      await iniciarSessao(user: user);
    } catch (e) {
      _desligarColetaLocal();
      _logControlado('Erro ao inicializar Caça Bug: $e');
    }
  }

  Future<void> refreshConfig() async {
    try {
      final doc = await _firestore
          .collection('configuracoes_sistema')
          .doc('caca_bug')
          .get(const GetOptions(source: Source.server));

      _config = doc.exists
          ? CacaBugConfig.fromMap(doc.data())
          : CacaBugConfig.defaults();
      _configCarregada = true;

      if (!_config.ativo) {
        _desligarColetaLocal();
      }
    } catch (e) {
      _config = CacaBugConfig.defaults();
      _configCarregada = true;
      _desligarColetaLocal();
      _logControlado('Erro ao atualizar configuração Caça Bug: $e');
    }
  }

  Future<void> iniciarSessao({required User user, String? nome}) async {
    try {
      if (!_config.ativo || !_config.deveMonitorarUsuario(user.uid)) return;

      final now = DateTime.now();
      final packageInfo = await PackageInfo.fromPlatform();
      final sessaoId = _firestore.collection('caca_bug_sessoes').doc().id;

      _sessao = CacaBugSessionModel(
        sessaoId: sessaoId,
        uid: user.uid,
        email: _sanitizeShort(user.email),
        nome: _sanitizeShort(nome ?? user.displayName),
        inicioEm: now,
        ativo: true,
        plataforma: _plataforma(),
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        deviceInfo: {
          'isWeb': kIsWeb,
          'targetPlatform': defaultTargetPlatform.name,
        },
        userAgent: null,
        eventosCount: 0,
        errosCount: 0,
        ultimaTela: 'HomePage',
        ultimoArquivo: 'lib/app/home_page.dart',
        ultimoEventoResumo: 'Sessão de diagnóstico iniciada',
      );

      _fila.clear();
      _dedupe.clear();
      _ordem = 0;
      _eventosPersistidos = 0;
      _limiteRegistrado = false;

      unawaited(
        registrarEvento(
          tipo: 'sistema',
          acao: CacaBugActions.sessaoIniciada,
          descricao: 'Sessão de diagnóstico iniciada',
          tela: 'HomePage',
          arquivo: 'lib/app/home_page.dart',
          rota: '/home',
          status: 'info',
        ),
      );

      await _firestore
          .collection('caca_bug_sessoes')
          .doc(sessaoId)
          .set(_sessao!.toMap(), SetOptions(merge: true));

      await _finalizarSessoesAntigasDoUsuario(user.uid, sessaoId);
      _iniciarTimer();
    } catch (e) {
      _desligarColetaLocal();
      _logControlado('Erro ao iniciar sessão Caça Bug: $e');
    }
  }

  Future<void> finalizarSessao({
    String motivo = 'manual',
    bool registrarEventoFinal = true,
  }) async {
    try {
      if (!coletando) return;

      final sessao = _sessao;
      if (sessao == null) return;

      if (registrarEventoFinal) {
        await registrarEvento(
          tipo: 'sistema',
          acao: CacaBugActions.sessaoFinalizada,
          descricao: 'Sessão de diagnóstico finalizada',
          tela: sessao.ultimaTela ?? '',
          arquivo: sessao.ultimoArquivo ?? '',
          rota: '',
          status: 'info',
        );
      }

      await flush(force: true);

      await _firestore.collection('caca_bug_sessoes').doc(sessao.sessaoId).set({
        'ativo': false,
        'fimEm': FieldValue.serverTimestamp(),
        'ultimoEventoResumo': 'Sessão finalizada',
        'finalizadaPor': motivo,
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logControlado('Erro ao finalizar sessão Caça Bug: $e');
    } finally {
      _desligarColetaLocal();
    }
  }

  Future<void> registrarEvento({
    required String tipo,
    required String acao,
    required String descricao,
    required String tela,
    required String arquivo,
    String rota = '',
    String status = 'info',
    Map<String, dynamic>? dados,
  }) async {
    try {
      if (!coletando) return;
      if (!_tipoPermitido(tipo) || !_statusPermitido(status)) return;
      if (tipo == 'navegacao' && !_config.registrarNavegacao) return;
      if (tipo == 'erro' && !_config.registrarErros) return;

      if (_eventosPersistidos + _fila.length >= _config.maxEventosPorSessao) {
        await _registrarLimiteSeNecessario();
        return;
      }

      final canalDedupe = dados?['canal']?.toString().trim();
      final destinoTipoDedupe = dados?['destinoTipo']?.toString().trim();
      final temDiscriminadorContato =
          canalDedupe != null &&
          canalDedupe.isNotEmpty &&
          destinoTipoDedupe != null &&
          destinoTipoDedupe.isNotEmpty;
      final dedupeKey = temDiscriminadorContato
          ? '$acao|$tela|$status|$canalDedupe|$destinoTipoDedupe'
          : '$acao|$tela|$status';
      final now = DateTime.now();
      final last = _dedupe[dedupeKey];
      if (last != null &&
          now.difference(last).inMilliseconds < _config.dedupeJanelaMs) {
        return;
      }
      _dedupe[dedupeKey] = now;

      final eventId = _firestore
          .collection('caca_bug_sessoes')
          .doc(_sessao!.sessaoId)
          .collection('eventos')
          .doc()
          .id;

      _fila.add(
        CacaBugEventModel.create(
          id: eventId,
          tipo: tipo,
          acao: acao,
          descricao: descricao,
          tela: tela,
          arquivo: arquivo,
          rota: rota,
          status: status,
          dados: dados,
          ordem: ++_ordem,
          erro: null,
        ),
      );

      _apararFila();
      if (_fila.length >= _config.maxEventosPorFlush) {
        unawaited(flush());
      }
    } catch (e) {
      _logControlado('Erro ao enfileirar evento Caça Bug: $e');
    }
  }

  Future<void> registrarErro({
    required String acao,
    required String descricao,
    required String tela,
    required String arquivo,
    String rota = '',
    Object? erro,
    StackTrace? stackTrace,
    Map<String, dynamic>? dados,
  }) async {
    if (!coletando || !_config.registrarErros) return;

    final erroMap = {
      'message': _sanitizeErrorMessage(erro, fallback: descricao),
      if (stackTrace != null) 'stackTrace': _sanitizeErrorMessage(stackTrace),
    };

    await _registrarEventoComErro(
      acao: acao,
      descricao: descricao,
      tela: tela,
      arquivo: arquivo,
      rota: rota,
      dados: dados,
      erro: erroMap,
    );
  }

  Future<void> flush({bool force = false}) async {
    if (!coletando || _flushEmAndamento) return;
    if (_fila.isEmpty) return;

    _flushEmAndamento = true;
    try {
      final sessao = _sessao!;
      final eventos = _fila
          .take(force ? _fila.length : _config.maxEventosPorFlush)
          .toList(growable: false);
      final batch = _firestore.batch();
      final sessaoRef = _firestore
          .collection('caca_bug_sessoes')
          .doc(sessao.sessaoId);

      for (final evento in eventos) {
        final eventRef = sessaoRef.collection('eventos').doc(evento.id);
        batch.set(eventRef, evento.toMap(), SetOptions(merge: true));
      }

      final errosNovos = eventos.where((e) => e.tipo == 'erro').length;
      final ultimo = eventos.last;
      batch.set(sessaoRef, {
        ...sessao.toMap(),
        'eventosCount': FieldValue.increment(eventos.length),
        'errosCount': FieldValue.increment(errosNovos),
        'ultimoEventoEm': FieldValue.serverTimestamp(),
        'ultimaTela': ultimo.tela,
        'ultimoArquivo': ultimo.arquivo,
        'ultimoEventoResumo': ultimo.descricao,
      }, SetOptions(merge: true));

      await batch.commit();

      _fila.removeRange(0, eventos.length);
      _eventosPersistidos += eventos.length;
    } catch (e) {
      _apararFila();
      _logControlado('Erro no flush Caça Bug: $e');
    } finally {
      _flushEmAndamento = false;
    }
  }

  Future<void> _finalizarSessoesAntigasDoUsuario(
    String uid,
    String sessaoAtualId,
  ) async {
    try {
      _logControlado('Caça Bug: finalizando sessões antigas do uid $uid.');
      final antigas = await _firestore
          .collection('caca_bug_sessoes')
          .where('uid', isEqualTo: uid)
          .where('ativo', isEqualTo: true)
          .limit(50)
          .get();

      final docsOrdenados = antigas.docs.toList()
        ..sort((a, b) {
          final bInicio = _inicioSessaoComparavel(b.data()['inicioEm']);
          final aInicio = _inicioSessaoComparavel(a.data()['inicioEm']);
          return bInicio.compareTo(aInicio);
        });

      final antigasParaFinalizar = docsOrdenados
          .where((doc) => doc.id != sessaoAtualId)
          .take(30)
          .toList(growable: false);
      if (antigasParaFinalizar.isEmpty) {
        _logControlado('Caça Bug: nenhuma sessão antiga ativa encontrada.');
        return;
      }

      final batch = _firestore.batch();
      for (final doc in antigasParaFinalizar) {
        batch.set(doc.reference, {
          'ativo': false,
          'fimEm': FieldValue.serverTimestamp(),
          'ultimoEventoResumo':
              'Sessão finalizada automaticamente ao iniciar nova sessão',
          'finalizadaPor': 'auto_nova_sessao',
          'atualizadoEm': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      _logControlado(
        'Caça Bug: ${antigasParaFinalizar.length} sessão(ões) antiga(s) finalizada(s).',
      );
    } catch (e) {
      _logControlado(
        'Caça Bug: não foi possível finalizar sessões antigas sem índice composto: $e',
      );
    }
  }

  DateTime _inicioSessaoComparavel(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1970);
    return DateTime(1970);
  }

  Future<void> _carregarConfigUmaVez() async {
    if (_configCarregada) return;
    await refreshConfig();
  }

  Future<void> _registrarEventoComErro({
    required String acao,
    required String descricao,
    required String tela,
    required String arquivo,
    required String rota,
    Map<String, dynamic>? dados,
    required Map<String, dynamic> erro,
  }) async {
    if (!coletando) return;
    final eventId = _firestore
        .collection('caca_bug_sessoes')
        .doc(_sessao!.sessaoId)
        .collection('eventos')
        .doc()
        .id;
    _fila.add(
      CacaBugEventModel.create(
        id: eventId,
        tipo: 'erro',
        acao: acao,
        descricao: descricao,
        tela: tela,
        arquivo: arquivo,
        rota: rota,
        status: 'error',
        dados: dados,
        erro: erro,
        ordem: ++_ordem,
      ),
    );
    _apararFila();
    if (_fila.length >= _config.maxEventosPorFlush) {
      unawaited(flush());
    }
  }

  Future<void> _registrarLimiteSeNecessario() async {
    if (_limiteRegistrado) return;
    _limiteRegistrado = true;
    if (_eventosPersistidos + _fila.length >= _config.maxEventosPorSessao) {
      return;
    }
    await registrarEvento(
      tipo: 'sistema',
      acao: CacaBugActions.limiteEventosAtingido,
      descricao: 'Limite de eventos da sessão atingido',
      tela: _sessao?.ultimaTela ?? '',
      arquivo: _sessao?.ultimoArquivo ?? '',
      status: 'warning',
    );
  }

  void _iniciarTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      Duration(seconds: _config.flushIntervalSegundos),
      (_) => unawaited(flush()),
    );
  }

  void _desligarColetaLocal() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _sessao = null;
    _fila.clear();
    _dedupe.clear();
    _ordem = 0;
    _eventosPersistidos = 0;
    _limiteRegistrado = false;
  }

  void _apararFila() {
    final limite = _config.maxEventosPorSessao < 100
        ? _config.maxEventosPorSessao
        : 100;
    if (_fila.length <= limite) return;
    _fila.removeRange(0, _fila.length - limite);
  }

  bool _tipoPermitido(String tipo) {
    return const {
      'navegacao',
      'acao_usuario',
      'erro',
      'sistema',
      'performance',
    }.contains(tipo);
  }

  bool _statusPermitido(String status) {
    return const {'success', 'error', 'info', 'warning'}.contains(status);
  }

  String _plataforma() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  String? _sanitizeShort(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= 160 ? text : text.substring(0, 160);
  }

  String _sanitizeErrorMessage(Object? erro, {String fallback = ''}) {
    var texto = erro?.toString() ?? fallback;
    texto = texto
        .replaceAll(RegExp(r'https?:\/\/\S+'), '[url_redigida]')
        .replaceAll(RegExp(r'wa\.me\/\S+'), '[whatsapp_redigido]')
        .replaceAll(RegExp(r'api\.whatsapp\.com\/\S+'), '[whatsapp_redigido]')
        .replaceAll(RegExp(r'tel:\S+'), '[telefone_redigido]')
        .replaceAll(RegExp(r'\+?\d[\d\s\-\(\)]{7,}\d'), '[numero_redigido]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (texto.length <= 180) return texto;
    return '${texto.substring(0, 180)}...';
  }

  void _logControlado(String message) {
    if (kDebugMode) debugPrint(message);
  }
}
