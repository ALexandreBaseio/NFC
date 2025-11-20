import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'models/token.dart';

const _secureKeyName = 'hive_key';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(TokenAdapter());

  // inicializa/gera chave e abre box (se chave existir usa encriptação)
  final keyBytes = await _ensureEncryptionKeyExists();
  if (keyBytes != null) {
    await Hive.openBox<Token>('tokens', encryptionCipher: HiveAesCipher(keyBytes));
  } else {
    await Hive.openBox<Token>('tokens');
  }

  runApp(const MyApp());
}

// Gera/recupera a chave do flutter_secure_storage.
// Retorna bytes da chave (32 bytes) ou null se não houver (não esperado).
Future<Uint8List?> _ensureEncryptionKeyExists() async {
  final storage = const FlutterSecureStorage();
  final existing = await storage.read(key: _secureKeyName);
  if (existing != null && existing.isNotEmpty) {
    try {
      final bytes = base64Url.decode(existing);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    } catch (_) {}
  }
  // Se não existir, gera e salva
  final rng = Random.secure();
  final key = List<int>.generate(32, (_) => rng.nextInt(256));
  final encoded = base64UrlEncode(key);
  await storage.write(key: _secureKeyName, value: encoded);
  return Uint8List.fromList(key);
}

// Recupera bytes da chave (se existir), sem gerar.
Future<Uint8List?> _getStoredKeyBytes() async {
  final storage = const FlutterSecureStorage();
  final existing = await storage.read(key: _secureKeyName);
  if (existing == null) return null;
  try {
    final bytes = base64Url.decode(existing);
    return Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Registro NFC - Tokens (Hive + Backup/Cripto)',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TokenHomePage(),
    );
  }
}

class TokenHomePage extends StatefulWidget {
  const TokenHomePage({super.key});
  @override
  State<TokenHomePage> createState() => _TokenHomePageState();
}

class _TokenHomePageState extends State<TokenHomePage> {
  Box<Token> get box => Hive.box<Token>('tokens');

  String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  String? _extractId(NfcTag tag) {
    final data = tag.data;
    if (data == null) return null;

    final Map<String, dynamic> dataMap = data as Map<String, dynamic>;
    if (dataMap['id'] != null && dataMap['id'] is Uint8List) {
      return _bytesToHex(dataMap['id'] as Uint8List);
    }

    String? found;
    void search(dynamic v) {
      if (found != null) return;
      if (v is Uint8List) {
        found = _bytesToHex(v);
      } else if (v is Map) {
        v.values.forEach(search);
      } else if (v is List) {
        v.forEach(search);
      }
    }

    search(data);
    return found;
  }

