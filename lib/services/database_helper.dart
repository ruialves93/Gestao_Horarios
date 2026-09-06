import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('horarios_gestao.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, filePath);

    return await openDatabase(
      fullPath,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE perfil (
        id INTEGER PRIMARY KEY,
        nomeTrabalhador TEXT,
        nomeEmpresa TEXT,
        salarioBase REAL,
        horarioNormalDiario REAL,
        pinSeguranca TEXT,
        biometriaAtiva INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE registos_diarios (
        data TEXT PRIMARY KEY,
        tipoDia TEXT,
        horaInicio TEXT,
        horaFim TEXT,
        horaAlmocoInicio TEXT,
        horaAlmocoFim TEXT,
        horasAlmoco REAL,
        horasEfetivas REAL,
        horasCargaPrevista REAL,
        horasCreditoBanco REAL,
        horasDebitoBanco REAL,
        horasExtraPagas REAL,
        horasDescontoSalario REAL,
        tipoFalta TEXT
      )
    ''');

    await db.insert('perfil', {
      'id': 1,
      'nomeTrabalhador': '',
      'nomeEmpresa': '',
      'salarioBase': 1000.0,
      'horarioNormalDiario': 8.0,
      'pinSeguranca': '',
      'biometriaAtiva': 0,
    });
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE perfil ADD COLUMN pinSeguranca TEXT');
        await db.execute('ALTER TABLE perfil ADD COLUMN biometriaAtiva INTEGER');
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> getPerfil() async {
    final db = await instance.database;
    final res = await db.query('perfil', where: 'id = ?', whereArgs: [1]);
    if (res.isNotEmpty) return res.first;
    return {
      'nomeTrabalhador': '',
      'nomeEmpresa': '',
      'salarioBase': 1000.0,
      'horarioNormalDiario': 8.0,
      'pinSeguranca': '',
      'biometriaAtiva': 0,
    };
  }

  Future<void> updatePerfil(Map<String, dynamic> row) async {
    final db = await instance.database;
    await db.update('perfil', row, where: 'id = ?', whereArgs: [1]);
  }

  Future<void> saveRegisto(Map<String, dynamic> row) async {
    final db = await instance.database;
    await db.insert('registos_diarios', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getRegistoData(String data) async {
    final db = await instance.database;
    final res = await db.query('registos_diarios', where: 'data = ?', whereArgs: [data]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> getRegistosMes(int ano, int mes) async {
    final db = await instance.database;
    final mesFormatado = mes.toString().padLeft(2, '0');
    final res = await db.query(
      'registos_diarios',
      where: 'data LIKE ?',
      whereArgs: ['$ano-$mesFormatado%'],
    );
    Map<String, Map<String, dynamic>> mapa = {};
    for (var r in res) {
      mapa[r['data'].toString()] = r;
    }
    return mapa;
  }

  Future<List<Map<String, dynamic>>> getRegistosAno(int ano) async {
    final db = await instance.database;
    return await db.query(
      'registos_diarios',
      where: 'data LIKE ?',
      whereArgs: ['$ano%'],
      orderBy: 'data ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getMovimentosBanco() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM registos_diarios 
      WHERE horasCreditoBanco > 0 OR horasDebitoBanco > 0
      ORDER BY data DESC
    ''');
  }

  Future<Map<String, double>> getTotaisGerais() async {
    final db = await instance.database;
    final res = await db.rawQuery('''
      SELECT 
        SUM(horasCreditoBanco) as totalCredito,
        SUM(horasDebitoBanco) as totalDebito,
        COUNT(CASE WHEN tipoDia = 'Férias' THEN 1 END) as totalFerias,
        COUNT(CASE WHEN tipoDia = 'Folga' THEN 1 END) as totalFolgas
      FROM registos_diarios
    ''');

    if (res.isNotEmpty) {
      final row = res.first;
      return {
        'credito': (row['totalCredito'] as num?)?.toDouble() ?? 0.0,
        'debito': (row['totalDebito'] as num?)?.toDouble() ?? 0.0,
        'ferias': (row['totalFerias'] as num?)?.toDouble() ?? 0.0,
        'folgas': (row['totalFolgas'] as num?)?.toDouble() ?? 0.0,
      };
    }
    return {'credito': 0.0, 'debito': 0.0, 'ferias': 0.0, 'folgas': 0.0};
  }

  // --- CRIAR E PARTILHAR BACKUP (PERMITE ESCOLHER ONDE GUARDAR) ---
  Future<bool> exportarEGuardarBaseDeDados() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'horarios_gestao.db');
      final dbFile = File(path);

      if (await dbFile.exists()) {
        Directory? output = await getTemporaryDirectory();
        final backupPath = p.join(output.path, 'backup_horarios_ruibarata_${DateTime.now().millisecondsSinceEpoch}.db');
        final backupFile = await dbFile.copy(backupPath);

        await Share.shareXFiles(
          [XFile(backupFile.path)],
          text: 'Backup da Base de Dados - Gestão de Horários (Rui Barata © 2026)',
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // --- RESTAURAR BASE DE DADOS (PERMITE ESCOLHER O FICHEIRO NO TELEMÓVEL) ---
  Future<bool> restaurarBaseDeDadosPorFilePicker() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        final backupPath = result.files.single.path!;
        final backupFile = File(backupPath);

        if (!await backupFile.exists()) return false;

        if (_database != null) {
          await _database!.close();
          _database = null;
        }

        final dbPath = await getDatabasesPath();
        final currentPath = p.join(dbPath, 'horarios_gestao.db');
        await backupFile.copy(currentPath);
        await database;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}