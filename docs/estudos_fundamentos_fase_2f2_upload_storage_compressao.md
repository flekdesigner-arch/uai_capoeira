# Fase 2F2 - Upload de imagens no Firebase Storage

## Objetivo

Usar Firebase Storage como fonte oficial das imagens de Estudos/Fundamentos, substituindo a dependencia pratica de links do Google Drive para capas e imagens internas.

## Onde as imagens sao salvas

Capa do ciclo:

```text
estudos_fundamentos/ciclos/{cicloId}/capa/capa_{timestamp}.jpg
```

Capa do estudo:

```text
estudos_fundamentos/ciclos/{cicloId}/estudos/{estudoId}/capa/capa_{timestamp}.jpg
```

Imagem interna do estudo:

```text
estudos_fundamentos/ciclos/{cicloId}/estudos/{estudoId}/imagens/img_{timestamp}_{random}.jpg
```

Os paths nao usam titulo, nome de usuario ou texto digitado pelo admin.

## Campos Firestore

Ciclos:

- `capaUrl`
- `capaStoragePath`

Estudos:

- `capaUrl`
- `capaStoragePath`
- `imagensUrls`
- `imagensStoragePaths`

Documentos antigos continuam compativeis: paths ausentes viram string/lista vazia.

## Compressao e redimensionamento

O admin escolhe compressao:

- 5% -> quality 95
- 10% -> quality 90
- 15% -> quality 85
- 20% -> quality 80
- 25% -> quality 75
- 30% -> quality 70

Todas as imagens sao convertidas para JPG e redimensionadas para no maximo 1600px de largura. Imagens menores nao sao ampliadas.

O upload retorna resumo com tamanho original, tamanho final, reducao aproximada e dimensoes finais.

## Admin

Ciclos:

- campo manual `Capa URL opcional` continua existindo;
- botao `Enviar capa` faz upload para Storage quando o ciclo ja existe;
- para ciclo novo, salve primeiro e edite depois para enviar a capa.

Estudos:

- campo manual `Capa URL opcional` continua existindo;
- botao `Enviar capa do estudo` faz upload da capa quando o estudo ja existe;
- botao `Enviar imagem` adiciona uma imagem interna a `imagensUrls` e salva o path em `imagensStoragePaths`;
- para estudo novo, salve primeiro e edite depois para enviar midias.

## Remocao de imagem

Nesta fase, a remocao individual por lista continua manual no campo de URLs. A limpeza real dos arquivos enviados ao Storage acontece na exclusao administrativa de estudo/ciclo pela Cloud Function.

Se uma imagem for removida manualmente da lista antes da exclusao do estudo, o arquivo pode permanecer no Storage ate uma limpeza operacional futura.

## Limpeza real no Storage

A Cloud Function `excluirConteudoEstudosFundamentos` apaga arquivos do Storage ao apagar estudo ou ciclo.

Ao apagar estudo, ela coleta:

- `estudo.capaStoragePath`
- `estudo.imagensStoragePaths`

E so apaga paths que comecem exatamente com:

```text
estudos_fundamentos/ciclos/{cicloId}/estudos/{estudoId}/
```

Ao apagar ciclo, ela coleta:

- `ciclo.capaStoragePath`
- paths dos estudos apagados pelo fluxo de apagar estudo

E so apaga a capa do ciclo quando o path comeca exatamente com:

```text
estudos_fundamentos/ciclos/{cicloId}/
```

A Function ignora path vazio, path com `..`, path que comeca com `/`, path com `//` e qualquer path fora do prefixo seguro. Ela nao apaga por downloadUrl.

Resumo retornado pela Function:

- `arquivosStorageApagados`
- `arquivosStorageNaoEncontrados`
- `arquivosStorageIgnorados`
- `errosStorage`

## Limitacoes

- Google Drive nao e mais recomendado como fonte oficial de imagem.
- Storage Rules nao foram alteradas nesta fase. Se aparecer `permission-denied` no upload, sera necessario tratar em uma fase 2F2B de Storage Rules.
- Upload em massa nao foi implementado; o admin envia imagens uma por vez.
- Remocao individual fisica do Storage pela tela admin fica para fase futura.

## Validacoes

Rodar:

```bash
dart analyze lib/modules/estudos_fundamentos
node --check functions/index.js
```

## Confirmacao

Nenhum deploy foi executado.
Nenhum APK foi gerado.
Rules nao foram alteradas.
Storage Rules nao foram alteradas.
pubspec.yaml nao foi alterado.
