// Modelo Token + TypeAdapter (manual) para Hive
import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class Token {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String addedAt;

  @HiveField(3)
  final String? imagePath; // caminho do arquivo de imagem no disco

  Token({
    required this.id,
    required this.name,
    required this.addedAt,
    this.imagePath,
  });
}

// Adapter manual (não requer build_runner)
class TokenAdapter extends TypeAdapter<Token> {
  @override
  final int typeId = 0;

  @override
  Token read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte() as int;
      final value = reader.read();
      fields[key] = value;
    }
    return Token(
      id: fields[0] as String,
      name: fields[1] as String,
      addedAt: fields[2] as String,
      imagePath: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Token obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.addedAt)
      ..writeByte(3)
      ..write(obj.imagePath);
  }
}