/* Homepage interactions. No tracking, app data, or payment requests. */
(function () {
  'use strict';
  // Public domains use the dedicated support host. Static previews stay navigable locally.
  if (!/(^|\.)flavorflow\.co\.in$/i.test(location.hostname)) {
    document.querySelectorAll('[data-support-link]').forEach(link => { link.href = '/support/'; });
  }
  const toggle = document.getElementById('menu-toggle');
  const navigation = document.getElementById('main-navigation');
  function setMenu(open) {
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    navigation.classList.toggle('open', open);
  }
  if (toggle && navigation) {
    toggle.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
    navigation.addEventListener('click', event => {
      if (event.target.closest('a')) setMenu(false);
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
        setMenu(false);
        toggle.focus();
      }
    });
    document.addEventListener('click', event => {
      if (!event.target.closest('.site-header')) setMenu(false);
    });
    window.matchMedia('(min-width: 1025px)').addEventListener('change', event => {
      if (event.matches) setMenu(false);
    });
  }
  const tabs = Array.from(document.querySelectorAll('.module-tab'));
  function selectTab(tab, focus) {
    tabs.forEach(item => {
      const selected = item === tab;
      item.classList.toggle('selected', selected);
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    });
    if (focus) tab.focus({preventScroll: true});
    tab.scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'instant'});
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab, false));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) {
        event.preventDefault();
        selectTab(tabs[next], true);
      }
    });
  });
  const tablist = document.querySelector('.module-tabs');
  if (tablist) {
    const mobileTabs = window.matchMedia('(max-width: 780px)');
    function updateOrientation() { tablist.setAttribute('aria-orientation', mobileTabs.matches ? 'horizontal' : 'vertical'); }
    updateOrientation();
    mobileTabs.addEventListener('change', updateOrientation);
  }
  const sectionLinks = Array.from(document.querySelectorAll('.section-navigation a'));
  if (sectionLinks.length && 'IntersectionObserver' in window) {
    const visible = new Map();
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => visible.set(entry.target.id, entry.isIntersecting));
      const active = sectionLinks.find(link => visible.get(link.hash.slice(1)));
      if (!active) return;
      sectionLinks.forEach(link => {
        link.classList.toggle('active', link === active);
        if (link === active) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }, {rootMargin: '-170px 0px -45% 0px', threshold: 0});
    sectionLinks.forEach(link => {
      const section = document.getElementById(link.hash.slice(1));
      if (section) observer.observe(section);
    });
  }
}());
