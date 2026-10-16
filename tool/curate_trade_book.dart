import 'dart:convert';
import 'dart:io';

import 'package:fly/features/knowledge/data/knowledge_markdown_compiler.dart';

/// Creates the first editorial draft. Later edits belong in book_sources.
Future<void> main() async {
  final root = Directory('book_sources/foreign_trade');
  final manifest = File('${root.path}/book.json');
  if (await manifest.exists()) {
    throw StateError(
      'Book draft already exists. Edit its HTML; do not overwrite it.',
    );
  }
  await Directory('${root.path}/chapters').create(recursive: true);
  final entries = <Map<String, Object>>[];
  Future<void> chapter(String id, String title, String body) async {
    final index = entries.length + 1;
    final html =
        '''<article><header class="chapter-header"><p class="eyebrow">FLY FIELD NOTES / ${(index).toString().padLeft(2, '0')}</p><h1>$title</h1></header>$body<footer class="chapter-footer">外贸工作手册 · 实践版 1.0 · 用事实判断，用行动推进</footer></article>''';
    await File('${root.path}/chapters/$id.html').writeAsString(html);
    entries.add({'id': id, 'title': title, 'file': 'chapters/$id.html'});
  }

  await chapter('reading-guide', '导读：把知识变成下一步', '''
<p class="lead">外贸工作并不缺信息。困难在于：面对一个具体客户，判断现在知道什么、缺什么，以及下一步应该做什么。</p>
<p>这本手册把现有外贸资料整理为一条可重复的工作路径：筛选线索，理解客户，开启沟通，确认需求，表达价值，推动样品与订单，再从结果中复盘。它不是一套让所有客户立刻成交的话术；同一句话在不同场景中可能需要完全不同的处理。</p>
<figure><img src="assets/journey.png" alt="客户旅程：了解、沟通、推进、复盘"><figcaption>把客户旅程当作持续循环，而不是发完报价就结束的单线流程。</figcaption></figure>
<h2>如何使用这本书</h2><ol><li>第一次阅读按目录顺序，建立完整的工作框架。</li><li>遇到具体问题时直接打开对应章节，先看适用场景，再检查当前事实。</li><li>把本章实践中的一个动作放入任务，而不是把整段文字当作结论。</li><li>完成动作后回到客户记录：实际发生了什么，哪些判断需要修改？</li></ol>
<aside class="fly-important"><strong>阅读约定</strong><p>书中的示例是为了说明沟通结构，不代表真实客户事实。只有确认过的规格、价格、交期和付款信息才能进入对外承诺。未知项应明确标为“待确认”。</p></aside>
<h2>阅读进度如何记录</h2><p>Fly 记录每章的最后位置和已浏览进度。重新打开可继续阅读；读完一章后，也可点击“标记本章已读”。阅读历史显示最近打开的章节。进度是帮助定位的工具，不替代理解和实践。</p>
<h2>三个始终有效的问题</h2><table><thead><tr><th>问题</th><th>工作中的用法</th></tr></thead><tbody><tr><td>依据是什么？</td><td>区分客户说过的话、可核实事实和自己的推测。</td></tr><tr><td>还缺什么？</td><td>用一个轻量问题补足关键条件，避免重复发送整套资料。</td></tr><tr><td>下一步是什么？</td><td>为动作安排负责人、时间和完成标准。</td></tr></tbody></table>
<p class="source-note">内容以工程内 14 篇原创外贸资料为基础，增加导读、原创流程图、实践任务和复盘工作表。未使用私人客户数据库、第三方课程原文或课程插图。</p>
''');
  const exercises = <String, String>{
    'sop-overview': '选一位正在跟进的客户，标出当前阶段、已完成动作、下一步负责人和日期。把“客户还在考虑”拆成具体的待确认问题。',
    'lead-screening':
        '从现有线索中选择三家公司，分别写出产品匹配证据、可能的采购场景和可触达联系人。先安排证据最充分的一位，不以公司规模代替匹配度。',
    'customer-background':
        '建立一张事实卡：公司网站、业务范围、联系人角色、已核实的联系方式和仍未确认的信息。对矛盾信息记录来源与核实日期，不凭一个截图作最终判断。',
    'first-contact':
        '写一段三句话的初次联系消息：为什么联系、可以提供的价值、一个容易回复的问题。发送前删掉无法证明的项目描述，只保留与对方有关的内容。',
    'before-quote':
        '将一份准备报价的需求分成“已确认”和“待确认”两栏。挑出影响价格或交付最多的一项，先向客户确认，再发送有清楚版本号的报价。',
    'product-value': '选择一个产品特点，写出对应使用场景、可能的优势和能够提供的证据。把“质量很好”改写为一条客户可以验证的具体说明。',
    'quote-followup':
        '回看最近一次报价，写出客户需要比较的条件、下一步决策人和一个尚未解决的问题。准备一条能够减少其决策负担的消息，而不是再问一次是否考虑好了。',
    'price-objection':
        '列出本次比较中的规格、数量、服务范围与交付条件。确认双方在比较同一条件后，准备两个真实可执行的调整方案，并写清各自的取舍。',
    'silent-customer':
        '把一位沉默客户的最后一次有效互动按日期整理。判断目前缺的是信息、时机还是优先级；设计一次有新价值的联系，并为停止无价值追问设一个明确界限。',
    'sample-progress':
        '为下一个样品建立验证卡：验证目的、样品规格、接收人、预计到达时间、反馈问题和下一步。只有客户知道如何判断结果，样品才真正进入决策过程。',
    'natural-order-nudge':
        '先写出客户尚未完成的决策动作，再判断自己能否提供支持。不要编造库存或排期压力；把真实的生产安排说明为有依据的选择条件。',
    'payment-followup':
        '检查已确认的订单编号、付款节点、金额币种和相关单据是否一致。准备简洁提醒，写明需对方核实的内容；付款账户发生变化时先按既定流程另行核实。',
    'lost-deal-review':
        '选择一笔未成交业务，分别写下可核实结果、自己的行动和推测原因。只选择一项下次可以改变的动作，并安排具体的验证方法。',
    'reactivate-customer':
        '从旧客户中挑一位有实际匹配机会的人，写清本次出现的新价值以及为何与其有关。不要把旧订单推断成当前需求，用一条轻量问题确认是否值得继续。',
  };
  final catalog = jsonDecode(
    await File('assets/knowledge/seed/catalog.json').readAsString(),
  ) as Map<String, dynamic>;
  final compiler = KnowledgeMarkdownCompiler();
  for (final name in (catalog['articles'] as List).cast<String>()) {
    final source = KnowledgeSource.parse(
      await File('assets/knowledge/seed/$name').readAsString(),
    );
    final id = source.frontMatter['id']!;
    var markdown = source.body
        .split('\n')
        .where((line) => !line.startsWith('插图位：'))
        .join('\n');

    var html = compiler.compile(markdown).bodyHtml;
    html = html.replaceFirst(RegExp(r'<h1>.*?</h1>', dotAll: true), '');
    html = html.replaceAllMapped(
      RegExp(r'<a href="#" data-fly-href="([^"]+)">'),
      (match) =>
          '<a href="${match[1]!.replaceAll('fly://knowledge/', 'fly://book/')}">',
    );
    final diagram = ['lead-screening', 'customer-background'].contains(id)
        ? 'facts'
        : [
            'sample-progress',
            'payment-followup',
            'lost-deal-review',
          ].contains(id)
        ? 'review'
        : 'journey';
    await chapter(id, source.frontMatter['title']!, '''
<p class="lead">${const HtmlEscape().convert(source.frontMatter['summary'] ?? '')}</p>
<div class="chapter-intro"><strong>本章要带走的能力</strong><p>${exercises[id]}</p></div>
$html
<figure><img src="assets/$diagram.png" alt="本章原创工作流程图"><figcaption>将判断与动作连起来。图中的步骤需要根据当前客户事实使用。</figcaption></figure>
<aside class="practice"><h2>本章实践</h2><p>${exercises[id]}</p><ol><li>写出目前能够确认的一条事实。</li><li>写出最值得补充的一条信息。</li><li>安排一个有日期的动作，定义什么结果算完成。</li></ol></aside>
<h2>把动作记入工作台</h2><table><tbody><tr><th>客户记录</th><td>保存本次确认的信息和来源，不把推测写成事实。</td></tr><tr><th>任务清单</th><td>用动词描述下一步，设定日期，并关联当前客户或订单。</td></tr><tr><th>复盘</th><td>回看实际结果；若假设被推翻，更新判断并调整动作。</td></tr></tbody></table>
<p class="source-note">本章根据现有原创资料整理；示例沟通不应被不加判断地批量发送。</p>
''');
  }
  await chapter('practice-workbook', '工作表：让每周工作形成闭环', '''
<p class="lead">学完一章后，不必增加更多记录负担。让已有的客户、订单和任务记录能够回答“现在在哪里，下一步做什么”。</p>
<figure><img src="assets/review.png" alt="每周复盘循环：事实、判断、行动、结果"><figcaption>重复的是判断过程，而不是对所有客户重复同一句话。</figcaption></figure>
<h2>一张客户推进卡</h2><table><thead><tr><th>字段</th><th>填写提示</th></tr></thead><tbody><tr><td>当前阶段</td><td>首次联系、需求确认、报价、样品、决策或执行，选择最接近实际情况的一项。</td></tr><tr><td>已确认事实</td><td>注明谁在什么日期确认了什么，必要时关联相应文件。</td></tr><tr><td>主要未知项</td><td>只保留会影响当前下一步的关键信息。</td></tr><tr><td>下一步动作</td><td>负责人、日期、输出结果；把“跟进客户”写得更具体。</td></tr><tr><td>停止或调整条件</td><td>如果目标、时间或业务匹配已改变，重新评估，而不是机械继续发送。</td></tr></tbody></table>
<h2>每周三十分钟复盘</h2><ol><li><strong>先看事实。</strong>本周完成了哪些联系、确认或交付？哪些事项只是等待，尚无结果？</li><li><strong>挑一处障碍。</strong>选择一件最影响推进的事情，区分客户条件和自己的行动。</li><li><strong>调整一个动作。</strong>只改变一个能够验证的沟通或执行步骤，避免一次修改全部流程后无法判断效果。</li><li><strong>安排下一周。</strong>明确最重要的成果，为关键动作安排可执行的时间。</li></ol>
<aside class="fly-tip"><strong>写给自己的提醒</strong><p>联系次数、发送附件数量和记录长度不是结果本身。更有价值的问题是：你是否理解了客户需求，减少了一个决策障碍，或者可靠地完成了一项已经确认的承诺？</p></aside>
<h2>资料与版本管理</h2><p>报价、规格和样品反馈应保存可辨识的版本与日期。订单进入执行后，保持文件、确认记录和下一步安排之间的关联。不要因为换设备或更换工作方式而丢失原记录；备份与同步承担不同任务，应定期确认恢复是否可用。</p>
<h2>下次打开这本书</h2><p>从阅读历史回到上次的章节，或者从目录直接找到当前问题。若发现某条做法不适合自己的市场或产品，把它作为需要验证的假设。经验值得积累，也值得重新检查。</p>
<p class="source-note">本手册提供业务组织与沟通实践，不替代具体交易中的专业合同、财税、产品合规或运输意见。涉及具体承诺时以核实后的业务文件和适用要求为准。</p>
''');
  await manifest.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'id': 'fly-trade-fieldbook',
      'title': '外贸工作手册：从客户开发到订单复盘',
      'author': 'Fly 编辑部',
      'version': 1,
      'description':
          '把现有外贸资料整理为可实践的客户工作路径。16 章涵盖线索、沟通、报价、样品、付款提醒、输单与复购，附原创流程图和实践清单。',
      'stylesheet': 'styles/book.css',
      'chapters': entries,
    }),
  );
  stdout.writeln(
    'Created an editable ${entries.length}-chapter first draft under ${root.path}.',
  );
}
