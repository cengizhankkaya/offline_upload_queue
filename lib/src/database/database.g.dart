// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UploadTasksTable extends UploadTasks
    with TableInfo<$UploadTasksTable, UploadTaskData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceNumberMeta = const VerificationMeta(
    'sequenceNumber',
  );
  @override
  late final GeneratedColumn<int> sequenceNumber = GeneratedColumn<int>(
    'sequence_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<UploadStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<UploadStatus>($UploadTasksTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<FailureType?, int> failureType =
      GeneratedColumn<int>(
        'failure_type',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<FailureType?>($UploadTasksTable.$converterfailureTypen);
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    taskId,
    filePath,
    sequenceNumber,
    status,
    failureType,
    retryCount,
    metadataJson,
    checksum,
    fileSizeBytes,
    errorMessage,
    createdAt,
    nextRetryAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadTaskData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('sequence_number')) {
      context.handle(
        _sequenceNumberMeta,
        sequenceNumber.isAcceptableOrUnknown(
          data['sequence_number']!,
          _sequenceNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sequenceNumberMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sequenceNumber},
  ];
  @override
  UploadTaskData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadTaskData(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      sequenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence_number'],
      )!,
      status: $UploadTasksTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      failureType: $UploadTasksTable.$converterfailureTypen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}failure_type'],
        ),
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      ),
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
    );
  }

  @override
  $UploadTasksTable createAlias(String alias) {
    return $UploadTasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<UploadStatus, int, int> $converterstatus =
      const EnumIndexConverter<UploadStatus>(UploadStatus.values);
  static JsonTypeConverter2<FailureType, int, int> $converterfailureType =
      const EnumIndexConverter<FailureType>(FailureType.values);
  static JsonTypeConverter2<FailureType?, int?, int?> $converterfailureTypen =
      JsonTypeConverter2.asNullable($converterfailureType);
}

class UploadTaskData extends DataClass implements Insertable<UploadTaskData> {
  /// Dahili otomatik artan birincil anahtar.
  final int localId;

  /// UUID — idempotency key; backend'e bu değer gönderilir.
  final String taskId;

  /// Dosyanın yerel yolu.
  ///
  /// `copyToSandbox: true` (varsayılan) ise bu, paketin kendi sandbox
  /// kopyasının yolunu tutar — orijinal dosya değil.
  final String filePath;

  /// Monoton artan mantıksal sıra numarası.
  ///
  /// `getNextPending` sorgusu bu alana göre sıralar.
  /// ⚠️ UNIQUE constraint var — çakışma durumunda `enqueue()` en fazla
  /// 3 kez yeniden dener (bkz. §11.7).
  final int sequenceNumber;

  /// Görevin anlık durumu. Drift `intEnum<UploadStatus>()` kullanır.
  ///
  /// ⚠️ [UploadStatus] enum sırası kesinlikle değiştirilmemeli.
  final UploadStatus status;

  /// Son hatanın tipi. `null` ise henüz hata yok.
  final FailureType? failureType;

  /// Kaç kez denendiği.
  final int retryCount;

  /// `metadata` alanının JSON string'i.
  ///
  /// Yalnızca `jsonEncode` destekli tipler (String, num, bool, null, List, Map).
  /// Geçersiz tip verilirse `enqueue()` senkron `ArgumentError` fırlatır.
  final String? metadataJson;

  /// SHA-256 checksum. `pending` durumunda `null`; `uploading`'e geçerken
  /// doldurulur.
  final String? checksum;

  /// Sandbox kopyasının bayt cinsinden boyutu.
  ///
  /// `enqueue()` sırasında `stat()` ile tek seferlik doldurulur.
  /// `estimatedDiskUsageBytes` bu kolonun `SUM`'udur — dosya sistemine
  /// dokunmadan ucuz SQL sorgusuyla hesaplanır.
  final int? fileSizeBytes;

  /// İnsan okunabilir hata mesajı (debug/UI amaçlı).
  final String? errorMessage;

  /// Görevin kuyruğa alındığı zaman.
  final DateTime createdAt;

