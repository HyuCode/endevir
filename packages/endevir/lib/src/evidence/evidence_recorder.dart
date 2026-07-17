import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// フレームのスナップショットを取る（同期部。ADR-004で実測1ms）。
abstract interface class FrameCapturer {
  Future<CapturedFrame> capture();
}

/// 確定済みのフレーム。エンコード（重い遅延部）はステップをブロックしない。
abstract interface class CapturedFrame {
  Future<List<int>> encodePng();
}

/// 証跡スクリーンショットのレコーダ（RPT-004、ADR-004）。
///
/// captureForStepはGPUスナップショットのみを待って即座にパスを返し、
/// PNGエンコードと配送は遅延キューで行う。キューは有界で、超過時は
/// 最古のエンコード完了を待つ（メモリ保護）。
class EvidenceRecorder {
  EvidenceRecorder({
    required FrameCapturer capturer,
    required void Function(String path, List<int> bytes) deliver,
    this.maxPending = 8,
  })  : _capturer = capturer,
        _deliver = deliver;

  final FrameCapturer _capturer;
  final void Function(String path, List<int> bytes) _deliver;
  final int maxPending;

  final List<Future<void>> _pending = [];

  /// ステップのスクリーンショットを撮り、証跡が参照する相対パスを返す。
  Future<String> captureForStep(int stepId) async {
    while (_pending.length >= maxPending) {
      await _pending.first;
    }

    final path = 'shots/$stepId.png';
    final frame = await _capturer.capture(); // フレーム内容はここで確定する

    late final Future<void> encodeTask;
    encodeTask = frame.encodePng().then(
      (bytes) => _deliver(path, bytes),
      onError: (Object e) =>
          debugPrint('ENDEVIR-EVIDENCE encode failed ($path): $e'),
    ).whenComplete(() => _pending.remove(encodeTask));
    _pending.add(encodeTask);

    return path;
  }

  /// 全ての遅延エンコード・配送の完了を待つ（実行終了時に呼ぶ）。
  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List.of(_pending));
    }
  }
}

/// RenderViewのレイヤーからキャプチャする本番実装（debugビルド限定）。
///
/// profile/releaseビルドでのキャプチャ機構はADR-004の未解決事項（M6以降）。
class DebugLayerFrameCapturer implements FrameCapturer {
  const DebugLayerFrameCapturer();

  @override
  Future<CapturedFrame> capture() async {
    final renderView = WidgetsBinding.instance.renderViews.first;
    final layer = renderView.debugLayer;
    if (layer is! OffsetLayer) {
      throw StateError('root layer is not capturable');
    }
    final image = await layer.toImage(renderView.paintBounds);
    return _UiImageFrame(image);
  }
}

class _UiImageFrame implements CapturedFrame {
  _UiImageFrame(this._image);

  final ui.Image _image;

  @override
  Future<List<int>> encodePng() async {
    try {
      final byteData =
          await _image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('png encode returned null');
      }
      return byteData.buffer.asUint8List();
    } finally {
      _image.dispose();
    }
  }
}
