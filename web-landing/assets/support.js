/* Static help search. No API calls, tracking, ticket submission or email sending. */
(function () {
  'use strict';
  const articles = Array.from(document.querySelectorAll('.help-article'));
  const input = document.getElementById('help-search-input');
  const search = document.querySelector('.help-search');
  const summary = document.querySelector('.search-summary');
  const empty = document.querySelector('.no-results');
  const library = document.getElementById('help-library');
  const categoryButtons = Array.from(document.querySelectorAll('[data-category]'));
  const filters = Array.from(document.querySelectorAll('[data-filter]'));
  let category = 'all';
  const normalize = text => text.toLocaleLowerCase('en').normalize('NFKC').replace(/[’']/g, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const index = articles.map(article => ({article, tokens: normalize(article.textContent + ' ' + article.dataset.keywords).split(' ')}));
  function update() {
    const query = input.value.trim();
    const words = normalize(query).split(' ').filter(Boolean);
    let count = 0;
    index.forEach(({article, tokens}) => {
      const visible = (category === 'all' || article.dataset.topic === category) && words.every(word => tokens.some(token => token.startsWith(word)));
      article.hidden = !visible;
      if (visible) count++;
    });
    filters.forEach(button => {
      const selected = button.dataset.filter === category;
      button.classList.toggle('active', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
    categoryButtons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.category === category)));
    const title = category === 'all' ? 'all topics' : filters.find(button => button.dataset.filter === category).textContent;
    summary.textContent = count + ' help article' + (count === 1 ? '' : 's') + ' · ' + title + (query ? ' · “' + query + '”' : '');
    empty.hidden = count > 0;
  }
  function scrollToResults() {
    library.scrollIntoView({block: 'start', behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
  }
  search.addEventListener('submit', event => { event.preventDefault(); update(); scrollToResults(); });
  input.addEventListener('input', update);
  categoryButtons.forEach(button => button.addEventListener('click', () => {
    category = button.dataset.category;
    input.value = '';
    update();
    scrollToResults();
  }));
  filters.forEach(button => button.addEventListener('click', () => { category = button.dataset.filter; update(); }));
  document.querySelectorAll('[data-query]').forEach(button => button.addEventListener('click', () => {
    category = 'all';
    input.value = button.dataset.query;
    update();
    scrollToResults();
  }));
  document.querySelectorAll('.clear-search').forEach(button => button.addEventListener('click', () => {
    input.value = '';
    category = 'all';
    update();
  }));
  function openLinkedArticle() {
    let id;
    try { id = decodeURIComponent(location.hash.slice(1)); } catch (_) { return; }
    const article = document.getElementById(id);
    if (!article || !article.classList.contains('help-article')) return;
    input.value = '';
    category = 'all';
    update();
    article.open = true;
    article.scrollIntoView({block: 'start', behavior: 'instant'});
  }
  window.addEventListener('hashchange', openLinkedArticle);
  update();
  openLinkedArticle();
}());
