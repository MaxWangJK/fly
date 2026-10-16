import 'dart:convert';
import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../domain/fly_book.dart';

/// A book supplies content/styles, never executable code or network resources.
class FlyBookDocument {
  static const _tags = {
    'article',
    'main',
    'section',
    'aside',
    'header',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'p',
    'ul',
    'ol',
    'li',
    'strong',
    'b',
    'em',
    'i',
    'blockquote',
    'div',
    'span',
    'figure',
    'figcaption',
    'img',
    'table',
    'tbody',
    'thead',
    'tr',
    'th',
    'td',
    'hr',
    'br',
    'code',
    'pre',
    'a',
    'small',
    'mark',
  };

  static String _image(FlyBook book, String path) {
    final bytes = book.assets[path];
    if (!FlyBook.validAssetPath(path) || bytes == null || bytes.isEmpty) {
      throw const FormatException('Missing or unsafe book image');
    }
    final extension = path.split('.').last;
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'jpeg',
      _ => extension,
    };
    final valid = switch (mime) {
      'png' =>
        bytes.length >= 8 &&
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71,
      'jpeg' =>
        bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255,
      'gif' =>
        bytes.length >= 6 &&
            ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF',
      'webp' =>
        bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP',
      _ => false,
    };
    if (!valid) throw const FormatException('Invalid book image format');
    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  }

  static String _css(FlyBook book, String source) {
    if (RegExp(
      r'[<>\\]|@import|@font-face|expression\s*\(|javascript:|behavior\s*:|-moz-binding',
      caseSensitive: false,
    ).hasMatch(source)) {
      throw const FormatException('Unsafe book stylesheet');
    }
    return source.replaceAllMapped(
      RegExp(r'url\s*\(([^)]*)\)', caseSensitive: false),
      (match) {
        final path = match[1]!.trim().replaceAll(RegExp('^[\'"]|[\'"]\$'), '');
        return 'url("${_image(book, path)}")';
      },
    );
  }

  static String _body(FlyBook book, FlyBookChapter chapter) {
    final fragment = html.parseFragment(chapter.html);
    for (final element in fragment.querySelectorAll('*')) {
      if (!_tags.contains(element.localName)) {
        throw FormatException('Unsupported book element: ${element.localName}');
      }
      for (final name in element.attributes.keys.toList()) {
        if (!{
          'class',
          'id',
          'alt',
          'title',
          'src',
          'href',
          'style',
          'colspan',
          'rowspan',
        }.contains(name)) {
          throw const FormatException('Unsafe book attribute');
        }
      }
      if (element.attributes.containsKey('style')) {
        element.attributes['style'] = _css(book, element.attributes['style']!);
      }
      if (element.localName == 'img') {
        element.attributes['src'] = _image(
          book,
          element.attributes['src'] ?? '',
        );
        element.attributes['draggable'] = 'false';
      } else if (element.attributes.containsKey('src')) {
        throw const FormatException('Only images may load book resources');
      }
      if (element.localName == 'a') {
        final href = element.attributes.remove('href');
        if (href == null) continue;
        if (href.startsWith('#') &&
            RegExp(r'^#[a-zA-Z0-9_-]+$').hasMatch(href)) {
          element.attributes['href'] = href;
        } else if (href.startsWith('fly://book/') &&
            book.chapters.any((c) => href == 'fly://book/${c.id}')) {
          element.attributes['data-fly-href'] = href;
        } else {
          throw const FormatException(
            'Books only support internal chapter links',
          );
        }
      } else if (element.attributes.containsKey('href')) {
        throw const FormatException('Unsafe book navigation');
      }
    }
    return fragment.nodes
        .map(
          (node) => node is Element
              ? node.outerHtml
              : const HtmlEscape().convert(node.text ?? ''),
        )
        .join();
  }

  static void validate(FlyBook book) {
    _css(book, book.css);
    for (final asset in book.assets.keys) {
      _image(book, asset);
    }
    for (final chapter in book.chapters) {
      _body(book, chapter);
    }
  }

  static String render(
    FlyBook book,
    FlyBookChapter chapter, {
    double position = 0,
    bool dark = false,
  }) {
    final nonce = List.generate(
      20,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final initial = position.isFinite ? position.clamp(0.0, 1.0) : 0.0;
    return '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-$nonce'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
<style>${_css(book, book.css)}
html{scroll-behavior:auto}body{user-select:none;-webkit-user-select:none;overflow-wrap:anywhere}img{max-width:100%;height:auto;-webkit-user-drag:none}a{cursor:pointer}body.dark{--paper:#202620;--ink:#e7ebe5;--muted:#a9b4a6;--card:#2c332b;--line:#454e42}
</style></head><body class="${dark ? 'dark' : 'light'}">${_body(book, chapter)}
<script nonce="$nonce">(() => {
 let restored=false, scheduled=false;
 function send(value){const message=JSON.stringify(value);if(window.chrome?.webview)window.chrome.webview.postMessage(message);else window.FlyBridge?.postMessage(message);}
 function report(){scheduled=false;if(!restored)return;const range=document.documentElement.scrollHeight-innerHeight;const value=range<=1?1:Math.max(0,Math.min(1,scrollY/range));send({type:'progress',target:'${chapter.id}',value:value});}
 function restore(){if(restored)return;window.scrollTo(0,Math.max(0,document.documentElement.scrollHeight-innerHeight)*$initial);restored=true;report();}
 window.addEventListener('load',()=>setTimeout(restore,100));setTimeout(restore,1200);
 document.addEventListener('scroll',()=>{if(!scheduled){scheduled=true;setTimeout(report,250)}},{passive:true});
 document.addEventListener('click',event=>{const link=event.target.closest('a[data-fly-href]');if(link){event.preventDefault();send({type:'link',target:link.dataset.flyHref})}});
 document.addEventListener('contextmenu',event=>event.preventDefault());
 document.addEventListener('copy',event=>event.preventDefault());
 document.addEventListener('dragstart',event=>event.preventDefault());
 document.addEventListener('keydown',event=>{if(event.key==='F12'||((event.ctrlKey||event.metaKey)&&['s','p','u'].includes(event.key.toLowerCase())))event.preventDefault()});
 window.addEventListener('pagehide',report);
})();</script></body></html>''';
  }
}
