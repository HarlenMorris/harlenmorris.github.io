// ── Demo URLs ──
const GLPI_URL = 'https://glpi.harlenmorris.me';
const BOOKSTACK_URL = 'https://kb.harlenmorris.me';
const DASHBOARD_URL = 'https://dashboard.harlenmorris.me';

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
      // Close mobile menu when any nav link is clicked
      const navLinks = document.querySelector('.nav-links');
      if (navLinks) {
        navLinks.classList.remove('open');
      }
    }
  });
});

// ── Video Toggle Function ──
function toggleVideo(id) {
  const el = document.getElementById(id + '-video');
  if (!el) return;
  
  const isHidden = el.style.display === 'none' || !el.style.display;
  el.style.display = isHidden ? 'block' : 'none';
  
  if (isHidden) {
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    // Auto-play the video when shown
    const video = el.querySelector('video');
    if (video) {
      setTimeout(() => video.play(), 500);
    }
  } else {
    // Pause and reset when hidden
    const video = el.querySelector('video');
    if (video) {
      video.pause();
      video.currentTime = 0;
    }
  }
}

// ══════════════════════════════════════════
//  ANIMATED COUNTERS
// ══════════════════════════════════════════
const counterObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const el = entry.target;
      const target = parseInt(el.dataset.target);
      const suffix = el.dataset.suffix || '';
      const duration = 1500; // ms
      const start = performance.now();
      
      function update(now) {
        const elapsed = now - start;
        const progress = Math.min(elapsed / duration, 1);
        // Ease out cubic
        const eased = 1 - Math.pow(1 - progress, 3);
        const current = Math.round(eased * target);
        el.textContent = current.toLocaleString() + suffix;
        if (progress < 1) requestAnimationFrame(update);
      }
      requestAnimationFrame(update);
      counterObserver.unobserve(el);
    }
  });
}, { threshold: 0.5 });

document.querySelectorAll('.highlight-num').forEach(el => {
  // Parse the number and suffix from current text
  const text = el.textContent.trim();
  const match = text.match(/^([\d,]+)(.*)/);
  if (match) {
    el.dataset.target = match[1].replace(/,/g, '');
    el.dataset.suffix = match[2];
    el.textContent = '0' + match[2];
    counterObserver.observe(el);
  }
});

// ══════════════════════════════════════════
//  SCROLL REVEAL ANIMATIONS
// ══════════════════════════════════════════
const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('revealed');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });

// Add .reveal to section titles, demo cards, timeline items, skill groups
document.querySelectorAll('.section-title, .demo-hero, .showcase-item, .timeline-item, .skill-group, .contact-card, .article-card').forEach(el => {
  el.classList.add('reveal');
  revealObserver.observe(el);
});

// ══════════════════════════════════════════
//  DARK MODE TOGGLE
// ══════════════════════════════════════════
function toggleTheme() {
  const html = document.documentElement;
  const current = html.getAttribute('data-theme');
  const next = current === 'dark' ? 'light' : 'dark';
  html.setAttribute('data-theme', next);
  localStorage.setItem('theme', next);
  const icon = document.querySelector('.theme-icon');
  if (icon) icon.textContent = next === 'dark' ? '☀️' : '🌙';
}

// Load saved preference
(function() {
  const saved = localStorage.getItem('theme');
  if (saved === 'dark' || (!saved && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
    document.documentElement.setAttribute('data-theme', 'dark');
    const icon = document.querySelector('.theme-icon');
    if (icon) icon.textContent = '☀️';
  }
})();

// ── Fade-in on scroll (legacy — now using reveal classes above) ──
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

document.querySelectorAll('.highlight-card').forEach(el => {
  el.style.opacity = '0';
  el.style.transform = 'translateY(20px)';
  el.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
  fadeObserver.observe(el);
});
