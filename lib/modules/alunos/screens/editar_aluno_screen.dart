import 'dart:developer' as developer;
import 'dart:async';
import 'dart:convert';
import 'package:uai_capoeira/modules/inscricoes/services/ficha_callable_client.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 👈 ADICIONAR
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/session_log/session_log_service.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uai_capoeira/modules/alunos/photo_studio/photo_editor_state.dart';
import 'package:uai_capoeira/modules/alunos/photo_studio/photo_studio_screen.dart';
import 'package:uai_capoeira/modules/alunos/photo_capture/guided_camera_screen.dart';
import 'package:uai_capoeira/modules/alunos/photo_history/aluno_photo_history_service.dart';
import 'package:uai_capoeira/modules/chamadas/services/aluno_foto_resolver.dart';
import 'package:uai_capoeira/core/image_cache/uai_student_photo_cache.dart';
import 'package:uai_capoeira/modules/inscricoes/ficha/ficha_complementar_fields.dart';

bool get _isWindowsPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

// 🔐 IMPORTAR SERVIÇO DE PERMISSÕES

String _mensagemErroAmigavelEditarAluno(
  Object erro, {
  String contexto = 'ação',
}) {
  if (erro is FirebaseException) {
    if (erro.code == 'permission-denied') {
      return 'Você não tem permissão para realizar esta ação.';
    }
    if (erro.code == 'unavailable' || erro.code == 'deadline-exceeded') {
      return 'Não foi possível comunicar com o Firebase agora. Verifique sua conexão.';
    }
  }
  return 'Não foi possível concluir esta $contexto. Tente novamente.';
}

class PermissaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final PermissaoService _instance = PermissaoService._internal();
  factory PermissaoService() => _instance;
  PermissaoService._internal();

  final Map<String, Map<String, bool>> _cache = {};

  Future<Map<String, bool>> carregarPermissoes(String userId) async {
    if (_cache.containsKey(userId)) {
      return _cache[userId]!;
    }

    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (doc.exists) {
        final permissoes =
            doc.data()?.map(
              (key, value) => MapEntry(key, value as bool? ?? false),
            ) ??
            {};
        _cache[userId] = permissoes;
        return permissoes;
      }
    } catch (e) {
      developer.log('Erro ao carregar permissões: $e');
    }
    return {};
  }

  Future<bool> temPermissao(String userId, String permissao) async {
    final permissoes = await carregarPermissoes(userId);
    return permissoes[permissao] ?? false;
  }

  Future<bool> isAdmin(String userId) async {
    try {
      final doc = await _firestore.collection('usuarios').doc(userId).get();

      if (doc.exists) {
        final peso = doc.data()?['peso_permissao'] as int? ?? 0;
        return peso >= 90;
      }
    } catch (e) {
      developer.log('Erro ao verificar admin: $e');
    }
    return false;
  }

  Future<int> obterPesoPermissao(String userId) async {
    final doc = await _firestore.collection('usuarios').doc(userId).get();
    final peso = doc.data()?['peso_permissao'];
    return peso is num ? peso.toInt() : 0;
  }

  void limparCache(String userId) {
    _cache.remove(userId);
  }
}

class _PhotoSaveProgressState {
  final String title;
  final String message;
  final double progress;

  const _PhotoSaveProgressState({
    required this.title,
    required this.message,
    required this.progress,
  });
}

class EditarAlunoScreen extends StatefulWidget {
  final String? alunoId;
  final String? academiaIdInicial;
  final String? academiaNomeInicial;
  final String? turmaIdInicial;
  final String? turmaNomeInicial;
  final Map<String, dynamic>? dadosInscricao;
  /// Revisão guiada anterior à reativação. Não altera status nem turma.
  final bool modoReativacao;
  final String? turmaReativacaoNome;

  const EditarAlunoScreen({
    super.key,
    this.alunoId,
    this.academiaIdInicial,
    this.academiaNomeInicial,
    this.turmaIdInicial,
    this.turmaNomeInicial,
    this.dadosInscricao,
    this.modoReativacao = false,
    this.turmaReativacaoNome,
  });

  @override
  State<EditarAlunoScreen> createState() => _EditarAlunoScreenState();
}

