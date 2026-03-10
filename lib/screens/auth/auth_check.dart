// auth_check.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/portal_screen.dart';
import '../../main.dart';

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  User? _currentUser;
  String? _userStatus;
  bool _isNavigating = false;
  bool _isCreatingDocument = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // Reset error state on auth change
        if (_hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _hasError = false;
              _errorMessage = '';
            });
          });
        }

        // Handle auth loading state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen('Verificando autenticação...');
        }

        // Handle unauthenticated user
        if (!authSnapshot.hasData || authSnapshot.data == null) {
          _resetNavigationState();
          return const LoginScreen();
        }

        final user = authSnapshot.data!;

        // Update current user if changed
        if (_currentUser?.uid != user.uid) {
          _currentUser = user;
          _userStatus = null;
        }

        // Show loading if navigating or creating document
        if (_isNavigating) {
          return _buildLoadingScreen('Redirecionando...');
        }

        if (_isCreatingDocument) {
          return _buildLoadingScreen('Preparando sua conta...');
        }

        if (_hasError) {
          return _buildErrorScreen(context);
        }

        // If we already have the status, navigate directly
        if (_userStatus != null && !_isNavigating) {
          _navigateBasedOnStatus(user);
          return _buildLoadingScreen('Redirecionando...');
        }

        // Listen to Firestore document
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .snapshots(),
          builder: (context, firestoreSnapshot) {
            // Handle Firestore loading state
            if (firestoreSnapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingScreen('Carregando dados...');
            }

            // Handle Firestore error
            if (firestoreSnapshot.hasError) {
              print('❌ Erro no Firestore: ${firestoreSnapshot.error}');
              _handleFirestoreError(firestoreSnapshot.error);
              return _buildErrorScreen(context);
            }

            // Handle non-existent document
            if (!firestoreSnapshot.hasData || !firestoreSnapshot.data!.exists) {
              print('📝 Documento não existe para: ${user.uid}');

              if (!_isCreatingDocument) {
                _criarDocumentoUsuario(user);
              }

              return _buildLoadingScreen('Preparando sua conta...');
            }

            // ✅ Document exists
            final userData = firestoreSnapshot.data!.data() as Map<String, dynamic>;
            final statusConta = userData['status_conta'] ?? 'pendente';

            print('✅ Usuário: ${user.email} - Status: $statusConta');

            // Update status and navigate
            if (_userStatus != statusConta) {
              _userStatus = statusConta;
            }

            if (!_isNavigating) {
              _navigateBasedOnStatus(user, userData: userData);
            }

            return _buildLoadingScreen('Redirecionando...');
          },
        );
      },
    );
  }

  void _resetNavigationState() {
    if (_isNavigating || _isCreatingDocument) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isNavigating = false;
            _isCreatingDocument = false;
            _currentUser = null;
            _userStatus = null;
          });
        }
      });
    }
  }

  void _handleFirestoreError(Object? error) {
    if (!mounted) return;

    setState(() {
      _hasError = true;
      if (error is FirebaseException) {
        switch (error.code) {
          case 'permission-denied':
            _errorMessage = 'Sem permissão para acessar os dados';
            break;
          case 'unavailable':
            _errorMessage = 'Serviço temporariamente indisponível';
            break;
          default:
            _errorMessage = 'Erro ao carregar dados: ${error.message}';
        }
      } else {
        _errorMessage = 'Erro de conexão com o servidor';
      }
    });
  }

  void _navigateBasedOnStatus(User user, {Map<String, dynamic>? userData}) {
    if (_isNavigating || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isNavigating) return;

      setState(() => _isNavigating = true);

      try {
        if (_userStatus == 'ativa') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PortalScreen(
                userId: user.uid,
                userData: userData ?? {},
                status: _userStatus ?? 'pendente',
              ),
            ),
          );
        }
      } catch (e) {
        print('❌ Erro na navegação: $e');
        setState(() {
          _isNavigating = false;
          _hasError = true;
          _errorMessage = 'Erro ao redirecionar';
        });
      }
    });
  }

  Future<void> _criarDocumentoUsuario(User user) async {
    if (_isCreatingDocument) return;

    setState(() => _isCreatingDocument = true);

    try {
      print('📝 Criando documento para: ${user.email}');

      final userData = {
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
      };

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));

      print('✅ Documento criado com sucesso!');

    } catch (e) {
      print('❌ Erro ao criar documento: $e');

      if (mounted) {
        setState(() {
          _hasError = true;
          if (e is FirebaseException) {
            switch (e.code) {
              case 'permission-denied':
                _errorMessage = 'Sem permissão para criar conta';
                break;
              case 'unavailable':
                _errorMessage = 'Serviço indisponível';
                break;
              default:
                _errorMessage = 'Erro ao criar conta: ${e.message}';
            }
          } else {
            _errorMessage = 'Erro ao criar conta';
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Tentar novamente',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = '';
                  _isCreatingDocument = false;
                });
                _criarDocumentoUsuario(user);
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingDocument = false);
      }
    }
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage.isNotEmpty ? _errorMessage : 'Erro de conexão',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Não foi possível conectar ao servidor.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = '';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade800,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Tentar novamente'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Sair'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _resetNavigationState();
    super.dispose();
  }
}