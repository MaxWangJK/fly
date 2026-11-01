enum ReviewProgram { classic, guided }

/// Separate answer keys keep both programs in the existing synced daily record.
/// Basic q1–q11 answers are never repurposed by the guided program.
abstract final class GuidedReview {
  static const progress = 'flight.v1.progress';
  static const facts = 'flight.v1.facts';
  static const insight = 'flight.v1.insight';
  static const experiment = 'flight.v1.experiment';
  static const signal = 'flight.v1.signal';
  static const lens = 'flight.v1.lens';
  static const energy = 'flight.v1.energy';
  static const outcome = 'flight.v1.outcome';
  static const revisit = 'flight.v1.revisit';
  static const revisitDay = 'flight.v1.revisit_day';
  static const taskId = 'flight.v1.task_id';
  static const closed = 'flight.v1.closed';
  static const keep = 'flight.v1.week_keep';
  static const adjust = 'flight.v1.week_adjust';
  static const direction = 'flight.v1.week_direction';
  static const core = [progress, facts, insight, experiment, signal];
  static const visibleFields = {
    ...core,
    lens,
    energy,
    outcome,
    revisit,
    keep,
    adjust,
    direction,
  };
  static const fields = {...visibleFields, revisitDay, taskId, closed};
  static int completed(Map<String, String> answers) =>
      core.where((key) => answers[key]?.trim().isNotEmpty ?? false).length;
}

class ReviewPrompt {
  const ReviewPrompt(this.id, this.zh, this.en, this.hintZh, this.hintEn);
  final String id, zh, en, hintZh, hintEn;
}

const guidedPrompts = [
  ReviewPrompt(
    GuidedReview.progress,
    '留下一个真实进展',
    'Keep one real win',
    '哪件小事值得保留？写下具体变化，不用证明今天足够忙。',
    'What changed for the better? Keep it concrete; being busy is not the goal.',
  ),
  ReviewPrompt(
    GuidedReview.facts,
    '看清一次偏差',
    'Notice a gap',
    '原本期待什么，实际发生什么？先写看得见的事实，暂时不评价自己。',
    'What did you expect, and what actually happened? Start with evidence, without judging yourself.',
  ),
  ReviewPrompt(
    GuidedReview.insight,
    '找到可以改变的一环',
    'Find your next lever',
    '哪些在你控制之内？区分已知原因与猜测，也留意精力、方法和沟通。',
    'What can you influence? Separate evidence from assumptions; consider energy, method and communication.',
  ),
  ReviewPrompt(
    GuidedReview.experiment,
    '安排一个小实验',
    'Choose one small experiment',
    '明天在什么场景，做哪个具体动作？一次只改一件事，十分钟也可以。',
    'In what situation tomorrow will you do one specific thing? Ten minutes is enough.',
  ),
  ReviewPrompt(
    GuidedReview.signal,
    '约定一个回看信号',
    'Decide what to look for',
    '什么时候回看，看到什么变化就算有帮助？结果未知也值得记录。',
    'When will you revisit this, and what change would help? An uncertain result is still useful.',
  ),
];

const weeklyPrompts = [
  ReviewPrompt(
    GuidedReview.keep,
    '继续做什么',
    'What will you keep?',
    '从过去七天挑一个有证据支持的做法，把它留下。',
    'Keep one practice that the last seven days give you evidence for.',
  ),
  ReviewPrompt(
    GuidedReview.adjust,
    '停止或调整什么',
    'What will you change?',
    '哪个阻力反复出现？换一种方法，或为自己减掉一件事。',
    'What friction keeps returning? Change the method, or remove a commitment.',
  ),
  ReviewPrompt(
    GuidedReview.direction,
    '下一程只聚焦一件事',
    'One focus for the next stretch',
    '下一周，哪件事最值得你的时间？写出可以判断的进展。',
    'What most deserves your attention next week? Describe observable progress.',
  ),
];
