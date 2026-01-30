// ── Demo URL ──
const GLPI_URL = 'http://136.116.109.190';

// Wire up demo button
document.addEventListener('DOMContentLoaded', () => {
  const glpiLink = document.getElementById('glpi-link');
  if (glpiLink) {
    glpiLink.href = GLPI_URL;
    glpiLink.target = '_blank';
    glpiLink.rel = 'noopener noreferrer';
  }
});

// ── Smooth scroll for nav links ──
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', e => {
    const target = document.querySelector(anchor.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      // Close mobile menu if open
      document.querySelector('.nav-links')?.classList.remove('open');
    }
  });
});

// ── Nav background on scroll ──
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.style.boxShadow = window.scrollY > 20
    ? '0 2px 12px rgba(0,0,0,0.08)'
    : 'none';
});

// ── Fade-in on scroll ──
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.style.opacity = '1';
        entry.target.style.transform = 'translateY(0)';
      }
    });
  },
  { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
);

document.querySelectorAll('.demo-hero, .showcase-item, .article-card, .timeline-item, .skill-group, .contact-card, .highlight-card').forEach(el => {
  el.style.opacity = '0';
  el.style.transform = 'translateY(20px)';
  el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
  observer.observe(el);
});
