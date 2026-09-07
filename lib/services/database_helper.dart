import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:file_picker/file_picker.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gestao_horarios_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE perfil (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nomeTrabalhador TEXT,
        nomeEmpresa TEXT,
        salarioBase REAL,
        valorSubsidioAlimentacao REAL,
        pinApp TEXT,
        biometriaAtiva INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE registos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT UNIQUE,
        tipoDia TEXT,
        horasContratadas REAL,
        horaInicio TEXT,
        horaFim TEXT,
        almocoInicio TEXT,
        almocoFim TEXT,
        horasEfetivas REAL,
        horasExtraPagas REAL,
        horasDescontoSalario REAL,
        acaoExcesso TEXT,
        acaoFalta TEXT,
        tipoJustificacao TEXT,
        incluiSubsidio INTEGER
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE perfil ADD COLUMN valorSubsidioAlimentacao REAL DEFAULT 0.0");
        await db.execute("ALTER TABLE registos ADD COLUMN horasContratadas REAL DEFAULT 8.0");
        await db.execute("ALTER TABLE registos ADD COLUMN horaInicio TEXT DEFAULT '08:00'");
        await db.execute("ALTER TABLE registos ADD COLUMN horaFim TEXT DEFAULT '17:00'");
        await db.execute("ALTER TABLE registos ADD COLUMN almocoInicio TEXT DEFAULT '12:00'");
        await db.execute("ALTER TABLE registos ADD COLUMN almocoFim TEXT DEFAULT '13:00'");
        await db.execute("ALTER TABLE registos ADD COLUMN acaoExcesso TEXT DEFAULT 'Banco de Horas'");
        await db.execute("ALTER TABLE registos ADD COLUMN acaoFalta TEXT DEFAULT 'Descontar no Banco'");
        await db.execute("ALTER TABLE registos ADD COLUMN tipoJustificacao TEXT DEFAULT 'Justificado'");
        await db.execute("ALTER TABLE registos ADD COLUMN incluiSubsidio INTEGER DEFAULT 1");
      } catch (_) {}
    }
  }

  // --- PERFIL ---
  Future<Map<String, dynamic>> getPerfil() async {
    final db = await instance.database;
    final result = await db.query('perfil');
    if (result.isNotEmpty) {
      return result.first;
    } else {
      await db.insert('perfil', {
        'nomeTrabalhador': '',
        'nomeEmpresa': '',
        'salarioBase': 1000.0,
        'valorSubsidioAlimentacao': 6.0,
        'pinApp': '',
        'biometriaAtiva': 0,
      });
      final res = await db.query('perfil');
      return res.first;
    }
  }

  Future<int> atualizarPerfil(Map<String, dynamic> perfil) async {
    final db = await instance.database;
    return await db.update('perfil', perfil, where: 'id = ?', whereArgs: [1]);
  }

  // --- REGISTOS DIÁRIOS ---
  Future<Map<String, Map<String, dynamic>>> getRegistosMes(int ano, int mes) async {
    final db = await instance.database;
    String mesStr = mes.toString().padLeft(2, '0');
    final result = await db.query(
      'registos',
      where: "data LIKE ?",
      whereArgs: ["$ano-$mesStr-%"],
    );

    Map<String, Map<String, dynamic>> mapa = {};
    for (var row in result) {
      mapa[row['data'].toString()] = row;
    }
    return mapa;
  }

  Future<List<Map<String, dynamic>>> getRegistosAno(int ano) async {
    final db = await instance.database;
    return await db.query(
      'registos',
      where: "data LIKE ?",
      whereArgs: ["$ano-%"],
    );
  }

  Future<int> guardarRegistoCompleto({
    required String data,
    required String tipoDia,
    required double horasContratadas,
    required String horaInicio,
    required String horaFim,
    required String almocoInicio,
    required String almocoFim,
    required double horasEfetivas,
    required double horasExtraPagas,
    required double horasDescontoSalario,
    required String acaoExcesso,
    required String acaoFalta,
    required String tipoJustificacao,
    required int incluiSubsidio,
  }) async {
    final db = await instance.database;
    return await db.insert(
      'registos',
      {
        'data': data,
        'tipoDia': tipoDia,
        'horasContratadas': horasContratadas,
        'horaInicio': horaInicio,
        'horaFim': horaFim,
        'almocoInicio': almocoInicio,
        'almocoFim': almocoFim,
        'horasEfetivas': horasEfetivas,
        'horasExtraPagas': horasExtraPagas,
        'horasDescontoSalario': horasDescontoSalario,
        'acaoExcesso': acaoExcesso,
        'acaoFalta': acaoFalta,
        'tipoJustificacao': tipoJustificacao,
        'incluiSubsidio': incluiSubsidio,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- TOTAIS GERAIS E BANCO DE HORAS (COM DESCONTO CORRETO) ---
  Future<Map<String, double>> getTotaisGerais() async {
    final db = await instance.database;
    final registos = await db.query('registos');
    
    double totalCreditoTrabalho = 0.0;
    double totalDebitoBanco = 0.0;
    double totalDescontoSalario = 0.0;
    double totalExtraPago = 0.0;
    double totalFerias = 0.0;
    double totalFolgas = 0.0;
    double totalSubsidiosAlimentacao = 0.0;

    final perfil = await getPerfil();
    double salarioBase = (perfil['salarioBase'] as num?)?.toDouble() ?? 1000.0;
    double valorSubsidioDiario = (perfil['valorSubsidioAlimentacao'] as num?)?.toDouble() ?? 6.0;
    double valorHoraBase = salarioBase / 174.0;

    for (var reg in registos) {
      String tipo = reg['tipoDia']?.toString() ?? 'Trabalho';
      double hEfetivas = (reg['horasEfetivas'] as num?)?.toDouble() ?? 0.0;
      double hContratadas = (reg['horasContratadas'] as num?)?.toDouble() ?? 8.0;
      int incluiSub = (reg['incluiSubsidio'] as num?)?.toInt() ?? 0;

      if (incluiSub == 1) {
        totalSubsidiosAlimentacao += valorSubsidioDiario;
      }

      if (tipo == 'Férias') {
        totalFerias += 1.0;
      } else if (tipo == 'Folga') {
        totalFolgas += 1.0;
      } else if (tipo == 'Trabalho') {
        double diff = hEfetivas - hContratadas;
        if (diff > 0.01) {
          String acao = reg['acaoExcesso']?.toString() ?? 'Banco de Horas';
          if (acao == 'Banco de Horas') {
            totalCreditoTrabalho += diff;
          } else if (acao == 'Pagar') {
            totalExtraPago += diff;
          }
        } else if (diff < -0.01) {
          String acaoFalta = reg['acaoFalta']?.toString() ?? 'Descontar no Banco';
          if (acaoFalta == 'Descontar no Banco') {
            totalDebitoBanco += diff.abs();
          } else if (acaoFalta == 'Descontar no Salário') {
            totalDescontoSalario += diff.abs();
          }
        }
      } else if (tipo == 'Falta') {
        String acaoFalta = reg['acaoFalta']?.toString() ?? 'Descontar no Banco';
        if (acaoFalta == 'Descontar no Banco') {
          totalDebitoBanco += hContratadas > 0 ? hContratadas : 8.0;
        } else if (acaoFalta == 'Descontar no Salário') {
          totalDescontoSalario += hContratadas > 0 ? hContratadas : 8.0;
        }
      }
    }

    double bancoHorasLiquido = totalCreditoTrabalho - totalDebitoBanco;
    double valorHorasExtra = totalExtraPago * valorHoraBase * 1.25;
    double valorDescontosSalario = totalDescontoSalario * valorHoraBase;
    double valorTotalHorasAReceber = valorHorasExtra - valorDescontosSalario;
    double totalGeralReceber = salarioBase + valorTotalHorasAReceber + totalSubsidiosAlimentacao;

    return {
      'credito': bancoHorasLiquido,
      'debito': totalDebitoBanco,
      'ferias': totalFerias,
      'folgas': totalFolgas,
      'salarioBase': salarioBase,
      'valorHorasAReceber': valorTotalHorasAReceber,
      'subsidioAlimentacao': totalSubsidiosAlimentacao,
      'totalAReceber': totalGeralReceber,
    };
  }

  // --- BACKUP E RESTAURO ---
  Future<bool> exportarEGuardarBaseDeDados() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios_v3.db');
      final dbFile = File(path);

      if (!await dbFile.exists()) return false;

      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar Backup da Base de Dados',
        fileName: 'backup_gestao_horarios_${DateTime.now().millisecondsSinceEpoch}.db',
      );

      if (outputPath != null) {
        await dbFile.copy(outputPath);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restaurarBaseDeDadosDeFicheiro(String sourcePath) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'gestao_horarios_v3.db');
      
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(path);
        _database = await _initDB('gestao_horarios_v3.db');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}