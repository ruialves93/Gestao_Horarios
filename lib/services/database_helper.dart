import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gestao_horarios.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
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
        pinSeguranca TEXT
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
    });
  }

  // Adiciona colunas em falta automaticamente sem apagar registos existentes
  Future<void> _verificarEAtualizarColunas(Database db) async {
    try {
      final colunas = await db.rawQuery('PRAGMA table_info(registos)');
      final nomesColunas = colunas.map((c) => c['name'] as String).toSet();

      final colunasNecessarias = {
        'subTipoFalta': 'TEXT',
        'acaoFaltaTratamento': 'TEXT',
        'horasExtraPagas': 'REAL',
        'horasDescontoSalario': 'REAL',
      };

      for (var entry in colunasNecessarias.entries) {
        if (!nomesColunas.contains(entry.key)) {
          await db.execute('ALTER TABLE registos ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    } catch (_) {}
  }

  // --- MÉTODOS DE PERFIL ---
  Future<Map<String, dynamic>> getPerfil() async {
    final db = await instance.database;
    final result = await db.query('perfil');
    if (result.isNotEmpty) {
      return result.first;
    }
    return {};
  }

  Future<int> salvarPerfil(Map<String, dynamic> perfil) async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM perfil'));
    if (count == null || count == 0) {
      return await db.insert('perfil', perfil);
    } else {
      return await db.update('perfil', perfil, where: 'id = ?', whereArgs: [1]);
    }
  }

  Future<int> atualizarPerfil(Map<String, dynamic> perfil) async {
    return await salvarPerfil(perfil);
  }

  // --- MÉTODOS DE REGISTOS DIÁRIOS ---
  Future<Map<String, dynamic>?> getRegisto(String data) async {
    final db = await instance.database;
    final results = await db.query('registos', where: 'data = ?', whereArgs: [data]);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  Future<int> salvarRegisto(Map<String, dynamic> registo) async {
    final db = await instance.database;
    return await db.insert(
      'registos',
      registo,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deletarRegisto(String data) async {
    final db = await instance.database;
    return await db.delete('registos', where: 'data = ?', whereArgs: [data]);
  }

  // --- CONSULTAS DO CALENDÁRIO E ESTATÍSTICAS ---
  Future<Map<String, Map<String, dynamic>>> getRegistosMes(int ano, int mes) async {
    final db = await instance.database;
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
    final db = await instance.database;
    final results = await db.query(
      'registos',
      where: 'data LIKE ?',
      whereArgs: ['$ano-%'],
      orderBy: 'data ASC',
    );
    return results;
  }

  Future<Map<String, double>> getTotaisGerais() async {
    final db = await instance.database;
    final perfil = await getPerfil();
    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;

    final results = await db.query('registos');
    double creditoHoras = 0.0;
    double ferias = 0.0;
    double folgas = 0.0;

    for (var reg in results) {
      String tipo = reg['tipoDia']?.toString() ?? '';
      if (tipo == 'Férias') ferias += 1.0;
      if (tipo == 'Folga') folgas += 1.0;

      if (tipo == 'Trabalho' || tipo == 'Folga Trabalhada') {
        double hEfetivas = (reg['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
        double hContratadas = (reg['horasContratadas'] as num?)?.toDouble() ?? 8.0;
        creditoHoras += (hEfetivas - hContratadas);
      }
    }

    return {
      'salarioBase': salarioBase,
      'credito': creditoHoras,
      'ferias': ferias,
      'folgas': folgas,
    };
  }

  // --- BACKUP E RESTAURO ---
  Future<bool> exportarEGuardarBaseDeDados() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios.db');
      final dbFile = File(path);

      Directory? downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        downloadsDir = await getExternalStorageDirectory();
      }
      downloadsDir ??= await getApplicationDocumentsDirectory();

      final backupPath = join(
        downloadsDir.path, 
        'backup_gestao_horarios_${DateTime.now().millisecondsSinceEpoch}.db'
      );
      await dbFile.copy(backupPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restaurarBaseDeDados(String caminhoFicheiro) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios.db');
      
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final origem = File(caminhoFicheiro);
      await origem.copy(path);
      
      _database = await _initDB('gestao_horarios.db');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restaurarBaseDeDadosDeFicheiro(String caminhoFicheiro) async {
    return await restaurarBaseDeDados(caminhoFicheiro);
  }
}