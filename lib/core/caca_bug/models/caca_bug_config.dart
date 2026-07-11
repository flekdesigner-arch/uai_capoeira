import 'package:cloud_firestore/cloud_firestore.dart';

class CacaBugConfig {
  final bool ativo;
  final bool registrarTodosUsuarios;
  final List<String> usuariosMonitorados;
  final bool registrarEventosHumanos;
  final bool registrarEventosTecnicos;
  final bool registrarNavegacao;
  final bool registrarErros;
  final int maxEventosPorSessao;
  final int retencaoDias;
  final int flushIntervalSegundos;
  final int maxEventosPorFlush;
  final int dedupeJanelaMs;
  final DateTime? atualizadoEm;
  final String? atualizadoPorUid;
  final String? atualizadoPorNome;

  const CacaBugConfig({
    required this.ativo,
    required this.registrarTodosUsuarios,
    required this.usuariosMonitorados,
    required this.registrarEventosHumanos,
    required this.registrarEventosTecnicos,
    required this.registrarNavegacao,
    required this.registrarErros,
    required this.maxEventosPorSessao,
    required this.retencaoDias,
    required this.flushIntervalSegundos,
    required this.maxEventosPorFlush,
    required this.dedupeJanelaMs,
    this.atualizadoEm,
    this.atualizadoPorUid,
    this.atualizadoPorNome,
  });

  factory CacaBugConfig.defaults() {
    return const CacaBugConfig(
      ativo: false,
      registrarTodosUsuarios: false,
      usuariosMonitorados: [],
      registrarEventosHumanos: true,
      registrarEventosTecnicos: true,
      registrarNavegacao: false,
      registrarErros: true,
      maxEventosPorSessao: 300,
      retencaoDias: 7,
      flushIntervalSegundos: 10,
      maxEventosPorFlush: 20,
      dedupeJanelaMs: 1500,
    );
  }

  factory CacaBugConfig.fromMap(Map<String, dynamic>? map) {
    final base = CacaBugConfig.defaults();
    if (map == null) return base;

    DateTime? toDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    int intInRange(dynamic value, int fallback, int min, int max) {
      final parsed = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
      return (parsed ?? fallback).clamp(min, max);
    }

    return CacaBugConfig(
      ativo: map['ativo'] == true,
      registrarTodosUsuarios: map['registrarTodosUsuarios'] == true,
      usuariosMonitorados: List<String>.from(
        (map['usuariosMonitorados'] as List? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty),
      ),
      registrarEventosHumanos: map['registrarEventosHumanos'] is bool
          ? map['registrarEventosHumanos'] == true
          : base.registrarEventosHumanos,
      registrarEventosTecnicos: map['registrarEventosTecnicos'] is bool
          ? map['registrarEventosTecnicos'] == true
          : base.registrarEventosTecnicos,
      registrarNavegacao: map['registrarNavegacao'] == true,
      registrarErros: map['registrarErros'] is bool
          ? map['registrarErros'] == true
          : base.registrarErros,
      maxEventosPorSessao: intInRange(
        map['maxEventosPorSessao'],
        base.maxEventosPorSessao,
        20,
        1000,
      ),
      retencaoDias: intInRange(map['retencaoDias'], base.retencaoDias, 1, 30),
      flushIntervalSegundos: intInRange(
        map['flushIntervalSegundos'],
        base.flushIntervalSegundos,
        5,
        60,
      ),
      maxEventosPorFlush: intInRange(
        map['maxEventosPorFlush'],
        base.maxEventosPorFlush,
        5,
        100,
      ),
      dedupeJanelaMs: intInRange(
        map['dedupeJanelaMs'],
        base.dedupeJanelaMs,
        300,
        10000,
      ),
      atualizadoEm: toDate(map['atualizadoEm']),
      atualizadoPorUid: map['atualizadoPorUid']?.toString(),
      atualizadoPorNome: map['atualizadoPorNome']?.toString(),
    );
  }

  Map<String, dynamic> toMapForSave() {
    return {
      'ativo': ativo,
      'registrarTodosUsuarios': registrarTodosUsuarios,
      'usuariosMonitorados': usuariosMonitorados,
      'registrarEventosHumanos': registrarEventosHumanos,
      'registrarEventosTecnicos': registrarEventosTecnicos,
      'registrarNavegacao': registrarNavegacao,
      'registrarErros': registrarErros,
      'maxEventosPorSessao': maxEventosPorSessao.clamp(20, 1000),
      'retencaoDias': retencaoDias.clamp(1, 30),
      'flushIntervalSegundos': flushIntervalSegundos.clamp(5, 60),
      'maxEventosPorFlush': maxEventosPorFlush.clamp(5, 100),
      'dedupeJanelaMs': dedupeJanelaMs.clamp(300, 10000),
    };
  }

  CacaBugConfig copyWith({
    bool? ativo,
    bool? registrarTodosUsuarios,
    List<String>? usuariosMonitorados,
    bool? registrarEventosHumanos,
    bool? registrarEventosTecnicos,
    bool? registrarNavegacao,
    bool? registrarErros,
    int? maxEventosPorSessao,
    int? retencaoDias,
    int? flushIntervalSegundos,
    int? maxEventosPorFlush,
    int? dedupeJanelaMs,
    DateTime? atualizadoEm,
    String? atualizadoPorUid,
    String? atualizadoPorNome,
  }) {
    return CacaBugConfig.fromMap({
      ...toMapForSave(),
      'ativo': ativo ?? this.ativo,
      'registrarTodosUsuarios':
          registrarTodosUsuarios ?? this.registrarTodosUsuarios,
      'usuariosMonitorados': usuariosMonitorados ?? this.usuariosMonitorados,
      'registrarEventosHumanos':
          registrarEventosHumanos ?? this.registrarEventosHumanos,
      'registrarEventosTecnicos':
          registrarEventosTecnicos ?? this.registrarEventosTecnicos,
      'registrarNavegacao': registrarNavegacao ?? this.registrarNavegacao,
      'registrarErros': registrarErros ?? this.registrarErros,
      'maxEventosPorSessao': maxEventosPorSessao ?? this.maxEventosPorSessao,
      'retencaoDias': retencaoDias ?? this.retencaoDias,
      'flushIntervalSegundos':
          flushIntervalSegundos ?? this.flushIntervalSegundos,
      'maxEventosPorFlush': maxEventosPorFlush ?? this.maxEventosPorFlush,
      'dedupeJanelaMs': dedupeJanelaMs ?? this.dedupeJanelaMs,
      'atualizadoEm': atualizadoEm ?? this.atualizadoEm,
      'atualizadoPorUid': atualizadoPorUid ?? this.atualizadoPorUid,
      'atualizadoPorNome': atualizadoPorNome ?? this.atualizadoPorNome,
    });
  }

  bool deveMonitorarUsuario(String? uid) {
    final id = uid?.trim() ?? '';
    if (!ativo || id.isEmpty) return false;
    if (registrarTodosUsuarios) return true;
    return usuariosMonitorados.contains(id);
  }
}
