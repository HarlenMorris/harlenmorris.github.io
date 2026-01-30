// ── Demo URLs (update these when hosting goes live) ──
const DEMO_URLS = {
  glpi: 'http://136.116.109.190',
  glpiAssets: 'http://136.116.109.190/front/computer.php',
};

// Wire up demo buttons
document.addEventListener('DOMContentLoaded', () => {
  const glpiLink = document.getElementById('glpi-link');
  const assetsLink = document.getElementById('glpi-assets-link');
  if (glpiLink) {
    glpiLink.href = DEMO_URLS.glpi;
    glpiLink.target = '_blank';
    glpiLink.rel = 'noopener noreferrer';
  }
  if (assetsLink) {
    assetsLink.href = DEMO_URLS.glpiAssets;
    assetsLink.target = '_blank';
    assetsLink.rel = 'noopener noreferrer';
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

document.querySelectorAll('.demo-card, .article-card, .timeline-item, .skill-group, .contact-card, .highlight-card').forEach(el => {
  el.style.opacity = '0';
  el.style.transform = 'translateY(20px)';
  el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
  observer.observe(el);
});