class _EditarAlunoScreenState extends State<EditarAlunoScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }



  // Resumo somente de leitura: não interfere na edição nem na vinculação.
  String _cadastroDataExibicao = '';
  String _ultimaAtualizacaoDataExibicao = '';
  String _ultimaAtualizacaoAutorExibicao = '';
  bool _exibindoAutorCadastro = false;

  String _formatarDataHistorica(dynamic valor) {
    DateTime? data;
    if (valor is Timestamp) {
      data = valor.toDate();
    } else if (valor is DateTime) {
      data = valor;
    } else if (valor is String && valor.trim().isNotEmpty) {
      data = DateTime.tryParse(valor.trim());
    }
    if (data == null || data.year < 1900) return '';
    return DateFormat('dd/MM/yyyy • HH:mm').format(data);
  }

  void _carregarResumoCadastro(Map<String, dynamic> dados) {
    // Documentos legados usam data_do_cadastro; os recentes, criado_em.
    // Não inferir a data de cadastro a partir da última atualização.
    final cadastro = dados['cadastro_realizado_em'] ??
        dados['data_do_cadastro'] ?? dados['criado_em'];
    final atualizacao = dados['ultima_edicao_em'] ?? dados['atualizado_em'];
    _cadastroDataExibicao = _formatarDataHistorica(cadastro);
    _ultimaAtualizacaoDataExibicao = _formatarDataHistorica(atualizacao);
    String primeiroPreenchido(List<dynamic> valores) {
      for (final valor in valores) {
        final texto = valor?.toString().trim() ?? '';
        if (texto.isNotEmpty) return texto;
      }
      return '';
    }

    // O responsável pelo cadastro não deve ser confundido com o último editor.
    final ultimoEditor = primeiroPreenchido([
      dados['ultima_edicao_por_nome'],
      dados['ultima_edicao_por_email'],
      dados['atualizado_por'],
    ]);
    final autorCadastro = primeiroPreenchido([
      dados['cadastro_realizado_por_nome'],
      dados['cadastro_realizado_por'],
      dados['cadastro_realizado_por_email'],
      dados['criado_por_nome'],
      dados['criado_por_email'],
    ]);
    _exibindoAutorCadastro = ultimoEditor.isEmpty && autorCadastro.isNotEmpty;
    _ultimaAtualizacaoAutorExibicao = ultimoEditor.isNotEmpty
        ? ultimoEditor
        : autorCadastro;
  }

  Widget _buildResumoCadastro() {
    Widget dado(String rotulo, String valor, IconData icone) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: context.uai.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: TextStyle(
                    fontSize: 11, color: context.uai.textSecondary)),
                const SizedBox(height: 2),
                Text(valor.isEmpty ? ' ' : valor,
                    style: TextStyle(fontSize: 13,
                        color: context.uai.textPrimary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.uai.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded,
                color: context.uai.primary, size: 19),
            const SizedBox(width: 8),
            Text('Sobre o cadastro', style: TextStyle(
                color: context.uai.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: dado('Data do cadastro', _cadastroDataExibicao,
                    Icons.event_available_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: dado('Última atualização', _ultimaAtualizacaoDataExibicao,
                    Icons.update_rounded),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 16, color: context.uai.textMuted),
                const SizedBox(height: 3),
                Text(
                  _exibindoAutorCadastro ? 'Responsável pelo cadastro' : 'Atualizado por',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11,
                      color: context.uai.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  _ultimaAtualizacaoAutorExibicao.isEmpty
                      ? ' '
                      : _ultimaAtualizacaoAutorExibicao,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13,
                      color: context.uai.textPrimary,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Apenas uma secao do formulario pode permanecer aberta por vez.
  String? _secaoAbertaId;
  static const _secoesReativacao = <String>[
    'foto', 'pessoais', 'contato', 'endereco', 'saude',
  ];
  final Set<String> _secoesConferidas = <String>{};
  final ScrollController _reativacaoScroll = ScrollController();
  bool? _atualizarFotoNaReativacao;
  bool _exibirResumoReativacao = false;


  void _invalidarRevisao(String secao) {
    if (widget.modoReativacao && _secoesConferidas.contains(secao) && mounted) {
      setState(() => _secoesConferidas.remove(secao));
    }
  }

  static const _perguntasReativacao = <String, String>{
    'foto': 'A foto do cadastro precisa ser atualizada?',
    'pessoais': 'Confirme nome, apelido, data de nascimento e sexo com o aluno.',
    'contato': 'Os telefones, o responsável e os contatos de emergência continuam corretos?',
    'endereco': 'O aluno mudou de residência? Confira rua, número, bairro e cidade.',
    'saude': 'Houve mudança nos cuidados ou restrições? Confirme também a ciência da ficha.',
  };

  int get _indiceEtapaReativacao {
    final indice = _secoesReativacao.indexOf(_secaoAbertaId ?? '');
    return indice < 0 ? 0 : indice;
  }

  String? _erroEtapaReativacao(String etapa) {
    bool vazio(String campo) => _controllers[campo]!.text.trim().isEmpty;
    switch (etapa) {
      case 'foto':
        if (_atualizarFotoNaReativacao == null) {
          return 'Responda se a foto do aluno precisa ser atualizada.';
        }
        if (_atualizarFotoNaReativacao == true && _pickedImage == null) {
          return 'Selecione ou prepare uma nova foto antes de continuar.';
        }
        if (_atualizarFotoNaReativacao == false &&
            (_networkImageUrl == null || _networkImageUrl!.trim().isEmpty)) {
          return 'Este aluno ainda não tem foto. Adicione uma para continuar.';
        }
        break;
      case 'pessoais':
        for (final campo in ['nome', 'apelido', 'data_nascimento']) {
          if (vazio(campo)) return 'Preencha ${campo == 'nome' ? 'o nome' : campo == 'apelido' ? 'o apelido' : 'a data de nascimento'}.';
        }
        if (_sexo == null || _sexo!.trim().isEmpty) return 'Selecione o sexo do aluno.';
        if (_parseDate(_controllers['data_nascimento']!.text.trim()) == null) {
          return 'Informe uma data de nascimento válida.';
        }
        final cpf = _controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (cpf.isNotEmpty && cpf.length != 11) return 'O CPF pode ficar vazio, mas, se informado, precisa ter 11 dígitos.';
        break;
      case 'contato':
        for (final campo in ['contato_aluno', 'nome_responsavel', 'contato_responsavel', 'grau_emergencia']) {
          if (vazio(campo)) return 'Preencha ${campo.replaceAll('_', ' ')}.';
        }
        for (final campo in ['contato_aluno', 'contato_responsavel']) {
          final numero = _controllers[campo]!.text.replaceAll(RegExp(r'[^0-9]'), '');
          if (numero.length < 10 || numero.length > 13) return 'Confira o telefone em ${campo.replaceAll('_', ' ')}.';
        }
        for (final contato in _contatosEmergenciaAdicionais) {
          if (['nome', 'telefone', 'grau'].any((campo) => (contato[campo]?.toString().trim() ?? '').isEmpty)) {
            return 'Complete nome, telefone e parentesco dos contatos adicionais.';
          }
        }
        break;
      case 'endereco':
        for (final campo in ['rua', 'numero', 'bairro', 'cidade']) {
          if (vazio(campo)) return 'Preencha ${campo == 'numero' ? 'o número' : campo == 'bairro' ? 'o bairro' : campo == 'cidade' ? 'a cidade' : 'a rua'} do endereço.';
        }
        if (_enderecoLegadoAmbiguo && !_enderecoRevisaoConfirmada) {
          return 'Confira o endereço antigo antes de avançar.';
        }
        break;
      case 'saude':
        if (!_fichaRestritaCarregada) return 'A ficha protegida ainda não foi carregada.';
        final erros = validarFichaUai(_fichaComplementar, secao: 'saude');
        if (erros.isNotEmpty) return erros.first;
        break;
      case 'capoeira_ficha':
        if (!_fichaRestritaCarregada) return 'A ficha protegida ainda não foi carregada.';
        final erros = validarFichaUai(_fichaComplementar, secao: 'capoeira');
        if (erros.isNotEmpty) return erros.first;
        break;
      case 'capoeira_dados':
        // Graduação "Sem graduação" é uma opção legítima do cadastro.
        // Dados de graduação já existentes podem ser protegidos por permissão.
        for (final campo in [if (_graduacaoId != null) 'data_graduacao_atual', 'tempo_capoeira']) {
          if (vazio(campo)) return 'Confira e preencha ${campo == 'tempo_capoeira' ? 'o início na capoeira' : 'a data da graduação'}.';
          if (_parseDate(_controllers[campo]!.text.trim()) == null) return 'Confira a data em ${campo.replaceAll('_', ' ')}.';
        }
        break;
    }
    return null;
  }

  void _navegarRevisao(int indice) {
    if (!mounted) return;
    setState(() {
      _exibirResumoReativacao = false;
      _secaoAbertaId = _secoesReativacao[indice.clamp(0, _secoesReativacao.length - 1)];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reativacaoScroll.hasClients) {
        _reativacaoScroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      }
    });
  }

  void _conferirEAvancar(String id) {
    // A confirmação de ciência da ficha é implícita no avanço da etapa
    // de saúde, sem checkbox adicional durante a reativação.
    if (id == 'saude' && widget.modoReativacao) {
      final saude = Map<String, dynamic>.from(
        _fichaComplementar['saude'] is Map
            ? _fichaComplementar['saude'] as Map
            : const <String, dynamic>{},
      );
      if (saude['resposta'] != null && saude['ciente'] != true) {
        setState(() {
          _fichaComplementar = {
            ..._fichaComplementar,
            'saude': {...saude, 'ciente': true},
          };
        });
      }
    }
    // Na reativação, o próprio avanço confirma o endereço legado já conferido.
    // A edição normal continua exigindo a confirmação manual original.
    if (id == 'endereco' && widget.modoReativacao && _enderecoLegadoAmbiguo) {
      final completos = ['rua', 'numero', 'bairro', 'cidade'].every(
        (campo) => _controllers[campo]!.text.trim().isNotEmpty,
      );
      if (completos) {
        setState(() => _enderecoRevisadoAssinatura = _assinaturaEnderecoAtual);
      }
    }
    final erro = _erroEtapaReativacao(id);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    setState(() => _secoesConferidas.add(id));
    final proximo = _secoesReativacao.indexOf(id) + 1;
    if (proximo < _secoesReativacao.length) {
      _navegarRevisao(proximo);
    } else {
      setState(() => _exibirResumoReativacao = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reativacaoScroll.hasClients) {
          _reativacaoScroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  Widget _buildEtapaFotoReativacao() {
    if (!widget.modoReativacao || _secaoAbertaId != 'foto') {
      return const SizedBox.shrink();
    }
    final t = context.uai;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('A foto do cadastro precisa ser atualizada?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: t.textPrimary)),
        const SizedBox(height: 6),
        Text('Confira se a foto ainda representa o aluno e se o rosto está bem visível.',
          style: TextStyle(color: t.textSecondary)),
        const SizedBox(height: 14),
        _buildFotoAlunoHeader(),
        const SizedBox(height: 12),
        RadioGroup<bool>(
          groupValue: _atualizarFotoNaReativacao,
          onChanged: (value) {
            if (_salvandoAluno) return;
            setState(() {
              _atualizarFotoNaReativacao = value;
              _secoesConferidas.remove('foto');
            });
          },
          child: const Column(
            children: [
              RadioListTile<bool>(
                title: Text('Não, a foto atual está boa'),
                value: false,
              ),
              RadioListTile<bool>(
                title: Text('Sim, precisamos atualizar a foto'),
                value: true,
              ),
            ],
          ),
        ),
        if (_atualizarFotoNaReativacao == true) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _salvandoAluno ? null : _showImageSourceActionSheet,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_pickedImage == null ? 'Selecionar nova foto' : 'Trocar foto selecionada'),
          ),
          if (_pickedImage != null)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text('Nova foto preparada. Será salva apenas ao concluir a revisão.',
                style: TextStyle(color: t.success))),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _salvandoAluno ? null : () => _conferirEAvancar('foto'),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Conferir e continuar'),
        ),
      ]),
    );
  }

  Widget _buildCabecalhoReativacao() {
    final t = context.uai;
    final nome = _controllers['nome']!.text.trim();
    final imageProvider = _pickedImageBytesPreview != null
        ? MemoryImage(_pickedImageBytesPreview!) as ImageProvider
        : (_networkImageUrl?.trim().isNotEmpty == true
            ? CachedNetworkImageProvider(_networkImageUrl!) as ImageProvider
            : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border)),
        child: Row(children: [
          CircleAvatar(radius: 27, backgroundColor: t.cardAlt,
            backgroundImage: imageProvider,
            child: imageProvider == null ? const Icon(Icons.person_outline_rounded) : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nome.isEmpty ? 'Aluno' : nome,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900, color: t.textPrimary)),
            Text('Turma: ${widget.turmaReativacaoNome ?? _turmaNome ?? "Selecionada"}',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
            Text('Inativo • revisão em andamento',
              style: TextStyle(fontSize: 11, color: t.primary, fontWeight: FontWeight.w700)),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(_exibirResumoReativacao ? 'Conferência concluída' : 'Etapa ${_indiceEtapaReativacao + 1} de ${_secoesReativacao.length}',
          style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary))),
        Text('${_secoesConferidas.length} conferidas',
          style: TextStyle(fontSize: 12, color: t.textSecondary)),
      ]),
      const SizedBox(height: 8),
      Row(children: [for (final item in _secoesReativacao) ...[
        Expanded(child: Container(height: 5,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
            color: _secoesConferidas.contains(item) || item == _secaoAbertaId
                ? t.primary : t.border))),
        if (item != _secoesReativacao.last) const SizedBox(width: 4),
      ]]),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildRevisaoSecao(String id, String titulo, List<Widget> campos) {
    if (!widget.modoReativacao) return _buildSecaoCompacta(id, titulo, campos);
    // Experiência em outro grupo e graduação não fazem parte da reativação.
    if (!_secoesReativacao.contains(id)) return const SizedBox.shrink();
    final indice = _secoesReativacao.indexOf(id);
    final conferida = _secoesConferidas.contains(id);
    final atual = _indiceEtapaReativacao == indice;
    if (!atual || _exibirResumoReativacao) return const SizedBox.shrink();
    return _buildSecaoCompacta(id, titulo, [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(_perguntasReativacao[id] ?? 'Confira as informações.',
          style: TextStyle(fontWeight: FontWeight.w700, color: context.uai.textSecondary)),
      ),
      ...campos,
      if (conferida) Row(children: [
        Icon(Icons.check_circle_rounded, color: context.uai.success),
        const SizedBox(width: 8),
        const Expanded(child: Text('Etapa conferida. Se alterar algum dado, confira novamente.')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        if (indice > 0) ...[
          Expanded(child: OutlinedButton.icon(
            onPressed: _salvandoAluno ? null : () => _navegarRevisao(indice - 1),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Anterior'),
          )),
          const SizedBox(width: 10),
        ],
        Expanded(flex: 2, child: FilledButton.icon(
          onPressed: _salvandoAluno ? null : () => _conferirEAvancar(id),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Conferir e continuar'),
        )),
      ]),
    ]);
  }


  Widget _buildResumoFinalReativacao() {
    if (!widget.modoReativacao || !_exibirResumoReativacao) {
      return const SizedBox.shrink();
    }
    final t = context.uai;
    const itens = <(String, String, IconData)>[
      ('foto', 'Foto conferida', Icons.photo_camera_outlined),
      ('pessoais', 'Dados pessoais', Icons.person_outline_rounded),
      ('contato', 'Contatos', Icons.phone_outlined),
      ('endereco', 'Endereço', Icons.place_outlined),
      ('saude', 'Ficha de saúde', Icons.favorite_border_rounded),
    ];
    final todasConferidas = _secoesReativacao.every(_secoesConferidas.contains);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.verified_outlined, color: t.success),
          const SizedBox(width: 8),
          Expanded(child: Text('Resumo da conferência',
            style: TextStyle(fontWeight: FontWeight.w800,
              fontSize: 16, color: t.textPrimary))),
        ]),
        const SizedBox(height: 6),
        Text('Confira as etapas revisadas antes de reativar o aluno.',
          style: TextStyle(fontSize: 12, color: t.textSecondary)),
        const SizedBox(height: 12),
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(item.$3, size: 17, color: t.textSecondary),
              const SizedBox(width: 9),
              Expanded(child: Text(item.$2,
                style: TextStyle(color: t.textPrimary, fontSize: 13))),
              Icon(_secoesConferidas.contains(item.$1)
                  ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18, color: _secoesConferidas.contains(item.$1)
                    ? t.success : t.error),
            ]),
          ),
        const SizedBox(height: 10),
        Text('Turma de destino: ${widget.turmaReativacaoNome ?? _turmaNome ?? "Selecionada"}',
          style: TextStyle(fontSize: 12, color: t.textSecondary)),
        const SizedBox(height: 16),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _salvandoAluno ? null : () => _navegarRevisao(_secoesReativacao.length - 1),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Voltar'),
          ),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(
            onPressed: _salvandoAluno || !todasConferidas ? null : _saveForm,
            icon: const Icon(Icons.how_to_reg_rounded),
            label: const Text('Reativar aluno'),
          )),
        ]),
      ]),
    );
  }

  final _formKey = GlobalKey<FormState>();
  bool get _isEditing => widget.alunoId != null;
  bool get _isFromInscricao => !_isEditing && widget.dadosInscricao != null;
  String? _idCadastroEmAndamento;


  // 🔐 PERMISSÕES
  final PermissaoService _permissaoService = PermissaoService();
  String? _currentUserId;
  Map<String, bool> _permissoes = {};
  bool _isAdmin = false;
  bool _podeEditarDadosCapoeira = false;
  bool _carregandoPermissoes = true;
  bool _verificouPermissoes = false;

  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'cpf': TextEditingController(),
    'apelido': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'data_graduacao_atual': TextEditingController(),
    'tempo_capoeira': TextEditingController(),
    'endereco': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
    'cidade': TextEditingController(),
    'rua': TextEditingController(),
    'numero': TextEditingController(),
    'bairro': TextEditingController(),
    'nome_contato_emergencia': TextEditingController(),
    'contato_emergencia': TextEditingController(),
    'grau_emergencia': TextEditingController(),
  };

  // Campos para academia e turma
  String? _academiaId;
  String? _academiaNome;
  String? _turmaId;
  String? _turmaNome;
  String? _academiaOriginalId;
  String? _academiaOriginalNome;
  String? _turmaOriginalId;
  String? _turmaOriginalNome;

  List<DropdownMenuItem<String>> _academiaItems = [];
  List<DropdownMenuItem<String>> _turmaItems = [];

  Map<String, String> _academiasMap = {}; // ID -> Nome
  Map<String, Map<String, dynamic>> _turmasMap = {}; // ID -> dados da turma

  String? _sexo;
  String? _statusAtividade = 'ATIVO(A)';
  String? _graduacaoId;
  List<DropdownMenuItem<String>> _graduacaoItems = [];
  Map<String, Map<String, dynamic>> _graduacoesData = {};
  XFile? _pickedImage;
  Uint8List? _pickedImageBytesPreview;
  String? _pickedImageExtension;
  String? _networkImageUrl;
  Uint8List? _studioOriginalBytesPendente;
  Uint8List? _studioArchiveFinalBytesPendente;
  PhotoCompressionSettings _fotoCompressaoPendente =
      const PhotoCompressionSettings();
  String _fotoOrigemPendente = 'studio';

  Map<String, dynamic> _fichaComplementar = fichaUaiVazia();
  String _fichaAssinaturaCarregada = '';
  String _assinaturaFicha(Map<String, dynamic> ficha) => jsonEncode({
    'familia': ficha['familia'] ?? <String, dynamic>{},
    'saude': ficha['saude'] ?? <String, dynamic>{},
    'capoeira': ficha['capoeira'] ?? <String, dynamic>{},
  });
  int _fichaRevisao = 0;
  bool _fichaRestritaCarregada = false;

  Future<void> _carregarFichaRestrita(String alunoId) async {
    final resposta = await FichaCallableClient.call('gerenciarFichaInscricao', {
      'aluno_id': alunoId, 'acao': 'ler',
    });
    final raw = resposta['ficha'];
    if (raw is Map) {
      final ficha = Map<String, dynamic>.from(raw);
      _fichaComplementar = ficha;
      _fichaRevisao = (ficha['revisao'] as num?)?.toInt() ?? 0;
    }
    _fichaRestritaCarregada = true;
    _fichaAssinaturaCarregada = _assinaturaFicha(_fichaComplementar);
  }

  Future<void> _salvarFichaRestritaSeAlterada(String alunoId) async {
    if (_fichaAssinaturaCarregada == _assinaturaFicha(_fichaComplementar)) return;
    if (!_fichaRestritaCarregada && _isEditing) {
      throw StateError('A ficha restrita não foi carregada. Reabra o cadastro antes de editar os cuidados.');
    }
    final erros = validarFichaUai(_fichaComplementar);
    if (erros.isNotEmpty) throw StateError(erros.join('\n'));
    await FichaCallableClient.call('gerenciarFichaInscricao', {
      'aluno_id': alunoId,
      'acao': 'salvar',
      'ficha': _fichaComplementar,
      'revisao': _fichaRevisao,
    });
    _fichaRestritaCarregada = true;
    _fichaAssinaturaCarregada = _assinaturaFicha(_fichaComplementar);
    _fichaRevisao++;
  }

  List<Map<String, dynamic>> _contatosEmergenciaAdicionais = [];
  bool _possuiEnderecoEstruturado = false;
  bool _enderecoLegadoAmbiguo = false;
  // A confirmação é válida somente para os valores efetivamente revisados.
  String? _enderecoRevisadoAssinatura;

  String get _assinaturaEnderecoAtual =>
      ['rua', 'numero', 'bairro']
          .map((campo) => _controllers[campo]!.text.trim().toUpperCase())
          .join('|');

  bool get _enderecoRevisaoConfirmada =>
      _enderecoRevisadoAssinatura != null &&
      _enderecoRevisadoAssinatura == _assinaturaEnderecoAtual;
  String _enderecoLegadoOriginal = '';
  Uint8List? _fotoAnteriorBytesEmMemoria;
  bool _isLoading = true;
  bool _carregandoTurmas = false;
  bool _turmaCheia = false;
  bool _isMounted = false;
  bool _salvandoAluno = false;
  bool _dialogSalvandoAberto = false;
  final ValueNotifier<_PhotoSaveProgressState> _saveProgress = ValueNotifier(
    const _PhotoSaveProgressState(
      title: 'Salvando aluno',
      message: 'Preparando dados...',
      progress: 0.05,
    ),
  );

  bool get _mudouTurma =>
      _isEditing && _turmaId != null && _turmaId != _turmaOriginalId;

  bool get _mudouAcademia =>
      _isEditing && _academiaId != null && _academiaId != _academiaOriginalId;

  bool get _mudouTurmaOuAcademia => _mudouTurma || _mudouAcademia;

  @override
  void initState() {
    super.initState();
    if (widget.modoReativacao) {
      assert(widget.alunoId != null, 'A reativação precisa de um aluno existente.');
      _secaoAbertaId = _secoesReativacao.first;
      for (final campo in _controllers.entries) {
        final secao = switch (campo.key) {
          'nome' || 'cpf' || 'apelido' || 'data_nascimento' => 'pessoais',
          'contato_aluno' || 'nome_responsavel' || 'contato_responsavel' ||
            'nome_contato_emergencia' || 'contato_emergencia' || 'grau_emergencia' => 'contato',
          'rua' || 'numero' || 'bairro' || 'cidade' || 'endereco' => 'endereco',
          _ => 'capoeira_dados',
        };
        campo.value.addListener(() => _invalidarRevisao(secao));
      }
    }
     _isMounted = true;
     for (final campo in const ['rua', 'numero', 'bairro']) {
       _controllers[campo]!.addListener(_atualizarConfirmacaoEndereco);
     }
     _carregarUsuarioLogado(); // 🔥 CARREGAR USUÁRIO PRIMEIRO
    _initializeData();
  }

   void _atualizarConfirmacaoEndereco() {
     // Atualiza visualmente o checkbox quando algum campo revisado muda.
     if (_enderecoRevisadoAssinatura != null &&
         !_enderecoRevisaoConfirmada && mounted) {
       setState(() => _enderecoRevisadoAssinatura = null);
     }
   }

   @override
   void dispose() {
    _isMounted = false;
    _controllers.forEach((_, controller) {
      controller.dispose();
    });
    _reativacaoScroll.dispose();
    _saveProgress.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback callback) {
    if (mounted) {
      setState(callback);
    }
  }

  // 🔐 CARREGAR USUÁRIO LOGADO
  Future<void> _carregarUsuarioLogado() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        _currentUserId = user.uid;
        developer.log('✅ Usuário logado: $_currentUserId');
        await _carregarPermissoes();
      } else {
        developer.log('❌ Nenhum usuário logado');
        _safeSetState(() {
          _carregandoPermissoes = false;
          _verificouPermissoes = true;
        });
      }
    } catch (e) {
      developer.log('❌ Erro ao carregar usuário: $e');
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    }
  }

  // 🔐 CARREGAR PERMISSÕES
  Future<void> _carregarPermissoes() async {
    if (_currentUserId == null) {
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
      return;
    }

    try {
      final permissoes = await _permissaoService.carregarPermissoes(
        _currentUserId!,
      );
      final peso = await _permissaoService.obterPesoPermissao(_currentUserId!);
      final isAdmin = peso >= 90;


      _safeSetState(() {
        _permissoes = permissoes;
        _isAdmin = isAdmin;
        _podeEditarDadosCapoeira = peso >= 100;
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    } catch (e) {
      developer.log('❌ Erro ao carregar permissões: $e');
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    }
  }

  // 🔐 VERIFICAR PERMISSÃO
  Future<bool> _verificarPermissao(String permissao, {String? acao}) async {
    // Se ainda está carregando, aguarda
    if (_carregandoPermissoes || !_verificouPermissoes) {
      developer.log('⏳ Aguardando carregar permissões...');
      await Future.delayed(Duration(milliseconds: 500));
      return _verificarPermissao(permissao, acao: acao);
    }

    // Admin tem todas as permissões
    if (_isAdmin) {
      developer.log('✅ ADMIN - Permissão concedida');
      return true;
    }

    final temPermissao = _permissoes[permissao] ?? false;
    developer.log('🔐 Permissão "$permissao": ${temPermissao ? "✅" : "❌"}');

    if (!temPermissao) {
      await _mostrarDialogoSemPermissao(acao ?? permissao);
    }

    return temPermissao;
  }

  // 🔐 DIÁLOGO DE SEM PERMISSÃO
  Future<void> _mostrarDialogoSemPermissao(String acao) async {
    if (!mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.no_accounts, color: context.uai.primary, size: 28),
              SizedBox(width: 12),
              Text(
                'Sem Permissão',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você não tem permissão para $acao.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.error.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.uai.error.withAlpha(41),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.uai.primary,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.uai.textPrimary.withAlpha(222),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: context.uai.primary),
              child: Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeData() async {
    try {
      await _fetchAcademias();
      await _fetchGraduacoes();
      if (!_isEditing) {
        await _aplicarDadosCadastroInicial();
        _fichaAssinaturaCarregada = _assinaturaFicha(_fichaComplementar);
      }
      if (_isEditing) {
        await _loadAlunoData();
      }
      _safeSetState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao inicializar dados: $e');
      _safeSetState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemErroAmigavelEditarAluno(e, contexto: 'carga de dados'),
            ),
          ),
        );
      }
    }
  }

  /// Os dois caminhos de cadastro usam o mesmo formulário e validadores.
  /// A inscrição conserva seus dados de origem para a conversão transacional.
  Future<void> _aplicarDadosCadastroInicial() async {
    final origem = widget.dadosInscricao;
    if (origem != null) {
      for (final campo in _controllers.keys) {
        final valor = origem[campo];
        if (valor is String && valor.trim().isNotEmpty) {
          _controllers[campo]!.text = valor;
        } else if (valor is Timestamp) {
          _controllers[campo]!.text = DateFormat('dd/MM/yyyy').format(valor.toDate());
        }
      }
      // Datas antigas podem chegar como ISO, Timestamp ou dd/MM/yyyy.
      // O formulário unificado sempre espera dd/MM/yyyy.
      for (final campo in const [
        'data_nascimento', 'data_graduacao_atual', 'tempo_capoeira',
      ]) {
        final texto = _controllers[campo]!.text.trim();
        if (texto.isNotEmpty && !texto.contains('/')) {
          final dt = DateTime.tryParse(texto);
          if (dt != null) {
            _controllers[campo]!.text = DateFormat('dd/MM/yyyy').format(dt);
          }
        }
      }
      final endereco = origem['endereco']?.toString() ?? '';
      final interpretado = _EnderecoLegadoUai.interpretar(
        endereco, cidadeConhecida: origem['cidade']?.toString());
      for (final campo in const ['rua', 'numero', 'bairro', 'cidade']) {
        if (_controllers[campo]!.text.trim().isEmpty &&
            interpretado[campo]?.isNotEmpty == true) {
          _controllers[campo]!.text = interpretado[campo]!;
        }
      }
      _sexo = origem['sexo']?.toString();
      // Saúde/ficha sensível da inscrição permanece na ficha restrita,
      // identificada por ficha_inscricao_id. Não copiar para alunos (leitura
      // de gestão mais ampla) durante a conversão.
      _fichaComplementar = fichaUaiVazia();
      _contatosEmergenciaAdicionais = (origem['contatos_emergencia_adicionais'] is List
          ? origem['contatos_emergencia_adicionais'] as List : const [])
          .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _consolidarContatosLegados(origem: origem);
      _fichaAssinaturaCarregada = _assinaturaFicha(_fichaComplementar);
      final foto = (origem['foto_url'] ?? origem['foto_perfil_aluno'] ??
          origem['foto_aluno_url'] ?? '').toString().trim();
      if (foto.isNotEmpty) _networkImageUrl = foto;
    }
    _academiaId = widget.academiaIdInicial;
    _academiaNome = widget.academiaNomeInicial;
    _turmaId = widget.turmaIdInicial;
    _turmaNome = widget.turmaNomeInicial;
    // Não manter Dropdown com ID ausente: academia/turma podem ter sido
    // desativadas entre a escolha inicial e a abertura da tela.
    if (_academiaId != null && !_academiasMap.containsKey(_academiaId)) {
      debugPrint('Academia inicial indisponível; escolha outra antes de salvar.');
      _academiaId = null;
      _academiaNome = null;
      _turmaId = null;
      _turmaNome = null;
    }
    if (_academiaId != null && _academiaId!.isNotEmpty) {
      await _fetchTurmas(_academiaId);
      if (_turmasMap.containsKey(widget.turmaIdInicial)) {
        _turmaId = widget.turmaIdInicial;
        _turmaNome = widget.turmaNomeInicial ??
            _turmasMap[_turmaId]?['nome']?.toString();
        _turmaCheia = _turmasMap[_turmaId]?['cheia'] == true;
      } else if (widget.turmaIdInicial != null) {
        _turmaId = null;
        _turmaNome = null;
      }
    }
  }

  // O responsável é o contato principal. Dados legados que indiquem outra
  // pessoa são preservados como contato adicional, nunca descartados.
  void _consolidarContatosLegados({Map<String, dynamic>? origem}) {
    final responsavel = _controllers['nome_responsavel']!;
    final telefoneResponsavel = _controllers['contato_responsavel']!;
    final nomeEmergencia = _controllers['nome_contato_emergencia']!;
    final telefoneEmergencia = _controllers['contato_emergencia']!;
    final nomeAntigo = nomeEmergencia.text.trim();
    final telefoneAntigo = telefoneEmergencia.text.trim();
    final nomePrincipal = responsavel.text.trim();
    final telefonePrincipal = telefoneResponsavel.text.trim();
    String soNumeros(String valor) => valor.replaceAll(RegExp(r'[^0-9]'), '');
    final haOutroContato = (nomeAntigo.isNotEmpty || telefoneAntigo.isNotEmpty) &&
        ((nomePrincipal.isNotEmpty && nomeAntigo.isNotEmpty &&
            nomePrincipal.toUpperCase() != nomeAntigo.toUpperCase()) ||
         (telefonePrincipal.isNotEmpty && telefoneAntigo.isNotEmpty &&
            soNumeros(telefonePrincipal) != soNumeros(telefoneAntigo)));
    if (haOutroContato) {
      final nomeExtra = nomeAntigo.isNotEmpty ? nomeAntigo : 'Contato de emergência';
      final telefoneExtra = soNumeros(telefoneAntigo);
      final existe = _contatosEmergenciaAdicionais.any((item) =>
          (telefoneExtra.isNotEmpty && soNumeros(item['telefone']?.toString() ?? '') == telefoneExtra) ||
          (telefoneExtra.isEmpty &&
              (item['nome']?.toString().trim().toUpperCase() ?? '') == nomeExtra.toUpperCase()));
      if (!existe) {
        _contatosEmergenciaAdicionais.add({
          'nome': nomeExtra,
          'telefone': telefoneExtra,
          'grau': _controllers['grau_emergencia']!.text.trim(),
        });
      }
    }
    if (responsavel.text.trim().isEmpty && nomeAntigo.isNotEmpty) {
      responsavel.text = nomeAntigo;
    }
    if (telefoneResponsavel.text.trim().isEmpty && telefoneAntigo.isNotEmpty) {
      telefoneResponsavel.text = telefoneAntigo;
    }
    final familia = Map<String, dynamic>.from(
      _fichaComplementar['familia'] is Map
          ? _fichaComplementar['familia'] as Map : const <String, dynamic>{},
    );
    final parentesco = (origem?['grau_responsavel'] ??
        familia['grau_responsavel'] ??
        (!haOutroContato ? _controllers['grau_emergencia']!.text : null))
        ?.toString().trim() ?? '';
    if (parentesco.isNotEmpty) {
      _controllers['grau_emergencia']!.text = parentesco;
      familia['grau_responsavel'] = parentesco;
      _fichaComplementar['familia'] = familia;
    }
    // Os campos legados continuam disponíveis para integrações antigas,
    // agora refletindo o único contato principal visível.
    nomeEmergencia.text = responsavel.text;
    telefoneEmergencia.text = telefoneResponsavel.text;
  }

  // Buscar academias ativas
  Future<void> _fetchAcademias() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .orderBy('nome')
          .get();

      final items = <DropdownMenuItem<String>>[];
      final academiasMap = <String, String>{};
      final uniqueIds = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome'] ?? 'Sem nome';
        final id = doc.id;

        // Evitar duplicatas
        if (uniqueIds.contains(id)) {
          debugPrint('⚠️ Academia duplicada ignorada: $id - $nome');
          continue;
        }
        uniqueIds.add(id);

        academiasMap[id] = nome;
        items.add(DropdownMenuItem(value: id, child: Text(nome)));
      }

      _safeSetState(() {
        _academiasMap = academiasMap;
        _academiaItems = items;
      });
    } catch (e) {
      debugPrint('Erro ao buscar academias: $e');
      rethrow;
    }
  }

  // Buscar turmas da academia selecionada (coleção separada)
  Future<void> _fetchTurmas(String? academiaId) async {
    if (academiaId == null || academiaId.isEmpty) {
      _safeSetState(() {
        _turmaItems = [];
        _turmasMap = {};
        _turmaId = null;
        _turmaNome = null;
        _carregandoTurmas = false;
        _turmaCheia = false;
      });
      return;
    }

    _safeSetState(() {
      _carregandoTurmas = true;
    });

    final mutedColor = context.uai.textMuted;
    try {
      debugPrint('🔄 Buscando turmas para academia ID: $academiaId');

      final snapshot = await FirebaseFirestore.instance
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .orderBy('nome')
          .get();

      debugPrint('✅ ${snapshot.docs.length} turmas encontradas');

      final items = <DropdownMenuItem<String>>[];
      final turmasMap = <String, Map<String, dynamic>>{};
      final uniqueTurmaIds = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome'] ?? 'Sem nome';
        final id = doc.id;

        if (uniqueTurmaIds.contains(id)) {
          debugPrint('⚠️ Turma duplicada ignorada: $id - $nome');
          continue;
        }
        uniqueTurmaIds.add(id);

        final capacidadeMaxima = data['capacidade_maxima'] ?? 0;
        final alunosCount = data['alunos_count'] ?? 0;
        final alunosAtivos = data['alunos_ativos'] ?? 0;
        final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
        final turmaCheia =
            capacidadeMaxima > 0 && totalAlunos >= capacidadeMaxima;
        final turmaAtualOriginal =
            _isEditing &&
            id == _turmaOriginalId &&
            academiaId == _academiaOriginalId;
        final turmaBloqueada = turmaCheia && !turmaAtualOriginal;

        turmasMap[id] = {
          'id': id,
          'nome': nome,
          'horario': data['horario_display'] ?? data['horario'] ?? '',
          'dias_semana':
              data['dias_semana_display'] ?? data['dias_semana'] ?? [],
          'capacidade_maxima': capacidadeMaxima,
          'alunos_count': alunosCount,
          'alunos_ativos': alunosAtivos,
          'faixa_etaria': data['faixa_etaria'] ?? '',
          'nivel': data['nivel'] ?? '',
          'academia_id': data['academia_id'] ?? '',
          'cheia': turmaCheia,
        };

        items.add(
          DropdownMenuItem(
            value: id,
            enabled: !turmaBloqueada,
            child: Text(
              nome,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: turmaBloqueada ? mutedColor : null,
                fontWeight: turmaCheia ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }

      final finalItems = <DropdownMenuItem<String>>[];
      final seenValues = <String>{};

      for (var item in items) {
        if (!seenValues.contains(item.value)) {
          seenValues.add(item.value!);
          finalItems.add(item);
        }
      }

      _safeSetState(() {
        _turmasMap = turmasMap;
        _turmaItems = finalItems;
        _carregandoTurmas = false;

        if (_turmaId != null && turmasMap.containsKey(_turmaId)) {
          final turmaData = turmasMap[_turmaId];
          _turmaCheia = turmaData?['cheia'] == true;
        }

        if (_turmaId != null && !seenValues.contains(_turmaId)) {
          _turmaId = null;
          _turmaNome = null;
          _turmaCheia = false;
        }

        if (_statusAtividade == 'ATIVO(A)' &&
            _turmaId == null &&
            finalItems.length == 1 &&
            finalItems.first.enabled) {
          _turmaId = finalItems.first.value;
          final turmaData = _turmasMap[_turmaId];
          _turmaNome = turmaData != null ? turmaData['nome'] as String? : null;
          _turmaCheia = turmaData?['cheia'] == true;
        }
      });
    } catch (e) {
      debugPrint('❌ Erro ao buscar turmas: $e');
      _safeSetState(() {
        _carregandoTurmas = false;
      });
    }
  }

  Future<void> _fetchGraduacoes() async {
    final graduationBorderColor = context.uai.textPrimary.withAlpha(97);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      Map<String, Map<String, dynamic>> dataMap = {};
      final uniqueGraduacoes = <String>{};
      final items = <DropdownMenuItem<String>>[];

      for (var doc in snapshot.docs) {
        final id = doc.id;
        if (uniqueGraduacoes.contains(id)) {
          debugPrint('⚠️ Graduação duplicada ignorada: $id');
          continue;
        }
        uniqueGraduacoes.add(id);

        final data = doc.data();
        dataMap[id] = data;

        final cor1 = _colorFromHex(data['hex_cor1']);
        final cor2 = _colorFromHex(data['hex_cor2']);

        items.add(
          DropdownMenuItem(
            value: id,
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [cor2, cor1],
                      stops: [0.5, 0.5],
                    ),
                    border: Border.all(
                      color: graduationBorderColor,
                      width: 1,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data['nome_graduacao'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final finalItems = <DropdownMenuItem<String>>[];
      final seenValues = <String>{};

      finalItems.add(
        DropdownMenuItem(value: null, child: Text("Sem Graduação")),
      );

      for (var item in items) {
        if (!seenValues.contains(item.value)) {
          seenValues.add(item.value!);
          finalItems.add(item);
        }
      }

      _safeSetState(() {
        _graduacoesData = dataMap;
        _graduacaoItems = finalItems;
      });
    } catch (e) {
      debugPrint('Erro ao buscar graduações: $e');
      rethrow;
    }
  }

  Future<void> _loadAlunoData() async {
    try {
      if (widget.alunoId == null || widget.alunoId!.isEmpty) {
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(widget.alunoId)
          .get();

      final data = doc.data();
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Aluno não encontrado')));
        }
        return;
      }

      if (!mounted) return;

      _carregarResumoCadastro(data);

      // Preencher controllers com dados textuais
      _controllers.forEach((key, controller) {
        if (data.containsKey(key) &&
            data[key] != null &&
            data[key] is! Timestamp) {
          controller.text = data[key].toString();
        }
      });

      void safeSetDate(String fieldName, dynamic timestamp) {
        if (timestamp != null && timestamp is Timestamp) {
          _controllers[fieldName]!.text = _formatTimestamp(timestamp);
        }
      }

      safeSetDate('data_nascimento', data['data_nascimento']);
      safeSetDate('data_graduacao_atual', data['data_graduacao_atual']);
      safeSetDate('tempo_capoeira', data['tempo_capoeira']);

      // Migração em memória: cadastro antigo com somente responsável passa a
      // preencher o contato principal de emergência, sem apagar os campos legados.
      final nomeEmergencia = _controllers['nome_contato_emergencia']!;
      final telefoneEmergencia = _controllers['contato_emergencia']!;
      if (nomeEmergencia.text.trim().isEmpty) {
        nomeEmergencia.text = _controllers['nome_responsavel']!.text.trim();
      }
      if (telefoneEmergencia.text.trim().isEmpty) {
        telefoneEmergencia.text = _controllers['contato_responsavel']!.text.trim();
      }

      // Valores vindos do Firestore são armazenados sem pontuação.
      // Exibição usa a mesma máscara da inscrição pública.
      for (final campo in const ['contato_aluno', 'contato_responsavel', 'contato_emergencia']) {
        final valor = _controllers[campo]?.text ?? '';
        if (valor.isNotEmpty) {
          _controllers[campo]!.text = _EditarTelefoneFormatter().formatEditUpdate(
            const TextEditingValue(), TextEditingValue(text: valor),
          ).text;
        }
      }
      final cpfLegado = _controllers['cpf']!.text;
       if (cpfLegado == '0') {
         _controllers['cpf']!.clear(); // Marcador antigo de dado ausente.
       } else if (cpfLegado.isNotEmpty) {
        _controllers['cpf']!.text = _EditarCpfFormatter().formatEditUpdate(
          const TextEditingValue(), TextEditingValue(text: cpfLegado),
        ).text;
      }

      _fichaComplementar = Map<String, dynamic>.from(
        data['ficha_complementar'] is Map ? data['ficha_complementar'] as Map : fichaUaiVazia(),
      );
      // A tela da ficha lê fichas_inscricao via callable, não alunos.ficha_complementar.
      // Uma falha impede edição da ficha, sem sobrescrever o conteúdo protegido.
      try {
        await _carregarFichaRestrita(widget.alunoId!);
      } catch (e) {
        debugPrint('Ficha restrita indisponível: $e');
        _fichaRestritaCarregada = false;
      }
      _contatosEmergenciaAdicionais = (data['contatos_emergencia_adicionais'] is List
              ? data['contatos_emergencia_adicionais'] as List : const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)).toList();
      // Migração apenas em memória: os campos novos sempre têm prioridade.
      // Um endereço legado ambíguo não é descartado nem inventado.
      final legado = data['endereco']?.toString().trim() ?? '';
      _enderecoLegadoOriginal = legado;
      final migrado = _EnderecoLegadoUai.interpretar(
        legado,
        cidadeConhecida: data['cidade']?.toString(),
      );
      _possuiEnderecoEstruturado = ['rua', 'numero', 'bairro'].any(
        (key) => data[key]?.toString().trim().isNotEmpty == true,
      );
       _enderecoLegadoAmbiguo = false;
       _enderecoRevisadoAssinatura = null;
       for (final campo in const ['rua', 'numero', 'bairro']) {
        if (_controllers[campo]!.text.trim().isEmpty &&
            (migrado[campo]?.isNotEmpty ?? false)) {
          _controllers[campo]!.text = migrado[campo]!;
        }
      }
      if (_controllers['cidade']!.text.trim().isEmpty &&
          (migrado['cidade']?.isNotEmpty ?? false)) {
        _controllers['cidade']!.text = migrado['cidade']!;
      }
       _enderecoLegadoAmbiguo = legado.isNotEmpty &&
           ((migrado['revisao_necessaria'] == 'true' && !_possuiEnderecoEstruturado) ||
            _controllers['rua']!.text.trim().isEmpty ||
            _controllers['numero']!.text.trim().isEmpty ||
            _controllers['bairro']!.text.trim().isEmpty);

      // A ficha antiga pode trazer informações fora do mapa complementar.
      // Os dados que não têm equivalência certa são mantidos sem alterações.
      final familia = Map<String, dynamic>.from(
        _fichaComplementar['familia'] is Map
            ? _fichaComplementar['familia'] as Map : const <String, dynamic>{},
      );
       // Parentesco do responsável e parentesco de emergência são conceitos
       // diferentes. Só herdar o vínculo quando a emergência foi derivada
       // do responsável antigo (sem contato de emergência independente).
       final emergenciaEspecifica =
           (data['nome_contato_emergencia']?.toString().trim().isNotEmpty ?? false) ||
           (data['contato_emergencia']?.toString().trim().isNotEmpty ?? false);
       final grauResponsavel = data['grau_responsavel']?.toString().trim() ?? '';
       final grauFicha = familia['grau_responsavel']?.toString().trim() ?? '';
       final grauEmergencia = _controllers['grau_emergencia']!.text.trim();
       if (grauFicha.isEmpty && grauResponsavel.isNotEmpty) {
         familia['grau_responsavel'] = grauResponsavel;
       }
       if (grauEmergencia.isEmpty && !emergenciaEspecifica) {
         final herdado = grauResponsavel.isNotEmpty ? grauResponsavel : grauFicha;
         if (herdado.isNotEmpty) {
           _controllers['grau_emergencia']!.text = herdado;
         }
       }
      _fichaComplementar['familia'] = familia;
       _consolidarContatosLegados(origem: data);
       // A reativação começa com 'Não' somente em fichas de saúde sem
       // resposta anterior. Respostas existentes (incluindo 'Sim') ficam intactas.
       if (widget.modoReativacao && _fichaRestritaCarregada) {
         final saude = Map<String, dynamic>.from(
           _fichaComplementar['saude'] is Map
               ? _fichaComplementar['saude'] as Map
               : const <String, dynamic>{},
         );
         if ((saude['resposta']?.toString().trim() ?? '').isEmpty) {
           _fichaComplementar['saude'] = {...saude, 'resposta': 'Não'};
         }
       }
       // Na revisão de reativação, ficha de capoeira vazia equivale a "Não":
       // esse campo trata de experiência em OUTRO grupo, não da UAI.
       if (widget.modoReativacao && _fichaRestritaCarregada) {
         final capoeira = Map<String, dynamic>.from(
           _fichaComplementar['capoeira'] is Map
               ? _fichaComplementar['capoeira'] as Map : const <String, dynamic>{},
         );
         if ((capoeira['ja_treinou']?.toString().trim() ?? '').isEmpty) {
           capoeira['ja_treinou'] = 'Não';
           _fichaComplementar['capoeira'] = capoeira;
         }
       }
       String? academiaId = data['academia_id'] as String?;
      String? turmaId = data['turma_id'] as String?;
      String? academiaNome = data['academia'] as String?;
      String? turmaNome = data['turma'] as String?;

      _safeSetState(() {
        _sexo = data['sexo'] as String?;
        _statusAtividade = data['status_atividade'] as String? ?? 'ATIVO(A)';
        _graduacaoId = data['graduacao_id'] as String?;
        _networkImageUrl = data['foto_perfil_aluno'] as String?;

        _academiaId = academiaId;
        _academiaNome = academiaNome;
        _turmaId = turmaId;
        _turmaNome = turmaNome;
        _academiaOriginalId = academiaId;
        _academiaOriginalNome = academiaNome;
        _turmaOriginalId = turmaId;
        _turmaOriginalNome = turmaNome;
      });

      if (academiaId != null && academiaId.isNotEmpty) {
        if (academiaNome == null || academiaNome.isEmpty) {
          try {
            final academiaDoc = await FirebaseFirestore.instance
                .collection('academias')
                .doc(academiaId)
                .get();

            if (academiaDoc.exists) {
              final academiaData = academiaDoc.data();
              _safeSetState(() {
                _academiaNome = academiaData?['nome'] as String?;
              });
            }
          } catch (e) {
            debugPrint('Erro ao buscar dados da academia: $e');
          }
        }

        await _fetchTurmas(academiaId);
      } else if (academiaNome != null && academiaNome.isNotEmpty) {
        final academiaIdPorNome = _academiasMap.entries
            .firstWhere(
              (entry) => entry.value == academiaNome,
              orElse: () => MapEntry('', ''),
            )
            .key;

        if (academiaIdPorNome.isNotEmpty) {
          _safeSetState(() {
            _academiaId = academiaIdPorNome;
          });
          await _fetchTurmas(academiaIdPorNome);
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do aluno: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemErroAmigavelEditarAluno(e, contexto: 'carga de dados'),
            ),
          ),
        );
      }
      rethrow;
    }
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.length < 7) return context.uai.textMuted;
    return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
  }

  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1920),
      lastDate: DateTime(2100),
    );

    if (picked != null && _isMounted) {
      _safeSetState(
        () => controller.text = DateFormat('dd/MM/yyyy').format(picked),
      );
    }
  }

  void _showImageSourceActionSheet() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: context.uai.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(
                    Icons.photo_library,
                    color: context.uai.primary,
                  ),
                  title: Text('Escolher da Galeria'),
                  subtitle: Text('Selecionar uma nova foto do aluno'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ),
              if (!_isWindowsPlatform)
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(Icons.camera_alt, color: context.uai.primary),
                    title: Text(
                      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                          ? 'Câmera guiada UAI'
                          : 'Tirar Foto com a Câmera',
                    ),
                    subtitle: Text(
                      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                          ? 'Oval, cruz, perfil e card de chamada ao vivo'
                          : 'Abrir a câmera do dispositivo',
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(
                    _isWindowsPlatform
                        ? Icons.auto_fix_high_rounded
                        : Icons.crop_rounded,
                    color: context.uai.success,
                  ),
                  title: Text(
                    _isWindowsPlatform
                        ? 'Abrir UAI Photo Studio'
                        : 'Editar foto do aluno',
                  ),
                  subtitle: Text(
                    _isWindowsPlatform
                        ? 'Enquadramento profissional, filtros e prévias dos cards'
                        : 'Centralizar o rosto para aparecer certo nos cards',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editarFotoAluno();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _obterBytesImagemParaEditar() async {
    try {
      if (_pickedImage != null) {
        return await _pickedImage!.readAsBytes();
      }

      final url = _networkImageUrl?.trim() ?? '';
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://'))) {
        return null;
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Erro ao preparar foto para edição: $e');
      return null;
    }
  }

  Future<Uint8List?> _obterBytesFotoSalvaNoStorage() async {
    try {
      final url = _networkImageUrl?.trim() ?? '';
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://'))) {
        return null;
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Erro ao baixar foto atual do Storage para backup: $e');
      return null;
    }
  }

  Future<void> _editarFotoAluno() async {
    final podeEditar = !_isEditing || await _verificarPermissao(
      'pode_editar_aluno',
      acao: 'abrir o UAI Photo Studio',
    );
    if (!podeEditar || !mounted) return;

    final imagemOrigem = await _obterBytesImagemParaEditar();

    if (imagemOrigem == null || imagemOrigem.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Selecione ou tire uma foto primeiro para editar.',
          ),
          backgroundColor: context.uai.warning,
        ),
      );
      return;
    }

    if (!mounted) return;

    final storageOriginalBytes = _isEditing
        ? (_fotoAnteriorBytesEmMemoria ??
            (_pickedImage == null ? imagemOrigem : await _obterBytesFotoSalvaNoStorage()))
        : null;
    if (!mounted) return;
    _fotoAnteriorBytesEmMemoria ??= storageOriginalBytes;

    final resultado = await Navigator.of(context).push<PhotoStudioResult?>(
      MaterialPageRoute<PhotoStudioResult?>(
        fullscreenDialog: true,
        builder: (_) => PhotoStudioScreen(
          sourceBytes: imagemOrigem,
          storageOriginalBytes: storageOriginalBytes,
          nomeAluno: _controllers['nome']?.text.trim() ?? 'Aluno',
          alunoId: widget.alunoId,
          dataNascimento: _parseDate(
            _controllers['data_nascimento']?.text.trim() ?? '',
          ),
          sourceOrigin: _fotoOrigemPendente,
          initialCompression: _fotoCompressaoPendente,
        ),
      ),
    );

    if (resultado != null && mounted) {
      _safeSetState(() {
        _studioOriginalBytesPendente =
            resultado.sourceOriginalBytes ?? imagemOrigem;
        _studioArchiveFinalBytesPendente = resultado.archiveFinalBytes;
        _fotoCompressaoPendente = resultado.compression;
        _fotoOrigemPendente = resultado.origem;
        _pickedImage = XFile.fromData(
          resultado.bytes,
          mimeType: resultado.contentType,
          name: 'foto_aluno_editada.${resultado.extension}',
        );
        _pickedImageBytesPreview = resultado.bytes;
        _pickedImageExtension = resultado.extension;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '✓ Foto editada. Toque em Salvar para enviar ao Firebase.',
          ),
          backgroundColor: context.uai.success,
        ),
      );
    }
  }

  Future<PhotoCompressionSettings?> _escolherQualidadeInicialFoto() async {
    if (!_isMounted) return null;
    return showModalBottomSheet<PhotoCompressionSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final t = sheetContext.uai;
        var selected = _fotoCompressaoPendente.preset;
        var customQuality = _fotoCompressaoPendente.jpegQuality
            .toDouble()
            .clamp(40.0, 100.0);
        return StatefulBuilder(
          builder: (context, setLocalState) {
            PhotoCompressionSettings current() {
              if (selected == PhotoCompressionPreset.custom) {
                return PhotoCompressionSettings(
                  preset: PhotoCompressionPreset.custom,
                  jpegQuality: customQuality.round().clamp(40, 100),
                  maxSide: 1600,
                );
              }
              return PhotoCompressionSettings.fromPreset(selected);
            }

            Widget option(
              PhotoCompressionPreset preset,
              String title,
              String subtitle,
              IconData icon,
            ) {
              final active = selected == preset;
              return InkWell(
                onTap: () => setLocalState(() => selected = preset),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: active ? t.primary.withAlpha(28) : t.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? t.primary : t.border),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: active ? t.primary : t.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (active)
                        Icon(Icons.check_circle_rounded, color: t.primary),
                    ],
                  ),
                ),
              );
            }

            final cfg = current();
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.border),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: t.primary.withAlpha(31),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.photo_size_select_large_rounded,
                              color: t.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Qualidade da nova foto',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  'O ORIGINAL full-res fica preservado no Drive. Esta escolha afeta só a foto operacional.',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 11.2,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      option(
                        PhotoCompressionPreset.original,
                        'Original / sem compressão extra',
                        'JPEG 100% no limite do editor. Máxima qualidade operacional.',
                        Icons.auto_awesome_rounded,
                      ),
                      const SizedBox(height: 8),
                      option(
                        PhotoCompressionPreset.high,
                        'Alta qualidade',
                        '90% • recomendado para Perfil, Chamada e Turmas.',
                        Icons.hd_rounded,
                      ),
                      const SizedBox(height: 8),
                      option(
                        PhotoCompressionPreset.balanced,
                        'Equilibrada',
                        '80% • boa qualidade com arquivo menor.',
                        Icons.balance_rounded,
                      ),
                      const SizedBox(height: 8),
                      option(
                        PhotoCompressionPreset.light,
                        'Leve',
                        '65% • prioriza velocidade e economia de dados.',
                        Icons.speed_rounded,
                      ),
                      const SizedBox(height: 8),
                      option(
                        PhotoCompressionPreset.custom,
                        'Personalizada',
                        'Escolha exatamente a porcentagem JPEG.',
                        Icons.tune_rounded,
                      ),
                      if (selected == PhotoCompressionPreset.custom) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Compressão JPEG',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${customQuality.round()}%',
                              style: TextStyle(
                                color: t.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: customQuality,
                          min: 40,
                          max: 100,
                          divisions: 60,
                          label: '${customQuality.round()}%',
                          onChanged: (value) =>
                              setLocalState(() => customQuality = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: t.cardAlt,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.border),
                        ),
                        child: Text(
                          'Selecionado: ${cfg.label} • ${cfg.jpegQuality}% • lado máximo ${cfg.maxSide}px\nDrive: ORIGINAL bruto + FINAL do Studio em alta qualidade.',
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(sheetContext, cfg),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Usar esta qualidade'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final useGuidedCamera =
          source == ImageSource.camera &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android;

      XFile? image;
      if (useGuidedCamera) {
        image = await Navigator.of(context).push<XFile?>(
          MaterialPageRoute<XFile?>(
            fullscreenDialog: true,
            builder: (_) => GuidedCameraScreen(
              nomeAluno: _controllers['nome']?.text.trim().isNotEmpty == true
                  ? _controllers['nome']!.text.trim()
                  : 'Aluno',
            ),
          ),
        );
      } else {
        image = await ImagePicker().pickImage(
          source: source,
          // V11: preserve os bytes originais. Compressão só acontece depois,
          // de forma explícita, no UAI Photo Studio.
          imageQuality: 100,
        );
      }

      if (image != null && mounted) {
        final previewBytes = await image.readAsBytes();
        if (!mounted) return;
        if (useGuidedCamera) {
          final quality = await _escolherQualidadeInicialFoto();
          if (quality == null || !_isMounted) return;
          _fotoCompressaoPendente = quality;
        }
        _safeSetState(() {
          _pickedImage = image;
         if (widget.modoReativacao) _secoesConferidas.remove('foto');
          _pickedImageBytesPreview = previewBytes;
          _studioOriginalBytesPendente = previewBytes;
          _fotoOrigemPendente = useGuidedCamera ? 'camera_guiada' : 'galeria';
          final candidate = image!.name.isNotEmpty ? image.name : image.path;
          final parts = candidate.split('.');
          _pickedImageExtension = parts.length > 1
              ? parts.last.toLowerCase()
              : 'jpg';
        });

        if (useGuidedCamera && mounted) {
          await _editarFotoAluno();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemErroAmigavelEditarAluno(
                e,
                contexto: 'seleção da imagem',
              ),
            ),
          ),
        );
      }
    }
  }

  void _atualizarSplashSalvandoAluno({
    required String titulo,
    required String mensagem,
    required double progresso,
  }) {
    if (!mounted) return;
    _saveProgress.value = _PhotoSaveProgressState(
      title: titulo,
      message: mensagem,
      progress: progresso.clamp(0.0, 1.0).toDouble(),
    );
  }

  void _mostrarSplashSalvandoAluno({
    String mensagem = 'Salvando ficha do aluno...',
  }) {
    if (_dialogSalvandoAberto || !mounted) return;

    _atualizarSplashSalvandoAluno(
      titulo: 'Preparando salvamento',
      mensagem: mensagem,
      progresso: 0.05,
    );
    _dialogSalvandoAberto = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final t = dialogContext.uai;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: t.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ValueListenableBuilder<_PhotoSaveProgressState>(
                valueListenable: _saveProgress,
                builder: (context, progress, _) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: t.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  value: progress.progress,
                                  strokeWidth: 4,
                                  backgroundColor: t.border,
                                  color: t.primary,
                                ),
                              ),
                              Icon(
                                Icons.cloud_done_rounded,
                                color: t.primary,
                                size: 25,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          progress.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          progress.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress.progress,
                            minHeight: 8,
                            backgroundColor: t.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              t.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 13,
                              color: t.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'A foto antiga só é removida depois de um backup seguro.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _fecharSplashSalvandoAluno() {
    if (!_dialogSalvandoAberto || !mounted) return;
    _dialogSalvandoAberto = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _nomeAcademiaAtual() {
    return _academiaNome ?? _academiasMap[_academiaId] ?? 'Sem academia';
  }

  String _nomeTurmaAtual() {
    final turmaData = _turmaId != null ? _turmasMap[_turmaId] : null;
    return _turmaNome ?? turmaData?['nome']?.toString() ?? 'Sem turma';
  }

  String? _resumoMudancaTurma() {
    if (!_mudouTurmaOuAcademia) return null;

    final academiaAntes = _academiaOriginalNome ?? 'Sem academia';
    final turmaAntes = _turmaOriginalNome ?? 'Sem turma';
    final academiaDepois = _nomeAcademiaAtual();
    final turmaDepois = _nomeTurmaAtual();

    if (_mudouAcademia) {
      return 'Mudança de núcleo/turma: $academiaAntes / $turmaAntes → $academiaDepois / $turmaDepois';
    }

    return 'Mudança de turma: $turmaAntes → $turmaDepois';
  }

  /// Studio 2.0: o usuário aguarda apenas o staging seguro, a fila durável
  /// e a confirmação da foto operacional. Drive é processado pelo backend.
  /// Nenhuma foto anterior é excluída aqui: a versão fica recuperável.
  Future<void> _salvarFotoComFilaSegura(String alunoIdSalvo) async {
    final relogio = Stopwatch()..start();
    final previousUrl = _networkImageUrl;
    final bytesUpload = _pickedImageBytesPreview ?? await _pickedImage!.readAsBytes();
    if (bytesUpload.isEmpty) throw StateError('Foto editada vazia.');
    final originalFull = _studioOriginalBytesPendente ?? bytesUpload;
    final finalArchive = _studioArchiveFinalBytesPendente ?? bytesUpload;
    final originalMime = AlunoPhotoHistoryService.inferMimeType(originalFull);
    final finalMime = AlunoPhotoHistoryService.inferMimeType(finalArchive);
    final nome = _controllers['nome']!.text.trim();
    final nascimento = _parseDate(_controllers['data_nascimento']!.text.trim());

    _atualizarSplashSalvandoAluno(
      titulo: 'Protegendo a memória fotográfica',
      mensagem: 'Guardando ORIGINAL e FINAL no Storage seguro…',
      progresso: 0.16,
    );
    Uint8List? anterior;
    DateTime? capturadaEm;
    if (previousUrl != null && previousUrl.isNotEmpty) {
      anterior = _fotoAnteriorBytesEmMemoria ?? await _obterBytesFotoSalvaNoStorage();
      if (anterior == null || anterior.isEmpty) {
        throw StateError('Não foi possível preservar a foto anterior. Nenhuma foto foi alterada.');
      }
      try {
        final aluno = await FirebaseFirestore.instance.collection('alunos').doc(alunoIdSalvo).get();
        final referencia = aluno.data()?['foto_atualizada_em'] ?? aluno.data()?['atualizado_em'];
        if (referencia is Timestamp) capturadaEm = referencia.toDate();
      } catch (e) {
        debugPrint('Data de captura anterior indisponível: $e');
      }
    }
    if (!mounted) return;
    debugPrint('UAI Photo Pipeline 2: preparar foto anterior ${relogio.elapsedMilliseconds}ms');
    _atualizarSplashSalvandoAluno(
      titulo: 'Agendando backup seguro',
      mensagem: 'Validando os arquivos e criando a fila de backup no servidor…',
      progresso: 0.32,
    );
    await AlunoPhotoHistoryService().enqueueStudioBackup(
      alunoId: alunoIdSalvo,
      alunoNome: nome.isEmpty ? 'Aluno' : nome,
      finalBytes: finalArchive,
      originalBytes: originalFull,
      previousBytes: anterior,
      finalMimeType: finalMime,
      originalMimeType: originalMime,
      origem: _fotoOrigemPendente,
      dataNascimento: nascimento,
      previousCapturedAt: capturadaEm,
    );
    if (!mounted) return;
    debugPrint('UAI Photo Pipeline 2: staging e fila ${relogio.elapsedMilliseconds}ms');
    _atualizarSplashSalvandoAluno(
      titulo: 'Atualizando foto operacional',
      mensagem: 'Enviando somente a foto de perfil na qualidade do Studio…',
      progresso: 0.53,
    );
    var extension = (_pickedImageExtension ?? 'jpg').toLowerCase();
    if (extension == 'jpeg') extension = 'jpg';
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref().child(
      'foto_alunos/${alunoIdSalvo}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await ref.putData(bytesUpload, SettableMetadata(
      contentType: contentType,
      customMetadata: {
        'edited': 'true', 'studio': 'uai_photo_studio_v2',
        'compressionPreset': _fotoCompressaoPendente.preset.name,
        'jpegQuality': _fotoCompressaoPendente.jpegQuality.toString(),
      },
    ));
    _networkImageUrl = await ref.getDownloadURL();
    debugPrint('UAI Photo Pipeline 2: operacional confirmado em ${relogio.elapsedMilliseconds}ms');
    // O arquivo anterior não é removido: o worker fará backup idempotente.
  }

  /// O commit do cadastro já ocorreu quando este diálogo aparece.
  /// Compartilhar WhatsApp é opcional e nunca reverte ou repete a conversão.
  Future<void> _oferecerConvitesPosCadastro() async {
    if (!mounted || _isEditing) return;
    try {
      final db = FirebaseFirestore.instance;
      final turma = await db.collection('turmas').doc(_turmaId).get();
      if (!mounted) return;
      final turmaData = turma.data() ?? const <String, dynamic>{};
      final grupoUrl = turmaData['whatsapp_url']?.toString().trim() ?? '';
      var conviteGrupo = turmaData['msg_convite_grupo_whatsapp']
          ?.toString().trim() ?? '';
      if (conviteGrupo.isEmpty) {
        conviteGrupo = '🥋 Olá {nome_aluno}! Seja bem-vindo(a) à turma {turma_nome} da UAI Capoeira!';
      }
      final nome = _controllers['nome']!.text.trim();
      for (final marcador in const ['nome_aluno', 'aluno_nome']) {
        conviteGrupo = conviteGrupo.replaceAll('{{$marcador}}', nome)
            .replaceAll('{$marcador}', nome);
      }
      for (final marcador in const ['turma_nome', 'nome_turma']) {
        conviteGrupo = conviteGrupo.replaceAll('{{$marcador}}', _nomeTurmaAtual())
            .replaceAll('{$marcador}', _nomeTurmaAtual());
      }
      for (final marcador in const ['academia_nome', 'nome_academia']) {
        conviteGrupo = conviteGrupo.replaceAll('{{$marcador}}', _nomeAcademiaAtual())
            .replaceAll('{$marcador}', _nomeAcademiaAtual());
      }
      if (grupoUrl.isNotEmpty) conviteGrupo = '$conviteGrupo\n\n👇 GRUPO DA TURMA: $grupoUrl';

      var areaAlunoAtiva = false;
      try {
        final config = await db.collection('configuracoes_site')
            .doc('area_aluno').get();
        areaAlunoAtiva = config.data()?['visivel_site'] == true;
      } catch (e) {
        debugPrint('Configuração da Área do Aluno indisponível: $e');
      }
      if (!mounted) return;
      final nascimento = _controllers['data_nascimento']!.text.trim();
      final palavras = nome.toUpperCase().split(RegExp(r'\s+'))
          .where((parte) => parte.isNotEmpty &&
              !const {'DE', 'DA', 'DO', 'DAS', 'DOS', 'E'}.contains(parte));
      final iniciais = palavras.map((parte) => parte.substring(0, 1))
          .join().replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
      final contatoAluno = _controllers['contato_aluno']!.text
          .replaceAll(RegExp(r'[^0-9]'), '');
      final contatoResponsavel = _controllers['contato_responsavel']!.text
          .replaceAll(RegExp(r'[^0-9]'), '');
      final telefoneBase = contatoAluno.length >= 8
          ? contatoAluno : contatoResponsavel;
      final ultimos4 = telefoneBase.length >= 4
          ? telefoneBase.substring(telefoneBase.length - 4) : '';
      final acessoValido = areaAlunoAtiva && nascimento.isNotEmpty &&
          iniciais.isNotEmpty && ultimos4.isNotEmpty;
      final mensagemAcesso = '🥋 ÁREA DO ALUNO - UAI CAPOEIRA 🥋\n\n'
          'Olá! Seguem os dados para acessar a Área do Aluno de $nome.\n\n'
          '🌐 https://uaicapoeira.com.br\n\n'
          'No site, toque em Área do Aluno e preencha:\n'
          '📅 Data de nascimento: $nascimento\n'
          '🔤 Iniciais do nome: $iniciais\n'
          '📱 Últimos 4 dígitos do telefone: $ultimos4\n\n'
          'Não compartilhe esses dados com outras pessoas.';
      final numeros = <String, String>{};
      if (contatoAluno.length >= 10 && contatoAluno.length <= 13) {
        numeros['Aluno'] = contatoAluno;
      }
      if (contatoResponsavel.length >= 10 &&
          contatoResponsavel.length <= 13 &&
          contatoResponsavel != contatoAluno) {
        numeros['Responsável'] = contatoResponsavel;
      }
      if (!mounted || numeros.isEmpty || (grupoUrl.isEmpty && !acessoValido)) {
        return;
      }

      Future<void> abrirWhatsApp(String numero, String texto) async {
        final comPais = numero.startsWith('55') ? numero : '55$numero';
        final uri = Uri.parse('https://wa.me/$comPais?text=${Uri.encodeComponent(texto)}');
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('O WhatsApp não pôde ser aberto.');
        }
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aluno cadastrado!'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$nome foi cadastrado na turma ${_nomeTurmaAtual()}.'),
                const SizedBox(height: 14),
                if (grupoUrl.isNotEmpty) ...[
                  const Text('Convite do grupo da turma',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 7),
                  for (final contato in numeros.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await abrirWhatsApp(contato.value, conviteGrupo);
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('Não foi possível abrir WhatsApp: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text('Convidar ${contato.key}'),
                      ),
                    ),
                ],
                if (acessoValido) ...[
                  const SizedBox(height: 12),
                  const Text('Dados da Área do Aluno',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 7),
                  for (final contato in numeros.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await abrirWhatsApp(contato.value, mensagemAcesso);
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('Não foi possível abrir WhatsApp: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.school_outlined),
                        label: Text('Enviar acesso para ${contato.key}'),
                      ),
                    ),
                ],
              ],
            )),
          ),
          actions: [TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Concluir'),
          )],
        ),
      );
    } catch (e) {
      debugPrint('Convite pós-cadastro indisponível: $e');
    }
  }

  Future<void> _saveForm() async {
    if (_salvandoAluno) return;
    if (widget.modoReativacao && !_exibirResumoReativacao) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Conclua as etapas para visualizar o resumo da reativação.'),
      ));
      return;
    }
    if (widget.modoReativacao) {
      for (final etapa in _secoesReativacao) {
        final erro = _erroEtapaReativacao(etapa);
        if (erro != null) {
          _navegarRevisao(_secoesReativacao.indexOf(etapa));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
          return;
        }
      }
    }
    if (widget.modoReativacao) {
      final pendentes = _secoesReativacao.where((id) => !_secoesConferidas.contains(id)).toList();
      if (pendentes.isNotEmpty) {
        _navegarRevisao(_secoesReativacao.indexOf(pendentes.first));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Confira todas as seções antes de continuar (${_secoesConferidas.length}/${_secoesReativacao.length}).'),
        ));
        return;
      }
      if (!_fichaRestritaCarregada) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A ficha complementar não carregou. Reabra a tela para continuar com segurança.'),
        ));
        return;
      }
    }
    if (!_isMounted || !_formKey.currentState!.validate()) return;

    // O fluxo de edição cadastral não transfere, ativa ou desativa alunos.
    // Apenas a criação de alunos novos exige vínculo inicial com turma.
    if (_isFromInscricao &&
        (widget.dadosInscricao!['id']?.toString().trim().isNotEmpty != true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Não é possível converter uma inscrição sem identificação.'),
      ));
      return;
    }
    if (!_isEditing && _statusAtividade == 'ATIVO(A)' &&
        (_academiaId == null || _academiaId!.isEmpty ||
         _turmaId == null || _turmaId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione academia e turma ao cadastrar um aluno ativo.'),
      ));
      return;
    }

    final enderecoCompletoParaMigrar = const ['rua', 'numero', 'bairro']
        .every((campo) => _controllers[campo]!.text.trim().isNotEmpty);
    if (_isEditing &&
        _enderecoLegadoAmbiguo &&
        enderecoCompletoParaMigrar &&
        !_enderecoRevisaoConfirmada) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Confira e confirme o endereço antigo antes de salvar. '
            'Nenhum dado foi alterado.'),
      ));
      return;
    }

     if (!_isEditing && _pickedImage == null &&
         (_networkImageUrl == null || _networkImageUrl!.isEmpty)) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
         content: Text('Adicione uma foto para cadastrar o aluno.'),
       ));
       return;
     }

    final deveValidarLotacao = !_isEditing;

    if (deveValidarLotacao && _turmaId != null && _turmaId!.isNotEmpty) {
      final turmaData = _turmasMap[_turmaId];
      final capacidadeMaxima = turmaData?['capacidade_maxima'] ?? 0;
      final alunosCount = turmaData?['alunos_count'] ?? 0;
      final alunosAtivos = turmaData?['alunos_ativos'] ?? 0;
      final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;

      if (capacidadeMaxima > 0 && totalAlunos >= capacidadeMaxima) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'A turma "${turmaData?['nome']}" está cheia! ($totalAlunos/$capacidadeMaxima alunos)',
              ),
              backgroundColor: context.uai.error,
            ),
          );
        }
        return;
      }
    }

    // Reconsulta o peso para não depender apenas do estado visual da tela.
    // Falhas na verificação não autorizam edição de dados restritos.
    var podeSalvarCapoeira = false;
    if (_currentUserId != null) {
      try {
        podeSalvarCapoeira = await _permissaoService
                .obterPesoPermissao(_currentUserId!) >= 100;
      } catch (e) {
        debugPrint('Não foi possível validar peso para os dados da capoeira: $e');
      }
    }
    if (!mounted) return;

    // Falhar antes de gravar aluno/foto caso a ficha sensível esteja incompleta.
    // A confirmação final da ficha ocorre na Function protegida.
    if (_fichaAssinaturaCarregada != _assinaturaFicha(_fichaComplementar)) {
      if (_isEditing && !_fichaRestritaCarregada) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ficha protegida indisponível. Reabra a tela antes de salvar alterações de saúde.'),
        ));
        return;
      }
      final errosFicha = validarFichaUai(_fichaComplementar);
      if (errosFicha.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Complete a ficha complementar: ${errosFicha.first}'),
        ));
        return;
      }
    }

    _safeSetState(() => _salvandoAluno = true);
    _mostrarSplashSalvandoAluno(
      mensagem: _pickedImage != null
          ? 'Enviando foto do aluno...'
          : _mudouTurmaOuAcademia
          ? 'Atualizando turma e registrando histórico...'
          : 'Salvando ficha do aluno...',
    );

    bool mudouTurmaOuAcademiaAoSalvar = false;
    bool escritaAlunoConfirmada = false;
    bool graduacaoAlterada = false;
    bool houveAlteracaoReal = false;
    String? fotoAntigaPendenteExcluir;
    Uint8List? fotoAntigaBytesBackup;
    final alunosCollection = FirebaseFirestore.instance.collection('alunos');
     _idCadastroEmAndamento ??= _isFromInscricao
         ? 'inscricao_${widget.dadosInscricao!['id']}'
         : alunosCollection.doc().id;
     String alunoIdSalvo = widget.alunoId ?? _idCadastroEmAndamento!;
    bool backupFotoAntigaConcluido = false;
    DateTime? fotoAntigaDataReferencia;

    try {
      if (_pickedImage != null) {
        try {
          if (_isEditing) {
            await _salvarFotoComFilaSegura(alunoIdSalvo);
          } else {
          // Cadastro manual novo: mantém o fluxo legado até o documento existir.
          final photoHistory = AlunoPhotoHistoryService();
          final nascimento = _parseDate(
            _controllers['data_nascimento']?.text.trim() ?? '',
          );
          final nomeAlunoBackup =
              _controllers['nome']?.text.trim().isNotEmpty == true
              ? _controllers['nome']!.text.trim()
              : 'Aluno';
          final previousImageUrl = _networkImageUrl;

          _atualizarSplashSalvandoAluno(
            titulo: 'Protegendo a memória atual',
            mensagem: previousImageUrl?.isNotEmpty == true
                ? 'Arquivando a foto atual antes de qualquer substituição…'
                : 'Preparando o arquivo fotográfico do aluno…',
            progresso: 0.12,
          );

          if (_isEditing &&
              previousImageUrl != null &&
              previousImageUrl.isNotEmpty) {
            fotoAntigaBytesBackup = _fotoAnteriorBytesEmMemoria ??
                await _obterBytesFotoSalvaNoStorage();
            try {
              final alunoAtual = await alunosCollection
                  .doc(widget.alunoId)
                  .get();
              final raw =
                  alunoAtual.data()?['foto_atualizada_em'] ??
                  alunoAtual.data()?['atualizado_em'];
              if (raw is Timestamp) fotoAntigaDataReferencia = raw.toDate();
              if (raw is DateTime) fotoAntigaDataReferencia = raw;
            } catch (_) {}

            if (fotoAntigaBytesBackup != null &&
                fotoAntigaBytesBackup.isNotEmpty) {
              try {
                await photoHistory.backupVersion(
                  alunoId: alunoIdSalvo,
                  alunoNome: nomeAlunoBackup,
                  finalBytes: fotoAntigaBytesBackup,
                  finalMimeType: AlunoPhotoHistoryService.inferMimeType(
                    fotoAntigaBytesBackup,
                  ),
                  origem: 'foto_anterior',
                  capturadoEm: fotoAntigaDataReferencia,
                  dataNascimento: nascimento,
                  nota:
                      'Versão preservada automaticamente antes da troca da foto de perfil.',
                );
                backupFotoAntigaConcluido = true;
              } catch (e) {
                debugPrint(
                  '⚠️ Backup Drive da foto anterior falhou; a foto atual será mantida no Storage: $e',
                );
                await photoHistory.registerPendingStorageBackup(
                  alunoId: alunoIdSalvo,
                  alunoNome: nomeAlunoBackup,
                  storageUrl: previousImageUrl,
                  dataNascimento: nascimento,
                  origem: 'foto_anterior',
                  nota:
                      'Backup pendente criado automaticamente antes da troca de foto.',
                );
              }
            }
          }

          final bytesUpload = _pickedImageBytesPreview ??
              await _pickedImage!.readAsBytes();
          var extension = (_pickedImageExtension ?? 'jpg').toLowerCase();
          if (extension == 'jpeg') extension = 'jpg';
          final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';

          final originalFull = _studioOriginalBytesPendente ?? bytesUpload;
          final archiveFinal = _studioArchiveFinalBytesPendente ?? bytesUpload;
          final originalMime = AlunoPhotoHistoryService.inferMimeType(
            originalFull,
          );
          final archiveMime = AlunoPhotoHistoryService.inferMimeType(
            archiveFinal,
          );

          _atualizarSplashSalvandoAluno(
            titulo: 'Preservando o original',
            mensagem:
                'Enviando ORIGINAL full-res e versão FINAL do Studio para a memória visual…',
            progresso: 0.28,
          );

          try {
            await photoHistory.backupVersion(
              alunoId: alunoIdSalvo,
              alunoNome: nomeAlunoBackup,
              originalBytes: originalFull,
              finalBytes: archiveFinal,
              originalMimeType: originalMime,
              finalMimeType: archiveMime,
              origem: _fotoOrigemPendente,
              dataNascimento: nascimento,
              nota:
                  'ORIGINAL full-res + FINAL do Studio preservados antes da ativação da nova foto.',
            );
          } catch (driveError) {
            debugPrint(
              '⚠️ Drive indisponível; criando staging seguro da nova foto: $driveError',
            );
            _atualizarSplashSalvandoAluno(
              titulo: 'Protegendo backup pendente',
              mensagem:
                  'O Drive não respondeu. Guardando uma cópia temporária segura para sincronizar depois…',
              progresso: 0.34,
            );
            try {
              await photoHistory.registerPendingBytesBackup(
                alunoId: alunoIdSalvo,
                alunoNome: nomeAlunoBackup,
                originalBytes: originalFull,
                finalBytes: archiveFinal,
                originalMimeType: originalMime,
                finalMimeType: archiveMime,
                origem: _fotoOrigemPendente,
                dataNascimento: nascimento,
                nota:
                    'ORIGINAL + FINAL aguardando sincronização automática com o Drive.',
              );
            } catch (stagingError) {
              throw StateError(
                'Não foi possível proteger o original da nova foto. Tente novamente. Detalhe: $stagingError',
              );
            }
          }

          _atualizarSplashSalvandoAluno(
            titulo: 'Enviando foto operacional',
            mensagem:
                'Aplicando exatamente a qualidade escolhida no Studio, sem recompressão extra…',
            progresso: 0.52,
          );

          final storagePath =
              'foto_alunos/${alunoIdSalvo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
          final ref = FirebaseStorage.instance.ref().child(storagePath);
          final metadata = SettableMetadata(
            contentType: contentType,
            customMetadata: {
              'edited': 'true',
              'extension': extension,
              'studio': 'uai_photo_studio_v11',
              'compressionPreset': _fotoCompressaoPendente.preset.name,
              'jpegQuality': _fotoCompressaoPendente.jpegQuality.toString(),
            },
          );
          // IMPORTANTE: os bytes já foram exportados pelo Studio com a qualidade
          // escolhida pelo usuário. Não há segunda compressão JPEG aqui.
          await ref.putData(bytesUpload, metadata);
          _networkImageUrl = await ref.getDownloadURL();

          if (previousImageUrl != null &&
              previousImageUrl.isNotEmpty &&
              previousImageUrl != _networkImageUrl) {
            fotoAntigaPendenteExcluir = previousImageUrl;
          }
          } // Fim do caminho legado para criação manual.
        } catch (e) {
          if (mounted) {
            _fecharSplashSalvandoAluno();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _mensagemErroAmigavelEditarAluno(
                    e,
                    contexto: 'processamento seguro da foto',
                  ),
                ),
              ),
            );
          }
          return;
        }
      }

      Map<String, dynamic> dataToSave = {};

      _controllers.forEach((key, controller) {
        if (dateKeys.contains(key)) {
          final date = _parseDate(controller.text.trim());
           if (date != null && date.year >= 1900 &&
               date.year <= DateTime.now().year + 1) {
             dataToSave[key] = Timestamp.fromDate(date);
           }
        } else {
          final text = controller.text.trim();
          if (text.isNotEmpty) {
            dataToSave[key] = text;
          }
        }
      });

      // Compatibilidade retroativa: campos novos e endereço composto público.
      final rua = _controllers['rua']!.text.trim();
      final numero = _controllers['numero']!.text.trim();
      final bairro = _controllers['bairro']!.text.trim();
      final cidade = _controllers['cidade']!.text.trim();
      final enderecoCompleto = rua.isNotEmpty && numero.isNotEmpty &&
          bairro.isNotEmpty;
       final podeConverterEndereco = enderecoCompleto &&
           (!_enderecoLegadoAmbiguo || _enderecoRevisaoConfirmada);
       if (podeConverterEndereco) {
        dataToSave['rua'] = rua.toUpperCase();
        dataToSave['numero'] = numero.toUpperCase();
        dataToSave['bairro'] = bairro.toUpperCase();
        dataToSave['cidade'] = cidade.toUpperCase();
        dataToSave['endereco'] = [
          '${rua.toUpperCase()} - ${numero.toUpperCase()}',
          bairro.toUpperCase(),
          if (cidade.isNotEmpty) cidade.toUpperCase(),
        ].join(', ');
        dataToSave['endereco_versao'] = 2;
       } else if (_isEditing && _enderecoLegadoOriginal.isNotEmpty) {
         // Uma sugestão incompleta nunca é um dado confirmado.
         dataToSave.remove('rua');
         dataToSave.remove('numero');
         dataToSave.remove('bairro');
         dataToSave.remove('endereco_versao');
         dataToSave['endereco'] = _enderecoLegadoOriginal;
       }
       _controllers['nome_contato_emergencia']!.text =
           _controllers['nome_responsavel']!.text.trim();
       _controllers['contato_emergencia']!.text =
           _controllers['contato_responsavel']!.text.trim();
       final grauEmergencia = _controllers['grau_emergencia']!.text.trim();
       final mesmoContatoResponsavel =
           _controllers['nome_contato_emergencia']!.text.trim().toUpperCase() ==
               _controllers['nome_responsavel']!.text.trim().toUpperCase() &&
           _controllers['nome_responsavel']!.text.trim().isNotEmpty;
       if (grauEmergencia.isNotEmpty && mesmoContatoResponsavel) {
         final familia = Map<String, dynamic>.from(
           _fichaComplementar['familia'] is Map
               ? _fichaComplementar['familia'] as Map
               : const <String, dynamic>{},
         );
         familia['grau_responsavel'] = grauEmergencia;
         _fichaComplementar['familia'] = familia;
       }
      // Informação sensível: salvar somente em fichas_inscricao via Cloud Function.
      // Não duplicar saúde no documento de leitura geral alunos.
      dataToSave['contatos_emergencia_adicionais'] = _contatosEmergenciaAdicionais;

      for (final campo in const ['cpf', 'contato_aluno', 'contato_responsavel', 'contato_emergencia']) {
        final valor = _controllers[campo]?.text.trim() ?? '';
         final digitos = valor.replaceAll(RegExp(r'[^0-9]'), '');
         if (digitos.isNotEmpty && (campo != 'cpf' || digitos.length == 11)) {
           dataToSave[campo] = digitos;
         }
      }
      if (_academiaId != null && _academiaId!.isNotEmpty) {
        dataToSave['academia_id'] = _academiaId;
        dataToSave['academia'] = _academiaNome ?? _academiasMap[_academiaId];
      }

      if (_turmaId != null && _turmaId!.isNotEmpty) {
        dataToSave['turma_id'] = _turmaId;
        final turmaData = _turmasMap[_turmaId];
        dataToSave['turma'] =
            _turmaNome ??
            (turmaData != null ? turmaData['nome'] as String? : null);
      }

      final graduacaoRef = _graduacaoId != null
          ? FirebaseFirestore.instance
                .collection('graduacoes')
                .doc(_graduacaoId)
          : null;
      final graduacaoData = _graduacaoId != null
          ? _graduacoesData[_graduacaoId]
          : null;

      final camposObrigatorios = {
        'sexo': _sexo,
        'status_atividade': _statusAtividade ?? 'ATIVO(A)',
        if (_pickedImage != null || !_isEditing)
          'foto_perfil_aluno': _networkImageUrl,
        'graduacao_id': _graduacaoId,
        'graduacao_ref': graduacaoRef,
         if (_controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), '').length == 11)
           'cpf': _controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'atualizado_em': FieldValue.serverTimestamp(),
        'editavel': true,
      };
      if (_pickedImage != null) {
        camposObrigatorios['foto_atualizada_em'] = FieldValue.serverTimestamp();
      }

      // Para uma edição cadastral, jamais sincronizar as cores/pontas
      // da graduação apenas porque o catálogo foi recarregado. A graduação
      // só deve ser sincronizada quando a seleção realmente mudou.
      if (graduacaoData != null && !_isEditing) {
        final camposGraduacao = {
          'graduacao_nome': graduacaoData['nome_graduacao'],
          'graduacao_cor1': graduacaoData['hex_cor1'],
          'graduacao_cor2': graduacaoData['hex_cor2'],
          'graduacao_ponta1': graduacaoData['hex_ponta1'],
          'graduacao_ponta2': graduacaoData['hex_ponta2'],
        };

        camposGraduacao.removeWhere((key, value) => value == null);
        dataToSave.addAll(camposGraduacao);
      }

       dataToSave.addAll(camposObrigatorios);
       if (!_isEditing && !_isFromInscricao && _pickedImage != null) {
         dataToSave['foto_cadastro_versao'] =
             'cadastro_${_idCadastroEmAndamento ?? DateTime.now().microsecondsSinceEpoch}';
         dataToSave['foto_cadastro_em'] = FieldValue.serverTimestamp();
         dataToSave['foto_cadastro_data_tipo'] = 'cadastro';
       }
       if (_isFromInscricao) {
         final origem = widget.dadosInscricao!;
         final inscricaoId = origem['id']?.toString().trim() ?? '';
         if (inscricaoId.isEmpty) {
           throw StateError('A inscrição não possui identificação válida.');
         }
         dataToSave['inscricao_id'] = inscricaoId;
         for (final campo in const [
           'email_conta_uai', 'conta_uai_uid', 'email_confirmado',
           'metodo_confirmacao_email', 'ficha_inscricao_id',
           'grau_responsavel', 'is_maior_idade',
         ]) {
           if (origem[campo] != null) dataToSave[campo] = origem[campo];
         }
         if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
           dataToSave['foto_inscricao_url'] =
               (origem['foto_url'] ?? _networkImageUrl).toString();
           final captura = origem['foto_capturada_em_ms'];
           dataToSave['foto_inscricao_em'] = captura is num && captura > 0
               ? Timestamp.fromMillisecondsSinceEpoch(captura.toInt())
               : origem['data_inscricao'] is Timestamp
                   ? origem['data_inscricao']
                   : FieldValue.serverTimestamp();
           dataToSave['foto_inscricao_data_tipo'] = captura is num && captura > 0
               ? 'captura' : 'envio';
         }
         // A versão é o gatilho da fila fotográfica automática do cadastro.
         dataToSave['foto_cadastro_versao'] =
             'inscricao_${inscricaoId}_${DateTime.now().microsecondsSinceEpoch}';
         dataToSave['foto_cadastro_em'] = FieldValue.serverTimestamp();
         dataToSave['foto_cadastro_data_tipo'] = 'cadastro';
         // Nunca perder o endereço público original quando a leitura é ambígua.
         if (!dataToSave.containsKey('endereco') &&
             (origem['endereco']?.toString().trim().isNotEmpty ?? false)) {
           dataToSave['endereco'] = origem['endereco'].toString();
         }
       }

      if (_isEditing) {
        // Alterações estruturais são exclusivas dos fluxos auditáveis de
        // Detalhes do Aluno. Não sobrescrever nem recalcular estes campos.
        for (final campo in const [
          'academia_id', 'academia', 'turma_id', 'turma',
          'status_atividade',
        ]) {
          dataToSave.remove(campo);
        }
      }
      if (!podeSalvarCapoeira) {
        for (final campo in const [
          'graduacao_id', 'graduacao_ref', 'graduacao_nome', 'graduacao_cor1',
          'graduacao_cor2', 'graduacao_ponta1', 'graduacao_ponta2',
          'data_graduacao_atual', 'tempo_capoeira',
        ]) {
          dataToSave.remove(campo);
        }
      }


      if (_isEditing) {
        final alunoRef = FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId);
        DocumentSnapshot<Map<String, dynamic>> alunoSnapshot;

        try {
          alunoSnapshot = await alunoRef.get(
            const GetOptions(source: Source.server),
          );
        } catch (_) {
          alunoSnapshot = await alunoRef.get();
        }

        final dadosAntes = alunoSnapshot.data() ?? <String, dynamic>{};
        // A mudança de graduação deve ser explícita e autorizada. Dados
        // legados podem ter cores distintas das atuais do catálogo e não
        // devem ser corrigidos silenciosamente ao editar endereço/contato.
        final mudouGraduacaoSelecionada = podeSalvarCapoeira &&
            dadosAntes['graduacao_id'] != _graduacaoId;
        if (!mudouGraduacaoSelecionada) {
          for (final campo in const [
            'graduacao_id', 'graduacao_ref', 'graduacao_nome',
            'graduacao_cor1', 'graduacao_cor2',
            'graduacao_ponta1', 'graduacao_ponta2',
          ]) {
            dataToSave.remove(campo);
          }
        } else {
          // A graduação foi realmente trocada por um administrador peso 100.
          dataToSave['graduacao_id'] = _graduacaoId;
          dataToSave['graduacao_ref'] = graduacaoRef;
          if (graduacaoData != null) {
            final camposGraduacao = <String, dynamic>{
              'graduacao_nome': graduacaoData['nome_graduacao'],
              'graduacao_cor1': graduacaoData['hex_cor1'],
              'graduacao_cor2': graduacaoData['hex_cor2'],
              'graduacao_ponta1': graduacaoData['hex_ponta1'],
              'graduacao_ponta2': graduacaoData['hex_ponta2'],
            }..removeWhere((key, value) => value == null);
            dataToSave.addAll(camposGraduacao);
          }
        }
        final fotoDataRaw =
            dadosAntes['foto_atualizada_em'] ?? dadosAntes['atualizado_em'];
        if (fotoDataRaw is Timestamp) {
          fotoAntigaDataReferencia = fotoDataRaw.toDate();
        } else if (fotoDataRaw is DateTime) {
          fotoAntigaDataReferencia = fotoDataRaw;
        }
        final dadosDepois = Map<String, dynamic>.from(dadosAntes)
          ..addAll(dataToSave);
        final camposAlterados = AlunoHistoricoEdicaoService.compararDados(
          dadosAntes,
          dadosDepois,
        );

        houveAlteracaoReal = camposAlterados.isNotEmpty;
        graduacaoAlterada = mudouGraduacaoSelecionada;
        mudouTurmaOuAcademiaAoSalvar = false;
        final resumoMudancaTurma = _resumoMudancaTurma();

        _atualizarSplashSalvandoAluno(
          titulo: 'Atualizando perfil',
          mensagem: _pickedImage != null
              ? 'Confirmando a nova foto e os dados no Firestore…'
              : 'Gravando os dados cadastrais no Firestore…',
          progresso: 0.76,
        );
        await alunoRef.update(dataToSave);
        escritaAlunoConfirmada = true;
        unawaited(SessionLogService.instance.recordEntityOperation(
          module: 'alunos.editar', entityType: 'aluno',
          entityId: widget.alunoId!, operation: 'atualizou', result: 'sucesso',
        ));
        if (graduacaoAlterada) {
          unawaited(SessionLogService.instance.recordAction(
            action: 'alterou_graduacao_aluno', module: 'alunos.editar',
            status: 'sucesso',
          ));
        }
        if (_pickedImage != null) {
          AlunoFotoResolver.invalidar(widget.alunoId!);
          await UaiStudentPhotoCache.invalidate(
            studentId: widget.alunoId!,
            imageUrls: <String?>[fotoAntigaPendenteExcluir, _networkImageUrl],
          );
        }

        try {
          await AlunoHistoricoEdicaoService().registrarEdicaoManual(
            alunoId: widget.alunoId!,
            dadosAntes: dadosAntes,
            dadosDepois: dadosDepois,
            origem: 'editar_aluno_screen',
            subtipoEdicao: 'dados_cadastrais',
            resumoPersonalizado: resumoMudancaTurma,
          );
        } catch (e) {
          debugPrint('Erro ao registrar histórico de edição do aluno: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Os dados foram salvos, mas não foi possível registrar o histórico.',
                ),
                backgroundColor: context.uai.warning,
              ),
            );
          }
        }

        // A Cloud Function grava a ficha e seu histórico oficial na mesma
        // transação; uma falha não é apresentada como sucesso completo.
        await _salvarFichaRestritaSeAlterada(widget.alunoId!);

        // Contadores de turma não são atualizados numa edição cadastral.
      } else {
        dataToSave['criado_em'] = FieldValue.serverTimestamp();
        dataToSave['data_do_cadastro'] = FieldValue.serverTimestamp();
        dataToSave['cadastro_realizado_em'] = FieldValue.serverTimestamp();
        final usuarioCadastro = FirebaseAuth.instance.currentUser;
        var nomeCadastro = usuarioCadastro?.displayName?.trim() ?? '';
        if (nomeCadastro.isEmpty && usuarioCadastro != null) {
          try {
            final perfil = await FirebaseFirestore.instance.collection('usuarios')
                .doc(usuarioCadastro.uid).get();
            nomeCadastro = (perfil.data()?['nome_completo'] ??
                perfil.data()?['nome'] ?? '').toString().trim();
          } catch (e) {
            debugPrint('Nome de cadastro indisponível: $e');
          }
        }
        if (nomeCadastro.isEmpty) nomeCadastro = usuarioCadastro?.email ?? 'Sistema';
        dataToSave['cadastro_realizado_por'] = nomeCadastro;
        dataToSave['cadastro_realizado_por_email'] = usuarioCadastro?.email;
        dataToSave['cadastro_realizado_por_uid'] = usuarioCadastro?.uid;
        _atualizarSplashSalvandoAluno(
          titulo: 'Criando ficha do aluno',
          mensagem: 'Registrando os dados e vinculando a memória fotográfica…',
          progresso: 0.76,
        );
         if (_isFromInscricao) {
           final inscricaoId = widget.dadosInscricao!['id'].toString();
           final db = FirebaseFirestore.instance;
           final alunoRef = alunosCollection.doc(alunoIdSalvo);
           final inscricaoRef = db.collection('inscricoes').doc(inscricaoId);
           final aprovadaRef = db.collection('inscricoes_aprovadas').doc(inscricaoId);
           await db.runTransaction((tx) async {
             // Todos os reads precedem writes. Operação idempotente.
             final atual = await tx.get(inscricaoRef);
             final aprovado = await tx.get(aprovadaRef);
             final alunoAtual = await tx.get(alunoRef);
             if (!atual.exists) {
               if (aprovado.data()?['aluno_id'] == alunoIdSalvo &&
                   alunoAtual.data()?['inscricao_id']?.toString() == inscricaoId) {
                 return; // Conversão já concluída na tentativa anterior.
               }
               throw StateError('Inscrição indisponível. Atualize a lista antes de tentar novamente.');
             }
             if (alunoAtual.exists &&
                 alunoAtual.data()?['inscricao_id']?.toString() != inscricaoId) {
               throw StateError('Conflito de cadastro: o aluno existente pertence a outra inscrição.');
             }
             if (aprovado.exists && aprovado.data()?['aluno_id'] != alunoIdSalvo) {
               throw StateError('Esta inscrição já possui outra conversão registrada.');
             }
             final dadosOriginais = atual.data()!;
             final timeline = <dynamic>[
               ...((dadosOriginais['timeline'] is List)
                   ? dadosOriginais['timeline'] as List : const []),
               {
                 'tipo': 'inscricao_aprovada',
                 'titulo': 'Inscrição aprovada',
                 'descricao': 'Convertida em aluno na turma ${_nomeTurmaAtual()}.',
                 'data': Timestamp.now(),
                 'origem': 'cadastro_unificado',
                 'usuario_uid': FirebaseAuth.instance.currentUser?.uid,
               }
             ];
             if (!alunoAtual.exists) {
               tx.set(alunoRef, dataToSave);
             } else {
               final complementos = Map<String, dynamic>.from(dataToSave);
               for (final campo in const [
                 'criado_em', 'data_do_cadastro', 'cadastro_realizado_em',
                 'cadastro_realizado_por', 'cadastro_realizado_por_email',
                 'cadastro_realizado_por_uid',
               ]) {
                 complementos.remove(campo);
               }
               tx.set(alunoRef, complementos, SetOptions(merge: true));
             }
             tx.set(aprovadaRef, {
               ...dadosOriginais,
               'aluno_id': alunoIdSalvo,
               'aluno_nome': _controllers['nome']!.text.trim(),
               'aluno_apelido': _controllers['apelido']!.text.trim(),
               'turma_id': _turmaId,
               'turma_nome': _nomeTurmaAtual(),
               'academia_id': _academiaId,
               'academia_nome': _nomeAcademiaAtual(),
               'aprovado_em': FieldValue.serverTimestamp(),
               'aprovado_por_uid': FirebaseAuth.instance.currentUser?.uid,
               'aprovado_por': FirebaseAuth.instance.currentUser?.displayName ??
                   FirebaseAuth.instance.currentUser?.email ?? 'Sistema',
               'status': 'aprovado',
               'etapa_atendimento': 'convertida_em_aluno',
               'timeline': timeline,
             });
             tx.delete(inscricaoRef);
           });
         } else {
           await alunosCollection.doc(alunoIdSalvo).set(dataToSave);
         }
        escritaAlunoConfirmada = true;
        if (_isFromInscricao) {
          // O histórico é reconstruível a partir de inscricoes_aprovadas:
          // IDs determinísticos impedem duplicatas mesmo após interrupções.
          try {
            final registro = await FirebaseFirestore.instance
                .collection('inscricoes_aprovadas')
                .doc(widget.dadosInscricao!['id'].toString()).get();
            final timeline = registro.data()?['timeline'];
            if (timeline is List && timeline.isNotEmpty) {
              await AlunoHistoricoEdicaoService().registrarProcessoInscricao(
                alunoId: alunoIdSalvo,
                inscricaoId: widget.dadosInscricao!['id'].toString(),
                timeline: timeline,
                alunoNome: _controllers['nome']!.text.trim(),
              );
            }
          } catch (e) {
            // Não desfazer um commit atômico que já criou o aluno e arquivou
            // a inscrição. O histórico original fica no documento aprovado.
            debugPrint('Histórico da inscrição aguardando sincronização: $e');
          }
        }
        unawaited(SessionLogService.instance.recordEntityOperation(
          module: 'alunos.editar', entityType: 'aluno',
          entityId: alunoIdSalvo, operation: 'criou', result: 'sucesso',
        ));

        if (_turmaId != null && _turmaId!.isNotEmpty) {
          await _atualizarContadorTurma(_turmaId!);
        }
      }

      if (!_isEditing) {
        // Em novo cadastro, somente tentar gravar ficha se o usuário a
        // preencheu. A gravação usa o aluno recém-criado como referência.
        await _salvarFichaRestritaSeAlterada(alunoIdSalvo);
      }

      _atualizarSplashSalvandoAluno(
        titulo: 'Finalizando com segurança',
        mensagem: _pickedImage != null
            ? 'Conferindo backups e limpando apenas arquivos protegidos…'
            : 'Concluindo a atualização cadastral…',
        progresso: 0.92,
      );

      if (fotoAntigaPendenteExcluir != null) {
        final origemPath = FirebaseStorage.instance
            .refFromURL(fotoAntigaPendenteExcluir)
            .fullPath;
        final fotoDeCadastro =
            origemPath.startsWith('fotos_inscricoes/') ||
            origemPath.startsWith('foto_alunos/cadastro_');
        if (backupFotoAntigaConcluido && !fotoDeCadastro) {
          try {
            await FirebaseStorage.instance
                .refFromURL(fotoAntigaPendenteExcluir)
                .delete();
            debugPrint(
              '✅ Foto antiga removida do Storage após backup no Drive',
            );
          } catch (e) {
            debugPrint(
              '⚠️ Backup concluído, mas não foi possível remover a foto antiga: $e',
            );
          }
        } else {
          debugPrint(
            '🛡️ Foto antiga mantida no Storage porque o backup no Drive não foi confirmado.',
          );
        }
      }

      if (mounted) {
        _fecharSplashSalvandoAluno();
        if (!_isEditing) await _oferecerConvitesPosCadastro();
        if (!mounted) return;
        final mensagem = widget.modoReativacao
             ? 'Dados conferidos e salvos. Prosseguindo com a reativação.'
             : !_isEditing
            ? 'Aluno criado!'
            : mudouTurmaOuAcademiaAoSalvar
            ? 'Aluno atualizado e mudança de turma registrada no histórico.'
            : houveAlteracaoReal
            ? 'Aluno atualizado e histórico registrado.'
            : 'Aluno salvo. Nenhuma alteração real foi identificada para histórico.';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensagem)));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!escritaAlunoConfirmada) {
        unawaited(SessionLogService.instance.recordEntityOperation(
          module: 'alunos.editar', entityType: 'aluno',
          entityId: alunoIdSalvo,
          operation: _isEditing ? 'atualizou' : 'criou', result: 'falha',
        ));
      }
      if (mounted) {
        _fecharSplashSalvandoAluno();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemErroAmigavelEditarAluno(
                e,
                contexto: 'salvamento do aluno',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        _fecharSplashSalvandoAluno();
        _safeSetState(() => _salvandoAluno = false);
      }
    }
  }

  Future<void> _atualizarContadorTurma(String turmaId) async {
    if (_academiaId == null || _academiaId!.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .where('turma_id', isEqualTo: turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosCount = snapshot.docs.length;

      await FirebaseFirestore.instance
          .collection('turmas')
          .doc(turmaId)
          .update({
            'alunos_count': alunosCount,
            'alunos_ativos': alunosCount,
            'atualizado_em': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma: $e');
    }
  }

  final List<String> dateKeys = [
    'data_nascimento',
    'data_graduacao_atual',
    'tempo_capoeira',
  ];

  // 🔥 FUNÇÃO DE EXCLUIR COM VALIDAÇÃO DE PERMISSÃO
  Future<void> _deleteAluno() async {
    if (_salvandoAluno) return;
    if (!_isEditing || !_isMounted) return;

    // 🔐 VERIFICAR PERMISSÃO DE EXCLUIR
    final temPermissao = await _verificarPermissao(
      'pode_excluir_aluno',
      acao: 'excluir aluno',
    );

    if (!temPermissao || !mounted) return; // ✅ Diálogo já é mostrado no _verificarPermissao

    final nomeAluno = _controllers['nome']!.text;
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConfirmarExclusaoAlunoDialog(nomeAluno: nomeAluno),
    );

    if (!mounted) return;
    if (shouldDelete == true) {
      bool exclusaoConfirmada = false;
      try {
        // Mostrar loading
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => Center(child: CircularProgressIndicator()),
          );
        }

        // Deletar foto do Storage
        if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
          try {
            await FirebaseStorage.instance
                .refFromURL(_networkImageUrl!)
                .delete();
            debugPrint('✅ Foto deletada do Storage');
          } catch (e) {
            debugPrint("⚠️ Aviso: Falha ao deletar foto do Storage: $e");
          }
        }

        // Deletar documento do Firestore
        await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .delete();

        exclusaoConfirmada = true;
        unawaited(SessionLogService.instance.recordEntityOperation(
          module: 'alunos.editar', entityType: 'aluno',
          entityId: widget.alunoId!, operation: 'excluiu', result: 'sucesso',
        ));

        debugPrint('✅ Aluno deletado do Firestore');

        // Atualizar contador da turma se houver
        if (_turmaId != null && _turmaId!.isNotEmpty) {
          await _atualizarContadorTurma(_turmaId!);
          debugPrint('✅ Contador da turma atualizado');
        }

        // Fechar loading
        if (mounted) {
          Navigator.of(context).pop(); // Fecha o loading

          // Mostrar sucesso
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: context.uai.card),
                  SizedBox(width: 8),
                  Text("Aluno excluído com sucesso."),
                ],
              ),
              backgroundColor: context.uai.success,
              duration: Duration(seconds: 2),
            ),
          );

          // Voltar para a tela anterior
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (!exclusaoConfirmada) {
          unawaited(SessionLogService.instance.recordEntityOperation(
            module: 'alunos.editar', entityType: 'aluno',
            entityId: widget.alunoId!, operation: 'excluiu', result: 'falha',
          ));
        }
        debugPrint('❌ Erro ao excluir aluno: $e');

        // Fechar loading se estiver aberto
        if (mounted) {
          Navigator.of(context).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _mensagemErroAmigavelEditarAluno(
                  e,
                  contexto: 'exclusão do aluno',
                ),
              ),
              backgroundColor: context.uai.error,
            ),
          );
        }
      }
    }
  }

  String _formatTimestamp(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy').format(timestamp.toDate());

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(dateStr);
    } catch (e) {
      debugPrint("Erro ao parsear data: $dateStr");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 MOSTRAR LOADING ENQUANTO CARREGA PERMISSÕES
    if (_isLoading || _carregandoPermissoes) {
      return Scaffold(
        backgroundColor: context.uai.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: context.uai.error),
              SizedBox(height: 20),
              Text('Carregando...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(widget.modoReativacao ? 'Revisar para reativar' : (_isEditing ? 'Editar Aluno' : 'Novo Aluno')),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ??
            context.uai.primary,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ??
            _readableOn(
              Theme.of(context).appBarTheme.backgroundColor ??
                  context.uai.primary,
            ),
        actions: [
          // ✅ BOTÃO SALVAR - SEMPRE VISÍVEL
          if (!widget.modoReativacao) IconButton(
            icon: Icon(Icons.save),
            onPressed: _salvandoAluno ? null : _saveForm,
            tooltip: widget.modoReativacao ? "Salvar revisão e continuar" : "Salvar Alterações",
          ),

          // ✅ BOTÃO EXCLUIR - SÓ APARECE SE FOR EDIÇÃO E TIVER PERMISSÃO
          if (_isEditing && !widget.modoReativacao &&
              _verificouPermissoes &&
              (_isAdmin || _permissoes['pode_excluir_aluno'] == true))
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _salvandoAluno ? null : _deleteAluno,
              tooltip: "Excluir Aluno",
            ),

        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: widget.modoReativacao ? _reativacaoScroll : null,
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children:
                    [
                          if (widget.modoReativacao) ...[
                            _buildCabecalhoReativacao(),
                            _buildEtapaFotoReativacao(),
                            _buildResumoFinalReativacao(),
                            if (_secaoAbertaId == 'foto' || _exibirResumoReativacao)
                              const SizedBox(height: 10),
                          ] else ...[
                            _buildFotoAlunoHeader(),
                            const SizedBox(height: 10),
                            if (_isEditing) _buildResumoCadastro(),
                          ],

                          // Dados Pessoais
                          _buildRevisaoSecao('pessoais', 'Dados Pessoais', [

                          _buildTextField(
                            _controllers['nome']!,
                            'Nome do Aluno',
                            isRequired: true,
                          ),
                          _buildTextField(_controllers['apelido']!, 'Apelido'),
                          _buildTextField(
                            _controllers['cpf']!,
                            'CPF',
                            keyboardType: TextInputType.number,
                          ),

                          DropdownButtonFormField<String>(
                            initialValue: _sexo,
                            items: ['MASCULINO', 'FEMININO']
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() { _sexo = v; _secoesConferidas.remove('pessoais'); }),
                            decoration: InputDecoration(
                              labelText: 'Sexo',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                v == null ? 'Campo obrigatório' : null,
                          ),

                          _buildDateField(
                            _controllers['data_nascimento']!,
                            'Data de Nascimento',
                            isRequired: true,
                          ),

                          // Contato
                                                    ]),
_buildRevisaoSecao('contato', 'Contato', [

                          _buildTextField(
                            _controllers['contato_aluno']!,
                            'Contato do Aluno',
                            keyboardType: TextInputType.phone,
                          ),
                          _buildTextField(
                            _controllers['nome_responsavel']!,
                            'Nome do Responsável',
                          ),
                          _buildTextField(
                            _controllers['contato_responsavel']!,
                            'Contato do Responsável',
                            keyboardType: TextInputType.phone,
                          ),
                          _buildParentescoEmergencia(),
                          _buildContatosEmergenciaAdicionais(),
                                                    ]),
_buildRevisaoSecao('endereco', 'Endereço', [

                          if (_possuiEnderecoEstruturado && !_enderecoLegadoAmbiguo)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text('Endereço estruturado existente: os campos foram preservados.'),
                            ),
                          if (_enderecoLegadoAmbiguo)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Endereço antigo: confirme os campos abaixo',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    SelectableText(_enderecoLegadoOriginal),
                                    const SizedBox(height: 6),
                                    const Text('O registro original será preservado até o endereço ser completamente preenchido.'),
                                  ],
                                ),
                              ),
                            ),
                          _buildTextField(_controllers['rua']!, 'Rua', enderecoTexto: true),
                          _buildTextField(_controllers['numero']!, 'Número',
                            enderecoTexto: true, maxLength: 5),
                          _buildTextField(_controllers['bairro']!, 'Bairro', enderecoTexto: true),
                          _buildTextField(_controllers['cidade']!, 'Cidade'),
                           if (_enderecoLegadoAmbiguo && !widget.modoReativacao)
                             CheckboxListTile(
                               contentPadding: EdgeInsets.zero,
                               title: const Text('Conferi rua, número e bairro'),
                               subtitle: const Text(
                                 'Após conferir, o endereço será convertido ao formato novo ao salvar.'),
                                value: _enderecoRevisaoConfirmada,
                                onChanged: (checked) {
                                  if (checked == false) {
                                    setState(() => _enderecoRevisadoAssinatura = null);
                                  } else if (checked == true) {
                                   final completo = ['rua', 'numero', 'bairro'].every(
                                     (campo) => _controllers[campo]!.text.trim().isNotEmpty,
                                   );
                                   if (completo) {
                                      setState(() => _enderecoRevisadoAssinatura =
                                          _assinaturaEnderecoAtual);
                                   } else {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       const SnackBar(content: Text(
                                         'Confira e complete rua, número e bairro antes de confirmar.')),
                                     );
                                   }
                                 }
                               },
                             ),

                           // Campos compartilhados com a inscrição pública.
                                                    ]),
