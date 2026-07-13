import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_ciclo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_ciclos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/estudos_repository.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/services/importar_ciclo_completo_service.dart';

class ImportarCicloCompletoScreen extends StatefulWidget {
  final String modoInicial;
  final String cicloId;
  final int cicloNumero;
  final String cicloTitulo;
  final String estudoId;
  final int estudoNumero;
  final String estudoTitulo;

  const ImportarCicloCompletoScreen({
    super.key,
    this.modoInicial = 'novo_ciclo',
    this.cicloId = '',
    this.cicloNumero = 0,
    this.cicloTitulo = '',
    this.estudoId = '',
    this.estudoNumero = 0,
    this.estudoTitulo = '',
  });

  @override
  State<ImportarCicloCompletoScreen> createState() =>
      _ImportarCicloCompletoScreenState();
}

class _ImportarCicloCompletoScreenState
    extends State<ImportarCicloCompletoScreen> {
  final TextEditingController _jsonController = TextEditingController();
  final ImportarCicloCompletoService _service = ImportarCicloCompletoService();
  final EstudosCiclosRepository _ciclosRepository = EstudosCiclosRepository();
  final EstudosRepository _estudosRepository = EstudosRepository();

  late String _modo;
  late String _cicloIdSelecionado;
  late String _estudoIdSelecionado;
  ImportacaoPreview? _preview;
  List<String> _erros = const [];
  List<String> _avisos = const [];
  ImportarCicloCompletoResumo? _ultimoResumo;
  bool _importando = false;

  bool get _contextoCiclo => widget.cicloId.trim().isNotEmpty;
  bool get _contextoEstudo => widget.estudoId.trim().isNotEmpty;
  bool get _modoTravado => _contextoCiclo || _contextoEstudo;

  @override
  void initState() {
    super.initState();
    _modo = _modoValido(widget.modoInicial);
    if (_contextoEstudo) _modo = 'estudo_existente';
    if (_contextoCiclo && !_contextoEstudo) _modo = 'ciclo_existente';
    _cicloIdSelecionado = widget.cicloId;
    _estudoIdSelecionado = widget.estudoId;
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  String _modoValido(String modo) {
    return const [
          'novo_ciclo',
          'ciclo_existente',
          'estudo_existente',
        ].contains(modo)
        ? modo
        : 'novo_ciclo';
  }

  void _limpar() {
    setState(() {
      _jsonController.clear();
      _preview = null;
      _erros = const [];
      _avisos = const [];
      _ultimoResumo = null;
    });
  }

  void _validarJson(List<EstudoCicloModel> ciclos, List<EstudoModel> estudos) {
    final resultado = _validarConteudo(ciclos, estudos);
    setState(() {
      _preview = resultado.preview;
      _erros = resultado.erros;
      _avisos = resultado.avisos;
      _ultimoResumo = null;
    });
    _mostrarMensagem(
      resultado.erros.isEmpty
          ? 'JSON validado. Confira a previa antes de importar.'
          : 'Corrija os campos indicados antes de importar.',
    );
  }

  Future<void> _importar(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos,
  ) async {
    if (_importando) return;
    final resultado = _validarConteudo(ciclos, estudos);
    setState(() {
      _preview = resultado.preview;
      _erros = resultado.erros;
      _avisos = resultado.avisos;
      _ultimoResumo = null;
    });
    if (resultado.erros.isNotEmpty) {
      _mostrarMensagem('JSON invalido. Valide e corrija antes de importar.');
      return;
    }

    final confirmado = await _confirmarImportacao();
    if (!mounted || confirmado != true) return;

    setState(() => _importando = true);
    try {
      final resumo = await _service.importarConteudoEstudos(
        modo: _modo,
        ciclo: resultado.ciclo,
        estudos: resultado.estudos,
        perguntas: resultado.perguntas,
        cicloIdExistente: _modo == 'novo_ciclo' ? null : _cicloIdSelecionado,
        estudoIdExistente: _modo == 'estudo_existente'
            ? _estudoIdSelecionado
            : null,
      );
      if (!mounted) return;
      setState(() => _ultimoResumo = resumo);
      _mostrarMensagem(
        'Importacao concluida: ${resumo.estudosCriados} estudo(s), ${resumo.perguntasCriadas} pergunta(s).',
      );
    } catch (error) {
      if (!mounted) return;
      _mostrarMensagem(_mensagemErro(error));
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<bool?> _confirmarImportacao() {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: !_importando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final habilitado = controller.text == 'IMPORTAR';
            return AlertDialog(
              title: const Text('Confirmar importacao'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Digite IMPORTAR para criar conteudo e gabaritos privados.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmacao',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: habilitado
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('Importar'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  _ValidacaoImportacao _validarConteudo(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudosAdmin,
  ) {
    final erros = <String>[];
    final avisos = <String>[
      'Todos os itens serao importados como rascunho, independentemente do status informado no JSON.',
    ];
    final texto = _jsonController.text.trim();
    if (texto.isEmpty) {
      return _ValidacaoImportacao(erros: ['Cole um JSON para validar.']);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(texto);
    } catch (_) {
      return _ValidacaoImportacao(
        erros: ['JSON invalido. Confira chaves, aspas e virgulas.'],
      );
    }
    if (decoded is! Map) {
      return _ValidacaoImportacao(
        erros: ['A raiz do JSON precisa ser um objeto.'],
      );
    }
    final root = Map<String, dynamic>.from(decoded);

    final cicloSelecionado = _cicloSelecionado(ciclos);
    final estudoSelecionado = _estudoSelecionado(estudosAdmin);
    Map<String, dynamic>? ciclo;
    List<Map<String, dynamic>>? estudos;
    List<Map<String, dynamic>>? perguntas;

    if (_modo == 'novo_ciclo') {
      final cicloRaw = root['ciclo'];
      final estudosRaw = root['estudos'];
      if (cicloRaw is! Map) erros.add('ciclo e obrigatorio.');
      if (estudosRaw is! List || estudosRaw.isEmpty) {
        erros.add('estudos e obrigatorio e nao pode ser vazio.');
      }
      if (estudosRaw is List && estudosRaw.length > 20) {
        erros.add('O importador permite no maximo 20 estudos por ciclo.');
      }
      if (cicloRaw is Map) {
        ciclo = Map<String, dynamic>.from(cicloRaw);
        _obrigatorio(ciclo, 'ciclo.numero', erros);
        _obrigatorio(ciclo, 'ciclo.titulo', erros);
      }
      if (estudosRaw is List) {
        estudos = _validarEstudos(estudosRaw, erros, avisos);
      }
    } else if (_modo == 'ciclo_existente') {
      if (cicloSelecionado == null) {
        erros.add('Selecione um ciclo para importar estudos.');
      }
      if (root['ciclo'] != null) {
        avisos.add(
          'O campo ciclo do JSON sera ignorado porque voce escolheu importar em ciclo existente.',
        );
      }
      final estudosRaw = root['estudos'];
      if (estudosRaw is! List || estudosRaw.isEmpty) {
        erros.add('estudos e obrigatorio e nao pode ser vazio.');
      }
      if (estudosRaw is List && estudosRaw.length > 20) {
        erros.add('O importador permite no maximo 20 estudos por ciclo.');
      }
      if (estudosRaw is List) {
        estudos = _validarEstudos(estudosRaw, erros, avisos);
      }
    } else {
      if (cicloSelecionado == null) erros.add('Selecione um ciclo.');
      if (estudoSelecionado == null) erros.add('Selecione um estudo.');
      final perguntasRaw = _extrairPerguntasModoEstudo(root, erros);
      if (perguntasRaw.isEmpty) {
        erros.add('perguntas e obrigatorio e nao pode ser vazio.');
      }
      if (perguntasRaw.length > 10) {
        erros.add('O importador permite no maximo 10 perguntas por estudo.');
      }
      perguntas = _validarPerguntas(perguntasRaw, 'perguntas', erros, avisos);
    }

    final totalPerguntas =
        perguntas?.length ??
        (estudos ?? const <Map<String, dynamic>>[]).fold<int>(
          0,
          (sum, estudo) => sum + _lista(estudo['perguntas']).length,
        );
    final totalEstudos = estudos?.length ?? 0;

    return _ValidacaoImportacao(
      ciclo: erros.isEmpty ? ciclo : null,
      estudos: erros.isEmpty ? estudos : null,
      perguntas: erros.isEmpty ? perguntas : null,
      preview: erros.isEmpty
          ? ImportacaoPreview(
              modo: _modo,
              cicloNumero: _modo == 'novo_ciclo'
                  ? _inteiro(ciclo?['numero'])
                  : (cicloSelecionado?.numero ?? widget.cicloNumero),
              cicloTitulo: _modo == 'novo_ciclo'
                  ? _texto(ciclo?['titulo'])
                  : (cicloSelecionado?.titulo ?? widget.cicloTitulo),
              estudoNumero: estudoSelecionado?.numero ?? widget.estudoNumero,
              estudoTitulo: estudoSelecionado?.titulo ?? widget.estudoTitulo,
              estudos: totalEstudos,
              perguntas: totalPerguntas,
              gabaritos: totalPerguntas,
              statusImportacao: 'rascunho',
            )
          : null,
      erros: erros,
      avisos: avisos,
    );
  }

  List<dynamic> _extrairPerguntasModoEstudo(
    Map<String, dynamic> root,
    List<String> erros,
  ) {
    if (root['perguntas'] is List) return root['perguntas'] as List;
    final estudosRaw = root['estudos'];
    if (estudosRaw is List) {
      if (estudosRaw.length != 1) {
        erros.add(
          'Para importar perguntas em estudo existente, envie apenas uma lista perguntas ou um unico estudo com perguntas.',
        );
        return const [];
      }
      final estudo = estudosRaw.first;
      if (estudo is Map && estudo['perguntas'] is List) {
        return estudo['perguntas'] as List;
      }
    }
    return const [];
  }

  List<Map<String, dynamic>> _validarEstudos(
    List<dynamic> source,
    List<String> erros,
    List<String> avisos,
  ) {
    final result = <Map<String, dynamic>>[];
    final numeros = <int>{};
    final ordens = <int>{};
    for (var i = 0; i < source.length; i++) {
      final item = source[i];
      final prefixo = 'estudos[$i]';
      if (item is! Map) {
        erros.add('$prefixo precisa ser um objeto.');
        continue;
      }
      final estudo = Map<String, dynamic>.from(item);
      result.add(estudo);
      _obrigatorio(estudo, '$prefixo.numero', erros);
      _obrigatorio(estudo, '$prefixo.ordem', erros);
      _obrigatorio(estudo, '$prefixo.titulo', erros);
      if (_texto(estudo['resumo']).isEmpty &&
          _texto(estudo['textoAprofundado']).isEmpty) {
        erros.add('$prefixo precisa ter resumo ou textoAprofundado.');
      }
      final numero = _inteiro(estudo['numero']);
      final ordem = _inteiro(estudo['ordem']);
      if (numero > 0 && !numeros.add(numero)) {
        erros.add('Ha dois estudos com numero $numero no pacote.');
      }
      if (ordem > 0 && !ordens.add(ordem)) {
        erros.add('Ha dois estudos com ordem $ordem no pacote.');
      }
      final perguntasRaw = estudo['perguntas'];
      if (perguntasRaw is! List || perguntasRaw.isEmpty) {
        avisos.add('$prefixo sera importado sem perguntas.');
        continue;
      }
      if (perguntasRaw.length > 10) {
        erros.add(
          'O estudo ${numero > 0 ? numero : i + 1} possui mais de 10 perguntas. O limite e 10 perguntas por estudo.',
        );
      }
      estudo['perguntas'] = _validarPerguntas(
        perguntasRaw,
        '$prefixo.perguntas',
        erros,
        avisos,
      );
    }
    return result;
  }

  List<Map<String, dynamic>> _validarPerguntas(
    List<dynamic> source,
    String prefixo,
    List<String> erros,
    List<String> avisos,
  ) {
    final result = <Map<String, dynamic>>[];
    final ordens = <int>{};
    for (var i = 0; i < source.length; i++) {
      final raw = source[i];
      final path = '$prefixo[$i]';
      if (raw is! Map) {
        erros.add('$path precisa ser um objeto.');
        continue;
      }
      final pergunta = Map<String, dynamic>.from(raw);
      result.add(pergunta);
      _obrigatorio(pergunta, '$path.enunciado', erros);
      _obrigatorio(pergunta, '$path.justificativa', erros);
      final ordem = _inteiro(pergunta['ordem']);
      if (ordem > 0 && !ordens.add(ordem)) {
        erros.add('Ha duas perguntas com ordem $ordem no pacote.');
      }
      final alternativas = pergunta['alternativas'] is List
          ? pergunta['alternativas'] as List
          : const [];
      final ids = <String>{};
      if (alternativas.length != 4) {
        erros.add('$path precisa ter alternativas A/B/C/D.');
      }
      for (final alternativa in alternativas) {
        if (alternativa is Map) {
          ids.add(_texto(alternativa['id']).toUpperCase());
        }
      }
      for (final id in const ['A', 'B', 'C', 'D']) {
        if (!ids.contains(id)) erros.add('$path nao possui alternativa $id.');
      }
      final correta = _texto(pergunta['respostaCorreta']).toUpperCase();
      if (correta.isEmpty || !ids.contains(correta)) {
        erros.add('$path.respostaCorreta precisa existir nas alternativas.');
      }
      final normalizada = _normalizarDificuldade(pergunta['dificuldade']);
      if (_texto(pergunta['dificuldade']).isNotEmpty &&
          normalizada.foiNormalizada) {
        avisos.add(
          '$path.dificuldade sera importada como ${normalizada.valor}.',
        );
      }
      pergunta['dificuldade'] = normalizada.valor;
    }
    return result;
  }

  String _normalizarTextoSemAcento(dynamic valor) {
    var texto = (valor ?? '').toString().trim().toLowerCase();

    texto = texto
        .replaceAll('Ã¡', 'á')
        .replaceAll('Ã ', 'à')
        .replaceAll('Ã¢', 'â')
        .replaceAll('Ã£', 'ã')
        .replaceAll('Ã¤', 'ä')
        .replaceAll('Ã©', 'é')
        .replaceAll('Ãª', 'ê')
        .replaceAll('Ã¨', 'è')
        .replaceAll('Ã«', 'ë')
        .replaceAll('Ã­', 'í')
        .replaceAll('Ã¬', 'ì')
        .replaceAll('Ã®', 'î')
        .replaceAll('Ã¯', 'ï')
        .replaceAll('Ã³', 'ó')
        .replaceAll('Ã²', 'ò')
        .replaceAll('Ã´', 'ô')
        .replaceAll('Ãµ', 'õ')
        .replaceAll('Ã¶', 'ö')
        .replaceAll('Ãº', 'ú')
        .replaceAll('Ã¹', 'ù')
        .replaceAll('Ã»', 'û')
        .replaceAll('Ã¼', 'ü')
        .replaceAll('Ã§', 'ç');

    texto = texto
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c');

    texto = texto
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return texto;
  }

  _DificuldadeNormalizada _normalizarDificuldade(dynamic value) {
    final raw = _texto(value).trim().toLowerCase();
    final dificuldade = _normalizarTextoSemAcento(value);
    final mapped = switch (dificuldade) {
      'muito_facil' || 'facil' => 'facil',
      'intermediaria' || 'media' || 'medio' => 'media',
      'media_dificil' || 'dificil' || 'desafio' => 'dificil',
      _ => 'facil',
    };
    return _DificuldadeNormalizada(mapped, raw.isNotEmpty && raw != mapped);
  }

  void _obrigatorio(Map<String, dynamic> map, String path, List<String> erros) {
    final key = path.split('.').last;
    final value = map[key];
    if (value == null || _texto(value).isEmpty) {
      erros.add('$path e obrigatorio.');
    }
  }

  EstudoCicloModel? _cicloSelecionado(List<EstudoCicloModel> ciclos) {
    final id = _cicloIdSelecionado.trim();
    for (final ciclo in ciclos) {
      if (ciclo.id == id) return ciclo;
    }
    if (_contextoCiclo) {
      return EstudoCicloModel.empty().copyWith(
        id: widget.cicloId,
        numero: widget.cicloNumero,
        titulo: widget.cicloTitulo,
      );
    }
    return null;
  }

  EstudoModel? _estudoSelecionado(List<EstudoModel> estudos) {
    final id = _estudoIdSelecionado.trim();
    for (final estudo in estudos) {
      if (estudo.id == id) return estudo;
    }
    if (_contextoEstudo) {
      return EstudoModel.empty().copyWith(
        id: widget.estudoId,
        cicloId: widget.cicloId,
        cicloTituloSnapshot: widget.cicloTitulo,
        numero: widget.estudoNumero,
        titulo: widget.estudoTitulo,
      );
    }
    return null;
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  String _mensagemErro(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Nao foi possivel importar o conteudo.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return StreamBuilder<List<EstudoCicloModel>>(
      stream: _ciclosRepository.watchCiclosAdmin(),
      builder: (context, ciclosSnapshot) {
        final ciclos = (ciclosSnapshot.data ?? const <EstudoCicloModel>[])
            .where((c) => c.status != EstudoCicloStatus.arquivado)
            .toList();
        return StreamBuilder<List<EstudoModel>>(
          stream: _estudosRepository.watchEstudosAdmin(),
          builder: (context, estudosSnapshot) {
            final estudos = (estudosSnapshot.data ?? const <EstudoModel>[])
                .where((e) => e.status != EstudoCicloStatus.arquivado)
                .toList();
            _corrigirSelecao(ciclos, estudos);
            return Scaffold(
              backgroundColor: t.background,
              appBar: AppBar(
                title: const Text(
                  'Importar conteudo de estudos',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              body: ListView(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  16,
                  MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                  28,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _avisoSuperior(),
                          const SizedBox(height: 14),
                          _modoCard(ciclos, estudos),
                          const SizedBox(height: 14),
                          _editorJson(),
                          const SizedBox(height: 14),
                          _acoes(ciclos, estudos),
                          if (_importando) ...[
                            const SizedBox(height: 12),
                            LinearProgressIndicator(color: t.primary),
                          ],
                          if (_erros.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _listaMensagens(
                              'Campos a corrigir',
                              Icons.error_outline,
                              _erros,
                            ),
                          ],
                          if (_avisos.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _listaMensagens(
                              'Avisos',
                              Icons.info_outline,
                              _avisos,
                            ),
                          ],
                          if (_preview != null) ...[
                            const SizedBox(height: 14),
                            _previewCard(_preview!),
                          ],
                          if (_ultimoResumo != null) ...[
                            const SizedBox(height: 14),
                            _resumoImportacao(_ultimoResumo!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _corrigirSelecao(
    List<EstudoCicloModel> ciclos,
    List<EstudoModel> estudos,
  ) {
    if (_contextoCiclo) return;
    if ((_modo == 'ciclo_existente' || _modo == 'estudo_existente') &&
        _cicloIdSelecionado.isEmpty &&
        ciclos.isNotEmpty) {
      _cicloIdSelecionado = ciclos.first.id;
    }
    if (!_contextoEstudo && _modo == 'estudo_existente') {
      final doCiclo = estudos
          .where((e) => e.cicloId == _cicloIdSelecionado)
          .toList();
      if (_estudoIdSelecionado.isEmpty && doCiclo.isNotEmpty) {
        _estudoIdSelecionado = doCiclo.first.id;
      }
      if (_estudoIdSelecionado.isNotEmpty &&
          !doCiclo.any((e) => e.id == _estudoIdSelecionado)) {
        _estudoIdSelecionado = doCiclo.isEmpty ? '' : doCiclo.first.id;
      }
    }
  }

  Widget _avisoSuperior() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: t.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Use esta ferramenta para importar conteudo em massa. Capas e imagens podem ser adicionadas depois. Tudo entra como rascunho.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modoCard(List<EstudoCicloModel> ciclos, List<EstudoModel> estudos) {
    final t = context.uai;
    final estudosDoCiclo = estudos
        .where((e) => e.cicloId == _cicloIdSelecionado)
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Modo de importacao',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'novo_ciclo',
                label: Text('Criar novo ciclo'),
                icon: Icon(Icons.library_add_rounded),
              ),
              ButtonSegment(
                value: 'ciclo_existente',
                label: Text('Estudos em ciclo'),
                icon: Icon(Icons.playlist_add_check_rounded),
              ),
              ButtonSegment(
                value: 'estudo_existente',
                label: Text('Perguntas em estudo'),
                icon: Icon(Icons.quiz_rounded),
              ),
            ],
            selected: {_modo},
            onSelectionChanged: _modoTravado || _importando
                ? null
                : (value) => setState(() {
                    _modo = value.first;
                    _preview = null;
                    _erros = const [];
                  }),
          ),
          if (_modo == 'ciclo_existente' || _modo == 'estudo_existente') ...[
            const SizedBox(height: 12),
            if (_contextoCiclo)
              Text('Ciclo selecionado: ${_rotuloCicloContexto()}')
            else
              DropdownButtonFormField<String>(
                initialValue: ciclos.any((c) => c.id == _cicloIdSelecionado)
                    ? _cicloIdSelecionado
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Ciclo',
                  border: OutlineInputBorder(),
                ),
                items: ciclos
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(_rotuloCiclo(c)),
                      ),
                    )
                    .toList(),
                onChanged: _importando
                    ? null
                    : (value) => setState(() {
                        _cicloIdSelecionado = value ?? '';
                        _estudoIdSelecionado = '';
                        _preview = null;
                      }),
              ),
          ],
          if (_modo == 'estudo_existente') ...[
            const SizedBox(height: 12),
            if (_contextoEstudo)
              Text('Estudo selecionado: ${_rotuloEstudoContexto()}')
            else
              DropdownButtonFormField<String>(
                initialValue:
                    estudosDoCiclo.any((e) => e.id == _estudoIdSelecionado)
                    ? _estudoIdSelecionado
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Estudo',
                  border: OutlineInputBorder(),
                ),
                items: estudosDoCiclo
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(_rotuloEstudo(e)),
                      ),
                    )
                    .toList(),
                onChanged: _importando
                    ? null
                    : (value) => setState(() {
                        _estudoIdSelecionado = value ?? '';
                        _preview = null;
                      }),
              ),
          ],
        ],
      ),
    );
  }

  Widget _editorJson() {
    return TextField(
      controller: _jsonController,
      minLines: 18,
      maxLines: 26,
      decoration: const InputDecoration(
        labelText: 'JSON para importacao',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      textInputAction: TextInputAction.newline,
    );
  }

  Widget _acoes(List<EstudoCicloModel> ciclos, List<EstudoModel> estudos) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: _importando ? null : () => _validarJson(ciclos, estudos),
          icon: const Icon(Icons.fact_check_rounded),
          label: const Text('Validar JSON'),
        ),
        OutlinedButton.icon(
          onPressed: _importando ? null : _limpar,
          icon: const Icon(Icons.clear_rounded),
          label: const Text('Limpar'),
        ),
        FilledButton.icon(
          onPressed: _importando || _preview == null
              ? null
              : () => _importar(ciclos, estudos),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Importar'),
        ),
      ],
    );
  }

  Widget _listaMensagens(String title, IconData icon, List<String> items) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: t.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('- $item'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(ImportacaoPreview preview) {
    final linhas = <String>[];
    if (preview.modo == 'novo_ciclo') {
      linhas.add('Sera criado um novo ciclo.');
      linhas.add('Ciclo ${preview.cicloNumero} - ${preview.cicloTitulo}');
      linhas.add('${preview.estudos} estudo(s)');
    } else if (preview.modo == 'ciclo_existente') {
      linhas.add('Os estudos serao importados em ciclo existente.');
      linhas.add(
        'Ciclo selecionado: Ciclo ${preview.cicloNumero} - ${preview.cicloTitulo}',
      );
      linhas.add('${preview.estudos} estudo(s) a criar');
    } else {
      linhas.add('As perguntas serao importadas em estudo existente.');
      linhas.add(
        'Ciclo: Ciclo ${preview.cicloNumero} - ${preview.cicloTitulo}',
      );
      linhas.add(
        'Estudo: Estudo ${preview.estudoNumero} - ${preview.estudoTitulo}',
      );
    }
    linhas.add('${preview.perguntas} pergunta(s) a criar');
    linhas.add('${preview.gabaritos} gabarito(s) privado(s) a criar');
    linhas.add('Status de importacao: ${preview.statusImportacao}');
    return _listaMensagens(
      'Previa da importacao',
      Icons.preview_rounded,
      linhas,
    );
  }

  Widget _resumoImportacao(ImportarCicloCompletoResumo resumo) {
    return _listaMensagens(
      'Resumo retornado pela Function',
      Icons.check_circle_outline_rounded,
      [
        'modo: ${resumo.modo}',
        if (resumo.cicloId.isNotEmpty) 'cicloId: ${resumo.cicloId}',
        if (resumo.estudoId.isNotEmpty) 'estudoId: ${resumo.estudoId}',
        '${resumo.ciclosCriados} ciclo(s) criado(s)',
        '${resumo.estudosCriados} estudo(s) criado(s)',
        '${resumo.perguntasCriadas} pergunta(s) criada(s)',
        '${resumo.gabaritosCriados} gabarito(s) criado(s)',
        'Total criado: ${resumo.totalCriado}',
        'Status importado: ${resumo.statusImportado}',
      ],
    );
  }

  String _rotuloCiclo(EstudoCicloModel c) => 'Ciclo ${c.numero} - ${c.titulo}';
  String _rotuloEstudo(EstudoModel e) => 'Estudo ${e.numero} - ${e.titulo}';
  String _rotuloCicloContexto() =>
      'Ciclo ${widget.cicloNumero} - ${widget.cicloTitulo}';
  String _rotuloEstudoContexto() =>
      'Estudo ${widget.estudoNumero} - ${widget.estudoTitulo}';
}

class ImportacaoPreview {
  final String modo;
  final int cicloNumero;
  final String cicloTitulo;
  final int estudoNumero;
  final String estudoTitulo;
  final int estudos;
  final int perguntas;
  final int gabaritos;
  final String statusImportacao;

  const ImportacaoPreview({
    required this.modo,
    required this.cicloNumero,
    required this.cicloTitulo,
    required this.estudoNumero,
    required this.estudoTitulo,
    required this.estudos,
    required this.perguntas,
    required this.gabaritos,
    required this.statusImportacao,
  });
}

class _ValidacaoImportacao {
  final Map<String, dynamic>? ciclo;
  final List<Map<String, dynamic>>? estudos;
  final List<Map<String, dynamic>>? perguntas;
  final ImportacaoPreview? preview;
  final List<String> erros;
  final List<String> avisos;

  const _ValidacaoImportacao({
    this.ciclo,
    this.estudos,
    this.perguntas,
    this.preview,
    this.erros = const [],
    this.avisos = const [],
  });
}

class _DificuldadeNormalizada {
  final String valor;
  final bool foiNormalizada;
  const _DificuldadeNormalizada(this.valor, this.foiNormalizada);
}

String _texto(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text == 'null' ? '' : text;
}

int _inteiro(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_texto(value)) ?? 0;
}

List<dynamic> _lista(dynamic value) => value is List ? value : const [];
