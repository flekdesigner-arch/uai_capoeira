import 'package:flutter/material.dart';

/// Tipos de template usados pelo módulo de certificados.
///
/// A escolha principal vem do campo `certificado_ou_diploma` da coleção
/// `graduacoes`.
enum CertificadoTemplateTipo {
  certificadoSemCpf,
  certificadoComCpf,
  diploma,
}

extension CertificadoTemplateTipoX on CertificadoTemplateTipo {
  String get codigo {
    switch (this) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return 'CERTIFICADO';
      case CertificadoTemplateTipo.certificadoComCpf:
        return 'CERTIFICADOCOMCPF';
      case CertificadoTemplateTipo.diploma:
        return 'DIPLOMA';
    }
  }

  String get nome {
    switch (this) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return 'Certificado simples';
      case CertificadoTemplateTipo.certificadoComCpf:
        return 'Certificado com CPF';
      case CertificadoTemplateTipo.diploma:
        return 'Diploma';
    }
  }

  String get subtitulo {
    switch (this) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return 'Modelo para graduações comuns, sem CPF no texto.';
      case CertificadoTemplateTipo.certificadoComCpf:
        return 'Modelo para instrutor/formação, com CPF no certificado.';
      case CertificadoTemplateTipo.diploma:
        return 'Modelo especial para professor e formações superiores.';
    }
  }

  IconData get icon {
    switch (this) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return Icons.workspace_premium_rounded;
      case CertificadoTemplateTipo.certificadoComCpf:
        return Icons.badge_rounded;
      case CertificadoTemplateTipo.diploma:
        return Icons.history_edu_rounded;
    }
  }

  bool get exigeCpf {
    switch (this) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return false;
      case CertificadoTemplateTipo.certificadoComCpf:
      case CertificadoTemplateTipo.diploma:
        return true;
    }
  }

  static CertificadoTemplateTipo fromCodigo(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();

    switch (normalized) {
      case 'CERTIFICADOCOMCPF':
      case 'CERTIFICADO_COM_CPF':
      case 'COMCPF':
        return CertificadoTemplateTipo.certificadoComCpf;
      case 'DIPLOMA':
        return CertificadoTemplateTipo.diploma;
      case 'CERTIFICADO':
      case 'CERTIFICADOSEMCPF':
      case 'CERTIFICADO_SEM_CPF':
      default:
        return CertificadoTemplateTipo.certificadoSemCpf;
    }
  }
}
