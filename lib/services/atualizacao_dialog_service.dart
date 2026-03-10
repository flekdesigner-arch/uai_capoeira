// services/atualizacao_dialog_service.dart
import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/atualizacao_direta_service.dart';
import 'package:uai_capoeira/services/versao_service.dart';

class AtualizacaoDialogService {
  static final AtualizacaoDialogService _instance = AtualizacaoDialogService._internal();
  factory AtualizacaoDialogService() => _instance;
  AtualizacaoDialogService._internal();

  final VersaoService _versaoService = VersaoService();
  final AtualizacaoDiretaService _atualizacaoService = AtualizacaoDiretaService();

  bool _dialogoJaMostrado = false;

  // 🔥 VERIFICAR E MOSTRAR DIÁLOGO
  Future<void> verificarEMostrarDialogo(BuildContext context) async {
    // Evita mostrar múltiplas vezes
    if (_dialogoJaMostrado) return;

    try {
      // 1️⃣ PEGAR VERSÕES
      final versaoLocal = await _versaoService.getVersaoLocal();
      final versaoFirebase = await _versaoService.getVersaoFirebase();

      // 2️⃣ VERIFICAR SE APK EXISTE
      final apkExiste = await _atualizacaoService.apkExiste(versaoFirebase);

      // 3️⃣ COMPARAR VERSÕES
      final precisaAtualizar = _compararVersoes(versaoLocal, versaoFirebase);

      // 4️⃣ SE TUDO OK, MOSTRAR DIÁLOGO
      if (precisaAtualizar && apkExiste && context.mounted) {
        _dialogoJaMostrado = true;
        _mostrarDialogoAtualizacao(context, versaoLocal, versaoFirebase);
      }
    } catch (e) {
      debugPrint('❌ Erro ao verificar atualização: $e');
    }
  }

  // 🔍 COMPARAR VERSÕES
  bool _compararVersoes(String local, String firebase) {
    try {
      final localParts = local.split('.').map(int.parse).toList();
      final firebaseParts = firebase.split('.').map(int.parse).toList();

      for (int i = 0; i < firebaseParts.length; i++) {
        if (i >= localParts.length) return true;
        if (firebaseParts[i] > localParts[i]) return true;
        if (firebaseParts[i] < localParts[i]) return false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao comparar versões: $e');
      return false;
    }
  }

  // 🎨 MOSTRAR DIÁLOGO LINDO
  void _mostrarDialogoAtualizacao(
      BuildContext context,
      String versaoAtual,
      String novaVersao
      ) {
    showDialog(
      context: context,
      barrierDismissible: false, // Não pode fechar clicando fora
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 8,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.red.shade900,
                Colors.red.shade700,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🎉 ÍCONE DE NOVIDADE
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_alt,
                  size: 60,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              // 📢 TÍTULO
              const Text(
                '🚀 NOVA VERSÃO DISPONÍVEL!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ℹ️ INFORMAÇÕES DA VERSÃO
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        Text(
                          'ATUAL',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            versaoAtual,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    Column(
                      children: [
                        Text(
                          'NOVA',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade600,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            novaVersao,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ✨ BENEFÍCIOS
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildBeneficioItem(
                      Icons.speed,
                      'Desempenho otimizado',
                    ),
                    const SizedBox(height: 8),
                    _buildBeneficioItem(
                      Icons.bug_report,
                      'Correções e melhorias',
                    ),
                    const SizedBox(height: 8),
                    _buildBeneficioItem(
                      Icons.security,
                      'Segurança atualizada',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 🎯 BOTÕES
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context); // Fecha o diálogo
                        _dialogoJaMostrado = false; // Permite mostrar de novo
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'AGORA NÃO',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Fecha o diálogo
                        _iniciarAtualizacao(context, novaVersao);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ATUALIZAR',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ⏱️ LEMBRETE
              Text(
                'Recomendamos atualizar para ter a melhor experiência',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎨 ITEM DE BENEFÍCIO
  Widget _buildBeneficioItem(IconData icon, String texto) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.amber.shade300,
        ),
        const SizedBox(width: 12),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // 📥 INICIAR ATUALIZAÇÃO
  void _iniciarAtualizacao(BuildContext context, String versao) {
    _atualizacaoService.baixarEInstalarComFeedback(context, versao);
  }

  // 🔄 RESETAR FLAG (se precisar)
  void resetarDialogoJaMostrado() {
    _dialogoJaMostrado = false;
  }
}