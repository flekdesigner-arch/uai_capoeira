// lib/screens/auth/splash_auth_screen.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/modules/auth/screens/auth_check.dart';

class SplashAuthScreen extends StatefulWidget {
  const SplashAuthScreen({super.key});

  @override
  State<SplashAuthScreen> createState() => _SplashAuthScreenState();
}

class _SplashAuthScreenState extends State<SplashAuthScreen>
    with SingleTickerProviderStateMixin {
  bool _mostrarAuthCheck = false;
  String _mensagem = 'Iniciando app...';

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _iniciarFluxo();
  }

  Future<void> _iniciarFluxo() async {
    try {
      if (mounted) {
        setState(() {
          _mensagem = 'Restaurando sessão...';
        });
      }

      // Primeiro tenta ler o usuário atual imediatamente.
      // Em muitos aparelhos o Firebase já restaura a sessão antes mesmo
      // do primeiro evento do stream chegar.
      User? user = FirebaseAuth.instance.currentUser;

      // Se ainda veio nulo, aguarda o Firebase Auth responder.
      // O timeout evita o app ficar preso no splash caso o stream demore.
      if (user == null) {
        try {
          user = await FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 3));
        } on TimeoutException {
          debugPrint('⚠️ SplashAuthScreen: timeout aguardando FirebaseAuth.');
          user = FirebaseAuth.instance.currentUser;
        }
      }

      // Pequena espera visual para não piscar entre splash e AuthCheck.
      await Future.delayed(const Duration(milliseconds: 700));

      if (user != null) {
        debugPrint('✅ SplashAuthScreen: sessão detectada para ${user.email}');
      } else {
        debugPrint('ℹ️ SplashAuthScreen: nenhum usuário logado detectado.');
      }

      if (!mounted) return;

      setState(() {
        _mensagem = 'Carregando dados...';
      });

      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('❌ Erro no SplashAuthScreen: $e');
    }

    if (!mounted) return;

    setState(() {
      _mostrarAuthCheck = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLogoComLoading() {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _controller,
            child: SizedBox(
              width: 142,
              height: 142,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade900),
                backgroundColor: Colors.red.shade900.withOpacity(0.08),
              ),
            ),
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(15),
            child: Image.asset(
              'assets/logoprincipal.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.sports_martial_arts,
                  size: 54,
                  color: Colors.red.shade900,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_mostrarAuthCheck) {
      return const AuthCheck();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogoComLoading(),
                const SizedBox(height: 28),
                Text(
                  _mensagem,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
