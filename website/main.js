const products = {
  word: { kicker: '文字 / WRITE', title: '从容落笔，<br>让表达更有力量。', description: '从日常记录到正式报告，在熟悉的编辑界面中整理思路、调整排版，完成每一份用心的文档。', file: '项目方案.docx', label: 'PROJECT PROPOSAL', heading: '每一个想法，都有新的可能', subtitle: '项目计划与工作安排', content: '<h5>01 &nbsp; 明确方向，专注重要的事</h5><p>用清晰的结构梳理思路，用简洁的表达传递价值。</p><div class="fake-lines"><i></i><i></i><i></i></div><h5>02 &nbsp; 从想法，到行动</h5><div class="fake-lines"><i></i><i></i></div>' },
  sheet: { kicker: '表格 / ORGANIZE', title: '整理每一列数据，<br>看清每一步进展。', description: '用表格记录数据、梳理计划，通过公式计算和图表呈现，让日常工作有条不紊。', file: '工作计划.xlsx', label: 'WORK PLAN', heading: '让每一步进展，清晰可见', subtitle: '示例工作表', content: '<table style="width:100%;border-collapse:collapse;font-size:10px;color:#7c738e"><tr style="background:#f0edf8"><th style="padding:8px">事项</th><th>计划</th><th>状态</th></tr><tr><td style="padding:9px;border-bottom:1px solid #eee">资料整理</td><td>周一</td><td>已完成</td></tr><tr><td style="padding:9px;border-bottom:1px solid #eee">方案编写</td><td>周三</td><td>进行中</td></tr><tr><td style="padding:9px">成果汇报</td><td>周五</td><td>待开始</td></tr></table>' },
  slide: { kicker: '演示 / PRESENT', title: '让重要的想法，<br>拥有出色的开场。', description: '整理大纲、设计页面、组织演示，把内容与视觉放在一起，让每一场表达更有条理。', file: '项目汇报.pptx', label: 'PRESENT YOUR IDEAS', heading: '好的想法，值得被看见', subtitle: '项目成果汇报 · 示例演示', content: '<div style="display:flex;gap:12px;margin-top:24px"><div style="background:#eee8fa;color:#8f78b8;padding:20px 12px;border-radius:8px;flex:1">01<br>发现问题</div><div style="background:#ebeefb;color:#788bb8;padding:20px 12px;border-radius:8px;flex:1">02<br>梳理方案</div><div style="background:#e8f2ef;color:#78a894;padding:20px 12px;border-radius:8px;flex:1">03<br>推进落地</div></div>' },
  pdf: { kicker: 'PDF / REVIEW', title: '从阅读到编辑，<br>让文档顺畅流转。', description: '在同一工作空间中阅读 PDF、编辑内容、添加批注和图章，再保存你的修改，让文档交付更从容。', file: '文档评审.pdf', label: 'DOCUMENT REVIEW', heading: '每一次修改，都让文档更好', subtitle: '文档评审与交付 · 示例页面', content: '<h5>文档评审要点</h5><div class="fake-lines"><i></i><i></i><i></i></div><p style="margin-top:20px;background:#fff7db;padding:12px;border-left:3px solid #e9d283">批注：请补充这一部分的说明。</p><div style="margin-top:18px;color:#8c7cba;font-size:11px;text-align:right">✓ 已完成评审</div>' }
};
const tabs = [...document.querySelectorAll('[data-product]')];
function selectProduct(tab) {
  const product = products[tab.dataset.product];
  tabs.forEach(item => { const selected = item === tab; item.classList.toggle('active', selected); item.setAttribute('aria-selected', String(selected)); item.tabIndex = selected ? 0 : -1; });
  document.querySelector('#product-panel').setAttribute('aria-labelledby', tab.id);
  document.querySelector('#product-kicker').textContent = product.kicker;
  document.querySelector('#product-title').innerHTML = product.title;
  document.querySelector('#product-description').textContent = product.description;
  document.querySelector('#demo-file').textContent = product.file;
  document.querySelector('#demo-label').textContent = product.label;
  document.querySelector('#demo-title').textContent = product.heading;
  document.querySelector('#demo-subtitle').textContent = product.subtitle;
  document.querySelector('#demo-content').innerHTML = product.content;
  document.querySelector('#feature-demo').dataset.kind = tab.dataset.product;
}
tabs.forEach((tab, index) => {
  tab.tabIndex = index === 0 ? 0 : -1;
  tab.addEventListener('click', () => selectProduct(tab));
  tab.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
    tabs[next].focus(); selectProduct(tabs[next]);
  });
});
let toastTimer;
document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
  const toast = document.querySelector('.toast');
  try { await navigator.clipboard.writeText(button.dataset.copy); toast.textContent = '提取码 gxcx 已复制'; }
  catch { toast.textContent = '提取码：gxcx，请手动复制'; }
  toast.classList.add('visible'); clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 2400);
}));
