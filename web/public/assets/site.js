const menuButton = document.querySelector('.menu-toggle');
const menu = document.querySelector('.main-nav');
menuButton?.addEventListener('click', () => {
  const open = menu.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(open));
  menuButton.setAttribute('aria-label', open ? '关闭导航' : '打开导航');
});
menu?.querySelectorAll('a').forEach(link => link.addEventListener('click', () => {
  menu.classList.remove('open');
  menuButton?.setAttribute('aria-expanded', 'false');
}));

const screens = {
  customer: ['01', '客户跟进', '客户跟进，清楚下一步', '在同一个视图里查看待联系客户、记录与下一次行动。'],
  orders: ['02', '订单执行', '每一笔订单都能追溯', '客户、工厂、产品与执行状态，在同一个地方查看。'],
  finance: ['03', '收款利润', '收款与费用心中有数', '逐笔记录收款与费用，根据录入信息汇总预计利润。'],
  tasks: ['04', '任务清单', '每一件待办，都有明确进度', '用清单、标签、日期、提醒与优先级安排每天的工作。'],
  calendar: ['05', '日历视图', '从日期看清工作安排', '月历集中呈现任务，也能按选定日期快速添加或调整安排。'],
  matrix: ['06', '四象限', '把重要的事放在前面', '按重要与紧急分区查看任务，并在象限中调整和处理待办。'],
  container: ['07', '装柜规划', '装柜方案提前预演', '分节安排货物和托盘，观察 3D 摆放及剩余空间。'],
};
const tabs = document.querySelectorAll('[data-screen]');
tabs.forEach(tab => tab.addEventListener('click', () => {
  const key = tab.dataset.screen;
  const [index, label, title, copy] = screens[key];
  tabs.forEach(item => {
    const selected = item === tab;
    item.classList.toggle('active', selected);
    item.setAttribute('aria-selected', String(selected));
  });
  const url = `/assets/screens/${key}.png`;
  document.querySelector('#gallery-image').src = url;
  document.querySelector('#gallery-image').alt = `Fly ${label}真实界面`;
  document.querySelector('#gallery-link').href = url;
  document.querySelector('#gallery-open').href = url;
  document.querySelector('#gallery-index').textContent = `${index} / 07`;
  document.querySelector('#gallery-window-title').textContent = `Fly · ${label}`;
  document.querySelector('#gallery-title').textContent = title;
  document.querySelector('#gallery-copy').textContent = copy;
}));

document.querySelector('.copy-token')?.addEventListener('click', async event => {
  const token = document.querySelector('.token-panel textarea')?.value;
  if (!token) return;
  try {
    await navigator.clipboard.writeText(token);
    event.currentTarget.textContent = '已复制';
  } catch {
    document.querySelector('.token-panel textarea')?.select();
    event.currentTarget.textContent = '请手动复制';
  }
});
