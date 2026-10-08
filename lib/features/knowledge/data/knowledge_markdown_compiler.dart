import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as markdown;

import '../domain/knowledge_models.dart';

class KnowledgeSource {
  const KnowledgeSource(this.frontMatter, this.body);
  final Map<String, String> frontMatter;
  final String body;

  static KnowledgeSource parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('Knowledge article requires front matter');
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end < 0) throw const FormatException('Unclosed front matter');
    final fields = <String, String>{};
    for (final line in normalized.substring(4, end).split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (fields.containsKey(key)) throw FormatException('Duplicate $key');
      fields[key] = value;
    }
    for (final key in ['id', 'title', 'category', 'slug']) {
      if (fields[key]?.isNotEmpty != true) {
        throw FormatException('Missing article $key');
      }
    }
    return KnowledgeSource(fields, normalized.substring(end + 5).trim());
  }
}

class KnowledgeOutlineEntry {
  const KnowledgeOutlineEntry(this.id, this.label, this.level);
  final String id;
  final String label;
  final int level;
}

class KnowledgeRenderedArticle {
  const KnowledgeRenderedArticle({
    required this.bodyHtml,
    required this.plainText,
    required this.outline,
    required this.copyableSnippets,
  });
  final String bodyHtml;
  final String plainText;
  final List<KnowledgeOutlineEntry> outline;
  final List<String> copyableSnippets;
}

/// Pack Markdown is never trusted as HTML. Only a small semantic subset survives.
class KnowledgeMarkdownCompiler {
  static const allowedDirectives = {
    'tip',
    'important',
    'warning',
    'example',
    'script',
    'steps',
    'copyable',
  };
  static const _allowedTags = {
    'h1',
    'h2',
    'h3',
    'h4',
    'p',
    'ul',
    'ol',
    'li',
    'strong',
    'em',
    'del',
    'a',
    'img',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'code',
    'pre',
    'blockquote',
    'hr',
    'br',
    'div',
    'span',
  };

  KnowledgeRenderedArticle compile(
    String markdownBody, {
    Map<String, List<int>> assets = const {},
  }) {
    final directives = <String, String>{};
    final snippets = <String>[];
    final lines = markdownBody.replaceAll('\r\n', '\n').split('\n');
    final processed = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(r'^:::(\w+)\s*$').firstMatch(lines[index]);
      if (match == null) {
        processed.add(lines[index]);
        continue;
      }
      final type = match.group(1)!;
      if (!allowedDirectives.contains(type)) {
        throw FormatException('Unsupported knowledge directive: $type');
      }
      final content = <String>[];
      var closed = false;
      while (++index < lines.length) {
        if (lines[index].trim() == ':::') {
          closed = true;
          break;
        }
        content.add(lines[index]);
      }
      if (!closed) throw FormatException('Unclosed $type directive');
      final inner = _sanitize(
        markdown.markdownToHtml(
          content.join('\n'),
          extensionSet: markdown.ExtensionSet.gitHubFlavored,
          enableTagfilter: true,
        ),
        assets,
      );
      final token = 'FLYDIRECTIVE${directives.length}END';
      directives[token] = '<section class="fly-$type">$inner</section>';
      if (type == 'copyable') snippets.add(content.join('\n').trim());
      processed.add('');
      processed.add(token);
      processed.add('');
    }
    var body = _sanitize(
      markdown.markdownToHtml(
        processed.join('\n'),
        extensionSet: markdown.ExtensionSet.gitHubFlavored,
        enableTagfilter: true,
      ),
      assets,
    );
    for (final directive in directives.entries) {
      body = body.replaceAll('<p>${directive.key}</p>', directive.value);
    }
    final document = html.parseFragment(body);
    final outline = <KnowledgeOutlineEntry>[];
    var headingIndex = 0;
    for (final heading in document.querySelectorAll('h2, h3')) {
      final id = 'section-${++headingIndex}';
      heading.attributes['id'] = id;
      outline.add(
        KnowledgeOutlineEntry(
          id,
          heading.text.trim(),
          heading.localName == 'h2' ? 2 : 3,
        ),
      );
    }
    final plainText = (document.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return KnowledgeRenderedArticle(
      bodyHtml: document.nodes
          .map(
            (node) => switch (node) {
              dom.Element element => element.outerHtml,
              dom.Text text => const HtmlEscape().convert(text.text),
              _ => '',
            },
          )
          .join(),
      plainText: plainText,
      outline: outline,
      copyableSnippets: snippets,
    );
  }

  String _sanitize(String unsafe, Map<String, List<int>> assets) {
    final parsed = html.parseFragment(unsafe);
    final output = StringBuffer();
    for (final node in parsed.nodes) {
      _writeNode(output, node, assets);
    }
    return output.toString();
  }

  void _writeNode(
    StringBuffer out,
    dom.Node node,
    Map<String, List<int>> assets,
  ) {
    if (node is dom.Text) {
      out.write(const HtmlEscape().convert(node.text));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (!_allowedTags.contains(tag)) {
      for (final child in node.nodes) {
        _writeNode(out, child, assets);
      }
      return;
    }
    if (tag == 'img') {
      final source = node.attributes['src'] ?? '';
      final bytes = assets[source];
      if (!source.startsWith('assets/') ||
          source.contains('..') ||
          bytes == null ||
          bytes.length > 8 * 1024 * 1024) {
        return;
      }
      final mime = source.toLowerCase().endsWith('.png')
          ? 'image/png'
          : source.toLowerCase().endsWith('.webp')
          ? 'image/webp'
          : source.toLowerCase().endsWith('.jpg') ||
                source.toLowerCase().endsWith('.jpeg')
          ? 'image/jpeg'
          : null;
      if (mime == null) return;
      out.write('<img src="data:$mime;base64,${base64Encode(bytes)}"');
      out.write(
        ' alt="${const HtmlEscape().convert(node.attributes['alt'] ?? '')}">',
      );
      return;
    }
    if (tag == 'a') {
      final href = node.attributes['href'] ?? '';
      final uri = Uri.tryParse(href);
      final safe =
          uri != null &&
          ((uri.scheme == 'https' && uri.host.isNotEmpty) ||
              (uri.scheme == 'fly' &&
                  uri.host == 'knowledge' &&
                  uri.pathSegments.length == 1));
      if (!safe) {
        for (final child in node.nodes) {
          _writeNode(out, child, assets);
        }
        return;
      }
      // Never give the WebView a navigable external URL. The trusted viewer
      // bridge handles validated targets; without the bridge a click stays put.
      out.write(
        '<a href="#" data-fly-href="${const HtmlEscape().convert(href)}">',
      );
    } else {
      out.write('<$tag>');
    }
    for (final child in node.nodes) {
      _writeNode(out, child, assets);
    }
    if (!{'hr', 'br'}.contains(tag)) out.write('</$tag>');
  }
}

KnowledgeCopyPolicy parseCopyPolicy(String? value) =>
    KnowledgeCopyPolicy.values.byName(value ?? 'none');

KnowledgeAccessLevel parseAccessLevel(String? value) =>
    KnowledgeAccessLevel.values.byName(value ?? 'free');
