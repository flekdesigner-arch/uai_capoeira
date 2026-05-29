// lib/screens/auth/auth_check.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/modules/auth/screens/login_screen.dart';
import 'package:uai_capoeira/app/portal_screen.dart';
import 'package:uai_capoeira/main.dart';

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  // ═══════════════════════════════════════════════════════════
  // CRIA DOCUMENTO DO USUÁRIO SE ELE AINDA NÃO EXISTIR
  // ═══════════════════════════════════════════════════════════
  Future<void> _criarDocumentoUsuarioSeNecessario(User user) async {
    final userRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      return;
    }

    debugPrint('📝 Documento do usuário não existe. Criando para: ${user.email}');

    await userRef.set({
      'uid': user.uid,
      'nome_completo': user.displayName ?? 'Usuário Google',
      'email': user.email,
      'contato': '',
      'foto_url': user.photoURL ?? '',
      'status_conta': 'pendente',
      'peso_permissao': 0,
      'tipo': 'pendente',
      'aprovado_por': '',
      'aprovado_por_nome': '',
      'aprovado_em': null,
      'data_cadastro': FieldValue.serverTimestamp(),
      'ultima_atualizacao': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('✅ Documento do usuário criado com sucesso.');
  }

  // ═══════════════════════════════════════════════════════════
  // TELA DE CARREGAMENTO COM LOGO
  // ═══════════════════════════════════════════════════════════
  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logoprincipal.png',
                width: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.sports_martial_arts,
                    size: 90,
                    color: Colors.red.shade900,
                  );
                },
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TELA DE ERRO
  // ═══════════════════════════════════════════════════════════
  Widget _buildErrorScreen({
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 70,
                color: Colors.red.shade900,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 26),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sair'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DESCOBRE A MENSAGEM DE ERRO DO FIRESTORE
  // ═══════════════════════════════════════════════════════════
  String _mensagemErroFirestore(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Sem permissão para acessar os dados do usuário.';
        case 'unavailable':
          return 'Servidor temporariamente indisponível. Verifique sua internet e tente novamente.';
        default:
          return error.message ?? 'Erro ao carregar dados do usuário.';
      }
    }

    return 'Não foi possível conectar ao servidor.';
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // idTokenChanges costuma ser mais confiável para restauração de sessão
      // e mudanças internas do Firebase Auth.
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, authSnapshot) {
        debugPrint('🔐 AuthCheck estado: ${authSnapshot.connectionState}');

        // Enquanto o Firebase restaura a sessão salva no APK,
        // mantém uma tela de carregamento em vez de jogar para login.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen('Verificando login salvo...');
        }

        if (authSnapshot.hasError) {
          debugPrint('❌ Erro no FirebaseAuth: ${authSnapshot.error}');
          return _buildErrorScreen(
            title: 'Erro na autenticação',
            message: 'Não foi possível verificar seu login. Tente novamente.',
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          debugPrint('🔐 Nenhum usuário logado. Indo para LoginScreen.');
          return const LoginScreen();
        }

        debugPrint('🔐 Usuário logado detectado: ${user.email}');

        return FutureBuilder<void>(
          future: _criarDocumentoUsuarioSeNecessario(user),
          builder: (context, createSnapshot) {
            if (createSnapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingScreen('Preparando sua conta...');
            }

            if (createSnapshot.hasError) {
              debugPrint('❌ Erro ao preparar documento do usuário: ${createSnapshot.error}');
              return _buildErrorScreen(
                title: 'Erro ao preparar conta',
                message: 'Não foi possível preparar seus dados de acesso.',
                onRetry: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthCheck()),
                  );
                },
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingScreen('Carregando seus dados...');
                }

                if (userSnapshot.hasError) {
                  debugPrint('❌ Erro ao carregar usuário no Firestore: ${userSnapshot.error}');
                  return _buildErrorScreen(
                    title: 'Erro ao carregar dados',
                    message: _mensagemErroFirestore(userSnapshot.error),
                    onRetry: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthCheck()),
                      );
                    },
                  );
                }

                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  debugPrint('⚠️ Documento ainda não apareceu no Firestore.');
                  return _buildLoadingScreen('Finalizando configuração...');
                }

                final userData = userSnapshot.data!.data() ?? {};
                final statusConta = (userData['status_conta'] ?? 'pendente').toString();

                debugPrint('✅ Usuário: ${user.email} - Status: $statusConta');

                if (statusConta == 'ativa') {
                  return const MainScreen();
                }

                return PortalScreen(
                  userId: user.uid,
                  userData: userData,
                  status: statusConta,
                );
              },
            );
          },
        );
      },
    );
  }
}