  /// Backoff sonrası bir sonraki deneme zamanı.
  ///
  /// `null` ise görev hemen alınabilir.
  /// `getNextPending` sorgusu: `nextRetryAt IS NULL OR nextRetryAt <= :now`
  final DateTime? nextRetryAt;
  const UploadTaskData({
    required this.localId,
    required this.taskId,
    required this.filePath,
    required this.sequenceNumber,
    required this.status,
    this.failureType,
    required this.retryCount,
    this.metadataJson,
    this.checksum,
    this.fileSizeBytes,
    this.errorMessage,
    required this.createdAt,
    this.nextRetryAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    map['task_id'] = Variable<String>(taskId);
    map['file_path'] = Variable<String>(filePath);
    map['sequence_number'] = Variable<int>(sequenceNumber);
    {
      map['status'] = Variable<int>(
        $UploadTasksTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || failureType != null) {
      map['failure_type'] = Variable<int>(
        $UploadTasksTable.$converterfailureTypen.toSql(failureType),
      );
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    if (!nullToAbsent || checksum != null) {
      map['checksum'] = Variable<String>(checksum);
    }
    if (!nullToAbsent || fileSizeBytes != null) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    return map;
  }

  UploadTasksCompanion toCompanion(bool nullToAbsent) {
    return UploadTasksCompanion(
      localId: Value(localId),
      taskId: Value(taskId),
      filePath: Value(filePath),
      sequenceNumber: Value(sequenceNumber),
      status: Value(status),
      failureType: failureType == null && nullToAbsent
          ? const Value.absent()
          : Value(failureType),
      retryCount: Value(retryCount),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      checksum: checksum == null && nullToAbsent
          ? const Value.absent()
          : Value(checksum),
      fileSizeBytes: fileSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSizeBytes),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      createdAt: Value(createdAt),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
    );
  }

  factory UploadTaskData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadTaskData(
      localId: serializer.fromJson<int>(json['localId']),
      taskId: serializer.fromJson<String>(json['taskId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sequenceNumber: serializer.fromJson<int>(json['sequenceNumber']),
      status: $UploadTasksTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      failureType: $UploadTasksTable.$converterfailureTypen.fromJson(
        serializer.fromJson<int?>(json['failureType']),
      ),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      checksum: serializer.fromJson<String?>(json['checksum']),
      fileSizeBytes: serializer.fromJson<int?>(json['fileSizeBytes']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'taskId': serializer.toJson<String>(taskId),
      'filePath': serializer.toJson<String>(filePath),
      'sequenceNumber': serializer.toJson<int>(sequenceNumber),
      'status': serializer.toJson<int>(
        $UploadTasksTable.$converterstatus.toJson(status),
      ),
      'failureType': serializer.toJson<int?>(
        $UploadTasksTable.$converterfailureTypen.toJson(failureType),
      ),
      'retryCount': serializer.toJson<int>(retryCount),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'checksum': serializer.toJson<String?>(checksum),
      'fileSizeBytes': serializer.toJson<int?>(fileSizeBytes),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
    };
  }

  UploadTaskData copyWith({
    int? localId,
    String? taskId,
    String? filePath,
    int? sequenceNumber,
    UploadStatus? status,
    Value<FailureType?> failureType = const Value.absent(),
    int? retryCount,
    Value<String?> metadataJson = const Value.absent(),
    Value<String?> checksum = const Value.absent(),
    Value<int?> fileSizeBytes = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> nextRetryAt = const Value.absent(),
  }) => UploadTaskData(
    localId: localId ?? this.localId,
    taskId: taskId ?? this.taskId,
    filePath: filePath ?? this.filePath,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    status: status ?? this.status,
    failureType: failureType.present ? failureType.value : this.failureType,
    retryCount: retryCount ?? this.retryCount,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    checksum: checksum.present ? checksum.value : this.checksum,
    fileSizeBytes: fileSizeBytes.present
        ? fileSizeBytes.value
        : this.fileSizeBytes,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
  );
  UploadTaskData copyWithCompanion(UploadTasksCompanion data) {
    return UploadTaskData(
      localId: data.localId.present ? data.localId.value : this.localId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sequenceNumber: data.sequenceNumber.present
          ? data.sequenceNumber.value
          : this.sequenceNumber,
      status: data.status.present ? data.status.value : this.status,
      failureType: data.failureType.present
          ? data.failureType.value
          : this.failureType,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadTaskData(')
          ..write('localId: $localId, ')
          ..write('taskId: $taskId, ')
          ..write('filePath: $filePath, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('status: $status, ')
          ..write('failureType: $failureType, ')
          ..write('retryCount: $retryCount, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('checksum: $checksum, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextRetryAt: $nextRetryAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    taskId,
    filePath,
    sequenceNumber,
    status,
    failureType,
    retryCount,
    metadataJson,
    checksum,
    fileSizeBytes,
    errorMessage,
    createdAt,
    nextRetryAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadTaskData &&
          other.localId == this.localId &&
          other.taskId == this.taskId &&
          other.filePath == this.filePath &&
          other.sequenceNumber == this.sequenceNumber &&
          other.status == this.status &&
          other.failureType == this.failureType &&
          other.retryCount == this.retryCount &&
          other.metadataJson == this.metadataJson &&
          other.checksum == this.checksum &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.errorMessage == this.errorMessage &&
          other.createdAt == this.createdAt &&
          other.nextRetryAt == this.nextRetryAt);
}

class UploadTasksCompanion extends UpdateCompanion<UploadTaskData> {
  final Value<int> localId;
  final Value<String> taskId;
  final Value<String> filePath;
  final Value<int> sequenceNumber;
  final Value<UploadStatus> status;
  final Value<FailureType?> failureType;
  final Value<int> retryCount;
  final Value<String?> metadataJson;
  final Value<String?> checksum;
  final Value<int?> fileSizeBytes;
  final Value<String?> errorMessage;
  final Value<DateTime> createdAt;
  final Value<DateTime?> nextRetryAt;
  const UploadTasksCompanion({
    this.localId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sequenceNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.failureType = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.checksum = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
  });
  UploadTasksCompanion.insert({
    this.localId = const Value.absent(),
    required String taskId,
    required String filePath,
    required int sequenceNumber,
    required UploadStatus status,
    this.failureType = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.checksum = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.errorMessage = const Value.absent(),
    required DateTime createdAt,
    this.nextRetryAt = const Value.absent(),
  }) : taskId = Value(taskId),
       filePath = Value(filePath),
       sequenceNumber = Value(sequenceNumber),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<UploadTaskData> custom({
    Expression<int>? localId,
    Expression<String>? taskId,
    Expression<String>? filePath,
    Expression<int>? sequenceNumber,
    Expression<int>? status,
    Expression<int>? failureType,
    Expression<int>? retryCount,
    Expression<String>? metadataJson,
    Expression<String>? checksum,
    Expression<int>? fileSizeBytes,
    Expression<String>? errorMessage,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? nextRetryAt,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (taskId != null) 'task_id': taskId,
      if (filePath != null) 'file_path': filePath,
      if (sequenceNumber != null) 'sequence_number': sequenceNumber,
      if (status != null) 'status': status,
      if (failureType != null) 'failure_type': failureType,
      if (retryCount != null) 'retry_count': retryCount,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (checksum != null) 'checksum': checksum,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAt != null) 'created_at': createdAt,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
    });
  }

  UploadTasksCompanion copyWith({
    Value<int>? localId,
    Value<String>? taskId,
    Value<String>? filePath,
    Value<int>? sequenceNumber,
    Value<UploadStatus>? status,
    Value<FailureType?>? failureType,
    Value<int>? retryCount,
    Value<String?>? metadataJson,
    Value<String?>? checksum,
    Value<int?>? fileSizeBytes,
    Value<String?>? errorMessage,
    Value<DateTime>? createdAt,
    Value<DateTime?>? nextRetryAt,
  }) {
    return UploadTasksCompanion(
      localId: localId ?? this.localId,
      taskId: taskId ?? this.taskId,
      filePath: filePath ?? this.filePath,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      status: status ?? this.status,
      failureType: failureType ?? this.failureType,
      retryCount: retryCount ?? this.retryCount,
      metadataJson: metadataJson ?? this.metadataJson,
      checksum: checksum ?? this.checksum,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sequenceNumber.present) {
      map['sequence_number'] = Variable<int>(sequenceNumber.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $UploadTasksTable.$converterstatus.toSql(status.value),
      );
    }
    if (failureType.present) {
      map['failure_type'] = Variable<int>(
        $UploadTasksTable.$converterfailureTypen.toSql(failureType.value),
      );
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadTasksCompanion(')
          ..write('localId: $localId, ')
          ..write('taskId: $taskId, ')
          ..write('filePath: $filePath, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('status: $status, ')
          ..write('failureType: $failureType, ')
          ..write('retryCount: $retryCount, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('checksum: $checksum, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextRetryAt: $nextRetryAt')
          ..write(')'))
        .toString();
  }
}

class $ActiveWorkerLockTable extends ActiveWorkerLock
    with TableInfo<$ActiveWorkerLockTable, ActiveWorkerLockData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActiveWorkerLockTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _acquiredAtMeta = const VerificationMeta(
    'acquiredAt',
  );
  @override
  late final GeneratedColumn<DateTime> acquiredAt = GeneratedColumn<DateTime>(
    'acquired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, acquiredAt, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'active_worker_lock';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActiveWorkerLockData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('acquired_at')) {
      context.handle(
        _acquiredAtMeta,
        acquiredAt.isAcceptableOrUnknown(data['acquired_at']!, _acquiredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_acquiredAtMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActiveWorkerLockData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActiveWorkerLockData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      acquiredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}acquired_at'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
    );
  }

  @override
  $ActiveWorkerLockTable createAlias(String alias) {
    return $ActiveWorkerLockTable(attachedDatabase, alias);
  }
}

class ActiveWorkerLockData extends DataClass
    implements Insertable<ActiveWorkerLockData> {
  /// Sabit birincil anahtar — her zaman `0`.
  final int id;

  /// Kilidin alındığı zaman.
  final DateTime acquiredAt;

  /// Kilidin sahibi (isolate/worker kimliği). Debug amaçlı, nullable.
  final String? ownerId;
  const ActiveWorkerLockData({
    required this.id,
    required this.acquiredAt,
    this.ownerId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['acquired_at'] = Variable<DateTime>(acquiredAt);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  ActiveWorkerLockCompanion toCompanion(bool nullToAbsent) {
    return ActiveWorkerLockCompanion(
      id: Value(id),
      acquiredAt: Value(acquiredAt),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory ActiveWorkerLockData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActiveWorkerLockData(
      id: serializer.fromJson<int>(json['id']),
      acquiredAt: serializer.fromJson<DateTime>(json['acquiredAt']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'acquiredAt': serializer.toJson<DateTime>(acquiredAt),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  ActiveWorkerLockData copyWith({
    int? id,
    DateTime? acquiredAt,
    Value<String?> ownerId = const Value.absent(),
  }) => ActiveWorkerLockData(
    id: id ?? this.id,
    acquiredAt: acquiredAt ?? this.acquiredAt,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
  );
  ActiveWorkerLockData copyWithCompanion(ActiveWorkerLockCompanion data) {
    return ActiveWorkerLockData(
      id: data.id.present ? data.id.value : this.id,
      acquiredAt: data.acquiredAt.present
          ? data.acquiredAt.value
          : this.acquiredAt,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActiveWorkerLockData(')
          ..write('id: $id, ')
          ..write('acquiredAt: $acquiredAt, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, acquiredAt, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActiveWorkerLockData &&
          other.id == this.id &&
          other.acquiredAt == this.acquiredAt &&
          other.ownerId == this.ownerId);
}

class ActiveWorkerLockCompanion extends UpdateCompanion<ActiveWorkerLockData> {
  final Value<int> id;
  final Value<DateTime> acquiredAt;
  final Value<String?> ownerId;
  const ActiveWorkerLockCompanion({
    this.id = const Value.absent(),
    this.acquiredAt = const Value.absent(),
    this.ownerId = const Value.absent(),
  });
  ActiveWorkerLockCompanion.insert({
    this.id = const Value.absent(),
    required DateTime acquiredAt,
    this.ownerId = const Value.absent(),
  }) : acquiredAt = Value(acquiredAt);
  static Insertable<ActiveWorkerLockData> custom({
    Expression<int>? id,
    Expression<DateTime>? acquiredAt,
    Expression<String>? ownerId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (acquiredAt != null) 'acquired_at': acquiredAt,
      if (ownerId != null) 'owner_id': ownerId,
    });
  }

  ActiveWorkerLockCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? acquiredAt,
    Value<String?>? ownerId,
  }) {
    return ActiveWorkerLockCompanion(
      id: id ?? this.id,
      acquiredAt: acquiredAt ?? this.acquiredAt,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (acquiredAt.present) {
      map['acquired_at'] = Variable<DateTime>(acquiredAt.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActiveWorkerLockCompanion(')
          ..write('id: $id, ')
          ..write('acquiredAt: $acquiredAt, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }
}

abstract class _$QueueDatabase extends GeneratedDatabase {
  _$QueueDatabase(QueryExecutor e) : super(e);
  $QueueDatabaseManager get managers => $QueueDatabaseManager(this);
  late final $UploadTasksTable uploadTasks = $UploadTasksTable(this);
  late final $ActiveWorkerLockTable activeWorkerLock = $ActiveWorkerLockTable(
    this,
  );
  late final Index idxUploadTasksStatusRetrySeq = Index(
    'idx_upload_tasks_status_retry_seq',
    'CREATE INDEX idx_upload_tasks_status_retry_seq ON upload_tasks (status, next_retry_at, sequence_number)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    uploadTasks,
    activeWorkerLock,
    idxUploadTasksStatusRetrySeq,
  ];
}

typedef $$UploadTasksTableCreateCompanionBuilder =
    UploadTasksCompanion Function({
      Value<int> localId,
      required String taskId,
      required String filePath,
      required int sequenceNumber,
      required UploadStatus status,
      Value<FailureType?> failureType,
      Value<int> retryCount,
      Value<String?> metadataJson,
      Value<String?> checksum,
      Value<int?> fileSizeBytes,
      Value<String?> errorMessage,
      required DateTime createdAt,
      Value<DateTime?> nextRetryAt,
    });
typedef $$UploadTasksTableUpdateCompanionBuilder =
    UploadTasksCompanion Function({
      Value<int> localId,
      Value<String> taskId,
      Value<String> filePath,
      Value<int> sequenceNumber,
      Value<UploadStatus> status,
      Value<FailureType?> failureType,
      Value<int> retryCount,
      Value<String?> metadataJson,
      Value<String?> checksum,
      Value<int?> fileSizeBytes,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
      Value<DateTime?> nextRetryAt,
    });

class $$UploadTasksTableFilterComposer
    extends Composer<_$QueueDatabase, $UploadTasksTable> {
  $$UploadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<UploadStatus, UploadStatus, int> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<FailureType?, FailureType, int>
  get failureType => $composableBuilder(
    column: $table.failureType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadTasksTableOrderingComposer
    extends Composer<_$QueueDatabase, $UploadTasksTable> {
  $$UploadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failureType => $composableBuilder(
    column: $table.failureType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadTasksTableAnnotationComposer
    extends Composer<_$QueueDatabase, $UploadTasksTable> {
  $$UploadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<UploadStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FailureType?, int> get failureType =>
      $composableBuilder(
        column: $table.failureType,
        builder: (column) => column,
      );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );
}

class $$UploadTasksTableTableManager
    extends
        RootTableManager<
          _$QueueDatabase,
          $UploadTasksTable,
          UploadTaskData,
          $$UploadTasksTableFilterComposer,
          $$UploadTasksTableOrderingComposer,
          $$UploadTasksTableAnnotationComposer,
          $$UploadTasksTableCreateCompanionBuilder,
          $$UploadTasksTableUpdateCompanionBuilder,
          (
            UploadTaskData,
            BaseReferences<_$QueueDatabase, $UploadTasksTable, UploadTaskData>,
          ),
          UploadTaskData,
          PrefetchHooks Function()
        > {
  $$UploadTasksTableTableManager(_$QueueDatabase db, $UploadTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> sequenceNumber = const Value.absent(),
                Value<UploadStatus> status = const Value.absent(),
                Value<FailureType?> failureType = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> checksum = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
              }) => UploadTasksCompanion(
                localId: localId,
                taskId: taskId,
                filePath: filePath,
                sequenceNumber: sequenceNumber,
                status: status,
                failureType: failureType,
                retryCount: retryCount,
                metadataJson: metadataJson,
                checksum: checksum,
                fileSizeBytes: fileSizeBytes,
                errorMessage: errorMessage,
                createdAt: createdAt,
                nextRetryAt: nextRetryAt,
              ),
          createCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                required String taskId,
                required String filePath,
                required int sequenceNumber,
                required UploadStatus status,
                Value<FailureType?> failureType = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> checksum = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> nextRetryAt = const Value.absent(),
              }) => UploadTasksCompanion.insert(
                localId: localId,
                taskId: taskId,
                filePath: filePath,
                sequenceNumber: sequenceNumber,
                status: status,
                failureType: failureType,
                retryCount: retryCount,
                metadataJson: metadataJson,
                checksum: checksum,
                fileSizeBytes: fileSizeBytes,
                errorMessage: errorMessage,
                createdAt: createdAt,
                nextRetryAt: nextRetryAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$QueueDatabase,
      $UploadTasksTable,
      UploadTaskData,
      $$UploadTasksTableFilterComposer,
      $$UploadTasksTableOrderingComposer,
      $$UploadTasksTableAnnotationComposer,
      $$UploadTasksTableCreateCompanionBuilder,
      $$UploadTasksTableUpdateCompanionBuilder,
      (
        UploadTaskData,
        BaseReferences<_$QueueDatabase, $UploadTasksTable, UploadTaskData>,
      ),
      UploadTaskData,
      PrefetchHooks Function()
    >;
typedef $$ActiveWorkerLockTableCreateCompanionBuilder =
    ActiveWorkerLockCompanion Function({
      Value<int> id,
      required DateTime acquiredAt,
      Value<String?> ownerId,
    });
typedef $$ActiveWorkerLockTableUpdateCompanionBuilder =
    ActiveWorkerLockCompanion Function({
      Value<int> id,
      Value<DateTime> acquiredAt,
      Value<String?> ownerId,
    });

class $$ActiveWorkerLockTableFilterComposer
    extends Composer<_$QueueDatabase, $ActiveWorkerLockTable> {
  $$ActiveWorkerLockTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acquiredAt => $composableBuilder(
    column: $table.acquiredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActiveWorkerLockTableOrderingComposer
    extends Composer<_$QueueDatabase, $ActiveWorkerLockTable> {
  $$ActiveWorkerLockTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acquiredAt => $composableBuilder(
    column: $table.acquiredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActiveWorkerLockTableAnnotationComposer
    extends Composer<_$QueueDatabase, $ActiveWorkerLockTable> {
  $$ActiveWorkerLockTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get acquiredAt => $composableBuilder(
    column: $table.acquiredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$ActiveWorkerLockTableTableManager
    extends
        RootTableManager<
          _$QueueDatabase,
          $ActiveWorkerLockTable,
          ActiveWorkerLockData,
          $$ActiveWorkerLockTableFilterComposer,
          $$ActiveWorkerLockTableOrderingComposer,
          $$ActiveWorkerLockTableAnnotationComposer,
          $$ActiveWorkerLockTableCreateCompanionBuilder,
          $$ActiveWorkerLockTableUpdateCompanionBuilder,
          (
            ActiveWorkerLockData,
            BaseReferences<
              _$QueueDatabase,
              $ActiveWorkerLockTable,
              ActiveWorkerLockData
            >,
          ),
          ActiveWorkerLockData,
          PrefetchHooks Function()
        > {
  $$ActiveWorkerLockTableTableManager(
    _$QueueDatabase db,
    $ActiveWorkerLockTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActiveWorkerLockTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActiveWorkerLockTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActiveWorkerLockTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> acquiredAt = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
              }) => ActiveWorkerLockCompanion(
                id: id,
                acquiredAt: acquiredAt,
                ownerId: ownerId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime acquiredAt,
                Value<String?> ownerId = const Value.absent(),
              }) => ActiveWorkerLockCompanion.insert(
                id: id,
                acquiredAt: acquiredAt,
                ownerId: ownerId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActiveWorkerLockTableProcessedTableManager =
    ProcessedTableManager<
      _$QueueDatabase,
      $ActiveWorkerLockTable,
      ActiveWorkerLockData,
      $$ActiveWorkerLockTableFilterComposer,
      $$ActiveWorkerLockTableOrderingComposer,
      $$ActiveWorkerLockTableAnnotationComposer,
      $$ActiveWorkerLockTableCreateCompanionBuilder,
      $$ActiveWorkerLockTableUpdateCompanionBuilder,
      (
        ActiveWorkerLockData,
        BaseReferences<
          _$QueueDatabase,
          $ActiveWorkerLockTable,
          ActiveWorkerLockData
        >,
      ),
      ActiveWorkerLockData,
      PrefetchHooks Function()
    >;

class $QueueDatabaseManager {
  final _$QueueDatabase _db;
  $QueueDatabaseManager(this._db);
  $$UploadTasksTableTableManager get uploadTasks =>
      $$UploadTasksTableTableManager(_db, _db.uploadTasks);
  $$ActiveWorkerLockTableTableManager get activeWorkerLock =>
      $$ActiveWorkerLockTableTableManager(_db, _db.activeWorkerLock);
}
