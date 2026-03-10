import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PermissaoService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache para evitar múltiplas leituras
  static final Map<String, Map<String, bool>> _cachePermissoes = {};
  static final Map<String, bool> _cacheAdmin = {}; // Cache para admin

  // Verifica se o usuário tem uma permissão específica
  Future<bool> temPermissao(String permissao) async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) return false;

      // 🔥 PRIMEIRO: Verifica se é admin (peso >= 90)
      if (_cacheAdmin.containsKey(user.uid)) {
        if (_cacheAdmin[user.uid] == true) return true;
      } else {
        final isAdmin = await _verificarAdmin(user.uid);
        _cacheAdmin[user.uid] = isAdmin;
        if (isAdmin) return true;
      }

      // 🔥 SEGUNDO: Verifica cache de permissões específicas
      if (_cachePermissoes.containsKey(user.uid) &&
          _cachePermissoes[user.uid]!.containsKey(permissao)) {
        return _cachePermissoes[user.uid]![permissao] ?? false;
      }

      // 🔥 TERCEIRO: Se não tem no cache, carrega TUDO de uma vez
      await _carregarTodasPermissoes(user.uid);

      // 🔥 QUARTO: Retorna do cache (agora deve ter)
      return _cachePermissoes[user.uid]?[permissao] ?? false;

    } catch (e) {
      print('❌ Erro ao verificar permissão: $e');
      return false;
    }
  }

  // 🔥 NOVO: Verifica se é admin pelo peso_permissao
  Future<bool> _verificarAdmin(String userId) async {
    try {
      final userDoc = await _firestore.collection('usuarios').doc(userId).get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() as Map<String, dynamic>;
      final pesoPermissao = userData['peso_permissao'] ?? 0;

      return pesoPermissao >= 90;
    } catch (e) {
      print('❌ Erro ao verificar admin: $e');
      return false;
    }
  }

  // 🔥 NOVO: Carrega TODAS as permissões de uma vez (otimizado)
  Future<void> _carregarTodasPermissoes(String userId) async {
    try {
      final permissoesDoc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (!permissoesDoc.exists) {
        _cachePermissoes[userId] = {};
        return;
      }

      final data = permissoesDoc.data() as Map<String, dynamic>;

      // Converte tudo para Map<String, bool>
      final permissoes = data.map((key, value) => MapEntry(
        key,
        value is bool ? value : false,
      ));

      _cachePermissoes[userId] = permissoes;

    } catch (e) {
      print('❌ Erro ao carregar permissões: $e');
      _cachePermissoes[userId] = {};
    }
  }

  // 🔥 NOVO: Força recarregar permissões (útil após editar)
  Future<void> recarregarPermissoes() async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    // Limpa cache
    _cachePermissoes.remove(user.uid);
    _cacheAdmin.remove(user.uid);

    // Carrega novamente
    await _carregarTodasPermissoes(user.uid);
    await _verificarAdmin(user.uid); // Já atualiza o cache admin
  }

  // Limpa cache (útil ao fazer logout)
  void limparCache() {
    _cachePermissoes.clear();
    _cacheAdmin.clear();
  }

  // Verifica múltiplas permissões de uma vez
  Future<Map<String, bool>> verificarMultiplasPermissoes(List<String> permissoes) async {
    final Map<String, bool> resultado = {};

    for (var permissao in permissoes) {
      resultado[permissao] = await temPermissao(permissao);
    }

    return resultado;
  }

  // 🔥 NOVO: Pega TODAS as permissões de uma vez (sem verificar uma por uma)
  Future<Map<String, bool>> getTodasPermissoes() async {
    final User? user = _auth.currentUser;
    if (user == null) return {};

    // Se já tem no cache, retorna
    if (_cachePermissoes.containsKey(user.uid)) {
      return _cachePermissoes[user.uid]!;
    }

    // Se não tem, carrega
    await _carregarTodasPermissoes(user.uid);
    return _cachePermissoes[user.uid] ?? {};
  }

  // Widget builder condicional baseado em permissão
  Widget buildIfPermissao({
    required BuildContext context,
    required String permissao,
    required Widget child,
    Widget? fallback,
  }) {
    return FutureBuilder<bool>(
      future: temPermissao(permissao),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.data == true) {
          return child;
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }

  // 🔥 NOVO: Versão que já recebe o mapa de permissões (evita FutureBuilder)
  Widget buildIfPermissaoFromMap({
    required Map<String, bool> permissoes,
    required String permissao,
    required Widget child,
    Widget? fallback,
  }) {
    if (permissoes[permissao] == true) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}