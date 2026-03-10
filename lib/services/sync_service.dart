import 'dart:async'; // ✅ IMPORT OBRIGATÓRIO PARA StreamController
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  // StreamController para o contador global de pendências
  final _pendingCountController = StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  // Cache do último valor do contador
  int _currentPendingCount = 0;
  int get currentPendingCount => _currentPendingCount;

  // Mapa para rastrear quais documentos estão pendentes (opcional, para performance)
  final Map<String, bool> _pendingStatus = {};

  /// Atualiza o contador de documentos pendentes
  void updatePendingCount(QuerySnapshot snapshot) {
    int pending = 0;

    for (var doc in snapshot.docs) {
      final isPending = doc.metadata.hasPendingWrites;
      final docId = doc.id;

      // Atualiza cache do status
      _pendingStatus[docId] = isPending;

      if (isPending) pending++;
    }

    // Só emite se mudou
    if (_currentPendingCount != pending) {
      _currentPendingCount = pending;
      _pendingCountController.add(pending);
    }
  }

  /// Verifica se um documento específico está pendente
  bool isDocumentPending(QueryDocumentSnapshot doc) {
    return doc.metadata.hasPendingWrites;
  }

  /// Verifica se um documento específico está pendente (por ID)
  bool isDocumentPendingById(String docId) {
    return _pendingStatus[docId] ?? false;
  }

  /// Limpa o cache
  void clearCache() {
    _pendingStatus.clear();
    _currentPendingCount = 0;
    _pendingCountController.add(0);
  }

  /// Libera recursos
  void dispose() {
    _pendingCountController.close();
  }
}