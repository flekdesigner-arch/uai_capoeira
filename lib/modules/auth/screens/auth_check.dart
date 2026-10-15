// lib/screens/auth/auth_check.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uai_capoeira/modules/auth/screens/login_screen.dart';
import 'package:uai_capoeira/app/portal_screen.dart';
import 'package:uai_capoeira/app/bootstrap/uai_native_bootstrap.dart' show MainScreen;
import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_dashboard_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/screens/escolher_aluno_vinculado_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_google_service.dart';
import 'package:uai_capoeira/modules/usuarios/services/user_service.dart';
import 'package:uai_capoeira/modules/minha_uai/screens/minha_uai_home_screen.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_identidade_service.dart';

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  Future<void> _criarDocumentoUsuarioSeNecessario(User user) async {
    final userRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      return;
    }

    // IMPORTANTE: Firebase Auth nao significa automaticamente usuario da gestao.
    // Antes de criar uma pendencia administrativa, verifica se a identidade
    // Google ja pertence exclusivamente a Area do Aluno.
    try {
      final alunos = await AreaAlunoGoogleService().buscarAlunosVinculados();
      if (alunos.isNotEmpty) {
        debugPrint(
          'Identidade vinculada a Area do Aluno. Perfil administrativo nao sera criado.',
        );
        return;
      }
    } catch (e) {
      // Uma falha temporaria na verificacao nao deve criar lixo administrativo.
      // Propaga o erro para permitir retry seguro em vez de assumir gestao.
      debugPrint('Erro ao verificar identidade da Area do Aluno: $e');
      rethrow;
    }

    debugPrint('Perfil do usuario nao existe. Preparando via Function.');

    await UserService.ensureInitialUserProfile(
      user,
      isGoogleLogin: user.providerData.any(
        (provider) => provider.providerId == 'google.com',
      ),
      origem: 'auth_check',
    );

    debugPrint('Perfil do usuario preparado com sucesso.');
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
              Icon(Icons.error_outline, size: 70, color: Colors.red.shade900),
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
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
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
              debugPrint(
                '❌ Erro ao preparar documento do usuário: ${createSnapshot.error}',
              );
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
                  debugPrint(
                    '❌ Erro ao carregar usuário no Firestore: ${userSnapshot.error}',
                  );
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
                  // Sem documento em /usuarios pode ser exatamente o caso correto:
                  // uma conta exclusiva da Area do Aluno.
                  return FutureBuilder<List<AlunoVinculadoGoogle>>(
                    future: AreaAlunoGoogleService().buscarAlunosVinculados(),
                    builder: (context, alunoSnapshot) {
                      if (alunoSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return _buildLoadingScreen('Abrindo Área do Aluno...');
                      }

                      if (alunoSnapshot.hasError) {
                        return _buildErrorScreen(
                          title: 'Erro ao identificar sua conta',
                          message:
                              'Não foi possível confirmar se esta conta pertence à Área do Aluno.',
                          onRetry: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const AuthCheck()),
                            );
                          },
                        );
                      }

                      final alunos = alunoSnapshot.data ?? const [];
                      if (alunos.length == 1) {
                        return FutureBuilder<Map<String, dynamic>?>(
                          future: AreaAlunoGoogleService()
                              .prepararAcessoAreaAluno(alunos.first),
                          builder: (context, acessoSnapshot) {
                            if (acessoSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return _buildLoadingScreen('Abrindo Área do Aluno...');
                            }
                            final acesso = acessoSnapshot.data;
                            if (acesso != null) {
                              return AreaAlunoDashboardScreen(
                                aluno: Map<String, dynamic>.from(
                                  acesso['aluno'] as Map,
                                ),
                                config: Map<String, dynamic>.from(
                                  acesso['config'] as Map,
                                ),
                                authPayload: Map<String, dynamic>.from(
                                  acesso['authPayload'] as Map,
                                ),
                              );
                            }
                            return _buildErrorScreen(
                              title: 'Não foi possível abrir a Área do Aluno',
                              message: 'Tente novamente em alguns instantes.',
                            );
                          },
                        );
                      }

                      if (alunos.length > 1) {
                        return EscolherAlunoVinculadoScreen(alunos: alunos);
                      }

                      return _buildErrorScreen(
                        title: 'Conta sem perfil de acesso',
                        message:
                            'Esta conta não possui perfil de gestão nem vínculo ativo com a Área do Aluno.',
                      );
                    },
                  );
                }

                final userData = userSnapshot.data!.data() ?? {};
                final statusConta = (userData['status_conta'] ?? 'pendente')
                    .toString();

                debugPrint('✅ Usuário: ${user.email} - Status: $statusConta');

                // A origem da identidade tem prioridade sobre o status legado.
                // Uma Conta UAI criada pela inscrição continua sendo Conta UAI
                // mesmo que a inscrição seja excluída depois.
                if (UsuarioIdentidadeService.ehContextoMinhaUai(userData)) {
                  return FutureBuilder<void>(
                    future: UsuarioIdentidadeService().reconciliarContaInscricao(
                      userId: user.uid,
                      data: userData,
                    ),
                    builder: (context, repairSnapshot) {
                      if (repairSnapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingScreen('Preparando sua Conta UAI...');
                      }
                      // Falha no auto-healing não deve bloquear uma rota que já
                      // sabemos ser da Minha UAI. A próxima abertura tenta de novo.
                      return const MinhaUaiHomeScreen();
                    },
                  );
                }

                if (statusConta == 'ativa') {
                  return const MainScreen();
                }

                return FutureBuilder<List<AlunoVinculadoGoogle>>(
                  future: AreaAlunoGoogleService().buscarAlunosVinculados(),
                  builder: (context, alunoSnapshot) {
                    if (alunoSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return _buildLoadingScreen(
                        'Verificando Área do Aluno...',
                      );
                    }

                    final alunos = alunoSnapshot.data ?? const [];

                    if (alunos.length == 1) {
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: AreaAlunoGoogleService()
                            .prepararAcessoAreaAluno(alunos.first),
                        builder: (context, acessoSnapshot) {
                          if (acessoSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return _buildLoadingScreen(
                              'Abrindo Área do Aluno...',
                            );
                          }

                          final acesso = acessoSnapshot.data;
                          if (acesso != null) {
                            return AreaAlunoDashboardScreen(
                              aluno: Map<String, dynamic>.from(
                                acesso['aluno'] as Map,
                              ),
                              config: Map<String, dynamic>.from(
                                acesso['config'] as Map,
                              ),
                              authPayload: Map<String, dynamic>.from(
                                acesso['authPayload'] as Map,
                              ),
                            );
                          }

                          return PortalScreen(
                            userId: user.uid,
                            userData: userData,
                            status: statusConta,
                          );
                        },
                      );
                    }

                    if (alunos.length > 1) {
                      return EscolherAlunoVinculadoScreen(alunos: alunos);
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
      },
    );
  }
}
