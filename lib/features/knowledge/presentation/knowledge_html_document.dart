import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/design_system/fly_color_scheme.dart';
import '../domain/knowledge_models.dart';

String knowledgeHtmlDocument({
  required KnowledgeArticle article,
  required FlyColorScheme colors,
}) {
  String rgb(Color value) =>
      '#${(value.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final nonce = List.generate(
    20,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  final policy = article.copyPolicy.name;
  return '''<!doctype html>
<html lang="${article.locale}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-$nonce'; connect-src 'none'; frame-src 'none'; form-action 'none'">
<style>
:root{--fly-bg:${rgb(colors.surface)};--fly-surface:${rgb(colors.surfaceMuted)};--fly-text:${rgb(colors.textPrimary)};--fly-secondary:${rgb(colors.textSecondary)};--fly-accent:${rgb(colors.accent)};--fly-border:${rgb(colors.divider)};--fly-warning:${rgb(colors.warning)};--fly-selected:${rgb(colors.selected)};}
*{box-sizing:border-box}html{background:var(--fly-bg);scroll-behavior:smooth}body{margin:0;padding:28px clamp(18px,5vw,70px) 90px;color:var(--fly-text);background:var(--fly-bg);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Microsoft YaHei',sans-serif;font-size:15px;line-height:1.65;overflow-wrap:anywhere}main{max-width:840px;margin:auto}h1{font-size:30px;line-height:1.25;margin:0 0 24px;font-weight:750;letter-spacing:-.025em}h2{font-size:23px;line-height:1.35;margin:36px 0 14px;padding-top:8px;font-weight:700}h3{font-size:18px;margin:26px 0 10px}p{margin:0 0 18px}ul,ol{padding-left:25px;margin:0 0 20px}li{margin:6px 0}strong{font-weight:700}a{color:var(--fly-accent);text-decoration:none;border-bottom:1px solid currentColor;cursor:pointer}a:hover{opacity:.75}blockquote{border-left:3px solid var(--fly-accent);margin:22px 0;padding:8px 18px;color:var(--fly-secondary);background:var(--fly-surface);border-radius:0 10px 10px 0}hr{border:0;border-top:1px solid var(--fly-border);margin:34px 0}code{padding:2px 5px;border-radius:4px;background:var(--fly-surface);font-size:.92em}pre{padding:18px;overflow:auto;border:1px solid var(--fly-border);border-radius:10px;background:var(--fly-surface)}pre code{padding:0}table{border-collapse:collapse;width:100%;margin:22px 0;display:block;overflow-x:auto}th,td{border:1px solid var(--fly-border);padding:9px 12px;text-align:left}th{background:var(--fly-surface)}img{max-width:100%;height:auto;border-radius:9px;border:1px solid var(--fly-border);cursor:zoom-in}.fly-tip,.fly-important,.fly-warning,.fly-example,.fly-script,.fly-steps,.fly-copyable{border:1px solid var(--fly-border);border-left:4px solid var(--fly-accent);border-radius:11px;padding:17px 20px;margin:24px 0;background:var(--fly-surface)}.fly-warning{border-left-color:var(--fly-warning)}.fly-script,.fly-copyable{background:var(--fly-selected)}.fly-steps{counter-reset:step}.fly-steps ol{margin-bottom:0}.fly-tip>:last-child,.fly-important>:last-child,.fly-warning>:last-child,.fly-example>:last-child,.fly-script>:last-child,.fly-copyable>:last-child{margin-bottom:0}.copy-none,.copy-snippet{-webkit-user-select:none;user-select:none}.copy-snippet .fly-copyable{-webkit-user-select:text;user-select:text}
</style></head><body class="copy-$policy"><main>${article.html}</main>
<script nonce="$nonce">
(() => {
  function send(message) {
    const encoded = JSON.stringify(message);
    if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(encoded);
    else if (window.FlyBridge) window.FlyBridge.postMessage(encoded);
  }
  document.addEventListener('click', event => {
    const target = event.target;
    const link = target.closest('a[data-fly-href]');
    if (link) { event.preventDefault(); send({type:'link',target:link.dataset.flyHref}); return; }
    const image = target.closest('img');
    if (image) { event.preventDefault(); send({type:'image',target:image.src}); }
  });
  document.addEventListener('copy', event => {
    if ('$policy' === 'none') event.preventDefault();
    if ('$policy' === 'snippet') {
      const node = window.getSelection()?.anchorNode?.parentElement;
      if (!node || !node.closest('.fly-copyable')) event.preventDefault();
    }
  });
  document.addEventListener('contextmenu', event => {
    if ('$policy' !== 'full') event.preventDefault();
  });
})();
</script></body></html>''';
}
