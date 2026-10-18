import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  Database? _database;

  DatabaseHelper._init();

  @visibleForTesting
  DatabaseHelper.forTesting(Database database) : _database = database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gestao_horarios.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return _abrirCaminho(path);
  }

  Future<Database> _abrirCaminho(String path) async {
    return await openDatabase(
      path,
      version: 3, // Versão atualizada para incluir biometria
      onCreate: _criarBD,
      onOpen: _verificarEAtualizarColunas,
    );
  }

  Future _criarBD(Database db, int version) async {
    // Tabela de Perfil
    await db.execute('''
      CREATE TABLE perfil (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nomeTrabalhador TEXT,
        nomeEmpresa TEXT,
        salarioBase REAL,
        valorSubsidioAlimentacao REAL,
        pinSeguranca TEXT,
        pinAtivo INTEGER,
        codigoPin TEXT,
        biometriaAtiva INTEGER DEFAULT 0
      )
    ''');

    // Tabela de Registos Diários
    await db.execute('''
      CREATE TABLE registos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT UNIQUE,
        tipoDia TEXT,
        horaInicio TEXT,
        horaFim TEXT,
        almocoInicio TEXT,
        almocoFim TEXT,
        horasEfetivas REAL,
        horasContratadas REAL,
        incluiSubsidio INTEGER,
        acaoExcesso TEXT,
        acaoFalta TEXT,
        acaoFolgaTrabalhada TEXT,
        subTipoFalta TEXT,
        acaoFaltaTratamento TEXT,
        horasExtraPagas REAL,
        horasDescontoSalario REAL
      )
    ''');

    await db.insert('perfil', {
      'nomeTrabalhador': 'Rui Barata',
      'nomeEmpresa': 'Gestão de Horários',
      'salarioBase': 1000.0,
      'valorSubsidioAlimentacao': 6.0,
      'pinSeguranca': '',
      'pinAtivo': 0,
      'codigoPin': '',
      'biometriaAtiva': 0,
    });
  }

  // Adiciona colunas em falta automaticamente sem apagar registos existentes
  Future<void> _verificarEAtualizarColunas(Database db) async {
    try {
      // Verificar colunas na tabela registos
      final colunasRegistos = await db.rawQuery('PRAGMA table_info(registos)');
      final nomesColunasRegistos =
          colunasRegistos.map((c) => c['name'] as String).toSet();

      final colunasNecessariasRegistos = {
        'acaoFolgaTrabalhada': 'TEXT',
        'subTipoFalta': 'TEXT',
        'acaoFaltaTratamento': 'TEXT',
        'horasExtraPagas': 'REAL',
        'horasDescontoSalario': 'REAL',
      };

      for (var entry in colunasNecessariasRegistos.entries) {
        if (!nomesColunasRegistos.contains(entry.key)) {
          await db.execute(
              'ALTER TABLE registos ADD COLUMN ${entry.key} ${entry.value}');
        }
      }

      // Verificar colunas na tabela perfil
      final colunasPerfil = await db.rawQuery('PRAGMA table_info(perfil)');
      final nomesColunasPerfil =
          colunasPerfil.map((c) => c['name'] as String).toSet();

      final colunasNecessariasPerfil = {
        'pinAtivo': 'INTEGER DEFAULT 0',
        'codigoPin': 'TEXT DEFAULT ""',
        'pinSeguranca': 'TEXT DEFAULT ""',
        'biometriaAtiva': 'INTEGER DEFAULT 0',
      };

      for (var entry in colunasNecessariasPerfil.entries) {
        if (!nomesColunasPerfil.contains(entry.key)) {
          await db.execute(
              'ALTER TABLE perfil ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    } catch (_) {
      rethrow;
    }
  }

  // --- MÉTODOS DE PERFIL ---
  Future<Map<String, dynamic>> getPerfil() async {
    final db = await database;
    final result = await db.query('perfil');
    if (result.isNotEmpty) {
      return result.first;
    }
    return {};
  }

  Future<int> salvarPerfil(Map<String, dynamic> perfil) async {
    final db = await database;
    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM perfil'));
    if (count == null || count == 0) {
      return await db.insert('perfil', perfil);
    } else {
      int id = perfil['id'] ?? 1;
      return await db
          .update('perfil', perfil, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> atualizarPerfil(Map<String, dynamic> perfil) async {
    return await salvarPerfil(perfil);
  }

  // --- MÉTODOS DE REGISTOS DIÁRIOS ---
  Future<Map<String, dynamic>?> getRegisto(String data) async {
    final db = await database;
    final results =
        await db.query('registos', where: 'data = ?', whereArgs: [data]);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<int> salvarRegisto(Map<String, dynamic> registo) async {
    final db = await database;
    return await db.insert(
      'registos',
      registo,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deletarRegisto(String data) async {
    final db = await database;
    return await db.delete('registos', where: 'data = ?', whereArgs: [data]);
  }

  // --- CONSULTAS DO CALENDÁRIO E ESTATÍSTICAS ---
  Future<Map<String, Map<String, dynamic>>> getRegistosMes(
      int ano, int mes) async {
    final db = await database;
    String mesStr = mes.toString().padLeft(2, '0');
    String prefixo = '$ano-$mesStr';

    final results = await db.query(
      'registos',
      where: 'data LIKE ?',
      whereArgs: ['$prefixo%'],
    );

    Map<String, Map<String, dynamic>> mapa = {};
    for (var reg in results) {
      mapa[reg['data'].toString()] = reg;
    }
    return mapa;
  }

  Future<List<Map<String, dynamic>>> getRegistosAno(int ano) async {
    final db = await database;
    final results = await db.query(
      'registos',
      where: 'data LIKE ?',
      whereArgs: ['$ano-%'],
      orderBy: 'data ASC',
    );
    return results;
  }

  Future<Map<String, double>> getTotaisGerais() async {
    final db = await database;
    final perfil = await getPerfil();
    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;

    final results = await db.query('registos');
    double creditoHoras = 0.0;
    double totalGanhas = 0.0;
    double totalDescontadas = 0.0;
    double ferias = 0.0;
    double folgas = 0.0;

    for (var reg in results) {
      String tipo = reg['tipoDia']?.toString() ?? '';
      double hContratadas =
          (reg['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      double hEfetivas = (reg['horasEfetivas'] as num?)?.toDouble() ?? 0.0;

      if (tipo == 'Férias') ferias += 1.0;
      if (tipo == 'Folga') folgas += 1.0;

      if (tipo == 'Trabalho') {
        double diff = hEfetivas - hContratadas;
        if (diff > 0.01) {
          String acao = reg['acaoExcesso']?.toString() ?? 'Banco de Horas';
          if (acao == 'Banco de Horas') {
            totalGanhas += diff;
          }
        } else if (diff < -0.01) {
          String acaoFalta =
              reg['acaoFalta']?.toString() ?? 'Descontar no Banco';
          if (acaoFalta == 'Descontar no Banco') {
            totalDescontadas += diff.abs();
          }
        }
      } else if (tipo == 'Folga Trabalhada') {
        String acao =
            reg['acaoFolgaTrabalhada']?.toString() ?? 'Banco de Horas';
        if (acao == 'Banco de Horas') {
          totalGanhas += hEfetivas;
        }
      } else if (tipo == 'Falta') {
        String acaoFaltaTratamento =
            reg['acaoFaltaTratamento']?.toString() ?? '';
        if (acaoFaltaTratamento == 'Descontar no Banco de Horas') {
          totalDescontadas += hContratadas;
        }
      }
    }

    creditoHoras = totalGanhas - totalDescontadas;

    return {
      'salarioBase': salarioBase,
      'credito': creditoHoras,
      'totalGanhas': totalGanhas,
      'totalDescontadas': totalDescontadas,
      'ferias': ferias,
      'folgas': folgas,
    };
  }

  // --- BACKUP E RESTAURO (COM SELETOR DE FICHEIROS NATIVO) ---
  /// Obtém uma cópia consistente, incluindo todas as alterações já guardadas.
  Future<Uint8List> lerCopiaSeguranca() async {
    final db = await database;
    // O ficheiro principal tem de conter os dados, sem depender de um WAL.
    final mode = await db.rawQuery('PRAGMA journal_mode = DELETE');
    if (mode.isEmpty ||
        mode.first.values.first.toString().toLowerCase() != 'delete') {
      throw StateError('Não foi possível preparar a base de dados para cópia.');
    }
    return db.transaction((txn) async {
      await txn.rawQuery('SELECT count(*) FROM sqlite_master');
      return File(db.path).readAsBytes();
    }, exclusive: true);
  }

  Future<bool> exportarEGuardarBaseDeDados() async {
    try {
      final bytes = await lerCopiaSeguranca();
      final mobile = defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar Cópia da Base de Dados',
        fileName:
            'gestao_horarios_backup_${DateTime.now().toIso8601String().substring(0, 10)}.db',
        bytes: mobile ? bytes : null,
      );
      if (outputFile == null) return false;
      // No Android/iOS o seletor já guardou os bytes e pode devolver um URI.
      if (!mobile) {
        await File(outputFile).writeAsBytes(bytes, flush: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<BackupSummary> resumoAtual() async {
    final db = await database;
    final row = (await db.rawQuery(
            'SELECT count(*) AS total, min(data) AS primeira, max(data) AS ultima FROM registos'))
        .first;
    return BackupSummary((row['total'] as num).toInt(),
        row['primeira'] as String?, row['ultima'] as String?);
  }

  Future<void> fechar() async {
    await _database?.close();
    _database = null;
  }

  static Future<BackupSummary> inspecionarCopia(String caminho) async {
    final db =
        await openDatabase(caminho, readOnly: true, singleInstance: false);
    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        throw const FormatException('A cópia de segurança está danificada.');
      }
      final version = await db.getVersion();
      if (version > 3)
        throw const FormatException(
            'Esta cópia requer uma versão mais recente da aplicação.');
      for (final entry in {
        'perfil': {'id', 'nomeTrabalhador', 'salarioBase'},
        'registos': {'data', 'tipoDia', 'horasEfetivas', 'horasContratadas'},
      }.entries) {
        final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
        if (!columns
            .map((row) => row['name'])
            .toSet()
            .containsAll(entry.value)) {
          throw const FormatException(
              'O ficheiro não é uma cópia válida desta aplicação.');
        }
      }
      final result = (await db.rawQuery(
              'SELECT count(*) AS total, min(data) AS primeira, max(data) AS ultima FROM registos'))
          .first;
      return BackupSummary((result['total'] as num).toInt(),
          result['primeira'] as String?, result['ultima'] as String?);
    } finally {
      await db.close();
    }
  }

  Future<bool> restaurarBaseDeDados(String caminhoFicheiro) async {
    File? staged;
    Database? current;
    bool attached = false;
    try {
      await inspecionarCopia(caminhoFicheiro);
      current = await database;
      final suffix = DateTime.now().microsecondsSinceEpoch;
      staged =
          await File(caminhoFicheiro).copy('${current.path}.restore-$suffix');
      // Valida e migra o ficheiro recebido antes de alterar os registos atuais.
      final prepared = await _abrirCaminho(staged.path);
      await prepared.close();
      await inspecionarCopia(staged.path);
      await _verificarEAtualizarColunas(current);
      final bytes = await lerCopiaSeguranca();
      await File('${current.path}.before-restore-$suffix')
          .writeAsBytes(bytes, flush: true);
      await current
          .execute('ATTACH DATABASE ? AS restore_source', [staged.path]);
      attached = true;
      // A transação é atómica, mesmo se o processo terminar durante o restauro.
      await current.transaction((txn) async {
        for (final table in ['perfil', 'registos']) {
          final targetColumns =
              await txn.rawQuery('PRAGMA main.table_info($table)');
          final sourceColumns =
              await txn.rawQuery('PRAGMA restore_source.table_info($table)');
          final available = sourceColumns.map((row) => row['name']).toSet();
          final columns = targetColumns
              .map((row) => row['name'] as String)
              .where(available.contains)
              .map((name) => '"${name.replaceAll('"', '""')}"')
              .join(', ');
          await txn.execute('DELETE FROM main.$table');
          await txn.execute(
              'INSERT INTO main.$table ($columns) SELECT $columns FROM restore_source.$table');
        }
      });
      return true;
    } catch (_) {
      return false;
    } finally {
      if (attached) await current!.execute('DETACH DATABASE restore_source');
      if (staged != null && await staged.exists()) await staged.delete();
    }
  }

  Future<bool> restaurarBaseDeDadosDeFicheiro(String caminhoFicheiro) async {
    return await restaurarBaseDeDados(caminhoFicheiro);
  }
}

class BackupSummary {
  const BackupSummary(this.records, this.firstDate, this.lastDate);
  final int records;
  final String? firstDate;
  final String? lastDate;
}
