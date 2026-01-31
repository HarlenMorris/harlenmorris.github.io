// ── Demo URLs ──
const GLPI_URL = 'http://136.116.109.190';
const BOOKSTACK_URL = 'http://136.116.109.190:8080';
const DASHBOARD_URL = 'http://136.116.109.190:8085';

document.addEventListener('DOMContentLoaded', () => {

  // ── Wire up demo button ──
  const glpiLink = document.getElementById('glpi-link');
  if (glpiLink) {
    glpiLink.href = GLPI_URL;
    glpiLink.target = '_blank';
    glpiLink.rel = 'noopener noreferrer';
  }

  // ── Wire up BookStack demo button ──
  const bookstackLink = document.getElementById('bookstack-link');
  if (bookstackLink) {
    bookstackLink.href = BOOKSTACK_URL;
    bookstackLink.target = '_blank';
    bookstackLink.rel = 'noopener noreferrer';
  }

  // ── Wire up Dashboard demo button ──
  const dashboardLink = document.getElementById('dashboard-link');
  if (dashboardLink) {
    dashboardLink.href = DASHBOARD_URL;
    dashboardLink.target = '_blank';
    dashboardLink.rel = 'noopener noreferrer';
  }

  // ══════════════════════════════════════════
  //  IMAGE LIGHTBOX
  // ══════════════════════════════════════════
  const lightbox = document.createElement('div');
  lightbox.className = 'lightbox';
  lightbox.innerHTML = `
    <button class="lb-close" aria-label="Close">&times;</button>
    <button class="lb-prev" aria-label="Previous">&#8249;</button>
    <button class="lb-next" aria-label="Next">&#8250;</button>
    <img class="lb-img" src="" alt="">
    <p class="lb-caption"></p>
    <span class="lb-counter"></span>
  `;
  document.body.appendChild(lightbox);

  const lbImg = lightbox.querySelector('.lb-img');
  const lbCaption = lightbox.querySelector('.lb-caption');
  const lbCounter = lightbox.querySelector('.lb-counter');
  const lbClose = lightbox.querySelector('.lb-close');
  const lbPrev = lightbox.querySelector('.lb-prev');
  const lbNext = lightbox.querySelector('.lb-next');

  // Gather all clickable images
  const allImages = Array.from(document.querySelectorAll('.demo-img, .showcase-img'));
  let currentIdx = 0;

  function openLightbox(idx) {
    currentIdx = idx;
    const img = allImages[idx];
    lbImg.src = img.src;
    lbCaption.textContent = img.alt || '';
    lbCounter.textContent = `${idx + 1} / ${allImages.length}`;
    lightbox.classList.add('lb-open');
    document.body.style.overflow = 'hidden';
    // Show/hide arrows
    lbPrev.style.display = allImages.length > 1 ? '' : 'none';
    lbNext.style.display = allImages.length > 1 ? '' : 'none';
  }

  function closeLightbox() {
    lightbox.classList.remove('lb-open');
    document.body.style.overflow = '';
  }

  function navigate(dir) {
    currentIdx = (currentIdx + dir + allImages.length) % allImages.length;
    const img = allImages[currentIdx];
    lbImg.style.opacity = '0';
    setTimeout(() => {
      lbImg.src = img.src;
      lbCaption.textContent = img.alt || '';
      lbCounter.textContent = `${currentIdx + 1} / ${allImages.length}`;
      lbImg.style.opacity = '1';
    }, 150);
  }

  allImages.forEach((img, i) => {
    img.style.cursor = 'zoom-in';
    img.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      openLightbox(i);
    });
  });

  lbClose.addEventListener('click', closeLightbox);
  lbPrev.addEventListener('click', () => navigate(-1));
  lbNext.addEventListener('click', () => navigate(1));
  lightbox.addEventListener('click', (e) => {
    if (e.target === lightbox) closeLightbox();
  });

  // Keyboard controls
  document.addEventListener('keydown', (e) => {
    if (!lightbox.classList.contains('lb-open')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') navigate(-1);
    if (e.key === 'ArrowRight') navigate(1);
  });

  // Swipe support for mobile
  let touchStartX = 0;
  lightbox.addEventListener('touchstart', (e) => {
    touchStartX = e.changedTouches[0].screenX;
  }, { passive: true });
  lightbox.addEventListener('touchend', (e) => {
    const diff = e.changedTouches[0].screenX - touchStartX;
    if (Math.abs(diff) > 50) {
      navigate(diff > 0 ? -1 : 1);
    }
  }, { passive: true });

  // ══════════════════════════════════════════
  //  BACK-TO-TOP BUTTON
  // ══════════════════════════════════════════
  const topBtn = document.createElement('button');
  topBtn.className = 'back-to-top';
  topBtn.setAttribute('aria-label', 'Back to top');
  topBtn.innerHTML = '↑';
  document.body.appendChild(topBtn);

  topBtn.addEventListener('click', () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  // ══════════════════════════════════════════
  //  ACTIVE NAV HIGHLIGHTING (scroll spy)
  // ══════════════════════════════════════════
  const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');
  const sections = Array.from(navLinks).map(link => {
    const id = link.getAttribute('href').slice(1);
    return { link, el: document.getElementById(id) };
  }).filter(s => s.el);

  function updateActiveNav() {
    const scrollY = window.scrollY + 120;
    let active = sections[0];
    for (const s of sections) {
      if (s.el.offsetTop <= scrollY) active = s;
    }
    navLinks.forEach(l => l.classList.remove('nav-active'));
    if (active) active.link.classList.add('nav-active');

    // Back-to-top visibility
    topBtn.classList.toggle('visible', window.scrollY > 400);
  }

  // ── Scroll handler (throttled) ──
  let ticking = false;
  window.addEventListener('scroll', () => {
    if (!ticking) {
      requestAnimationFrame(() => {
        // Nav shadow
        const nav = document.getElementById('nav');
        nav.style.boxShadow = window.scrollY > 20
          ? '0 2px 12px rgba(0,0,0,0.08)'
          : 'none';

        updateActiveNav();
        ticking = false;
      });
      ticking = true;
    }
  });

  updateActiveNav();
});

// ── Smooth scroll for nav links ──
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
  anchor.addEventListener('click', e => {
    const target = document.querySelector(anchor.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      document.querySelector('.nav-links')?.classList.remove('open');
    }
  });
});

// ── Fade-in on scroll ──
const fadeObserver = new IntersectionObserver(
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
  fadeObserver.observe(el);
});