_buildRevisaoSecao('saude', 'Ficha complementar • Saúde', [

                           FichaComplementarFields(
                             ficha: _fichaComplementar,
                             secao: 'saude',
                             modoReativacao: widget.modoReativacao,
                             onChanged: (nova) => setState(() { _fichaComplementar = nova; _secoesConferidas.remove('saude'); }),
                           ),
                                                    ]),
_buildRevisaoSecao('capoeira_ficha', 'Ficha complementar • Capoeira', [

                           Opacity(
                             opacity: (_podeEditarDadosCapoeira || widget.modoReativacao) ? 1 : 0.48,
                             child: IgnorePointer(
                               ignoring: !_podeEditarDadosCapoeira && !widget.modoReativacao,
                               child: FichaComplementarFields(
                                 ficha: _fichaComplementar,
                                 secao: 'capoeira',
                                 onChanged: (nova) => setState(() { _fichaComplementar = nova; _secoesConferidas.remove('capoeira_ficha'); }),
                               ),
                             ),
                           ),
                           // O vínculo familiar é editado no seletor acima.
                           // Evita os chips duplicados da seção Família.

                          ]),

                          // Academia e Turma: somente cadastro novo.
                          if (!_isEditing) ...[
                          // Academia e Turma
                          _buildSecaoCompacta('turma_nova', 'Academia e Turma', [

                          // Seleção de Academia
                          DropdownButtonFormField<String>(
                            key: ValueKey('academia_${_academiaId ?? ''}'),
                             initialValue: _academiaId,
                            items: [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Selecione uma academia'),
                              ),
                              ..._academiaItems,
                            ],
                            onChanged: _salvandoAluno
                                ? null
                                : (String? newValue) {
                                    setState(() {
                                      _academiaId = newValue;
                                      _academiaNome = newValue != null
                                          ? _academiasMap[newValue]
                                          : null;
                                      _turmaId = null;
                                      _turmaNome = null;
                                      _turmaItems = [];
                                      _turmaCheia = false;
                                      if (newValue != null) {
                                        _fetchTurmas(newValue);
                                      }
                                    });
                                  },
                            decoration: InputDecoration(
                              labelText: 'Academia/Núcleo',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.school),
                            ),
                            validator: (value) =>
                                _statusAtividade == 'ATIVO(A)' && value == null
                                    ? 'Aluno ativo precisa de uma academia'
                                    : null,
                          ),

                          SizedBox(height: 16),

                          // Seleção de Turma
                          Stack(
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey('turma_${_turmaId ?? ''}'),
                                 initialValue: _turmaId,
                                items: [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('Selecione uma turma'),
                                  ),
                                  ..._turmaItems,
                                ],
                                onChanged: _salvandoAluno
                                    ? null
                                    : (String? newValue) {
                                        setState(() {
                                          _turmaId = newValue;
                                          if (newValue != null) {
                                            final turmaData =
                                                _turmasMap[newValue];
                                            _turmaNome = turmaData != null
                                                ? turmaData['nome'] as String?
                                                : null;
                                            _turmaCheia =
                                                turmaData?['cheia'] == true;
                                          } else {
                                            _turmaNome = null;
                                            _turmaCheia = false;
                                          }
                                        });
                                      },
                                decoration: InputDecoration(
                                  labelText: 'Turma',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.group),
                                ),
                                validator: (value) {
                                  if (_statusAtividade == 'ATIVO(A)' && value == null) {
                                    return 'Aluno ativo precisa de uma turma';
                                  }
                                  return null;
                                },
                              ),
                              if (_carregandoTurmas)
                                Positioned.fill(
                                  child: Container(
                                    color: context.uai.card.withAlpha(179),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          if (_turmaCheia)
                            Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.uai.error.withAlpha(26),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: context.uai.error.withAlpha(77),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning,
                                      color: context.uai.primaryDark,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Esta turma está CHEIA! Não é possível adicionar mais alunos.',
                                        style: TextStyle(
                                          color: context.uai.primaryDark,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (_academiaId != null &&
                              _turmaItems.isEmpty &&
                              !_carregandoTurmas)
                            Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Nenhuma turma disponível para esta academia',
                                style: TextStyle(
                                  color: context.uai.warning,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),

                          if (_turmaId != null &&
                              _turmasMap.containsKey(_turmaId) &&
                              _turmasMap[_turmaId] != null)
                            Card(
                              margin: EdgeInsets.only(top: 8),
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Informações da Turma:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: context.uai.primary,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Horário: ${_turmasMap[_turmaId]!['horario'] ?? 'Não informado'}',
                                    ),
                                    Text(
                                      'Capacidade: ${_turmasMap[_turmaId]!['alunos_ativos'] ?? _turmasMap[_turmaId]!['alunos_count'] ?? 0}/${_turmasMap[_turmaId]!['capacidade_maxima'] ?? 0} alunos',
                                    ),
                                    if (_turmaCheia)
                                      Text(
                                        'STATUS: CHEIA ❌',
                                        style: TextStyle(
                                          color: context.uai.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Text(
                                      'Faixa Etária: ${_turmasMap[_turmaId]!['faixa_etaria'] ?? ''}',
                                    ),
                                    Text(
                                      'Nível: ${_turmasMap[_turmaId]!['nivel'] ?? ''}',
                                    ),
                                    if (_turmasMap[_turmaId]!['dias_semana'] !=
                                            null &&
                                        (_turmasMap[_turmaId]!['dias_semana']
                                                as List)
                                            .isNotEmpty)
                                      Text(
                                        'Dias: ${(_turmasMap[_turmaId]!['dias_semana'] as List).join(', ')}',
                                      ),
                                  ],
                                ),
                              ),
                            ),

                          ]),
                          ],

                          // Dados da Capoeira
                          _buildRevisaoSecao('capoeira_dados', 'Dados da Capoeira', [

                          if (!_podeEditarDadosCapoeira)
                            Text('Somente administradores com peso 100 podem alterar estes dados.',
                              style: TextStyle(color: context.uai.textSecondary)),
                          Opacity(
                            opacity: _podeEditarDadosCapoeira ? 1 : 0.48,
                            child: IgnorePointer(
                              ignoring: !_podeEditarDadosCapoeira,
                              child: Column(children: [

                          DropdownButtonFormField<String>(
                            initialValue: _graduacaoId,
                            items: _graduacaoItems,
                            onChanged: (v) => setState(() { _graduacaoId = v; _secoesConferidas.remove('capoeira_dados'); }),
                            decoration: InputDecoration(
                              labelText: 'Graduação Atual',
                              border: OutlineInputBorder(),
                            ),
                            isExpanded: true,
                            selectedItemBuilder: (BuildContext context) {
                              return _graduacaoItems.map<Widget>((
                                DropdownMenuItem<String> item,
                              ) {
                                return Text(
                                  item.value == null
                                      ? "Sem Graduação"
                                      : (_graduacoesData[item
                                                .value!]?['nome_graduacao'] ??
                                            ''),
                                  overflow: TextOverflow.ellipsis,
                                );
                              }).toList();
                            },
                          ),

                          _buildDateField(
                            _controllers['data_graduacao_atual']!,
                            'Data da Graduação',
                          ),
                          _buildDateField(
                            _controllers['tempo_capoeira']!,
                            'Início na Capoeira',
                          ),

                          ]),
                            ),
                          ),

                          ]),
                        ]
                        // Widgets das etapas ocultas não podem reservar
                        // margem vertical na versão mobile do assistente.
                        .where((e) => !widget.modoReativacao || e is! SizedBox)
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: e,
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContatosEmergenciaAdicionais() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _contatosEmergenciaAdicionais.length; i++)
          Card(
            child: ListTile(
              title: Text(_contatosEmergenciaAdicionais[i]['nome']?.toString() ?? 'Contato'),
              subtitle: Text([
                _contatosEmergenciaAdicionais[i]['telefone']?.toString() ?? '',
                _contatosEmergenciaAdicionais[i]['grau']?.toString() ?? '',
              ].where((v) => v.isNotEmpty).join(' • ')),
              onTap: _salvandoAluno ? null : () => _editarContatoEmergencia(i),
              trailing: IconButton(
                tooltip: 'Remover contato',
                onPressed: _salvandoAluno ? null : () => setState(() => _contatosEmergenciaAdicionais.removeAt(i)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _salvandoAluno ? null : () => _editarContatoEmergencia(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar contato de emergência'),
        ),
      ],
    );
  }

  Widget _buildParentescoEmergencia() {
    final selecionado = _controllers['grau_emergencia']!.text.trim();
    final reconhecido = grausResponsavelUai.contains(selecionado);
    return DropdownButtonFormField<String>(
      key: ValueKey('grau_emergencia_${reconhecido ? selecionado : 'sem_vinculo'}'),
      initialValue: reconhecido ? selecionado : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'O responsável é o quê do aluno?',
        prefixIcon: const Icon(Icons.family_restroom_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        helperText: selecionado.isNotEmpty && !reconhecido
            ? 'Vínculo anterior: $selecionado. Selecione o equivalente.'
            : null,
        helperMaxLines: 2,
      ),
      items: grausResponsavelUai
          .map((grau) => DropdownMenuItem(value: grau, child: Text(grau)))
          .toList(),
      onChanged: _salvandoAluno ? null : (grau) {
        if (grau == null) return;
        setState(() {
          _controllers['grau_emergencia']!.text = grau;
          final familia = Map<String, dynamic>.from(
            _fichaComplementar['familia'] is Map
                ? _fichaComplementar['familia'] as Map
                : const <String, dynamic>{},
          );
          familia['grau_responsavel'] = grau;
          familia['grau_outro'] = grau == 'Outro' ? 'Outro vínculo' : '';
          _fichaComplementar['familia'] = familia;
        });
      },
    );
  }

  Future<void> _editarContatoEmergencia(int? index) async {
    final anterior = index == null ? <String, dynamic>{} : _contatosEmergenciaAdicionais[index];
    final nome = TextEditingController(text: anterior['nome']?.toString() ?? '');
    final telefone = TextEditingController(text: anterior['telefone']?.toString() ?? '');
    String? grauSelecionado = grausResponsavelUai.contains(anterior['grau'])
        ? anterior['grau']?.toString()
        : null;
    try {
      final novo = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Adicionar contato' : 'Editar contato'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(controller: telefone, keyboardType: TextInputType.phone,
                inputFormatters: [_EditarTelefoneFormatter()],
                decoration: const InputDecoration(labelText: 'Telefone')),
              DropdownButtonFormField<String>(
                initialValue: grauSelecionado,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Parentesco'),
                items: grausResponsavelUai
                    .map((grau) => DropdownMenuItem(value: grau, child: Text(grau)))
                    .toList(),
                onChanged: (valor) => setDialogState(() => grauSelecionado = valor),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (nome.text.trim().isEmpty || telefone.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, {
                ...anterior,
                'nome': nome.text.trim(),
                'telefone': telefone.text.replaceAll(RegExp(r'[^0-9]'), ''),
                'grau': grauSelecionado ?? anterior['grau']?.toString() ?? '',
              });
            }, child: const Text('Salvar contato')),
          ],
        ),
        ),
      );
      if (!mounted || novo == null) return;
      setState(() {
        if (index == null) {
          _contatosEmergenciaAdicionais.add(novo);
        } else {
          _contatosEmergenciaAdicionais[index] = novo;
        }
      });
    } finally {
      nome.dispose();
      telefone.dispose();
    }
  }

  Widget _buildFotoAlunoHeader() {
    final isWindowsWide =
        _isWindowsPlatform && MediaQuery.of(context).size.width >= 900;
    final foto = CircleAvatar(
      radius: isWindowsWide ? 64 : 58,
      backgroundColor: context.uai.cardAlt,
      backgroundImage: _pickedImageBytesPreview != null
          ? MemoryImage(_pickedImageBytesPreview!)
          : (_networkImageUrl != null && _networkImageUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(_networkImageUrl!)
                    : null)
                as ImageProvider?,
      child:
          _pickedImage == null &&
              (_networkImageUrl == null || _networkImageUrl!.isEmpty)
          ? Icon(Icons.person_rounded, size: 54, color: context.uai.textMuted)
          : null,
    );

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        foto,
        Positioned(
          right: 0,
          bottom: 2,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: context.uai.primary,
              shape: BoxShape.circle,
              border: Border.all(color: context.uai.card, width: 3),
            ),
            child: const Icon(
              Icons.edit_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );

    if (!isWindowsWide) {
      return GestureDetector(
        onTap: _salvandoAluno ? null : _showImageSourceActionSheet,
        child: Column(
          children: [
            avatar,
            const SizedBox(height: 10),
            Text(
              'Toque na foto para trocar ou ajustar o enquadramento',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.uai.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.uai.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _salvandoAluno ? null : _showImageSourceActionSheet,
            child: avatar,
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _controllers['nome']!.text.trim().isEmpty
                      ? 'Foto do aluno'
                      : _controllers['nome']!.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Gerencie a foto usada no perfil, cards e chamadas. No Windows, o UAI Photo Studio oferece enquadramento e tratamento completo.',
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _salvandoAluno
                          ? null
                          : _showImageSourceActionSheet,
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: const Text('Trocar foto'),
                    ),
                    FilledButton.icon(
                      onPressed: _salvandoAluno ? null : _editarFotoAluno,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('Abrir UAI Photo Studio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: context.uai.success.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.uai.success.withAlpha(89)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.desktop_windows_rounded,
                  size: 16,
                  color: context.uai.success,
                ),
                const SizedBox(width: 6),
                Text(
                  'Studio Windows',
                  style: TextStyle(
                    color: context.uai.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Acordeao: apenas uma secao aberta, mantendo os controles montados para
  // preservar valores, validacoes e estado local de cada campo.
  Widget _buildSecaoCompacta(String id, String titulo, List<Widget> campos) {
    final t = context.uai;
    final aberta = _secaoAbertaId == id;
    final (cor, icone) = switch (id) {
      'pessoais' => (const Color(0xFF2875B9), Icons.badge_outlined),
      'contato' => (const Color(0xFF168D81), Icons.phone_outlined),
      'endereco' => (const Color(0xFFE08A20), Icons.location_on_outlined),
      'complementares' => (const Color(0xFF8053B8), Icons.assignment_outlined),
      'emergencia' => (const Color(0xFFD05C61), Icons.contact_emergency_outlined),
      'saude' => (const Color(0xFFDB5B88), Icons.favorite_border_rounded),
      'capoeira_ficha' => (const Color(0xFF6D7E31), Icons.menu_book_outlined),
      'turma_nova' => (const Color(0xFF2F889F), Icons.groups_outlined),
      'capoeira_dados' => (const Color(0xFFAD7134), Icons.workspace_premium_outlined),
      _ => (t.primary, Icons.description_outlined),
    };

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.modoReativacao ? null : () => setState(() => _secaoAbertaId = aberta ? null : id),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 5, color: cor),
                  const SizedBox(width: 12),
                  Icon(icone, color: cor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 19),
                      child: Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    aberta ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: t.textSecondary,
                  ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
          Visibility(
            visible: aberta,
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: campos
                    .map((campo) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: campo,
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextFormField _buildTextField(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool isRequired = false,
    bool enderecoTexto = false,
    bool nomePessoa = false,
    int? maxLength,
  }) {
    final ehTelefone = keyboardType == TextInputType.phone;
    final ehCpf = identical(controller, _controllers['cpf']);
    final formatadores = <TextInputFormatter>[
      if (ehTelefone || ehCpf || keyboardType == TextInputType.number)
        FilteringTextInputFormatter.digitsOnly
      else if (nomePessoa)
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ\s]'))
      else if (enderecoTexto)
        FilteringTextInputFormatter.allow(
          RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\.,\-ºª/]'),
        ),
      if (ehTelefone || ehCpf)
        LengthLimitingTextInputFormatter(11)
      else if (maxLength != null)
        LengthLimitingTextInputFormatter(maxLength),
      if (ehTelefone) _EditarTelefoneFormatter(),
      if (ehCpf) _EditarCpfFormatter(),
    ];
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      textCapitalization: (ehTelefone || ehCpf || keyboardType == TextInputType.number ||
          keyboardType == TextInputType.emailAddress)
          ? TextCapitalization.none : TextCapitalization.characters,
      keyboardType: keyboardType,
      inputFormatters: formatadores,
      validator: (value) => (isRequired && (value == null || value.isEmpty))
          ? 'Campo obrigatório' : null,
    );
  }

  TextFormField _buildDateField(
    TextEditingController controller,
    String label, {
    bool isRequired = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Icon(Icons.calendar_today),
        border: OutlineInputBorder(),
      ),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
      validator: (value) => (isRequired && (value == null || value.isEmpty))
          ? 'Campo obrigatório'
          : null,
    );
  }
}

class _ConfirmarExclusaoAlunoDialog extends StatefulWidget {
  final String nomeAluno;

  const _ConfirmarExclusaoAlunoDialog({required this.nomeAluno});

  @override
  State<_ConfirmarExclusaoAlunoDialog> createState() =>
      _ConfirmarExclusaoAlunoDialogState();
}

class _ConfirmarExclusaoAlunoDialogState
    extends State<_ConfirmarExclusaoAlunoDialog> {
  final TextEditingController _confirmacaoController = TextEditingController();
  bool _confirmado = false;

  @override
  void initState() {
    super.initState();
    _confirmacaoController.addListener(_validar);
  }

  void _validar() {
    final novoValor = _confirmacaoController.text == widget.nomeAluno;
    if (novoValor != _confirmado && mounted) {
      setState(() => _confirmado = novoValor);
    }
  }

  @override
  void dispose() {
    _confirmacaoController
      ..removeListener(_validar)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.uai.warning),
          const SizedBox(width: 10),
          const Expanded(child: Text('Confirmar exclusão permanente')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Para evitar exclusões acidentais, digite ou cole exatamente o nome completo do aluno:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.cardAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.uai.border),
              ),
              child: SelectableText(
                widget.nomeAluno,
                style: TextStyle(
                  color: context.uai.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmacaoController,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Nome completo para confirmar',
                hintText: widget.nomeAluno,
                prefixIcon: const Icon(Icons.edit_note_rounded),
                suffixIcon: _confirmado
                    ? Icon(Icons.verified_rounded, color: context.uai.success)
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.error.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.uai.error.withAlpha(89)),
              ),
              child: Text(
                'Esta ação é permanente e irreversível. Os dados do aluno serão removidos do sistema.',
                style: TextStyle(
                  color: context.uai.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _confirmado ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: context.uai.error,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('EXCLUIR PERMANENTEMENTE'),
        ),
      ],
    );
  }
}



// Formatos de entrada equivalentes aos utilizados na inscrição pública.
class _EditarTelefoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var formatted = digits;
    if (digits.length >= 2) {
      formatted = '(${digits.substring(0, 2)})';
      if (digits.length > 2) {
        formatted += ' ${digits.substring(2, digits.length > 7 ? 7 : digits.length)}';
      }
      if (digits.length > 7) {
        formatted += '-${digits.substring(7, digits.length > 11 ? 11 : digits.length)}';
      }
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _EditarCpfFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var formatted = digits;
    if (digits.length > 3) formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length > 6) formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    if (digits.length > 9) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, digits.length > 11 ? 11 : digits.length)}';
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _EnderecoLegadoUai {
  static String _normalizar(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[ÁÀÂÃ]'), 'A')
      .replaceAll(RegExp(r'[ÉÊ]'), 'E')
      .replaceAll(RegExp(r'[Í]'), 'I')
      .replaceAll(RegExp(r'[ÓÔÕ]'), 'O')
      .replaceAll(RegExp(r'[ÚÜ]'), 'U')
      .replaceAll('Ç', 'C')
      .replaceAll(RegExp(r'\s+'), ' ');

  static Map<String, String> interpretar(
    String endereco, {
    String? cidadeConhecida,
  }) {
    final resultado = <String, String>{};
    final original = endereco.trim();
    if (original.isEmpty) return resultado;

    final cidade = cidadeConhecida?.trim() ?? '';
    final partes = original.split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return resultado;

    // Não atribuir a cidade ao bairro, nem duplicá-la no endereço.
    if (cidade.isNotEmpty && partes.length > 1 &&
        _normalizar(partes.last) == _normalizar(cidade)) {
      partes.removeLast();
    } else if (cidade.isEmpty && partes.length >= 3) {
      resultado['cidade'] = partes.removeLast();
    }

    final texto = partes.join(', ');
    // Formato antigo rotulado: Rua: X N: 123 B: Y.
    final rotulado = RegExp(
      r'^\s*(?:RUA|R|LOGRADOURO)\s*:\s*(.+?)\s+(?:N|Nº|N°|NUMERO|NÚMERO)\s*:?\s*(\d+[A-Za-z]?)\s+(?:B|BAIRRO)\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(texto);
    if (rotulado != null) {
      resultado['rua'] = rotulado.group(1)!.trim();
      resultado['numero'] = rotulado.group(2)!.trim();
      resultado['bairro'] = rotulado.group(3)!.trim();
      return resultado;
    }

    // Novo formato: RUA - 123, BAIRRO; legado: RUA, 123, BAIRRO.
    final separado = RegExp(r'^(.+?)\s+-\s+(\d{1,6}[A-Za-z]?)$')
        .firstMatch(partes.first);
    if (separado != null) {
      resultado['rua'] = separado.group(1)!.trim();
      resultado['numero'] = separado.group(2)!.trim();
      if (partes.length > 1) resultado['bairro'] = partes[1];
      return resultado;
    }
    if (partes.length >= 3 &&
        RegExp(r'^\d{1,6}[A-Za-z]?$').hasMatch(partes[1])) {
      resultado['rua'] = partes[0];
      resultado['numero'] = partes[1];
      resultado['bairro'] = partes[2];
      return resultado;
    }
    final comNumero = RegExp(r'^(.+?)\s+(\d{1,6}[A-Za-z]?)$')
        .firstMatch(partes.first);
    if (comNumero != null && partes.length >= 2) {
      resultado['rua'] = comNumero.group(1)!.trim();
      resultado['numero'] = comNumero.group(2)!.trim();
      resultado['bairro'] = partes[1];
      return resultado;
    }

    // Variação Rua X N: 123 / Bairro, sem os dois-pontos em Rua.
    final comBairro = RegExp(
      r'^(.+?)\s+(?:N|Nº|N°|NUMERO|NÚMERO)\s*:?\s*(\d+[A-Za-z]?)\s*[/,]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(texto);
    if (comBairro != null) {
      resultado['rua'] = comBairro.group(1)!.trim();
      resultado['numero'] = comBairro.group(2)!.trim();
      resultado['bairro'] = comBairro.group(3)!.trim();
      return resultado;
    }

    // Texto sem separadores: sugerir rua/número/bairro, mas a interface
    // exige conferência antes de transformar o endereço original.
    final noMeio = RegExp(r'^(.+?)\s+(\d{1,6}[A-Za-z]?)\s+(.+)$')
        .firstMatch(partes.first);
    if (noMeio != null) {
      resultado['rua'] = noMeio.group(1)!.trim();
      resultado['numero'] = noMeio.group(2)!.trim();
      resultado['bairro'] = noMeio.group(3)!.trim();
      resultado['revisao_necessaria'] = 'true';
      return resultado;
    }

    // Não inventar número ou bairro onde não houver identificação confiável.
    resultado['rua'] = partes.first;
    if (partes.length > 1) resultado['bairro'] = partes[1];
    return resultado;
  }
}
