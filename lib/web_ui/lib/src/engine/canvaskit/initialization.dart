// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
library canvaskit_initialization;

import 'dart:async';
import 'dart:html' as html;

import '../../engine.dart' show kProfileMode;
import '../browser_detection.dart';
import '../configuration.dart';
import '../embedder.dart';
import '../safe_browser_api.dart';
import 'canvaskit_api.dart';
import 'fonts.dart';
import 'util.dart';

/// Whether to use CanvasKit as the rendering backend.
final bool useCanvasKit = FlutterConfiguration.flutterWebAutoDetect
  ? _hasCanvasKit
  : FlutterConfiguration.useSkia;

/// Returns true if CanvasKit is used.
///
/// Otherwise, returns false.
final bool _hasCanvasKit = _detectCanvasKit();

bool _detectCanvasKit() {
  if (requestedRendererType != null) {
    return requestedRendererType! == 'canvaskit';
  }
  // If requestedRendererType is not specified, use CanvasKit for desktop and
  // html for mobile.
  return isDesktop;
}

String get canvasKitBuildUrl =>
    configuration.canvasKitBaseUrl + (kProfileMode ? 'profiling/' : '');
String get canvasKitJavaScriptBindingsUrl =>
    canvasKitBuildUrl + 'canvaskit.js';
String canvasKitWasmModuleUrl(String file) => _currentCanvasKitBase! + file;

/// The script element which CanvasKit is loaded from.
html.ScriptElement? _canvasKitScript;

/// The currently used base URL for loading CanvasKit.
String? _currentCanvasKitBase;

/// Initialize CanvasKit.
///
/// Uses a cached or native CanvasKit implemenation if it exists. Otherwise
/// downloads CanvasKit. Assigns the global [canvasKit] object.
Future<void> initializeCanvasKit({String? canvasKitBase}) async {
  if (windowFlutterCanvasKit != null) {
    canvasKit = windowFlutterCanvasKit!;
  } else if (useH5vccCanvasKit) {
    if (h5vcc?.canvasKit == null) {
      throw CanvasKitError('H5vcc CanvasKit implementation not found.');
    }
    canvasKit = h5vcc!.canvasKit!;
    windowFlutterCanvasKit = canvasKit;
  } else {
    canvasKit = await downloadCanvasKit(canvasKitBase: canvasKitBase);
    windowFlutterCanvasKit = canvasKit;
  }

  /// Add a Skia scene host.
  skiaSceneHost = html.Element.tag('flt-scene');
  flutterViewEmbedder.renderScene(skiaSceneHost);
}

/// Download and initialize the CanvasKit module.
///
/// Downloads the CanvasKit JavaScript, then calls `CanvasKitInit` to download
/// and intialize the CanvasKit wasm.
Future<CanvasKit> downloadCanvasKit({String? canvasKitBase}) async {
  await _downloadCanvasKitJs(canvasKitBase: canvasKitBase);
  final Completer<CanvasKit> canvasKitInitCompleter = Completer<CanvasKit>();
  final CanvasKitInitPromise canvasKitInitPromise =
      CanvasKitInit(CanvasKitInitOptions(
    locateFile: allowInterop(
        (String file, String unusedBase) => canvasKitWasmModuleUrl(file)),
  ));
  canvasKitInitPromise.then(allowInterop((CanvasKit ck) {
    canvasKitInitCompleter.complete(ck);
  }));
  return canvasKitInitCompleter.future;
}

/// Downloads the CanvasKit JavaScript file at [canvasKitBase].
Future<void> _downloadCanvasKitJs({String? canvasKitBase}) {
  final String canvasKitJavaScriptUrl = canvasKitBase != null
      ? canvasKitBase + 'canvaskit.js'
      : canvasKitJavaScriptBindingsUrl;
  _currentCanvasKitBase = canvasKitBase ?? canvasKitBuildUrl;

  _canvasKitScript = html.ScriptElement();
  _canvasKitScript!.src = canvasKitJavaScriptUrl;

  final Completer<void> canvasKitLoadCompleter = Completer<void>();
  late StreamSubscription<html.Event> loadSubscription;
  loadSubscription = _canvasKitScript!.onLoad.listen((_) {
    loadSubscription.cancel();
    canvasKitLoadCompleter.complete();
  });

  patchCanvasKitModule(_canvasKitScript!);

  return canvasKitLoadCompleter.future;
}

/// The Skia font collection.
SkiaFontCollection get skiaFontCollection => _skiaFontCollection!;
SkiaFontCollection? _skiaFontCollection;

void debugSetSkiaFontCollection(SkiaFontCollection? value) {
  _skiaFontCollection = value;
}

/// Initializes [skiaFontCollection].
void ensureSkiaFontCollectionInitialized() {
  _skiaFontCollection ??= SkiaFontCollection();
}

/// The scene host, where the root canvas and overlay canvases are added to.
html.Element? skiaSceneHost;
