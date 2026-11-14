import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/models.dart';
import 'catalog.dart';
import 'smartbuds_player.dart';

/// YouTube con su reproductor OFICIAL incrustado (IFrame Player API) dentro
/// de SmartBuds. Reglas de YouTube que se respetan:
/// - el video se ve (mínimo 200×200) mientras suena;
/// - no se extrae el audio ni se oculta el reproductor;
/// - al salir de la app se pausa (sin reproducción en segundo plano).
class YouTubeEngine extends PlaybackEngine {
  YouTubeEngine() {
    PlatformWebViewControllerCreationParams params = const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('SmartBuds', onMessageReceived: _onMessage);
    final platform = controller.platform;
    if (platform is AndroidWebViewController) platform.setMediaPlaybackRequiresUserGesture(false);
  }

  late final WebViewController controller;
  bool _loaded = false;
  int? _durationMs;

  void _onMessage(JavaScriptMessage m) {
    final Object? d;
    try {
      d = jsonDecode(m.message);
    } catch (_) {
      return;
    }
    if (d is! Map) return;
    final dur = (d['duration'] as num?)?.toDouble();
    if (dur != null && dur > 0) _durationMs = (dur * 1000).round();
    final pos = (d['time'] as num?)?.toDouble();
    switch (d['event']) {
      case 'error':
        // 101/150: el dueño no permite verlo fuera de YouTube.
        onState?.call(EngineState(PlaybackState.stopped,
            error: (d['code'] == 101 || d['code'] == 150) ? 'not_embeddable' : 'YouTube no pudo reproducirla'));
      case 'state':
        final st = switch (d['state']) {
          1 => PlaybackState.playing,
          2 => PlaybackState.paused,
          3 => PlaybackState.buffering,
          0 => PlaybackState.stopped,
          _ => PlaybackState.buffering,
        };
        onState?.call(EngineState(st,
            positionMs: pos == null ? null : (pos * 1000).round(), durationMs: _durationMs, ended: d['state'] == 0));
      case 'time':
        onState?.call(EngineState(PlaybackState.playing,
            positionMs: pos == null ? null : (pos * 1000).round(), durationMs: _durationMs));
    }
  }

  static String _html(String videoId) => '''
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#p{width:100%;height:100%}</style></head>
<body><div id="p"></div><script>
var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';document.head.appendChild(tag);
var player,timer;
function send(o){try{SmartBuds.postMessage(JSON.stringify(o));}catch(e){}}
function onYouTubeIframeAPIReady(){
 player=new YT.Player('p',{videoId:'$videoId',playerVars:{autoplay:1,playsinline:1,controls:1,rel:0,modestbranding:1},
  events:{onReady:function(e){e.target.playVideo();},
   onStateChange:function(e){send({event:'state',state:e.data,time:player.getCurrentTime(),duration:player.getDuration()});},
   onError:function(e){send({event:'error',code:e.data});}}});
 timer=setInterval(function(){if(player&&player.getPlayerState&&player.getPlayerState()==1){send({event:'time',time:player.getCurrentTime(),duration:player.getDuration()});}},1000);
}
function sbLoad(id){if(player&&player.loadVideoById){player.loadVideoById(id);}}
function sbPause(){if(player)player.pauseVideo();}
function sbPlay(){if(player)player.playVideo();}
function sbStop(){if(player)player.stopVideo();}
function sbSeek(s){if(player)player.seekTo(s,true);}
function sbVol(v){if(player)player.setVolume(v);}
</script></body></html>''';

  Future<void> _js(String code) async {
    try {
      await controller.runJavaScript(code);
    } catch (_) {}
  }

  @override
  Future<void> load(InAppTrack track) async {
    final id = track.videoId;
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) {
      onState?.call(const EngineState(PlaybackState.stopped, error: 'Video no válido'));
      return;
    }
    _durationMs = null;
    if (!_loaded) {
      _loaded = true;
      // El origen identifica a SmartBuds ante YouTube (necesario para incrustar).
      await controller.loadHtmlString(_html(id), baseUrl: 'https://smartbuds-ai-web.vercel.app');
    } else {
      await _js("sbLoad('$id')");
    }
  }

  @override
  Future<void> pause() => _js('sbPause()');
  @override
  Future<void> resume() => _js('sbPlay()');
  @override
  Future<void> stop() => _js('sbStop()');
  @override
  Future<void> seek(int positionMs) => _js('sbSeek(${positionMs / 1000})');
  @override
  Future<void> setVolume(int percent) => _js('sbVol(${percent.clamp(0, 100)})');
}
