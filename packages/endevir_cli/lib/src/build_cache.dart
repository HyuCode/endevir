import 'dart:convert';
import 'dart:io';

const _manifestSchemaVersion = 1;
const _fingerprintMask = 0xffffffffffffffff;

/// A reusable Flutter application artifact built for an Endevir test target.
class BuildArtifactManifest {
  const BuildArtifactManifest({
    required this.platform,
    required this.target,
    required this.artifactPath,
    required this.projectFingerprint,
    required this.builtAt,
  });

  final String platform;
  final String target;
  final String artifactPath;
  final String projectFingerprint;
  final DateTime builtAt;

  Map<String, Object> toJson() => {
    'schemaVersion': _manifestSchemaVersion,
    'platform': platform,
    'target': target,
    'artifactPath': artifactPath,
    'projectFingerprint': projectFingerprint,
    'builtAt': builtAt.toUtc().toIso8601String(),
  };

  static BuildArtifactManifest fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != _manifestSchemaVersion) {
      throw const FormatException('unsupported build manifest schema');
    }
    return BuildArtifactManifest(
      platform: json['platform'] as String,
      target: json['target'] as String,
      artifactPath: json['artifactPath'] as String,
      projectFingerprint: json['projectFingerprint'] as String,
      builtAt: DateTime.parse(json['builtAt'] as String),
    );
  }
}

class BuildReuseValidation {
  const BuildReuseValidation._(this.isValid, this.message, this.manifest);

  const BuildReuseValidation.valid(BuildArtifactManifest manifest)
    : this._(true, 'build artifact is reusable', manifest);

  const BuildReuseValidation.invalid(String message)
    : this._(false, message, null);

  final bool isValid;
  final String message;
  final BuildArtifactManifest? manifest;
}

String buildManifestPath(String outDir, String platform) =>
    '$outDir/builds/$platform.json';

void writeBuildManifest({
  required String projectRoot,
  required String outDir,
  required String platform,
  required String target,
  required String artifactPath,
  DateTime? now,
}) {
  final manifest = BuildArtifactManifest(
    platform: platform,
    target: target,
    artifactPath: artifactPath,
    projectFingerprint: computeProjectFingerprint(projectRoot),
    builtAt: now ?? DateTime.now().toUtc(),
  );
  final file = File(buildManifestPath(outDir, platform));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );
}

BuildReuseValidation validateReusableBuild({
  required String projectRoot,
  required String outDir,
  required String platform,
  required String target,
}) {
  final manifestFile = File(buildManifestPath(outDir, platform));
  if (!manifestFile.existsSync()) {
    return BuildReuseValidation.invalid(
      'build manifest not found: ${manifestFile.path}',
    );
  }

  final BuildArtifactManifest manifest;
  try {
    final json = jsonDecode(manifestFile.readAsStringSync());
    manifest = BuildArtifactManifest.fromJson(
      (json as Map).cast<String, Object?>(),
    );
  } on Object catch (error) {
    return BuildReuseValidation.invalid('invalid build manifest: $error');
  }

  if (manifest.platform != platform) {
    return BuildReuseValidation.invalid(
      'build platform changed (${manifest.platform} -> $platform)',
    );
  }
  if (manifest.target != target) {
    return BuildReuseValidation.invalid(
      'test target changed (${manifest.target} -> $target)',
    );
  }

  final artifact = _resolvePath(projectRoot, manifest.artifactPath);
  if (FileSystemEntity.typeSync(artifact) == FileSystemEntityType.notFound) {
    return BuildReuseValidation.invalid(
      'build artifact not found: ${manifest.artifactPath}',
    );
  }

  final currentFingerprint = computeProjectFingerprint(projectRoot);
  if (manifest.projectFingerprint != currentFingerprint) {
    return const BuildReuseValidation.invalid(
      'project inputs changed after the artifact was built',
    );
  }
  return BuildReuseValidation.valid(manifest);
}

/// Computes a deterministic content fingerprint of Flutter build inputs.
///
/// The hash is not used for security. FNV-1a keeps the CLI dependency-free
/// while detecting source, test, asset, dependency lock, and native changes.
String computeProjectFingerprint(String projectRoot) {
  final root = Directory(projectRoot).absolute;
  final files = <File>[];
  for (final path in ['pubspec.yaml', 'pubspec.lock']) {
    final file = File('${root.path}/$path');
    if (file.existsSync()) files.add(file);
  }
  for (final directoryName in [
    'lib',
    'endevir_test',
    'assets',
    'ios',
    'android',
  ]) {
    final directory = Directory('${root.path}/$directoryName');
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          !_isGeneratedPath(_relativePath(root.path, entity.path))) {
        files.add(entity);
      }
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));

  var hash = 0xcbf29ce484222325;
  for (final file in files) {
    final relativePath = _relativePath(root.path, file.path);
    for (final byte in utf8.encode(relativePath)) {
      hash = _fnvStep(hash, byte);
    }
    hash = _fnvStep(hash, 0);
    for (final byte in file.readAsBytesSync()) {
      hash = _fnvStep(hash, byte);
    }
    hash = _fnvStep(hash, 0xff);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

int _fnvStep(int hash, int byte) =>
    ((hash ^ byte) * 0x100000001b3) & _fingerprintMask;

bool _isGeneratedPath(String path) {
  final normalized = '/${path.replaceAll('\\', '/')}';
  return normalized.contains('/.dart_tool/') ||
      normalized.contains('/build/') ||
      normalized.contains('/.gradle/') ||
      normalized.contains('/Pods/') ||
      normalized.contains('/Flutter/ephemeral/') ||
      normalized.endsWith('/Flutter/.last_build_id');
}

String _relativePath(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

String _resolvePath(String root, String path) =>
    path.startsWith(Platform.pathSeparator) ? path : '$root/$path';
