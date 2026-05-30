import 'package:uai_capoeira/modules/certificados/models/certificado_template_tipo.dart';

/// Caminhos dos SVGs dentro de assets/certificados.
///
/// Os arquivos LIMPOS são os usados para gerar o certificado final.
/// Os arquivos GUIA servem só como referência/extração das posições dos textos.
class CertificadoTemplateAssets {
  const CertificadoTemplateAssets._();

  static const String basePath = 'assets/certificados';

  static const String certificadoSemCpf =
      '$basePath/certificado_sem_cpf_limpo_funcional.svg';

  static const String certificadoSemCpfGuia =
      '$basePath/certificado_sem_cpf_guia_limpo_funcional.svg';

  static const String certificadoComCpf =
      '$basePath/certificado_com_cpf_limpo_funcional.svg';

  static const String certificadoComCpfGuia =
      '$basePath/certificado_com_cpf_guia_limpo_funcional.svg';

  static const String diploma = '$basePath/diploma.svg';

  static const String diplomaGuia = '$basePath/diploma_guia.svg';

  static String templatePath(CertificadoTemplateTipo tipo) {
    switch (tipo) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return certificadoSemCpf;
      case CertificadoTemplateTipo.certificadoComCpf:
        return certificadoComCpf;
      case CertificadoTemplateTipo.diploma:
        return diploma;
    }
  }

  static String guiaPath(CertificadoTemplateTipo tipo) {
    switch (tipo) {
      case CertificadoTemplateTipo.certificadoSemCpf:
        return certificadoSemCpfGuia;
      case CertificadoTemplateTipo.certificadoComCpf:
        return certificadoComCpfGuia;
      case CertificadoTemplateTipo.diploma:
        return diplomaGuia;
    }
  }

  static const List<CertificadoTemplateTipo> tiposDisponiveis = [
    CertificadoTemplateTipo.certificadoSemCpf,
    CertificadoTemplateTipo.certificadoComCpf,
    CertificadoTemplateTipo.diploma,
  ];
}