  Future<void> _startNfcSession() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      _showMessage('NFC não disponível neste dispositivo.');
      return;
    }

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        try {
        final id = _extractId(tag);
        NfcManager.instance.stopSession();
        if (id == null) {
          _showMessage('Não foi possível extrair ID do token.');
          return;
        }
        await _onTagRead(id);
      } catch (e) {
        NfcManager.instance.stopSession();
      }
      },
    );
  }

  Future<String> _saveImageFile(String id, XFile picked) async {
    final bytes = await picked.readAsBytes();
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final extension = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    final file = File('${imagesDir.path}/$id.$extension');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _onTagRead(String id) async {
    final nameController = TextEditingController();
    String? imagePath;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setStateDialog) {
        return AlertDialog(
          title: const Text('Token detectado'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ID: $id'),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome (ex: Chave do carro)'),
                ),
                const SizedBox(height: 8),
                if (imagePath != null)
                  SizedBox(height: 120, child: Image.file(File(imagePath!), fit: BoxFit.contain)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tirar foto (opcional)'),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 1200);
                    if (picked != null) {
                      final saved = await _saveImageFile(id, picked);
                      imagePath = saved;
                      setStateDialog(() {}); // atualizar diálogo
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Coloque um nome')));
                    return;
                  }
                  final token = Token(
                      id: id, name: name, addedAt: DateTime.now().toIso8601String(), imagePath: imagePath);
                  await box.put(id, token); // armazenamos com chave = id (evita duplicatas)
                  Navigator.of(ctx).pop();
                },
                child: const Text('Salvar')),
          ],
        );
      }),
    );
  }

  void _showMessage(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _confirmDelete(String key) async {
    final token = box.get(key);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remover token'),
            content: Text('Remover "${token?.name}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Não')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sim')),
            ],
          ),
        ) ??
        false;
    if (ok) {
      // remove imagem do disco se existir
      try {
        if (token?.imagePath != null) {
          final f = File(token!.imagePath!);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
      await box.delete(key);
    }
  }

  // ---------- BACKUP / RESTORE ----------

  // Exporta arquivo zip contendo arquivos do Hive (tokens.*) e a pasta images, além do hive_key.txt (se existir)
  Future<void> _exportBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dirPath = dir.path;

      final archiveObj = Archive();

      // Inclui arquivos do box que comecem com 'tokens' (tokens.hive, tokens.lock, etc)
      final docDir = Directory(dirPath);
      if (await docDir.exists()) {
        final files = docDir.listSync(recursive: false);
        for (var f in files) {
          if (f is File) {
            final name = f.path.split(Platform.pathSeparator).last;
            if (name.startsWith('tokens')) {
              final bytes = await f.readAsBytes();
              archiveObj.addFile(ArchiveFile('app/$name', bytes.length, bytes));
            }
          }
        }
      }

      // Inclui imagens (diretório images/)
      final imagesDir = Directory('${dirPath}/images');
      if (await imagesDir.exists()) {
        final imageFiles = imagesDir.listSync(recursive: true);
        for (var f in imageFiles) {
          if (f is File) {
            final relPath = f.path.substring(dirPath.length + 1); // relative path
            final bytes = await f.readAsBytes();
            archiveObj.addFile(ArchiveFile('app/$relPath', bytes.length, bytes));
          }
        }
      }

      // Inclui a chave do Hive (opcional) para facilitar a restauração
      final storage = const FlutterSecureStorage();
      final stored = await storage.read(key: _secureKeyName);
      if (stored != null && stored.isNotEmpty) {
        final keyBytes = utf8.encode(stored);
        archiveObj.addFile(ArchiveFile('app/hive_key.txt', keyBytes.length, keyBytes));
      }

      // Gera zip
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archiveObj);
      if (zipData == null) throw Exception('Erro gerando ZIP');

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final outFile = File('${dirPath}/nfc_backup_$timestamp.zip');
      await outFile.writeAsBytes(zipData);

      // Compartilha o arquivo via share sheet
      await Share.shareXFiles([XFile(outFile.path)], text: 'Backup NFC Tokens');

      _showMessage('Backup gerado: ${outFile.path}');
    } catch (e) {
      _showMessage('Erro exportando backup: $e');
    }
  }

  // Importa um ZIP selecionado pelo usuário. Fecha Hive antes de sobrescrever arquivos.
  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // fecha Hive para permitir sobrescrever arquivos
      await Hive.close();

      final dir = await getApplicationDocumentsDirectory();
      final dirPath = dir.path;

      // Extrai arquivos para o diretório appDocuments (sobrescreve)
      for (final file in archive) {
        final filename = file.name;
        // esperamos que dentro do zip os arquivos estejam com prefixo app/...
        final relative = filename.startsWith('app/') ? filename.substring(4) : filename;
        final outPath = '$dirPath/$relative';

        if (file.isFile) {
          final outFile = File(outPath);
          final parent = outFile.parent;
          if (!await parent.exists()) await parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      // se o zip continha hive_key.txt, restauramos para flutter_secure_storage
      final keyFile = File('$dirPath/hive_key.txt');
      if (await keyFile.exists()) {
        final stored = await keyFile.readAsString();
        final storage = const FlutterSecureStorage();
        await storage.write(key: _secureKeyName, value: stored);
        // opcional: deletar hive_key.txt do diretório extraído por segurança
        // await keyFile.delete();
      }

      // re-inicializa Hive com a chave atual (se existir)
      await Hive.initFlutter();
      Hive.registerAdapter(TokenAdapter());
      final keyBytes = await _getStoredKeyBytes();
      if (keyBytes != null) {
        await Hive.openBox<Token>('tokens', encryptionCipher: HiveAesCipher(keyBytes));
      } else {
        await Hive.openBox<Token>('tokens');
      }

      setState(() {}); // atualiza UI
      _showMessage('Backup importado com sucesso.');
    } catch (e) {
      _showMessage('Erro importando backup: $e');
      // tenta reabrir box caso erro (recuperação)
      try {
        final keyBytes = await _getStoredKeyBytes();
        if (keyBytes != null) await Hive.openBox<Token>('tokens', encryptionCipher: HiveAesCipher(keyBytes));
        else await Hive.openBox<Token>('tokens');
      } catch (_) {}
    }
  }

  // ---------- FIM BACKUP / RESTORE ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro NFC - Tokens (Hive + Backup/Cripto)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Exportar backup',
            onPressed: _exportBackup,
          ),
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Importar backup',
            onPressed: _importBackup,
          ),
          IconButton(
            icon: const Icon(Icons.nfc),
            tooltip: 'Registrar token (encoste o token)',
            onPressed: _startNfcSession,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Registro NFC - Tokens (Hive)',
                applicationVersion: '0.2',
                children: const [Text('App para registrar tokens NFC com Hive, backup e criptografia local.')],
              );
            },
          )
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Token> b, _) {
          final keys = b.keys.cast<String>().toList();
          if (keys.isEmpty) return const Center(child: Text('Nenhum token salvo.'));
          return ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, i) {
              final key = keys[i];
              final t = b.get(key);
              if (t == null) return const SizedBox.shrink();
              return ListTile(
                leading: (t.imagePath != null && File(t.imagePath!).existsSync())
                    ? CircleAvatar(backgroundImage: FileImage(File(t.imagePath!)))
                    : const CircleAvatar(child: Icon(Icons.vpn_key)),
                title: Text(t.name),
                subtitle: Text('ID: ${t.id}\nAdicionado: ${t.addedAt}'),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _confirmDelete(key),
                ),
                onTap: () {
                  showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            title: Text(t.name),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('ID: ${t.id}'),
                                const SizedBox(height: 8),
                                if (t.imagePath != null && File(t.imagePath!).existsSync())
                                  Image.file(File(t.imagePath!)),
                              ],
                            ),
                            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar'))],
                          ));
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.nfc),
        label: const Text('Registrar (encoste token)'),
        onPressed: _startNfcSession,
      ),
    );
  }
}