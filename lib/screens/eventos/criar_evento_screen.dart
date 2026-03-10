import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../models/evento_model.dart';
import '../../services/evento_service.dart';

class CriarEventoScreen extends StatefulWidget {
  final EventoModel? evento;

  const CriarEventoScreen({super.key, this.evento});

  @override
  State<CriarEventoScreen> createState() => _CriarEventoScreenState();
}

class _CriarEventoScreenState extends State<CriarEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  final EventoService _eventoService = EventoService();

  // Controllers
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController(); // 👈 NOVO!
  final _tipoController = TextEditingController();
  final _dataController = TextEditingController();
  final _horarioController = TextEditingController();
  final _localController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _organizadoresController = TextEditingController();
  final _linkFotosController = TextEditingController();
  final _linkPreviaController = TextEditingController();
  final _linkPlaylistController = TextEditingController();

  // Banner
  File? _bannerFile;
  String? _bannerUrl;
  bool _isUploadingBanner = false;

  // Valores
  double _valorInscricao = 0;
  int _maxParcelas = 1;
  int _descontoAVista = 0;
  bool _permiteParcelamento = false;
  DateTime? _dataLimitePrimeiraParcela;

  // Camisa
  bool _temCamisa = false;
  double _valorCamisa = 0;
  bool _camisaObrigatoria = false;
  final List<String> _todosTamanhos = [
    '4A', '6A', '8A', '10A', '12A', '14A',
    'PP', 'P', 'M', 'G', 'GG', 'EGG'
  ];
  List<String> _tamanhosSelecionados = [];

  // Certificado
  bool _temCertificado = false;

  // 🔥 Portfólio Web
  bool _mostrarNoPortfolioWeb = false;

  // Status
  String _status = 'andamento';
  bool _isLoading = false;

  // Tipos de evento
  final List<String> _tiposEvento = [
    'BATIZADO & TROCA DE CORDAS',
    'ALUNO DESTAQUE',
    'EVENTO EM OUTRA CIDADE',
    'CONFRATERNIZAÇÃO',
    'RODAS',
    'AULÃO',
    'CAMPEONATO',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.evento != null) {
      _preencherFormulario();
    }
  }

  void _preencherFormulario() {
    final e = widget.evento!;
    _nomeController.text = e.nome;
    _descricaoController.text = e.descricao; // 👈 NOVO!
    _tipoController.text = e.tipo;
    _dataController.text = e.dataFormatada;
    _horarioController.text = e.horario;
    _localController.text = e.local;
    _cidadeController.text = e.cidade;
    _organizadoresController.text = e.organizadores.join(', ');
    _bannerUrl = e.linkBanner;
    _linkFotosController.text = e.linkFotosVideos ?? '';
    _linkPreviaController.text = e.previaVideo ?? '';
    _linkPlaylistController.text = e.linkPlaylist ?? '';

    _valorInscricao = e.valorInscricao;
    _permiteParcelamento = e.permiteParcelamento;
    _maxParcelas = e.maxParcelas;
    _descontoAVista = e.descontoAVista;
    _dataLimitePrimeiraParcela = e.dataLimitePrimeiraParcela;

    _temCamisa = e.temCamisa;
    _valorCamisa = e.valorCamisa ?? 0;
    _tamanhosSelecionados = List.from(e.tamanhosDisponiveis);
    _camisaObrigatoria = e.camisaObrigatoria;

    _temCertificado = e.temCertificado;

    // 🔥 Carregar valor do portfólio web
    _mostrarNoPortfolioWeb = e.mostrarNoPortfolioWeb;

    _status = e.status;
  }

  Future<void> _selecionarData() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (data != null) {
      setState(() {
        _dataController.text = '${data.day.toString().padLeft(2, '0')}/'
            '${data.month.toString().padLeft(2, '0')}/'
            '${data.year}';
      });
    }
  }

  Future<void> _selecionarDataLimite() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (data != null) {
      setState(() {
        _dataLimitePrimeiraParcela = data;
      });
    }
  }

  Future<void> _selecionarImagem() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _bannerFile = File(image.path);
          _bannerUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _tirarFoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _bannerFile = File(image.path);
          _bannerUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao tirar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadBanner(File imageFile, String eventoId) async {
    try {
      setState(() => _isUploadingBanner = true);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('eventos')
          .child('banners')
          .child('$eventoId-${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await storageRef.putFile(imageFile);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      debugPrint('Erro no upload: $e');
      return null;
    } finally {
      setState(() => _isUploadingBanner = false);
    }
  }

  void _removerBanner() {
    setState(() {
      _bannerFile = null;
      _bannerUrl = null;
    });
  }

  void _mostrarOpcoesImagem() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Escolher da Galeria'),
              onTap: () {
                Navigator.pop(context);
                _selecionarImagem();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Tirar Foto'),
              onTap: () {
                Navigator.pop(context);
                _tirarFoto();
              },
            ),
            if (_bannerFile != null || _bannerUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remover Banner'),
                onTap: () {
                  Navigator.pop(context);
                  _removerBanner();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _selecionarTamanhos() async {
    List<String> tamanhosTemp = List.from(_tamanhosSelecionados);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Tamanhos Disponíveis'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: _todosTamanhos.length,
                itemBuilder: (context, index) {
                  final tamanho = _todosTamanhos[index];
                  final isSelected = tamanhosTemp.contains(tamanho);

                  return CheckboxListTile(
                    title: Text(
                      tamanho,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    value: isSelected,
                    activeColor: Colors.red.shade900,
                    onChanged: (selected) {
                      setStateDialog(() {
                        if (selected == true) {
                          tamanhosTemp.add(tamanho);
                        } else {
                          tamanhosTemp.remove(tamanho);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _tamanhosSelecionados = tamanhosTemp;
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                ),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Widget do Certificado (simples)
  Widget _buildCertificadoSimples() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _temCertificado ? Colors.green : Colors.grey.shade300,
          width: _temCertificado ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.card_membership,
                color: _temCertificado ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Certificados',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _temCertificado ? Colors.green : Colors.black,
                      ),
                    ),
                    Text(
                      _temCertificado
                          ? 'Este evento terá certificados'
                          : 'Este evento NÃO terá certificados',
                      style: TextStyle(
                        fontSize: 12,
                        color: _temCertificado ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _temCertificado,
                onChanged: (value) {
                  setState(() {
                    _temCertificado = value;
                  });
                },
                activeColor: Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget do Portfólio Web
  Widget _buildPortfolioWebSimples() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _mostrarNoPortfolioWeb ? Colors.blue : Colors.grey.shade300,
          width: _mostrarNoPortfolioWeb ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.web,
                color: _mostrarNoPortfolioWeb ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mostrar no Portfólio Web',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _mostrarNoPortfolioWeb ? Colors.blue : Colors.black,
                      ),
                    ),
                    Text(
                      _mostrarNoPortfolioWeb
                          ? 'Este evento aparecerá no site'
                          : 'Este evento NÃO aparecerá no site',
                      style: TextStyle(
                        fontSize: 12,
                        color: _mostrarNoPortfolioWeb ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _mostrarNoPortfolioWeb,
                onChanged: (value) {
                  setState(() {
                    _mostrarNoPortfolioWeb = value;
                  });
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Parse da data
      final partesData = _dataController.text.split('/');
      final data = DateTime(
        int.parse(partesData[2]),
        int.parse(partesData[1]),
        int.parse(partesData[0]),
      );

      // Parse dos organizadores
      final organizadores = _organizadoresController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // Determinar regras por tipo
      final tipo = _tipoController.text;
      final alteraGraduacao = tipo.contains('BATIZADO') ||
          tipo.contains('CAMPEONATO');
      final geraCertificado = tipo.contains('BATIZADO') ||
          tipo.contains('CAMPEONATO') ||
          tipo.contains('AULÃO') ||
          _temCertificado;

      // Cria o objeto evento com o campo descrição
      final evento = EventoModel(
        id: widget.evento?.id,
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim(), // 👈 NOVO CAMPO PREENCHIDO!
        tipo: tipo,
        data: data,
        horario: _horarioController.text.trim(),
        local: _localController.text.trim(),
        cidade: _cidadeController.text.trim(),
        organizadores: organizadores,
        status: _status,
        valorInscricao: _valorInscricao,
        permiteParcelamento: _permiteParcelamento,
        maxParcelas: _maxParcelas,
        descontoAVista: _descontoAVista,
        dataLimitePrimeiraParcela: _dataLimitePrimeiraParcela,
        temCamisa: _temCamisa,
        valorCamisa: _temCamisa ? _valorCamisa : null,
        tamanhosDisponiveis: _temCamisa ? _tamanhosSelecionados : [],
        camisaObrigatoria: _temCamisa ? _camisaObrigatoria : false,
        alteraGraduacao: alteraGraduacao,
        geraCertificado: geraCertificado,
        tipoPublico: 'todos',
        linkBanner: _bannerUrl,
        linkFotosVideos: _linkFotosController.text.isNotEmpty
            ? _linkFotosController.text.trim()
            : null,
        previaVideo: _linkPreviaController.text.isNotEmpty
            ? _linkPreviaController.text.trim()
            : null,
        linkPlaylist: _linkPlaylistController.text.isNotEmpty
            ? _linkPlaylistController.text.trim()
            : null,
        temCertificado: _temCertificado,
        configuracoesCertificado: null,
        modeloCertificadoId: null,
        modeloCertificadoPath: null,
        criadoEm: null,
        atualizadoEm: null,
        mostrarNoPortfolioWeb: _mostrarNoPortfolioWeb,
      );

      // Salva o evento para obter o ID
      final eventoId = await _eventoService.salvarEvento(evento);

      if (eventoId == null) {
        throw Exception('Erro ao salvar evento: ID não gerado');
      }

      // Se tem nova imagem, faz upload e atualiza o evento
      if (_bannerFile != null) {
        final bannerUrl = await _uploadBanner(_bannerFile!, eventoId);

        if (bannerUrl != null) {
          await _eventoService.atualizarBanner(eventoId, bannerUrl);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.evento == null
                ? 'Evento criado com sucesso!'
                : 'Evento atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.evento == null ? 'Criar Evento' : 'Editar Evento'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // DADOS BÁSICOS
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📅 DADOS BÁSICOS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Nome
                      TextFormField(
                        controller: _nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Evento *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.event),
                        ),
                        validator: (value) =>
                        value!.isEmpty ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 12),

                      // 👇 NOVO CAMPO DESCRIÇÃO
                      TextFormField(
                        controller: _descricaoController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição do Evento',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                          hintText: 'Descreva os detalhes do evento...',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),

                      // Tipo
                      DropdownButtonFormField<String>(
                        value: _tipoController.text.isNotEmpty
                            ? _tipoController.text
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Tipo do Evento *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: _tiposEvento.map((tipo) {
                          return DropdownMenuItem(
                            value: tipo,
                            child: Text(tipo),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _tipoController.text = value ?? '';
                          });
                        },
                        validator: (value) =>
                        value == null ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 12),

                      // Data e Horário
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selecionarData,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Data *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _dataController.text.isEmpty
                                      ? 'Selecione a data'
                                      : _dataController.text,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _horarioController,
                              decoration: const InputDecoration(
                                labelText: 'Horário *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.access_time),
                                hintText: 'HH:MM',
                              ),
                              validator: (value) =>
                              value!.isEmpty ? 'Campo obrigatório' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Local e Cidade
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _localController,
                              decoration: const InputDecoration(
                                labelText: 'Local *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_on),
                              ),
                              validator: (value) =>
                              value!.isEmpty ? 'Campo obrigatório' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _cidadeController,
                              decoration: const InputDecoration(
                                labelText: 'Cidade *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                              value!.isEmpty ? 'Campo obrigatório' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Organizadores
                      TextFormField(
                        controller: _organizadoresController,
                        decoration: const InputDecoration(
                          labelText: 'Organizadores (separados por vírgula)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.people),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // BANNER DO EVENTO
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🖼️ BANNER DO EVENTO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Área de preview da imagem
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: _bannerFile != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _bannerFile!,
                            fit: BoxFit.cover,
                          ),
                        )
                            : _bannerUrl != null
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _bannerUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return Container(
                                color: Colors.grey.shade200,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      size: 40,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Erro ao carregar imagem',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                            : InkWell(
                          onTap: _mostrarOpcoesImagem,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 50,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Clique para adicionar um banner',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_isUploadingBanner) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text('Enviando banner...'),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Botões de ação
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_bannerFile != null || _bannerUrl != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _mostrarOpcoesImagem,
                                icon: const Icon(Icons.edit),
                                label: const Text('Alterar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _mostrarOpcoesImagem,
                                icon: const Icon(Icons.add),
                                label: const Text('Adicionar Banner'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade900,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          if (_bannerFile != null || _bannerUrl != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _removerBanner,
                                icon: const Icon(Icons.delete),
                                label: const Text('Remover'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      if (_bannerUrl != null && _bannerFile == null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Você pode substituir o banner atual selecionando uma nova imagem.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CONFIGURAÇÕES DE TAXA
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💰 CONFIGURAÇÕES DE TAXA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Valor da inscrição
                      TextFormField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Valor da inscrição (R\$) *",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        onChanged: (value) {
                          _valorInscricao = double.tryParse(value) ?? 0;
                        },
                        initialValue: _valorInscricao.toString(),
                        validator: (value) {
                          if (value!.isEmpty) return 'Campo obrigatório';
                          if (double.tryParse(value) == null) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Parcelamento
                      SwitchListTile(
                        title: const Text('Permite parcelamento?'),
                        value: _permiteParcelamento,
                        activeColor: Colors.red.shade900,
                        onChanged: (value) {
                          setState(() {
                            _permiteParcelamento = value;
                          });
                        },
                      ),
                      if (_permiteParcelamento) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Máximo de parcelas',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _maxParcelas = int.tryParse(value) ?? 1;
                          },
                          initialValue: _maxParcelas.toString(),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Desconto à vista
                      TextFormField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Desconto à vista (%)',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        onChanged: (value) {
                          _descontoAVista = int.tryParse(value) ?? 0;
                        },
                        initialValue: _descontoAVista.toString(),
                      ),
                      const SizedBox(height: 12),

                      // Data limite 1ª parcela
                      InkWell(
                        onTap: _permiteParcelamento ? _selecionarDataLimite : null,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Data limite 1ª parcela',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.calendar_today),
                            enabled: _permiteParcelamento,
                          ),
                          child: Text(
                            _dataLimitePrimeiraParcela == null
                                ? 'Não definido'
                                : '${_dataLimitePrimeiraParcela!.day}/${_dataLimitePrimeiraParcela!.month}/${_dataLimitePrimeiraParcela!.year}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CONFIGURAÇÕES DE CAMISA
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '👕 CONFIGURAÇÕES DE CAMISA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tem camisa?
                      SwitchListTile(
                        title: const Text('Evento terá camisa?'),
                        value: _temCamisa,
                        activeColor: Colors.red.shade900,
                        onChanged: (value) {
                          setState(() {
                            _temCamisa = value;
                            if (!value) {
                              _tamanhosSelecionados = [];
                              _camisaObrigatoria = false;
                              _valorCamisa = 0;
                            }
                          });
                        },
                      ),

                      if (_temCamisa) ...[
                        const SizedBox(height: 12),

                        // Valor da camisa
                        TextFormField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Valor da camisa (R\$)",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          onChanged: (value) {
                            _valorCamisa = double.tryParse(value) ?? 0;
                          },
                          initialValue: _valorCamisa.toString(),
                        ),
                        const SizedBox(height: 12),

                        // Tamanhos disponíveis
                        InkWell(
                          onTap: _selecionarTamanhos,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Tamanhos disponíveis',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.checkroom),
                              enabled: _temCamisa,
                            ),
                            child: Text(
                              _tamanhosSelecionados.isEmpty
                                  ? 'Nenhum tamanho selecionado'
                                  : _tamanhosSelecionados.join(', '),
                              style: TextStyle(
                                color: _tamanhosSelecionados.isEmpty ? Colors.grey : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Camisa obrigatória?
                        SwitchListTile(
                          title: const Text('Camisa obrigatória?'),
                          value: _camisaObrigatoria,
                          activeColor: Colors.red.shade900,
                          onChanged: (value) {
                            setState(() {
                              _camisaObrigatoria = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CONFIGURAÇÃO DE CERTIFICADO
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📄 CERTIFICADOS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Defina se este evento terá certificados',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      _buildCertificadoSimples(),
                      if (_temCertificado) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Os certificados serão gerados com base nas graduações dos alunos',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CONFIGURAÇÃO DE PORTFÓLIO WEB
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🌐 PORTFÓLIO WEB',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Controle se este evento será exibido no site institucional',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      _buildPortfolioWebSimples(),
                      if (_mostrarNoPortfolioWeb) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.language, color: Colors.blue.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Este evento aparecerá na página de portfólio do site',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // LINKS
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔗 LINKS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _linkFotosController,
                        decoration: const InputDecoration(
                          labelText: 'Link de Fotos/Vídeos',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.photo_library, color: Colors.blue),
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _linkPreviaController,
                        decoration: const InputDecoration(
                          labelText: 'Link da Prévia',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.play_circle, color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _linkPlaylistController,
                        decoration: const InputDecoration(
                          labelText: 'Link da Playlist',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.playlist_play, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // BOTÕES
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isUploadingBanner) ? null : _salvar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        widget.evento == null ? 'CRIAR EVENTO' : 'ATUALIZAR',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose(); // 👈 NOVO!
    _tipoController.dispose();
    _dataController.dispose();
    _horarioController.dispose();
    _localController.dispose();
    _cidadeController.dispose();
    _organizadoresController.dispose();
    _linkFotosController.dispose();
    _linkPreviaController.dispose();
    _linkPlaylistController.dispose();
    super.dispose();
  }
}